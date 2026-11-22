-- Said Nazzal Trading – online shop database
-- Paste this whole file into Supabase → SQL Editor → New query → Run.

-- ---------- tables ----------
create table if not exists public.settings (
  id int primary key default 1 check (id = 1),
  data jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id text primary key,
  sort int not null default 0,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

create sequence if not exists public.order_no start 1001;

create table if not exists public.orders (
  id bigint generated always as identity primary key,
  code text not null unique,
  created_at timestamptz not null default now(),
  status text not null default 'new' check (status in ('new','ok','ship','done','cancel')),
  customer jsonb not null,
  items jsonb not null,
  sub numeric(10,3) not null,
  fee numeric(10,3) not null,
  total numeric(10,3) not null
);

-- people allowed into the control panel
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------- security rules ----------
alter table public.settings enable row level security;
alter table public.products enable row level security;
alter table public.orders   enable row level security;
alter table public.admins   enable row level security;

drop policy if exists "settings: anyone reads" on public.settings;
create policy "settings: anyone reads" on public.settings for select using (true);
drop policy if exists "settings: admin writes" on public.settings;
create policy "settings: admin writes" on public.settings for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "products: anyone reads visible" on public.products;
create policy "products: anyone reads visible" on public.products for select
  using (coalesce((data->>'visible')::boolean, true) or public.is_admin());
drop policy if exists "products: admin writes" on public.products;
create policy "products: admin writes" on public.products for all using (public.is_admin()) with check (public.is_admin());

-- orders: customers never read or write the table directly; they go through place_order()
drop policy if exists "orders: admin only" on public.orders;
create policy "orders: admin only" on public.orders for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admins: see self" on public.admins;
create policy "admins: see self" on public.admins for select using (user_id = auth.uid());

-- ---------- placing an order ----------
-- Prices, delivery fee and totals are worked out here on the server from the
-- product list, so nobody can change a price in their browser.
create or replace function public.place_order(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; z jsonb; it jsonb; p jsonb; v jsonb;
  pid text; vi int; q int; price numeric; stock numeric;
  lines jsonb := '[]'::jsonb; subtotal numeric := 0; fee numeric := 0;
  intl boolean; free_over numeric; c jsonb; new_code text;
begin
  select data into s from settings where id = 1;
  z := s->'zones'->((payload->>'zone')::int);
  if z is null then raise exception 'bad_zone'; end if;
  intl := coalesce((z->>'intl')::boolean, false);

  c := payload->'customer';
  if coalesce(trim(c->>'name'),'') = '' or coalesce(trim(c->>'phone'),'') = '' then raise exception 'missing_contact'; end if;
  if jsonb_typeof(payload->'items') <> 'array' or jsonb_array_length(payload->'items') = 0
     or jsonb_array_length(payload->'items') > 100 then raise exception 'bad_items'; end if;

  for it in select * from jsonb_array_elements(payload->'items') loop
    pid := it->>'pid'; vi := (it->>'vi')::int; q := (it->>'q')::int;
    if q is null or q < 1 or q > 100000 then raise exception 'bad_qty'; end if;
    select data into p from products where id = pid for update;
    if p is null or not coalesce((p->>'visible')::boolean, true) or coalesce((p->>'ask')::boolean, false) then
      raise exception 'unavailable:%', pid; end if;
    v := p->'vars'->vi;
    if v is null then raise exception 'bad_variant:%', pid; end if;
    price := (v->>'price')::numeric;
    stock := nullif(v->>'stock','')::numeric;
    if stock is not null then
      if stock < q then raise exception 'out_of_stock:%', pid; end if;
      update products set data = jsonb_set(data, array['vars', vi::text, 'stock'], to_jsonb(stock - q)), updated_at = now() where id = pid;
    end if;
    subtotal := subtotal + price * q;
    lines := lines || jsonb_build_object('pid', pid, 'name', p->>'name', 'v', v->>'label', 'price', price, 'q', q);
  end loop;

  free_over := nullif(s->>'freeOver','')::numeric;
  if intl then fee := 0;
  elsif free_over is not null and free_over > 0 and subtotal >= free_over then fee := 0;
  else fee := coalesce((z->>'fee')::numeric, 0); end if;

  new_code := 'SN-' || nextval('order_no');
  insert into orders (code, customer, items, sub, fee, total)
  values (new_code,
          jsonb_build_object('name', c->>'name', 'phone', c->>'phone', 'addr', c->>'addr', 'note', c->>'note',
                             'country', c->>'country', 'city', c->>'city', 'lang', c->>'lang',
                             'zone', z->>'name', 'intl', intl),
          lines, subtotal, fee, subtotal + fee);
  return jsonb_build_object('code', new_code, 'sub', subtotal, 'fee', fee, 'total', subtotal + fee, 'intl', intl);
end $$;

revoke all on function public.place_order(jsonb) from public;
grant execute on function public.place_order(jsonb) to anon, authenticated;

-- ---------- photo storage ----------
insert into storage.buckets (id, name, public) values ('photos', 'photos', true)
on conflict (id) do nothing;

drop policy if exists "photos: anyone reads" on storage.objects;
create policy "photos: anyone reads" on storage.objects for select using (bucket_id = 'photos');
drop policy if exists "photos: admin uploads" on storage.objects;
create policy "photos: admin uploads" on storage.objects for insert with check (bucket_id = 'photos' and public.is_admin());
drop policy if exists "photos: admin changes" on storage.objects;
create policy "photos: admin changes" on storage.objects for update using (bucket_id = 'photos' and public.is_admin());
drop policy if exists "photos: admin deletes" on storage.objects;
create policy "photos: admin deletes" on storage.objects for delete using (bucket_id = 'photos' and public.is_admin());
