# SME-OS Deployment Log

This file records which SQL migration files were manually executed in Supabase Cloud.

## Development Database

Project: sme-os-dev

| Date | Migration File | Executed By | Status | Notes |
|---|---|---|---|---|
| 2026-06-08 | 001_core_platform.sql | Marcellin | Completed | Created tenants, branches, warehouses, tenant_settings |
| 2026-06-08 | 002_security_roles.sql | Marcellin | Completed | Created app_users, user_tenants, roles, permissions, role mappings, helper functions, and RLS foundation |
| 2026-06-08 | 003_subscriptions_and_localization.sql | Marcellin | Completed | Created subscription plans, subscriptions, billing events, languages, translations, and tenant language settings |
| 2026-06-08 | 004_parties_products.sql | Marcellin | Completed | Created parties/customers, product/service master data, categories, units, prices, barcodes, and credit-readiness fields |
| 2026-06-08 | 005_sales_inventory.sql | Marcellin | Completed | Created invoices, invoice lines, payments, payment allocations, stock movements, and MVP reporting views |
| 2026-06-08 | 006_mobile_offline.sql | Marcellin | Completed | Created mobile devices, device sessions, transaction drafts, sync queue, sync logs, conflict logs, offline cache metadata, number sequences, and pending mobile transaction view |
| 2026-06-08 | 007_credit_readiness.sql | Marcellin | Completed | Created credit consent, financial snapshots, score runs, credit events, external facilities, and bankability views |
| 2026-06-08 | 008_audit_error_and_initial_seed.sql | Marcellin | Completed | Created audit logs, error logs, support views, logging helpers, and tenant default initialization function |
| date not recorded | 009_auth_user_profile_trigger.sql | Marcellin | Completed | Trigger creating app_users profile on Supabase Auth signup |
| date not recorded | 010_fix_customer_balances_view.sql | Marcellin | Completed | Fixed customer balances view |
| date not recorded | 011_post_sale_draft_rpc.sql | Marcellin | Completed | RPC to post offline sale drafts (transaction_drafts/sync_queue flow) |
| date not recorded | 012_credit_invoice_due_date.sql | Marcellin | Completed | Added due date handling for credit invoices |
| date not recorded | 013_signup_subscription.sql | Marcellin | Completed | Subscription setup on tenant signup |
| 2026-07-04/06 | 014_purchases.sql | Marcellin | Completed | Suppliers, purchase invoices, and stock receipt for the purchases module |
| 2026-07-04/06 | 015_void_transactions_and_product_codes.sql | Marcellin | Completed | Void support for transactions and product code generation |
| 2026-07-04/06 | 016_import_staging.sql | Marcellin | Completed | Staging tables for legacy Entos data import |
| 2026-07-04/06 | 017_fix_view_rls.sql | Marcellin | Completed | Fixed RLS on reporting views |
| 2026-07-04/06 | 018_party_code_generator.sql | Marcellin | Completed | Party (customer/supplier) code generation |
| 2026-07-04/06 | 019_fix_receivables_aging.sql | Marcellin | Completed | Fixed receivables aging calculation |
| 2026-07-04/06 | 020_fix_void_and_edit_cash_invoice.sql | Marcellin | Completed | Fixed void and edit flows for cash invoices |
| 2026-07-04/06 | 021_fix_inventory_valuation.sql | Marcellin | Completed | Fixed inventory valuation calculation |
| 2026-07-04/06 | 022_post_purchase_tenant_check.sql | Marcellin | Completed | Added tenant check to post-purchase function |