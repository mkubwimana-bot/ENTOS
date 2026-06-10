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