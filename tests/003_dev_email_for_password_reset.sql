-- ============================================================
-- SME-OS Dev Setup 003
-- Point the dev login at a REAL email so password-reset emails work.
--
-- Supabase Auth rejects @*.test when sending recovery mail. The dev user
-- created by 002_create_dev_user_and_tenant.sql can still sign in, but
-- forgot-password will fail until the auth email is a deliverable address.
--
-- 1. Set v_new_email below to an inbox you can open on your phone.
-- 2. Run this once in the Supabase SQL editor.
-- 3. Log in with v_new_email / DevPassword123!
-- 4. Test Forgot password in the app.
-- ============================================================

do $$
declare
  v_old_email text := 'dev@smeos.test';
  v_new_email text := 'YOUR_REAL_EMAIL@gmail.com'; -- CHANGE ME
  v_user_id uuid;
begin
  if v_new_email = 'YOUR_REAL_EMAIL@gmail.com' then
    raise exception 'Set v_new_email to your real inbox before running.';
  end if;

  select id into v_user_id
  from auth.users
  where email = v_old_email;

  if v_user_id is null then
    raise exception 'Dev user % not found. Run 002_create_dev_user_and_tenant.sql first.', v_old_email;
  end if;

  update auth.users
  set email = v_new_email,
      updated_at = now()
  where id = v_user_id;

  update auth.identities
  set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_new_email)),
      updated_at = now()
  where user_id = v_user_id
    and provider = 'email';

  update public.app_users
  set email = v_new_email
  where id = v_user_id;

  raise notice 'Dev login email updated: % -> %. Password unchanged (DevPassword123!).', v_old_email, v_new_email;
end $$;
