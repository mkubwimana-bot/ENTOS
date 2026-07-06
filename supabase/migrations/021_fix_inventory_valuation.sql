-- ============================================================
-- SME-OS Migration 021
-- Inventory valuation: merge stock across warehouses per product
--
-- vw_inventory_valuation filtered current_quantity > 0 per warehouse
-- row, so split stock (import vs adjustment) showed only the small
-- positive bucket (e.g. qty 5) and hid the migrated negative balance.
-- ============================================================

-- CREATE OR REPLACE cannot remove columns (warehouse_id, warehouse_name).
-- Drop and recreate.

drop view if exists public.vw_inventory_valuation;

create view public.vw_inventory_valuation as
select
  cs.tenant_id,
  cs.product_id,
  cs.product_code,
  cs.product_name,
  sum(cs.current_quantity) as current_quantity,
  p.cost_price,
  round(sum(cs.current_quantity) * coalesce(p.cost_price, 0), 2) as inventory_value
from public.vw_current_stock cs
join public.products p on p.id = cs.product_id
group by
  cs.tenant_id,
  cs.product_id,
  cs.product_code,
  cs.product_name,
  p.cost_price
having sum(cs.current_quantity) > 0;

alter view if exists public.vw_inventory_valuation set (security_invoker = true);
