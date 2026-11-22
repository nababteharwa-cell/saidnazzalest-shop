-- Run this AFTER you have created your login in Supabase → Authentication → Users → Add user.
-- It gives that login access to the control panel.
insert into public.admins (user_id)
select id from auth.users where email = 'info@saidnazzalest.com'
on conflict do nothing;
-- To add a staff member later, run the same lines with their email.
