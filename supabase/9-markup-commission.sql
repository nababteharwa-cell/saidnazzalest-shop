-- Said Nazzal – online price markup and the monthly commission report. Run once in Supabase → SQL Editor, after files 6–8.
-- Safe to run again. NOTE: running it raises online prices to Trust price + 5% straight away (change the % in the panel → Settings).
--
-- Settings (panel → الإعدادات):  markup     = % added to the Trust selling price for the website (default 5)
--                                 commission = % of online sales paid as commission (default 1)
-- Each online order line keeps "base" (the Trust price at the time) next to "price" (the online price),
-- so the monthly report shows the exact difference.

create or replace function public.round5(x numeric) returns numeric
language sql immutable as $$ select round(x / 0.005) * 0.005 $$;   -- nearest 5 fils

create or replace function public.web_stock_fix(d jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; v jsonb; q numeric; pr numeric; mk numeric;
begin
  if d->'vars' is null or jsonb_typeof(d->'vars') <> 'array' then return d; end if;
  select coalesce(nullif(data->>'markup','')::numeric, 0) into mk from settings where id = 1;
  mk := coalesce(mk, 0);
  for v in select value from jsonb_array_elements(d->'vars') loop
    q := null; pr := null;
    if coalesce(v->>'sku','') <> '' then
      select greatest(floor(i.qty), 0), i.price into q, pr from inv_items i
       where i.barcode = trim(v->>'sku') or i.code = trim(v->>'sku')
       order by (i.barcode = trim(v->>'sku')) desc limit 1;   -- a barcode match wins over a Trust code
    end if;
    if q is not null then
      v := jsonb_set(v, '{stock}', to_jsonb(q));
      if pr is not null and pr > 0 then v := jsonb_set(v, '{price}', to_jsonb(public.round5(pr * (1 + mk / 100)))); end if;
    end if;
    out := out || jsonb_build_array(v);
  end loop;
  return jsonb_set(d, '{vars}', out);
end $$;

-- when the markup changes in Settings, every linked product is re-priced
create or replace function public.settings_markup_refresh() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (old.data->>'markup') is distinct from (new.data->>'markup') then
    perform set_config('hist.src', 'تغيير نسبة الزيادة', true);
    update products set data = data, updated_at = now() where id is not null;
    perform set_config('hist.src', '', true);
  end if;
  return null;
end $$;
drop trigger if exists settings_markup_refresh on public.settings;
create trigger settings_markup_refresh after update on public.settings
  for each row execute function public.settings_markup_refresh();

-- orders remember the Trust price next to the online price
create or replace function public.place_order(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s jsonb; z jsonb; it jsonb; p jsonb; v jsonb;
  pid text; vi int; q int; price numeric; stock numeric; inv bigint; iq numeric; bp numeric; mk numeric;
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
    lines := lines || jsonb_build_object('pid', pid, 'vi', vi, 'sku', v->>'sku', 'inv', inv, 'name', p->>'name', 'v', v->>'label', 'price', price, 'base', bp, 'q', q);
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

-- defaults: 5% markup, 1% commission (only if not set yet)
update public.settings set data = data || '{"markup": 5}'::jsonb where id = 1 and not (data ? 'markup');
update public.settings set data = data || '{"commission": 1}'::jsonb where id = 1 and not (data ? 'commission');
