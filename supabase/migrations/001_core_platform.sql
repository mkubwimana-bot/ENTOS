-- SME-OS Migration 001
-- Core platform tables
-- This file will create tenants, branches, warehouses, and tenant settings.

-- Status: draft
-- ============================================================
-- SME-OS Migration 001
-- Core Platform Tables
-- Creates:
--   - tenants
--   - branches
--   - warehouses
--   - tenant_settings
--   - updated_at trigger helper
--
-- No-Docker workflow:
-- Save this file in Cursor, then copy and run it in Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Required extension for UUID generation
-- ------------------------------------------------------------

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 2. Helper function: automatically update updated_at
-- ------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- 3. Tenants
-- A tenant is one SME/company using the platform.
-- Access/VBA analogy:
-- This is like a Companies table, and tenant_id is like CompanyID.
-- ------------------------------------------------------------

create table if not exists public.tenants (
  id uuid primary key default gen_random_uuid(),

  tenant_code text not null,
  legal_name text not null,
  trading_name text,

  business_type text,
  tin_number text,

  country_code text not null default 'RW',
  default_currency text not null default 'RWF',
  default_language_code text not null default 'en',
  timezone text not null default 'Africa/Kigali',

  subscription_status text not null default 'trial',
  onboarding_status text not null default 'not_started',

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,

  constraint tenants_tenant_code_unique unique (tenant_code),

  constraint tenants_subscription_status_check
    check (subscription_status in (
      'trial',
      'active',
      'past_due',
      'suspended',
      'cancelled'
    )),

  constraint tenants_onboarding_status_check
    check (onboarding_status in (
      'not_started',
      'setup_started',
      'active',
      'needs_help'
    ))
);

create index if not exists idx_tenants_subscription_status
on public.tenants (subscription_status);

create index if not exists idx_tenants_is_active
on public.tenants (is_active);

create trigger trg_tenants_set_updated_at
before update on public.tenants
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 4. Branches
-- A branch is a physical or logical business location.
-- MVP can start with one default branch per tenant.
-- ------------------------------------------------------------

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete restrict,

  branch_code text not null,
  name text not null,

  address_text text,
  phone text,

  is_default boolean not null default false,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,

  constraint branches_tenant_branch_code_unique
    unique (tenant_id, branch_code)
);

create index if not exists idx_branches_tenant_id
on public.branches (tenant_id);

create index if not exists idx_branches_tenant_active
on public.branches (tenant_id, is_active);

create unique index if not exists idx_branches_one_default_per_tenant
on public.branches (tenant_id)
where is_default = true and deleted_at is null;

create trigger trg_branches_set_updated_at
before update on public.branches
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 5. Warehouses
-- A warehouse is a stock location.
-- For a small shop, this can simply be "Main Store".
-- ------------------------------------------------------------

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,

  warehouse_code text not null,
  name text not null,

  warehouse_type text not null default 'store',

  is_default boolean not null default false,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz,
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,

  constraint warehouses_tenant_warehouse_code_unique
    unique (tenant_id, warehouse_code),

  constraint warehouses_type_check
    check (warehouse_type in (
      'store',
      'backroom',
      'van',
      'production',
      'damaged',
      'other'
    ))
);

create index if not exists idx_warehouses_tenant_id
on public.warehouses (tenant_id);

create index if not exists idx_warehouses_branch_id
on public.warehouses (branch_id);

create index if not exists idx_warehouses_tenant_active
on public.warehouses (tenant_id, is_active);

create unique index if not exists idx_warehouses_one_default_per_branch
on public.warehouses (tenant_id, branch_id)
where is_default = true and deleted_at is null;

create trigger trg_warehouses_set_updated_at
before update on public.warehouses
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 6. Tenant Settings
-- Stores flexible tenant configuration.
-- Example:
-- invoice_prefix, default_payment_method, allow_negative_stock
-- ------------------------------------------------------------

create table if not exists public.tenant_settings (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete restrict,

  setting_key text not null,
  setting_value jsonb,
  description text,

  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz,
  updated_by uuid,

  constraint tenant_settings_tenant_key_unique
    unique (tenant_id, setting_key)
);

create index if not exists idx_tenant_settings_tenant_id
on public.tenant_settings (tenant_id);

create trigger trg_tenant_settings_set_updated_at
before update on public.tenant_settings
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 7. RLS note
-- ------------------------------------------------------------
-- Row-Level Security will be enabled after we create:
--   - app_users
--   - user_tenants
--   - roles
--   - permissions
--
-- Reason:
-- Tenant isolation policies need the user_tenants table.
-- That comes in migration 002_security_roles.sql.
-- ------------------------------------------------------------