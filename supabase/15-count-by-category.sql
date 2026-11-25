-- 15) Count by categories and families, from any place, adding up.
-- Run once in Supabase → SQL Editor, after 14-locations-count.sql.
--
-- Shelves and aisles are no longer needed for a count:
--  * a count is split by category (the same categories as the shop); each category is a "zone" with area = 'CAT'
--  * every count is a new line with the place it was counted in (المعرض / المستودع / السدة / any text);
--    the same item counted in several places adds up, nothing is overwritten
--  * a wrong line is removed on its own (inv_count_void), never by counting again
--  * a recount asks for the item's whole quantity again, from every place: its new lines form a new round,
--    and the newest round with lines is the one that counts

alter table public.inv_count_flags add column if not exists round int not null default 2;

drop function if exists public.inv_count_open(text, text);
create or replace function public.inv_count_open(name text, kind text default 'full', cats jsonb default '[]')
returns bigint language plpgsql security definer set search_path = public as $$
declare sid bigint;
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  if exists (select 1 from inv_count_sessions where status = 'open') then raise exception 'count_already_open'; end if;
  insert into inv_count_sessions (name, kind)
  values (left(coalesce(nullif(trim(inv_count_open.name), ''), 'جرد'), 120), case when kind = 'partial' then 'partial' else 'full' end)
  returning id into sid;
  insert into inv_count_zones (session_id, area, aisle)
  select distinct sid, 'CAT', left(trim(value #>> '{}'), 120)
    from jsonb_array_elements(case when jsonb_typeof(cats) = 'array' then cats else '[]'::jsonb end)
   where coalesce(trim(value #>> '{}'), '') <> '';
  return sid;
end $$;

-- lines [{"item":12,"qty":24} | {"unknown":"علب بيضاء بدون اسم","qty":3}] counted in one place. Always added, never replacing.
create or replace function public.inv_count_add(session bigint, place text, lines jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare l jsonb; it bigint; q numeric; r int; n int := 0; ids bigint[] := '{}'; nid bigint;
        who text := public.inv_my_name(); pl text := left(nullif(trim(place), ''), 60);
begin
  if public.inv_role() is null then raise exception 'not_allowed'; end if;
  if not exists (select 1 from inv_count_sessions s where s.id = session and s.status = 'open') then raise exception 'count_closed'; end if;
  if pl is null then raise exception 'no_place'; end if;
  if jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(lines) > 500 then raise exception 'too_many_lines'; end if;
  for l in select value from jsonb_array_elements(lines) loop
    q := (l->>'qty')::numeric;
    if q is null or q < 0 or q > 1000000000 then raise exception 'bad_qty'; end if;
    it := nullif(l->>'item', '')::bigint;
    if it is not null then
      if not exists (select 1 from inv_items x where x.id = it) then raise exception 'no_item'; end if;
      r := null;
      select f.round into r from inv_count_flags f where f.session_id = session and f.item_id = it;
      if r is null then
        select coalesce(max(x.round), 1) into r from inv_count_lines x where x.session_id = session and x.item_id = it and not x.voided;
      end if;
      insert into inv_count_lines (session_id, item_id, loc, qty, round, by_name) values (session, it, pl, q, r, who) returning id into nid;
    else
      if coalesce(trim(l->>'unknown'), '') = '' then raise exception 'bad_line'; end if;
      insert into inv_count_lines (session_id, unknown, loc, qty, round, by_name)
      values (session, left(trim(l->>'unknown'), 200), pl, q, 1, who) returning id into nid;
    end if;
    ids := ids || nid; n := n + 1;
  end loop;
  return jsonb_build_object('saved', n, 'ids', to_jsonb(ids));
end $$;

-- owner: items to count again from scratch (all places), or clear = true to take the flags away
create or replace function public.inv_count_flag(session bigint, items jsonb, reason text default null, clear boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int := 0; i bigint;
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  if not exists (select 1 from inv_count_sessions where id = session and status = 'open') then raise exception 'count_closed'; end if;
  for i in select (value #>> '{}')::bigint from jsonb_array_elements(items) loop
    if clear then
      delete from inv_count_flags where session_id = session and item_id = i;
    else
      insert into inv_count_flags (session_id, item_id, reason, round)
      values (session, i, left(reason, 100),
              (select coalesce(max(x.round), 1) + 1 from inv_count_lines x where x.session_id = session and x.item_id = i and not x.voided))
      on conflict (session_id, item_id) do update set reason = excluded.reason, round = greatest(inv_count_flags.round, excluded.round);
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('flagged', n);
end $$;

-- owner: approve. Each counted item becomes what was counted. Items that were not counted become 0 when
-- missing_zero is true: in a full count all of them, or only the ids in zero_items (a count of some categories).
drop function if exists public.inv_count_close(bigint, boolean);
create or replace function public.inv_count_close(session bigint, missing_zero boolean default true, zero_items jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.inv_count_sessions; t record; n int := 0; ch int := 0; z int := 0; val numeric := 0; res jsonb;
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  select * into s from inv_count_sessions where id = session for update;
  if s.id is null or s.status <> 'open' then raise exception 'count_closed'; end if;
  create temp table if not exists inv_ct (item_id bigint primary key, counted numeric) on commit drop;
  truncate inv_ct;
  insert into inv_ct select c.item_id, c.counted from public.inv_count_totals(session) c;
  perform set_config('inv.nosync', '1', true);
  for t in select i.id, i.qty, i.price, c.counted from inv_items i join inv_ct c on c.item_id = i.id loop
    n := n + 1;
    if t.counted <> t.qty then
      insert into inv_moves (item_id, delta, kind, channel, ref, note) values (t.id, t.counted - t.qty, 'count', 'count', 'C' || session, left('جرد: ' || s.name, 500));
      ch := ch + 1; val := val + (t.counted - t.qty) * coalesce(t.price, 0);
    else
      update inv_items set counted_at = now() where id = t.id;
    end if;
  end loop;
  if missing_zero and (s.kind = 'full' or jsonb_typeof(zero_items) = 'array') then
    for t in select i.id, i.qty, i.price from inv_items i
              where i.active and i.qty <> 0 and not exists (select 1 from inv_ct c where c.item_id = i.id)
                and (jsonb_typeof(zero_items) is distinct from 'array'
                     or i.id in (select (value #>> '{}')::bigint from jsonb_array_elements(zero_items))) loop
      insert into inv_moves (item_id, delta, kind, channel, ref, note) values (t.id, -t.qty, 'count', 'count', 'C' || session, left('جرد: ' || s.name || ' – لم يُعثر عليه', 500));
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

revoke all on function public.inv_count_open(text, text, jsonb), public.inv_count_add(bigint, text, jsonb),
  public.inv_count_flag(bigint, jsonb, text, boolean), public.inv_count_close(bigint, boolean, jsonb) from public, anon;
grant execute on function public.inv_count_open(text, text, jsonb), public.inv_count_add(bigint, text, jsonb),
  public.inv_count_flag(bigint, jsonb, text, boolean), public.inv_count_close(bigint, boolean, jsonb) to authenticated;
