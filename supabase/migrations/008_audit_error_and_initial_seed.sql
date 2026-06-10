-- ============================================================
-- SME-OS Migration 008
-- Audit Logs, Error Logs, and Initial Seed Helpers
--
-- Creates:
--   - audit_logs
--   - error_logs
--   - helper function to initialize tenant defaults
--
-- Purpose:
-- Adds operational visibility, troubleshooting, and first-tenant
-- setup support for the MVP.
--
-- No-Docker workflow:
-- Save this file in Cursor, then copy and run it in Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Audit Logs
-- Records important user/system actions.
-- ------------------------------------------------------------

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid references public.tenants(id) on delete cascade,
  user_id uuid references public.app_users(id) on delete set null,

  action_code text not null,

  table_name text,
  record_id uuid,

  old_values jsonb,
  new_values jsonb,

  ip_address text,
  user_agent text,

  created_at timestamptz not null default now(),

  constraint audit_logs_action_code_check
    check (action_code in (
      'create',
      'update',
      'delete',
      'soft_delete',
      'post',
      'void',
      'login',
      'logout',
      'export',
      'sync',
      'permission_change',
      'settings_change',
      'subscription_change',
      'credit_consent_granted',
      'credit_consent_revoked',
      'error_recorded',
      'other'
    ))
);

create index if not exists idx_audit_logs_tenant_created_at
on public.audit_logs (tenant_id, created_at);

create index if not exists idx_audit_logs_user_created_at
on public.audit_logs (user_id, created_at);

create index if not exists idx_audit_logs_table_record
on public.audit_logs (table_name, record_id);

create index if not exists idx_audit_logs_action_code
on public.audit_logs (tenant_id, action_code);

-- ------------------------------------------------------------
-- 2. Error Logs
-- Stores application, database, sync, and integration errors.
-- ------------------------------------------------------------

create table if not exists public.error_logs (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid references public.tenants(id) on delete cascade,
  user_id uuid references public.app_users(id) on delete set null,

  error_source text not null,
  error_code text,
  error_message text not null,

  stack_trace text,
  context_payload jsonb,

  severity text not null default 'medium',
  status text not null default 'open',

  resolved_at timestamptz,
  resolved_by uuid references public.app_users(id) on delete set null,
  resolution_notes text,

  created_at timestamptz not null default now(),

  constraint error_logs_source_check
    check (error_source in (
      'flutterflow',
      'supabase',
      'database',
      'edge_function',
      'integration',
      'mobile_sync',
      'manual',
      'other'
    )),

  constraint error_logs_severity_check
    check (severity in (
      'low',
      'medium',
      'high',
      'critical'
    )),

  constraint error_logs_status_check
    check (status in (
      'open',
      'investigating',
      'resolved',
      'ignored'
    ))
);

create index if not exists idx_error_logs_tenant_created_at
on public.error_logs (tenant_id, created_at);

create index if not exists idx_error_logs_user_created_at
on public.error_logs (user_id, created_at);

create index if not exists idx_error_logs_source_created_at
on public.error_logs (error_source, created_at);

create index if not exists idx_error_logs_status_severity
on public.error_logs (status, severity);

-- ------------------------------------------------------------
-- 3. Helper: log audit event
-- ------------------------------------------------------------

create or replace function public.log_audit_event(
  target_tenant_id uuid,
  target_user_id uuid,
  target_action_code text,
  target_table_name text,
  target_record_id uuid,
  target_old_values jsonb,
  target_new_values jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_audit_id uuid;
begin
  insert into public.audit_logs (
    tenant_id,
    user_id,
    action_code,
    table_name,
    record_id,
    old_values,
    new_values
  )
  values (
    target_tenant_id,
    target_user_id,
    target_action_code,
    target_table_name,
    target_record_id,
    target_old_values,
    target_new_values
  )
  returning id into v_audit_id;

  return v_audit_id;
end;
$$;

-- ------------------------------------------------------------
-- 4. Helper: log error event
-- ------------------------------------------------------------

create or replace function public.log_error_event(
  target_tenant_id uuid,
  target_user_id uuid,
  target_error_source text,
  target_error_code text,
  target_error_message text,
  target_context_payload jsonb,
  target_severity text default 'medium'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_error_id uuid;
begin
  insert into public.error_logs (
    tenant_id,
    user_id,
    error_source,
    error_code,
    error_message,
    context_payload,
    severity
  )
  values (
    target_tenant_id,
    target_user_id,
    target_error_source,
    target_error_code,
    target_error_message,
    target_context_payload,
    target_severity
  )
  returning id into v_error_id;

  return v_error_id;
end;
$$;

-- ------------------------------------------------------------
-- 5. Helper: initialize default tenant records
--
-- This creates:
--   - default branch
--   - default warehouse
--   - default tenant settings
--   - default language settings
--   - default number sequences
--   - starter product category
--
-- Use after creating a tenant.
-- ------------------------------------------------------------

create or replace function public.initialize_tenant_defaults(
  target_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_warehouse_id uuid;
  v_pcs_unit_id uuid;
begin
  -- Validate tenant exists.
  if not exists (
    select 1 from public.tenants where id = target_tenant_id
  ) then
    raise exception 'Tenant does not exist: %', target_tenant_id;
  end if;

  -- Default branch.
  insert into public.branches (
    tenant_id,
    branch_code,
    name,
    is_default,
    is_active
  )
  values (
    target_tenant_id,
    'MAIN',
    'Main Branch',
    true,
    true
  )
  on conflict (tenant_id, branch_code) do update
  set
    name = excluded.name,
    is_default = true,
    is_active = true
  returning id into v_branch_id;

  -- Default warehouse.
  insert into public.warehouses (
    tenant_id,
    branch_id,
    warehouse_code,
    name,
    warehouse_type,
    is_default,
    is_active
  )
  values (
    target_tenant_id,
    v_branch_id,
    'MAIN',
    'Main Store',
    'store',
    true,
    true
  )
  on conflict (tenant_id, warehouse_code) do update
  set
    branch_id = excluded.branch_id,
    name = excluded.name,
    warehouse_type = excluded.warehouse_type,
    is_default = true,
    is_active = true
  returning id into v_warehouse_id;

  -- Default tenant settings.
  insert into public.tenant_settings (
    tenant_id,
    setting_key,
    setting_value,
    description
  )
  values
    (
      target_tenant_id,
      'allow_negative_stock',
      'false'::jsonb,
      'Controls whether stock can go below zero.'
    ),
    (
      target_tenant_id,
      'invoice_prefix',
      '"INV-"'::jsonb,
      'Default invoice number prefix.'
    ),
    (
      target_tenant_id,
      'receipt_prefix',
      '"REC-"'::jsonb,
      'Default receipt/payment number prefix.'
    ),
    (
      target_tenant_id,
      'stock_adjustment_prefix',
      '"ADJ-"'::jsonb,
      'Default stock adjustment number prefix.'
    ),
    (
      target_tenant_id,
      'default_credit_terms_days',
      '30'::jsonb,
      'Default number of days before a credit invoice is due.'
    ),
    (
      target_tenant_id,
      'offline_allowed_days',
      '3'::jsonb,
      'Maximum days offline permission cache remains valid.'
    )
  on conflict (tenant_id, setting_key) do nothing;

  -- Default language settings.
  insert into public.tenant_language_settings (
    tenant_id,
    default_language_code,
    enabled_languages
  )
  values (
    target_tenant_id,
    'en',
    array['en', 'fr', 'rw']
  )
  on conflict (tenant_id) do update
  set
    default_language_code = excluded.default_language_code,
    enabled_languages = excluded.enabled_languages;

  -- Default number sequences.
  insert into public.number_sequences (
    tenant_id,
    branch_id,
    sequence_code,
    prefix,
    current_value,
    padding_length,
    reset_period,
    status
  )
  values
    (
      target_tenant_id,
      v_branch_id,
      'invoice',
      'INV-',
      0,
      6,
      'never',
      'active'
    ),
    (
      target_tenant_id,
      v_branch_id,
      'receipt',
      'REC-',
      0,
      6,
      'never',
      'active'
    ),
    (
      target_tenant_id,
      v_branch_id,
      'payment',
      'PAY-',
      0,
      6,
      'never',
      'active'
    ),
    (
      target_tenant_id,
      v_branch_id,
      'stock_adjustment',
      'ADJ-',
      0,
      6,
      'never',
      'active'
    )
  on conflict (tenant_id, branch_id, sequence_code) do nothing;

  -- Starter product category.
  insert into public.product_categories (
    tenant_id,
    category_code,
    category_name,
    description,
    is_active
  )
  values (
    target_tenant_id,
    'GENERAL',
    'General',
    'Default product category.',
    true
  )
  on conflict (tenant_id, category_name) do nothing;

  -- Audit event.
  insert into public.audit_logs (
    tenant_id,
    action_code,
    table_name,
    record_id,
    new_values
  )
  values (
    target_tenant_id,
    'create',
    'tenant_defaults',
    target_tenant_id,
    jsonb_build_object(
      'default_branch_id', v_branch_id,
      'default_warehouse_id', v_warehouse_id
    )
  );
end;
$$;

-- ------------------------------------------------------------
-- 6. Enable RLS
-- ------------------------------------------------------------

alter table public.audit_logs enable row level security;
alter table public.error_logs enable row level security;

-- ------------------------------------------------------------
-- 7. RLS: audit_logs
-- ------------------------------------------------------------

drop policy if exists audit_logs_select_if_reports_or_settings
on public.audit_logs;

create policy audit_logs_select_if_reports_or_settings
on public.audit_logs
for select
using (
  public.is_platform_admin()
  or public.user_has_permission(tenant_id, 'reports.view')
  or public.user_has_permission(tenant_id, 'settings.view')
  or public.user_has_permission(tenant_id, 'settings.edit')
);

drop policy if exists audit_logs_insert_if_tenant_member
on public.audit_logs;

create policy audit_logs_insert_if_tenant_member
on public.audit_logs
for insert
with check (
  tenant_id is null
  or public.user_has_tenant_access(tenant_id)
);

-- ------------------------------------------------------------
-- 8. RLS: error_logs
-- ------------------------------------------------------------

drop policy if exists error_logs_select_if_reports_or_settings
on public.error_logs;

create policy error_logs_select_if_reports_or_settings
on public.error_logs
for select
using (
  public.is_platform_admin()
  or public.user_has_permission(tenant_id, 'reports.view')
  or public.user_has_permission(tenant_id, 'settings.view')
  or public.user_has_permission(tenant_id, 'settings.edit')
);

drop policy if exists error_logs_insert_if_tenant_member
on public.error_logs;

create policy error_logs_insert_if_tenant_member
on public.error_logs
for insert
with check (
  tenant_id is null
  or public.user_has_tenant_access(tenant_id)
);

drop policy if exists error_logs_update_if_settings_edit
on public.error_logs;

create policy error_logs_update_if_settings_edit
on public.error_logs
for update
using (
  public.is_platform_admin()
  or public.user_has_permission(tenant_id, 'settings.edit')
)
with check (
  public.is_platform_admin()
  or public.user_has_permission(tenant_id, 'settings.edit')
);

-- ------------------------------------------------------------
-- 9. Support Views
-- ------------------------------------------------------------

create or replace view public.vw_open_errors as
select
  el.tenant_id,
  t.tenant_code,
  t.trading_name,
  el.id as error_id,
  el.error_source,
  el.error_code,
  el.error_message,
  el.severity,
  el.status,
  el.created_at
from public.error_logs el
left join public.tenants t on t.id = el.tenant_id
where el.status in ('open', 'investigating');

create or replace view public.vw_recent_audit_activity as
select
  al.tenant_id,
  t.tenant_code,
  t.trading_name,
  al.user_id,
  au.full_name as user_name,
  al.action_code,
  al.table_name,
  al.record_id,
  al.created_at
from public.audit_logs al
left join public.tenants t on t.id = al.tenant_id
left join public.app_users au on au.id = al.user_id
where al.created_at >= now() - interval '30 days';

-- ------------------------------------------------------------
-- End of Migration 008
-- ------------------------------------------------------------