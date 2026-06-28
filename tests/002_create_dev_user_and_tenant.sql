-- ============================================================
-- SME-OS Dev Setup 002
-- Create a development login (auth user), tenant, app user profile,
-- membership, owner role, and starter data.
--
-- Self-contained and repeatable: running it again reuses the same dev
-- user (matched by email) instead of creating duplicates.
--
-- Run this in the Supabase SQL editor. Adjust the dev email/password
-- below if you like. Use ONLY synthetic (fake) credentials in development.
--
-- After running, log in to the app with v_dev_email / v_dev_password.
-- ============================================================

-- pgcrypto provides crypt()/gen_salt() used to hash the dev password.
create extension if not exists pgcrypto with schema extensions;
set search_path to public, extensions;

do $$
declare
  -- Development login credentials (synthetic / fake on purpose).
  v_dev_email text := 'dev@smeos.test';
  v_dev_password text := 'DevPassword123!';

  v_auth_user_id uuid;
  v_tenant_id uuid;
  v_branch_id uuid;
  v_owner_role_id uuid;
begin
  -- ----------------------------------------------------------
  -- 0. Create the Supabase Auth login if it does not exist.
  --    auth.users holds the email + hashed password.
  -- ----------------------------------------------------------

  select id into v_auth_user_id
  from auth.users
  where email = v_dev_email;

  if v_auth_user_id is null then
    v_auth_user_id := gen_random_uuid();

    insert into auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      recovery_token,
      email_change_token_new,
      email_change
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      v_auth_user_id,
      'authenticated',
      'authenticated',
      v_dev_email,
      crypt(v_dev_password, gen_salt('bf')),
      now(), -- email confirmed, so login works immediately
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      '', '', '', ''
    );

    -- GoTrue requires a matching identity row for email logins.
    insert into auth.identities (
      provider_id,
      user_id,
      identity_data,
      provider,
      last_sign_in_at,
      created_at,
      updated_at
    )
    values (
      v_auth_user_id::text,
      v_auth_user_id,
      jsonb_build_object('sub', v_auth_user_id::text, 'email', v_dev_email),
      'email',
      now(),
      now(),
      now()
    );
  end if;

  -- ----------------------------------------------------------
  -- 1. Create or update app user profile
  -- ----------------------------------------------------------

  insert into public.app_users (
    id,
    full_name,
    phone,
    email,
    preferred_language_code,
    is_platform_admin,
    is_active
  )
  values (
    v_auth_user_id,
    'Development Owner',
    null,
    v_dev_email,
    'en',
    false,
    true
  )
  on conflict (id) do update
  set
    full_name = excluded.full_name,
    email = excluded.email,
    preferred_language_code = excluded.preferred_language_code,
    is_active = true;

  -- ----------------------------------------------------------
  -- 2. Create development tenant
  -- ----------------------------------------------------------

  insert into public.tenants (
    tenant_code,
    legal_name,
    trading_name,
    business_type,
    subscription_status,
    onboarding_status,
    is_active
  )
  values (
    'DEV001',
    'SME-OS Development Ltd',
    'SME-OS Dev Shop',
    'retail',
    'trial',
    'active',
    true
  )
  on conflict (tenant_code) do update
  set
    legal_name = excluded.legal_name,
    trading_name = excluded.trading_name,
    business_type = excluded.business_type,
    subscription_status = excluded.subscription_status,
    onboarding_status = excluded.onboarding_status,
    is_active = true
  returning id into v_tenant_id;

  -- ----------------------------------------------------------
  -- 3. Initialize branch, warehouse, settings, sequences
  -- ----------------------------------------------------------

  perform public.initialize_tenant_defaults(v_tenant_id);

  select id
  into v_branch_id
  from public.branches
  where tenant_id = v_tenant_id
    and branch_code = 'MAIN';

  -- ----------------------------------------------------------
  -- 4. Create tenant membership
  -- ----------------------------------------------------------

  insert into public.user_tenants (
    user_id,
    tenant_id,
    default_branch_id,
    membership_status,
    joined_at
  )
  values (
    v_auth_user_id,
    v_tenant_id,
    v_branch_id,
    'active',
    now()
  )
  on conflict (user_id, tenant_id) do update
  set
    default_branch_id = excluded.default_branch_id,
    membership_status = 'active',
    joined_at = coalesce(public.user_tenants.joined_at, now());

  -- ----------------------------------------------------------
  -- 5. Assign Owner role
  -- ----------------------------------------------------------

  select id
  into v_owner_role_id
  from public.roles
  where tenant_id is null
    and role_code = 'owner';

  if v_owner_role_id is null then
    raise exception 'Owner role not found. Check migration 002.';
  end if;

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
    v_auth_user_id,
    v_owner_role_id,
    v_branch_id,
    v_auth_user_id,
    true
  )
  on conflict (tenant_id, user_id, role_id, branch_id) do update
  set
    is_active = true;

  -- ----------------------------------------------------------
  -- 6. Create starter customer
  -- ----------------------------------------------------------

  insert into public.parties (
    tenant_id,
    party_code,
    party_name,
    party_kind,
    primary_phone,
    customer_credit_limit,
    customer_credit_terms_days,
    internal_credit_rating,
    is_credit_eligible,
    opening_balance,
    status,
    created_by
  )
  values (
    v_tenant_id,
    'CUST-DEV-001',
    'Development Customer',
    'individual',
    '+250780000001',
    100000,
    30,
    'good',
    true,
    0,
    'active',
    v_auth_user_id
  )
  on conflict (tenant_id, party_code) do nothing;

  insert into public.party_type_links (
    tenant_id,
    party_id,
    party_type_id,
    is_primary
  )
  select
    v_tenant_id,
    p.id,
    pt.id,
    true
  from public.parties p
  join public.party_types pt on pt.type_code = 'customer'
  where p.tenant_id = v_tenant_id
    and p.party_code = 'CUST-DEV-001'
  on conflict (party_id, party_type_id) do nothing;

  -- ----------------------------------------------------------
  -- 7. Create starter product
  -- ----------------------------------------------------------

  insert into public.products (
    tenant_id,
    product_code,
    product_name,
    product_type_id,
    category_id,
    base_unit_id,
    cost_price,
    selling_price,
    is_inventory_tracked,
    reorder_level,
    reorder_quantity,
    allow_negative_stock,
    status,
    created_by
  )
  select
    v_tenant_id,
    'PROD-DEV-001',
    'Development Bottled Water',
    pt.id,
    pc.id,
    pu.id,
    300,
    500,
    true,
    10,
    20,
    false,
    'active',
    v_auth_user_id
  from public.product_types pt
  join public.product_categories pc
    on pc.tenant_id = v_tenant_id
   and pc.category_name = 'General'
  join public.product_units pu
    on pu.tenant_id is null
   and pu.unit_code = 'pcs'
  where pt.type_code = 'stock_item'
  on conflict (tenant_id, product_code) do nothing;

  -- ----------------------------------------------------------
  -- 8. Add starter opening stock
  -- ----------------------------------------------------------

  insert into public.stock_movements (
    tenant_id,
    branch_id,
    warehouse_id,
    product_id,
    movement_date,
    movement_type,
    quantity_in,
    quantity_out,
    unit_cost,
    total_cost,
    reference_number,
    reason,
    created_by
  )
  select
    v_tenant_id,
    b.id,
    w.id,
    p.id,
    current_date,
    'opening',
    100,
    0,
    300,
    30000,
    'DEV-OPENING-STOCK',
    'Development opening stock',
    v_auth_user_id
  from public.branches b
  join public.warehouses w
    on w.tenant_id = b.tenant_id
   and w.branch_id = b.id
  join public.products p
    on p.tenant_id = b.tenant_id
   and p.product_code = 'PROD-DEV-001'
  where b.tenant_id = v_tenant_id
    and b.branch_code = 'MAIN'
    and not exists (
      select 1
      from public.stock_movements sm
      where sm.tenant_id = v_tenant_id
        and sm.reference_number = 'DEV-OPENING-STOCK'
    );

  raise notice 'Dev setup complete. Login: % | Tenant: % | Branch: % | User: %',
    v_dev_email, v_tenant_id, v_branch_id, v_auth_user_id;
end $$;