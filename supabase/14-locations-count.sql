-- 14) Shelf locations and the full stock count (جرد شامل).
-- Safe to run more than once. Run after files 1–13.
--
-- Shelf address = area-aisle-unit-level, e.g. D-B-04-2
--   area  S = المعرض, D = المستودع, U = السدة
--   aisle A, B, C … (as the aisles are walked from the door)
--   unit  01, 02 … (shelving unit along the aisle)
--   level 1, 2 … (shelf counted from the floor)

-- ---------- aisles (the shelves are generated from them) ----------
create table if not exists public.inv_aisles (
  id bigint generated always as identity primary key,
  area text not null check (area in ('S','D','U')),
  aisle text not null check (aisle ~ '^[A-Z]{1,2}$'),
  units int not null check (units between 1 and 99),
  levels int not null check (levels between 1 and 9),
  note text,
  created_at timestamptz not null default now(),
  unique (area, aisle)
);

-- an item's home shelf and its overflow shelf (spare cartons)
alter table public.inv_items add column if not exists loc text;
alter table public.inv_items add column if not exists loc2 text;
create index if not exists inv_items_loc_idx on public.inv_items (loc);
create index if not exists inv_items_loc2_idx on public.inv_items (loc2);

create or replace function public.inv_loc_ok(l text) returns boolean
language sql stable security definer set search_path = public as $$
  select l is null or exists (
    select 1 from inv_aisles a
     where l ~ '^[SDU]-[A-Z]{1,2}-[0-9]{2}-[1-9]$'
       and a.area = split_part(l, '-', 1) and a.aisle = split_part(l, '-', 2)
       and split_part(l, '-', 3)::int between 1 and a.units
       and split_part(l, '-', 4)::int between 1 and a.levels);
$$;

-- ---------- count sessions ----------
create table if not exists public.inv_count_sessions (
  id bigint generated always as identity primary key,
  name text not null,
  kind text not null default 'full' check (kind in ('full','partial')),
  status text not null default 'open' check (status in ('open','closed','cancelled')),
  started_at timestamptz not null default now(),
  started_by uuid default auth.uid(),
  closed_at timestamptz,
  closed_by uuid,
  result jsonb
);
create unique index if not exists inv_count_one_open on public.inv_count_sessions ((status)) where status = 'open';

create table if not exists public.inv_count_zones (
  session_id bigint not null references public.inv_count_sessions(id) on delete cascade,
  area text not null,
  aisle text not null,
  team text,
  status text not null default 'todo' check (status in ('todo','counting','done','recount')),
  by_name text,
  updated_at timestamptz not null default now(),
  primary key (session_id, area, aisle)
);

create table if not exists public.inv_count_lines (
  id bigint generated always as identity primary key,
  session_id bigint not null references public.inv_count_sessions(id) on delete cascade,
  item_id bigint references public.inv_items(id),
  loc text,
  qty numeric(14,3) not null check (qty >= 0),
  unknown text,                 -- an item that could not be found in the list
  round int not null default 1, -- 2 = recount
  by_user uuid default auth.uid(),
  by_name text,
  voided boolean not null default false,
  created_at timestamptz not null default now(),
  check (item_id is not null or coalesce(unknown, '') <> '')
);
create index if not exists inv_count_lines_s_idx on public.inv_count_lines (session_id, item_id);

create table if not exists public.inv_count_shelves (
  session_id bigint not null references public.inv_count_sessions(id) on delete cascade,
  loc text not null,
  status text not null check (status in ('done','empty')),
  round int not null default 1,
  by_name text,
  at timestamptz not null default now(),
  primary key (session_id, loc)
);

create table if not exists public.inv_count_flags (
  session_id bigint not null references public.inv_count_sessions(id) on delete cascade,
  item_id bigint not null references public.inv_items(id),
  reason text,
  primary key (session_id, item_id)
);

alter table public.inv_aisles enable row level security;
alter table public.inv_count_sessions enable row level security;
alter table public.inv_count_zones enable row level security;
alter table public.inv_count_lines enable row level security;
alter table public.inv_count_shelves enable row level security;
alter table public.inv_count_flags enable row level security;
do $$ declare t text; begin
  foreach t in array array['inv_aisles','inv_count_sessions','inv_count_zones','inv_count_lines','inv_count_shelves','inv_count_flags'] loop
    execute format('drop policy if exists "%s read" on public.%I', t, t);
    execute format('create policy "%s read" on public.%I for select using ((select public.inv_role()) is not null)', t, t);
  end loop;
end $$;
-- No insert/update/delete policies: all changes go through the functions below.

create or replace function public.inv_my_name() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(name, ''), (select email from auth.users where id = auth.uid())) from inv_users where user_id = auth.uid();
$$;

-- ---------- aisles (owner) ----------
create or replace function public.inv_aisle_set(area text, aisle text, units int, levels int, note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  insert into inv_aisles (area, aisle, units, levels, note)
  values (upper(trim(inv_aisle_set.area)), upper(trim(inv_aisle_set.aisle)), inv_aisle_set.units, inv_aisle_set.levels, nullif(trim(inv_aisle_set.note), ''))
  on conflict on constraint inv_aisles_area_aisle_key do update set units = excluded.units, levels = excluded.levels, note = excluded.note;
  -- an open count gets the new aisle on its board
  insert into inv_count_zones (session_id, area, aisle)
  select s.id, upper(trim(inv_aisle_set.area)), upper(trim(inv_aisle_set.aisle)) from inv_count_sessions s where s.status = 'open'
  on conflict do nothing;
end $$;

create or replace function public.inv_aisle_delete(area text, aisle text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  select count(*) into n from inv_items i
   where split_part(i.loc, '-', 1) = inv_aisle_delete.area and split_part(i.loc, '-', 2) = inv_aisle_delete.aisle;
  if n > 0 then raise exception 'aisle_in_use:%', n; end if;
  delete from inv_aisles a where a.area = inv_aisle_delete.area and a.aisle = inv_aisle_delete.aisle;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- item locations (owner and staff: the mapping walk) ----------
-- lines: [{"item":12,"loc":"D-B-04-2"}]  mode: 'home' sets the home shelf (an older one moves to overflow),
-- 'overflow' sets the overflow shelf, 'auto' = home if it has none, else overflow if it has none, else nothing.
create or replace function public.inv_assign_locs(lines jsonb, mode text default 'auto')
returns jsonb language plpgsql security definer set search_path = public as $$
declare l jsonb; it public.inv_items; nl text; nh int := 0; no int := 0; ns int := 0;
begin
  if public.inv_role() is null then raise exception 'not_allowed'; end if;
  if jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) > 2000 then raise exception 'bad_lines'; end if;
  for l in select value from jsonb_array_elements(lines) loop
    nl := upper(nullif(trim(l->>'loc'), ''));
    if nl is null or not public.inv_loc_ok(nl) then raise exception 'bad_loc:%', coalesce(nl, ''); end if;
    select * into it from inv_items where id = (l->>'item')::bigint for update;
    if it.id is null then raise exception 'no_item'; end if;
    if it.loc = nl or it.loc2 = nl then ns := ns + 1;
    elsif mode = 'home' then update inv_items set loc2 = coalesce(loc2, loc), loc = nl, updated_at = now() where id = it.id; nh := nh + 1;
    elsif mode = 'overflow' then update inv_items set loc2 = nl, updated_at = now() where id = it.id; no := no + 1;
    elsif it.loc is null then update inv_items set loc = nl, updated_at = now() where id = it.id; nh := nh + 1;
    elsif it.loc2 is null then update inv_items set loc2 = nl, updated_at = now() where id = it.id; no := no + 1;
    else ns := ns + 1;
    end if;
  end loop;
  return jsonb_build_object('home', nh, 'overflow', no, 'kept', ns);
end $$;

create or replace function public.inv_item_locs(item bigint, loc text, loc2 text)
returns void language plpgsql security definer set search_path = public as $$
declare a text := upper(nullif(trim(loc), '')); b text := upper(nullif(trim(loc2), ''));
begin
  if public.inv_role() is null then raise exception 'not_allowed'; end if;
  if not public.inv_loc_ok(a) then raise exception 'bad_loc:%', a; end if;
  if not public.inv_loc_ok(b) then raise exception 'bad_loc:%', b; end if;
  update inv_items set loc = a, loc2 = case when b = a then null else b end, updated_at = now() where id = item;
end $$;

-- ---------- the count ----------
create or replace function public.inv_count_open(name text, kind text default 'full')
returns bigint language plpgsql security definer set search_path = public as $$
declare sid bigint;
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  if exists (select 1 from inv_count_sessions where status = 'open') then raise exception 'count_already_open'; end if;
  if not exists (select 1 from inv_aisles) then raise exception 'no_aisles'; end if;
  insert into inv_count_sessions (name, kind) values (left(coalesce(nullif(trim(inv_count_open.name), ''), 'جرد'), 120), case when kind = 'partial' then 'partial' else 'full' end)
  returning id into sid;
  insert into inv_count_zones (session_id, area, aisle) select sid, a.area, a.aisle from inv_aisles a;
  return sid;
end $$;

-- staff: take an aisle / say it is finished. owner: also set the team and send it back for a recount.
create or replace function public.inv_count_zone(session bigint, area text, aisle text, status text default null, team text default null)
returns void language plpgsql security definer set search_path = public as $$
declare z public.inv_count_zones;
begin
  if public.inv_role() is null then raise exception 'not_allowed'; end if;
  if not exists (select 1 from inv_count_sessions where id = session and inv_count_sessions.status = 'open') then raise exception 'count_closed'; end if;
  select * into z from inv_count_zones where session_id = session and inv_count_zones.area = inv_count_zone.area and inv_count_zones.aisle = inv_count_zone.aisle for update;
  if z.session_id is null then raise exception 'no_zone'; end if;
  if status is not null and status not in ('todo','counting','done','recount') then raise exception 'bad_status'; end if;
  if public.inv_role() <> 'owner' and (team is not null or status in ('recount','todo')) then raise exception 'owner_only'; end if;
  update inv_count_zones set status = coalesce(inv_count_zone.status, inv_count_zones.status),
         team = case when inv_count_zone.team is null then inv_count_zones.team else nullif(trim(inv_count_zone.team), '') end,
         by_name = public.inv_my_name(), updated_at = now()
   where session_id = session and inv_count_zones.area = inv_count_zone.area and inv_count_zones.aisle = inv_count_zone.aisle;
end $$;

-- one shelf at a time: lines [{"item":12,"qty":24} | {"unknown":"علب بيضاء بدون اسم","qty":3}]
-- shelf_status 'done' (or 'empty' with no lines). Sending a shelf again adds to it (a second visit) unless replace = true.
create or replace function public.inv_count_shelf(session bigint, loc text, lines jsonb, shelf_status text default 'done', replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare l jsonb; s public.inv_count_sessions; r int := 1; n int := 0; who text := public.inv_my_name(); q numeric;
begin
  if public.inv_role() is null then raise exception 'not_allowed'; end if;
  select * into s from inv_count_sessions where id = session;
  if s.id is null or s.status <> 'open' then raise exception 'count_closed'; end if;
  if loc is not null and not public.inv_loc_ok(upper(loc)) then raise exception 'bad_loc:%', loc; end if;
  if jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) > 500 then raise exception 'bad_lines'; end if;
  if shelf_status not in ('done','empty') then raise exception 'bad_status'; end if;
  if loc is not null then
    select case when z.status = 'recount' then 2 else 1 end into r from inv_count_zones z
     where z.session_id = session and z.area = split_part(upper(loc), '-', 1) and z.aisle = split_part(upper(loc), '-', 2);
    r := coalesce(r, 1);
    if replace then update inv_count_lines set voided = true where session_id = session and inv_count_lines.loc = upper(inv_count_shelf.loc) and round = r and not voided; end if;
  end if;
  for l in select value from jsonb_array_elements(lines) loop
    q := (l->>'qty')::numeric;
    if q is null or q < 0 or q > 10000000 then raise exception 'bad_qty'; end if;
    if l ? 'item' and not exists (select 1 from inv_items where id = (l->>'item')::bigint) then raise exception 'no_item'; end if;
    insert into inv_count_lines (session_id, item_id, loc, qty, unknown, round, by_name)
    values (session, (l->>'item')::bigint, upper(inv_count_shelf.loc), q, left(nullif(trim(l->>'unknown'), ''), 200), r, who);
    n := n + 1;
  end loop;
  if loc is not null then
    insert into inv_count_shelves (session_id, loc, status, round, by_name) values (session, upper(loc), case when n = 0 then 'empty' else shelf_status end, r, who)
    on conflict (session_id, loc) do update set status = excluded.status, round = excluded.round, by_name = excluded.by_name, at = now();
  end if;
  return jsonb_build_object('saved', n, 'round', r);
end $$;

-- a counter takes back one of their lines; the owner any line
create or replace function public.inv_count_void(line bigint)
returns void language plpgsql security definer set search_path = public as $$
declare x public.inv_count_lines;
begin
  if public.inv_role() is null then raise exception 'not_allowed'; end if;
  select * into x from inv_count_lines where id = line;
  if x.id is null then raise exception 'no_line'; end if;
  if not exists (select 1 from inv_count_sessions where id = x.session_id and status = 'open') then raise exception 'count_closed'; end if;
  if public.inv_role() <> 'owner' and x.by_user is distinct from auth.uid() then raise exception 'owner_only'; end if;
  update inv_count_lines set voided = true where id = line;
end $$;

-- owner: items to recount (their aisles go back to "recount"), or clear = true to take the flags away
create or replace function public.inv_count_flag(session bigint, items jsonb, reason text default null, clear boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int := 0; i bigint;
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  if not exists (select 1 from inv_count_sessions where id = session and status = 'open') then raise exception 'count_closed'; end if;
  for i in select (value::text)::bigint from jsonb_array_elements(items) loop
    if clear then delete from inv_count_flags where session_id = session and item_id = i;
    else insert into inv_count_flags (session_id, item_id, reason) values (session, i, left(reason, 100)) on conflict (session_id, item_id) do update set reason = excluded.reason; end if;
    n := n + 1;
  end loop;
  if not clear then
    update inv_count_zones z set status = 'recount', updated_at = now()
     where z.session_id = session and exists (
       select 1 from inv_count_flags f join inv_items it on it.id = f.item_id
        where f.session_id = session and (
          (split_part(it.loc, '-', 1) = z.area and split_part(it.loc, '-', 2) = z.aisle) or
          (split_part(it.loc2, '-', 1) = z.area and split_part(it.loc2, '-', 2) = z.aisle) or
          exists (select 1 from inv_count_lines l where l.session_id = session and l.item_id = it.id and not l.voided
                   and split_part(l.loc, '-', 1) = z.area and split_part(l.loc, '-', 2) = z.aisle)));
  end if;
  return jsonb_build_object('flagged', n);
end $$;

-- What each item comes to: the latest round in which it was counted (a recount replaces the first count).
create or replace function public.inv_count_totals(session bigint)
returns table (item_id bigint, counted numeric, rounds int, lines int)
language sql stable security definer set search_path = public as $$
  with l as (select * from inv_count_lines where session_id = session and not voided and item_id is not null),
       r as (select item_id, max(round) as mr from l group by item_id)
  select l.item_id, sum(l.qty) filter (where l.round = r.mr), max(r.mr), count(*)::int
    from l join r using (item_id) group by l.item_id;
$$;

-- owner: approve. Each counted item becomes what was counted; in a full count, active items that were not
-- found become 0 when missing_zero is true. Every change is a 'count' line in the ledger, under the owner's name.
create or replace function public.inv_count_close(session bigint, missing_zero boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.inv_count_sessions; t record; n int := 0; ch int := 0; z int := 0; val numeric := 0; res jsonb;
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  select * into s from inv_count_sessions where id = session for update;
  if s.id is null or s.status <> 'open' then raise exception 'count_closed'; end if;
  perform set_config('inv.nosync', '1', true);
  for t in
    select i.id, i.qty, i.price, c.counted from inv_items i join inv_count_totals(session) c on c.item_id = i.id
  loop
    n := n + 1;
    if t.counted <> t.qty then
      insert into inv_moves (item_id, delta, kind, channel, ref, note) values (t.id, t.counted - t.qty, 'count', 'count', 'C' || session, left('جرد: ' || s.name, 500));
      ch := ch + 1; val := val + (t.counted - t.qty) * coalesce(t.price, 0);
    else
      update inv_items set counted_at = now() where id = t.id;
    end if;
  end loop;
  if s.kind = 'full' and missing_zero then
    for t in select i.id, i.qty, i.price from inv_items i
              where i.active and i.qty <> 0 and not exists (select 1 from inv_count_totals(session) c where c.item_id = i.id) loop
      insert into inv_moves (item_id, delta, kind, channel, ref, note) values (t.id, -t.qty, 'count', 'count', 'C' || session, left('جرد: ' || s.name || ' – ما انلاقى', 500));
      z := z + 1; val := val - t.qty * coalesce(t.price, 0);
    end loop;
  end if;
  perform set_config('inv.nosync', '', true);
  update products set updated_at = now(), data = data where id is not null;   -- the shop takes the new stock
  res := jsonb_build_object('counted', n, 'changed', ch, 'zeroed', z, 'value_diff', round(val, 3),
           'unknown', (select count(*) from inv_count_lines where session_id = session and not voided and item_id is null));
  update inv_count_sessions set status = 'closed', closed_at = now(), closed_by = auth.uid(), result = res where id = session;
  return res;
end $$;

create or replace function public.inv_count_cancel(session bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  update inv_count_sessions set status = 'cancelled', closed_at = now(), closed_by = auth.uid() where id = session and status = 'open';
end $$;

revoke all on function public.inv_aisle_set(text, text, int, int, text), public.inv_aisle_delete(text, text),
  public.inv_assign_locs(jsonb, text), public.inv_item_locs(bigint, text, text), public.inv_count_open(text, text),
  public.inv_count_zone(bigint, text, text, text, text), public.inv_count_shelf(bigint, text, jsonb, text, boolean),
  public.inv_count_void(bigint), public.inv_count_flag(bigint, jsonb, text, boolean), public.inv_count_totals(bigint),
  public.inv_count_close(bigint, boolean), public.inv_count_cancel(bigint), public.inv_my_name(), public.inv_loc_ok(text) from public, anon;
grant execute on function public.inv_aisle_set(text, text, int, int, text), public.inv_aisle_delete(text, text),
  public.inv_assign_locs(jsonb, text), public.inv_item_locs(bigint, text, text), public.inv_count_open(text, text),
  public.inv_count_zone(bigint, text, text, text, text), public.inv_count_shelf(bigint, text, jsonb, text, boolean),
  public.inv_count_void(bigint), public.inv_count_flag(bigint, jsonb, text, boolean), public.inv_count_totals(bigint),
  public.inv_count_close(bigint, boolean), public.inv_count_cancel(bigint), public.inv_loc_ok(text) to authenticated;
