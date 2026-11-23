-- Said Nazzal – every Trust item becomes a shop product. Run once in Supabase → SQL Editor, after file 6. Safe to run again.
-- 1) Website price and stock of a linked size follow the stock system (Trust selling price, stock quantity).
-- 2) inv_publish(): the stock app sends the products; the old shop products are copied to products_backup first.

create table if not exists public.products_backup (
  backup_at timestamptz not null default now(),
  id text not null, sort int, data jsonb not null
);
alter table public.products_backup enable row level security;
drop policy if exists "products_backup admin" on public.products_backup;
create policy "products_backup admin" on public.products_backup for select using (public.is_admin());

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

create or replace function public.inv_item_for_sku(sku text) returns bigint
language sql stable security definer set search_path = public as $$
  select id from inv_items where coalesce(trim(sku),'') <> '' and (barcode = trim(sku) or code = trim(sku))
  order by (barcode = trim(sku)) desc limit 1;
$$;

create or replace function public.inv_sync_web(it public.inv_items) returns void
language plpgsql security definer set search_path = public as $$
begin
  update products set updated_at = now(), data = data
   where exists (select 1 from jsonb_array_elements(data->'vars') v where trim(v->>'sku') in (it.barcode, it.code));
end $$;

-- rows: [{"id":"t123","sort":5,"data":{…product…}}]
-- replace = true: copy every current product to products_backup and remove the products that did not come from Trust.
create or replace function public.inv_publish(rows jsonb, replace boolean default false, cats jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; n_new int := 0; n_old int := 0; removed int := 0;
begin
  if public.inv_role() is distinct from 'owner' or not public.is_admin() then raise exception 'owner_only'; end if;
  if jsonb_typeof(rows) <> 'array' or jsonb_array_length(rows) > 2000 then raise exception 'bad_rows'; end if;
  if replace then
    insert into products_backup (id, sort, data) select id, sort, data from products where id is not null;
    delete from products where id not like 't%';
    get diagnostics removed = row_count;
  end if;
  for r in select value from jsonb_array_elements(rows) loop
    if coalesce(r->>'id','') !~ '^t' or r->'data' is null then raise exception 'bad_row'; end if;
    insert into products (id, sort, data, updated_at) values (r->>'id', coalesce((r->>'sort')::int, 0), r->'data', now())
    on conflict (id) do nothing;
    if found then n_new := n_new + 1; else n_old := n_old + 1; end if;
  end loop;
  if cats is not null and jsonb_typeof(cats) = 'array' then
    update settings set data = jsonb_set(data, '{categories}', cats), updated_at = now() where id = 1;
  end if;
  return jsonb_build_object('added', n_new, 'already', n_old, 'removed', removed);
end $$;
revoke all on function public.inv_publish(jsonb, boolean, jsonb) from public, anon;
grant execute on function public.inv_publish(jsonb, boolean, jsonb) to authenticated;

-- refresh prices/stock of products already linked
update public.products set data = data, updated_at = now() where id is not null;
