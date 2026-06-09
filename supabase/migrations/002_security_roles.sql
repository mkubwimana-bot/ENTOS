-- ============================================================
-- SME-OS Migration 002
-- Security, Roles, Permissions, and RLS Foundation
--
-- Creates:
--   - app_users
--   - user_tenants
--   - roles
--   - permissions
--   - role_permissions
--   - user_roles
--   - helper security functions
--   - RLS policies for core platform tables
--
-- No-Docker workflow:
-- Save this file in Cursor, then copy and run it in Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. App Users
-- Application profile table linked to Supabase Auth.
--
-- Supabase Auth stores login/password data in auth.users.
-- app_users stores business-facing profile data.
--
-- Access/VBA analogy:
-- auth.users = login/security table managed by Supabase.
-- app_users = your own user profile table.
-- ------------------------------------------------------------

create table if not exists public.app_users (
  id uuid primary key references auth.users(id) on delete cascade,

  full_name text not null,
  phone text,
  email text not null,

  preferred_language_code text default 'en',

  avatar_url text,

  is_platform_admin boolean not null default false,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz,
  last_login_at timestamptz,

  constraint app_users_email_unique unique (email)
);

create index if not exists idx_app_users_email
on public.app_users (email);

create index if not exists idx_app_users_is_active
on public.app_users (is_active);

create trigger trg_app_users_set_updated_at
before update on public.app_users
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 2. User Tenants
-- Connects users to companies/tenants.
-- One user may later belong to more than one tenant.
-- ------------------------------------------------------------

create table if not exists public.user_tenants (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.app_users(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,

  default_branch_id uuid references public.branches(id) on delete set null,

  membership_status text not null default 'active',

  invited_by uuid references public.app_users(id) on delete set null,
  joined_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint user_tenants_user_tenant_unique
    unique (user_id, tenant_id),

  constraint user_tenants_membership_status_check
    check (membership_status in (
      'invited',
      'active',
      'suspended',
      'removed'
    ))
);

create index if not exists idx_user_tenants_user_id
on public.user_tenants (user_id);

create index if not exists idx_user_tenants_tenant_id
on public.user_tenants (tenant_id);

create index if not exists idx_user_tenants_active_membership
on public.user_tenants (user_id, tenant_id, membership_status);

create trigger trg_user_tenants_set_updated_at
before update on public.user_tenants
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3. Roles
-- Defines roles such as Owner, Manager, Cashier, Storekeeper.
-- tenant_id is nullable:
--   null = global system role template
--   not null = tenant-specific custom role later
-- ------------------------------------------------------------

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid references public.tenants(id) on delete cascade,

  role_code text not null,
  role_name text not null,
  description text,

  is_system_role boolean not null default true,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint roles_role_code_not_blank
    check (length(trim(role_code)) > 0)
);

create unique index if not exists idx_roles_global_role_code_unique
on public.roles (role_code)
where tenant_id is null;

create unique index if not exists idx_roles_tenant_role_code_unique
on public.roles (tenant_id, role_code)
where tenant_id is not null;

create index if not exists idx_roles_tenant_id
on public.roles (tenant_id);

create trigger trg_roles_set_updated_at
before update on public.roles
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 4. Permissions
-- Granular actions that roles may perform.
-- Example:
--   sales.create
--   products.edit
--   reports.view
-- ------------------------------------------------------------

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),

  permission_code text not null,
  module_code text not null,
  description text,
  risk_level text default 'low',

  created_at timestamptz not null default now(),

  constraint permissions_permission_code_unique
    unique (permission_code),

  constraint permissions_risk_level_check
    check (risk_level in (
      'low',
      'medium',
      'high'
    ))
);

create index if not exists idx_permissions_module_code
on public.permissions (module_code);

-- ------------------------------------------------------------
-- 5. Role Permissions
-- Maps roles to permissions.
-- ------------------------------------------------------------

create table if not exists public.role_permissions (
  id uuid primary key default gen_random_uuid(),

  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,

  is_allowed boolean not null default true,

  created_at timestamptz not null default now(),

  constraint role_permissions_role_permission_unique
    unique (role_id, permission_id)
);

create index if not exists idx_role_permissions_role_id
on public.role_permissions (role_id);

create index if not exists idx_role_permissions_permission_id
on public.role_permissions (permission_id);

-- ------------------------------------------------------------
-- 6. User Roles
-- Assigns roles to users inside a tenant.
-- ------------------------------------------------------------

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references public.app_users(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete restrict,

  branch_id uuid references public.branches(id) on delete set null,

  assigned_by uuid references public.app_users(id) on delete set null,
  assigned_at timestamptz not null default now(),

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint user_roles_unique_assignment
    unique (tenant_id, user_id, role_id, branch_id)
);

create index if not exists idx_user_roles_tenant_user
on public.user_roles (tenant_id, user_id);

create index if not exists idx_user_roles_role_id
on public.user_roles (role_id);

create index if not exists idx_user_roles_active
on public.user_roles (tenant_id, user_id, is_active);

create trigger trg_user_roles_set_updated_at
before update on public.user_roles
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 7. Security Helper Functions
-- ------------------------------------------------------------

-- Returns true if the current authenticated user is a platform admin.
create or replace function public.is_platform_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_users au
    where au.id = auth.uid()
      and au.is_platform_admin = true
      and au.is_active = true
  );
$$;

-- Returns true if the current authenticated user belongs to a tenant.
create or replace function public.user_has_tenant_access(target_tenant_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_tenants ut
    join public.app_users au on au.id = ut.user_id
    where ut.user_id = auth.uid()
      and ut.tenant_id = target_tenant_id
      and ut.membership_status = 'active'
      and au.is_active = true
  )
  or public.is_platform_admin();
$$;

-- Returns true if the current authenticated user has a permission inside a tenant.
create or replace function public.user_has_permission(
  target_tenant_id uuid,
  target_permission_code text
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p on p.id = rp.permission_id
    join public.user_tenants ut
      on ut.tenant_id = ur.tenant_id
     and ut.user_id = ur.user_id
    where ur.user_id = auth.uid()
      and ur.tenant_id = target_tenant_id
      and ur.is_active = true
      and r.is_active = true
      and rp.is_allowed = true
      and p.permission_code = target_permission_code
      and ut.membership_status = 'active'
  )
  or public.is_platform_admin();
$$;

-- ------------------------------------------------------------
-- 8. Seed system roles
-- ------------------------------------------------------------

insert into public.roles (
  tenant_id,
  role_code,
  role_name,
  description,
  is_system_role,
  is_active
)
values
  (null, 'owner', 'Owner', 'Full access to company settings, users, data, and billing.', true, true),
  (null, 'manager', 'Manager', 'Manages daily operations, products, sales, payments, stock, and reports.', true, true),
  (null, 'cashier', 'Cashier', 'Creates sales and records customer payments.', true, true),
  (null, 'storekeeper', 'Storekeeper', 'Manages stock checks and stock adjustments.', true, true),
  (null, 'auditor', 'Auditor', 'Read-only access to reports and history.', true, true)
on conflict do nothing;

-- ------------------------------------------------------------
-- 9. Seed permissions
-- ------------------------------------------------------------

insert into public.permissions (
  permission_code,
  module_code,
  description,
  risk_level
)
values
  -- Dashboard / reports
  ('dashboard.view', 'dashboard', 'View main dashboard.', 'low'),
  ('reports.view', 'reports', 'View business reports.', 'low'),
  ('reports.export', 'reports', 'Export reports.', 'medium'),

  -- Tenant / settings
  ('settings.view', 'settings', 'View company settings.', 'medium'),
  ('settings.edit', 'settings', 'Edit company settings.', 'high'),
  ('users.manage', 'security', 'Invite, suspend, and manage users.', 'high'),

  -- Products
  ('products.view', 'products', 'View products and services.', 'low'),
  ('products.create', 'products', 'Create products and services.', 'medium'),
  ('products.edit', 'products', 'Edit products and services.', 'medium'),
  ('products.delete', 'products', 'Delete or deactivate products.', 'high'),

  -- Parties / customers
  ('parties.view', 'parties', 'View customers and other parties.', 'low'),
  ('parties.create', 'parties', 'Create customers and parties.', 'medium'),
  ('parties.edit', 'parties', 'Edit customers and parties.', 'medium'),
  ('parties.delete', 'parties', 'Delete or deactivate parties.', 'high'),

  -- Sales
  ('sales.view', 'sales', 'View sales.', 'low'),
  ('sales.create', 'sales', 'Create sales.', 'medium'),
  ('sales.void', 'sales', 'Void posted sales.', 'high'),

  -- Payments
  ('payments.view', 'payments', 'View payments.', 'low'),
  ('payments.create', 'payments', 'Record payments.', 'medium'),
  ('payments.void', 'payments', 'Void posted payments.', 'high'),

  -- Inventory
  ('inventory.view', 'inventory', 'View stock and stock movements.', 'low'),
  ('inventory.adjust', 'inventory', 'Create stock adjustments.', 'high'),

  -- Mobile / offline
  ('offline.use', 'mobile', 'Use limited offline transaction capture.', 'medium'),
  ('mobile.quick_sale', 'mobile', 'Use mobile quick sale screen.', 'medium'),
  ('mobile.record_payment', 'mobile', 'Record customer payment on mobile.', 'medium'),
  ('mobile.stock_check', 'mobile', 'Check stock on mobile.', 'low'),
  ('mobile.stock_adjust', 'mobile', 'Create stock adjustment on mobile.', 'high'),
  ('sync.review_conflicts', 'mobile', 'Review failed or conflicting sync items.', 'high'),
  ('devices.manage', 'mobile', 'Trust, block, or manage devices.', 'high'),

  -- Credit readiness
  ('credit_readiness.view', 'credit_readiness', 'View credit readiness reports.', 'medium'),
  ('credit_readiness.manage', 'credit_readiness', 'Manage credit readiness consent and scoring.', 'high')
on conflict do nothing;

-- ------------------------------------------------------------
-- 10. Assign default permissions to system roles
-- ------------------------------------------------------------

-- Owner gets all permissions.
insert into public.role_permissions (role_id, permission_id, is_allowed)
select r.id, p.id, true
from public.roles r
cross join public.permissions p
where r.tenant_id is null
  and r.role_code = 'owner'
on conflict do nothing;

-- Manager gets operational permissions, but not billing/settings/user admin.
insert into public.role_permissions (role_id, permission_id, is_allowed)
select r.id, p.id, true
from public.roles r
join public.permissions p
  on p.permission_code in (
    'dashboard.view',
    'reports.view',
    'products.view',
    'products.create',
    'products.edit',
    'parties.view',
    'parties.create',
    'parties.edit',
    'sales.view',
    'sales.create',
    'sales.void',
    'payments.view',
    'payments.create',
    'payments.void',
    'inventory.view',
    'inventory.adjust',
    'offline.use',
    'mobile.quick_sale',
    'mobile.record_payment',
    'mobile.stock_check',
    'mobile.stock_adjust',
    'sync.review_conflicts',
    'devices.manage',
    'credit_readiness.view'
  )
where r.tenant_id is null
  and r.role_code = 'manager'
on conflict do nothing;

-- Cashier.
insert into public.role_permissions (role_id, permission_id, is_allowed)
select r.id, p.id, true
from public.roles r
join public.permissions p
  on p.permission_code in (
    'dashboard.view',
    'products.view',
    'parties.view',
    'parties.create',
    'sales.view',
    'sales.create',
    'payments.view',
    'payments.create',
    'inventory.view',
    'offline.use',
    'mobile.quick_sale',
    'mobile.record_payment',
    'mobile.stock_check'
  )
where r.tenant_id is null
  and r.role_code = 'cashier'
on conflict do nothing;

-- Storekeeper.
insert into public.role_permissions (role_id, permission_id, is_allowed)
select r.id, p.id, true
from public.roles r
join public.permissions p
  on p.permission_code in (
    'dashboard.view',
    'products.view',
    'inventory.view',
    'inventory.adjust',
    'offline.use',
    'mobile.stock_check',
    'mobile.stock_adjust'
  )
where r.tenant_id is null
  and r.role_code = 'storekeeper'
on conflict do nothing;

-- Auditor.
insert into public.role_permissions (role_id, permission_id, is_allowed)
select r.id, p.id, true
from public.roles r
join public.permissions p
  on p.permission_code in (
    'dashboard.view',
    'reports.view',
    'products.view',
    'parties.view',
    'sales.view',
    'payments.view',
    'inventory.view',
    'credit_readiness.view'
  )
where r.tenant_id is null
  and r.role_code = 'auditor'
on conflict do nothing;

-- ------------------------------------------------------------
-- 11. Enable Row-Level Security
-- ------------------------------------------------------------

alter table public.tenants enable row level security;
alter table public.branches enable row level security;
alter table public.warehouses enable row level security;
alter table public.tenant_settings enable row level security;

alter table public.app_users enable row level security;
alter table public.user_tenants enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;

-- ------------------------------------------------------------
-- 12. RLS Policies: app_users
-- ------------------------------------------------------------

drop policy if exists app_users_select_self_or_platform_admin
on public.app_users;

create policy app_users_select_self_or_platform_admin
on public.app_users
for select
using (
  id = auth.uid()
  or public.is_platform_admin()
);

drop policy if exists app_users_update_self
on public.app_users;

create policy app_users_update_self
on public.app_users
for update
using (
  id = auth.uid()
)
with check (
  id = auth.uid()
);

-- Note:
-- app_users insert will usually be handled by a signup trigger later,
-- or by controlled app onboarding logic.

-- ------------------------------------------------------------
-- 13. RLS Policies: user_tenants
-- ------------------------------------------------------------

drop policy if exists user_tenants_select_own_memberships_or_platform_admin
on public.user_tenants;

create policy user_tenants_select_own_memberships_or_platform_admin
on public.user_tenants
for select
using (
  user_id = auth.uid()
  or public.is_platform_admin()
);

-- ------------------------------------------------------------
-- 14. RLS Policies: tenants
-- ------------------------------------------------------------

drop policy if exists tenants_select_if_member
on public.tenants;

create policy tenants_select_if_member
on public.tenants
for select
using (
  public.user_has_tenant_access(id)
);

drop policy if exists tenants_update_if_owner_or_platform_admin
on public.tenants;

create policy tenants_update_if_owner_or_platform_admin
on public.tenants
for update
using (
  public.user_has_permission(id, 'settings.edit')
)
with check (
  public.user_has_permission(id, 'settings.edit')
);

-- ------------------------------------------------------------
-- 15. RLS Policies: branches
-- ------------------------------------------------------------

drop policy if exists branches_select_if_tenant_member
on public.branches;

create policy branches_select_if_tenant_member
on public.branches
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists branches_manage_if_settings_edit
on public.branches;

create policy branches_manage_if_settings_edit
on public.branches
for all
using (
  public.user_has_permission(tenant_id, 'settings.edit')
)
with check (
  public.user_has_permission(tenant_id, 'settings.edit')
);

-- ------------------------------------------------------------
-- 16. RLS Policies: warehouses
-- ------------------------------------------------------------

drop policy if exists warehouses_select_if_tenant_member
on public.warehouses;

create policy warehouses_select_if_tenant_member
on public.warehouses
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists warehouses_manage_if_inventory_adjust_or_settings_edit
on public.warehouses;

create policy warehouses_manage_if_inventory_adjust_or_settings_edit
on public.warehouses
for all
using (
  public.user_has_permission(tenant_id, 'settings.edit')
  or public.user_has_permission(tenant_id, 'inventory.adjust')
)
with check (
  public.user_has_permission(tenant_id, 'settings.edit')
  or public.user_has_permission(tenant_id, 'inventory.adjust')
);

-- ------------------------------------------------------------
-- 17. RLS Policies: tenant_settings
-- ------------------------------------------------------------

drop policy if exists tenant_settings_select_if_settings_view_or_platform_admin
on public.tenant_settings;

create policy tenant_settings_select_if_settings_view_or_platform_admin
on public.tenant_settings
for select
using (
  public.user_has_permission(tenant_id, 'settings.view')
  or public.user_has_permission(tenant_id, 'settings.edit')
);

drop policy if exists tenant_settings_manage_if_settings_edit
on public.tenant_settings;

create policy tenant_settings_manage_if_settings_edit
on public.tenant_settings
for all
using (
  public.user_has_permission(tenant_id, 'settings.edit')
)
with check (
  public.user_has_permission(tenant_id, 'settings.edit')
);

-- ------------------------------------------------------------
-- 18. RLS Policies: roles and permissions
-- ------------------------------------------------------------

drop policy if exists roles_select_system_or_tenant_roles
on public.roles;

create policy roles_select_system_or_tenant_roles
on public.roles
for select
using (
  tenant_id is null
  or public.user_has_tenant_access(tenant_id)
);

drop policy if exists permissions_select_all_authenticated
on public.permissions;

create policy permissions_select_all_authenticated
on public.permissions
for select
using (
  auth.role() = 'authenticated'
  or public.is_platform_admin()
);

drop policy if exists role_permissions_select_all_authenticated
on public.role_permissions;

create policy role_permissions_select_all_authenticated
on public.role_permissions
for select
using (
  auth.role() = 'authenticated'
  or public.is_platform_admin()
);

-- ------------------------------------------------------------
-- 19. RLS Policies: user_roles
-- ------------------------------------------------------------

drop policy if exists user_roles_select_if_tenant_member
on public.user_roles;

create policy user_roles_select_if_tenant_member
on public.user_roles
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists user_roles_manage_if_users_manage
on public.user_roles;

create policy user_roles_manage_if_users_manage
on public.user_roles
for all
using (
  public.user_has_permission(tenant_id, 'users.manage')
)
with check (
  public.user_has_permission(tenant_id, 'users.manage')
);

-- ------------------------------------------------------------
-- End of Migration 002
-- ------------------------------------------------------------