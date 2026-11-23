-- QA fixes: run once in Supabase → SQL Editor (after files 1–3). Includes everything in 4-stock.sql,
-- so if you haven't run 4 yet you can run just this one. Safe to run more than once.
-- 1) Orders remember exactly which size/colour was bought; cancelling returns stock, un-cancelling takes it again.
-- 2) Spam protection: limits on text length, max 5 orders per phone in 10 minutes, max 40 orders per 10 minutes overall.
-- 3) A size number below 0 is rejected.

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
    stock := nullif(v->>'stock','')::numeric;
    if stock is not null then
      if stock < q then raise exception 'out_of_stock:%', pid; end if;
      update products set data = jsonb_set(data, array['vars', vi::text, 'stock'], to_jsonb(stock - q)), updated_at = now() where id = pid;
    end if;
    subtotal := subtotal + price * q;
    lines := lines || jsonb_build_object('pid', pid, 'vi', vi, 'sku', v->>'sku', 'name', p->>'name', 'v', v->>'label', 'price', price, 'q', q);
  end loop;

  free_over := nullif(s->>'freeOver','')::numeric;
  if intl then fee := 0;
  elsif free_over is not null and free_over > 0 and subtotal >= free_over then fee := 0;
  else fee := coalesce((z->>'fee')::numeric, 0); end if;

  new_code := 'SN-' || nextval('order_no');
  insert into orders (code, customer, items, sub, fee, total)
  values (new_code,
          jsonb_build_object('name', trim(c->>'name'), 'phone', c->>'phone', 'addr', c->>'addr', 'note', c->>'note',
                             'country', c->>'country', 'city', c->>'city', 'lang', c->>'lang',
                             'zone', z->>'name', 'intl', intl),
          lines, subtotal, fee, subtotal + fee);
  return jsonb_build_object('code', new_code, 'sub', subtotal, 'fee', fee, 'total', subtotal + fee, 'intl', intl);
end $$;

create or replace function public.order_stock_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare it jsonb; p jsonb; vi int; q int; stock numeric; dir int;
begin
  if new.status = 'cancel' and old.status <> 'cancel' then dir := 1;
  elsif old.status = 'cancel' and new.status <> 'cancel' then dir := -1;
  else return new; end if;
  for it in select * from jsonb_array_elements(new.items) loop
    select data into p from products where id = it->>'pid' for update;
    if p is null then continue; end if;
    vi := (it->>'vi')::int;
    if vi is null then  -- older orders: find the size by its name
      select (e.ord - 1)::int into vi from jsonb_array_elements(p->'vars') with ordinality e(v, ord)
       where e.v->>'label' = it->>'v' limit 1;
    end if;
    if vi is null or p->'vars'->vi is null then continue; end if;
    stock := nullif(p->'vars'->vi->>'stock','')::numeric;
    if stock is null then continue; end if;
    q := (it->>'q')::int;
    update products set data = jsonb_set(data, array['vars', vi::text, 'stock'], to_jsonb(greatest(stock + dir * q, 0))), updated_at = now()
     where id = it->>'pid';
  end loop;
  return new;
end $$;

drop trigger if exists orders_stock_on_status on public.orders;
create trigger orders_stock_on_status after update of status on public.orders
  for each row execute function public.order_stock_on_status();

create index if not exists orders_created_idx on public.orders (created_at);
