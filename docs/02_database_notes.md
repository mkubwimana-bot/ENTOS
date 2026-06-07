# Database Notes

## Core Design Decisions

- Use Supabase PostgreSQL.

- Use UUID primary keys.

- Use tenant_id on all tenant-owned business tables.

- Use Row-Level Security.

- Use parties instead of separate customers and suppliers.

- Use products for stock items, services, manufactured items, and subscriptions.

- Use stock_movements as the source of truth for inventory.

- Do not store stock only as a product balance.

- Use transaction_drafts and sync_queue for limited offline support.

- Use credit-readiness fields early, but build scoring later.

## MVP Core Tables

- tenants

- app_users

- user_tenants

- roles

- permissions

- user_roles

- parties

- party_types

- products

- product_types

- product_categories

- product_units

- invoices

- invoice_lines

- payments

- payment_allocations

- stock_movements

- mobile_devices

- device_sessions

- transaction_drafts

- sync_queue

- sync_logs

- audit_logs