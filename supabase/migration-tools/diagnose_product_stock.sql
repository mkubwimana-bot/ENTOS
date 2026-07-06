-- ============================================================
-- Diagnose stock for one product (e.g. 00012 / Congo Original)
-- Replace tenant_id and product_code before running.
-- ============================================================

-- 1) Current stock rows (one row per warehouse — duplicates here = split stock)
select
  cs.product_code,
  cs.product_name,
  cs.warehouse_name,
  cs.warehouse_id,
  cs.current_quantity
from public.vw_current_stock cs
where cs.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and cs.product_code = '00012'
order by cs.warehouse_name;

-- 2) Net quantity across all warehouses (should match what you expect)
select
  p.product_code,
  p.product_name,
  sum(cs.current_quantity) as total_on_hand
from public.vw_current_stock cs
join public.products p on p.id = cs.product_id
where cs.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and p.product_code = '00012'
group by p.product_code, p.product_name;

-- 3) Movement breakdown by warehouse (look for manual adjustments on a different warehouse)
select
  w.name as warehouse_name,
  w.id as warehouse_id,
  w.is_default as warehouse_is_default,
  sm.movement_type,
  sm.movement_date,
  sm.quantity_in,
  sm.quantity_out,
  sm.reason,
  sm.reference_number,
  sm.created_at
from public.stock_movements sm
join public.products p on p.id = sm.product_id
join public.warehouses w on w.id = sm.warehouse_id
where sm.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and p.product_code = '00012'
  and sm.voided_at is null
order by sm.movement_date, sm.created_at;

-- 4) Compare import warehouse vs app default warehouse
select
  w.id,
  w.name,
  w.warehouse_code,
  w.is_default,
  b.name as branch_name,
  (select count(*)
   from public.stock_movements sm
   join public.products p on p.id = sm.product_id
   where sm.warehouse_id = w.id
     and p.product_code = '00012'
     and sm.voided_at is null) as movements_for_00012
from public.warehouses w
join public.branches b on b.id = w.branch_id
where w.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
order by w.is_default desc, w.name;

-- 5) Duplicate warehouse names (same label, different ids — looks like duplicate products)
select
  w.name,
  count(*) as warehouse_count,
  array_agg(w.id order by w.is_default desc) as warehouse_ids,
  array_agg(w.warehouse_code order by w.is_default desc) as warehouse_codes
from public.warehouses w
where w.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
group by w.name
having count(*) > 1;
