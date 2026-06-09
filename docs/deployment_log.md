# SME-OS Deployment Log

This file records which SQL migration files were manually executed in Supabase Cloud.

## Development Database

Project: sme-os-dev

| Date | Migration File | Executed By | Status | Notes |
|---|---|---|---|---|
| 2026-06-08 | 001_core_platform.sql | Marcellin | Completed | Created tenants, branches, warehouses, tenant_settings |
| 2026-06-08 | 002_security_roles.sql | Marcellin | Completed | Created app_users, user_tenants, roles, permissions, role mappings, helper functions, and RLS foundation |
| 2026-06-08 | 003_subscriptions_and_localization.sql | Marcellin | Completed | Created subscription plans, subscriptions, billing events, languages, translations, and tenant language settings |
| | 003_products_parties.sql | | Pending | |
| | 004_sales_inventory.sql | | Pending | |
| | 005_mobile_offline.sql | | Pending | |
| | 006_credit_readiness.sql | | Pending | |
| | seed.sql | | Pending | |