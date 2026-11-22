# Said Nazzal Trading – online shop

Static shop page (`index.html`) backed by Supabase (database, admin login, photo storage).

- `index.html` – public coming-soon page
- `shop-o6bwd2u8fe.html` – the shop (private link, not indexed) and its control panel (`shop-o6bwd2u8fe.html#admin`)
- `config.js` – Supabase project URL and public anon key
- `photos/` – product and banner photos
- `supabase/` – database setup: run 1, 2, 3 in order in the Supabase SQL Editor

Hosting: Vercel, framework preset "Other", no build step. Every push to `main` deploys.
