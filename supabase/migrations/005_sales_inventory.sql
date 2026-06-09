-- ============================================================
-- SME-OS Migration 005
-- Sales, Payments, Inventory and MVP Views
--
-- Creates:
--   - invoices
--   - invoice_lines
--   - payments
--   - payment_allocations
--   - stock_movements
--
-- Creates views:
--   - vw_current_stock
--   - vw_low_stock
--   - vw_customer_balances
--   - vw_daily_sales
--   - vw_product_sales_summary
--   - vw_gross_profit_simple
--
-- No-Docker workflow:
-- Save this file in Cursor, then copy and run it in Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Invoices
-- Sales document header.
-- Supports cash sales, credit sales, and mixed sales.
-- ------------------------------------------------------------

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  warehouse_id uuid references public.warehouses(id) on delete restrict,

  invoice_number text not null,
  invoice_date date not null default current_date,

  party_id uuid references public.parties(id) on delete restrict,

  sale_type text not null default 'cash',
  status text not null default 'draft',

  subtotal_amount numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null default 0,

  paid_amount numeric(14,2) not null default 0,
  balance_amount numeric(14,2) not null default 0,

  due_date date,

  notes text,

  external_status text,

  created_by uuid references public.app_users(id) on delete set null,
  posted_at timestamptz,
  voided_at timestamptz,
  voided_by uuid references public.app_users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,
  deleted_at timestamptz,
  deleted_by uuid references public.app_users(id) on delete set null,

  constraint invoices_tenant_invoice_number_unique
    unique (tenant_id, invoice_number),

  constraint invoices_sale_type_check
    check (sale_type in ('cash', 'credit', 'mixed')),

  constraint invoices_status_check
    check (status in ('draft', 'posted', 'voided', 'cancelled')),

  constraint invoices_amounts_check
    check (
      subtotal_amount >= 0
      and discount_amount >= 0
      and tax_amount >= 0
      and total_amount >= 0
      and paid_amount >= 0
      and balance_amount >= 0
    ),

  constraint invoices_credit_requires_customer_check
    check (
      sale_type <> 'credit'
      or party_id is not null
    )
);

create index if not exists idx_invoices_tenant_id
on public.invoices (tenant_id);

create index if not exists idx_invoices_tenant_date
on public.invoices (tenant_id, invoice_date);

create index if not exists idx_invoices_tenant_party
on public.invoices (tenant_id, party_id);

create index if not exists idx_invoices_tenant_status
on public.invoices (tenant_id, status);

create index if not exists idx_invoices_branch_id
on public.invoices (branch_id);

create trigger trg_invoices_set_updated_at
before update on public.invoices
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 2. Invoice Lines
-- Sales document detail lines.
-- ------------------------------------------------------------

create table if not exists public.invoice_lines (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,

  line_number integer not null,

  product_id uuid not null references public.products(id) on delete restrict,

  description text,

  quantity numeric(14,3) not null,
  unit_id uuid not null references public.product_units(id) on delete restrict,

  unit_price numeric(14,2) not null,
  discount_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  line_total numeric(14,2) not null default 0,

  cost_price_snapshot numeric(18,4),

  warehouse_id uuid references public.warehouses(id) on delete restrict,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,

  constraint invoice_lines_invoice_line_number_unique
    unique (invoice_id, line_number),

  constraint invoice_lines_quantity_check
    check (quantity > 0),

  constraint invoice_lines_amounts_check
    check (
      unit_price >= 0
      and discount_amount >= 0
      and tax_amount >= 0
      and line_total >= 0
    ),

  constraint invoice_lines_cost_price_snapshot_check
    check (
      cost_price_snapshot is null
      or cost_price_snapshot >= 0
    )
);

create index if not exists idx_invoice_lines_tenant_invoice
on public.invoice_lines (tenant_id, invoice_id);

create index if not exists idx_invoice_lines_tenant_product
on public.invoice_lines (tenant_id, product_id);

create index if not exists idx_invoice_lines_warehouse
on public.invoice_lines (warehouse_id);

create trigger trg_invoice_lines_set_updated_at
before update on public.invoice_lines
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3. Payments
-- Records money received from customers.
-- ------------------------------------------------------------

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,

  payment_number text not null,
  payment_date date not null default current_date,

  party_id uuid references public.parties(id) on delete restrict,

  payment_method text not null default 'cash',
  payment_channel text,

  amount numeric(14,2) not null,
  currency_code text not null default 'RWF',

  provider_reference text,

  status text not null default 'draft',

  notes text,

  created_by uuid references public.app_users(id) on delete set null,
  posted_at timestamptz,
  voided_at timestamptz,
  voided_by uuid references public.app_users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,
  deleted_at timestamptz,
  deleted_by uuid references public.app_users(id) on delete set null,

  constraint payments_tenant_payment_number_unique
    unique (tenant_id, payment_number),

  constraint payments_payment_method_check
    check (payment_method in (
      'cash',
      'momo',
      'airtel',
      'bank',
      'card',
      'other'
    )),

  constraint payments_payment_channel_check
    check (
      payment_channel is null
      or payment_channel in (
        'cash',
        'momo',
        'airtel',
        'bank',
        'card',
        'ebm',
        'other'
      )
    ),

  constraint payments_status_check
    check (status in ('draft', 'posted', 'voided', 'reversed', 'cancelled')),

  constraint payments_amount_check
    check (amount > 0)
);

create index if not exists idx_payments_tenant_id
on public.payments (tenant_id);

create index if not exists idx_payments_tenant_party_date
on public.payments (tenant_id, party_id, payment_date);

create index if not exists idx_payments_tenant_status
on public.payments (tenant_id, status);

create index if not exists idx_payments_provider_reference
on public.payments (payment_method, provider_reference);

create trigger trg_payments_set_updated_at
before update on public.payments
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 4. Payment Allocations
-- Allocates one payment to one or more invoices.
-- ------------------------------------------------------------

create table if not exists public.payment_allocations (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,

  payment_id uuid not null references public.payments(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete restrict,

  allocated_amount numeric(14,2) not null,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,

  constraint payment_allocations_payment_invoice_unique
    unique (payment_id, invoice_id),

  constraint payment_allocations_amount_check
    check (allocated_amount > 0)
);

create index if not exists idx_payment_allocations_tenant_payment
on public.payment_allocations (tenant_id, payment_id);

create index if not exists idx_payment_allocations_tenant_invoice
on public.payment_allocations (tenant_id, invoice_id);

-- ------------------------------------------------------------
-- 5. Stock Movements
-- Source of truth for inventory.
-- Current stock is calculated from quantity_in - quantity_out.
-- ------------------------------------------------------------

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,

  movement_date date not null default current_date,
  movement_type text not null,

  quantity_in numeric(14,3) not null default 0,
  quantity_out numeric(14,3) not null default 0,

  unit_cost numeric(18,4),
  total_cost numeric(18,4),

  source_table text,
  source_id uuid,
  reference_number text,

  reason text,

  created_by uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),

  voided_at timestamptz,
  voided_by uuid references public.app_users(id) on delete set null,

  constraint stock_movements_type_check
    check (movement_type in (
      'opening',
      'purchase',
      'sale',
      'adjustment',
      'transfer_in',
      'transfer_out',
      'production_in',
      'production_out',
      'return',
      'offline_pending',
      'reversal'
    )),

  constraint stock_movements_quantities_check
    check (
      quantity_in >= 0
      and quantity_out >= 0
      and (
        quantity_in > 0
        or quantity_out > 0
      )
      and not (
        quantity_in > 0
        and quantity_out > 0
      )
    ),

  constraint stock_movements_cost_check
    check (
      (unit_cost is null or unit_cost >= 0)
      and (total_cost is null or total_cost >= 0)
    )
);

create index if not exists idx_stock_movements_tenant_product_date
on public.stock_movements (tenant_id, product_id, movement_date);

create index if not exists idx_stock_movements_tenant_warehouse_product
on public.stock_movements (tenant_id, warehouse_id, product_id);

create index if not exists idx_stock_movements_source
on public.stock_movements (source_table, source_id);

create index if not exists idx_stock_movements_tenant_type
on public.stock_movements (tenant_id, movement_type);

-- ------------------------------------------------------------
-- 6. Helper function: recalculate invoice paid and balance
-- ------------------------------------------------------------

create or replace function public.recalculate_invoice_payment_totals(target_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total numeric(14,2);
  v_paid numeric(14,2);
begin
  select total_amount
  into v_total
  from public.invoices
  where id = target_invoice_id;

  select coalesce(sum(pa.allocated_amount), 0)
  into v_paid
  from public.payment_allocations pa
  join public.payments p on p.id = pa.payment_id
  where pa.invoice_id = target_invoice_id
    and p.status = 'posted'
    and p.voided_at is null;

  update public.invoices
  set
    paid_amount = coalesce(v_paid, 0),
    balance_amount = greatest(coalesce(v_total, 0) - coalesce(v_paid, 0), 0),
    updated_at = now()
  where id = target_invoice_id;
end;
$$;

-- ------------------------------------------------------------
-- 7. Trigger: update invoice payment totals after allocations
-- ------------------------------------------------------------

create or replace function public.trg_recalculate_invoice_after_allocation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalculate_invoice_payment_totals(old.invoice_id);
    return old;
  else
    perform public.recalculate_invoice_payment_totals(new.invoice_id);
    return new;
  end if;
end;
$$;

drop trigger if exists trg_payment_allocations_recalculate_invoice
on public.payment_allocations;

create trigger trg_payment_allocations_recalculate_invoice
after insert or update or delete on public.payment_allocations
for each row
execute function public.trg_recalculate_invoice_after_allocation();

-- ------------------------------------------------------------
-- 8. MVP Views
-- ------------------------------------------------------------

-- Current stock by tenant, warehouse, and product.
create or replace view public.vw_current_stock as
select
  sm.tenant_id,
  sm.warehouse_id,
  w.name as warehouse_name,
  sm.product_id,
  p.product_code,
  p.product_name,
  p.reorder_level,
  sum(sm.quantity_in - sm.quantity_out) as current_quantity
from public.stock_movements sm
join public.products p on p.id = sm.product_id
join public.warehouses w on w.id = sm.warehouse_id
where sm.voided_at is null
group by
  sm.tenant_id,
  sm.warehouse_id,
  w.name,
  sm.product_id,
  p.product_code,
  p.product_name,
  p.reorder_level;

-- Low stock view.
create or replace view public.vw_low_stock as
select
  cs.*
from public.vw_current_stock cs
where cs.reorder_level is not null
  and cs.current_quantity <= cs.reorder_level;

-- Customer balances from posted invoices and posted payments.
create or replace view public.vw_customer_balances as
select
  p.tenant_id,
  p.id as party_id,
  p.party_code,
  p.party_name,
  p.opening_balance,
  coalesce(sum(i.total_amount) filter (
    where i.status = 'posted'
      and i.voided_at is null
  ), 0) as total_invoiced,
  coalesce(sum(pa.allocated_amount) filter (
    where pay.status = 'posted'
      and pay.voided_at is null
  ), 0) as total_paid,
  p.opening_balance
    + coalesce(sum(i.total_amount) filter (
        where i.status = 'posted'
          and i.voided_at is null
      ), 0)
    - coalesce(sum(pa.allocated_amount) filter (
        where pay.status = 'posted'
          and pay.voided_at is null
      ), 0) as balance
from public.parties p
left join public.invoices i
  on i.party_id = p.id
 and i.tenant_id = p.tenant_id
left join public.payment_allocations pa
  on pa.invoice_id = i.id
 and pa.tenant_id = p.tenant_id
left join public.payments pay
  on pay.id = pa.payment_id
 and pay.tenant_id = p.tenant_id
where p.deleted_at is null
group by
  p.tenant_id,
  p.id,
  p.party_code,
  p.party_name,
  p.opening_balance;

-- Daily sales totals.
create or replace view public.vw_daily_sales as
select
  tenant_id,
  branch_id,
  invoice_date,
  count(*) as invoice_count,
  sum(total_amount) as total_sales,
  sum(paid_amount) as total_paid,
  sum(balance_amount) as total_balance
from public.invoices
where status = 'posted'
  and voided_at is null
group by
  tenant_id,
  branch_id,
  invoice_date;

-- Product sales summary.
create or replace view public.vw_product_sales_summary as
select
  il.tenant_id,
  il.product_id,
  p.product_code,
  p.product_name,
  sum(il.quantity) as quantity_sold,
  sum(il.line_total) as total_sales,
  sum(coalesce(il.cost_price_snapshot, 0) * il.quantity) as estimated_cost,
  sum(il.line_total) - sum(coalesce(il.cost_price_snapshot, 0) * il.quantity) as estimated_gross_profit
from public.invoice_lines il
join public.invoices i on i.id = il.invoice_id
join public.products p on p.id = il.product_id
where i.status = 'posted'
  and i.voided_at is null
group by
  il.tenant_id,
  il.product_id,
  p.product_code,
  p.product_name;

-- Simple gross profit view by invoice.
create or replace view public.vw_gross_profit_simple as
select
  i.tenant_id,
  i.id as invoice_id,
  i.invoice_number,
  i.invoice_date,
  i.total_amount,
  sum(coalesce(il.cost_price_snapshot, 0) * il.quantity) as estimated_cost,
  i.total_amount - sum(coalesce(il.cost_price_snapshot, 0) * il.quantity) as estimated_gross_profit
from public.invoices i
join public.invoice_lines il on il.invoice_id = i.id
where i.status = 'posted'
  and i.voided_at is null
group by
  i.tenant_id,
  i.id,
  i.invoice_number,
  i.invoice_date,
  i.total_amount;

-- ------------------------------------------------------------
-- 9. Enable RLS
-- ------------------------------------------------------------

alter table public.invoices enable row level security;
alter table public.invoice_lines enable row level security;
alter table public.payments enable row level security;
alter table public.payment_allocations enable row level security;
alter table public.stock_movements enable row level security;

-- ------------------------------------------------------------
-- 10. RLS: invoices
-- ------------------------------------------------------------

drop policy if exists invoices_select_if_sales_or_reports
on public.invoices;

create policy invoices_select_if_sales_or_reports
on public.invoices
for select
using (
  public.user_has_permission(tenant_id, 'sales.view')
  or public.user_has_permission(tenant_id, 'sales.create')
  or public.user_has_permission(tenant_id, 'reports.view')
);

drop policy if exists invoices_insert_if_sales_create
on public.invoices;

create policy invoices_insert_if_sales_create
on public.invoices
for insert
with check (
  public.user_has_permission(tenant_id, 'sales.create')
);

drop policy if exists invoices_update_if_sales_create_or_void
on public.invoices;

create policy invoices_update_if_sales_create_or_void
on public.invoices
for update
using (
  public.user_has_permission(tenant_id, 'sales.create')
  or public.user_has_permission(tenant_id, 'sales.void')
)
with check (
  public.user_has_permission(tenant_id, 'sales.create')
  or public.user_has_permission(tenant_id, 'sales.void')
);

-- ------------------------------------------------------------
-- 11. RLS: invoice_lines
-- ------------------------------------------------------------

drop policy if exists invoice_lines_select_if_sales_or_reports
on public.invoice_lines;

create policy invoice_lines_select_if_sales_or_reports
on public.invoice_lines
for select
using (
  public.user_has_permission(tenant_id, 'sales.view')
  or public.user_has_permission(tenant_id, 'sales.create')
  or public.user_has_permission(tenant_id, 'reports.view')
);

drop policy if exists invoice_lines_insert_if_sales_create
on public.invoice_lines;

create policy invoice_lines_insert_if_sales_create
on public.invoice_lines
for insert
with check (
  public.user_has_permission(tenant_id, 'sales.create')
);

drop policy if exists invoice_lines_update_if_sales_create
on public.invoice_lines;

create policy invoice_lines_update_if_sales_create
on public.invoice_lines
for update
using (
  public.user_has_permission(tenant_id, 'sales.create')
)
with check (
  public.user_has_permission(tenant_id, 'sales.create')
);

-- ------------------------------------------------------------
-- 12. RLS: payments
-- ------------------------------------------------------------

drop policy if exists payments_select_if_payment_or_reports
on public.payments;

create policy payments_select_if_payment_or_reports
on public.payments
for select
using (
  public.user_has_permission(tenant_id, 'payments.view')
  or public.user_has_permission(tenant_id, 'payments.create')
  or public.user_has_permission(tenant_id, 'reports.view')
);

drop policy if exists payments_insert_if_payments_create
on public.payments;

create policy payments_insert_if_payments_create
on public.payments
for insert
with check (
  public.user_has_permission(tenant_id, 'payments.create')
);

drop policy if exists payments_update_if_payments_create_or_void
on public.payments;

create policy payments_update_if_payments_create_or_void
on public.payments
for update
using (
  public.user_has_permission(tenant_id, 'payments.create')
  or public.user_has_permission(tenant_id, 'payments.void')
)
with check (
  public.user_has_permission(tenant_id, 'payments.create')
  or public.user_has_permission(tenant_id, 'payments.void')
);

-- ------------------------------------------------------------
-- 13. RLS: payment_allocations
-- ------------------------------------------------------------

drop policy if exists payment_allocations_select_if_payments_or_reports
on public.payment_allocations;

create policy payment_allocations_select_if_payments_or_reports
on public.payment_allocations
for select
using (
  public.user_has_permission(tenant_id, 'payments.view')
  or public.user_has_permission(tenant_id, 'payments.create')
  or public.user_has_permission(tenant_id, 'reports.view')
);

drop policy if exists payment_allocations_manage_if_payments_create
on public.payment_allocations;

create policy payment_allocations_manage_if_payments_create
on public.payment_allocations
for all
using (
  public.user_has_permission(tenant_id, 'payments.create')
)
with check (
  public.user_has_permission(tenant_id, 'payments.create')
);

-- ------------------------------------------------------------
-- 14. RLS: stock_movements
-- ------------------------------------------------------------

drop policy if exists stock_movements_select_if_inventory_or_reports
on public.stock_movements;

create policy stock_movements_select_if_inventory_or_reports
on public.stock_movements
for select
using (
  public.user_has_permission(tenant_id, 'inventory.view')
  or public.user_has_permission(tenant_id, 'reports.view')
  or public.user_has_permission(tenant_id, 'sales.create')
  or public.user_has_permission(tenant_id, 'mobile.stock_check')
);

drop policy if exists stock_movements_insert_if_inventory_or_sales
on public.stock_movements;

create policy stock_movements_insert_if_inventory_or_sales
on public.stock_movements
for insert
with check (
  public.user_has_permission(tenant_id, 'inventory.adjust')
  or public.user_has_permission(tenant_id, 'sales.create')
);

drop policy if exists stock_movements_update_if_inventory_adjust
on public.stock_movements;

create policy stock_movements_update_if_inventory_adjust
on public.stock_movements
for update
using (
  public.user_has_permission(tenant_id, 'inventory.adjust')
)
with check (
  public.user_has_permission(tenant_id, 'inventory.adjust')
);

-- ------------------------------------------------------------
-- End of Migration 005
-- ------------------------------------------------------------