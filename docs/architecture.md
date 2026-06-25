<!-- Machine-readable export of SME-OS Volume 3 (v1.3, hand-coded Flutter stack). Source of truth: SME_OS_Volume_3_v1_3_Flutter.docx. Regenerate with: pandoc -f docx -t gfm --wrap=none SME_OS_Volume_3_v1_3_Flutter.docx -o docs/architecture.md -->

**SME-OS Rwanda  
Volume 3: Database Architecture & Data Dictionary  
Version 1.1 - Offline & Mobile Transaction Capability Integrated  
CTO-Grade Blueprint for MVP to Multi-Industry ERP Scale-Up**

| **Document Metadata**    | **Value**                                                                                                                                  |
|--------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Version                  | 1.1 - Offline & Mobile Transaction Capability Integrated                                                                                   |
| Date                     | June 06, 2026                                                                                                                              |
| Owner                    | Founder / Product Owner                                                                                                                    |
| Audience                 | Founder, AI coding assistants, future developers, implementation partners                                                                  |
| Primary stack assumption | Hand-coded Flutter frontend, Supabase backend, PostgreSQL database                                                                         |
| Revision Scope           | Adds mobile-first simple transactions, limited offline draft capture, local transaction queue, sync controls, and related database tables. |

This document is designed as the database foundation for a Rwanda-focused SME management platform that starts with Sales, Inventory, Customer Debts, and Dashboard reporting, while remaining extensible to services, wholesale, pharmacies, manufacturing, subscriptions, self-service SaaS onboarding, multilingual UI, and future ERP modules.

# Table of Contents

1.  1\. Executive Database Strategy

2.  2\. Design Principles

3.  3\. Access/VBA to SaaS Translation

4.  4\. System Context and Boundaries

5.  5\. Multi-Tenant Architecture

6.  6\. Naming Standards and Data Types

7.  7\. Conceptual ERD

8.  8\. Module Map: MVP to Scale-Up

9.  9\. Core Table Catalogue

10. 10\. Data Dictionary: Platform and Tenant Tables

11. 11\. Data Dictionary: Security and Permissions

12. 12\. Data Dictionary: Subscription and Trial Management

13. 13\. Data Dictionary: Party / Customer / Supplier Model

14. 14\. Data Dictionary: Product and Service Model

15. 15\. Data Dictionary: Sales, Invoicing and Payments

16. 16\. Data Dictionary: Inventory and Warehouses

17. 17\. Data Dictionary: Reporting and Analytics Support

18. 18\. Data Dictionary: Localization and Multi-Language

19. 19\. Data Dictionary: Integrations and API Logging

20. 20\. Data Dictionary: Audit, Compliance and Operations

21. 21\. Future Expansion: Services, Manufacturing and Accounting

22. 22\. Relationship Rules and Transaction Flows

23. 23\. Supabase Implementation Notes

24. 24\. Row-Level Security Blueprint

25. 25\. Migration and Versioning Strategy

26. 26\. Data Quality, Testing and QA

27. 27\. MVP Build Order

28. 28\. Appendices

29. 29\. Integrated MVP Revision: Mobile and Offline Transactions

30. 30\. Data Dictionary: Offline Sync and Mobile Transaction Tables

31. 31\. Offline Transaction Flows, Conflict Rules and MVP Build Order Update

# 1. Executive Database Strategy

The database is the permanent foundation of SME-OS. Screens, reports, AI-generated code and APIs will change, but the core data model should remain stable. The recommended architecture is a modular monolith database: one PostgreSQL database, multiple tenants, shared core tables, and optional industry modules added gradually.

- Start with an MVP data model that supports sales, inventory, customers, debtors and dashboards.

- Use generic core entities such as party, product, document, payment and stock_movement so the platform is not locked into retail only.

- Use tenant_id on every tenant-owned business table. This is equivalent to adding CompanyID to every Access table, but enforced at database security level.

- Use event/movement tables for inventory and transactions. Do not overwrite important history.

- Delay complex accounting and manufacturing implementation, but reserve clean extension points for them.

| **Strategic Decision**  | **Recommendation**                                | **Reason**                                                                                                   |
|-------------------------|---------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| Database engine         | PostgreSQL through Supabase                       | Mature relational database with SQL, constraints, indexes, JSON support, Row-Level Security and scalability. |
| Tenant model            | Shared database, shared schema, tenant_id per row | Fastest and simplest for solo founder; can support many SMEs before needing more complex isolation.          |
| Inventory model         | Stock movements as the source of truth            | Supports retail, wholesale, services with stock, pharmacies, transfers and manufacturing later.              |
| Customer/supplier model | Generic party table                               | Prevents future redesign when a person or company is both customer and supplier.                             |
| Product model           | Generic product table with product_type           | Allows stock items, services, manufactured items, subscriptions and spare parts.                             |
| Accounting              | Deferred, but transaction-ready                   | Avoids MVP complexity while preserving upgrade path.                                                         |
| Localization            | Translation keys, not hardcoded text              | Allows English, French, Kinyarwanda and Swahili later.                                                       |

# 2. Design Principles

- Design for simplicity first, extensibility second, and theoretical enterprise complexity last.

- Every important table should have an id, tenant_id where applicable, created_at, created_by, updated_at, updated_by and status where useful.

- Never delete business-critical records physically. Use status, voided_at or deleted_at soft-delete patterns.

- Do not store calculated balances as the only source of truth. Store transactions, then calculate balances or cache them separately.

- Use database constraints to prevent bad data rather than relying only on screen validation.

- Keep MVP tables lean. Add specialist columns only when a real paying customer requires them.

- Use readable naming. Avoid abbreviations that future developers or AI tools may misunderstand.

- Prefer UUID primary keys in SaaS to avoid predictable IDs and to simplify future data merging.

# 3. Access/VBA to SaaS Translation

This section translates familiar Microsoft Access concepts into the SaaS architecture used in SME-OS.

| **Access/VBA Concept** | **SME-OS / Supabase Equivalent**                                      | **Practical Meaning**                                             |
|------------------------|-----------------------------------------------------------------------|-------------------------------------------------------------------|
| Access back-end tables | PostgreSQL tables in Supabase                                         | The central data storage layer.                                   |
| Access forms           | Flutter screens and widgets                                           | User input screens connected to database tables.                  |
| Queries                | SQL views, Supabase queries, RPC functions                            | Reusable data retrieval and reporting logic.                      |
| VBA event procedures   | Flutter and Dart code, Supabase functions, database triggers          | Logic that runs when a user clicks a button or a record changes.  |
| Reports                | Flutter report screens, Supabase views, exported PDFs, BI tools later | Management outputs and printable documents.                       |
| User-level security    | Supabase Auth + Row-Level Security + roles                            | Controls who can see or edit what.                                |
| CompanyID field        | tenant_id                                                             | The key that isolates each SME customer inside the same database. |
| Audit trail table      | audit_logs                                                            | Stores who changed what and when.                                 |
| Linked tables          | API integrations / foreign data imports                               | Connections to external systems such as EBM or Mobile Money.      |

# 4. System Context and Boundaries

The database must support the business application, the public commercialization website, self-service signup, subscriptions, and future integrations. However, these do not all need to be built on day one.

| **System Area**     | **Database Responsibility**                                                      | **MVP Status**                        |
|---------------------|----------------------------------------------------------------------------------|---------------------------------------|
| Business app        | Stores tenants, users, products, parties, invoices, payments and stock movements | Build in MVP                          |
| Public website      | Captures leads and routes users to signup                                        | Later; design subscription tables now |
| Self-service signup | Creates tenant, owner user, trial subscription and default settings              | Manual first; automate later          |
| Subscriptions       | Tracks plan, trial, billing and account status                                   | Simple table in MVP                   |
| EBM integration     | Stores external invoice status, request/response logs and device references      | Future                                |
| Mobile Money        | Stores payment provider transactions and webhook events                          | Future                                |
| Multilingual UI     | Stores language preferences and translation keys                                 | Design now; populate later            |

# 5. Multi-Tenant Architecture

SME-OS should start with a shared-database, shared-schema multi-tenant model. Every customer company is a tenant. Most business tables include tenant_id. Supabase Row-Level Security policies ensure a logged-in user can only access rows belonging to their tenant.

- Tenant = customer business/company using the platform.

- User = person who logs in. A user belongs to one or more tenants through user_tenants or app_users.

- Role = what the user is allowed to do inside a tenant, such as Owner, Manager, Cashier or Storekeeper.

- Tenant-owned rows must always include tenant_id.

- Platform-level tables such as subscription_plans, languages and permissions may not require tenant_id.

| **Isolation Level**          | **Description**                                                 | **Recommended Timing**                        |
|------------------------------|-----------------------------------------------------------------|-----------------------------------------------|
| Shared DB / shared schema    | All tenants in same PostgreSQL schema; tenant_id separates data | Recommended for MVP and early scale           |
| Shared DB / separate schema  | Each large tenant has separate database schema                  | Possible later for large enterprise customers |
| Separate database per tenant | Each tenant gets a dedicated database                           | Only for regulated or very large customers    |
| Regional hosting             | Data hosted in Rwanda or regional infrastructure when required  | Future compliance/scaling option              |

# 6. Naming Standards and Data Types

| **Standard**     | **Recommendation**                                         | **Example**                                   |
|------------------|------------------------------------------------------------|-----------------------------------------------|
| Table names      | snake_case plural nouns                                    | products, invoice_lines                       |
| Primary key      | id UUID                                                    | id uuid primary key default gen_random_uuid() |
| Foreign key      | singular table name + \_id                                 | tenant_id, product_id                         |
| Dates/timestamps | timestamptz for system timestamps; date for business dates | created_at, invoice_date                      |
| Money            | numeric(14,2) or numeric(18,4) for unit costs              | total_amount numeric(14,2)                    |
| Quantities       | numeric(14,3) or numeric(18,4)                             | quantity numeric(14,3)                        |
| Status fields    | text with check constraint or enum                         | status in draft, posted, void                 |
| Booleans         | is\_ prefix                                                | is_active, is_inventory_tracked               |
| Soft delete      | deleted_at timestamp and deleted_by                        | deleted_at timestamptz                        |
| Audit columns    | created_at, created_by, updated_at, updated_by             | standard on business tables                   |

# 7. Conceptual ERD

The ERD below is expressed in text so it remains easy to read, edit and later convert into a visual diagram.

TENANTS  
├── BRANCHES  
│ └── WAREHOUSES  
├── APP_USERS / USER_TENANTS  
│ └── USER_ROLES ── ROLES ── ROLE_PERMISSIONS ── PERMISSIONS  
├── PARTIES ── PARTY_TYPES  
│ ├── PARTY_CONTACTS  
│ └── PARTY_ADDRESSES  
├── PRODUCTS ── PRODUCT_TYPES  
│ ├── PRODUCT_CATEGORIES  
│ ├── PRODUCT_UNITS  
│ └── PRODUCT_PRICES  
├── INVOICES  
│ ├── INVOICE_LINES ── PRODUCTS  
│ ├── PAYMENTS / PAYMENT_ALLOCATIONS  
│ └── STOCK_MOVEMENTS  
├── PURCHASES / PURCHASE_LINES \[Phase 2\]  
├── SERVICE_JOBS / APPOINTMENTS \[Future service pack\]  
├── BILL_OF_MATERIALS / PRODUCTION_ORDERS \[Future manufacturing pack\]  
├── SUBSCRIPTIONS / BILLING_EVENTS  
├── INTEGRATION_CONNECTIONS / API_LOGS  
└── AUDIT_LOGS

# 8. Module Map: MVP to Scale-Up

| **Module**                    | **Purpose**                                                                                       | **Database Objects**                                                                                                                | **Phase**                             |
|-------------------------------|---------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------|
| Tenant/Admin                  | Company setup, branches, users                                                                    | tenants, branches, app_users, user_tenants                                                                                          | MVP                                   |
| Security                      | Roles and permissions                                                                             | roles, permissions, role_permissions, user_roles                                                                                    | MVP simplified                        |
| Parties                       | Customers and suppliers using one flexible model                                                  | parties, party_types, party_contacts, party_addresses                                                                               | MVP customer only; supplier later     |
| Products/Services             | Sellable items and services                                                                       | products, product_types, product_categories, product_units, product_prices                                                          | MVP                                   |
| Sales                         | Invoices, receipts and credit sales                                                               | invoices, invoice_lines, payments, payment_allocations                                                                              | MVP                                   |
| Inventory                     | Stock in/out and current stock                                                                    | warehouses, stock_movements, stock_counts                                                                                           | MVP stock movements                   |
| Purchasing                    | Supplier bills and stock receipts                                                                 | purchase_orders, purchases, purchase_lines                                                                                          | Phase 2                               |
| Accounting                    | Journals, chart of accounts and statements                                                        | accounts, journal_entries, journal_lines                                                                                            | Phase 3                               |
| Services                      | Jobs, appointments and work tracking                                                              | service_jobs, service_tasks, appointments                                                                                           | Future                                |
| Manufacturing                 | BOM, production and work orders                                                                   | bill_of_materials, bom_lines, production_orders                                                                                     | Future                                |
| Subscriptions                 | Commercial SaaS pricing and trial                                                                 | subscription_plans, subscriptions, billing_events                                                                                   | MVP basic; automate later             |
| Localization                  | Languages and translation keys                                                                    | languages, translations                                                                                                             | Design MVP; populate later            |
| Integrations                  | EBM, MoMo, Airtel, banks                                                                          | integration_connections, integration_events, api_logs                                                                               | Future                                |
| Mobile / Offline Transactions | Phone-based quick sales, customer payments, stock checks, limited offline draft capture and sync. | mobile_devices, device_sessions, transaction_drafts, sync_queue, sync_logs, offline_cache_metadata, conflict_logs, number_sequences | MVP limited / strengthen during pilot |

# 9. Core Table Catalogue

| **Group**            | **Tables**                                                                                                                          | **MVP?**          | **Notes**                                                                                                       |
|----------------------|-------------------------------------------------------------------------------------------------------------------------------------|-------------------|-----------------------------------------------------------------------------------------------------------------|
| Platform             | tenants, branches, warehouses, settings                                                                                             | Yes, simplified   | branches/warehouses can start as default records                                                                |
| Security             | app_users, user_tenants, roles, permissions, user_roles                                                                             | Yes, simplified   | Supabase auth.users remains the authentication source                                                           |
| Subscriptions        | subscription_plans, subscriptions, billing_events                                                                                   | Partial           | Manual billing first; automate later                                                                            |
| Parties              | party_types, parties, party_contacts, party_addresses                                                                               | Yes               | Customers in MVP; suppliers later                                                                               |
| Products             | product_types, product_categories, product_units, products, product_prices                                                          | Yes               | Services supported through product_type                                                                         |
| Sales                | invoices, invoice_lines, payments, payment_allocations                                                                              | Yes               | Receivables from unpaid invoices                                                                                |
| Inventory            | stock_movements, stock_counts, stock_count_lines                                                                                    | Yes for movements | Stock count module can be Phase 2                                                                               |
| Reporting            | report_snapshots, kpi_daily_summary                                                                                                 | Later             | Use SQL views first                                                                                             |
| Localization         | languages, translations, tenant_language_settings                                                                                   | Design            | May not need UI in MVP                                                                                          |
| Integrations         | integration_connections, integration_events, api_logs                                                                               | Future            | Required for EBM/MoMo/Airtel                                                                                    |
| Audit                | audit_logs, error_logs                                                                                                              | Yes, minimal      | Critical for troubleshooting and trust                                                                          |
| Future services      | service_jobs, service_job_lines, appointments                                                                                       | Future            | For salons, garages, repair and consulting                                                                      |
| Future manufacturing | bill_of_materials, bom_lines, production_orders, production_order_lines                                                             | Future            | Adds BOM and work order logic                                                                                   |
| Future accounting    | accounts, fiscal_periods, journal_entries, journal_lines                                                                            | Future            | Do not build fully in MVP                                                                                       |
| Mobile / Offline     | mobile_devices, device_sessions, transaction_drafts, sync_queue, sync_logs, conflict_logs, offline_cache_metadata, number_sequences | Yes, simplified   | Required to support mobile simple transactions and limited offline capture without building a full offline ERP. |

# 10. Data Dictionary: Platform and Tenant Tables

## tenants

**Purpose:** Stores each customer business/company using SME-OS. This is the central company table for multi-tenancy.

**Build phase:** MVP

| **Field**             | **Type**    | **Key** | **Required** | **Description / Business Rule**                                                      |
|-----------------------|-------------|---------|--------------|--------------------------------------------------------------------------------------|
| id                    | uuid        | PK      | Yes          | Unique tenant/company identifier.                                                    |
| tenant_code           | text        | UQ      | Yes          | Short unique code used in support, invoices and logs.                                |
| legal_name            | text        |         | Yes          | Registered company or owner business name.                                           |
| trading_name          | text        |         | No           | Public business name if different from legal name.                                   |
| business_type         | text        |         | No           | Initial classification: retail, wholesale, services, pharmacy, manufacturing, other. |
| tin_number            | text        |         | No           | Rwanda tax identifier; useful for EBM later.                                         |
| country_code          | text        |         | Yes          | Default RW; allows regional expansion.                                               |
| default_currency      | text        |         | Yes          | Default RWF.                                                                         |
| default_language_code | text        | FK      | Yes          | References languages.code; default en.                                               |
| timezone              | text        |         | Yes          | Default Africa/Kigali.                                                               |
| subscription_status   | text        |         | Yes          | trial, active, past_due, suspended, cancelled.                                       |
| onboarding_status     | text        |         | Yes          | not_started, setup_started, active, needs_help.                                      |
| is_active             | boolean     |         | Yes          | Whether tenant can access the system.                                                |
| created_at            | timestamptz |         | Yes          | System timestamp.                                                                    |
| created_by            | uuid        | FK      | No           | User who created tenant.                                                             |
| updated_at            | timestamptz |         | No           | Last update timestamp.                                                               |
| deleted_at            | timestamptz |         | No           | Soft-delete marker; avoid hard delete.                                               |

**Business rules:**

- Every business row must reference tenants.id through tenant_id.

- Tenant status controls access but should not destroy data.

- Trial and subscription status may initially be updated manually by the founder.

**Recommended indexes / constraints:**

- Unique index on tenant_code.

- Index on subscription_status for admin monitoring.

## branches

**Purpose:** Stores physical or logical business locations. MVP can create one default branch per tenant.

**Build phase:** MVP simplified / Phase 2 expanded

| **Field**    | **Type**    | **Key** | **Required** | **Description / Business Rule**      |
|--------------|-------------|---------|--------------|--------------------------------------|
| id           | uuid        | PK      | Yes          | Unique branch identifier.            |
| tenant_id    | uuid        | FK      | Yes          | Owning tenant.                       |
| branch_code  | text        |         | Yes          | Short code unique per tenant.        |
| name         | text        |         | Yes          | Branch name, e.g., Main Shop.        |
| address_text | text        |         | No           | Physical address.                    |
| phone        | text        |         | No           | Contact phone.                       |
| is_default   | boolean     |         | Yes          | Default branch for new transactions. |
| is_active    | boolean     |         | Yes          | Controls branch visibility.          |
| created_at   | timestamptz |         | Yes          | System timestamp.                    |
| updated_at   | timestamptz |         | No           | Last update timestamp.               |

**Business rules:**

- Create one default branch automatically when tenant is created.

- Later, branches enable multi-branch sales and stock reporting.

**Recommended indexes / constraints:**

- Unique index on tenant_id + branch_code.

- Partial unique index on tenant_id where is_default = true if supported.

## warehouses

**Purpose:** Stores stock locations. For a small shop, warehouse can simply mean Main Store.

**Build phase:** MVP simplified / Phase 2 expanded

| **Field**      | **Type**    | **Key** | **Required** | **Description / Business Rule**                   |
|----------------|-------------|---------|--------------|---------------------------------------------------|
| id             | uuid        | PK      | Yes          | Unique warehouse identifier.                      |
| tenant_id      | uuid        | FK      | Yes          | Owning tenant.                                    |
| branch_id      | uuid        | FK      | Yes          | Branch where stock is located.                    |
| warehouse_code | text        |         | Yes          | Code unique per tenant.                           |
| name           | text        |         | Yes          | Warehouse/location name.                          |
| warehouse_type | text        |         | Yes          | store, backroom, van, production, damaged, other. |
| is_default     | boolean     |         | Yes          | Default stock location.                           |
| is_active      | boolean     |         | Yes          | Controls usage.                                   |
| created_at     | timestamptz |         | Yes          | System timestamp.                                 |

**Business rules:**

- MVP can use one default warehouse per branch.

- Every stock movement should reference a warehouse_id.

**Recommended indexes / constraints:**

- Unique index on tenant_id + warehouse_code.

- Index on tenant_id + branch_id.

## tenant_settings

**Purpose:** Stores configurable settings per tenant without changing database schema for every preference.

**Build phase:** MVP / Scale

| **Field**     | **Type**    | **Key** | **Required** | **Description / Business Rule**                  |
|---------------|-------------|---------|--------------|--------------------------------------------------|
| id            | uuid        | PK      | Yes          | Unique setting row.                              |
| tenant_id     | uuid        | FK      | Yes          | Owning tenant.                                   |
| setting_key   | text        |         | Yes          | Machine key, e.g., invoice_prefix.               |
| setting_value | jsonb       |         | No           | Flexible value: text, number, boolean or object. |
| description   | text        |         | No           | Human explanation.                               |
| created_at    | timestamptz |         | Yes          | Created timestamp.                               |
| updated_at    | timestamptz |         | No           | Updated timestamp.                               |

**Business rules:**

- Use for configuration, not core transactional data.

- Avoid hiding important business data inside JSON.

**Recommended indexes / constraints:**

- Unique index on tenant_id + setting_key.

# 11. Data Dictionary: Security and Permissions

## app_users

**Purpose:** Application profile table linked to Supabase auth.users. Stores business-facing user details.

**Build phase:** MVP

| **Field**               | **Type**    | **Key** | **Required** | **Description / Business Rule**        |
|-------------------------|-------------|---------|--------------|----------------------------------------|
| id                      | uuid        | PK/FK   | Yes          | Same as auth.users.id or linked to it. |
| full_name               | text        |         | Yes          | User display name.                     |
| phone                   | text        |         | No           | Contact number.                        |
| email                   | text        |         | Yes          | Login/contact email.                   |
| preferred_language_code | text        | FK      | No           | Preferred UI language.                 |
| avatar_url              | text        |         | No           | Optional profile image.                |
| is_platform_admin       | boolean     |         | Yes          | True only for internal SME-OS admins.  |
| is_active               | boolean     |         | Yes          | Controls app access.                   |
| created_at              | timestamptz |         | Yes          | Created timestamp.                     |
| last_login_at           | timestamptz |         | No           | Optional login tracking.               |

**Business rules:**

- Do not store passwords; Supabase Auth manages credentials.

- A user may later belong to multiple tenants.

**Recommended indexes / constraints:**

- Unique index on email if not already enforced by auth system.

## user_tenants

**Purpose:** Junction table that connects users to tenant companies.

**Build phase:** MVP

| **Field**         | **Type**    | **Key** | **Required** | **Description / Business Rule**      |
|-------------------|-------------|---------|--------------|--------------------------------------|
| id                | uuid        | PK      | Yes          | Unique membership row.               |
| user_id           | uuid        | FK      | Yes          | References app_users.id.             |
| tenant_id         | uuid        | FK      | Yes          | References tenants.id.               |
| default_branch_id | uuid        | FK      | No           | Default branch for user actions.     |
| membership_status | text        |         | Yes          | invited, active, suspended, removed. |
| invited_by        | uuid        | FK      | No           | User who invited this member.        |
| joined_at         | timestamptz |         | No           | When membership became active.       |
| created_at        | timestamptz |         | Yes          | Created timestamp.                   |

**Business rules:**

- Most users will belong to one tenant at first.

- RLS policies can check this table to authorize tenant access.

**Recommended indexes / constraints:**

- Unique index on user_id + tenant_id.

- Index on tenant_id + membership_status.

## roles

**Purpose:** Defines user roles such as Owner, Manager, Cashier and Storekeeper.

**Build phase:** MVP simplified

| **Field**      | **Type** | **Key** | **Required** | **Description / Business Rule**                                             |
|----------------|----------|---------|--------------|-----------------------------------------------------------------------------|
| id             | uuid     | PK      | Yes          | Unique role identifier.                                                     |
| tenant_id      | uuid     | FK      | No           | Null means global system role template; tenant_id means tenant custom role. |
| role_code      | text     |         | Yes          | owner, manager, cashier, storekeeper, auditor.                              |
| role_name      | text     |         | Yes          | Human-readable role name.                                                   |
| description    | text     |         | No           | Role purpose.                                                               |
| is_system_role | boolean  |         | Yes          | Whether role is protected system role.                                      |
| is_active      | boolean  |         | Yes          | Controls availability.                                                      |

**Business rules:**

- MVP can use fixed roles without a custom role builder.

- Later allow tenant-specific custom roles.

**Recommended indexes / constraints:**

- Unique index on tenant_id + role_code, treating null carefully.

## permissions

**Purpose:** Defines granular actions that roles can perform.

**Build phase:** MVP simplified / Scale

| **Field**       | **Type** | **Key** | **Required** | **Description / Business Rule**                     |
|-----------------|----------|---------|--------------|-----------------------------------------------------|
| id              | uuid     | PK      | Yes          | Unique permission.                                  |
| permission_code | text     | UQ      | Yes          | Example: sales.create, products.edit, reports.view. |
| module_code     | text     |         | Yes          | sales, inventory, products, reports, settings.      |
| description     | text     |         | No           | Explains allowed action.                            |
| risk_level      | text     |         | No           | low, medium, high; useful for admin UI.             |

**Business rules:**

- Keep permission codes stable because app screens will depend on them.

**Recommended indexes / constraints:**

- Unique index on permission_code.

## role_permissions

**Purpose:** Maps roles to permissions.

**Build phase:** MVP simplified / Scale

| **Field**     | **Type** | **Key** | **Required** | **Description / Business Rule**                  |
|---------------|----------|---------|--------------|--------------------------------------------------|
| id            | uuid     | PK      | Yes          | Unique mapping.                                  |
| role_id       | uuid     | FK      | Yes          | References roles.id.                             |
| permission_id | uuid     | FK      | Yes          | References permissions.id.                       |
| is_allowed    | boolean  |         | Yes          | Usually true; can support explicit denial later. |

**Recommended indexes / constraints:**

- Unique index on role_id + permission_id.

## user_roles

**Purpose:** Assigns one or more roles to a user within a tenant.

**Build phase:** MVP

| **Field**   | **Type**    | **Key** | **Required** | **Description / Business Rule** |
|-------------|-------------|---------|--------------|---------------------------------|
| id          | uuid        | PK      | Yes          | Unique assignment.              |
| tenant_id   | uuid        | FK      | Yes          | Tenant context.                 |
| user_id     | uuid        | FK      | Yes          | User being assigned.            |
| role_id     | uuid        | FK      | Yes          | Assigned role.                  |
| branch_id   | uuid        | FK      | No           | Optional branch-scoped role.    |
| assigned_by | uuid        | FK      | No           | User who assigned role.         |
| assigned_at | timestamptz |         | Yes          | Assignment date.                |
| is_active   | boolean     |         | Yes          | Controls role usage.            |

**Business rules:**

- Owner should always exist for each tenant.

- Cashiers should not access tenant settings or delete posted documents.

**Recommended indexes / constraints:**

- Unique index on tenant_id + user_id + role_id + coalesce(branch_id).

# 12. Data Dictionary: Subscription and Trial Management

## subscription_plans

**Purpose:** Defines commercial plans available to customers.

**Build phase:** MVP simple / Scale

| **Field**     | **Type**      | **Key** | **Required** | **Description / Business Rule**    |
|---------------|---------------|---------|--------------|------------------------------------|
| id            | uuid          | PK      | Yes          | Unique plan.                       |
| plan_code     | text          | UQ      | Yes          | starter, business, premium.        |
| plan_name     | text          |         | Yes          | Display name.                      |
| monthly_price | numeric(14,2) |         | Yes          | Monthly price in default currency. |
| currency_code | text          |         | Yes          | RWF initially.                     |
| max_users     | integer       |         | No           | Null means unlimited.              |
| max_branches  | integer       |         | No           | Plan limit.                        |
| max_products  | integer       |         | No           | Optional trial/control limit.      |
| features      | jsonb         |         | No           | Feature flags included in plan.    |
| is_public     | boolean       |         | Yes          | Shown on website pricing page.     |
| is_active     | boolean       |         | Yes          | Available for signup.              |

**Business rules:**

- Do not overcomplicate pricing in MVP.

- Plans should support later website pricing and automated checkout.

**Recommended indexes / constraints:**

- Unique index on plan_code.

## subscriptions

**Purpose:** Stores each tenant subscription, trial and billing status.

**Build phase:** MVP

| **Field**                 | **Type**    | **Key** | **Required** | **Description / Business Rule**                   |
|---------------------------|-------------|---------|--------------|---------------------------------------------------|
| id                        | uuid        | PK      | Yes          | Unique subscription.                              |
| tenant_id                 | uuid        | FK      | Yes          | Subscribed tenant.                                |
| plan_id                   | uuid        | FK      | Yes          | Current plan.                                     |
| status                    | text        |         | Yes          | trialing, active, past_due, suspended, cancelled. |
| trial_start_date          | date        |         | No           | Free trial start.                                 |
| trial_end_date            | date        |         | No           | Free trial end.                                   |
| current_period_start      | date        |         | No           | Paid period start.                                |
| current_period_end        | date        |         | No           | Paid period end.                                  |
| billing_cycle             | text        |         | Yes          | monthly, quarterly, annual.                       |
| payment_method_preference | text        |         | No           | momo, airtel, bank, card, manual.                 |
| cancelled_at              | timestamptz |         | No           | Cancellation timestamp.                           |
| created_at                | timestamptz |         | Yes          | Created timestamp.                                |

**Business rules:**

- MVP can manually update status after payment confirmation.

- Trial access should expire automatically later via scheduled job.

**Recommended indexes / constraints:**

- Index on tenant_id + status.

- Index on trial_end_date for expiry reminders.

## billing_events

**Purpose:** Logs invoices, payments, renewals, failed payments and manual billing notes.

**Build phase:** Phase 1 manual / Scale automated

| **Field**          | **Type**      | **Key** | **Required** | **Description / Business Rule**                                   |
|--------------------|---------------|---------|--------------|-------------------------------------------------------------------|
| id                 | uuid          | PK      | Yes          | Unique billing event.                                             |
| tenant_id          | uuid          | FK      | Yes          | Tenant billed.                                                    |
| subscription_id    | uuid          | FK      | Yes          | Related subscription.                                             |
| event_type         | text          |         | Yes          | invoice_created, payment_received, payment_failed, reminder_sent. |
| amount             | numeric(14,2) |         | No           | Amount involved.                                                  |
| currency_code      | text          |         | No           | RWF initially.                                                    |
| provider           | text          |         | No           | manual, momo, airtel, bank, card.                                 |
| provider_reference | text          |         | No           | External transaction reference.                                   |
| event_status       | text          |         | Yes          | pending, successful, failed, reversed.                            |
| event_payload      | jsonb         |         | No           | Raw provider or admin details.                                    |
| created_at         | timestamptz   |         | Yes          | Created timestamp.                                                |

**Business rules:**

- Keep billing history even if subscription changes.

- Do not store sensitive card details.

**Recommended indexes / constraints:**

- Index on tenant_id + created_at.

- Index on provider + provider_reference.

# 13. Data Dictionary: Party / Customer / Supplier Model

## party_types

**Purpose:** Defines allowed classifications for parties.

**Build phase:** MVP

| **Field**   | **Type** | **Key** | **Required** | **Description / Business Rule**                        |
|-------------|----------|---------|--------------|--------------------------------------------------------|
| id          | uuid     | PK      | Yes          | Unique party type.                                     |
| type_code   | text     | UQ      | Yes          | customer, supplier, employee, contractor, distributor. |
| type_name   | text     |         | Yes          | Human name.                                            |
| description | text     |         | No           | Meaning of this type.                                  |
| is_active   | boolean  |         | Yes          | Controls usage.                                        |

**Business rules:**

- A party can have multiple types through party_type_links.

## parties

**Purpose:** Generic master table for customers, suppliers, employees and other economic actors.

**Build phase:** MVP customer / Phase 2 supplier

| **Field**          | **Type**      | **Key** | **Required** | **Description / Business Rule**                |
|--------------------|---------------|---------|--------------|------------------------------------------------|
| id                 | uuid          | PK      | Yes          | Unique party.                                  |
| tenant_id          | uuid          | FK      | Yes          | Owning tenant.                                 |
| party_code         | text          |         | Yes          | Human-friendly code unique per tenant.         |
| party_name         | text          |         | Yes          | Person or organization name.                   |
| party_kind         | text          |         | Yes          | individual, company, government, ngo, other.   |
| primary_phone      | text          |         | No           | Main phone number.                             |
| primary_email      | text          |         | No           | Main email.                                    |
| tin_number         | text          |         | No           | Tax ID if applicable.                          |
| credit_limit       | numeric(14,2) |         | No           | Optional maximum credit allowed.               |
| payment_terms_days | integer       |         | No           | Default credit terms.                          |
| opening_balance    | numeric(14,2) |         | Yes          | Initial receivable/payable balance; default 0. |
| status             | text          |         | Yes          | active, inactive, blocked.                     |
| notes              | text          |         | No           | Free notes.                                    |
| created_at         | timestamptz   |         | Yes          | Created timestamp.                             |
| created_by         | uuid          | FK      | No           | Creator user.                                  |
| updated_at         | timestamptz   |         | No           | Last update.                                   |
| deleted_at         | timestamptz   |         | No           | Soft-delete marker.                            |

**Business rules:**

- Use parties for customers in MVP instead of a separate customers table.

- A customer who later becomes a supplier remains one party record with multiple classifications.

- Blocking a party should prevent new credit sales but should not hide history.

**Recommended indexes / constraints:**

- Unique index on tenant_id + party_code.

- Index on tenant_id + party_name for search.

- Index on tenant_id + primary_phone.

## party_type_links

**Purpose:** Links parties to one or more party types.

**Build phase:** MVP

| **Field**     | **Type** | **Key** | **Required** | **Description / Business Rule**           |
|---------------|----------|---------|--------------|-------------------------------------------|
| id            | uuid     | PK      | Yes          | Unique link.                              |
| tenant_id     | uuid     | FK      | Yes          | Tenant context.                           |
| party_id      | uuid     | FK      | Yes          | References parties.id.                    |
| party_type_id | uuid     | FK      | Yes          | References party_types.id.                |
| is_primary    | boolean  |         | Yes          | Primary classification if multiple types. |

**Recommended indexes / constraints:**

- Unique index on party_id + party_type_id.

- Index on tenant_id + party_type_id.

## party_contacts

**Purpose:** Stores multiple contact persons or numbers for a party.

**Build phase:** Phase 2 / optional MVP

| **Field**      | **Type** | **Key** | **Required** | **Description / Business Rule**  |
|----------------|----------|---------|--------------|----------------------------------|
| id             | uuid     | PK      | Yes          | Unique contact.                  |
| tenant_id      | uuid     | FK      | Yes          | Tenant context.                  |
| party_id       | uuid     | FK      | Yes          | Related party.                   |
| contact_name   | text     |         | No           | Contact person name.             |
| phone          | text     |         | No           | Phone number.                    |
| email          | text     |         | No           | Email address.                   |
| position_title | text     |         | No           | Manager, owner, accountant, etc. |
| is_primary     | boolean  |         | Yes          | Primary contact flag.            |
| notes          | text     |         | No           | Extra information.               |

**Recommended indexes / constraints:**

- Index on tenant_id + party_id.

## party_addresses

**Purpose:** Stores one or more addresses for each party.

**Build phase:** Phase 2

| **Field**    | **Type** | **Key** | **Required** | **Description / Business Rule**     |
|--------------|----------|---------|--------------|-------------------------------------|
| id           | uuid     | PK      | Yes          | Unique address.                     |
| tenant_id    | uuid     | FK      | Yes          | Tenant context.                     |
| party_id     | uuid     | FK      | Yes          | Related party.                      |
| address_type | text     |         | Yes          | billing, delivery, physical, other. |
| address_line | text     |         | No           | Free text address.                  |
| city         | text     |         | No           | City/district.                      |
| country_code | text     |         | Yes          | RW initially.                       |
| is_default   | boolean  |         | Yes          | Default address flag.               |

# 14. Data Dictionary: Product and Service Model

## product_types

**Purpose:** Defines what kind of thing a product record represents.

**Build phase:** MVP

| **Field**        | **Type** | **Key** | **Required** | **Description / Business Rule**                                       |
|------------------|----------|---------|--------------|-----------------------------------------------------------------------|
| id               | uuid     | PK      | Yes          | Unique type.                                                          |
| type_code        | text     | UQ      | Yes          | stock_item, service, manufactured_item, subscription, non_stock_item. |
| type_name        | text     |         | Yes          | Human-readable label.                                                 |
| tracks_inventory | boolean  |         | Yes          | Whether stock movements apply by default.                             |
| can_be_sold      | boolean  |         | Yes          | Whether this type can appear on sales invoices.                       |
| can_be_purchased | boolean  |         | Yes          | Whether this type can appear on purchase documents.                   |
| description      | text     |         | No           | Meaning and usage.                                                    |

**Business rules:**

- This table is key to supporting retail, services and manufacturing later.

## product_categories

**Purpose:** Groups products for search, reports and pricing.

**Build phase:** MVP

| **Field**          | **Type** | **Key** | **Required** | **Description / Business Rule** |
|--------------------|----------|---------|--------------|---------------------------------|
| id                 | uuid     | PK      | Yes          | Unique category.                |
| tenant_id          | uuid     | FK      | Yes          | Owning tenant.                  |
| parent_category_id | uuid     | FK      | No           | Supports category hierarchy.    |
| category_code      | text     |         | No           | Optional code.                  |
| category_name      | text     |         | Yes          | Category name.                  |
| description        | text     |         | No           | Optional description.           |
| is_active          | boolean  |         | Yes          | Controls usage.                 |

**Recommended indexes / constraints:**

- Unique index on tenant_id + category_name.

## product_units

**Purpose:** Defines units of measure such as piece, kg, litre, carton or hour.

**Build phase:** MVP

| **Field**      | **Type** | **Key** | **Required** | **Description / Business Rule**                    |
|----------------|----------|---------|--------------|----------------------------------------------------|
| id             | uuid     | PK      | Yes          | Unique unit.                                       |
| tenant_id      | uuid     | FK      | No           | Null for global units; tenant_id for custom units. |
| unit_code      | text     |         | Yes          | pcs, kg, l, hour, carton.                          |
| unit_name      | text     |         | Yes          | Piece, Kilogram, Litre, Hour.                      |
| decimal_places | integer  |         | Yes          | Allowed quantity precision.                        |
| is_active      | boolean  |         | Yes          | Controls usage.                                    |

**Recommended indexes / constraints:**

- Unique index on tenant_id + unit_code.

## products

**Purpose:** Stores all sellable or purchasable items, including stock items, services and future manufactured goods.

**Build phase:** MVP

| **Field**            | **Type**      | **Key** | **Required** | **Description / Business Rule**                        |
|----------------------|---------------|---------|--------------|--------------------------------------------------------|
| id                   | uuid          | PK      | Yes          | Unique product.                                        |
| tenant_id            | uuid          | FK      | Yes          | Owning tenant.                                         |
| product_code         | text          |         | Yes          | Code unique per tenant.                                |
| product_name         | text          |         | Yes          | Product/service name.                                  |
| product_type_id      | uuid          | FK      | Yes          | References product_types.id.                           |
| category_id          | uuid          | FK      | No           | Product category.                                      |
| base_unit_id         | uuid          | FK      | Yes          | Default unit of measure.                               |
| barcode              | text          |         | No           | Primary barcode if used.                               |
| description          | text          |         | No           | Detailed description.                                  |
| cost_price           | numeric(18,4) |         | No           | Estimated or last cost. Use for simple profit reports. |
| selling_price        | numeric(14,2) |         | Yes          | Default selling price.                                 |
| tax_code             | text          |         | No           | Reserved for EBM/tax handling.                         |
| is_inventory_tracked | boolean       |         | Yes          | Usually true for stock items; false for services.      |
| reorder_level        | numeric(14,3) |         | No           | Low stock threshold.                                   |
| reorder_quantity     | numeric(14,3) |         | No           | Suggested reorder quantity.                            |
| allow_negative_stock | boolean       |         | Yes          | Usually false; may be true for some workflows.         |
| status               | text          |         | Yes          | active, inactive, discontinued.                        |
| created_at           | timestamptz   |         | Yes          | Created timestamp.                                     |
| updated_at           | timestamptz   |         | No           | Updated timestamp.                                     |
| deleted_at           | timestamptz   |         | No           | Soft-delete marker.                                    |

**Business rules:**

- Services are products with is_inventory_tracked = false.

- Manufactured items can later use product_type = manufactured_item and link to BOM tables.

- Do not delete products with historical transactions.

**Recommended indexes / constraints:**

- Unique index on tenant_id + product_code.

- Index on tenant_id + product_name for search.

- Index on tenant_id + barcode.

## product_prices

**Purpose:** Supports multiple price lists later, such as retail, wholesale and promotional prices.

**Build phase:** Phase 2

| **Field**     | **Type**      | **Key** | **Required** | **Description / Business Rule**   |
|---------------|---------------|---------|--------------|-----------------------------------|
| id            | uuid          | PK      | Yes          | Unique price row.                 |
| tenant_id     | uuid          | FK      | Yes          | Owning tenant.                    |
| product_id    | uuid          | FK      | Yes          | Product being priced.             |
| price_type    | text          |         | Yes          | retail, wholesale, promo, custom. |
| currency_code | text          |         | Yes          | RWF initially.                    |
| unit_price    | numeric(14,2) |         | Yes          | Selling price.                    |
| min_quantity  | numeric(14,3) |         | No           | Wholesale break quantity.         |
| valid_from    | date          |         | No           | Start date.                       |
| valid_to      | date          |         | No           | End date.                         |
| is_active     | boolean       |         | Yes          | Controls usage.                   |

**Recommended indexes / constraints:**

- Index on tenant_id + product_id + price_type.

## product_barcodes

**Purpose:** Supports multiple barcodes per product.

**Build phase:** Phase 2

| **Field**    | **Type** | **Key** | **Required** | **Description / Business Rule** |
|--------------|----------|---------|--------------|---------------------------------|
| id           | uuid     | PK      | Yes          | Unique barcode row.             |
| tenant_id    | uuid     | FK      | Yes          | Owning tenant.                  |
| product_id   | uuid     | FK      | Yes          | Product.                        |
| barcode      | text     |         | Yes          | Barcode value.                  |
| barcode_type | text     |         | No           | ean, qr, internal, supplier.    |
| is_primary   | boolean  |         | Yes          | Primary barcode flag.           |

**Recommended indexes / constraints:**

- Unique index on tenant_id + barcode.

# 15. Data Dictionary: Sales, Invoicing and Payments

## invoices

**Purpose:** Sales document header. Represents cash sales, credit sales, invoices and receipts.

**Build phase:** MVP

| **Field**       | **Type**      | **Key** | **Required** | **Description / Business Rule**           |
|-----------------|---------------|---------|--------------|-------------------------------------------|
| id              | uuid          | PK      | Yes          | Unique invoice.                           |
| tenant_id       | uuid          | FK      | Yes          | Owning tenant.                            |
| branch_id       | uuid          | FK      | Yes          | Selling branch.                           |
| warehouse_id    | uuid          | FK      | No           | Default stock source.                     |
| invoice_number  | text          |         | Yes          | Human-readable number unique per tenant.  |
| invoice_date    | date          |         | Yes          | Business date.                            |
| party_id        | uuid          | FK      | No           | Customer; optional for walk-in cash sale. |
| sale_type       | text          |         | Yes          | cash, credit, mixed.                      |
| status          | text          |         | Yes          | draft, posted, voided.                    |
| subtotal_amount | numeric(14,2) |         | Yes          | Sum before tax/discount.                  |
| discount_amount | numeric(14,2) |         | Yes          | Header discount.                          |
| tax_amount      | numeric(14,2) |         | Yes          | Tax amount if applicable.                 |
| total_amount    | numeric(14,2) |         | Yes          | Final invoice total.                      |
| paid_amount     | numeric(14,2) |         | Yes          | Total paid; can be cached from payments.  |
| balance_amount  | numeric(14,2) |         | Yes          | total_amount - paid_amount.               |
| due_date        | date          |         | No           | For credit sales.                         |
| notes           | text          |         | No           | Invoice notes.                            |
| external_status | text          |         | No           | Reserved for EBM status.                  |
| created_by      | uuid          | FK      | No           | User who created invoice.                 |
| posted_at       | timestamptz   |         | No           | When invoice became final.                |
| voided_at       | timestamptz   |         | No           | When invoice was voided.                  |
| created_at      | timestamptz   |         | Yes          | Created timestamp.                        |

**Business rules:**

- Draft invoices do not affect stock until posted, unless you choose immediate posting for MVP simplicity.

- Posted invoice lines for inventory-tracked products create negative stock_movements.

- Credit sale requires party_id. Walk-in cash sale may use null party_id or a default Walk-in Customer party.

- Voiding should create reversal movements or mark document voided and adjust reports carefully.

**Recommended indexes / constraints:**

- Unique index on tenant_id + invoice_number.

- Index on tenant_id + invoice_date.

- Index on tenant_id + party_id + status.

## invoice_lines

**Purpose:** Sales document detail lines.

**Build phase:** MVP

| **Field**           | **Type**      | **Key** | **Required** | **Description / Business Rule**                |
|---------------------|---------------|---------|--------------|------------------------------------------------|
| id                  | uuid          | PK      | Yes          | Unique line.                                   |
| tenant_id           | uuid          | FK      | Yes          | Owning tenant.                                 |
| invoice_id          | uuid          | FK      | Yes          | Parent invoice.                                |
| line_number         | integer       |         | Yes          | Display order.                                 |
| product_id          | uuid          | FK      | Yes          | Sold product/service.                          |
| description         | text          |         | No           | Override line description.                     |
| quantity            | numeric(14,3) |         | Yes          | Quantity sold.                                 |
| unit_id             | uuid          | FK      | Yes          | Unit used.                                     |
| unit_price          | numeric(14,2) |         | Yes          | Selling price.                                 |
| discount_amount     | numeric(14,2) |         | Yes          | Line discount.                                 |
| tax_amount          | numeric(14,2) |         | Yes          | Line tax.                                      |
| line_total          | numeric(14,2) |         | Yes          | Calculated line total.                         |
| cost_price_snapshot | numeric(18,4) |         | No           | Cost at sale time for profit reporting.        |
| warehouse_id        | uuid          | FK      | No           | Stock source if different from invoice header. |
| created_at          | timestamptz   |         | Yes          | Created timestamp.                             |

**Business rules:**

- Store price and cost snapshots because product prices can change later.

- Quantity must be positive for normal invoice; returns can use credit note module later.

**Recommended indexes / constraints:**

- Index on tenant_id + invoice_id.

- Index on tenant_id + product_id.

## payments

**Purpose:** Records money received from customers for invoices or account balances.

**Build phase:** MVP

| **Field**          | **Type**      | **Key** | **Required** | **Description / Business Rule**              |
|--------------------|---------------|---------|--------------|----------------------------------------------|
| id                 | uuid          | PK      | Yes          | Unique payment.                              |
| tenant_id          | uuid          | FK      | Yes          | Owning tenant.                               |
| branch_id          | uuid          | FK      | Yes          | Receiving branch.                            |
| payment_number     | text          |         | Yes          | Receipt/payment reference unique per tenant. |
| payment_date       | date          |         | Yes          | Business payment date.                       |
| party_id           | uuid          | FK      | No           | Customer making payment.                     |
| payment_method     | text          |         | Yes          | cash, momo, airtel, bank, card, other.       |
| amount             | numeric(14,2) |         | Yes          | Amount received.                             |
| currency_code      | text          |         | Yes          | RWF initially.                               |
| provider_reference | text          |         | No           | External payment reference.                  |
| status             | text          |         | Yes          | draft, posted, voided, reversed.             |
| notes              | text          |         | No           | Payment notes.                               |
| created_by         | uuid          | FK      | No           | User who recorded payment.                   |
| created_at         | timestamptz   |         | Yes          | Created timestamp.                           |
| posted_at          | timestamptz   |         | No           | Posting timestamp.                           |

**Business rules:**

- Posted payments reduce receivables.

- Unallocated payments should be allowed for account deposits, then allocated later.

**Recommended indexes / constraints:**

- Unique index on tenant_id + payment_number.

- Index on tenant_id + party_id + payment_date.

## payment_allocations

**Purpose:** Allocates payments to one or more invoices.

**Build phase:** MVP for credit sales

| **Field**        | **Type**      | **Key** | **Required** | **Description / Business Rule** |
|------------------|---------------|---------|--------------|---------------------------------|
| id               | uuid          | PK      | Yes          | Unique allocation.              |
| tenant_id        | uuid          | FK      | Yes          | Tenant context.                 |
| payment_id       | uuid          | FK      | Yes          | Payment being allocated.        |
| invoice_id       | uuid          | FK      | Yes          | Invoice being paid.             |
| allocated_amount | numeric(14,2) |         | Yes          | Amount applied to invoice.      |
| created_at       | timestamptz   |         | Yes          | Created timestamp.              |

**Business rules:**

- Sum of allocations cannot exceed payment amount.

- Sum allocated to invoice cannot exceed invoice balance.

**Recommended indexes / constraints:**

- Unique index on payment_id + invoice_id.

- Index on tenant_id + invoice_id.

# 16. Data Dictionary: Inventory and Warehouses

## stock_movements

**Purpose:** The source of truth for inventory changes. Every stock increase or decrease must be recorded here.

**Build phase:** MVP

| **Field**        | **Type**      | **Key** | **Required** | **Description / Business Rule**                                                                        |
|------------------|---------------|---------|--------------|--------------------------------------------------------------------------------------------------------|
| id               | uuid          | PK      | Yes          | Unique movement.                                                                                       |
| tenant_id        | uuid          | FK      | Yes          | Owning tenant.                                                                                         |
| branch_id        | uuid          | FK      | Yes          | Branch context.                                                                                        |
| warehouse_id     | uuid          | FK      | Yes          | Stock location.                                                                                        |
| product_id       | uuid          | FK      | Yes          | Inventory-tracked product.                                                                             |
| movement_date    | date          |         | Yes          | Business date of movement.                                                                             |
| movement_type    | text          |         | Yes          | opening, purchase, sale, adjustment, transfer_in, transfer_out, production_in, production_out, return. |
| quantity_in      | numeric(14,3) |         | Yes          | Quantity added; default 0.                                                                             |
| quantity_out     | numeric(14,3) |         | Yes          | Quantity removed; default 0.                                                                           |
| unit_cost        | numeric(18,4) |         | No           | Cost per unit for valuation.                                                                           |
| total_cost       | numeric(18,4) |         | No           | quantity \* unit_cost for valuation.                                                                   |
| source_table     | text          |         | No           | invoice_lines, purchase_lines, stock_counts, production_orders.                                        |
| source_id        | uuid          |         | No           | ID of source record.                                                                                   |
| reference_number | text          |         | No           | Human-readable source reference.                                                                       |
| reason           | text          |         | No           | Reason for adjustment or transfer.                                                                     |
| created_by       | uuid          | FK      | No           | User who created movement.                                                                             |
| created_at       | timestamptz   |         | Yes          | Created timestamp.                                                                                     |
| voided_at        | timestamptz   |         | No           | If movement is voided/reversed.                                                                        |

**Business rules:**

- Current stock = SUM(quantity_in - quantity_out) grouped by tenant, warehouse and product.

- Only inventory-tracked products should have stock movements.

- Avoid editing posted movements. Use reversal movements for corrections.

- Sales create quantity_out; purchases create quantity_in; manufacturing consumes raw materials and produces finished goods.

**Recommended indexes / constraints:**

- Index on tenant_id + product_id + movement_date.

- Index on tenant_id + warehouse_id + product_id.

- Index on source_table + source_id.

## stock_counts

**Purpose:** Header for physical stock count exercises.

**Build phase:** Phase 2

| **Field**    | **Type**    | **Key** | **Required** | **Description / Business Rule** |
|--------------|-------------|---------|--------------|---------------------------------|
| id           | uuid        | PK      | Yes          | Unique stock count.             |
| tenant_id    | uuid        | FK      | Yes          | Owning tenant.                  |
| branch_id    | uuid        | FK      | Yes          | Branch.                         |
| warehouse_id | uuid        | FK      | Yes          | Counted warehouse.              |
| count_number | text        |         | Yes          | Human-readable count reference. |
| count_date   | date        |         | Yes          | Physical count date.            |
| status       | text        |         | Yes          | draft, posted, voided.          |
| notes        | text        |         | No           | Count notes.                    |
| created_by   | uuid        | FK      | No           | User who created count.         |
| posted_at    | timestamptz |         | No           | Posting timestamp.              |

**Recommended indexes / constraints:**

- Unique index on tenant_id + count_number.

## stock_count_lines

**Purpose:** Line items for physical stock counts.

**Build phase:** Phase 2

| **Field**              | **Type**      | **Key** | **Required** | **Description / Business Rule**            |
|------------------------|---------------|---------|--------------|--------------------------------------------|
| id                     | uuid          | PK      | Yes          | Unique count line.                         |
| tenant_id              | uuid          | FK      | Yes          | Tenant context.                            |
| stock_count_id         | uuid          | FK      | Yes          | Parent stock count.                        |
| product_id             | uuid          | FK      | Yes          | Counted product.                           |
| system_quantity        | numeric(14,3) |         | Yes          | Calculated quantity before count.          |
| counted_quantity       | numeric(14,3) |         | Yes          | Physical counted quantity.                 |
| difference_quantity    | numeric(14,3) |         | Yes          | counted - system.                          |
| adjustment_movement_id | uuid          | FK      | No           | Created adjustment movement after posting. |
| notes                  | text          |         | No           | Line notes.                                |

**Business rules:**

- Posting stock count creates stock adjustment movements for differences.

# 17. Data Dictionary: Reporting and Analytics Support

## kpi_daily_summary

**Purpose:** Optional cached daily KPI table for faster dashboards at scale.

**Build phase:** Future optimization

| **Field**           | **Type**      | **Key** | **Required** | **Description / Business Rule**           |
|---------------------|---------------|---------|--------------|-------------------------------------------|
| id                  | uuid          | PK      | Yes          | Unique summary row.                       |
| tenant_id           | uuid          | FK      | Yes          | Tenant.                                   |
| branch_id           | uuid          | FK      | No           | Branch-specific or null for tenant total. |
| summary_date        | date          |         | Yes          | Business date.                            |
| total_sales         | numeric(14,2) |         | Yes          | Posted sales total.                       |
| total_payments      | numeric(14,2) |         | Yes          | Payments received.                        |
| gross_profit        | numeric(14,2) |         | No           | Sales less cost estimate.                 |
| invoice_count       | integer       |         | Yes          | Number of invoices.                       |
| new_customers_count | integer       |         | Yes          | New customers.                            |
| low_stock_count     | integer       |         | Yes          | Products below reorder level.             |
| generated_at        | timestamptz   |         | Yes          | When summary was generated.               |

**Business rules:**

- Do not build this until live queries become slow.

- Useful for scale and mobile dashboard speed.

**Recommended indexes / constraints:**

- Unique index on tenant_id + branch_id + summary_date.

## report_snapshots

**Purpose:** Stores generated report outputs for audit or repeated access.

**Build phase:** Future

| **Field**      | **Type**    | **Key** | **Required** | **Description / Business Rule**                |
|----------------|-------------|---------|--------------|------------------------------------------------|
| id             | uuid        | PK      | Yes          | Unique report snapshot.                        |
| tenant_id      | uuid        | FK      | Yes          | Tenant.                                        |
| report_code    | text        |         | Yes          | sales_daily, stock_balance, customer_balances. |
| report_name    | text        |         | Yes          | Human report name.                             |
| parameters     | jsonb       |         | No           | Report filters used.                           |
| result_payload | jsonb       |         | No           | Summary data or file metadata.                 |
| generated_by   | uuid        | FK      | No           | User who generated report.                     |
| generated_at   | timestamptz |         | Yes          | Generated timestamp.                           |

# 18. Data Dictionary: Localization and Multi-Language

## languages

**Purpose:** Defines languages supported by the platform.

**Build phase:** Design MVP / Populate gradually

| **Field**     | **Type** | **Key** | **Required** | **Description / Business Rule**        |
|---------------|----------|---------|--------------|----------------------------------------|
| code          | text     | PK      | Yes          | ISO-like code: en, fr, rw, sw.         |
| language_name | text     |         | Yes          | English, French, Kinyarwanda, Swahili. |
| native_name   | text     |         | No           | Native display name.                   |
| is_active     | boolean  |         | Yes          | Available in UI.                       |
| is_default    | boolean  |         | Yes          | Default language flag.                 |
| display_order | integer  |         | No           | Ordering in language selector.         |

**Business rules:**

- Add Swahili later by inserting language code sw and translations.

## translations

**Purpose:** Stores UI text translations using stable keys.

**Build phase:** Design MVP / Populate gradually

| **Field**        | **Type**    | **Key** | **Required** | **Description / Business Rule**            |
|------------------|-------------|---------|--------------|--------------------------------------------|
| id               | uuid        | PK      | Yes          | Unique translation row.                    |
| translation_key  | text        |         | Yes          | Stable key, e.g., menu.sales, button.save. |
| language_code    | text        | FK      | Yes          | References languages.code.                 |
| translation_text | text        |         | Yes          | Translated display text.                   |
| context          | text        |         | No           | Where key is used.                         |
| module_code      | text        |         | No           | sales, inventory, settings.                |
| is_approved      | boolean     |         | Yes          | Translation approval status.               |
| updated_at       | timestamptz |         | No           | Last update.                               |

**Business rules:**

- Do not hardcode user-facing labels if multilingual support is required.

- Translation keys must remain stable even if wording changes.

**Recommended indexes / constraints:**

- Unique index on translation_key + language_code.

- Index on module_code.

## tenant_language_settings

**Purpose:** Stores tenant-level language preferences.

**Build phase:** Future

| **Field**             | **Type**    | **Key** | **Required** | **Description / Business Rule**    |
|-----------------------|-------------|---------|--------------|------------------------------------|
| id                    | uuid        | PK      | Yes          | Unique row.                        |
| tenant_id             | uuid        | FK      | Yes          | Tenant.                            |
| default_language_code | text        | FK      | Yes          | Default UI language.               |
| enabled_languages     | text\[\]    |         | No           | Languages enabled for this tenant. |
| created_at            | timestamptz |         | Yes          | Created timestamp.                 |

# 19. Data Dictionary: Integrations and API Logging

## integration_connections

**Purpose:** Stores tenant-specific external service configurations.

**Build phase:** Future

| **Field**       | **Type**    | **Key** | **Required** | **Description / Business Rule**                                   |
|-----------------|-------------|---------|--------------|-------------------------------------------------------------------|
| id              | uuid        | PK      | Yes          | Unique connection.                                                |
| tenant_id       | uuid        | FK      | Yes          | Tenant.                                                           |
| provider_code   | text        |         | Yes          | ebm, mtn_momo, airtel_money, bank_x.                              |
| connection_name | text        |         | Yes          | Display name.                                                     |
| status          | text        |         | Yes          | not_configured, active, disabled, error.                          |
| credentials_ref | text        |         | No           | Reference to secure secret storage; do not store secrets plainly. |
| settings        | jsonb       |         | No           | Non-secret configuration.                                         |
| last_success_at | timestamptz |         | No           | Last successful communication.                                    |
| last_error_at   | timestamptz |         | No           | Last error timestamp.                                             |
| created_at      | timestamptz |         | Yes          | Created timestamp.                                                |

**Business rules:**

- Never store API secrets in plain visible tables.

- Use this table to know which tenants have which integrations.

**Recommended indexes / constraints:**

- Unique index on tenant_id + provider_code.

## integration_events

**Purpose:** Business-level log of integration events, such as invoice sent to EBM or MoMo payment received.

**Build phase:** Future

| **Field**          | **Type**    | **Key** | **Required** | **Description / Business Rule**                |
|--------------------|-------------|---------|--------------|------------------------------------------------|
| id                 | uuid        | PK      | Yes          | Unique event.                                  |
| tenant_id          | uuid        | FK      | Yes          | Tenant.                                        |
| connection_id      | uuid        | FK      | No           | Related integration connection.                |
| provider_code      | text        |         | Yes          | ebm, mtn_momo, airtel_money.                   |
| event_type         | text        |         | Yes          | invoice_submit, payment_webhook, status_check. |
| source_table       | text        |         | No           | Related internal table.                        |
| source_id          | uuid        |         | No           | Related internal record.                       |
| event_status       | text        |         | Yes          | pending, successful, failed, retrying.         |
| external_reference | text        |         | No           | Provider reference.                            |
| error_message      | text        |         | No           | Human-readable error if failed.                |
| created_at         | timestamptz |         | Yes          | Created timestamp.                             |

**Recommended indexes / constraints:**

- Index on tenant_id + provider_code + created_at.

- Index on source_table + source_id.

## api_logs

**Purpose:** Technical request/response log for API calls and webhooks.

**Build phase:** Future / limited MVP for debugging

| **Field**        | **Type**    | **Key** | **Required** | **Description / Business Rule**               |
|------------------|-------------|---------|--------------|-----------------------------------------------|
| id               | uuid        | PK      | Yes          | Unique log.                                   |
| tenant_id        | uuid        | FK      | No           | Tenant if known.                              |
| provider_code    | text        |         | No           | External provider.                            |
| direction        | text        |         | Yes          | outbound, inbound.                            |
| endpoint         | text        |         | No           | API endpoint or route.                        |
| http_method      | text        |         | No           | GET, POST, PUT, DELETE.                       |
| request_payload  | jsonb       |         | No           | Request body with sensitive fields redacted.  |
| response_payload | jsonb       |         | No           | Response body with sensitive fields redacted. |
| status_code      | integer     |         | No           | HTTP status code.                             |
| duration_ms      | integer     |         | No           | Request duration.                             |
| error_message    | text        |         | No           | Error details.                                |
| created_at       | timestamptz |         | Yes          | Created timestamp.                            |

**Business rules:**

- Redact tokens, secrets and personal sensitive data where possible.

- Keep retention policy to avoid huge logs.

# 20. Data Dictionary: Audit, Compliance and Operations

## audit_logs

**Purpose:** Records important user/system actions for accountability and troubleshooting.

**Build phase:** MVP minimal

| **Field**   | **Type**    | **Key** | **Required** | **Description / Business Rule**                    |
|-------------|-------------|---------|--------------|----------------------------------------------------|
| id          | uuid        | PK      | Yes          | Unique audit record.                               |
| tenant_id   | uuid        | FK      | No           | Tenant context if applicable.                      |
| user_id     | uuid        | FK      | No           | Actor user.                                        |
| action_code | text        |         | Yes          | create, update, delete, post, void, login, export. |
| table_name  | text        |         | No           | Affected table.                                    |
| record_id   | uuid        |         | No           | Affected row ID.                                   |
| old_values  | jsonb       |         | No           | Before values for updates, if captured.            |
| new_values  | jsonb       |         | No           | After values for updates, if captured.             |
| ip_address  | text        |         | No           | IP address if available.                           |
| user_agent  | text        |         | No           | Device/browser info.                               |
| created_at  | timestamptz |         | Yes          | Action timestamp.                                  |

**Business rules:**

- Audit posting, voiding, deletions, permission changes and subscription changes.

- Do not over-log every tiny change in MVP if it slows development.

**Recommended indexes / constraints:**

- Index on tenant_id + created_at.

- Index on table_name + record_id.

## error_logs

**Purpose:** Stores application and database error events.

**Build phase:** MVP useful

| **Field**       | **Type**    | **Key** | **Required** | **Description / Business Rule**                    |
|-----------------|-------------|---------|--------------|----------------------------------------------------|
| id              | uuid        | PK      | Yes          | Unique error.                                      |
| tenant_id       | uuid        | FK      | No           | Tenant context if known.                           |
| user_id         | uuid        | FK      | No           | User context if known.                             |
| error_source    | text        |         | Yes          | flutterflow, supabase, edge_function, integration. |
| error_code      | text        |         | No           | Internal or provider code.                         |
| error_message   | text        |         | Yes          | Human-readable message.                            |
| stack_trace     | text        |         | No           | Technical details if available.                    |
| context_payload | jsonb       |         | No           | Relevant context.                                  |
| resolved_at     | timestamptz |         | No           | Resolution timestamp.                              |
| created_at      | timestamptz |         | Yes          | Error timestamp.                                   |

**Recommended indexes / constraints:**

- Index on tenant_id + created_at.

- Index on error_source + created_at.

# 21. Future Expansion: Services, Manufacturing and Accounting

## 21.1 Service Businesses

Service businesses can be supported without changing the sales engine because services are products with is_inventory_tracked = false. Future service modules add job tracking, appointments and service tasks.

## service_jobs

**Purpose:** Tracks service work such as garage repairs, salon appointments, consulting assignments or repair jobs.

**Build phase:** Future service pack

| **Field**        | **Type**    | **Key** | **Required** | **Description / Business Rule**                        |
|------------------|-------------|---------|--------------|--------------------------------------------------------|
| id               | uuid        | PK      | Yes          | Unique service job.                                    |
| tenant_id        | uuid        | FK      | Yes          | Tenant.                                                |
| job_number       | text        |         | Yes          | Human-readable job number.                             |
| party_id         | uuid        | FK      | Yes          | Customer.                                              |
| job_type         | text        |         | No           | repair, beauty, consulting, installation, maintenance. |
| status           | text        |         | Yes          | open, in_progress, completed, invoiced, cancelled.     |
| scheduled_start  | timestamptz |         | No           | Appointment/job start.                                 |
| scheduled_end    | timestamptz |         | No           | Appointment/job end.                                   |
| assigned_user_id | uuid        | FK      | No           | Responsible staff member.                              |
| description      | text        |         | No           | Work description.                                      |
| invoice_id       | uuid        | FK      | No           | Invoice generated from job.                            |
| created_at       | timestamptz |         | Yes          | Created timestamp.                                     |

## appointments

**Purpose:** Optional calendar-style booking table.

**Build phase:** Future service pack

| **Field**          | **Type**    | **Key** | **Required** | **Description / Business Rule**                      |
|--------------------|-------------|---------|--------------|------------------------------------------------------|
| id                 | uuid        | PK      | Yes          | Unique appointment.                                  |
| tenant_id          | uuid        | FK      | Yes          | Tenant.                                              |
| party_id           | uuid        | FK      | No           | Customer.                                            |
| service_product_id | uuid        | FK      | No           | Service being booked.                                |
| assigned_user_id   | uuid        | FK      | No           | Staff member.                                        |
| start_at           | timestamptz |         | Yes          | Start time.                                          |
| end_at             | timestamptz |         | Yes          | End time.                                            |
| status             | text        |         | Yes          | scheduled, confirmed, completed, cancelled, no_show. |
| notes              | text        |         | No           | Notes.                                               |

## 21.2 Manufacturing

Manufacturing should be added only after the retail/wholesale/service foundation is validated. The existing product and stock_movement model allows manufacturing by consuming raw materials and producing finished goods.

## bill_of_materials

**Purpose:** Defines how to manufacture one product from components.

**Build phase:** Future manufacturing pack

| **Field**           | **Type**      | **Key** | **Required** | **Description / Business Rule** |
|---------------------|---------------|---------|--------------|---------------------------------|
| id                  | uuid          | PK      | Yes          | Unique BOM.                     |
| tenant_id           | uuid          | FK      | Yes          | Tenant.                         |
| finished_product_id | uuid          | FK      | Yes          | Product being manufactured.     |
| bom_code            | text          |         | Yes          | BOM reference.                  |
| bom_name            | text          |         | Yes          | BOM name.                       |
| output_quantity     | numeric(14,3) |         | Yes          | Quantity produced by this BOM.  |
| unit_id             | uuid          | FK      | Yes          | Output unit.                    |
| status              | text          |         | Yes          | draft, active, inactive.        |
| effective_from      | date          |         | No           | Validity start.                 |
| effective_to        | date          |         | No           | Validity end.                   |
| created_at          | timestamptz   |         | Yes          | Created timestamp.              |

**Recommended indexes / constraints:**

- Unique index on tenant_id + bom_code.

## bom_lines

**Purpose:** Defines components required by a bill of materials.

**Build phase:** Future manufacturing pack

| **Field**            | **Type**      | **Key** | **Required** | **Description / Business Rule** |
|----------------------|---------------|---------|--------------|---------------------------------|
| id                   | uuid          | PK      | Yes          | Unique BOM line.                |
| tenant_id            | uuid          | FK      | Yes          | Tenant.                         |
| bom_id               | uuid          | FK      | Yes          | Parent BOM.                     |
| component_product_id | uuid          | FK      | Yes          | Raw material/component.         |
| quantity_required    | numeric(14,3) |         | Yes          | Quantity consumed.              |
| unit_id              | uuid          | FK      | Yes          | Component unit.                 |
| scrap_percentage     | numeric(5,2)  |         | No           | Expected waste.                 |
| line_number          | integer       |         | Yes          | Line order.                     |

## production_orders

**Purpose:** Tracks manufacturing execution.

**Build phase:** Future manufacturing pack

| **Field**           | **Type**      | **Key** | **Required** | **Description / Business Rule**                       |
|---------------------|---------------|---------|--------------|-------------------------------------------------------|
| id                  | uuid          | PK      | Yes          | Unique production order.                              |
| tenant_id           | uuid          | FK      | Yes          | Tenant.                                               |
| branch_id           | uuid          | FK      | Yes          | Branch.                                               |
| warehouse_id        | uuid          | FK      | Yes          | Production/finished goods warehouse.                  |
| production_number   | text          |         | Yes          | Human-readable order.                                 |
| bom_id              | uuid          | FK      | Yes          | BOM used.                                             |
| finished_product_id | uuid          | FK      | Yes          | Produced item.                                        |
| planned_quantity    | numeric(14,3) |         | Yes          | Planned output.                                       |
| completed_quantity  | numeric(14,3) |         | Yes          | Actual output.                                        |
| status              | text          |         | Yes          | planned, released, in_progress, completed, cancelled. |
| start_date          | date          |         | No           | Start date.                                           |
| completion_date     | date          |         | No           | Completion date.                                      |
| created_at          | timestamptz   |         | Yes          | Created timestamp.                                    |

**Business rules:**

- Completing production creates stock_movements: raw materials out and finished goods in.

## 21.3 Accounting Foundation

Do not build full accounting in the first MVP. However, the sales, payments and inventory tables should be structured so accounting can be generated later.

## accounts

**Purpose:** Future chart of accounts.

**Build phase:** Future accounting module

| **Field**          | **Type** | **Key** | **Required** | **Description / Business Rule**                           |
|--------------------|----------|---------|--------------|-----------------------------------------------------------|
| id                 | uuid     | PK      | Yes          | Unique account.                                           |
| tenant_id          | uuid     | FK      | Yes          | Tenant.                                                   |
| account_code       | text     |         | Yes          | Account number/code.                                      |
| account_name       | text     |         | Yes          | Account name.                                             |
| account_type       | text     |         | Yes          | asset, liability, equity, income, expense, cost_of_sales. |
| parent_account_id  | uuid     | FK      | No           | Account hierarchy.                                        |
| is_posting_account | boolean  |         | Yes          | Can receive journal entries.                              |
| is_active          | boolean  |         | Yes          | Controls usage.                                           |

## journal_entries

**Purpose:** Future accounting journal header.

**Build phase:** Future accounting module

| **Field**    | **Type**    | **Key** | **Required** | **Description / Business Rule** |
|--------------|-------------|---------|--------------|---------------------------------|
| id           | uuid        | PK      | Yes          | Unique journal entry.           |
| tenant_id    | uuid        | FK      | Yes          | Tenant.                         |
| entry_number | text        |         | Yes          | Journal number.                 |
| entry_date   | date        |         | Yes          | Accounting date.                |
| source_table | text        |         | No           | Source document.                |
| source_id    | uuid        |         | No           | Source ID.                      |
| description  | text        |         | No           | Narration.                      |
| status       | text        |         | Yes          | draft, posted, voided.          |
| created_at   | timestamptz |         | Yes          | Created timestamp.              |

## journal_lines

**Purpose:** Future accounting journal details.

**Build phase:** Future accounting module

| **Field**        | **Type**      | **Key** | **Required** | **Description / Business Rule** |
|------------------|---------------|---------|--------------|---------------------------------|
| id               | uuid          | PK      | Yes          | Unique journal line.            |
| tenant_id        | uuid          | FK      | Yes          | Tenant.                         |
| journal_entry_id | uuid          | FK      | Yes          | Parent entry.                   |
| account_id       | uuid          | FK      | Yes          | Account.                        |
| party_id         | uuid          | FK      | No           | Optional customer/supplier.     |
| debit_amount     | numeric(14,2) |         | Yes          | Debit amount.                   |
| credit_amount    | numeric(14,2) |         | Yes          | Credit amount.                  |
| description      | text          |         | No           | Line narration.                 |

**Business rules:**

- A posted journal entry must balance: total debits = total credits.

# 22. Relationship Rules and Transaction Flows

## 22.1 Sales and Inventory Flow

32. User creates invoice header in invoices.

33. User adds products/services in invoice_lines.

34. For services, no stock movement is created.

35. For inventory-tracked products, posting the invoice creates stock_movements with quantity_out.

36. If cash sale, create payment and allocation immediately.

37. If credit sale, invoice balance remains outstanding until payment is recorded.

38. Dashboard and customer balance reports read from invoices, payments and allocations.

| **Business Event**             | **Tables Written**                                                      | **Result**                                            |
|--------------------------------|-------------------------------------------------------------------------|-------------------------------------------------------|
| Cash sale of stock item        | invoices, invoice_lines, payments, payment_allocations, stock_movements | Sales recorded, stock reduced, no receivable balance. |
| Credit sale                    | invoices, invoice_lines, stock_movements                                | Sales recorded, stock reduced, customer owes balance. |
| Customer payment later         | payments, payment_allocations                                           | Receivable balance reduced.                           |
| Stock adjustment               | stock_movements                                                         | Stock increased or decreased with reason.             |
| Service sale                   | invoices, invoice_lines, payments optional                              | Revenue recorded; no stock movement.                  |
| Manufacturing completion later | production_orders, stock_movements                                      | Raw materials reduced, finished goods increased.      |

## 22.2 Current Stock Calculation

Current Stock Formula:  
  
current_quantity = SUM(quantity_in - quantity_out)  
WHERE tenant_id = current tenant  
AND product_id = selected product  
AND warehouse_id = selected warehouse  
AND voided_at IS NULL  
  
Low Stock:  
current_quantity \<= products.reorder_level

## 22.3 Customer Balance Calculation

Customer Balance Formula:  
  
balance = SUM(posted invoice total_amount for customer)  
- SUM(posted payment allocations for customer)  
+ opening_balance  
  
For MVP, invoices.paid_amount and invoices.balance_amount may be cached for speed,  
but payments and payment_allocations remain the source of truth.

# 23. Supabase Implementation Notes

- Use Supabase Auth for login. Do not create your own password table.

- Create app_users as a profile table linked to auth.users.

- Enable Row-Level Security on every tenant-owned business table.

- Create helper functions such as current_tenant_ids() or user_has_permission(permission_code) if needed.

- Start with database views for dashboards instead of creating complicated backend APIs.

- Use Supabase Edge Functions later for integrations such as EBM, Mobile Money and scheduled subscription expiry.

- Use SQL migrations and version control. Avoid manual database changes without documentation.

- Use storage buckets only when needed, e.g., product images, receipts, attachments.

| **Supabase Feature** | **Use in SME-OS**                           | **Timing**  |
|----------------------|---------------------------------------------|-------------|
| Auth                 | User signup, login, password reset          | MVP         |
| PostgreSQL           | All relational data                         | MVP         |
| Row-Level Security   | Tenant isolation and permission enforcement | MVP         |
| Database views       | Dashboards and reports                      | MVP         |
| RPC functions        | Complex operations such as posting invoices | MVP/Phase 2 |
| Edge Functions       | Integrations, webhooks, scheduled jobs      | Future      |
| Storage              | Images and attachments                      | Phase 2     |
| Realtime             | Live dashboards or notifications            | Future      |

# 24. Row-Level Security Blueprint

RLS is the database-level equivalent of automatically filtering every Access query by CompanyID, except users cannot bypass it from the frontend.

- Every tenant table policy should check that tenant_id belongs to the logged-in user through user_tenants.

- Platform admins should have separate secure policies; do not use normal customer screens for platform admin access.

- Read/write policies may differ. Cashier may insert invoices but not delete products.

- Use roles and permissions in application logic first; enforce critical isolation and high-risk operations at database level.

Example RLS concept, not final production SQL:  
  
CREATE POLICY tenant_isolation_select ON products  
FOR SELECT  
USING (  
tenant_id IN (  
SELECT tenant_id  
FROM user_tenants  
WHERE user_id = auth.uid()  
AND membership_status = 'active'  
)  
);

# 25. Migration and Versioning Strategy

- Use sequential migration files: 001_core_tenants.sql, 002_security.sql, 003_products.sql, etc.

- Never change production tables manually without recording the migration.

- Use development, test and production databases separately.

- Seed lookup tables such as product_types, party_types, languages, permissions and roles.

- Before destructive migrations, export backups.

- Keep a changelog explaining why each schema change exists.

| **Migration Phase**     | **Objects**                                                                |
|-------------------------|----------------------------------------------------------------------------|
| 001 Platform            | tenants, branches, warehouses, tenant_settings                             |
| 002 Security            | app_users, user_tenants, roles, permissions, role_permissions, user_roles  |
| 003 Subscriptions       | subscription_plans, subscriptions, billing_events                          |
| 004 Parties             | party_types, parties, party_type_links, party_contacts, party_addresses    |
| 005 Products            | product_types, product_categories, product_units, products, product_prices |
| 006 Sales               | invoices, invoice_lines, payments, payment_allocations                     |
| 007 Inventory           | stock_movements, stock_counts, stock_count_lines                           |
| 008 Localization        | languages, translations, tenant_language_settings                          |
| 009 Operations          | audit_logs, error_logs                                                     |
| 010 Future Integrations | integration_connections, integration_events, api_logs                      |

# 26. Data Quality, Testing and QA

| **Test Area**       | **What to Test**                                           | **Example Acceptance Criteria**                                      |
|---------------------|------------------------------------------------------------|----------------------------------------------------------------------|
| Tenant isolation    | Users cannot see other tenant data                         | User from Tenant A cannot query Tenant B products.                   |
| Invoice posting     | Posting creates correct invoice totals and stock movements | Stock decreases by sold quantity; invoice balance matches payment.   |
| Credit sales        | Customer balance updates correctly                         | Credit invoice increases customer balance; payment reduces it.       |
| Service products    | No stock movement for service sales                        | Selling consulting service does not affect inventory.                |
| Negative stock      | System blocks or allows according to product setting       | If allow_negative_stock=false, sale cannot post below zero.          |
| Role permissions    | Cashier cannot access settings                             | Cashier menu hides settings and database blocks high-risk operation. |
| Soft deletion       | Historical reports remain correct                          | Deleted inactive product still appears in old invoices.              |
| Localization        | Language preference changes labels                         | User selecting French sees translated keys where available.          |
| Subscription status | Suspended tenant cannot use app                            | Tenant with suspended status is blocked from normal operations.      |

# 27. MVP Build Order

39. Create lookup seed tables: languages, product_types, party_types, permissions, roles.

40. Create tenants, branches and warehouses with default records.

41. Connect Supabase Auth to app_users and user_tenants.

42. Implement tenant isolation with RLS before adding real customer data.

43. Build products and categories.

44. Build parties as customers.

45. Build invoices and invoice lines.

46. Build stock movements from sales and manual adjustments.

47. Build payments and payment allocations.

48. Build dashboard views: today sales, customer balances, low stock, stock value.

49. Add audit logs for posting, voiding, login and settings changes.

50. Only after stable MVP, add purchases, suppliers, stock counts and advanced reports.

# 28. Appendices

## Appendix A: MVP Permission Matrix

| **Module / Action**          | **Owner** | **Manager** | **Cashier** | **Storekeeper** | **Auditor** |
|------------------------------|-----------|-------------|-------------|-----------------|-------------|
| View dashboard               | Yes       | Yes         | Limited     | Inventory only  | Yes         |
| Create product               | Yes       | Yes         | No          | Yes             | No          |
| Edit product price           | Yes       | Yes         | No          | No              | No          |
| Create customer              | Yes       | Yes         | Yes         | No              | No          |
| Create sale                  | Yes       | Yes         | Yes         | No              | No          |
| Void posted sale             | Yes       | Yes         | No          | No              | No          |
| Receive payment              | Yes       | Yes         | Yes         | No              | No          |
| Stock adjustment             | Yes       | Yes         | No          | Yes             | No          |
| View reports                 | Yes       | Yes         | Limited     | Inventory only  | Yes         |
| Manage users                 | Yes       | No          | No          | No              | No          |
| Change subscription/settings | Yes       | No          | No          | No              | No          |

## Appendix B: Recommended Database Views for MVP

| **View Name**            | **Purpose**                               | **Base Tables**                                  |
|--------------------------|-------------------------------------------|--------------------------------------------------|
| vw_current_stock         | Current quantity by product and warehouse | stock_movements, products, warehouses            |
| vw_low_stock             | Products at or below reorder level        | vw_current_stock, products                       |
| vw_customer_balances     | Outstanding balance by customer           | parties, invoices, payments, payment_allocations |
| vw_daily_sales           | Sales totals by day                       | invoices                                         |
| vw_product_sales_summary | Quantity and amount sold by product       | invoice_lines, invoices, products                |
| vw_gross_profit_simple   | Sales less cost snapshots                 | invoice_lines, invoices                          |
| vw_user_permissions      | Effective permissions by user and tenant  | user_roles, roles, role_permissions, permissions |

## Appendix C: AI Development Prompt Template

Use this prompt with ChatGPT, Claude, Cursor or another AI coding assistant when creating schema, Flutter and Dart code or Supabase policies:

You are helping build SME-OS, a Rwanda-focused multi-tenant SaaS for SMEs.  
Use PostgreSQL/Supabase. Every tenant-owned table must include tenant_id.  
Use UUID primary keys, created_at timestamps, soft deletion where appropriate,  
and Row-Level Security for tenant isolation.  
Do not overengineer. MVP modules are tenants, users, products, parties/customers,  
sales invoices, payments, stock movements and dashboards.  
Future modules include services, manufacturing, accounting, EBM, Mobile Money,  
French/Kinyarwanda/Swahili localization and self-service subscription billing.  
Follow the Volume 3 database blueprint.

## Appendix D: Founder Build Guardrails

- Do not build manufacturing tables into the MVP UI. Design them, but implement later.

- Do not build full accounting before sales, stock and customer balances work reliably.

- Do not create separate customer and supplier tables unless there is a strong reason; use parties.

- Do not store stock only as a number in products. Use stock_movements.

- Do not allow any table access without tenant filtering.

- Do not automate billing before manually validating paid customers.

- Do not build complex custom role management before basic roles are proven.

**  
End of Volume 3 - Database Architecture & Data Dictionary**

# 29. Integrated MVP Revision: Mobile and Offline Transactions

This revision makes mobile-first simple transactions and limited offline working an explicit MVP requirement. The objective is not to build a fully offline ERP. The objective is to allow a cashier, owner or storekeeper to continue capturing simple business activity on a phone when internet connectivity is weak, then safely synchronize once connectivity returns.

## 29.1 Strategic Decision

| **Decision Area**                     | **Revised Recommendation**                                    | **Reason**                                                                                                                                  |
|---------------------------------------|---------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| Mobile support in MVP                 | Required for simple transactions                              | Rwanda SME users may rely on phones more than laptops for daily sales, customer payments and stock checks.                                  |
| Offline support in MVP                | Limited offline draft capture and queued sync                 | Full offline ERP would slow the project; draft capture gives practical resilience without overengineering.                                  |
| Target devices                        | Mobile browser/PWA first, Android app later if needed         | Faster for a solo founder; keeps deployment simple. Flutter targets Android, iOS and web from a single codebase, with native app packaging. |
| Sync model                            | Client creates local draft, server confirms final transaction | Prevents broken records and keeps Supabase/PostgreSQL as the source of truth.                                                               |
| EBM and Mobile Money offline behavior | Do not process as final offline                               | These external integrations require network/API confirmation; offline records remain pending until confirmed online.                        |

## 29.2 Access/VBA Analogy

In Access terms, think of a mobile device as a temporary local front-end cache. The user can enter a sale into a local holding table when the network is down. Later, the application appends the record to the central backend database and marks it as synced. Until the backend confirms it, the record is not treated as a fully posted invoice.

## 29.3 Revised MVP Mobile Transaction Scope

| **Priority**         | **Capability**                                 | **MVP Decision**    | **Notes**                                                                           |
|----------------------|------------------------------------------------|---------------------|-------------------------------------------------------------------------------------|
| Must Have            | Mobile-friendly quick sale screen              | Include             | Simple sale entry must work comfortably on phone-sized screens.                     |
| Must Have            | Mobile-friendly customer payment screen        | Include             | A user should record money received from a debtor without opening a desktop report. |
| Must Have            | Mobile-friendly stock check                    | Include             | Owner/cashier can search item and see available stock.                              |
| Must Have            | Mobile-friendly stock adjustment               | Include             | Simple stock correction for owner/manager/storekeeper.                              |
| Must Have            | Local draft saving                             | Include             | If connection drops, save transaction draft locally and show Pending Sync.          |
| Must Have            | Sync status                                    | Include             | Every offline transaction shows Draft, Pending Sync, Synced, Failed or Conflict.    |
| Must Have            | Duplicate prevention                           | Include             | Use client_reference_id and idempotency keys so the same sale is not posted twice.  |
| Should Have          | Offline recent product lookup                  | Include if feasible | Cache recently synced products and prices on the device.                            |
| Should Have          | Offline recent customer lookup                 | Include if feasible | Cache recently used customers and customer balances with timestamp.                 |
| Should Have          | Automatic sync retry                           | Include if feasible | Retry queued transactions when network returns.                                     |
| Could Have           | Offline receipt preview                        | Later               | Can show provisional receipt, but not legal/fiscal receipt.                         |
| Won't Have Initially | Full offline reporting                         | Exclude             | Reports should be online in MVP.                                                    |
| Won't Have Initially | Offline EBM fiscalization                      | Exclude             | Must wait for online confirmation from EBM.                                         |
| Won't Have Initially | Offline Mobile Money confirmation              | Exclude             | Must wait for online confirmation from provider.                                    |
| Won't Have Initially | Complex offline multi-user conflict resolution | Exclude             | Log conflicts and require user/admin review.                                        |

## 29.4 Mobile-First Simple Transactions in MVP

The MVP should allow these actions from a phone without needing desktop navigation:

- Create a simple cash sale.

- Create a simple credit sale.

- Record a customer payment.

- Search product stock availability.

- Add a quick customer during a sale.

- Record a basic stock adjustment.

- View today's sales summary.

- View customer balance.

## 29.5 Offline Design Principles

- Supabase/PostgreSQL remains the system of record. Offline data is temporary until synced.

- Offline transaction numbers are provisional. Final invoice numbers are assigned by the server when synced.

- Every locally created transaction must carry a client_reference_id generated on the device.

- Sync must be idempotent. Submitting the same client_reference_id twice must not create duplicate invoices or payments.

- Offline sales should be clearly marked Pending Sync and should not be treated as fiscalized, EBM-submitted or fully final.

- If product stock has changed before sync, the server either accepts, rejects or marks the transaction as Conflict based on business rules.

- Users must see simple language: Pending, Sent, Failed, Needs Review; avoid technical sync terminology in the UI.

## 29.6 MVP Offline Business Rules

| **Rule ID** | **Rule**                                                                                                                   | **Business Meaning**                                    |
|-------------|----------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------|
| OFF-001     | A user may create a draft sale offline only if they have sales.create permission.                                          | Offline capability does not bypass role permissions.    |
| OFF-002     | Offline records must include tenant_id, branch_id, user_id, device_id and client_reference_id.                             | Every offline record remains traceable.                 |
| OFF-003     | A draft sale cannot be considered a final invoice until server sync succeeds.                                              | Prevents false reporting and legal/fiscal confusion.    |
| OFF-004     | The system must not submit EBM fiscalization while offline.                                                                | EBM integration requires connectivity and API response. |
| OFF-005     | The system must not confirm Mobile Money receipt while offline.                                                            | Payment providers must confirm receipt online.          |
| OFF-006     | If the same client_reference_id is received twice, the server returns the existing posted transaction.                     | Prevents duplicate sales/payments.                      |
| OFF-007     | A failed sync must keep the draft visible with a clear action: Retry or Review.                                            | Users should not lose transactions.                     |
| OFF-008     | Stock shown offline is last-known stock and must display the last sync timestamp.                                          | Prevents users from trusting stale stock as current.    |
| OFF-009     | Offline permissions must be based on the latest cached permission set and must expire after a configurable number of days. | Prevents old access from remaining active indefinitely. |
| OFF-010     | Server-side validation always wins over offline/client-side validation.                                                    | Protects data integrity.                                |

## 29.7 Updated MVP Build Order Impact

The earlier MVP build order remains valid, but the mobile/offline requirement changes the implementation sequence. Mobile transaction screens and sync metadata must be designed before finalizing sales and payment posting logic.

| **Build Stage**                 | **Original Focus**          | **Revised Addition**                                                               |
|---------------------------------|-----------------------------|------------------------------------------------------------------------------------|
| Authentication and tenant setup | Login, tenant, users, roles | Add device_sessions and offline permission cache strategy.                         |
| Products and customers          | Master data forms           | Add recent mobile cache eligibility flags and updated_at timestamps.               |
| Sales                           | Invoice header and lines    | Add transaction_drafts, sync_queue, client_reference_id and provisional numbering. |
| Payments                        | Record payments             | Add offline payment drafts with online confirmation requirement.                   |
| Inventory                       | Stock movements             | Add pending stock movement handling for offline sale drafts.                       |
| Reports                         | Dashboard and basic reports | Separate posted records from pending/offline drafts.                               |

# 30. Data Dictionary: Offline Sync and Mobile Transaction Tables

The following tables extend the MVP database so mobile-first transactions and limited offline draft capture are treated as first-class architecture decisions. These tables are intentionally simple and can be implemented gradually. In the first MVP, some may be implemented as local-device storage plus server logs; however, the database model should reserve them now.

## mobile_devices

Purpose: Registers devices that use the mobile transaction experience. This helps with support, security, offline permissions and troubleshooting.

Build phase: MVP simplified / Scale-up recommended

| **Field**       | **Type**    | **Key**       | **Required** | **Description / Business Rule**                           |
|-----------------|-------------|---------------|--------------|-----------------------------------------------------------|
| id              | uuid        | PK            | Yes          | Unique device record.                                     |
| tenant_id       | uuid        | FK            | Yes          | Owning tenant.                                            |
| user_id         | uuid        | FK            | Yes          | User who registered or last used the device.              |
| device_code     | text        | UQ per tenant | Yes          | Human/support-friendly device identifier.                 |
| device_name     | text        |               | No           | Name shown to owner, e.g., Cashier Phone 1.               |
| device_type     | text        |               | Yes          | mobile_web, android_app, ios_app, tablet, desktop.        |
| platform        | text        |               | No           | Android, iOS, Windows, Web.                               |
| last_seen_at    | timestamptz |               | No           | Last successful contact with server.                      |
| is_trusted      | boolean     |               | Yes          | Whether this device is allowed offline capability.        |
| offline_enabled | boolean     |               | Yes          | Whether offline draft capture is enabled for this device. |
| status          | text        |               | Yes          | active, blocked, retired.                                 |
| created_at      | timestamptz |               | Yes          | Creation timestamp.                                       |
| created_by      | uuid        | FK            | No           | User who created/registered device.                       |

Implementation notes: For early MVP, device fingerprinting can be simple. Do not overengineer device identity; focus on support visibility and blocking lost devices.

## device_sessions

Purpose: Tracks login/session context for mobile and offline-capable devices. This is useful for audit, support and permission expiry.

Build phase: MVP simplified

| **Field**             | **Type**    | **Key** | **Required** | **Description / Business Rule**                                 |
|-----------------------|-------------|---------|--------------|-----------------------------------------------------------------|
| id                    | uuid        | PK      | Yes          | Unique device session.                                          |
| tenant_id             | uuid        | FK      | Yes          | Tenant context.                                                 |
| user_id               | uuid        | FK      | Yes          | Logged-in user.                                                 |
| device_id             | uuid        | FK      | No           | References mobile_devices.id where available.                   |
| session_started_at    | timestamptz |         | Yes          | When session started.                                           |
| last_online_at        | timestamptz |         | No           | Last confirmed online check.                                    |
| permissions_cached_at | timestamptz |         | No           | When permissions were last cached for offline use.              |
| offline_allowed_until | timestamptz |         | No           | Expiry timestamp after which offline actions should be blocked. |
| ip_address            | text        |         | No           | Last known IP address.                                          |
| user_agent            | text        |         | No           | Browser/app user agent.                                         |
| status                | text        |         | Yes          | active, expired, revoked.                                       |

Implementation notes: Offline permissions should expire. This prevents a removed cashier from continuing to transact offline for too long.

## transaction_drafts

Purpose: Stores incomplete, provisional or offline-created transaction payloads before they are posted into final business tables such as invoices, payments or stock_movements.

Build phase: MVP

| **Field**           | **Type**    | **Key**       | **Required** | **Description / Business Rule**                              |
|---------------------|-------------|---------------|--------------|--------------------------------------------------------------|
| id                  | uuid        | PK            | Yes          | Unique draft identifier.                                     |
| tenant_id           | uuid        | FK            | Yes          | Owning tenant.                                               |
| branch_id           | uuid        | FK            | Yes          | Branch context.                                              |
| warehouse_id        | uuid        | FK            | No           | Warehouse context when stock is involved.                    |
| user_id             | uuid        | FK            | Yes          | User who created the draft.                                  |
| device_id           | uuid        | FK            | No           | Device used to create the draft.                             |
| draft_type          | text        |               | Yes          | sale, payment, stock_adjustment, customer_create.            |
| client_reference_id | text        | UQ per tenant | Yes          | Device-generated idempotency key.                            |
| provisional_number  | text        |               | No           | Temporary number shown before server posting.                |
| payload             | jsonb       |               | Yes          | Draft data including header, lines, payments and metadata.   |
| status              | text        |               | Yes          | draft, pending_sync, synced, failed, conflict, cancelled.    |
| source              | text        |               | Yes          | online, offline, mobile, imported.                           |
| created_offline_at  | timestamptz |               | No           | Device timestamp when created offline.                       |
| received_at         | timestamptz |               | No           | Server timestamp when received.                              |
| posted_document_id  | uuid        | FK            | No           | Final invoice/payment/stock adjustment reference after sync. |
| error_message       | text        |               | No           | User-friendly failure reason.                                |
| created_at          | timestamptz |               | Yes          | Server creation timestamp if available.                      |
| updated_at          | timestamptz |               | Yes          | Last update timestamp.                                       |

Implementation notes: This table can also store online drafts before posting. Payload JSONB gives flexibility, but final posted transactions must still be normalized into invoices, invoice_lines, payments and stock_movements.

## sync_queue

Purpose: Server-side representation of pending offline actions that need validation and posting. Client devices may also maintain a local queue, but this table provides central visibility once data reaches the backend.

Build phase: MVP / Scale-up

| **Field**           | **Type**    | **Key** | **Required** | **Description / Business Rule**                                  |
|---------------------|-------------|---------|--------------|------------------------------------------------------------------|
| id                  | uuid        | PK      | Yes          | Unique queue item.                                               |
| tenant_id           | uuid        | FK      | Yes          | Owning tenant.                                                   |
| draft_id            | uuid        | FK      | No           | References transaction_drafts.id.                                |
| queue_type          | text        |         | Yes          | post_sale, post_payment, post_stock_adjustment, create_customer. |
| client_reference_id | text        |         | Yes          | Idempotency reference from device.                               |
| payload             | jsonb       |         | Yes          | Action payload to process.                                       |
| status              | text        |         | Yes          | pending, processing, succeeded, failed, conflict, cancelled.     |
| priority            | integer     |         | Yes          | Processing priority; default 100.                                |
| attempt_count       | integer     |         | Yes          | Number of processing attempts.                                   |
| next_retry_at       | timestamptz |         | No           | When to retry if failed.                                         |
| locked_at           | timestamptz |         | No           | Set when worker/process starts handling item.                    |
| locked_by           | text        |         | No           | Worker/process identifier.                                       |
| result_reference_id | uuid        |         | No           | Final created transaction/document id.                           |
| last_error          | text        |         | No           | Last technical or business error.                                |
| created_at          | timestamptz |         | Yes          | Created timestamp.                                               |
| updated_at          | timestamptz |         | Yes          | Updated timestamp.                                               |

Implementation notes: For a low-code MVP, processing may be triggered by an app action rather than a background worker. The table still keeps sync state auditable.

## sync_logs

Purpose: Records each sync attempt for offline/mobile transactions. This is critical for support when a user says a sale disappeared or was duplicated.

Build phase: MVP

| **Field**        | **Type**    | **Key** | **Required** | **Description / Business Rule**       |
|------------------|-------------|---------|--------------|---------------------------------------|
| id               | uuid        | PK      | Yes          | Unique sync log row.                  |
| tenant_id        | uuid        | FK      | Yes          | Owning tenant.                        |
| device_id        | uuid        | FK      | No           | Device involved.                      |
| user_id          | uuid        | FK      | No           | User involved.                        |
| draft_id         | uuid        | FK      | No           | Related transaction draft.            |
| sync_queue_id    | uuid        | FK      | No           | Related queue item.                   |
| sync_direction   | text        |         | Yes          | upload, download, retry.              |
| status           | text        |         | Yes          | started, succeeded, failed, conflict. |
| records_sent     | integer     |         | No           | Number of records sent by client.     |
| records_received | integer     |         | No           | Number of records returned by server. |
| started_at       | timestamptz |         | Yes          | Attempt start time.                   |
| completed_at     | timestamptz |         | No           | Attempt completion time.              |
| error_code       | text        |         | No           | Machine-readable error.               |
| error_message    | text        |         | No           | Human-readable error.                 |

Implementation notes: Keep logs concise. Do not store sensitive payment credentials in logs.

## conflict_logs

Purpose: Stores records requiring human or business-rule review because offline data could not be safely applied automatically.

Build phase: Scale-up / Add if conflicts appear during pilot

| **Field**         | **Type**    | **Key** | **Required** | **Description / Business Rule**                                                              |
|-------------------|-------------|---------|--------------|----------------------------------------------------------------------------------------------|
| id                | uuid        | PK      | Yes          | Unique conflict row.                                                                         |
| tenant_id         | uuid        | FK      | Yes          | Owning tenant.                                                                               |
| draft_id          | uuid        | FK      | Yes          | Related draft.                                                                               |
| conflict_type     | text        |         | Yes          | stock_shortage, stale_price, deleted_product, permission_changed, duplicate_customer, other. |
| severity          | text        |         | Yes          | low, medium, high.                                                                           |
| description       | text        |         | Yes          | Explanation of the conflict.                                                                 |
| server_snapshot   | jsonb       |         | No           | Server data at conflict time.                                                                |
| client_payload    | jsonb       |         | No           | Client-submitted data.                                                                       |
| resolution_status | text        |         | Yes          | open, accepted, rejected, adjusted, ignored.                                                 |
| resolved_by       | uuid        | FK      | No           | User who resolved.                                                                           |
| resolved_at       | timestamptz |         | No           | Resolution timestamp.                                                                        |
| resolution_notes  | text        |         | No           | Explanation of decision.                                                                     |
| created_at        | timestamptz |         | Yes          | Created timestamp.                                                                           |

Implementation notes: For MVP, conflicts can be surfaced simply as Failed/Needs Review. Detailed conflict management can come after pilot feedback.

## offline_cache_metadata

Purpose: Tracks what reference data was cached on a device and when. This supports safe offline product/customer lookup.

Build phase: Should Have / Scale-up

| **Field**      | **Type**    | **Key** | **Required** | **Description / Business Rule**                     |
|----------------|-------------|---------|--------------|-----------------------------------------------------|
| id             | uuid        | PK      | Yes          | Unique cache metadata row.                          |
| tenant_id      | uuid        | FK      | Yes          | Tenant context.                                     |
| device_id      | uuid        | FK      | Yes          | Device holding cache.                               |
| cache_type     | text        |         | Yes          | products, customers, prices, permissions, settings. |
| last_synced_at | timestamptz |         | Yes          | When this cache type was last refreshed.            |
| record_count   | integer     |         | No           | Number of records cached.                           |
| cache_version  | text        |         | No           | Version/hash of cached data.                        |
| expires_at     | timestamptz |         | No           | After this time offline use should warn or block.   |
| status         | text        |         | Yes          | current, stale, expired.                            |

Implementation notes: This does not store the actual cached records; those may live in device storage. It records server awareness and freshness.

## number_sequences

Purpose: Controls server-side final numbering for invoices, receipts and other documents. Offline numbers should be provisional only.

Build phase: MVP

| **Field**      | **Type**    | **Key** | **Required** | **Description / Business Rule**                  |
|----------------|-------------|---------|--------------|--------------------------------------------------|
| id             | uuid        | PK      | Yes          | Unique sequence row.                             |
| tenant_id      | uuid        | FK      | Yes          | Owning tenant.                                   |
| branch_id      | uuid        | FK      | No           | Branch-specific sequence if required.            |
| sequence_code  | text        |         | Yes          | invoice, receipt, stock_adjustment, credit_note. |
| prefix         | text        |         | No           | Example: INV-.                                   |
| current_value  | bigint      |         | Yes          | Last assigned final number.                      |
| padding_length | integer     |         | Yes          | Number length, e.g., 6 for INV-000001.           |
| reset_period   | text        |         | No           | never, yearly, monthly.                          |
| last_reset_at  | timestamptz |         | No           | Last reset timestamp.                            |
| status         | text        |         | Yes          | active, inactive.                                |

Implementation notes: The server assigns final official numbers during successful sync/posting. Mobile devices may show TEMP- numbers before sync.

# 31. Offline Transaction Flows, Conflict Rules and MVP Build Order Update

## 31.1 Offline Quick Sale Flow

51. User opens mobile Quick Sale screen.

52. System checks connectivity and loads cached products/customers if offline.

53. User selects product/service, quantity, price and payment mode.

54. Device creates client_reference_id and provisional_number.

55. If online, app posts directly to server and receives final invoice/payment/stock movement records.

56. If offline, app stores draft locally and marks it Pending Sync.

57. When connection returns, app uploads draft to transaction_drafts/sync_queue.

58. Server validates tenant, user permission, product status, stock policy and duplicate client_reference_id.

59. If accepted, server creates invoice, invoice_lines, payments where applicable, and stock_movements.

60. Server returns final invoice number and synced status to device.

## 31.2 Offline Customer Payment Flow

61. User opens Customer Payment screen on mobile.

62. User selects customer from cached recent customers or enters customer reference.

63. User enters amount, payment method and notes.

64. If online, payment is posted immediately and customer balance updates.

65. If offline, payment is saved as provisional draft and does not reduce official balance until synced.

66. On sync, server checks duplicate reference, user permission, customer status and subscription status.

67. Server posts payment and updates receivables view.

## 31.3 Offline Stock Adjustment Flow

68. Only Owner, Manager or Storekeeper should create stock adjustment drafts.

69. User selects product, warehouse, adjustment quantity and reason.

70. Offline draft is saved with device timestamp and last-known stock displayed.

71. On sync, server creates stock_movement of type adjustment if permission and product state are valid.

72. If the adjustment conflicts with a recent count or product status change, record is marked Needs Review.

## 31.4 Conflict Handling Rules

| **Conflict Scenario**                | **MVP Handling**                                                                                        | **Scale-Up Handling**                                  |
|--------------------------------------|---------------------------------------------------------------------------------------------------------|--------------------------------------------------------|
| Duplicate client_reference_id        | Return existing posted result; do not create another transaction.                                       | Same; include support trace and duplicate audit log.   |
| Product deleted/disabled before sync | Reject draft with Needs Review message.                                                                 | Allow manager to substitute product or cancel.         |
| Stock insufficient before sync       | For strict stock policy, reject/Needs Review. For soft stock policy, allow negative stock with warning. | Tenant-configurable stock policy.                      |
| Price changed before sync            | Use offline captured price but flag if outside allowed discount/price rules.                            | Approval workflow for price exceptions.                |
| User role revoked before sync        | Reject if server permission no longer allows action.                                                    | Optional grace-period policy for low-risk actions.     |
| Customer record merged/duplicated    | Post to matched customer if clear; otherwise Needs Review.                                              | Customer merge/resolution tool.                        |
| EBM unavailable after sync           | Post internal invoice as pending fiscalization only if allowed by business/legal rules.                 | Dedicated EBM retry queue and fiscalization dashboard. |

## 31.5 Reporting Rules for Pending Offline Transactions

Dashboards and reports must separate confirmed business records from pending offline drafts. This avoids overstating sales, cash or stock before the server validates transactions.

| **Report Area**  | **Confirmed Records**              | **Pending Offline Records**                             |
|------------------|------------------------------------|---------------------------------------------------------|
| Today's Sales    | Use posted invoices only.          | Show separate card: Pending mobile sales.               |
| Cash Received    | Use posted payments only.          | Show pending customer payments separately.              |
| Stock Balance    | Use posted stock_movements only.   | Optional warning: pending stock-affecting drafts exist. |
| Customer Balance | Use posted invoices/payments only. | Show pending payments as unconfirmed.                   |
| Audit/Support    | Use audit_logs and sync_logs.      | Show draft status and errors.                           |

## 31.6 Additional Permissions

| **Permission Code**   | **Description**                              | **Recommended MVP Roles**            |
|-----------------------|----------------------------------------------|--------------------------------------|
| offline.use           | Can use limited offline transaction capture. | Owner, Manager, Cashier, Storekeeper |
| mobile.quick_sale     | Can use mobile quick sale screen.            | Owner, Manager, Cashier              |
| mobile.record_payment | Can record customer payment on mobile.       | Owner, Manager, Cashier              |
| mobile.stock_check    | Can check stock on mobile.                   | Owner, Manager, Cashier, Storekeeper |
| mobile.stock_adjust   | Can create stock adjustment from mobile.     | Owner, Manager, Storekeeper          |
| sync.review_conflicts | Can review failed/conflicting sync items.    | Owner, Manager                       |
| devices.manage        | Can trust/block devices.                     | Owner, Manager                       |

## 31.7 Supabase Implementation Notes for Offline MVP

- Use PostgreSQL constraints and unique indexes on tenant_id + client_reference_id for idempotency.

- Create views that exclude transaction_drafts from official sales totals unless explicitly reporting pending drafts.

- Apply Row-Level Security to offline tables using tenant_id exactly like other business tables.

- Use updated_at timestamps on products, parties and prices so mobile cache refresh can download only changed records later.

- Do not expose service_role keys to mobile clients. All mobile operations must run under authenticated user context or controlled server functions.

- For the Flutter MVP, keep offline support simple: local state/persistence for drafts plus explicit Sync Now action. Add automated background sync later.

- Consider Supabase Edge Functions or Postgres RPC functions for posting drafts so invoice, payment and stock movement creation happen atomically.

## 31.8 Revised MVP Definition Statement

Revised MVP definition: SME-OS MVP includes authentication, tenant setup, products/services, parties/customers, sales, payments, stock movements, dashboards, basic reports, mobile-first simple transaction screens, and limited offline draft capture with queued synchronization. Full offline ERP, offline EBM, automated Mobile Money confirmation, advanced accounting and manufacturing remain outside the initial MVP.

## 31.9 Database Objects Added by Version 1.1

| **New / Strengthened Object** | **Purpose**                                                                     | **MVP Timing**                                        |
|-------------------------------|---------------------------------------------------------------------------------|-------------------------------------------------------|
| mobile_devices                | Track and manage devices used for mobile/offline work.                          | Simplified in MVP; strengthen during pilot.           |
| device_sessions               | Track sessions, offline permission cache and expiry.                            | MVP.                                                  |
| transaction_drafts            | Store provisional/offline sales, payments and adjustments before final posting. | MVP.                                                  |
| sync_queue                    | Queue actions that need server validation and posting.                          | MVP or early scale depending on tooling.              |
| sync_logs                     | Provide support/audit trail for sync attempts.                                  | MVP.                                                  |
| conflict_logs                 | Store offline sync conflicts needing review.                                    | Add when pilot exposes conflicts; reserve design now. |
| offline_cache_metadata        | Track freshness of cached products/customers/permissions.                       | Should Have.                                          |
| number_sequences              | Assign final server-side document numbers after sync.                           | MVP.                                                  |

Founder note: mobile and offline support should increase adoption, but it must not delay first market testing. Build the smallest reliable version: simple mobile screens, local draft capture, manual Sync Now, clear status indicators, and strong duplicate prevention. Do not attempt enterprise-grade offline replication in the first release.

# 32. Credit Footprint and Bankability Layer

This section extends the operational data model so the platform can generate a credit footprint for each SME tenant and for the SME’s own credit customers. The operational tables defined earlier already record what a business sells, holds and is owed; with a small number of intentional fields and a reporting layer, that same transaction history becomes alternative credit data suitable for lender screening, partial credit guarantee (PCG) assessment and development-finance reporting.

Two distinct uses are supported and should not be confused. The first is scoring the tenant SME itself, so that a bank, a guarantee scheme or a development finance institution can assess the business that uses SME-OS. The second is scoring the tenant’s own customers, so that the SME can make safer credit-sale decisions inside the app. Both draw on the same invoices, payments and stock movements, but they serve different audiences and carry different consent obligations.

This layer is a Phase 3 capability. Do not build it before the operational MVP (sales, stock, customer balances) is stable and trusted. No SME data may leave the tenant boundary for credit assessment without explicit, recorded consent, in line with Rwanda’s data protection regime and NCSA data controller obligations.

## 32.1 Strategic Decisions

| **Decision Area**            | **Recommendation**                                                        | **Reason**                                                                                                                   |
|------------------------------|---------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| Scope of credit data         | Derive from existing operational transactions; do not duplicate raw data  | The invoice, payment and stock history already captures the signals lenders value; recomputation, not re-entry, is the task. |
| Snapshot vs live computation | Store periodic computed snapshots (monthly) and score from snapshots      | Auditable, reproducible scores; avoids recomputing trailing metrics on every request; supports model versioning.             |
| Consent model                | Explicit, recorded, revocable consent per data-sharing scope              | Required for lawful sharing of SME data with external lenders or DFIs under Rwandan data protection law.                     |
| Score ownership              | Platform computes features; risk band is advisory, not a lending decision | Keeps the platform as a data and analytics provider, not a regulated credit decision-maker.                                  |
| External facility data       | Capture loans and PCG-covered facilities only with consent                | Enables DSCR-style analysis and PCG monitoring without making the platform a core banking system.                            |
| Customer (party) credit      | Optional in-app feature; tenant-private by default                        | Lets the SME manage its own receivables risk; this data is not shared externally unless separately consented.                |

## 32.2 Schema Additions to Existing Tables

The following additive fields make the operational tables credit-aware without restructuring them. All are nullable so existing MVP behaviour is unchanged.

| **Table** | **New Field**              | **Type**      | **Purpose / Business Rule**                                                                                |
|-----------|----------------------------|---------------|------------------------------------------------------------------------------------------------------------|
| parties   | customer_credit_limit      | numeric(14,2) | Maximum receivable the SME allows this customer; supports in-app credit-sale control.                      |
| parties   | customer_credit_terms_days | integer       | Agreed payment term in days; used to compute due dates and overdue aging.                                  |
| parties   | internal_credit_rating     | text          | SME’s own rating of the customer: good, watch, restricted. Tenant-private.                                 |
| invoices  | due_date                   | date          | Required for receivables aging. Defaults to invoice_date plus customer_credit_terms_days when credit sale. |
| payments  | payment_channel            | text          | cash, momo, airtel, bank, ebm, other. Enables cash-flow channel analysis and digital-payment evidence.     |
| parties   | is_credit_eligible         | boolean       | Whether the customer may transact on credit; enforced before posting a credit sale.                        |

## sme_credit_consents

**Purpose:** Records each consent an SME tenant grants for the use or sharing of its data for credit assessment. This is the legal control point for any external data sharing.

**Build phase:** Phase 3 (build before any external sharing)

| **Field**    | **Type**    | **Key** | **Required** | **Description / Business Rule**                                  |
|--------------|-------------|---------|--------------|------------------------------------------------------------------|
| id           | uuid        | PK      | Yes          | Unique consent record.                                           |
| tenant_id    | uuid        | FK      | Yes          | SME granting consent.                                            |
| consent_type | text        |         | Yes          | internal_scoring, lender_sharing, dfi_reporting, bureau_sharing. |
| scope        | text        |         | Yes          | Specific recipient or programme, e.g., BRD, PCG_scheme, IFC.     |
| granted_by   | uuid        | FK      | Yes          | User who granted consent (must be Owner).                        |
| granted_at   | timestamptz |         | Yes          | When consent was granted.                                        |
| expires_at   | timestamptz |         | No           | Optional consent expiry.                                         |
| revoked_at   | timestamptz |         | No           | Set when consent is withdrawn; sharing must then stop.           |
| status       | text        |         | Yes          | active, expired, revoked.                                        |
| evidence_ref | text        |         | No           | Reference to signed consent document in storage.                 |
| created_at   | timestamptz |         | Yes          | System timestamp.                                                |

**Implementation notes:** No row in sme_financial_snapshots may be shared externally unless an active matching consent exists. Revocation is non-destructive; keep the record for audit.

## sme_financial_snapshots

**Purpose:** Stores periodic computed bankability metrics per tenant, normally one row per calendar month. This is the stable, auditable input to scoring and to lender reporting.

**Build phase:** Phase 3

| **Field**               | **Type**      | **Key** | **Required** | **Description / Business Rule**                         |
|-------------------------|---------------|---------|--------------|---------------------------------------------------------|
| id                      | uuid          | PK      | Yes          | Unique snapshot.                                        |
| tenant_id               | uuid          | FK      | Yes          | SME the snapshot describes.                             |
| period_start            | date          |         | Yes          | First day of the period.                                |
| period_end              | date          |         | Yes          | Last day of the period.                                 |
| total_sales             | numeric(14,2) |         | Yes          | Posted sales in period.                                 |
| cash_sales              | numeric(14,2) |         | Yes          | Sales settled immediately.                              |
| credit_sales            | numeric(14,2) |         | Yes          | Sales on terms.                                         |
| collections             | numeric(14,2) |         | Yes          | Payments received in period.                            |
| gross_margin_est        | numeric(14,2) |         | No           | Estimated margin from cost snapshots where available.   |
| receivables_outstanding | numeric(14,2) |         | Yes          | Closing receivables balance.                            |
| overdue_receivables     | numeric(14,2) |         | Yes          | Receivables past due_date at period end.                |
| avg_collection_days     | numeric(8,2)  |         | No           | Days sales outstanding (DSO) proxy.                     |
| distinct_customers      | integer       |         | Yes          | Active customers in period.                             |
| repeat_customer_ratio   | numeric(6,4)  |         | No           | Share of customers seen in prior periods.               |
| active_days             | integer       |         | Yes          | Days with at least one posted sale; trading regularity. |
| sales_volatility        | numeric(8,4)  |         | No           | Coefficient of variation of daily sales.                |
| inventory_turnover_est  | numeric(8,4)  |         | No           | Cost of sales over average inventory value.             |
| digital_payment_ratio   | numeric(6,4)  |         | No           | Share of collections via momo/airtel/bank/ebm.          |
| computed_at             | timestamptz   |         | Yes          | When the snapshot was generated.                        |
| source_method           | text          |         | Yes          | view_rollup, batch_job, manual_adjust.                  |

**Implementation notes:** Snapshots are append-only. A late-arriving offline transaction should produce a corrected snapshot row, not an in-place edit, so historical scores remain reproducible.

## credit_score_runs

**Purpose:** Records each computed credit score for a tenant, including the model version and the feature inputs used, so any score can be explained and reproduced.

**Build phase:** Phase 3

| **Field**     | **Type**     | **Key** | **Required** | **Description / Business Rule**                      |
|---------------|--------------|---------|--------------|------------------------------------------------------|
| id            | uuid         | PK      | Yes          | Unique score run.                                    |
| tenant_id     | uuid         | FK      | Yes          | SME scored.                                          |
| model_version | text         |         | Yes          | Identifier of the scoring model used.                |
| score         | numeric(8,2) |         | Yes          | Numeric score output.                                |
| risk_band     | text         |         | Yes          | A, B, C, D or low, medium, high; advisory only.      |
| snapshot_id   | uuid         | FK      | No           | Primary sme_financial_snapshots row used as input.   |
| features      | jsonb        |         | Yes          | Feature values fed to the model, for explainability. |
| purpose       | text         |         | Yes          | internal_review, lender_screening, pcg_assessment.   |
| computed_by   | uuid         | FK      | No           | User or service that ran the score.                  |
| computed_at   | timestamptz  |         | Yes          | Run timestamp.                                       |
| status        | text         |         | Yes          | draft, final, superseded.                            |

## credit_events

**Purpose:** Captures material events that affect an SME’s creditworthiness and are not visible from ordinary sales data alone.

**Build phase:** Phase 3 (optional)

| **Field**   | **Type**      | **Key** | **Required** | **Description / Business Rule**                                                              |
|-------------|---------------|---------|--------------|----------------------------------------------------------------------------------------------|
| id          | uuid          | PK      | Yes          | Unique event.                                                                                |
| tenant_id   | uuid          | FK      | Yes          | SME the event concerns.                                                                      |
| event_type  | text          |         | Yes          | loan_disbursed, repayment_made, repayment_missed, guarantee_called, large_writeoff, dispute. |
| event_date  | date          |         | Yes          | When the event occurred.                                                                     |
| amount      | numeric(14,2) |         | No           | Monetary value where relevant.                                                               |
| facility_id | uuid          | FK      | No           | References external_facilities.id where applicable.                                          |
| source      | text          |         | Yes          | self_reported, lender_confirmed, system_derived.                                             |
| notes       | text          |         | No           | Free-text context.                                                                           |
| created_at  | timestamptz   |         | Yes          | System timestamp.                                                                            |
| created_by  | uuid          | FK      | No           | User who recorded the event.                                                                 |

## external_facilities

**Purpose:** Records loans and partial-credit-guarantee-covered facilities linked to an SME, enabling debt-service analysis and PCG monitoring. Recorded only with consent; the platform is not a core banking system.

**Build phase:** Phase 3 (optional)

| **Field**              | **Type**      | **Key** | **Required** | **Description / Business Rule**                          |
|------------------------|---------------|---------|--------------|----------------------------------------------------------|
| id                     | uuid          | PK      | Yes          | Unique facility.                                         |
| tenant_id              | uuid          | FK      | Yes          | SME holding the facility.                                |
| facility_type          | text          |         | Yes          | term_loan, working_capital, overdraft, pcg_covered_loan. |
| lender_name            | text          |         | No           | Financing institution.                                   |
| guarantee_scheme       | text          |         | No           | PCG scheme name where the facility is guaranteed.        |
| guarantee_coverage_pct | numeric(5,2)  |         | No           | Share of principal covered by the guarantee.             |
| principal_amount       | numeric(14,2) |         | Yes          | Original facility amount.                                |
| outstanding_balance    | numeric(14,2) |         | No           | Current balance, if tracked.                             |
| interest_rate_pct      | numeric(6,3)  |         | No           | Nominal annual rate.                                     |
| periodic_debt_service  | numeric(14,2) |         | No           | Scheduled repayment per period; feeds DSCR.              |
| disbursement_date      | date          |         | No           | When funds were released.                                |
| maturity_date          | date          |         | No           | Scheduled end date.                                      |
| status                 | text          |         | Yes          | active, closed, in_arrears, restructured, defaulted.     |
| created_at             | timestamptz   |         | Yes          | System timestamp.                                        |

## 32.3 Reporting Views for the Credit Footprint

The following views are illustrative SQL, not final production code, in the same spirit as the RLS example earlier in this document. They compute the credit footprint from operational tables and should be created as Supabase database views or RPC functions. All views are tenant-aware and must run under Row-Level Security.

vw_receivables_aging: outstanding balance per customer, bucketed by days past due. This is the single most requested figure when a lender assesses a trading business.

CREATE VIEW vw_receivables_aging AS

SELECT

i.tenant_id,

i.party_id AS customer_id,

i.id AS invoice_id,

i.due_date,

(i.total_amount - COALESCE(p.allocated, 0)) AS outstanding,

CASE

WHEN CURRENT_DATE \<= i.due_date THEN 'current'

WHEN CURRENT_DATE \<= i.due_date + INTERVAL '30 day' THEN '1_30'

WHEN CURRENT_DATE \<= i.due_date + INTERVAL '60 day' THEN '31_60'

WHEN CURRENT_DATE \<= i.due_date + INTERVAL '90 day' THEN '61_90'

ELSE 'over_90'

END AS aging_bucket

FROM invoices i

LEFT JOIN (

SELECT invoice_id, SUM(amount) AS allocated

FROM payment_allocations

GROUP BY invoice_id

) p ON p.invoice_id = i.id

WHERE i.status = 'posted'

AND i.voided_at IS NULL

AND (i.total_amount - COALESCE(p.allocated, 0)) \> 0;

vw_monthly_cashflow_proxy: per-tenant monthly sales, collections and a simple net operating cash proxy. Lenders use trading-cash regularity as a substitute for audited statements.

CREATE VIEW vw_monthly_cashflow_proxy AS

SELECT

i.tenant_id,

DATE_TRUNC('month', i.invoice_date) AS period,

SUM(i.total_amount) AS sales,

SUM(CASE WHEN i.is_credit_sale THEN 0 ELSE i.total_amount END) AS cash_sales,

COALESCE(SUM(pay.amount), 0) AS collections,

COUNT(DISTINCT i.party_id) AS distinct_customers

FROM invoices i

LEFT JOIN payments pay

ON pay.tenant_id = i.tenant_id

AND DATE_TRUNC('month', pay.payment_date) = DATE_TRUNC('month', i.invoice_date)

WHERE i.status = 'posted' AND i.voided_at IS NULL

GROUP BY i.tenant_id, DATE_TRUNC('month', i.invoice_date);

vw_sme_bankability: a trailing-twelve-month roll-up that assembles the headline features a score consumes. It reads from the monthly snapshots so results are stable and reproducible.

CREATE VIEW vw_sme_bankability AS

SELECT

s.tenant_id,

SUM(s.total_sales) AS ttm_sales,

AVG(s.total_sales) AS avg_monthly_sales,

STDDEV_POP(s.total_sales)

/ NULLIF(AVG(s.total_sales), 0) AS sales_cv,

AVG(s.avg_collection_days) AS avg_dso,

SUM(s.overdue_receivables)

/ NULLIF(SUM(s.receivables_outstanding), 0) AS overdue_ratio,

COUNT(\*) FILTER (WHERE s.total_sales \> 0) AS active_months,

AVG(s.digital_payment_ratio) AS avg_digital_ratio,

AVG(s.repeat_customer_ratio) AS avg_repeat_ratio

FROM sme_financial_snapshots s

WHERE s.period_start \>= (CURRENT_DATE - INTERVAL '12 month')

GROUP BY s.tenant_id;

vw_dscr_inputs: assembles the components of a debt-service coverage ratio. Note the honest limitation: operational data yields a trading-cash proxy, not audited EBITDA, and the debt-service figure depends on external_facilities being populated with consent. Treat the output as an indicative screening ratio, not a substitute for credit analysis.

CREATE VIEW vw_dscr_inputs AS

SELECT

b.tenant_id,

b.ttm_sales,

-- trading-cash proxy: collections net of estimated cost of sales

(b.ttm_sales \* 0.20) AS operating_cash_proxy, -- replace 0.20 with tenant margin

COALESCE(SUM(f.periodic_debt_service) \* 12, 0) AS annual_debt_service,

CASE

WHEN COALESCE(SUM(f.periodic_debt_service), 0) = 0 THEN NULL

ELSE (b.ttm_sales \* 0.20)

/ (SUM(f.periodic_debt_service) \* 12)

END AS indicative_dscr

FROM vw_sme_bankability b

LEFT JOIN external_facilities f

ON f.tenant_id = b.tenant_id AND f.status = 'active'

GROUP BY b.tenant_id, b.ttm_sales;

## 32.4 Scoring, Risk Banding and Use

The features assembled by vw_sme_bankability map directly onto signals a development bank or guarantee scheme already values: turnover scale, trading regularity, receivables discipline, customer diversification and the share of traceable digital payments. A first-generation score can be a transparent weighted model rather than a machine-learning model; transparency is itself a selling point to a regulated lender.

The risk band produced here is advisory. The platform supplies evidence and an indicative band; the lending or guarantee decision remains with the institution. Positioned this way, the platform is an alternative-data provider feeding PCG screening and DFI portfolio monitoring, not a regulated credit decision-maker. This keeps the regulatory burden manageable while preserving the commercial value of the data.

| **Audience**            | **What the layer provides**                               | **Decision it supports**                           |
|-------------------------|-----------------------------------------------------------|----------------------------------------------------|
| The SME (in-app)        | Receivables aging, customer credit limits, overdue alerts | Whether to extend credit to a given customer.      |
| Commercial lender / BRD | Bankability features, trading-cash proxy, indicative band | Whether to screen the SME in for a facility.       |
| PCG scheme              | Facility linkage, overdue and event history               | Eligibility and monitoring of guaranteed exposure. |
| DFI (IFC, AfDB, KfW)    | Aggregated, consented portfolio metrics                   | Programme reporting and impact measurement.        |

## 32.5 Data Protection and Consent

Because this layer can move SME data beyond the tenant boundary, it is governed by Rwanda’s data protection law and the obligations of a registered data controller. The platform must hold an active sme_credit_consents record matching the recipient and purpose before any snapshot or score is disclosed externally. Consent is revocable, and revocation must immediately halt further sharing while preserving prior records for audit. Customer-level credit data (the party fields and in-app aging) is tenant-private by default and is never shared externally on the basis of the SME’s own consent alone.

## 32.6 Build Phase and Guardrails

Do not build this layer until the operational MVP is stable and a real customer base is generating reliable transaction history; a credit footprint built on thin or inaccurate operational data is worse than none. Add the snapshot table and the in-app receivables views first, since they are useful to the SME immediately and require no external sharing. Defer external scoring, facility tracking and DFI reporting until consent governance and at least six to twelve months of trading history are in place. Keep the score model versioned and explainable from day one, so that every figure shared with a lender can be reconstructed and defended.

End of Section 32 - Credit Footprint and Bankability Layer.

# 33. Data Protection Compliance (Law No. 058/2021)

This section aligns the platform with Rwanda’s Law No. 058/2021 of 13/10/2021 relating to the protection of personal data and privacy, supervised by the National Cyber Security Authority (NCSA) through its Data Protection and Privacy Office. The transition period under the law has closed and the law is fully enforceable; it also reaches foreign-hosted systems that process the personal data of people in Rwanda.

The section is deliberately sequence-aware. Obligations under the law attach to the personal data of identifiable real people, not to software development. The defining trigger is therefore the moment real customer data first enters the system, not the number of customers. There is no small-scale or early-pilot exemption: a pilot running on real debtor names, contacts and balances is fully in scope. The practical consequence is encouraging - the inexpensive compliance steps are done once, before launch, and they do not by themselves require moving off the current stack.

## 33.1 Controller and Processor Roles

The platform operator holds two distinct legal roles at the same time, and registration must cover both.

| **Role**        | **Who**                           | **Data concerned**                                                    | **Implication**                                                                                 |
|-----------------|-----------------------------------|-----------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|
| Data controller | Platform operator                 | Account, billing, user identity and login data of the SME’s own staff | Operator decides purpose and means; must register as controller.                                |
| Data processor  | Platform operator                 | The SME tenant’s business data (its customers, suppliers, debtors)    | Operator processes on the tenant’s behalf; the tenant is the controller of that data.           |
| Sub-processor   | Hosting provider (e.g., Supabase) | All personal data physically stored on the infrastructure             | Requires a data processing agreement flowing down the operator’s obligations.                   |
| Data controller | SME tenant                        | Its own customers’ and suppliers’ personal data                       | The tenant is responsible to its own customers; the platform supports, not replaces, that duty. |

## 33.2 Compliance Sequencing

The following stages map obligations to the real state of the data. Stage 2 is the gate that must be fully satisfied before the first real customer is onboarded.

| **Stage**                      | **Trigger / data state**                                                                                     | **Required actions**                                                                                                                                                                                                                                                                                                                                                                                                                                        |
|--------------------------------|--------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1\. Build and test             | Synthetic or seed data only; no real personal data                                                           | No data-protection obligations. Continue on the current managed Supabase stack. Use clearly fake names, contacts and TINs in test data.                                                                                                                                                                                                                                                                                                                     |
| 2\. Pre-launch compliance gate | Immediately before the first real customer’s data is entered                                                 | Register with NCSA as controller and processor; obtain the offshore-storage certificate if hosting remains abroad; designate a Data Protection Officer; sign DPAs with each tenant and with the hosting provider; publish a privacy policy; establish lawful basis and consent capture; create the processing-activities register; stand up the breach procedure; encrypt offline device cache; complete a DPIA before enabling the credit-footprint layer. |
| 3\. Operating                  | Live, processing real personal data                                                                          | Honour data-subject requests; notify NCSA of any breach within 48 hours; notify NCSA of material changes within 15 working days; keep processing records current.                                                                                                                                                                                                                                                                                           |
| 4\. Optional Rwanda migration  | Driven by cost, latency, or a client (e.g., a bank or DFI) requiring in-country data - not by the law itself | Self-host the Supabase stack on Rwandan infrastructure; migrate via PostgreSQL dump/restore or logical replication. Optional if the offshore-storage certificate is held and maintained.                                                                                                                                                                                                                                                                    |

**Key clarification:** Compliance and hosting location are separate decisions. The law permits offshore storage where a valid NCSA offshore-storage certificate is held and a lawful transfer basis exists (consent or contract necessity, both present with paying customers). Doing the registration and certificate work early therefore keeps the current stack lawful and makes a Rwanda migration optional rather than mandatory.

## 33.3 Lawful Basis and Consent

Consent under the law must be freely given, specific, informed and unambiguous. Not all processing relies on consent; each purpose should be tied to a lawful basis and recorded in the processing register.

| **Processing purpose**                        | **Typical lawful basis**                    | **Notes**                                                         |
|-----------------------------------------------|---------------------------------------------|-------------------------------------------------------------------|
| SME account creation and billing              | Performance of a contract                   | Operator is controller for this data.                             |
| Storing customer, supplier and debtor records | Contract or legitimate interest of the SME  | The SME tenant is the controller; the platform processes.         |
| Recording debts, receivables and payments     | Contract or legitimate interest             | Core operational processing.                                      |
| Offline capture and on-device caching         | Contract necessity with security safeguards | Cache must be encrypted; lost device is a notifiable breach risk. |
| Credit footprint and external sharing         | Explicit consent plus a completed DPIA      | Governed by Section 32 and sme_credit_consents.                   |
| Public website leads and marketing            | Consent                                     | Separate, withdrawable consent.                                   |

## consent_records

**Purpose:** General-purpose record of consent given by a data subject for a specific processing purpose, separate from the credit-specific sme_credit_consents table.

**Build phase:** Pre-launch gate (Stage 2)

| **Field**            | **Type**    | **Key** | **Required** | **Description / Business Rule**                                |
|----------------------|-------------|---------|--------------|----------------------------------------------------------------|
| id                   | uuid        | PK      | Yes          | Unique consent record.                                         |
| tenant_id            | uuid        | FK      | No           | Tenant context where applicable.                               |
| subject_type         | text        |         | Yes          | app_user, customer, supplier, lead.                            |
| subject_ref          | text        |         | Yes          | Identifier of the data subject (party_id, user_id or contact). |
| purpose              | text        |         | Yes          | Processing purpose the consent covers.                         |
| consent_text_version | text        |         | Yes          | Version of the consent wording shown.                          |
| granted_at           | timestamptz |         | Yes          | When consent was given.                                        |
| withdrawn_at         | timestamptz |         | No           | When consent was withdrawn; processing must then stop.         |
| channel              | text        |         | No           | web, app, paper, ussd.                                         |
| status               | text        |         | Yes          | active, withdrawn, expired.                                    |
| created_at           | timestamptz |         | Yes          | System timestamp.                                              |

## processing_activities_register

**Purpose:** Record of processing activities required by Article 17, to be produced to the NCSA on request. One row per distinct processing purpose.

**Build phase:** Pre-launch gate (Stage 2)

| **Field**         | **Type**    | **Key** | **Required** | **Description / Business Rule**                             |
|-------------------|-------------|---------|--------------|-------------------------------------------------------------|
| id                | uuid        | PK      | Yes          | Unique register entry.                                      |
| activity_name     | text        |         | Yes          | Short name of the processing activity.                      |
| controller_role   | text        |         | Yes          | operator_controller, operator_processor, tenant_controller. |
| purpose           | text        |         | Yes          | Why the data is processed.                                  |
| lawful_basis      | text        |         | Yes          | contract, consent, legitimate_interest, legal_obligation.   |
| data_categories   | text        |         | Yes          | Categories of personal data involved.                       |
| data_subjects     | text        |         | Yes          | Categories of people affected.                              |
| recipients        | text        |         | No           | Who the data may be disclosed to.                           |
| cross_border      | boolean     |         | Yes          | Whether data leaves Rwanda.                                 |
| retention_period  | text        |         | Yes          | How long data is kept and why.                              |
| security_measures | text        |         | No           | Key safeguards applied.                                     |
| updated_at        | timestamptz |         | Yes          | Last review/update date.                                    |

## data_processing_agreements

**Purpose:** Tracks the data processing agreements in force, both with tenants and with sub-processors such as the hosting provider.

**Build phase:** Pre-launch gate (Stage 2)

| **Field**         | **Type**    | **Key** | **Required** | **Description / Business Rule**              |
|-------------------|-------------|---------|--------------|----------------------------------------------|
| id                | uuid        | PK      | Yes          | Unique agreement record.                     |
| counterparty_type | text        |         | Yes          | tenant, sub_processor.                       |
| counterparty_name | text        |         | Yes          | Name of the tenant or provider.              |
| tenant_id         | uuid        | FK      | No           | Linked tenant where applicable.              |
| agreement_ref     | text        |         | No           | Reference to the signed document in storage. |
| effective_date    | date        |         | Yes          | When the agreement takes effect.             |
| review_date       | date        |         | No           | Next scheduled review.                       |
| status            | text        |         | Yes          | active, expired, terminated.                 |
| created_at        | timestamptz |         | Yes          | System timestamp.                            |

## data_subject_requests

**Purpose:** Logs and tracks requests by individuals to exercise their rights of access, rectification, erasure and objection, with the response timeline.

**Build phase:** Pre-launch gate (Stage 2)

| **Field**    | **Type**    | **Key** | **Required** | **Description / Business Rule**                              |
|--------------|-------------|---------|--------------|--------------------------------------------------------------|
| id           | uuid        | PK      | Yes          | Unique request.                                              |
| tenant_id    | uuid        | FK      | No           | Tenant context where the data sits.                          |
| request_type | text        |         | Yes          | access, rectification, erasure, objection, portability.      |
| subject_ref  | text        |         | Yes          | Identifier of the requesting data subject.                   |
| received_at  | timestamptz |         | Yes          | When the request was received.                               |
| verified_at  | timestamptz |         | No           | When the requester’s identity was verified.                  |
| due_by       | date        |         | Yes          | Response deadline.                                           |
| resolution   | text        |         | No           | fulfilled, partially_fulfilled, refused_with_reason.         |
| resolved_at  | timestamptz |         | No           | When the request was closed.                                 |
| notes        | text        |         | No           | Context, including any lawful retention that limits erasure. |
| created_at   | timestamptz |         | Yes          | System timestamp.                                            |

**Implementation notes:** Erasure must be reconciled with the soft-delete principle and with legal retention duties (for example tax and EBM records). Where data cannot be erased due to a legal retention obligation, anonymise it where possible and record the reason rather than refusing silently.

## data_breach_log

**Purpose:** Records personal data breaches and the notifications required by Articles 43 and 45, supporting the 48-hour notification duty to the NCSA.

**Build phase:** Pre-launch gate (Stage 2)

| **Field**            | **Type**    | **Key** | **Required** | **Description / Business Rule**                        |
|----------------------|-------------|---------|--------------|--------------------------------------------------------|
| id                   | uuid        | PK      | Yes          | Unique breach record.                                  |
| tenant_id            | uuid        | FK      | No           | Affected tenant where applicable.                      |
| detected_at          | timestamptz |         | Yes          | When the breach was discovered.                        |
| nature               | text        |         | Yes          | confidentiality, integrity, availability.              |
| description          | text        |         | Yes          | What happened and how.                                 |
| data_categories      | text        |         | Yes          | Categories of personal data affected.                  |
| approx_subjects      | integer     |         | No           | Estimated number of people affected.                   |
| risk_level           | text        |         | Yes          | low, medium, high.                                     |
| ncsa_notified_at     | timestamptz |         | No           | When the NCSA was notified (target within 48h).        |
| subjects_notified_at | timestamptz |         | No           | When affected individuals were notified, if high risk. |
| remediation          | text        |         | No           | Containment and corrective actions.                    |
| status               | text        |         | Yes          | open, contained, closed.                               |
| created_at           | timestamptz |         | Yes          | System timestamp.                                      |

## 33.4 Data Residency and Cross-Border Transfer

Article 50 requires personal data to be stored in Rwanda unless the controller or processor holds a valid NCSA-issued certificate authorising offshore storage. Article 48 permits transfer outside Rwanda where the NCSA has authorised it on proof of appropriate safeguards, where the data subject consents, or where transfer is necessary to perform a contract with the data subject. Because the current managed stack stores data outside Rwanda, the lawful position before launch is to either obtain the offshore-storage certificate or migrate personal-data storage into Rwanda. The certificate route keeps the existing stack and is the lower-friction option for a solo founder.

## 33.5 Security and Sensitive Data

Personal data must be protected with appropriate technical measures, including encryption in transit and at rest, and access controls. The platform’s Row-Level Security and audit logging support this, but the offline device cache and transaction drafts held on phones must also be encrypted, since a lost or stolen device holding cleartext personal data is a reportable breach.

Sensitive personal data carries enhanced duties under Article 11, including separate storage and measures such as tokenisation, pseudonymisation or encryption. Ordinary retail and wholesale data is not sensitive, but the planned pharmacy module would process health-related data, which is sensitive. Do not enable any health-data processing until the Article 11 safeguards are implemented.

## 33.6 Pre-Launch Compliance Checklist

Each item below must be satisfied before the first real customer’s personal data is entered. The status column is for the founder to track completion.

| **Requirement**                                         | **Law reference** | **Stage** | **Status** |
|---------------------------------------------------------|-------------------|-----------|------------|
| Register as data controller with NCSA                   | Arts. 29-31       | Gate      |            |
| Register as data processor with NCSA                    | Arts. 29-31       | Gate      |            |
| Obtain offshore-storage certificate (if hosting abroad) | Art. 50           | Gate      |            |
| Designate a Data Protection Officer                     | Art. 8            | Gate      |            |
| Sign DPA with each tenant                               | Processor duties  | Gate      |            |
| Sign DPA with hosting sub-processor                     | Processor duties  | Gate      |            |
| Publish privacy policy                                  | Transparency      | Gate      |            |
| Implement lawful-basis and consent capture              | Consent rules     | Gate      |            |
| Build processing-activities register                    | Art. 17           | Gate      |            |
| Stand up 48-hour breach procedure                       | Arts. 43, 45      | Gate      |            |
| Encrypt offline device cache                            | Security duties   | Gate      |            |
| Complete DPIA before enabling credit layer              | Art. 38           | Gate      |            |
| Implement data-subject-request handling                 | Subject rights    | Gate      |            |

Penalty context for non-compliance: an administrative fine of between two and five million Rwandan francs, or one percent of the previous year’s global turnover, with more serious violations attracting higher penalties.

## 33.7 Build Phase and Guardrails

Do not enter any real personal data while still in the build-and-test stage; use synthetic data so the project carries no premature obligations. Do not onboard a single real customer before every item in the pre-launch checklist is satisfied, since a small pilot on real data is fully in scope. Do not treat a Rwanda migration as a legal prerequisite; it is an optional, business-driven step once the offshore-storage certificate is held. Do not enable the credit-footprint layer or any health-data processing before the DPIA and the Article 11 safeguards, respectively, are in place.

End of Section 33 - Data Protection Compliance (Law No. 058/2021).