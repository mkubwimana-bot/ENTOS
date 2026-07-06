-- ============================================================
-- SME-OS Migration 017
-- Fix report/dashboard views bypassing RLS (security definer default)
--
-- Problem: views owned by postgres run without RLS, so vw_daily_sales
-- can aggregate invoices from ALL tenants. The Sales List queries
-- public.invoices directly and correctly shows only the current tenant.
--
-- Fix: security_invoker = true (PostgreSQL 15+) so the querying user's
-- RLS policies apply to underlying tables.
-- ============================================================

alter view if exists public.vw_current_stock set (security_invoker = true);
alter view if exists public.vw_low_stock set (security_invoker = true);
alter view if exists public.vw_customer_balances set (security_invoker = true);
alter view if exists public.vw_daily_sales set (security_invoker = true);
alter view if exists public.vw_product_sales_summary set (security_invoker = true);
alter view if exists public.vw_gross_profit_simple set (security_invoker = true);
alter view if exists public.vw_pending_mobile_transactions set (security_invoker = true);
alter view if exists public.vw_inventory_valuation set (security_invoker = true);
alter view if exists public.vw_receivables_aging set (security_invoker = true);
alter view if exists public.vw_monthly_cashflow_proxy set (security_invoker = true);
alter view if exists public.vw_sme_bankability set (security_invoker = true);
alter view if exists public.vw_dscr_inputs set (security_invoker = true);
alter view if exists public.vw_open_errors set (security_invoker = true);
alter view if exists public.vw_recent_audit_activity set (security_invoker = true);
alter view if exists public.vw_migration_document_counts set (security_invoker = true);
alter view if exists public.vw_migration_legacy_movements set (security_invoker = true);
