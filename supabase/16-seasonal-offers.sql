-- 16) Seasonal offers: a discount (%) during a season, applied by the shop page and by place_order.
-- Run once in Supabase → SQL Editor, after 15-count-by-category.sql.
--
-- Seasons are kept in settings.seasons (edited in the shop dashboard → «العروض الموسمية»):
--   {key, name, from: 'YYYY-MM-DD', to: 'YYYY-MM-DD', on: true, off: 15, tag: 'رمضان', pick: {category: '*' | [families]} | {'*': '*'}}
-- A product gets the biggest discount of the published seasons running today (Amman time) that include it.

create or replace function public.shop_offer(p jsonb, s jsonb default null) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(max(least(greatest((x->>'off')::numeric, 0), 90)), 0)
    from jsonb_array_elements(case when jsonb_typeof(coalesce(s, (select data from settings where id = 1))->'seasons') = 'array'
                                   then coalesce(s, (select data from settings where id = 1))->'seasons' else '[]'::jsonb end) x
   where coalesce((x->>'on')::boolean, false)
     and coalesce(x->>'off', '') ~ '^[0-9]+(\.[0-9]+)?$' and (x->>'off')::numeric > 0
     and coalesce(x->>'from', '') ~ '^\d{4}-\d{2}-\d{2}$' and coalesce(x->>'to', '') ~ '^\d{4}-\d{2}-\d{2}$'
     and (now() at time zone 'Asia/Amman')::date between (x->>'from')::date and (x->>'to')::date
     and (   x->'pick'->>'*' = '*'
          or x->'pick'->>(p->>'cat') = '*'
          or (jsonb_typeof(x->'pick'->(p->>'cat')) = 'array' and x->'pick'->(p->>'cat') ? coalesce(p->>'sub', ''))
          or (coalesce(x->>'tag', '') <> '' and jsonb_typeof(p->'tags') = 'array' and p->'tags' ? (x->>'tag')))
$$;
revoke all on function public.shop_offer(jsonb, jsonb) from public;

create or replace function public.place_order(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; z jsonb; it jsonb; p jsonb; v jsonb;
  pid text; vi int; q int; price numeric; was numeric; off numeric; stock numeric; inv bigint; iq numeric; bp numeric; mk numeric;
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
    off := public.shop_offer(p, s);
    was := price;
    if off > 0 then price := round(price * (1 - off / 100), 3); end if;
    inv := public.inv_item_for_sku(v->>'sku');
    if inv is not null then
      select i.qty, i.price into iq, bp from inv_items i where i.id = inv for update;
      if floor(iq) < q then raise exception 'out_of_stock:%', pid; end if;
      insert into inv_moves (item_id, delta, kind, channel, ref, unit_price, by_name)
      values (inv, -q, 'online_sale', 'website', new_code, price, 'website');
    else
      bp := null;
      stock := nullif(v->>'stock','')::numeric;
      if stock is not null then
        if stock < q then raise exception 'out_of_stock:%', pid; end if;
        update products set data = jsonb_set(data, array['vars', vi::text, 'stock'], to_jsonb(stock - q)), updated_at = now() where id = pid;
      end if;
    end if;
    subtotal := subtotal + price * q;
    lines := lines || (jsonb_build_object('pid', pid, 'vi', vi, 'sku', v->>'sku', 'inv', inv, 'name', p->>'name', 'v', v->>'label', 'price', price, 'base', bp, 'q', q)
             || case when off > 0 then jsonb_build_object('was', was, 'off', off) else '{}'::jsonb end);
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

-- The shop shows discounted prices only when the catalogue says the database applies them (offersReady).
create or replace function public.shop_catalog() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'settings', (select data || '{"offersReady": true}'::jsonb from settings where id = 1),
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
