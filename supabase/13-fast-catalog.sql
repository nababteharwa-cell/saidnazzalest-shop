-- 13) Faster shop loading: the whole visible catalogue (and the shop settings) in ONE request,
-- without hidden products and without empty fields. Read-only; safe to run more than once.

create or replace function public.shop_catalog() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'settings', (select data from settings where id = 1),
    'products', coalesce((
      select jsonb_agg(
               (p.data - 'src') - array_remove(array[
                 case when coalesce(p.data->>'desc', '') = '' then 'desc' end,
                 case when coalesce(p.data->>'desc_en', '') = '' then 'desc_en' end,
                 case when coalesce(p.data->'tags', '[]'::jsonb) = '[]'::jsonb then 'tags' end,
                 case when coalesce(p.data->>'img', '') = '' then 'img' end
               ], null)
               order by p.sort, p.id)
        from products p
       where coalesce((p.data->>'visible')::boolean, true)
    ), '[]'::jsonb),
    'at', now());
$$;
revoke all on function public.shop_catalog() from public;
grant execute on function public.shop_catalog() to anon, authenticated;

-- Faster security rules: each permission check now runs once per request instead of once per row
-- (wrapping a function in "(select …)" lets the database evaluate it a single time). Same rules as before.
drop policy if exists "products: anyone reads visible" on public.products;
create policy "products: anyone reads visible" on public.products for select
  using (coalesce((data->>'visible')::boolean, true) or (select public.has_perm('products')) or (select public.has_perm('stock')) or (select public.has_perm('orders')));
drop policy if exists "products: team writes" on public.products;
create policy "products: team writes" on public.products for all
  using ((select public.has_perm('products')) or (select public.has_perm('stock')))
  with check ((select public.has_perm('products')) or (select public.has_perm('stock')));

drop policy if exists "orders: team reads" on public.orders;
create policy "orders: team reads" on public.orders for select using ((select public.has_perm('orders')) or (select public.has_perm('commission')));
drop policy if exists "orders: team updates" on public.orders;
create policy "orders: team updates" on public.orders for update using ((select public.has_perm('orders'))) with check ((select public.has_perm('orders')));
drop policy if exists "orders: owner deletes" on public.orders;
create policy "orders: owner deletes" on public.orders for delete using ((select public.is_admin()));

drop policy if exists "settings: team writes" on public.settings;
create policy "settings: team writes" on public.settings for all
  using ((select public.has_perm('settings')) or (select public.has_perm('products')))
  with check ((select public.has_perm('settings')) or (select public.has_perm('products')));

drop policy if exists "products_history admin read" on public.products_history;
create policy "products_history admin read" on public.products_history for select using ((select public.has_perm('history')));
drop policy if exists "products_backup admin" on public.products_backup;
create policy "products_backup admin" on public.products_backup for select using ((select public.is_admin()));

drop policy if exists "inv_items read" on public.inv_items;
create policy "inv_items read" on public.inv_items for select using ((select public.inv_role()) is not null);
drop policy if exists "inv_moves read" on public.inv_moves;
create policy "inv_moves read" on public.inv_moves for select using ((select public.inv_role()) is not null);
drop policy if exists "inv_imports read" on public.inv_imports;
create policy "inv_imports read" on public.inv_imports for select using ((select public.inv_role()) = 'owner');
drop policy if exists "inv_users read" on public.inv_users;
create policy "inv_users read" on public.inv_users for select using (user_id = (select auth.uid()) or (select public.inv_role()) = 'owner');

drop policy if exists "panel_users: self or owner reads" on public.panel_users;
create policy "panel_users: self or owner reads" on public.panel_users for select using (user_id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "admins: see self" on public.admins;
create policy "admins: see self" on public.admins for select using (user_id = (select auth.uid()) or (select public.is_admin()));

create index if not exists products_sort_idx on public.products (sort, id);
analyze public.products;
