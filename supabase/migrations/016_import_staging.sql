-- ============================================================
-- SME-OS Migration 016
-- Entos import staging tables, ID map, and reconciliation views
-- Run once before migrate_entos.py import (or included at top of import.sql)
-- ============================================================

-- ------------------------------------------------------------
-- 1. Migration run log
-- ------------------------------------------------------------

create table if not exists public.migration_run_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  run_label text not null,
  phase text not null,
  row_count integer not null default 0,
  status text not null default 'started',
  details jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz,

  constraint migration_run_log_status_check
    check (status in ('started', 'completed', 'failed'))
);

create index if not exists idx_migration_run_log_tenant
on public.migration_run_log (tenant_id, started_at desc);

-- ------------------------------------------------------------
-- 2. Old UUID → new document / entity map
-- ------------------------------------------------------------

create table if not exists public.migration_id_map (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  entity_type text not null,
  legacy_id uuid not null,
  new_id uuid not null,
  legacy_ref text,
  created_at timestamptz not null default now(),

  constraint migration_id_map_entity_type_check
    check (entity_type in (
      'party',
      'product',
      'category',
      'purchase',
      'invoice',
      'stock_movement',
      'adjustment'
    )),

  constraint migration_id_map_tenant_legacy_unique
    unique (tenant_id, entity_type, legacy_id)
);

create index if not exists idx_migration_id_map_new
on public.migration_id_map (tenant_id, entity_type, new_id);

-- ------------------------------------------------------------
-- 3. Optional raw staging (for manual inspection / re-runs)
-- ------------------------------------------------------------

create table if not exists public.stg_entos_parties (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  legacy_id uuid not null,
  party_kind text not null,
  name text not null,
  phone text,
  email text,
  note text,
  deleted boolean not null default false,
  updated_at timestamptz,
  primary key (tenant_id, legacy_id, party_kind)
);

create table if not exists public.stg_entos_products (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  legacy_id uuid not null,
  sku text,
  name text not null,
  category text,
  unit text,
  cost_price numeric(18,4),
  sale_price numeric(14,2),
  reorder_level numeric(14,3),
  opening_qty numeric(14,3),
  deleted boolean not null default false,
  updated_at timestamptz,
  primary key (tenant_id, legacy_id)
);

create table if not exists public.stg_entos_movements (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  legacy_id uuid not null,
  product_id uuid not null,
  movement_type text not null,
  qty numeric(14,3) not null,
  unit_price numeric(14,2) not null,
  movement_date date not null,
  supplier_id uuid,
  customer_id uuid,
  paid boolean,
  deleted boolean not null default false,
  updated_at timestamptz,
  primary key (tenant_id, legacy_id)
);

-- ------------------------------------------------------------
-- 4. Reconciliation views (post-import)
-- ------------------------------------------------------------

create or replace view public.vw_migration_document_counts as
select
  m.tenant_id,
  count(*) filter (where m.entity_type = 'purchase') as imported_purchases,
  count(*) filter (where m.entity_type = 'invoice') as imported_invoices,
  count(*) filter (where m.entity_type = 'adjustment') as imported_adjustments
from public.migration_id_map m
group by m.tenant_id;

create or replace view public.vw_migration_legacy_movements as
select
  sm.tenant_id,
  map.legacy_id as legacy_movement_id,
  map.entity_type,
  map.new_id as document_id,
  sm.movement_type,
  sm.product_id,
  sm.quantity_in,
  sm.quantity_out,
  sm.movement_date,
  sm.voided_at
from public.migration_id_map map
left join public.stock_movements sm
  on sm.source_id = map.new_id
 and sm.tenant_id = map.tenant_id
where map.entity_type in ('purchase', 'invoice', 'adjustment');

-- ------------------------------------------------------------
-- 5. RLS: service role / admin only (no anon access)
-- ------------------------------------------------------------

alter table public.migration_run_log enable row level security;
alter table public.migration_id_map enable row level security;
alter table public.stg_entos_parties enable row level security;
alter table public.stg_entos_products enable row level security;
alter table public.stg_entos_movements enable row level security;

-- Tenant members with settings permission can read migration status.
drop policy if exists migration_run_log_tenant_select on public.migration_run_log;
create policy migration_run_log_tenant_select
on public.migration_run_log
for select
to authenticated
using (
  exists (
    select 1
    from public.user_tenants ut
    where ut.tenant_id = migration_run_log.tenant_id
      and ut.user_id = auth.uid()
      and ut.membership_status = 'active'
  )
);

drop policy if exists migration_id_map_tenant_select on public.migration_id_map;
create policy migration_id_map_tenant_select
on public.migration_id_map
for select
to authenticated
using (
  exists (
    select 1
    from public.user_tenants ut
    where ut.tenant_id = migration_id_map.tenant_id
      and ut.user_id = auth.uid()
      and ut.membership_status = 'active'
  )
);
