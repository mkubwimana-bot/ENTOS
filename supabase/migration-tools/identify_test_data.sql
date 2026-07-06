-- ============================================================
-- Identify dev/test rows mixed with Entos migrated data
-- Replace e9aefc3f-cc08-4bfe-9b42-c354c62388c5, then run each section in Supabase SQL Editor.
--
-- Migrated data is recognized by:
--   - migration_id_map (parties, products, purchases, invoices, adjustments)
--   - invoice_number / purchase_number starting with MIG-INV- / MIG-PUR-
--   - notes containing legacy_movement:<uuid>
--   - opening stock with reason 'Entos opening_qty import'
--   - stock adjustments with reference MIG-ADJ-*
--
-- Test/dev data is usually:
--   - INV-*, PUR-*, PAY-*, ADJ-* (live app sequences from testing)
--   - products/parties NOT in migration_id_map
--   - category "General" from signup (optional keep)
-- ============================================================

-- ---------------------------------------------------------------------------
-- 1. Summary: migrated vs test counts
-- ---------------------------------------------------------------------------

select 'invoices' as entity,
  count(*) filter (
    where notes like 'legacy_movement:%'
       or invoice_number ~ '^MIG-INV-'
       or id in (
         select new_id from public.migration_id_map
         where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'invoice'
       )
  ) as migrated,
  count(*) filter (
    where not (
      notes like 'legacy_movement:%'
      or invoice_number ~ '^MIG-INV-'
      or id in (
        select new_id from public.migration_id_map
        where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'invoice'
      )
    )
  ) as test_or_live
from public.invoices
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid

union all

select 'purchases',
  count(*) filter (
    where notes like 'legacy_movement:%'
       or purchase_number ~ '^MIG-PUR-'
       or id in (
         select new_id from public.migration_id_map
         where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'purchase'
       )
  ),
  count(*) filter (
    where not (
      notes like 'legacy_movement:%'
      or purchase_number ~ '^MIG-PUR-'
      or id in (
        select new_id from public.migration_id_map
        where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'purchase'
      )
    )
  )
from public.purchases
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid

union all

select 'products',
  count(*) filter (
    where id in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'product'
    )
  ),
  count(*) filter (
    where id not in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'product'
    )
  )
from public.products
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid

union all

select 'parties',
  count(*) filter (
    where id in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'party'
    )
  ),
  count(*) filter (
    where id not in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'party'
    )
  )
from public.parties
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid

union all

select 'payments',
  0,
  count(*)
from public.payments
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid;

-- ---------------------------------------------------------------------------
-- 2. Test invoices (review before delete)
-- ---------------------------------------------------------------------------

select
  i.invoice_number,
  i.invoice_date,
  i.sale_type,
  i.status,
  i.total_amount,
  i.balance_amount,
  p.party_name,
  i.created_at
from public.invoices i
left join public.parties p on p.id = i.party_id
where i.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and not (
    i.notes like 'legacy_movement:%'
    or i.invoice_number ~ '^MIG-INV-'
    or i.id in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'invoice'
    )
  )
order by i.created_at desc;

-- ---------------------------------------------------------------------------
-- 3. Test purchases
-- ---------------------------------------------------------------------------

select
  pu.purchase_number,
  pu.purchase_date,
  pu.status,
  pu.total_amount,
  p.party_name,
  pu.created_at
from public.purchases pu
left join public.parties p on p.id = pu.party_id
where pu.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and not (
    pu.notes like 'legacy_movement:%'
    or pu.purchase_number ~ '^MIG-PUR-'
    or pu.id in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'purchase'
    )
  )
order by pu.created_at desc;

-- ---------------------------------------------------------------------------
-- 4. Test products (not from Entos CSV)
-- ---------------------------------------------------------------------------

select
  pr.product_code,
  pr.product_name,
  pr.selling_price,
  pr.created_at
from public.products pr
where pr.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and pr.id not in (
    select new_id from public.migration_id_map
    where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'product'
  )
order by pr.product_name;

-- ---------------------------------------------------------------------------
-- 5. Test customers/suppliers (not from Entos CSV)
-- ---------------------------------------------------------------------------

select
  p.party_code,
  p.party_name,
  p.primary_phone,
  p.created_at,
  string_agg(distinct pt.type_code, ', ') as party_types
from public.parties p
left join public.party_type_links ptl on ptl.party_id = p.id
left join public.party_types pt on pt.id = ptl.party_type_id
where p.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and p.id not in (
    select new_id from public.migration_id_map
    where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'party'
  )
group by p.id, p.party_code, p.party_name, p.primary_phone, p.created_at
order by p.party_name;

-- ---------------------------------------------------------------------------
-- 6. All payments (migration imported none — review if any are real post-cutover)
-- ---------------------------------------------------------------------------

select
  pay.payment_number,
  pay.payment_date,
  pay.amount,
  pay.payment_method,
  pay.status,
  p.party_name,
  pay.created_at
from public.payments pay
left join public.parties p on p.id = pay.party_id
where pay.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
order by pay.created_at desc;

-- ---------------------------------------------------------------------------
-- 7. Orphan stock movements (not tied to migrated docs / opening)
-- ---------------------------------------------------------------------------

select
  sm.movement_type,
  sm.movement_date,
  sm.quantity_in,
  sm.quantity_out,
  sm.reference_number,
  sm.source_table,
  sm.reason,
  pr.product_name
from public.stock_movements sm
join public.products pr on pr.id = sm.product_id
where sm.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and sm.voided_at is null
  and not (
    sm.reason = 'Entos opening_qty import'
    or sm.reference_number ~ '^MIG-ADJ-'
    or sm.source_id in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
        and entity_type in ('purchase', 'invoice')
    )
    or sm.id in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'adjustment'
    )
  )
order by sm.movement_date desc, sm.created_at desc
limit 50;

-- ---------------------------------------------------------------------------
-- 8. Cross-tenant leak check (Reports ≠ Sales List)
-- Multiple tenant_id rows = report views were aggregating other tenants.
-- ---------------------------------------------------------------------------

select
  t.trading_name,
  i.tenant_id,
  i.invoice_date,
  count(*) as invoice_count,
  sum(i.total_amount) as total_sales
from public.invoices i
join public.tenants t on t.id = i.tenant_id
where i.invoice_date = '2026-07-04'
  and i.status = 'posted'
  and i.voided_at is null
group by t.trading_name, i.tenant_id, i.invoice_date
order by total_sales desc;
