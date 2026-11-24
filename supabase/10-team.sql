-- Said Nazzal – panel users with permissions. Run once in Supabase → SQL Editor, after files 1–9. Safe to run again.
--
-- Owners  = rows in public.admins (everything, including users, markup and commission %).
-- Team    = rows in public.panel_users with a list of permissions:
--   orders      see and update orders
--   products    products, categories, front page (banner) and photos
--   stock       the shop panel's stock tab (quantities / codes)
--   history     product change history
--   commission  the monthly commission report (read only)
--   settings    delivery areas, WhatsApp, currency (not markup / commission %)
-- The database enforces these, so hiding a tab is never the only protection.

create table if not exists public.panel_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text,
  perms text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.panel_users enable row level security;
drop policy if exists "panel_users: self or owner reads" on public.panel_users;
create policy "panel_users: self or owner reads" on public.panel_users for select using (user_id = (select auth.uid()) or (select public.is_admin()));
-- written only by the server function (secret key), never from the browser

create or replace function public.has_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (select 1 from public.panel_users u where u.user_id = auth.uid() and u.active and p = any(u.perms));
$$;

-- products: everyone reads visible ones; team with products/stock/orders rights reads all; products/stock may write
drop policy if exists "products: anyone reads visible" on public.products;
create policy "products: anyone reads visible" on public.products for select
  using (coalesce((data->>'visible')::boolean, true) or (select public.has_perm('products')) or (select public.has_perm('stock')) or (select public.has_perm('orders')));
drop policy if exists "products: admin writes" on public.products;
drop policy if exists "products: team writes" on public.products;
create policy "products: team writes" on public.products for all
  using ((select public.has_perm('products')) or (select public.has_perm('stock'))) with check ((select public.has_perm('products')) or (select public.has_perm('stock')));

-- orders
drop policy if exists "orders: admin only" on public.orders;
drop policy if exists "orders: team reads" on public.orders;
drop policy if exists "orders: team updates" on public.orders;
drop policy if exists "orders: owner deletes" on public.orders;
create policy "orders: team reads" on public.orders for select using ((select public.has_perm('orders')) or (select public.has_perm('commission')));
create policy "orders: team updates" on public.orders for update using ((select public.has_perm('orders'))) with check ((select public.has_perm('orders')));
create policy "orders: owner deletes" on public.orders for delete using ((select public.is_admin()));

-- settings: products right may change banner + categories; settings right may change the rest except markup/commission
drop policy if exists "settings: admin writes" on public.settings;
drop policy if exists "settings: team writes" on public.settings;
create policy "settings: team writes" on public.settings for all
  using ((select public.has_perm('settings')) or (select public.has_perm('products'))) with check ((select public.has_perm('settings')) or (select public.has_perm('products')));
create or replace function public.settings_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text; allowed text[];
begin
  if public.is_admin() or auth.uid() is null then return new; end if;   -- owners and the database itself
  allowed := array[]::text[];
  if public.has_perm('products') then allowed := allowed || array['banner','categories']; end if;
  if public.has_perm('settings') then allowed := allowed || array['store','store_en','whatsapp','email','freeOver','zones','waMode','usdRate','usdAuto']; end if;
  for k in select key from jsonb_each(old.data) union select key from jsonb_each(new.data) loop
    if (old.data->k) is distinct from (new.data->k) and not (k = any(allowed)) then
      raise exception 'not_allowed:%', k;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists settings_guard on public.settings;
create trigger settings_guard before update on public.settings for each row execute function public.settings_guard();

-- history and backups
drop policy if exists "products_history admin read" on public.products_history;
create policy "products_history admin read" on public.products_history for select using ((select public.has_perm('history')));

-- photos
drop policy if exists "photos: admin uploads" on storage.objects;
create policy "photos: admin uploads" on storage.objects for insert with check (bucket_id = 'photos' and (select public.has_perm('products')));
drop policy if exists "photos: admin changes" on storage.objects;
create policy "photos: admin changes" on storage.objects for update using (bucket_id = 'photos' and (select public.has_perm('products')));
drop policy if exists "photos: admin deletes" on storage.objects;
create policy "photos: admin deletes" on storage.objects for delete using (bucket_id = 'photos' and (select public.has_perm('products')));

-- owners can see who the other owners are (for the users screen)
drop policy if exists "admins: see self" on public.admins;
create policy "admins: see self" on public.admins for select using (user_id = (select auth.uid()) or (select public.is_admin()));

-- linking website sizes to Trust items: stock-app owner who can edit products
create or replace function public.inv_link(pid text, vi int, sku text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p jsonb;
begin
  if public.inv_role() is distinct from 'owner' or not public.has_perm('products') then raise exception 'owner_only'; end if;
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
