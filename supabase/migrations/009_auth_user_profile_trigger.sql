-- ============================================================
-- SME-OS Migration 009
-- Auto-create app_users profile on Supabase Auth signup
--
-- Creates:
--   - public.handle_auth_user_created()
--   - trigger on auth.users after insert
--
-- Purpose:
-- Ensure every new auth login has a matching app_users row so app-side
-- profile updates (e.g. last_login_at) work immediately after signup.
-- Also creates a starter tenant + membership + owner role assignment so
-- new signups are not blocked by tenant-level RLS on first login.
-- ============================================================

create or replace function public.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text;
  v_business_name text;
  v_tenant_id uuid;
  v_default_branch_id uuid;
  v_owner_role_id uuid;
  v_tenant_code text;
begin
  v_full_name := nullif(
    trim(
      coalesce(
        new.raw_user_meta_data ->> 'full_name',
        new.raw_user_meta_data ->> 'name',
        ''
      )
    ),
    ''
  );

  if v_full_name is null then
    v_full_name := split_part(coalesce(new.email, ''), '@', 1);
  end if;

  v_business_name := nullif(
    trim(
      coalesce(
        new.raw_user_meta_data ->> 'business_name',
        new.raw_user_meta_data ->> 'company_name',
        ''
      )
    ),
    ''
  );
  if v_business_name is null then
    v_business_name := v_full_name || ' Business';
  end if;

  insert into public.app_users (
    id,
    full_name,
    email,
    preferred_language_code,
    is_active
  )
  values (
    new.id,
    v_full_name,
    coalesce(new.email, ''),
    'en',
    true
  )
  on conflict (id) do update
  set
    full_name = excluded.full_name,
    email = excluded.email,
    is_active = true;

  -- Keep SQL-seeded synthetic dev accounts on the existing manual setup path.
  if coalesce(new.email, '') like '%@smeos.test' then
    return new;
  end if;

  -- If this user already belongs to a tenant, keep existing setup.
  if exists (
    select 1
    from public.user_tenants ut
    where ut.user_id = new.id
  ) then
    return new;
  end if;

  v_tenant_code := 'TEN-' || substring(replace(new.id::text, '-', '') from 1 for 8);

  insert into public.tenants (
    tenant_code,
    legal_name,
    trading_name,
    onboarding_status,
    created_by
  )
  values (
    v_tenant_code,
    v_business_name,
    v_business_name,
    'setup_started',
    new.id
  )
  returning id into v_tenant_id;

  -- Creates default branch/warehouse/settings/number sequences/starter category.
  perform public.initialize_tenant_defaults(v_tenant_id);

  select b.id
    into v_default_branch_id
  from public.branches b
  where b.tenant_id = v_tenant_id
    and b.is_default = true
  limit 1;

  insert into public.user_tenants (
    user_id,
    tenant_id,
    default_branch_id,
    membership_status,
    joined_at
  )
  values (
    new.id,
    v_tenant_id,
    v_default_branch_id,
    'active',
    now()
  )
  on conflict (user_id, tenant_id) do nothing;

  select r.id
    into v_owner_role_id
  from public.roles r
  where r.tenant_id is null
    and r.role_code = 'owner'
  limit 1;

  if v_owner_role_id is not null then
    insert into public.user_roles (
      tenant_id,
      user_id,
      role_id,
      branch_id,
      assigned_by,
      is_active
    )
    values (
      v_tenant_id,
      new.id,
      v_owner_role_id,
      v_default_branch_id,
      new.id,
      true
    )
    on conflict (tenant_id, user_id, role_id, branch_id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_auth_users_create_app_user on auth.users;

create trigger trg_auth_users_create_app_user
after insert on auth.users
for each row
execute function public.handle_auth_user_created();

-- ------------------------------------------------------------
-- End of Migration 009
-- ------------------------------------------------------------
