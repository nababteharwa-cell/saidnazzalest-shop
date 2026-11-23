-- Said Nazzal – history of product changes. Run once in Supabase → SQL Editor, after files 6 and 7. Safe to run again.
-- Every change to a shop product (name, price, category, visibility, photos, sizes, codes…) is recorded with who, when and
-- the old → new value. Stock quantities are not repeated here: their history is in the stock app (inv_moves).

create table if not exists public.products_history (
  id bigint generated always as identity primary key,
  product_id text not null,
  product_name text,
  action text not null check (action in ('added','changed','removed')),
  changes jsonb not null default '[]'::jsonb,   -- [{"f":"price","v":"حبة","old":0.35,"new":0.4}, …]
  by_user uuid default auth.uid(),
  by_name text,
  created_at timestamptz not null default now()
);
create index if not exists products_history_pid_idx on public.products_history (product_id, created_at desc);
create index if not exists products_history_time_idx on public.products_history (created_at desc);
alter table public.products_history enable row level security;
drop policy if exists "products_history admin read" on public.products_history;
create policy "products_history admin read" on public.products_history for select using (public.is_admin());

create or replace function public.product_diff(o jsonb, n jsonb) returns jsonb
language plpgsql immutable as $$
declare out jsonb := '[]'::jsonb; f text; ov jsonb; nv jsonb; lbl text; ol jsonb; nl jsonb;
begin
  foreach f in array array['name','name_en','cat','sub','visible','ask','desc','desc_en','unit','kind','tags','img'] loop
    ov := o->f; nv := n->f;
    if coalesce(ov, 'null'::jsonb) is distinct from coalesce(nv, 'null'::jsonb)
       and not (coalesce(ov #>> '{}', '') = '' and coalesce(nv #>> '{}', '') = '') then
      if f = 'img' then
        out := out || jsonb_build_array(jsonb_build_object('f', 'img', 'old', case when coalesce(ov #>> '{}','') = '' then 'لا' else 'نعم' end,
                                                                     'new', case when coalesce(nv #>> '{}','') = '' then 'لا' else 'نعم' end));
      else
        out := out || jsonb_build_array(jsonb_build_object('f', f, 'old', ov, 'new', nv));
      end if;
    end if;
  end loop;
  -- sizes / colours, matched by their label
  for lbl in select distinct x from (
      select e->>'label' as x from jsonb_array_elements(coalesce(o->'vars','[]')) e
      union select e->>'label' from jsonb_array_elements(coalesce(n->'vars','[]')) e) s loop
    select e into ol from jsonb_array_elements(coalesce(o->'vars','[]')) e where e->>'label' = lbl limit 1;
    select e into nl from jsonb_array_elements(coalesce(n->'vars','[]')) e where e->>'label' = lbl limit 1;
    if ol is null then out := out || jsonb_build_array(jsonb_build_object('f', 'var_added', 'v', lbl, 'new', nl->'price'));
    elsif nl is null then out := out || jsonb_build_array(jsonb_build_object('f', 'var_removed', 'v', lbl, 'old', ol->'price'));
    else
      if (ol->'price') is distinct from (nl->'price') then out := out || jsonb_build_array(jsonb_build_object('f', 'price', 'v', lbl, 'old', ol->'price', 'new', nl->'price')); end if;
      if coalesce(ol->>'sku','') <> coalesce(nl->>'sku','') then out := out || jsonb_build_array(jsonb_build_object('f', 'sku', 'v', lbl, 'old', ol->'sku', 'new', nl->'sku')); end if;
      if coalesce(ol->>'img','') <> coalesce(nl->>'img','') then out := out || jsonb_build_array(jsonb_build_object('f', 'var_img', 'v', lbl, 'old', case when coalesce(ol->>'img','')='' then 'لا' else 'نعم' end, 'new', case when coalesce(nl->>'img','')='' then 'لا' else 'نعم' end)); end if;
    end if;
  end loop;
  return out;
end $$;

create or replace function public.products_history_log() returns trigger
language plpgsql security definer set search_path = public, auth as $$
declare ch jsonb; who text; src text := nullif(current_setting('hist.src', true), '');
begin
  if src is null then
    select coalesce(i.name, u.email) into who from auth.users u left join inv_users i on i.user_id = u.id where u.id = auth.uid();
    who := coalesce(who, case when auth.uid() is null then 'النظام' end);
  else who := src; end if;
  if tg_op = 'INSERT' then
    insert into products_history (product_id, product_name, action, by_name) values (new.id, new.data->>'name', 'added', who);
  elsif tg_op = 'DELETE' then
    insert into products_history (product_id, product_name, action, by_name, changes)
    values (old.id, old.data->>'name', 'removed', who, jsonb_build_array(jsonb_build_object('f','snapshot','old', old.data)));
  else
    ch := public.product_diff(old.data, new.data);
    if jsonb_array_length(ch) > 0 then
      insert into products_history (product_id, product_name, action, changes, by_name) values (new.id, new.data->>'name', 'changed', ch, who);
    end if;
  end if;
  return null;
end $$;
drop trigger if exists products_history_log on public.products;
create trigger products_history_log after insert or update or delete on public.products
  for each row execute function public.products_history_log();

-- the Trust import labels its price updates "استيراد ترست"
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

