-- ============================================================
-- Prep tenant for Entos full-history import
-- Replace e9aefc3f-cc08-4bfe-9b42-c354c62388c5 below, then run in Supabase SQL Editor.
-- Keeps: tenant, branch, warehouse, app_users, user_tenants, roles.
-- Removes: products, parties, sales, purchases, stock, migration staging.
-- ============================================================

begin;

delete from public.payment_allocations where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.payments where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.invoice_lines where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.invoices where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.purchase_lines where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.purchases where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.stock_movements where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.product_barcodes where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.product_prices where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.products where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.product_categories where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.party_contacts where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.party_addresses where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.party_type_links where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.parties where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.migration_id_map where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.migration_run_log where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.stg_entos_movements where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.stg_entos_products where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';
delete from public.stg_entos_parties where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5';

commit;
