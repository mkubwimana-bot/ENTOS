-- ============================================================
-- SME-OS Database Smoke Test Cleanup
-- Removes SMOKE001 tenant and related test data.
-- Run only after confirming the smoke test results.
-- ============================================================

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

select *
from public.tenants
where tenant_code = 'SMOKE001';