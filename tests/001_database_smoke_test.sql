-- ============================================================
-- SME-OS Database Smoke Test 001
--
-- Purpose:
-- Tests the core backend foundation after migrations 001-008.
--
-- This script:
--   1. Creates a test tenant
--   2. Initializes default branch, warehouse, settings, sequences
--   3. Creates a test customer
--   4. Creates a test product
--   5. Adds opening stock
--   6. Creates a posted cash sale
--   7. Creates a posted credit sale
--   8. Records a payment against the credit sale
--   9. Tests current stock
--   10. Tests customer balance
--   11. Tests daily sales
--   12. Tests pending mobile/offline draft view
--
-- Run this in Supabase SQL Editor on the DEV database only.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Clean previous test data if it exists
-- ------------------------------------------------------------

do $$
declare
  v_tenant_id uuid;
begin
  select id into v_tenant_id
  from public.tenants
  where tenant_code = 'SMOKE001';

  if v_tenant_id is not null then
    delete from public.sync_logs where tenant_id = v_tenant_id;
    delete from public.sync_queue where tenant_id = v_tenant_id;
    delete from public.conflict_logs where tenant_id = v_tenant_id;
    delete from public.transaction_drafts where tenant_id = v_tenant_id;
    delete from public.offline_cache_metadata where tenant_id = v_tenant_id;
    delete from public.device_sessions where tenant_id = v_tenant_id;
    delete from public.mobile_devices where tenant_id = v_tenant_id;

    delete from public.payment_allocations where tenant_id = v_tenant_id;
    delete from public.payments where tenant_id = v_tenant_id;
    delete from public.stock_movements where tenant_id = v_tenant_id;
    delete from public.invoice_lines where tenant_id = v_tenant_id;
    delete from public.invoices where tenant_id = v_tenant_id;

    delete from public.product_barcodes where tenant_id = v_tenant_id;
    delete from public.product_prices where tenant_id = v_tenant_id;
    delete from public.products where tenant_id = v_tenant_id;
    delete from public.product_categories where tenant_id = v_tenant_id;

    delete from public.party_addresses where tenant_id = v_tenant_id;
    delete from public.party_contacts where tenant_id = v_tenant_id;
    delete from public.party_type_links where tenant_id = v_tenant_id;
    delete from public.parties where tenant_id = v_tenant_id;

    delete from public.credit_score_runs where tenant_id = v_tenant_id;
    delete from public.credit_events where tenant_id = v_tenant_id;
    delete from public.external_facilities where tenant_id = v_tenant_id;
    delete from public.sme_financial_snapshots where tenant_id = v_tenant_id;
    delete from public.sme_credit_consents where tenant_id = v_tenant_id;

    delete from public.audit_logs where tenant_id = v_tenant_id;
    delete from public.error_logs where tenant_id = v_tenant_id;

    delete from public.number_sequences where tenant_id = v_tenant_id;
    delete from public.tenant_language_settings where tenant_id = v_tenant_id;
    delete from public.tenant_settings where tenant_id = v_tenant_id;
    delete from public.warehouses where tenant_id = v_tenant_id;
    delete from public.branches where tenant_id = v_tenant_id;
    delete from public.subscriptions where tenant_id = v_tenant_id;
    delete from public.billing_events where tenant_id = v_tenant_id;

    delete from public.tenants where id = v_tenant_id;
  end if;
end $$;

-- ------------------------------------------------------------
-- 1. Create test tenant and initialize defaults
-- ------------------------------------------------------------

insert into public.tenants (
  tenant_code,
  legal_name,
  trading_name,
  business_type,
  subscription_status,
  onboarding_status
)
values (
  'SMOKE001',
  'Smoke Test SME Ltd',
  'Smoke Test Shop',
  'retail',
  'trial',
  'setup_started'
);

select public.initialize_tenant_defaults(
  (select id from public.tenants where tenant_code = 'SMOKE001')
);

-- ------------------------------------------------------------
-- 2. Create test customer
-- ------------------------------------------------------------

insert into public.parties (
  tenant_id,
  party_code,
  party_name,
  party_kind,
  primary_phone,
  customer_credit_limit,
  customer_credit_terms_days,
  internal_credit_rating,
  is_credit_eligible,
  opening_balance,
  status
)
select
  t.id,
  'CUST001',
  'Jean Test Customer',
  'individual',
  '+250780000001',
  100000,
  30,
  'good',
  true,
  0,
  'active'
from public.tenants t
where t.tenant_code = 'SMOKE001';

insert into public.party_type_links (
  tenant_id,
  party_id,
  party_type_id,
  is_primary
)
select
  p.tenant_id,
  p.id,
  pt.id,
  true
from public.parties p
join public.party_types pt on pt.type_code = 'customer'
join public.tenants t on t.id = p.tenant_id
where t.tenant_code = 'SMOKE001'
  and p.party_code = 'CUST001';

-- ------------------------------------------------------------
-- 3. Create test product category and product
-- ------------------------------------------------------------

insert into public.product_categories (
  tenant_id,
  category_code,
  category_name,
  description,
  is_active
)
select
  t.id,
  'DRINKS',
  'Drinks',
  'Smoke test product category',
  true
from public.tenants t
where t.tenant_code = 'SMOKE001'
on conflict (tenant_id, category_name) do nothing;

insert into public.products (
  tenant_id,
  product_code,
  product_name,
  product_type_id,
  category_id,
  base_unit_id,
  cost_price,
  selling_price,
  is_inventory_tracked,
  reorder_level,
  reorder_quantity,
  allow_negative_stock,
  status
)
select
  t.id,
  'PROD001',
  'Test Bottled Water',
  pt.id,
  pc.id,
  pu.id,
  300,
  500,
  true,
  10,
  20,
  false,
  'active'
from public.tenants t
join public.product_types pt on pt.type_code = 'stock_item'
join public.product_categories pc
  on pc.tenant_id = t.id
 and pc.category_name = 'Drinks'
join public.product_units pu
  on pu.tenant_id is null
 and pu.unit_code = 'pcs'
where t.tenant_code = 'SMOKE001';

-- ------------------------------------------------------------
-- 4. Add opening stock: 100 pieces
-- ------------------------------------------------------------

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
  reference_number,
  reason
)
select
  t.id,
  b.id,
  w.id,
  p.id,
  current_date,
  'opening',
  100,
  0,
  300,
  30000,
  'OPENING-STOCK',
  'Smoke test opening stock'
from public.tenants t
join public.branches b on b.tenant_id = t.id and b.branch_code = 'MAIN'
join public.warehouses w on w.tenant_id = t.id and w.warehouse_code = 'MAIN'
join public.products p on p.tenant_id = t.id and p.product_code = 'PROD001'
where t.tenant_code = 'SMOKE001';

-- ------------------------------------------------------------
-- 5. Create posted cash sale: 5 units x 500 = 2,500
-- ------------------------------------------------------------

insert into public.invoices (
  tenant_id,
  branch_id,
  warehouse_id,
  invoice_number,
  invoice_date,
  party_id,
  sale_type,
  status,
  subtotal_amount,
  discount_amount,
  tax_amount,
  total_amount,
  paid_amount,
  balance_amount,
  posted_at
)
select
  t.id,
  b.id,
  w.id,
  'INV-SMOKE-CASH',
  current_date,
  null,
  'cash',
  'posted',
  2500,
  0,
  0,
  2500,
  2500,
  0,
  now()
from public.tenants t
join public.branches b on b.tenant_id = t.id and b.branch_code = 'MAIN'
join public.warehouses w on w.tenant_id = t.id and w.warehouse_code = 'MAIN'
where t.tenant_code = 'SMOKE001';

insert into public.invoice_lines (
  tenant_id,
  invoice_id,
  line_number,
  product_id,
  description,
  quantity,
  unit_id,
  unit_price,
  discount_amount,
  tax_amount,
  line_total,
  cost_price_snapshot,
  warehouse_id
)
select
  t.id,
  i.id,
  1,
  p.id,
  p.product_name,
  5,
  p.base_unit_id,
  500,
  0,
  0,
  2500,
  300,
  w.id
from public.tenants t
join public.invoices i on i.tenant_id = t.id and i.invoice_number = 'INV-SMOKE-CASH'
join public.products p on p.tenant_id = t.id and p.product_code = 'PROD001'
join public.warehouses w on w.tenant_id = t.id and w.warehouse_code = 'MAIN'
where t.tenant_code = 'SMOKE001';

insert into public.payments (
  tenant_id,
  branch_id,
  payment_number,
  payment_date,
  party_id,
  payment_method,
  payment_channel,
  amount,
  currency_code,
  status,
  posted_at
)
select
  t.id,
  b.id,
  'REC-SMOKE-CASH',
  current_date,
  null,
  'cash',
  'cash',
  2500,
  'RWF',
  'posted',
  now()
from public.tenants t
join public.branches b on b.tenant_id = t.id and b.branch_code = 'MAIN'
where t.tenant_code = 'SMOKE001';

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
  reason
)
select
  t.id,
  b.id,
  w.id,
  p.id,
  current_date,
  'sale',
  0,
  5,
  300,
  1500,
  'invoice_lines',
  il.id,
  'INV-SMOKE-CASH',
  'Smoke test cash sale'
from public.tenants t
join public.branches b on b.tenant_id = t.id and b.branch_code = 'MAIN'
join public.warehouses w on w.tenant_id = t.id and w.warehouse_code = 'MAIN'
join public.products p on p.tenant_id = t.id and p.product_code = 'PROD001'
join public.invoice_lines il on il.tenant_id = t.id
join public.invoices i on i.id = il.invoice_id and i.invoice_number = 'INV-SMOKE-CASH'
where t.tenant_code = 'SMOKE001';

-- ------------------------------------------------------------
-- 6. Create posted credit sale: 10 units x 500 = 5,000
-- ------------------------------------------------------------

insert into public.invoices (
  tenant_id,
  branch_id,
  warehouse_id,
  invoice_number,
  invoice_date,
  party_id,
  sale_type,
  status,
  subtotal_amount,
  discount_amount,
  tax_amount,
  total_amount,
  paid_amount,
  balance_amount,
  due_date,
  posted_at
)
select
  t.id,
  b.id,
  w.id,
  'INV-SMOKE-CREDIT',
  current_date,
  c.id,
  'credit',
  'posted',
  5000,
  0,
  0,
  5000,
  0,
  5000,
  current_date + interval '30 day',
  now()
from public.tenants t
join public.branches b on b.tenant_id = t.id and b.branch_code = 'MAIN'
join public.warehouses w on w.tenant_id = t.id and w.warehouse_code = 'MAIN'
join public.parties c on c.tenant_id = t.id and c.party_code = 'CUST001'
where t.tenant_code = 'SMOKE001';

insert into public.invoice_lines (
  tenant_id,
  invoice_id,
  line_number,
  product_id,
  description,
  quantity,
  unit_id,
  unit_price,
  discount_amount,
  tax_amount,
  line_total,
  cost_price_snapshot,
  warehouse_id
)
select
  t.id,
  i.id,
  1,
  p.id,
  p.product_name,
  10,
  p.base_unit_id,
  500,
  0,
  0,
  5000,
  300,
  w.id
from public.tenants t
join public.invoices i on i.tenant_id = t.id and i.invoice_number = 'INV-SMOKE-CREDIT'
join public.products p on p.tenant_id = t.id and p.product_code = 'PROD001'
join public.warehouses w on w.tenant_id = t.id and w.warehouse_code = 'MAIN'
where t.tenant_code = 'SMOKE001';

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
  reason
)
select
  t.id,
  b.id,
  w.id,
  p.id,
  current_date,
  'sale',
  0,
  10,
  300,
  3000,
  'invoice_lines',
  il.id,
  'INV-SMOKE-CREDIT',
  'Smoke test credit sale'
from public.tenants t
join public.branches b on b.tenant_id = t.id and b.branch_code = 'MAIN'
join public.warehouses w on w.tenant_id = t.id and w.warehouse_code = 'MAIN'
join public.products p on p.tenant_id = t.id and p.product_code = 'PROD001'
join public.invoice_lines il on il.tenant_id = t.id
join public.invoices i on i.id = il.invoice_id and i.invoice_number = 'INV-SMOKE-CREDIT'
where t.tenant_code = 'SMOKE001';

-- ------------------------------------------------------------
-- 7. Record partial payment against credit sale: 2,000
-- ------------------------------------------------------------

insert into public.payments (
  tenant_id,
  branch_id,
  payment_number,
  payment_date,
  party_id,
  payment_method,
  payment_channel,
  amount,
  currency_code,
  status,
  posted_at
)
select
  t.id,
  b.id,
  'REC-SMOKE-CREDIT',
  current_date,
  c.id,
  'momo',
  'momo',
  2000,
  'RWF',
  'posted',
  now()
from public.tenants t
join public.branches b on b.tenant_id = t.id and b.branch_code = 'MAIN'
join public.parties c on c.tenant_id = t.id and c.party_code = 'CUST001'
where t.tenant_code = 'SMOKE001';

insert into public.payment_allocations (
  tenant_id,
  payment_id,
  invoice_id,
  allocated_amount
)
select
  t.id,
  pay.id,
  inv.id,
  2000
from public.tenants t
join public.payments pay on pay.tenant_id = t.id and pay.payment_number = 'REC-SMOKE-CREDIT'
join public.invoices inv on inv.tenant_id = t.id and inv.invoice_number = 'INV-SMOKE-CREDIT'
where t.tenant_code = 'SMOKE001';

-- ------------------------------------------------------------
-- 8. Create pending mobile/offline transaction draft
-- ------------------------------------------------------------

insert into public.transaction_drafts (
  tenant_id,
  branch_id,
  warehouse_id,
  user_id,
  device_id,
  draft_type,
  client_reference_id,
  provisional_number,
  payload,
  status,
  source,
  created_offline_at,
  received_at
)
select
  t.id,
  b.id,
  w.id,
  -- Because this smoke test runs without a real auth user,
  -- use a placeholder only if there is at least one app_user.
  -- If no app_users exist, this insert is skipped.
  au.id,
  null,
  'sale',
  'SMOKE-OFFLINE-001',
  'TEMP-001',
  jsonb_build_object(
    'sale_type', 'cash',
    'items', jsonb_build_array(
      jsonb_build_object(
        'product_code', 'PROD001',
        'quantity', 2,
        'unit_price', 500
      )
    )
  ),
  'pending_sync',
  'offline',
  now(),
  now()
from public.tenants t
join public.branches b on b.tenant_id = t.id and b.branch_code = 'MAIN'
join public.warehouses w on w.tenant_id = t.id and w.warehouse_code = 'MAIN'
join public.app_users au on au.is_active = true
where t.tenant_code = 'SMOKE001'
limit 1;

-- ------------------------------------------------------------
-- 9. Results: Current stock
-- Expected:
-- Opening stock 100
-- Cash sale out 5
-- Credit sale out 10
-- Current stock = 85
-- ------------------------------------------------------------

select
  'CURRENT_STOCK_TEST' as test_name,
  product_code,
  product_name,
  current_quantity
from public.vw_current_stock
where tenant_id = (select id from public.tenants where tenant_code = 'SMOKE001')
  and product_code = 'PROD001';

-- ------------------------------------------------------------
-- 10. Results: Customer balance
-- Expected:
-- Credit invoice 5,000
-- Payment 2,000
-- Balance 3,000
-- ------------------------------------------------------------

select
  'CUSTOMER_BALANCE_TEST' as test_name,
  party_code,
  party_name,
  total_invoiced,
  total_paid,
  balance
from public.vw_customer_balances
where tenant_id = (select id from public.tenants where tenant_code = 'SMOKE001')
  and party_code = 'CUST001';

-- ------------------------------------------------------------
-- 11. Results: Daily sales
-- Expected:
-- Cash sale 2,500 + credit sale 5,000 = 7,500
-- ------------------------------------------------------------

select
  'DAILY_SALES_TEST' as test_name,
  invoice_date,
  invoice_count,
  total_sales,
  total_paid,
  total_balance
from public.vw_daily_sales
where tenant_id = (select id from public.tenants where tenant_code = 'SMOKE001')
  and invoice_date = current_date;

-- ------------------------------------------------------------
-- 12. Results: Product sales summary
-- Expected:
-- Quantity sold = 15
-- Total sales = 7,500
-- Estimated cost = 4,500
-- Estimated gross profit = 3,000
-- ------------------------------------------------------------

select
  'PRODUCT_SALES_TEST' as test_name,
  product_code,
  product_name,
  quantity_sold,
  total_sales,
  estimated_cost,
  estimated_gross_profit
from public.vw_product_sales_summary
where tenant_id = (select id from public.tenants where tenant_code = 'SMOKE001')
  and product_code = 'PROD001';

-- ------------------------------------------------------------
-- 13. Results: Pending mobile/offline transactions
-- This may return zero rows if no app_users exist yet.
-- That is acceptable at this stage.
-- ------------------------------------------------------------

select
  'PENDING_MOBILE_TEST' as test_name,
  draft_type,
  client_reference_id,
  provisional_number,
  status,
  source
from public.vw_pending_mobile_transactions
where tenant_id = (select id from public.tenants where tenant_code = 'SMOKE001');

-- ------------------------------------------------------------
-- End of smoke test
-- ============================================================