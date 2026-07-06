-- ============================================================
-- Remove dev/test data; KEEP Entos migrated history
-- Replace e9aefc3f-cc08-4bfe-9b42-c354c62388c5 before running.
--
-- 1. Run identify_test_data.sql first and review lists.
-- 2. Run this script once (single transaction).
-- 3. Re-run validate_import.sql to confirm stock/balances.
--
-- WARNING: Deletes ALL payments (migration imported none).
--          If you recorded real payments after cutover, comment out
--          the payments section or adjust the cutoff date.
-- ============================================================

begin;

-- ---------------------------------------------------------------------------
-- Helpers: ids to remove
-- ---------------------------------------------------------------------------

create temp table _test_invoices on commit drop as
select i.id
from public.invoices i
where i.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and not (
    i.notes like 'legacy_movement:%'
    or i.invoice_number ~ '^MIG-INV-'
    or i.id in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'invoice'
    )
  );

create temp table _test_purchases on commit drop as
select p.id
from public.purchases p
where p.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and not (
    p.notes like 'legacy_movement:%'
    or p.purchase_number ~ '^MIG-PUR-'
    or p.id in (
      select new_id from public.migration_id_map
      where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'purchase'
    )
  );

create temp table _test_products on commit drop as
select pr.id
from public.products pr
where pr.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and pr.id not in (
    select new_id from public.migration_id_map
    where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'product'
  );

create temp table _test_parties on commit drop as
select pa.id
from public.parties pa
where pa.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and pa.id not in (
    select new_id from public.migration_id_map
    where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and entity_type = 'party'
  );

create temp table _test_stock_movements on commit drop as
select sm.id
from public.stock_movements sm
where sm.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
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
  );

-- ---------------------------------------------------------------------------
-- Delete test transactional data (FK-safe order)
-- ---------------------------------------------------------------------------

delete from public.payment_allocations pa
where pa.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and (
    pa.payment_id in (select id from public.payments where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid)
    or pa.invoice_id in (select id from _test_invoices)
  );

delete from public.payments
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid;

delete from public.invoice_lines
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and invoice_id in (select id from _test_invoices);

delete from public.invoices
where id in (select id from _test_invoices);

delete from public.purchase_lines
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and purchase_id in (select id from _test_purchases);

delete from public.purchases
where id in (select id from _test_purchases);

delete from public.stock_movements
where id in (select id from _test_stock_movements);

delete from public.product_barcodes
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and product_id in (select id from _test_products);

delete from public.product_prices
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and product_id in (select id from _test_products);

delete from public.products
where id in (select id from _test_products);

delete from public.party_contacts
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and party_id in (select id from _test_parties);

delete from public.party_addresses
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and party_id in (select id from _test_parties);

delete from public.party_type_links
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and party_id in (select id from _test_parties);

delete from public.parties
where id in (select id from _test_parties);

-- Optional: remove signup "General" category if no products use it
delete from public.product_categories pc
where pc.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and pc.category_name = 'General'
  and pc.id not in (
    select category_id from public.products
    where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid and category_id is not null
  );

-- Offline / draft clutter from testing
delete from public.transaction_drafts
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid;

delete from public.sync_queue
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid;

-- ---------------------------------------------------------------------------
-- Summary (informational)
-- ---------------------------------------------------------------------------

select
  (select count(*) from public.invoices where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as invoices_remaining,
  (select count(*) from public.purchases where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as purchases_remaining,
  (select count(*) from public.products where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as products_remaining,
  (select count(*) from public.parties where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as parties_remaining,
  (select count(*) from public.payments where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid) as payments_remaining;

commit;
