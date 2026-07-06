-- ============================================================
-- Post-import validation for Entos full-history migration
-- Replace e9aefc3f-cc08-4bfe-9b42-c354c62388c5 before running in Supabase SQL Editor.
-- Each query should return ZERO rows on success (except summary counts).
-- ============================================================

-- Set once:
-- \set tenant_id 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'

-- ---------------------------------------------------------------------------
-- 1. Stock reconciliation vs staging expectations
-- Compare vw_current_stock to net from stg_entos (opening + movements, non-deleted)
-- ---------------------------------------------------------------------------

with expected as (
  select
    sp.legacy_id as product_id,
    p.product_name,
    sp.opening_qty
      + coalesce(sum(case when sm.movement_type = 'in' and not sm.deleted then sm.qty else 0 end), 0)
      + coalesce(sum(case when sm.movement_type = 'adjustment' and not sm.deleted then sm.qty else 0 end), 0)
      - coalesce(sum(case when sm.movement_type = 'out' and not sm.deleted then sm.qty else 0 end), 0)
      as expected_qty
  from public.stg_entos_products sp
  join public.products p
    on p.id = (
      select m.new_id
      from public.migration_id_map m
      where m.tenant_id = sp.tenant_id
        and m.entity_type = 'product'
        and m.legacy_id = sp.legacy_id
      limit 1
    )
  left join public.stg_entos_movements sm
    on sm.tenant_id = sp.tenant_id
   and sm.product_id = sp.legacy_id
  where sp.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
    and not sp.deleted
  group by sp.legacy_id, p.product_name, sp.opening_qty
),
actual as (
  select
    cs.product_id,
    cs.product_name,
    cs.current_quantity
  from public.vw_current_stock cs
  where cs.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
)
select
  coalesce(e.product_name, a.product_name) as product_name,
  e.expected_qty,
  a.current_quantity as actual_qty,
  coalesce(a.current_quantity, 0) - coalesce(e.expected_qty, 0) as diff
from expected e
full outer join actual a on a.product_id = (
  select m.new_id from public.migration_id_map m
  where m.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
    and m.entity_type = 'product'
    and m.legacy_id = e.product_id
  limit 1
)
where abs(coalesce(a.current_quantity, 0) - coalesce(e.expected_qty, 0)) > 0.001;

-- ---------------------------------------------------------------------------
-- 2. Customer balance reconciliation (unpaid credit outs from staging)
-- ---------------------------------------------------------------------------

with expected as (
  select
    sm.customer_id as legacy_party_id,
    sum(sm.qty * sm.unit_price) as expected_balance
  from public.stg_entos_movements sm
  where sm.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
    and sm.movement_type = 'out'
    and not sm.deleted
    and not coalesce(sm.paid, true)
    and sm.customer_id is not null
  group by sm.customer_id
),
actual as (
  select
    m.legacy_id as legacy_party_id,
    vb.balance
  from public.vw_customer_balances vb
  join public.migration_id_map m
    on m.new_id = vb.party_id
   and m.tenant_id = vb.tenant_id
   and m.entity_type = 'party'
  where vb.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
)
select
  e.legacy_party_id,
  e.expected_balance,
  a.balance as actual_balance,
  coalesce(a.balance, 0) - e.expected_balance as diff
from expected e
left join actual a using (legacy_party_id)
where abs(coalesce(a.balance, 0) - e.expected_balance) > 0.01;

-- ---------------------------------------------------------------------------
-- 3. Document count reconciliation
-- ---------------------------------------------------------------------------

with staged as (
  select
    count(*) filter (where movement_type = 'in') as stg_purchases,
    count(*) filter (where movement_type = 'out') as stg_invoices,
    count(*) filter (where movement_type = 'adjustment') as stg_adjustments
  from public.stg_entos_movements
  where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
),
imported as (
  select
    count(*) filter (where entity_type = 'purchase') as imp_purchases,
    count(*) filter (where entity_type = 'invoice') as imp_invoices,
    count(*) filter (where entity_type = 'adjustment') as imp_adjustments
  from public.migration_id_map
  where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
)
select
  s.stg_purchases,
  i.imp_purchases,
  s.stg_purchases - i.imp_purchases as purchase_diff,
  s.stg_invoices,
  i.imp_invoices,
  s.stg_invoices - i.imp_invoices as invoice_diff,
  s.stg_adjustments,
  i.imp_adjustments,
  s.stg_adjustments - i.imp_adjustments as adjustment_diff
from staged s, imported i
where s.stg_purchases <> i.imp_purchases
   or s.stg_invoices <> i.imp_invoices
   or s.stg_adjustments <> i.imp_adjustments;

-- ---------------------------------------------------------------------------
-- 4. Orphan stock movements (no source document)
-- ---------------------------------------------------------------------------

select sm.id, sm.movement_type, sm.reference_number, sm.source_table, sm.source_id
from public.stock_movements sm
where sm.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and sm.movement_type in ('purchase', 'sale')
  and sm.source_id is null
  and sm.voided_at is null;

-- ---------------------------------------------------------------------------
-- 5. Summary (informational — always returns one row)
-- ---------------------------------------------------------------------------

select
  (select count(*) from public.products where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as products,
  (select count(*) from public.parties where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as parties,
  (select count(*) from public.invoices where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as invoices,
  (select count(*) from public.purchases where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as purchases,
  (select count(*) from public.stock_movements where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as stock_movements,
  (select status from public.migration_run_log
   where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
   order by started_at desc limit 1) as last_migration_status;

-- ---------------------------------------------------------------------------
-- 6. Spot-check: list 10 recent imported sales with legacy ref in notes
-- ---------------------------------------------------------------------------

select
  i.invoice_number,
  i.invoice_date,
  p.party_name,
  i.sale_type,
  i.total_amount,
  i.paid_amount,
  i.balance_amount,
  i.status,
  i.notes
from public.invoices i
left join public.parties p on p.id = i.party_id
where i.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and i.notes like 'legacy_movement:%'
order by i.invoice_date desc, i.invoice_number desc
limit 10;
