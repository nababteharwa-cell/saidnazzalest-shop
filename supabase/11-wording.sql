-- Said Nazzal – product descriptions addressed to a man (standard form). Run once in Supabase → SQL Editor. Safe to run again.
update public.products
   set data = jsonb_set(data, '{desc}', to_jsonb(replace(data->>'desc', 'اختاري الشكل وشوفي صورته', 'اختر الشكل وشوف صورته'))),
       updated_at = now()
 where data->>'desc' like '%اختاري الشكل وشوفي صورته%';
