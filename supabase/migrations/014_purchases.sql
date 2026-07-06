-- ============================================================
-- SME-OS Migration 014
-- Purchases, purchase lines, post_purchase RPC, inventory valuation
--
-- Creates:
--   - purchases
--   - purchase_lines
--   - post_purchase()
--   - vw_inventory_valuation
--   - purchases.view / purchases.create / purchases.void permissions
--
-- Also adds purchase number sequence and backfills existing tenants.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Extend number_sequences for purchase documents
-- ------------------------------------------------------------

alter table public.number_sequences
  drop constraint if exists number_sequences_code_check;

alter table public.number_sequences
  add constraint number_sequences_code_check
  check (sequence_code in (
    'invoice',
    'receipt',
    'stock_adjustment',
    'credit_note',
    'payment',
    'purchase'
  ));

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
select
  b.tenant_id,
  b.id,
  'purchase',
  'PUR-',
  0,
  6,
  'never',
  'active'
from public.branches b
where b.is_default = true
on conflict (tenant_id, branch_id, sequence_code) do nothing;

-- ------------------------------------------------------------
-- 2. Purchases header
-- ------------------------------------------------------------

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,

  purchase_number text not null,
  purchase_date date not null default current_date,

  party_id uuid references public.parties(id) on delete restrict,

  status text not null default 'draft',

  subtotal_amount numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null default 0,

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

  constraint purchases_tenant_purchase_number_unique
    unique (tenant_id, purchase_number),

  constraint purchases_status_check
    check (status in ('draft', 'posted', 'voided', 'cancelled')),

  constraint purchases_amounts_check
    check (
      subtotal_amount >= 0
      and discount_amount >= 0
      and tax_amount >= 0
      and total_amount >= 0
    )
);

create index if not exists idx_purchases_tenant_id
on public.purchases (tenant_id);

create index if not exists idx_purchases_tenant_date
on public.purchases (tenant_id, purchase_date);

create index if not exists idx_purchases_tenant_party
on public.purchases (tenant_id, party_id);

create index if not exists idx_purchases_tenant_status
on public.purchases (tenant_id, status);

create trigger trg_purchases_set_updated_at
before update on public.purchases
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3. Purchase lines
-- ------------------------------------------------------------

create table if not exists public.purchase_lines (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_id uuid not null references public.purchases(id) on delete cascade,

  line_number integer not null,

  product_id uuid not null references public.products(id) on delete restrict,

  description text,

  quantity numeric(14,3) not null,
  unit_id uuid not null references public.product_units(id) on delete restrict,

  unit_cost numeric(14,2) not null,
  discount_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  line_total numeric(14,2) not null default 0,

  warehouse_id uuid references public.warehouses(id) on delete restrict,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,

  constraint purchase_lines_purchase_line_number_unique
    unique (purchase_id, line_number),

  constraint purchase_lines_quantity_check
    check (quantity > 0),

  constraint purchase_lines_amounts_check
    check (
      unit_cost >= 0
      and discount_amount >= 0
      and tax_amount >= 0
      and line_total >= 0
    )
);

create index if not exists idx_purchase_lines_tenant_purchase
on public.purchase_lines (tenant_id, purchase_id);

create index if not exists idx_purchase_lines_tenant_product
on public.purchase_lines (tenant_id, product_id);

create trigger trg_purchase_lines_set_updated_at
before update on public.purchase_lines
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 4. post_purchase RPC
-- Posts purchase, stock movements, and weighted-average cost.
-- ------------------------------------------------------------

create or replace function public.post_purchase(
  target_tenant_id uuid,
  target_branch_id uuid,
  target_warehouse_id uuid,
  p_party_id uuid,
  p_notes text,
  p_lines jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_document_number text;
  v_purchase_id uuid;
  v_line jsonb;
  v_line_number integer := 0;
  v_product_id uuid;
  v_quantity numeric(14,3);
  v_unit_cost numeric(14,2);
  v_line_total numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_product_name text;
  v_base_unit_id uuid;
  v_is_tracked boolean;
  v_product_status text;
  v_line_id uuid;
  v_old_qty numeric(14,3);
  v_old_cost numeric(18,4);
  v_new_cost numeric(18,4);
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated.';
  end if;

  if not public.user_has_permission(target_tenant_id, 'purchases.create') then
    raise exception 'You do not have permission to create purchases.';
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'Purchase must have at least one line.';
  end if;

  if p_party_id is not null then
    if not exists (
      select 1
      from public.parties p
      where p.id = p_party_id
        and p.tenant_id = target_tenant_id
        and p.deleted_at is null
    ) then
      raise exception 'Supplier not found for this tenant.';
    end if;
  end if;

  perform public.ensure_purchase_number_sequence(
    target_tenant_id,
    target_branch_id
  );

  v_document_number := public.get_next_document_number(
    target_tenant_id,
    target_branch_id,
    'purchase'
  );

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line ->> 'product_id')::uuid;
    v_quantity := (v_line ->> 'quantity')::numeric(14,3);
    v_unit_cost := (v_line ->> 'unit_cost')::numeric(14,2);

    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Each line must have quantity greater than zero.';
    end if;

    if v_unit_cost is null or v_unit_cost < 0 then
      raise exception 'Each line must have a valid unit cost.';
    end if;

    select
      product_name,
      base_unit_id,
      is_inventory_tracked,
      status
    into
      v_product_name,
      v_base_unit_id,
      v_is_tracked,
      v_product_status
    from public.products
    where id = v_product_id
      and tenant_id = target_tenant_id;

    if v_product_name is null then
      raise exception 'Product not found: %', v_product_id;
    end if;

    if v_product_status <> 'active' then
      raise exception 'Product % is not active.', v_product_name;
    end if;

    v_line_total := round(v_quantity * v_unit_cost, 2);
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  insert into public.purchases (
    tenant_id,
    branch_id,
    warehouse_id,
    purchase_number,
    purchase_date,
    party_id,
    status,
    subtotal_amount,
    discount_amount,
    tax_amount,
    total_amount,
    notes,
    created_by,
    posted_at
  )
  values (
    target_tenant_id,
    target_branch_id,
    target_warehouse_id,
    v_document_number,
    current_date,
    p_party_id,
    'posted',
    v_subtotal,
    0,
    0,
    v_subtotal,
    nullif(p_notes, ''),
    v_user_id,
    now()
  )
  returning id into v_purchase_id;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_line_number := v_line_number + 1;
    v_product_id := (v_line ->> 'product_id')::uuid;
    v_quantity := (v_line ->> 'quantity')::numeric(14,3);
    v_unit_cost := (v_line ->> 'unit_cost')::numeric(14,2);
    v_line_total := round(v_quantity * v_unit_cost, 2);

    select product_name, base_unit_id, is_inventory_tracked
    into v_product_name, v_base_unit_id, v_is_tracked
    from public.products
    where id = v_product_id;

    insert into public.purchase_lines (
      tenant_id,
      purchase_id,
      line_number,
      product_id,
      description,
      quantity,
      unit_id,
      unit_cost,
      discount_amount,
      tax_amount,
      line_total,
      warehouse_id,
      created_by
    )
    values (
      target_tenant_id,
      v_purchase_id,
      v_line_number,
      v_product_id,
      v_product_name,
      v_quantity,
      v_base_unit_id,
      v_unit_cost,
      0,
      0,
      v_line_total,
      target_warehouse_id,
      v_user_id
    )
    returning id into v_line_id;

    select coalesce(sum(sm.quantity_in - sm.quantity_out), 0)
    into v_old_qty
    from public.stock_movements sm
    where sm.tenant_id = target_tenant_id
      and sm.product_id = v_product_id
      and sm.voided_at is null;

    select p.cost_price
    into v_old_cost
    from public.products p
    where p.id = v_product_id;

    if coalesce(v_old_qty, 0) + v_quantity > 0 then
      v_new_cost :=
        (
          coalesce(v_old_qty, 0) * coalesce(v_old_cost, 0)
          + v_quantity * v_unit_cost
        ) / (coalesce(v_old_qty, 0) + v_quantity);
    else
      v_new_cost := v_unit_cost;
    end if;

    update public.products
    set
      cost_price = v_new_cost,
      updated_at = now()
    where id = v_product_id;

    if v_is_tracked then
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
        source_table,
        source_id,
        reference_number,
        reason,
        created_by
      )
      values (
        target_tenant_id,
        target_branch_id,
        target_warehouse_id,
        v_product_id,
        current_date,
        'purchase',
        v_quantity,
        0,
        v_unit_cost,
        round(v_quantity * v_unit_cost, 4),
        'purchase_lines',
        v_line_id,
        v_document_number,
        'Purchase receipt',
        v_user_id
      );
    end if;
  end loop;

  return v_document_number;
end;
$$;

-- ------------------------------------------------------------
-- 5. Inventory valuation view
-- ------------------------------------------------------------

create or replace view public.vw_inventory_valuation as
select
  cs.tenant_id,
  cs.warehouse_id,
  cs.warehouse_name,
  cs.product_id,
  cs.product_code,
  cs.product_name,
  cs.current_quantity,
  p.cost_price,
  round(cs.current_quantity * coalesce(p.cost_price, 0), 2) as inventory_value
from public.vw_current_stock cs
join public.products p on p.id = cs.product_id
where cs.current_quantity > 0;

-- ------------------------------------------------------------
-- 6. Permissions
-- ------------------------------------------------------------

insert into public.permissions (
  permission_code,
  module_code,
  description,
  risk_level
)
values
  ('purchases.view', 'purchases', 'View purchases.', 'low'),
  ('purchases.create', 'purchases', 'Create and post purchases.', 'medium'),
  ('purchases.void', 'purchases', 'Void posted purchases.', 'high')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id, is_allowed)
select r.id, p.id, true
from public.roles r
join public.permissions p
  on p.permission_code in (
    'purchases.view',
    'purchases.create',
    'purchases.void'
  )
where r.tenant_id is null
  and r.role_code = 'owner'
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id, is_allowed)
select r.id, p.id, true
from public.roles r
join public.permissions p
  on p.permission_code in (
    'purchases.view',
    'purchases.create'
  )
where r.tenant_id is null
  and r.role_code in ('manager', 'storekeeper')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id, is_allowed)
select r.id, p.id, true
from public.roles r
join public.permissions p
  on p.permission_code = 'purchases.view'
where r.tenant_id is null
  and r.role_code = 'auditor'
on conflict do nothing;

-- ------------------------------------------------------------
-- 7. Enable RLS
-- ------------------------------------------------------------

alter table public.purchases enable row level security;
alter table public.purchase_lines enable row level security;

-- ------------------------------------------------------------
-- 8. RLS: purchases
-- ------------------------------------------------------------

drop policy if exists purchases_select_if_purchases_or_reports
on public.purchases;

create policy purchases_select_if_purchases_or_reports
on public.purchases
for select
using (
  public.user_has_permission(tenant_id, 'purchases.view')
  or public.user_has_permission(tenant_id, 'purchases.create')
  or public.user_has_permission(tenant_id, 'reports.view')
);

drop policy if exists purchases_insert_if_purchases_create
on public.purchases;

create policy purchases_insert_if_purchases_create
on public.purchases
for insert
with check (
  public.user_has_permission(tenant_id, 'purchases.create')
);

drop policy if exists purchases_update_if_purchases_create_or_void
on public.purchases;

create policy purchases_update_if_purchases_create_or_void
on public.purchases
for update
using (
  public.user_has_permission(tenant_id, 'purchases.create')
  or public.user_has_permission(tenant_id, 'purchases.void')
)
with check (
  public.user_has_permission(tenant_id, 'purchases.create')
  or public.user_has_permission(tenant_id, 'purchases.void')
);

-- ------------------------------------------------------------
-- 9. RLS: purchase_lines
-- ------------------------------------------------------------

drop policy if exists purchase_lines_select_if_purchases_or_reports
on public.purchase_lines;

create policy purchase_lines_select_if_purchases_or_reports
on public.purchase_lines
for select
using (
  public.user_has_permission(tenant_id, 'purchases.view')
  or public.user_has_permission(tenant_id, 'purchases.create')
  or public.user_has_permission(tenant_id, 'reports.view')
);

drop policy if exists purchase_lines_insert_if_purchases_create
on public.purchase_lines;

create policy purchase_lines_insert_if_purchases_create
on public.purchase_lines
for insert
with check (
  public.user_has_permission(tenant_id, 'purchases.create')
);

drop policy if exists purchase_lines_update_if_purchases_create
on public.purchase_lines;

create policy purchase_lines_update_if_purchases_create
on public.purchase_lines
for update
using (
  public.user_has_permission(tenant_id, 'purchases.create')
)
with check (
  public.user_has_permission(tenant_id, 'purchases.create')
);

-- ------------------------------------------------------------
-- 10. Ensure new tenants get purchase number sequence
-- ------------------------------------------------------------

create or replace function public.ensure_purchase_number_sequence(
  target_tenant_id uuid,
  target_branch_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
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
  values (
    target_tenant_id,
    target_branch_id,
    'purchase',
    'PUR-',
    0,
    6,
    'never',
    'active'
  )
  on conflict (tenant_id, branch_id, sequence_code) do nothing;
end;
$$;

-- ------------------------------------------------------------
-- End of Migration 014
-- ------------------------------------------------------------
