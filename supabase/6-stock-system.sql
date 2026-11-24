-- Said Nazzal – stock system (المخزون). Run once in Supabase → SQL Editor, after files 1–3 and 5.
-- Safe to run again. It adds new tables only; your shop data is not touched.
--
-- Idea: every change of stock is one line in inv_moves (a ledger that is never edited or deleted).
-- The current quantity of each item is kept in inv_items.qty and is always the sum of its lines.
-- Website sizes whose code (sku) equals a Trust barcode or code take their stock from here automatically.

-- ---------- users ----------
create table if not exists public.inv_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','staff')),
  name text,
  created_at timestamptz not null default now()
);
create or replace function public.inv_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.inv_users where user_id = auth.uid();
$$;

-- ---------- items ----------
create table if not exists public.inv_items (
  id bigint generated always as identity primary key,
  code text not null unique,             -- رمز المادة in Trust
  barcode text unique,                   -- الباركود in Trust
  name text not null,
  price numeric(12,3),                   -- سعر البيع in Trust
  qty numeric(14,3) not null default 0,  -- current stock (sum of moves)
  min_qty numeric(14,3),                 -- alert when stock falls to this
  grp text,                              -- section / shelf (optional)
  active boolean not null default true,
  counted_at timestamptz,                -- last physical count
  trust_qty numeric(14,3), trust_sold numeric(14,3), trust_bought numeric(14,3), trust_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists inv_items_name_idx on public.inv_items (name);

create table if not exists public.inv_moves (
  id bigint generated always as identity primary key,
  item_id bigint not null references public.inv_items(id),
  delta numeric(14,3) not null,
  kind text not null check (kind in ('opening','pos_sale','pos_purchase','online_sale','online_return',
                                     'social_sale','purchase','return','adjust','count','void')),
  channel text,           -- instagram / facebook / whatsapp / showroom / website / trust …
  ref text,               -- order number, invoice number …
  note text,
  unit_price numeric(12,3),
  qty_after numeric(14,3),
  by_user uuid default auth.uid(),
  by_name text,
  voids bigint references public.inv_moves(id),
  voided boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists inv_moves_item_idx on public.inv_moves (item_id, created_at desc);
create index if not exists inv_moves_time_idx on public.inv_moves (created_at desc);
create index if not exists inv_moves_kind_idx on public.inv_moves (kind, created_at desc);

create table if not exists public.inv_imports (
  id bigint generated always as identity primary key,
  mode text not null, file_name text, summary jsonb,
  by_user uuid default auth.uid(), created_at timestamptz not null default now()
);

-- ---------- security ----------
alter table public.inv_users   enable row level security;
alter table public.inv_items   enable row level security;
alter table public.inv_moves   enable row level security;
alter table public.inv_imports enable row level security;

drop policy if exists "inv_users read" on public.inv_users;
create policy "inv_users read" on public.inv_users for select using (user_id = (select auth.uid()) or (select public.inv_role()) = 'owner');
drop policy if exists "inv_items read" on public.inv_items;
create policy "inv_items read" on public.inv_items for select using ((select public.inv_role()) is not null);
drop policy if exists "inv_moves read" on public.inv_moves;
create policy "inv_moves read" on public.inv_moves for select using ((select public.inv_role()) is not null);
drop policy if exists "inv_imports read" on public.inv_imports;
create policy "inv_imports read" on public.inv_imports for select using ((select public.inv_role()) = 'owner');
-- No insert/update/delete policies: all changes go through the functions below.

-- ---------- website stock follows the stock system ----------
-- Any size on the website whose sku equals an item's barcode or code gets stock = that item's quantity.
create or replace function public.web_stock_fix(d jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; v jsonb; q numeric; pr numeric;
begin
  if d->'vars' is null or jsonb_typeof(d->'vars') <> 'array' then return d; end if;
  for v in select value from jsonb_array_elements(d->'vars') loop
    q := null; pr := null;
    if coalesce(v->>'sku','') <> '' then
      select greatest(floor(i.qty), 0), i.price into q, pr from inv_items i
       where i.barcode = trim(v->>'sku') or i.code = trim(v->>'sku')
       order by (i.barcode = trim(v->>'sku')) desc limit 1;   -- a barcode match wins over a Trust code
    end if;
    if q is not null then
      v := jsonb_set(v, '{stock}', to_jsonb(q));
      if pr is not null and pr > 0 then v := jsonb_set(v, '{price}', to_jsonb(pr)); end if;
    end if;
    out := out || jsonb_build_array(v);
  end loop;
  return jsonb_set(d, '{vars}', out);
end $$;

create or replace function public.products_stock_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if to_regclass('public.inv_items') is not null then new.data := public.web_stock_fix(new.data); end if;
  return new;
end $$;
drop trigger if exists products_stock_guard on public.products;
create trigger products_stock_guard before insert or update of data on public.products
  for each row execute function public.products_stock_guard();

create or replace function public.inv_sync_web(it public.inv_items) returns void
language plpgsql security definer set search_path = public as $$
begin
  update products set updated_at = now(), data = data
   where exists (select 1 from jsonb_array_elements(data->'vars') v where trim(v->>'sku') in (it.barcode, it.code));
end $$;

-- ---------- the ledger ----------
create or replace function public.inv_moves_apply() returns trigger
language plpgsql security definer set search_path = public as $$
declare it public.inv_items;
begin
  update inv_items set qty = qty + new.delta, updated_at = now(),
         counted_at = case when new.kind = 'count' then now() else counted_at end
   where id = new.item_id returning * into it;
  if it.id is null then raise exception 'no_item'; end if;
  new.qty_after := it.qty;
  if new.by_name is null then
    select coalesce(name, '') into new.by_name from inv_users where user_id = new.by_user;
  end if;
  if coalesce(current_setting('inv.nosync', true), '') <> '1' then perform public.inv_sync_web(it); end if;
  return new;
end $$;
drop trigger if exists inv_moves_apply on public.inv_moves;
create trigger inv_moves_apply before insert on public.inv_moves
  for each row execute function public.inv_moves_apply();

create or replace function public.inv_moves_lock() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'ledger_is_permanent'; end if;
  if new.item_id <> old.item_id or new.delta <> old.delta or new.kind <> old.kind or new.created_at <> old.created_at
  then raise exception 'ledger_is_permanent'; end if;
  return new;
end $$;
drop trigger if exists inv_moves_lock on public.inv_moves;
create trigger inv_moves_lock before update or delete on public.inv_moves
  for each row execute function public.inv_moves_lock();

-- ---------- recording sales / receipts / returns / adjustments ----------
-- lines: [{"item": 12, "qty": 3, "price": 1.5}]   qty is always positive; the kind decides the sign.
create or replace function public.inv_record(kind text, lines jsonb, channel text default null, ref text default null, note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r text := public.inv_role(); l jsonb; s int; n int := 0; q numeric;
begin
  if r is null then raise exception 'not_allowed'; end if;
  if kind not in ('social_sale','purchase','return','adjust') then raise exception 'bad_kind'; end if;
  if kind = 'adjust' and r <> 'owner' then raise exception 'owner_only'; end if;
  if jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 or jsonb_array_length(lines) > 500 then raise exception 'bad_lines'; end if;
  if kind = 'adjust' and coalesce(trim(note), '') = '' then raise exception 'reason_required'; end if;
  s := case kind when 'social_sale' then -1 else 1 end;
  for l in select value from jsonb_array_elements(lines) loop
    q := (l->>'qty')::numeric;
    if q is null or q = 0 or (kind <> 'adjust' and q < 0) or abs(q) > 1000000 then raise exception 'bad_qty'; end if;
    insert into inv_moves (item_id, delta, kind, channel, ref, note, unit_price)
    values ((l->>'item')::bigint, s * q, kind, left(channel, 40), left(ref, 80), left(note, 500), nullif(l->>'price','')::numeric);
    n := n + 1;
  end loop;
  return jsonb_build_object('lines', n);
end $$;

-- ---------- physical count ----------
-- lines: [{"item": 12, "counted": 40}]  — sets the stock to what was counted and records the difference.
create or replace function public.inv_count(lines jsonb, note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l jsonb; cur numeric; c numeric; n int := 0; diff int := 0; it bigint;
begin
  if public.inv_role() is null then raise exception 'not_allowed'; end if;
  if jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 or jsonb_array_length(lines) > 2000 then raise exception 'bad_lines'; end if;
  for l in select value from jsonb_array_elements(lines) loop
    it := (l->>'item')::bigint; c := (l->>'counted')::numeric;
    if c is null or c < 0 then raise exception 'bad_qty'; end if;
    select qty into cur from inv_items where id = it for update;
    if cur is null then raise exception 'no_item'; end if;
    insert into inv_moves (item_id, delta, kind, channel, note) values (it, c - cur, 'count', 'count', left(note, 500));
    n := n + 1; if c <> cur then diff := diff + 1; end if;
  end loop;
  return jsonb_build_object('counted', n, 'changed', diff);
end $$;

-- ---------- undo a line (owner): adds an opposite line, keeps both in history ----------
create or replace function public.inv_void(move_id bigint, note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m public.inv_moves;
begin
  if public.inv_role() <> 'owner' or public.inv_role() is null then raise exception 'owner_only'; end if;
  select * into m from inv_moves where id = move_id for update;
  if m.id is null then raise exception 'no_move'; end if;
  if m.voided or m.kind in ('void','opening') then raise exception 'cannot_void'; end if;
  if m.kind in ('online_sale','online_return') then raise exception 'use_order_status'; end if;
  insert into inv_moves (item_id, delta, kind, channel, ref, note, voids)
  values (m.item_id, -m.delta, 'void', m.channel, m.ref, left(coalesce(note, ''), 500), m.id);
  update inv_moves set voided = true where id = m.id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- item settings (owner) ----------
create or replace function public.inv_item_set(item bigint, min_qty numeric, grp text, active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  update inv_items set min_qty = inv_item_set.min_qty, grp = nullif(trim(inv_item_set.grp), ''), active = inv_item_set.active, updated_at = now()
   where id = item;
end $$;

-- ---------- Trust import ----------
-- rows: [{"code":"1","name":"…","barcode":"200507","qty":113,"bought":1220,"sold":1284,"price":0.35}]
-- mode 'opening': stock is set to Trust's quantity (first time, or to start again).
-- mode 'daily'  : Trust's sold / purchased counters are compared with the last import;
--                 the increase is recorded as POS sales / purchases. Trust's own stock figure is only kept for comparison.
-- dry_run = true returns the summary without changing anything.
create or replace function public.inv_import_trust(rows jsonb, mode text, file_name text default null, dry_run boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; it public.inv_items; c_code text; q numeric; b numeric; s numeric; ds numeric; db numeric;
  n_new int := 0; n_sale int := 0; n_buy int := 0; n_price int := 0; n_open int := 0; n_name int := 0;
  q_sale numeric := 0; q_buy numeric := 0; samples jsonb := '[]'::jsonb; imp bigint;
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  if mode not in ('opening','daily') then raise exception 'bad_mode'; end if;
  if jsonb_typeof(rows) <> 'array' or jsonb_array_length(rows) = 0 or jsonb_array_length(rows) > 20000 then raise exception 'bad_rows'; end if;
  if mode = 'daily' and not exists (select 1 from inv_items where trust_at is not null) then raise exception 'need_opening'; end if;
  perform set_config('inv.nosync', '1', true);
  if not dry_run then
    insert into inv_imports (mode, file_name) values (mode, left(file_name, 200)) returning id into imp;
  end if;
  for r in select value from jsonb_array_elements(rows) loop
    c_code := trim(r->>'code');
    if coalesce(c_code, '') = '' or coalesce(trim(r->>'name'), '') = '' then continue; end if;
    q := coalesce(nullif(r->>'qty','')::numeric, 0);
    b := coalesce(nullif(r->>'bought','')::numeric, 0);
    s := coalesce(nullif(r->>'sold','')::numeric, 0);
    select * into it from inv_items where inv_items.code = c_code for update;
    if it.id is null then
      n_new := n_new + 1;
      if not dry_run then
        insert into inv_items (code, barcode, name, price, trust_qty, trust_sold, trust_bought, trust_at)
        values (c_code, nullif(trim(r->>'barcode'), ''), trim(r->>'name'), nullif(r->>'price','')::numeric, q, s, b, now())
        returning * into it;
        if q <> 0 then insert into inv_moves (item_id, delta, kind, channel, ref) values (it.id, q, 'opening', 'trust', 'import ' || imp); end if;
      end if;
      continue;
    end if;
    if it.price is distinct from nullif(r->>'price','')::numeric then n_price := n_price + 1; end if;
    if it.name <> trim(r->>'name') then n_name := n_name + 1; end if;
    if mode = 'opening' then
      if q <> it.qty then
        n_open := n_open + 1;
        if not dry_run then insert into inv_moves (item_id, delta, kind, channel, ref) values (it.id, q - it.qty, 'opening', 'trust', 'import ' || imp); end if;
      end if;
    else
      ds := case when it.trust_sold is null then 0 when s >= it.trust_sold then s - it.trust_sold else s end;
      db := case when it.trust_bought is null then 0 when b >= it.trust_bought then b - it.trust_bought else b end;
      if ds > 0 then
        n_sale := n_sale + 1; q_sale := q_sale + ds;
        if jsonb_array_length(samples) < 15 then samples := samples || jsonb_build_array(jsonb_build_object('name', it.name, 'sold', ds, 'stock', it.qty - ds + db)); end if;
        if not dry_run then insert into inv_moves (item_id, delta, kind, channel, ref, unit_price) values (it.id, -ds, 'pos_sale', 'trust', 'import ' || imp, nullif(r->>'price','')::numeric); end if;
      end if;
      if db > 0 then
        n_buy := n_buy + 1; q_buy := q_buy + db;
        if not dry_run then insert into inv_moves (item_id, delta, kind, channel, ref) values (it.id, db, 'pos_purchase', 'trust', 'import ' || imp); end if;
      end if;
    end if;
    if not dry_run then
      update inv_items set name = trim(r->>'name'), barcode = coalesce(nullif(trim(r->>'barcode'), ''), barcode),
             price = coalesce(nullif(r->>'price','')::numeric, price),
             trust_qty = q, trust_sold = s, trust_bought = b, trust_at = now(), updated_at = now()
       where id = it.id;
    end if;
  end loop;
  if not dry_run then
    perform set_config('inv.nosync', '', true);
    perform set_config('hist.src', 'استيراد ترست', true);
    update products set data = data, updated_at = now() where id is not null;   -- refresh website stock once
    update inv_imports set summary = jsonb_build_object('new', n_new, 'sales', n_sale, 'sold_qty', q_sale, 'purchases', n_buy, 'bought_qty', q_buy, 'opening', n_open, 'prices', n_price)
     where id = imp;
  end if;
  return jsonb_build_object('mode', mode, 'new', n_new, 'sales', n_sale, 'sold_qty', q_sale, 'purchases', n_buy, 'bought_qty', q_buy,
                            'opening', n_open, 'prices', n_price, 'names', n_name, 'samples', samples, 'dry_run', dry_run);
end $$;

-- ---------- users (owner) ----------
create or replace function public.inv_set_user(email text, role text, name text default null)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare uid uuid;
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  select id into uid from auth.users where lower(auth.users.email) = lower(trim(inv_set_user.email));
  if uid is null then raise exception 'no_such_login'; end if;
  if role = 'none' then
    if uid = auth.uid() then raise exception 'cannot_remove_self'; end if;
    delete from inv_users where user_id = uid; return jsonb_build_object('removed', true);
  end if;
  if role not in ('owner','staff') then raise exception 'bad_role'; end if;
  if uid = auth.uid() and role <> 'owner' then raise exception 'cannot_demote_self'; end if;
  insert into inv_users (user_id, role, name) values (uid, role, nullif(trim(name), ''))
  on conflict (user_id) do update set role = excluded.role, name = coalesce(excluded.name, inv_users.name);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.inv_user_list() returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if public.inv_role() is distinct from 'owner' then raise exception 'owner_only'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('email', u.email, 'role', i.role, 'name', i.name) order by i.role, u.email)
                     from inv_users i join auth.users u on u.id = i.user_id), '[]'::jsonb);
end $$;

-- ---------- reports ----------
create or replace function public.inv_report(d_from timestamptz, d_to timestamptz) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.inv_role() is null then raise exception 'not_allowed'; end if;
  return jsonb_build_object(
    'by_kind', coalesce((select jsonb_agg(x) from (
        select m.kind, coalesce(m.channel,'') as channel, count(*) as lines, sum(-m.delta) filter (where m.delta < 0) as out_qty,
               sum(m.delta) filter (where m.delta > 0) as in_qty,
               round(sum(-m.delta * coalesce(m.unit_price, i.price, 0)) filter (where m.delta < 0), 3) as out_value
          from inv_moves m join inv_items i on i.id = m.item_id
         where m.created_at >= d_from and m.created_at < d_to and not m.voided and m.kind <> 'void'
         group by m.kind, m.channel order by m.kind) x), '[]'::jsonb),
    'top', coalesce((select jsonb_agg(x) from (
        select i.id, i.name, i.barcode, sum(-m.delta) as qty, round(sum(-m.delta * coalesce(m.unit_price, i.price, 0)), 3) as value, i.qty as stock
          from inv_moves m join inv_items i on i.id = m.item_id
         where m.kind in ('pos_sale','online_sale','social_sale') and not m.voided
           and m.created_at >= d_from and m.created_at < d_to
         group by i.id order by 4 desc limit 30) x), '[]'::jsonb),
    'counts', coalesce((select jsonb_agg(x) from (
        select i.name, m.delta, m.qty_after, m.by_name, m.created_at from inv_moves m join inv_items i on i.id = m.item_id
         where m.kind = 'count' and m.delta <> 0 and m.created_at >= d_from and m.created_at < d_to
         order by abs(m.delta * coalesce(i.price,0)) desc limit 30) x), '[]'::jsonb)
  );
end $$;

-- items with stock but no sale for a number of days
create or replace function public.inv_dead(days int default 90) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.inv_role() is null then raise exception 'not_allowed'; end if;
  return coalesce((select jsonb_agg(x) from (
    select i.id, i.name, i.barcode, i.qty, i.price, round(i.qty * coalesce(i.price,0), 3) as value,
           (select max(created_at) from inv_moves m where m.item_id = i.id and m.kind in ('pos_sale','online_sale','social_sale')) as last_sale
      from inv_items i
     where i.qty > 0 and i.active
       and not exists (select 1 from inv_moves m where m.item_id = i.id and m.kind in ('pos_sale','online_sale','social_sale')
                         and m.created_at > now() - make_interval(days => days))
     order by i.qty * coalesce(i.price,0) desc limit 300) x), '[]'::jsonb);
end $$;

-- ---------- online orders go through the stock system ----------
create or replace function public.inv_item_for_sku(sku text) returns bigint
language sql stable security definer set search_path = public as $$
  select id from inv_items where coalesce(trim(sku),'') <> '' and (barcode = trim(sku) or code = trim(sku))
  order by (barcode = trim(sku)) desc limit 1;
$$;

create or replace function public.place_order(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; z jsonb; it jsonb; p jsonb; v jsonb;
  pid text; vi int; q int; price numeric; stock numeric; inv bigint; iq numeric;
  lines jsonb := '[]'::jsonb; subtotal numeric := 0; fee numeric := 0;
  intl boolean; free_over numeric; c jsonb; new_code text;
begin
  select data into s from settings where id = 1;
  z := s->'zones'->((payload->>'zone')::int);
  if z is null or (payload->>'zone')::int < 0 then raise exception 'bad_zone'; end if;
  intl := coalesce((z->>'intl')::boolean, false);

  c := payload->'customer';
  if jsonb_typeof(c) <> 'object' then raise exception 'missing_contact'; end if;
  if coalesce(trim(c->>'name'),'') = '' or coalesce(trim(c->>'phone'),'') = '' then raise exception 'missing_contact'; end if;
  if length(c->>'name') > 120 or length(c->>'phone') > 30 or length(coalesce(c->>'addr','')) > 400
     or length(coalesce(c->>'note','')) > 1000 or length(coalesce(c->>'country','')) > 80
     or length(coalesce(c->>'city','')) > 80 then raise exception 'too_long'; end if;
  if (select count(*) from orders where created_at > now() - interval '10 minutes'
        and regexp_replace(customer->>'phone', '\D', '', 'g') = regexp_replace(c->>'phone', '\D', '', 'g')) >= 5
     or (select count(*) from orders where created_at > now() - interval '10 minutes') >= 40
  then raise exception 'too_many_orders'; end if;
  if jsonb_typeof(payload->'items') <> 'array' or jsonb_array_length(payload->'items') = 0
     or jsonb_array_length(payload->'items') > 100 then raise exception 'bad_items'; end if;

  new_code := 'SN-' || nextval('order_no');
  for it in select * from jsonb_array_elements(payload->'items') loop
    pid := it->>'pid'; vi := (it->>'vi')::int; q := (it->>'q')::int;
    if q is null or q < 1 or q > 100000 then raise exception 'bad_qty'; end if;
    if vi is null or vi < 0 then raise exception 'bad_variant:%', pid; end if;
    select data into p from products where id = pid for update;
    if p is null or not coalesce((p->>'visible')::boolean, true) or coalesce((p->>'ask')::boolean, false) then
      raise exception 'unavailable:%', pid; end if;
    v := p->'vars'->vi;
    if v is null then raise exception 'bad_variant:%', pid; end if;
    price := (v->>'price')::numeric;
    if price is null or price < 0 then raise exception 'unavailable:%', pid; end if;
    inv := public.inv_item_for_sku(v->>'sku');
    if inv is not null then
      select qty into iq from inv_items where id = inv for update;
      if floor(iq) < q then raise exception 'out_of_stock:%', pid; end if;
      insert into inv_moves (item_id, delta, kind, channel, ref, unit_price, by_name)
      values (inv, -q, 'online_sale', 'website', new_code, price, 'website');
    else
      stock := nullif(v->>'stock','')::numeric;
      if stock is not null then
        if stock < q then raise exception 'out_of_stock:%', pid; end if;
        update products set data = jsonb_set(data, array['vars', vi::text, 'stock'], to_jsonb(stock - q)), updated_at = now() where id = pid;
      end if;
    end if;
    subtotal := subtotal + price * q;
    lines := lines || jsonb_build_object('pid', pid, 'vi', vi, 'sku', v->>'sku', 'inv', inv, 'name', p->>'name', 'v', v->>'label', 'price', price, 'q', q);
  end loop;

  free_over := nullif(s->>'freeOver','')::numeric;
  if intl then fee := 0;
  elsif free_over is not null and free_over > 0 and subtotal >= free_over then fee := 0;
  else fee := coalesce((z->>'fee')::numeric, 0); end if;

  insert into orders (code, customer, items, sub, fee, total)
  values (new_code,
          jsonb_build_object('name', trim(c->>'name'), 'phone', c->>'phone', 'addr', c->>'addr', 'note', c->>'note',
                             'country', c->>'country', 'city', c->>'city', 'lang', c->>'lang',
                             'zone', z->>'name', 'intl', intl),
          lines, subtotal, fee, subtotal + fee);
  return jsonb_build_object('code', new_code, 'sub', subtotal, 'fee', fee, 'total', subtotal + fee, 'intl', intl);
end $$;
revoke all on function public.place_order(jsonb) from public;
grant execute on function public.place_order(jsonb) to anon, authenticated;

create or replace function public.order_stock_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare it jsonb; p jsonb; vi int; q int; stock numeric; dir int; inv bigint;
begin
  if new.status = 'cancel' and old.status <> 'cancel' then dir := 1;
  elsif old.status = 'cancel' and new.status <> 'cancel' then dir := -1;
  else return new; end if;
  for it in select * from jsonb_array_elements(new.items) loop
    q := (it->>'q')::int;
    inv := nullif(it->>'inv','')::bigint;
    if inv is not null then
      insert into inv_moves (item_id, delta, kind, channel, ref, unit_price, by_name)
      values (inv, dir * q, case when dir = 1 then 'online_return' else 'online_sale' end, 'website', new.code, (it->>'price')::numeric, 'website');
      continue;
    end if;
    select data into p from products where id = it->>'pid' for update;
    if p is null then continue; end if;
    vi := (it->>'vi')::int;
    if vi is null then
      select (e.ord - 1)::int into vi from jsonb_array_elements(p->'vars') with ordinality e(v, ord)
       where e.v->>'label' = it->>'v' limit 1;
    end if;
    if vi is null or p->'vars'->vi is null then continue; end if;
    stock := nullif(p->'vars'->vi->>'stock','')::numeric;
    if stock is null then continue; end if;
    update products set data = jsonb_set(data, array['vars', vi::text, 'stock'], to_jsonb(greatest(stock + dir * q, 0))), updated_at = now()
     where id = it->>'pid';
  end loop;
  return new;
end $$;
drop trigger if exists orders_stock_on_status on public.orders;
create trigger orders_stock_on_status after update of status on public.orders
  for each row execute function public.order_stock_on_status();

revoke all on function public.inv_record(text, jsonb, text, text, text) from public, anon;
revoke all on function public.inv_count(jsonb, text) from public, anon;
revoke all on function public.inv_void(bigint, text) from public, anon;
revoke all on function public.inv_import_trust(jsonb, text, text, boolean) from public, anon;
revoke all on function public.inv_set_user(text, text, text) from public, anon;
revoke all on function public.inv_user_list() from public, anon;
revoke all on function public.inv_item_set(bigint, numeric, text, boolean) from public, anon;
grant execute on function public.inv_record(text, jsonb, text, text, text), public.inv_count(jsonb, text), public.inv_void(bigint, text),
  public.inv_import_trust(jsonb, text, text, boolean), public.inv_set_user(text, text, text), public.inv_user_list(),
  public.inv_item_set(bigint, numeric, text, boolean), public.inv_report(timestamptz, timestamptz), public.inv_dead(int) to authenticated;


-- ---------- link a website size to a Trust item (owner; also needs shop-admin rights) ----------
create or replace function public.inv_link(pid text, vi int, sku text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p jsonb;
begin
  if public.inv_role() is distinct from 'owner' or not public.is_admin() then raise exception 'owner_only'; end if;
  select data into p from products where id = pid for update;
  if p is null or vi < 0 or p->'vars'->vi is null then raise exception 'no_variant'; end if;
  if coalesce(trim(sku),'') = '' then
    update products set data = data #- array['vars', vi::text, 'sku'], updated_at = now() where id = pid;
  else
    if public.inv_item_for_sku(sku) is null then raise exception 'no_item'; end if;
    update products set data = jsonb_set(data, array['vars', vi::text, 'sku'], to_jsonb(trim(sku))), updated_at = now() where id = pid;
  end if;
  select data into p from products where id = pid;
  return p->'vars'->vi;
end $$;
revoke all on function public.inv_link(text, int, text) from public, anon;
grant execute on function public.inv_link(text, int, text) to authenticated;

-- ---------- make yourself the owner ----------
insert into public.inv_users (user_id, role, name)
select id, 'owner', 'Arwa' from auth.users where email = 'info@saidnazzalest.com'
on conflict (user_id) do update set role = 'owner';
