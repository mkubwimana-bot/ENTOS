-- ============================================================
-- SME-OS Migration 007
-- Credit Readiness and Bankability Layer
--
-- Creates:
--   - sme_credit_consents
--   - sme_financial_snapshots
--   - credit_score_runs
--   - credit_events
--   - external_facilities
--
-- Creates views:
--   - vw_receivables_aging
--   - vw_monthly_cashflow_proxy
--   - vw_sme_bankability
--   - vw_dscr_inputs
--
-- Purpose:
-- Prepare SME-OS to convert operational transaction history into
-- bankability evidence for SMEs and responsible in-app customer
-- credit control.
--
-- Guardrail:
-- No SME data should be shared externally without active consent.
--
-- No-Docker workflow:
-- Save this file in Cursor, then copy and run it in Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. SME Credit Consents
-- Records explicit SME consent for internal scoring or external sharing.
-- ------------------------------------------------------------

create table if not exists public.sme_credit_consents (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,

  consent_type text not null,
  scope text not null,

  granted_by uuid not null references public.app_users(id) on delete restrict,
  granted_at timestamptz not null default now(),

  expires_at timestamptz,
  revoked_at timestamptz,

  status text not null default 'active',

  evidence_ref text,

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint sme_credit_consents_type_check
    check (consent_type in (
      'internal_scoring',
      'lender_sharing',
      'dfi_reporting',
      'bureau_sharing'
    )),

  constraint sme_credit_consents_status_check
    check (status in (
      'active',
      'expired',
      'revoked'
    )),

  constraint sme_credit_consents_scope_not_blank
    check (length(trim(scope)) > 0),

  constraint sme_credit_consents_expiry_check
    check (
      expires_at is null
      or expires_at > granted_at
    )
);

create index if not exists idx_sme_credit_consents_tenant_status
on public.sme_credit_consents (tenant_id, status);

create index if not exists idx_sme_credit_consents_type_scope
on public.sme_credit_consents (tenant_id, consent_type, scope);

create index if not exists idx_sme_credit_consents_granted_by
on public.sme_credit_consents (granted_by);

create trigger trg_sme_credit_consents_set_updated_at
before update on public.sme_credit_consents
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 2. SME Financial Snapshots
-- Monthly or periodic computed bankability metrics.
-- Snapshots are designed to be auditable and reproducible.
-- ------------------------------------------------------------

create table if not exists public.sme_financial_snapshots (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,

  period_start date not null,
  period_end date not null,

  total_sales numeric(14,2) not null default 0,
  cash_sales numeric(14,2) not null default 0,
  credit_sales numeric(14,2) not null default 0,
  collections numeric(14,2) not null default 0,

  gross_margin_est numeric(14,2),

  receivables_outstanding numeric(14,2) not null default 0,
  overdue_receivables numeric(14,2) not null default 0,

  avg_collection_days numeric(8,2),

  distinct_customers integer not null default 0,
  repeat_customer_ratio numeric(6,4),

  active_days integer not null default 0,
  sales_volatility numeric(8,4),

  inventory_turnover_est numeric(8,4),
  digital_payment_ratio numeric(6,4),

  computed_at timestamptz not null default now(),
  source_method text not null default 'view_rollup',

  correction_of_snapshot_id uuid references public.sme_financial_snapshots(id) on delete set null,

  created_at timestamptz not null default now(),

  constraint sme_financial_snapshots_period_check
    check (period_end >= period_start),

  constraint sme_financial_snapshots_amounts_check
    check (
      total_sales >= 0
      and cash_sales >= 0
      and credit_sales >= 0
      and collections >= 0
      and receivables_outstanding >= 0
      and overdue_receivables >= 0
    ),

  constraint sme_financial_snapshots_counts_check
    check (
      distinct_customers >= 0
      and active_days >= 0
    ),

  constraint sme_financial_snapshots_ratios_check
    check (
      (repeat_customer_ratio is null or (repeat_customer_ratio >= 0 and repeat_customer_ratio <= 1))
      and (digital_payment_ratio is null or (digital_payment_ratio >= 0 and digital_payment_ratio <= 1))
    ),

  constraint sme_financial_snapshots_source_method_check
    check (source_method in (
      'view_rollup',
      'batch_job',
      'manual_adjust',
      'corrected_rollup'
    ))
);

create index if not exists idx_sme_financial_snapshots_tenant_period
on public.sme_financial_snapshots (tenant_id, period_start, period_end);

create index if not exists idx_sme_financial_snapshots_computed_at
on public.sme_financial_snapshots (tenant_id, computed_at);

-- ------------------------------------------------------------
-- 3. Credit Score Runs
-- Records score output, model version, features, and purpose.
-- This is advisory evidence, not a final lending decision.
-- ------------------------------------------------------------

create table if not exists public.credit_score_runs (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,

  model_version text not null,

  score numeric(8,2) not null,
  risk_band text not null,

  snapshot_id uuid references public.sme_financial_snapshots(id) on delete set null,

  features jsonb not null,

  purpose text not null default 'internal_review',

  computed_by uuid references public.app_users(id) on delete set null,
  computed_at timestamptz not null default now(),

  status text not null default 'draft',

  created_at timestamptz not null default now(),

  constraint credit_score_runs_score_check
    check (score >= 0),

  constraint credit_score_runs_risk_band_check
    check (risk_band in (
      'A',
      'B',
      'C',
      'D',
      'low',
      'medium',
      'high'
    )),

  constraint credit_score_runs_purpose_check
    check (purpose in (
      'internal_review',
      'lender_screening',
      'pcg_assessment',
      'dfi_reporting'
    )),

  constraint credit_score_runs_status_check
    check (status in (
      'draft',
      'final',
      'superseded'
    ))
);

create index if not exists idx_credit_score_runs_tenant_computed_at
on public.credit_score_runs (tenant_id, computed_at);

create index if not exists idx_credit_score_runs_snapshot_id
on public.credit_score_runs (snapshot_id);

create index if not exists idx_credit_score_runs_purpose_status
on public.credit_score_runs (tenant_id, purpose, status);

-- ------------------------------------------------------------
-- 4. Credit Events
-- Material credit-related events not visible from sales data alone.
-- ------------------------------------------------------------

create table if not exists public.credit_events (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,

  event_type text not null,
  event_date date not null default current_date,

  amount numeric(14,2),

  facility_id uuid,

  source text not null default 'self_reported',

  notes text,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,

  constraint credit_events_type_check
    check (event_type in (
      'loan_disbursed',
      'repayment_made',
      'repayment_missed',
      'guarantee_called',
      'large_writeoff',
      'dispute',
      'other'
    )),

  constraint credit_events_source_check
    check (source in (
      'self_reported',
      'lender_confirmed',
      'system_derived'
    )),

  constraint credit_events_amount_check
    check (amount is null or amount >= 0)
);

create index if not exists idx_credit_events_tenant_date
on public.credit_events (tenant_id, event_date);

create index if not exists idx_credit_events_type
on public.credit_events (tenant_id, event_type);

-- ------------------------------------------------------------
-- 5. External Facilities
-- Loans, overdrafts, working capital, and PCG-covered facilities.
-- Recorded only with consent.
-- ------------------------------------------------------------

create table if not exists public.external_facilities (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,

  facility_type text not null,

  lender_name text,
  guarantee_scheme text,
  guarantee_coverage_pct numeric(5,2),

  principal_amount numeric(14,2) not null,
  outstanding_balance numeric(14,2),

  interest_rate_pct numeric(6,3),
  periodic_debt_service numeric(14,2),

  disbursement_date date,
  maturity_date date,

  status text not null default 'active',

  consent_id uuid references public.sme_credit_consents(id) on delete restrict,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,

  constraint external_facilities_type_check
    check (facility_type in (
      'term_loan',
      'working_capital',
      'overdraft',
      'pcg_covered_loan',
      'other'
    )),

  constraint external_facilities_amounts_check
    check (
      principal_amount >= 0
      and (outstanding_balance is null or outstanding_balance >= 0)
      and (periodic_debt_service is null or periodic_debt_service >= 0)
    ),

  constraint external_facilities_guarantee_pct_check
    check (
      guarantee_coverage_pct is null
      or (guarantee_coverage_pct >= 0 and guarantee_coverage_pct <= 100)
    ),

  constraint external_facilities_interest_rate_check
    check (
      interest_rate_pct is null
      or interest_rate_pct >= 0
    ),

  constraint external_facilities_dates_check
    check (
      maturity_date is null
      or disbursement_date is null
      or maturity_date >= disbursement_date
    ),

  constraint external_facilities_status_check
    check (status in (
      'active',
      'closed',
      'in_arrears',
      'restructured',
      'defaulted'
    ))
);

create index if not exists idx_external_facilities_tenant_status
on public.external_facilities (tenant_id, status);

create index if not exists idx_external_facilities_consent_id
on public.external_facilities (consent_id);

create trigger trg_external_facilities_set_updated_at
before update on public.external_facilities
for each row
execute function public.set_updated_at();

-- Now that external_facilities exists, add FK from credit_events.facility_id.
alter table public.credit_events
drop constraint if exists credit_events_facility_id_fkey;

alter table public.credit_events
add constraint credit_events_facility_id_fkey
foreign key (facility_id)
references public.external_facilities(id)
on delete set null;

-- ------------------------------------------------------------
-- 6. Credit Readiness Views
-- ------------------------------------------------------------

-- Receivables aging by customer and invoice.
create or replace view public.vw_receivables_aging as
select
  i.tenant_id,
  i.party_id as customer_id,
  p.party_code,
  p.party_name,
  i.id as invoice_id,
  i.invoice_number,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  coalesce(sum(pa.allocated_amount) filter (
    where pay.status = 'posted'
      and pay.voided_at is null
  ), 0) as allocated_amount,
  i.total_amount
    - coalesce(sum(pa.allocated_amount) filter (
        where pay.status = 'posted'
          and pay.voided_at is null
      ), 0) as outstanding,
  case
    when i.due_date is null then 'no_due_date'
    when current_date <= i.due_date then 'current'
    when current_date <= i.due_date + interval '30 day' then '1_30'
    when current_date <= i.due_date + interval '60 day' then '31_60'
    when current_date <= i.due_date + interval '90 day' then '61_90'
    else 'over_90'
  end as aging_bucket
from public.invoices i
join public.parties p
  on p.id = i.party_id
 and p.tenant_id = i.tenant_id
left join public.payment_allocations pa
  on pa.invoice_id = i.id
 and pa.tenant_id = i.tenant_id
left join public.payments pay
  on pay.id = pa.payment_id
 and pay.tenant_id = i.tenant_id
where i.status = 'posted'
  and i.voided_at is null
  and i.party_id is not null
group by
  i.tenant_id,
  i.party_id,
  p.party_code,
  p.party_name,
  i.id,
  i.invoice_number,
  i.invoice_date,
  i.due_date,
  i.total_amount
having
  i.total_amount
    - coalesce(sum(pa.allocated_amount) filter (
        where pay.status = 'posted'
          and pay.voided_at is null
      ), 0) > 0;

-- Monthly cashflow proxy.
create or replace view public.vw_monthly_cashflow_proxy as
with invoice_months as (
  select
    tenant_id,
    date_trunc('month', invoice_date)::date as period_start,
    (date_trunc('month', invoice_date) + interval '1 month - 1 day')::date as period_end,
    sum(total_amount) as total_sales,
    sum(case when sale_type = 'cash' then total_amount else 0 end) as cash_sales,
    sum(case when sale_type = 'credit' then total_amount else 0 end) as credit_sales,
    count(distinct party_id) filter (where party_id is not null) as distinct_customers,
    count(distinct invoice_date) as active_days
  from public.invoices
  where status = 'posted'
    and voided_at is null
  group by
    tenant_id,
    date_trunc('month', invoice_date)
),
payment_months as (
  select
    tenant_id,
    date_trunc('month', payment_date)::date as period_start,
    sum(amount) as collections,
    sum(amount) filter (
      where payment_channel in ('momo', 'airtel', 'bank', 'card', 'ebm')
        or payment_method in ('momo', 'airtel', 'bank', 'card')
    ) as digital_collections
  from public.payments
  where status = 'posted'
    and voided_at is null
  group by
    tenant_id,
    date_trunc('month', payment_date)
)
select
  im.tenant_id,
  im.period_start,
  im.period_end,
  im.total_sales,
  im.cash_sales,
  im.credit_sales,
  coalesce(pm.collections, 0) as collections,
  im.distinct_customers,
  im.active_days,
  case
    when coalesce(pm.collections, 0) = 0 then 0
    else coalesce(pm.digital_collections, 0) / nullif(pm.collections, 0)
  end as digital_payment_ratio
from invoice_months im
left join payment_months pm
  on pm.tenant_id = im.tenant_id
 and pm.period_start = im.period_start;

-- SME bankability rollup from snapshots.
create or replace view public.vw_sme_bankability as
select
  s.tenant_id,
  sum(s.total_sales) as ttm_sales,
  avg(s.total_sales) as avg_monthly_sales,
  case
    when avg(s.total_sales) = 0 then null
    else stddev_pop(s.total_sales) / nullif(avg(s.total_sales), 0)
  end as sales_cv,
  avg(s.avg_collection_days) as avg_dso,
  sum(s.overdue_receivables) / nullif(sum(s.receivables_outstanding), 0) as overdue_ratio,
  count(*) filter (where s.total_sales > 0) as active_months,
  avg(s.digital_payment_ratio) as avg_digital_ratio,
  avg(s.repeat_customer_ratio) as avg_repeat_ratio,
  avg(s.inventory_turnover_est) as avg_inventory_turnover_est,
  max(s.computed_at) as latest_snapshot_at
from public.sme_financial_snapshots s
where s.period_start >= (current_date - interval '12 month')
group by s.tenant_id;

-- DSCR input proxy.
create or replace view public.vw_dscr_inputs as
select
  b.tenant_id,
  b.ttm_sales,
  -- This is a placeholder proxy. Replace with better margin logic later.
  (b.ttm_sales * 0.20) as operating_cash_proxy,
  coalesce(sum(f.periodic_debt_service) * 12, 0) as annual_debt_service,
  case
    when coalesce(sum(f.periodic_debt_service), 0) = 0 then null
    else (b.ttm_sales * 0.20) / nullif((sum(f.periodic_debt_service) * 12), 0)
  end as indicative_dscr
from public.vw_sme_bankability b
left join public.external_facilities f
  on f.tenant_id = b.tenant_id
 and f.status = 'active'
group by
  b.tenant_id,
  b.ttm_sales;

-- ------------------------------------------------------------
-- 7. Enable RLS
-- ------------------------------------------------------------

alter table public.sme_credit_consents enable row level security;
alter table public.sme_financial_snapshots enable row level security;
alter table public.credit_score_runs enable row level security;
alter table public.credit_events enable row level security;
alter table public.external_facilities enable row level security;

-- ------------------------------------------------------------
-- 8. RLS: sme_credit_consents
-- ------------------------------------------------------------

drop policy if exists sme_credit_consents_select_if_credit_view
on public.sme_credit_consents;

create policy sme_credit_consents_select_if_credit_view
on public.sme_credit_consents
for select
using (
  public.user_has_permission(tenant_id, 'credit_readiness.view')
  or public.user_has_permission(tenant_id, 'credit_readiness.manage')
);

drop policy if exists sme_credit_consents_manage_if_credit_manage
on public.sme_credit_consents;

create policy sme_credit_consents_manage_if_credit_manage
on public.sme_credit_consents
for all
using (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
)
with check (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
);

-- ------------------------------------------------------------
-- 9. RLS: sme_financial_snapshots
-- ------------------------------------------------------------

drop policy if exists sme_financial_snapshots_select_if_credit_view
on public.sme_financial_snapshots;

create policy sme_financial_snapshots_select_if_credit_view
on public.sme_financial_snapshots
for select
using (
  public.user_has_permission(tenant_id, 'credit_readiness.view')
  or public.user_has_permission(tenant_id, 'credit_readiness.manage')
  or public.user_has_permission(tenant_id, 'reports.view')
);

drop policy if exists sme_financial_snapshots_manage_if_credit_manage
on public.sme_financial_snapshots;

create policy sme_financial_snapshots_manage_if_credit_manage
on public.sme_financial_snapshots
for all
using (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
)
with check (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
);

-- ------------------------------------------------------------
-- 10. RLS: credit_score_runs
-- ------------------------------------------------------------

drop policy if exists credit_score_runs_select_if_credit_view
on public.credit_score_runs;

create policy credit_score_runs_select_if_credit_view
on public.credit_score_runs
for select
using (
  public.user_has_permission(tenant_id, 'credit_readiness.view')
  or public.user_has_permission(tenant_id, 'credit_readiness.manage')
);

drop policy if exists credit_score_runs_manage_if_credit_manage
on public.credit_score_runs;

create policy credit_score_runs_manage_if_credit_manage
on public.credit_score_runs
for all
using (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
)
with check (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
);

-- ------------------------------------------------------------
-- 11. RLS: credit_events
-- ------------------------------------------------------------

drop policy if exists credit_events_select_if_credit_view
on public.credit_events;

create policy credit_events_select_if_credit_view
on public.credit_events
for select
using (
  public.user_has_permission(tenant_id, 'credit_readiness.view')
  or public.user_has_permission(tenant_id, 'credit_readiness.manage')
);

drop policy if exists credit_events_manage_if_credit_manage
on public.credit_events;

create policy credit_events_manage_if_credit_manage
on public.credit_events
for all
using (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
)
with check (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
);

-- ------------------------------------------------------------
-- 12. RLS: external_facilities
-- ------------------------------------------------------------

drop policy if exists external_facilities_select_if_credit_view
on public.external_facilities;

create policy external_facilities_select_if_credit_view
on public.external_facilities
for select
using (
  public.user_has_permission(tenant_id, 'credit_readiness.view')
  or public.user_has_permission(tenant_id, 'credit_readiness.manage')
);

drop policy if exists external_facilities_manage_if_credit_manage
on public.external_facilities;

create policy external_facilities_manage_if_credit_manage
on public.external_facilities
for all
using (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
)
with check (
  public.user_has_permission(tenant_id, 'credit_readiness.manage')
);

-- ------------------------------------------------------------
-- End of Migration 007
-- ------------------------------------------------------------