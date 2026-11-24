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
