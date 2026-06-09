-- ============================================================
-- SME-OS Migration 006
-- Mobile and Offline Transaction Support
--
-- Creates:
--   - mobile_devices
--   - device_sessions
--   - transaction_drafts
--   - sync_queue
--   - sync_logs
--   - conflict_logs
--   - offline_cache_metadata
--   - number_sequences
--
-- Purpose:
-- Supports mobile-first simple transactions and limited offline
-- draft capture without building a full offline ERP.
--
-- No-Docker workflow:
-- Save this file in Cursor, then copy and run it in Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Mobile Devices
-- Registers devices that use mobile/offline transaction features.
-- ------------------------------------------------------------

create table if not exists public.mobile_devices (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references public.app_users(id) on delete cascade,

  device_code text not null,
  device_name text,

  device_type text not null default 'mobile_web',
  platform text,

  last_seen_at timestamptz,

  is_trusted boolean not null default false,
  offline_enabled boolean not null default false,

  status text not null default 'active',

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,

  constraint mobile_devices_tenant_device_code_unique
    unique (tenant_id, device_code),

  constraint mobile_devices_device_type_check
    check (device_type in (
      'mobile_web',
      'android_app',
      'ios_app',
      'tablet',
      'desktop',
      'other'
    )),

  constraint mobile_devices_status_check
    check (status in (
      'active',
      'blocked',
      'retired'
    ))
);

create index if not exists idx_mobile_devices_tenant_id
on public.mobile_devices (tenant_id);

create index if not exists idx_mobile_devices_user_id
on public.mobile_devices (user_id);

create index if not exists idx_mobile_devices_tenant_status
on public.mobile_devices (tenant_id, status);

create index if not exists idx_mobile_devices_offline_enabled
on public.mobile_devices (tenant_id, offline_enabled);

create trigger trg_mobile_devices_set_updated_at
before update on public.mobile_devices
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 2. Device Sessions
-- Tracks login/session context for mobile and offline-capable devices.
-- ------------------------------------------------------------

create table if not exists public.device_sessions (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references public.app_users(id) on delete cascade,
  device_id uuid references public.mobile_devices(id) on delete set null,

  session_started_at timestamptz not null default now(),
  last_online_at timestamptz,

  permissions_cached_at timestamptz,
  offline_allowed_until timestamptz,

  ip_address text,
  user_agent text,

  status text not null default 'active',

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint device_sessions_status_check
    check (status in (
      'active',
      'expired',
      'revoked'
    ))
);

create index if not exists idx_device_sessions_tenant_user
on public.device_sessions (tenant_id, user_id);

create index if not exists idx_device_sessions_device_id
on public.device_sessions (device_id);

create index if not exists idx_device_sessions_status
on public.device_sessions (tenant_id, status);

create index if not exists idx_device_sessions_offline_allowed_until
on public.device_sessions (offline_allowed_until);

create trigger trg_device_sessions_set_updated_at
before update on public.device_sessions
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3. Transaction Drafts
-- Stores provisional, incomplete, online draft, or offline-created
-- transaction payloads before final posting.
-- ------------------------------------------------------------

create table if not exists public.transaction_drafts (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  warehouse_id uuid references public.warehouses(id) on delete restrict,

  user_id uuid not null references public.app_users(id) on delete restrict,
  device_id uuid references public.mobile_devices(id) on delete set null,

  draft_type text not null,

  client_reference_id text not null,
  provisional_number text,

  payload jsonb not null,

  status text not null default 'draft',
  source text not null default 'online',

  created_offline_at timestamptz,
  received_at timestamptz,

  posted_document_id uuid,
  posted_document_table text,

  error_message text,

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint transaction_drafts_tenant_client_ref_unique
    unique (tenant_id, client_reference_id),

  constraint transaction_drafts_draft_type_check
    check (draft_type in (
      'sale',
      'payment',
      'stock_adjustment',
      'customer_create'
    )),

  constraint transaction_drafts_status_check
    check (status in (
      'draft',
      'pending_sync',
      'synced',
      'failed',
      'conflict',
      'cancelled'
    )),

  constraint transaction_drafts_source_check
    check (source in (
      'online',
      'offline',
      'mobile',
      'imported'
    )),

  constraint transaction_drafts_posted_table_check
    check (
      posted_document_table is null
      or posted_document_table in (
        'invoices',
        'payments',
        'stock_movements',
        'parties'
      )
    )
);

create index if not exists idx_transaction_drafts_tenant_id
on public.transaction_drafts (tenant_id);

create index if not exists idx_transaction_drafts_tenant_status
on public.transaction_drafts (tenant_id, status);

create index if not exists idx_transaction_drafts_tenant_type
on public.transaction_drafts (tenant_id, draft_type);

create index if not exists idx_transaction_drafts_user_id
on public.transaction_drafts (user_id);

create index if not exists idx_transaction_drafts_device_id
on public.transaction_drafts (device_id);

create index if not exists idx_transaction_drafts_created_at
on public.transaction_drafts (tenant_id, created_at);

create trigger trg_transaction_drafts_set_updated_at
before update on public.transaction_drafts
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 4. Sync Queue
-- Server-side queue of offline/mobile actions awaiting validation.
-- ------------------------------------------------------------

create table if not exists public.sync_queue (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  draft_id uuid references public.transaction_drafts(id) on delete cascade,

  queue_type text not null,

  client_reference_id text not null,
  payload jsonb not null,

  status text not null default 'pending',

  priority integer not null default 100,
  attempt_count integer not null default 0,

  next_retry_at timestamptz,

  locked_at timestamptz,
  locked_by text,

  result_reference_id uuid,

  last_error text,

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint sync_queue_tenant_client_ref_unique
    unique (tenant_id, client_reference_id),

  constraint sync_queue_queue_type_check
    check (queue_type in (
      'post_sale',
      'post_payment',
      'post_stock_adjustment',
      'create_customer'
    )),

  constraint sync_queue_status_check
    check (status in (
      'pending',
      'processing',
      'succeeded',
      'failed',
      'conflict',
      'cancelled'
    )),

  constraint sync_queue_attempt_count_check
    check (attempt_count >= 0),

  constraint sync_queue_priority_check
    check (priority >= 0)
);

create index if not exists idx_sync_queue_tenant_status
on public.sync_queue (tenant_id, status);

create index if not exists idx_sync_queue_draft_id
on public.sync_queue (draft_id);

create index if not exists idx_sync_queue_next_retry
on public.sync_queue (next_retry_at);

create index if not exists idx_sync_queue_priority
on public.sync_queue (status, priority, created_at);

create trigger trg_sync_queue_set_updated_at
before update on public.sync_queue
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 5. Sync Logs
-- Records each sync attempt for support and audit.
-- ------------------------------------------------------------

create table if not exists public.sync_logs (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  device_id uuid references public.mobile_devices(id) on delete set null,
  user_id uuid references public.app_users(id) on delete set null,

  draft_id uuid references public.transaction_drafts(id) on delete set null,
  sync_queue_id uuid references public.sync_queue(id) on delete set null,

  sync_direction text not null,
  status text not null,

  records_sent integer,
  records_received integer,

  started_at timestamptz not null default now(),
  completed_at timestamptz,

  error_code text,
  error_message text,

  created_at timestamptz not null default now(),

  constraint sync_logs_direction_check
    check (sync_direction in (
      'upload',
      'download',
      'retry'
    )),

  constraint sync_logs_status_check
    check (status in (
      'started',
      'succeeded',
      'failed',
      'conflict'
    )),

  constraint sync_logs_records_sent_check
    check (records_sent is null or records_sent >= 0),

  constraint sync_logs_records_received_check
    check (records_received is null or records_received >= 0)
);

create index if not exists idx_sync_logs_tenant_created_at
on public.sync_logs (tenant_id, created_at);

create index if not exists idx_sync_logs_device_id
on public.sync_logs (device_id);

create index if not exists idx_sync_logs_draft_id
on public.sync_logs (draft_id);

create index if not exists idx_sync_logs_queue_id
on public.sync_logs (sync_queue_id);

-- ------------------------------------------------------------
-- 6. Conflict Logs
-- Records sync conflicts that need review.
-- ------------------------------------------------------------

create table if not exists public.conflict_logs (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  draft_id uuid not null references public.transaction_drafts(id) on delete cascade,

  conflict_type text not null,
  severity text not null default 'medium',

  description text not null,

  server_snapshot jsonb,
  client_payload jsonb,

  resolution_status text not null default 'open',

  resolved_by uuid references public.app_users(id) on delete set null,
  resolved_at timestamptz,
  resolution_notes text,

  created_at timestamptz not null default now(),

  constraint conflict_logs_type_check
    check (conflict_type in (
      'stock_shortage',
      'stale_price',
      'deleted_product',
      'permission_changed',
      'duplicate_customer',
      'validation_failed',
      'other'
    )),

  constraint conflict_logs_severity_check
    check (severity in (
      'low',
      'medium',
      'high'
    )),

  constraint conflict_logs_resolution_status_check
    check (resolution_status in (
      'open',
      'accepted',
      'rejected',
      'adjusted',
      'ignored'
    ))
);

create index if not exists idx_conflict_logs_tenant_status
on public.conflict_logs (tenant_id, resolution_status);

create index if not exists idx_conflict_logs_draft_id
on public.conflict_logs (draft_id);

create index if not exists idx_conflict_logs_type
on public.conflict_logs (tenant_id, conflict_type);

-- ------------------------------------------------------------
-- 7. Offline Cache Metadata
-- Tracks cache freshness on mobile devices.
-- ------------------------------------------------------------

create table if not exists public.offline_cache_metadata (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  device_id uuid not null references public.mobile_devices(id) on delete cascade,

  cache_type text not null,

  last_synced_at timestamptz not null default now(),

  record_count integer,
  cache_version text,
  expires_at timestamptz,

  status text not null default 'current',

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint offline_cache_metadata_device_cache_unique
    unique (device_id, cache_type),

  constraint offline_cache_metadata_cache_type_check
    check (cache_type in (
      'products',
      'customers',
      'prices',
      'permissions',
      'settings'
    )),

  constraint offline_cache_metadata_status_check
    check (status in (
      'current',
      'stale',
      'expired'
    )),

  constraint offline_cache_metadata_record_count_check
    check (record_count is null or record_count >= 0)
);

create index if not exists idx_offline_cache_metadata_tenant
on public.offline_cache_metadata (tenant_id);

create index if not exists idx_offline_cache_metadata_device
on public.offline_cache_metadata (device_id);

create index if not exists idx_offline_cache_metadata_status
on public.offline_cache_metadata (tenant_id, status);

create trigger trg_offline_cache_metadata_set_updated_at
before update on public.offline_cache_metadata
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 8. Number Sequences
-- Controls final server-side document numbering.
-- Offline/mobile numbers are provisional only.
-- ------------------------------------------------------------

create table if not exists public.number_sequences (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,

  sequence_code text not null,

  prefix text,
  current_value bigint not null default 0,
  padding_length integer not null default 6,

  reset_period text not null default 'never',
  last_reset_at timestamptz,

  status text not null default 'active',

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint number_sequences_unique
    unique (tenant_id, branch_id, sequence_code),

  constraint number_sequences_code_check
    check (sequence_code in (
      'invoice',
      'receipt',
      'stock_adjustment',
      'credit_note',
      'payment'
    )),

  constraint number_sequences_current_value_check
    check (current_value >= 0),

  constraint number_sequences_padding_check
    check (padding_length >= 1 and padding_length <= 12),

  constraint number_sequences_reset_period_check
    check (reset_period in (
      'never',
      'yearly',
      'monthly'
    )),

  constraint number_sequences_status_check
    check (status in (
      'active',
      'inactive'
    ))
);

create index if not exists idx_number_sequences_tenant
on public.number_sequences (tenant_id);

create index if not exists idx_number_sequences_branch
on public.number_sequences (branch_id);

create trigger trg_number_sequences_set_updated_at
before update on public.number_sequences
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 9. Helper function: generate next document number
-- ------------------------------------------------------------

create or replace function public.get_next_document_number(
  target_tenant_id uuid,
  target_branch_id uuid,
  target_sequence_code text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sequence_id uuid;
  v_prefix text;
  v_current_value bigint;
  v_padding_length integer;
  v_next_value bigint;
  v_document_number text;
begin
  select id, prefix, current_value, padding_length
  into v_sequence_id, v_prefix, v_current_value, v_padding_length
  from public.number_sequences
  where tenant_id = target_tenant_id
    and (
      branch_id = target_branch_id
      or (branch_id is null and target_branch_id is null)
    )
    and sequence_code = target_sequence_code
    and status = 'active'
  for update;

  if v_sequence_id is null then
    raise exception 'No active number sequence found for sequence code %', target_sequence_code;
  end if;

  v_next_value := v_current_value + 1;

  update public.number_sequences
  set
    current_value = v_next_value,
    updated_at = now()
  where id = v_sequence_id;

  v_document_number :=
    coalesce(v_prefix, '')
    || lpad(v_next_value::text, v_padding_length, '0');

  return v_document_number;
end;
$$;

-- ------------------------------------------------------------
-- 10. MVP view: pending mobile/offline transactions
-- ------------------------------------------------------------

create or replace view public.vw_pending_mobile_transactions as
select
  td.tenant_id,
  td.branch_id,
  td.warehouse_id,
  td.user_id,
  td.device_id,
  td.id as draft_id,
  td.draft_type,
  td.client_reference_id,
  td.provisional_number,
  td.status,
  td.source,
  td.created_offline_at,
  td.received_at,
  td.error_message,
  td.created_at,
  sq.id as sync_queue_id,
  sq.queue_type,
  sq.status as queue_status,
  sq.attempt_count,
  sq.next_retry_at,
  sq.last_error
from public.transaction_drafts td
left join public.sync_queue sq
  on sq.draft_id = td.id
where td.status in (
  'draft',
  'pending_sync',
  'failed',
  'conflict'
);

-- ------------------------------------------------------------
-- 11. Enable RLS
-- ------------------------------------------------------------

alter table public.mobile_devices enable row level security;
alter table public.device_sessions enable row level security;
alter table public.transaction_drafts enable row level security;
alter table public.sync_queue enable row level security;
alter table public.sync_logs enable row level security;
alter table public.conflict_logs enable row level security;
alter table public.offline_cache_metadata enable row level security;
alter table public.number_sequences enable row level security;

-- ------------------------------------------------------------
-- 12. RLS: mobile_devices
-- ------------------------------------------------------------

drop policy if exists mobile_devices_select_if_tenant_member
on public.mobile_devices;

create policy mobile_devices_select_if_tenant_member
on public.mobile_devices
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists mobile_devices_insert_if_offline_use
on public.mobile_devices;

create policy mobile_devices_insert_if_offline_use
on public.mobile_devices
for insert
with check (
  public.user_has_permission(tenant_id, 'offline.use')
);

drop policy if exists mobile_devices_update_if_devices_manage
on public.mobile_devices;

create policy mobile_devices_update_if_devices_manage
on public.mobile_devices
for update
using (
  public.user_has_permission(tenant_id, 'devices.manage')
)
with check (
  public.user_has_permission(tenant_id, 'devices.manage')
);

-- ------------------------------------------------------------
-- 13. RLS: device_sessions
-- ------------------------------------------------------------

drop policy if exists device_sessions_select_own_or_manager
on public.device_sessions;

create policy device_sessions_select_own_or_manager
on public.device_sessions
for select
using (
  user_id = auth.uid()
  or public.user_has_permission(tenant_id, 'devices.manage')
);

drop policy if exists device_sessions_insert_if_offline_use
on public.device_sessions;

create policy device_sessions_insert_if_offline_use
on public.device_sessions
for insert
with check (
  user_id = auth.uid()
  and public.user_has_permission(tenant_id, 'offline.use')
);

drop policy if exists device_sessions_update_own_or_manager
on public.device_sessions;

create policy device_sessions_update_own_or_manager
on public.device_sessions
for update
using (
  user_id = auth.uid()
  or public.user_has_permission(tenant_id, 'devices.manage')
)
with check (
  user_id = auth.uid()
  or public.user_has_permission(tenant_id, 'devices.manage')
);

-- ------------------------------------------------------------
-- 14. RLS: transaction_drafts
-- ------------------------------------------------------------

drop policy if exists transaction_drafts_select_own_or_review
on public.transaction_drafts;

create policy transaction_drafts_select_own_or_review
on public.transaction_drafts
for select
using (
  user_id = auth.uid()
  or public.user_has_permission(tenant_id, 'sync.review_conflicts')
  or public.user_has_permission(tenant_id, 'reports.view')
);

drop policy if exists transaction_drafts_insert_if_offline_or_mobile
on public.transaction_drafts;

create policy transaction_drafts_insert_if_offline_or_mobile
on public.transaction_drafts
for insert
with check (
  user_id = auth.uid()
  and (
    public.user_has_permission(tenant_id, 'offline.use')
    or public.user_has_permission(tenant_id, 'mobile.quick_sale')
    or public.user_has_permission(tenant_id, 'mobile.record_payment')
    or public.user_has_permission(tenant_id, 'mobile.stock_adjust')
  )
);

drop policy if exists transaction_drafts_update_own_or_review
on public.transaction_drafts;

create policy transaction_drafts_update_own_or_review
on public.transaction_drafts
for update
using (
  user_id = auth.uid()
  or public.user_has_permission(tenant_id, 'sync.review_conflicts')
)
with check (
  user_id = auth.uid()
  or public.user_has_permission(tenant_id, 'sync.review_conflicts')
);

-- ------------------------------------------------------------
-- 15. RLS: sync_queue
-- ------------------------------------------------------------

drop policy if exists sync_queue_select_own_or_review
on public.sync_queue;

create policy sync_queue_select_own_or_review
on public.sync_queue
for select
using (
  public.user_has_permission(tenant_id, 'offline.use')
  or public.user_has_permission(tenant_id, 'sync.review_conflicts')
);

drop policy if exists sync_queue_insert_if_offline_use
on public.sync_queue;

create policy sync_queue_insert_if_offline_use
on public.sync_queue
for insert
with check (
  public.user_has_permission(tenant_id, 'offline.use')
);

drop policy if exists sync_queue_update_if_review_conflicts
on public.sync_queue;

create policy sync_queue_update_if_review_conflicts
on public.sync_queue
for update
using (
  public.user_has_permission(tenant_id, 'sync.review_conflicts')
)
with check (
  public.user_has_permission(tenant_id, 'sync.review_conflicts')
);

-- ------------------------------------------------------------
-- 16. RLS: sync_logs
-- ------------------------------------------------------------

drop policy if exists sync_logs_select_if_tenant_member
on public.sync_logs;

create policy sync_logs_select_if_tenant_member
on public.sync_logs
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists sync_logs_insert_if_offline_use
on public.sync_logs;

create policy sync_logs_insert_if_offline_use
on public.sync_logs
for insert
with check (
  public.user_has_permission(tenant_id, 'offline.use')
);

-- ------------------------------------------------------------
-- 17. RLS: conflict_logs
-- ------------------------------------------------------------

drop policy if exists conflict_logs_select_if_review
on public.conflict_logs;

create policy conflict_logs_select_if_review
on public.conflict_logs
for select
using (
  public.user_has_permission(tenant_id, 'sync.review_conflicts')
);

drop policy if exists conflict_logs_manage_if_review
on public.conflict_logs;

create policy conflict_logs_manage_if_review
on public.conflict_logs
for all
using (
  public.user_has_permission(tenant_id, 'sync.review_conflicts')
)
with check (
  public.user_has_permission(tenant_id, 'sync.review_conflicts')
);

-- ------------------------------------------------------------
-- 18. RLS: offline_cache_metadata
-- ------------------------------------------------------------

drop policy if exists offline_cache_metadata_select_own_or_manager
on public.offline_cache_metadata;

create policy offline_cache_metadata_select_own_or_manager
on public.offline_cache_metadata
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists offline_cache_metadata_manage_if_offline_use
on public.offline_cache_metadata;

create policy offline_cache_metadata_manage_if_offline_use
on public.offline_cache_metadata
for all
using (
  public.user_has_permission(tenant_id, 'offline.use')
)
with check (
  public.user_has_permission(tenant_id, 'offline.use')
);

-- ------------------------------------------------------------
-- 19. RLS: number_sequences
-- ------------------------------------------------------------

drop policy if exists number_sequences_select_if_tenant_member
on public.number_sequences;

create policy number_sequences_select_if_tenant_member
on public.number_sequences
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists number_sequences_manage_if_settings_edit
on public.number_sequences;

create policy number_sequences_manage_if_settings_edit
on public.number_sequences
for all
using (
  public.user_has_permission(tenant_id, 'settings.edit')
)
with check (
  public.user_has_permission(tenant_id, 'settings.edit')
);

-- ------------------------------------------------------------
-- End of Migration 006
-- ------------------------------------------------------------