-- ============================================================
-- Consolidate stock into one warehouse (single-store tenants)
-- Run diagnose_product_stock.sql query #5 first to confirm duplicates.
-- Replace tenant_id before running.
-- ============================================================

begin;

-- Canonical warehouse = default flag first, then most movements.
with ranked as (
  select
    w.id as warehouse_id,
    w.branch_id,
    w.name,
    w.warehouse_code,
    w.is_default,
    count(sm.id) as movement_count,
    row_number() over (
      order by w.is_default desc, count(sm.id) desc, w.created_at
    ) as rn
  from public.warehouses w
  left join public.stock_movements sm
    on sm.warehouse_id = w.id
   and sm.voided_at is null
  where w.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  group by w.id, w.branch_id, w.name, w.warehouse_code, w.is_default, w.created_at
),
canonical as (
  select warehouse_id, branch_id, name, warehouse_code
  from ranked
  where rn = 1
),
moved as (
  update public.stock_movements sm
  set
    warehouse_id = c.warehouse_id,
    branch_id = c.branch_id
  from canonical c
  where sm.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
    and sm.voided_at is null
    and sm.warehouse_id <> c.warehouse_id
  returning sm.id
)
select
  c.warehouse_id as kept_warehouse_id,
  c.name as kept_warehouse_name,
  c.warehouse_code as kept_warehouse_code,
  (select count(*) from moved) as movements_moved
from canonical c;

commit;

-- After commit: Current Stock should show one row per product.
-- Optional: deactivate extra empty warehouses in Supabase Table Editor.
