-- ============================================================
-- SME-OS Migration 004
-- Parties, Customers, Products, Services
--
-- Creates:
--   - party_types
--   - parties
--   - party_type_links
--   - party_contacts
--   - party_addresses
--   - product_types
--   - product_categories
--   - product_units
--   - products
--   - product_prices
--   - product_barcodes
--
-- No-Docker workflow:
-- Save this file in Cursor, then copy and run it in Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Party Types
-- A party can be a customer, supplier, employee, contractor, etc.
-- MVP uses customer first.
-- ------------------------------------------------------------

create table if not exists public.party_types (
  id uuid primary key default gen_random_uuid(),

  type_code text not null,
  type_name text not null,
  description text,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),

  constraint party_types_type_code_unique
    unique (type_code),

  constraint party_types_type_code_check
    check (type_code in (
      'customer',
      'supplier',
      'employee',
      'contractor',
      'distributor',
      'other'
    ))
);

create index if not exists idx_party_types_is_active
on public.party_types (is_active);

-- ------------------------------------------------------------
-- 2. Parties
-- Generic master table for customers, suppliers, and other actors.
--
-- Access/VBA analogy:
-- Instead of separate tblCustomers and tblSuppliers,
-- we use one tblParties and classify each party by type.
-- ------------------------------------------------------------

create table if not exists public.parties (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,

  party_code text not null,
  party_name text not null,

  party_kind text not null default 'individual',

  primary_phone text,
  primary_email text,
  tin_number text,

  -- Credit readiness / customer credit control fields
  customer_credit_limit numeric(14,2),
  customer_credit_terms_days integer,
  internal_credit_rating text,
  is_credit_eligible boolean not null default true,

  opening_balance numeric(14,2) not null default 0,

  status text not null default 'active',
  notes text,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,
  deleted_at timestamptz,
  deleted_by uuid references public.app_users(id) on delete set null,

  constraint parties_tenant_party_code_unique
    unique (tenant_id, party_code),

  constraint parties_party_kind_check
    check (party_kind in (
      'individual',
      'company',
      'government',
      'ngo',
      'other'
    )),

  constraint parties_status_check
    check (status in (
      'active',
      'inactive',
      'blocked'
    )),

  constraint parties_internal_credit_rating_check
    check (
      internal_credit_rating is null
      or internal_credit_rating in (
        'good',
        'watch',
        'restricted',
        'unknown'
      )
    ),

  constraint parties_customer_credit_limit_check
    check (
      customer_credit_limit is null
      or customer_credit_limit >= 0
    ),

  constraint parties_customer_credit_terms_days_check
    check (
      customer_credit_terms_days is null
      or customer_credit_terms_days >= 0
    )
);

create index if not exists idx_parties_tenant_id
on public.parties (tenant_id);

create index if not exists idx_parties_tenant_name
on public.parties (tenant_id, party_name);

create index if not exists idx_parties_tenant_phone
on public.parties (tenant_id, primary_phone);

create index if not exists idx_parties_tenant_status
on public.parties (tenant_id, status);

create index if not exists idx_parties_credit_eligible
on public.parties (tenant_id, is_credit_eligible);

create trigger trg_parties_set_updated_at
before update on public.parties
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3. Party Type Links
-- Allows one party to be both customer and supplier.
-- ------------------------------------------------------------

create table if not exists public.party_type_links (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  party_id uuid not null references public.parties(id) on delete cascade,
  party_type_id uuid not null references public.party_types(id) on delete restrict,

  is_primary boolean not null default false,

  created_at timestamptz not null default now(),

  constraint party_type_links_party_type_unique
    unique (party_id, party_type_id)
);

create index if not exists idx_party_type_links_tenant_id
on public.party_type_links (tenant_id);

create index if not exists idx_party_type_links_party_id
on public.party_type_links (party_id);

create index if not exists idx_party_type_links_party_type_id
on public.party_type_links (party_type_id);

-- ------------------------------------------------------------
-- 4. Party Contacts
-- Optional multiple contacts per party.
-- ------------------------------------------------------------

create table if not exists public.party_contacts (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  party_id uuid not null references public.parties(id) on delete cascade,

  contact_name text,
  phone text,
  email text,
  position_title text,

  is_primary boolean not null default false,
  notes text,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null
);

create index if not exists idx_party_contacts_tenant_party
on public.party_contacts (tenant_id, party_id);

create trigger trg_party_contacts_set_updated_at
before update on public.party_contacts
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 5. Party Addresses
-- Optional addresses per party.
-- ------------------------------------------------------------

create table if not exists public.party_addresses (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  party_id uuid not null references public.parties(id) on delete cascade,

  address_type text not null default 'physical',
  address_line text,
  city text,
  country_code text not null default 'RW',

  is_default boolean not null default false,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,

  constraint party_addresses_address_type_check
    check (address_type in (
      'billing',
      'delivery',
      'physical',
      'other'
    ))
);

create index if not exists idx_party_addresses_tenant_party
on public.party_addresses (tenant_id, party_id);

create trigger trg_party_addresses_set_updated_at
before update on public.party_addresses
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 6. Product Types
-- A product can be stock item, service, manufactured item, etc.
-- ------------------------------------------------------------

create table if not exists public.product_types (
  id uuid primary key default gen_random_uuid(),

  type_code text not null,
  type_name text not null,

  tracks_inventory boolean not null default false,
  can_be_sold boolean not null default true,
  can_be_purchased boolean not null default true,

  description text,

  is_active boolean not null default true,
  created_at timestamptz not null default now(),

  constraint product_types_type_code_unique
    unique (type_code),

  constraint product_types_type_code_check
    check (type_code in (
      'stock_item',
      'service',
      'manufactured_item',
      'subscription',
      'non_stock_item'
    ))
);

create index if not exists idx_product_types_active
on public.product_types (is_active);

-- ------------------------------------------------------------
-- 7. Product Categories
-- Tenant-owned product/service grouping.
-- ------------------------------------------------------------

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  parent_category_id uuid references public.product_categories(id) on delete set null,

  category_code text,
  category_name text not null,
  description text,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,
  deleted_at timestamptz,
  deleted_by uuid references public.app_users(id) on delete set null,

  constraint product_categories_tenant_name_unique
    unique (tenant_id, category_name)
);

create index if not exists idx_product_categories_tenant_id
on public.product_categories (tenant_id);

create index if not exists idx_product_categories_parent
on public.product_categories (parent_category_id);

create index if not exists idx_product_categories_active
on public.product_categories (tenant_id, is_active);

create trigger trg_product_categories_set_updated_at
before update on public.product_categories
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 8. Product Units
-- Units of measure: pcs, kg, litre, hour, carton, etc.
-- tenant_id can be null for global units.
-- ------------------------------------------------------------

create table if not exists public.product_units (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid references public.tenants(id) on delete cascade,

  unit_code text not null,
  unit_name text not null,

  decimal_places integer not null default 0,

  is_active boolean not null default true,
  created_at timestamptz not null default now(),

  constraint product_units_decimal_places_check
    check (decimal_places >= 0 and decimal_places <= 6)
);

create unique index if not exists idx_product_units_global_unit_code_unique
on public.product_units (unit_code)
where tenant_id is null;

create unique index if not exists idx_product_units_tenant_unit_code_unique
on public.product_units (tenant_id, unit_code)
where tenant_id is not null;

create index if not exists idx_product_units_tenant_id
on public.product_units (tenant_id);

-- ------------------------------------------------------------
-- 9. Products
-- Stores sellable/purchasable items and services.
-- ------------------------------------------------------------

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,

  product_code text not null,
  product_name text not null,

  product_type_id uuid not null references public.product_types(id) on delete restrict,
  category_id uuid references public.product_categories(id) on delete set null,
  base_unit_id uuid not null references public.product_units(id) on delete restrict,

  barcode text,
  description text,

  cost_price numeric(18,4),
  selling_price numeric(14,2) not null default 0,

  tax_code text,

  is_inventory_tracked boolean not null default false,

  reorder_level numeric(14,3),
  reorder_quantity numeric(14,3),

  allow_negative_stock boolean not null default false,

  status text not null default 'active',

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,
  deleted_at timestamptz,
  deleted_by uuid references public.app_users(id) on delete set null,

  constraint products_tenant_product_code_unique
    unique (tenant_id, product_code),

  constraint products_selling_price_check
    check (selling_price >= 0),

  constraint products_cost_price_check
    check (cost_price is null or cost_price >= 0),

  constraint products_reorder_level_check
    check (reorder_level is null or reorder_level >= 0),

  constraint products_reorder_quantity_check
    check (reorder_quantity is null or reorder_quantity >= 0),

  constraint products_status_check
    check (status in (
      'active',
      'inactive',
      'discontinued'
    ))
);

create index if not exists idx_products_tenant_id
on public.products (tenant_id);

create index if not exists idx_products_tenant_name
on public.products (tenant_id, product_name);

create index if not exists idx_products_tenant_barcode
on public.products (tenant_id, barcode);

create index if not exists idx_products_tenant_status
on public.products (tenant_id, status);

create index if not exists idx_products_category_id
on public.products (category_id);

create index if not exists idx_products_inventory_tracked
on public.products (tenant_id, is_inventory_tracked);

create trigger trg_products_set_updated_at
before update on public.products
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 10. Product Prices
-- Supports future retail, wholesale, promo pricing.
-- MVP can use products.selling_price first.
-- ------------------------------------------------------------

create table if not exists public.product_prices (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,

  price_type text not null default 'retail',
  currency_code text not null default 'RWF',

  unit_price numeric(14,2) not null,
  min_quantity numeric(14,3),

  valid_from date,
  valid_to date,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz,
  updated_by uuid references public.app_users(id) on delete set null,

  constraint product_prices_price_type_check
    check (price_type in (
      'retail',
      'wholesale',
      'promo',
      'custom'
    )),

  constraint product_prices_unit_price_check
    check (unit_price >= 0),

  constraint product_prices_min_quantity_check
    check (min_quantity is null or min_quantity >= 0),

  constraint product_prices_valid_dates_check
    check (
      valid_from is null
      or valid_to is null
      or valid_to >= valid_from
    )
);

create index if not exists idx_product_prices_tenant_product
on public.product_prices (tenant_id, product_id);

create index if not exists idx_product_prices_type_active
on public.product_prices (tenant_id, price_type, is_active);

create trigger trg_product_prices_set_updated_at
before update on public.product_prices
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 11. Product Barcodes
-- Supports multiple barcodes per product.
-- ------------------------------------------------------------

create table if not exists public.product_barcodes (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,

  barcode text not null,
  barcode_type text default 'internal',

  is_primary boolean not null default false,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,

  constraint product_barcodes_tenant_barcode_unique
    unique (tenant_id, barcode),

  constraint product_barcodes_type_check
    check (barcode_type in (
      'ean',
      'qr',
      'internal',
      'supplier',
      'other'
    ))
);

create index if not exists idx_product_barcodes_tenant_product
on public.product_barcodes (tenant_id, product_id);

-- ------------------------------------------------------------
-- 12. Seed Party Types
-- ------------------------------------------------------------

insert into public.party_types (
  type_code,
  type_name,
  description,
  is_active
)
values
  ('customer', 'Customer', 'A person or business that buys from the tenant.', true),
  ('supplier', 'Supplier', 'A person or business that supplies goods or services to the tenant.', true),
  ('employee', 'Employee', 'A staff member of the tenant.', true),
  ('contractor', 'Contractor', 'A contractor or service provider.', true),
  ('distributor', 'Distributor', 'A distributor or channel partner.', true),
  ('other', 'Other', 'Other party type.', true)
on conflict (type_code) do update
set
  type_name = excluded.type_name,
  description = excluded.description,
  is_active = excluded.is_active;

-- ------------------------------------------------------------
-- 13. Seed Product Types
-- ------------------------------------------------------------

insert into public.product_types (
  type_code,
  type_name,
  tracks_inventory,
  can_be_sold,
  can_be_purchased,
  description,
  is_active
)
values
  (
    'stock_item',
    'Stock Item',
    true,
    true,
    true,
    'Physical item that is stocked and sold.',
    true
  ),
  (
    'service',
    'Service',
    false,
    true,
    false,
    'Service sold to customers without stock movement.',
    true
  ),
  (
    'manufactured_item',
    'Manufactured Item',
    true,
    true,
    false,
    'Finished good produced from raw materials in future manufacturing module.',
    true
  ),
  (
    'subscription',
    'Subscription',
    false,
    true,
    false,
    'Recurring service or subscription item.',
    true
  ),
  (
    'non_stock_item',
    'Non-Stock Item',
    false,
    true,
    true,
    'Item bought or sold without stock tracking.',
    true
  )
on conflict (type_code) do update
set
  type_name = excluded.type_name,
  tracks_inventory = excluded.tracks_inventory,
  can_be_sold = excluded.can_be_sold,
  can_be_purchased = excluded.can_be_purchased,
  description = excluded.description,
  is_active = excluded.is_active;

-- ------------------------------------------------------------
-- 14. Seed Global Product Units
-- ------------------------------------------------------------

insert into public.product_units (
  tenant_id,
  unit_code,
  unit_name,
  decimal_places,
  is_active
)
values
  (null, 'pcs', 'Piece', 0, true),
  (null, 'kg', 'Kilogram', 3, true),
  (null, 'g', 'Gram', 3, true),
  (null, 'l', 'Litre', 3, true),
  (null, 'ml', 'Millilitre', 3, true),
  (null, 'm', 'Metre', 2, true),
  (null, 'box', 'Box', 0, true),
  (null, 'carton', 'Carton', 0, true),
  (null, 'hour', 'Hour', 2, true),
  (null, 'day', 'Day', 2, true)
on conflict do nothing;

-- ------------------------------------------------------------
-- 15. Enable RLS
-- ------------------------------------------------------------

alter table public.party_types enable row level security;
alter table public.parties enable row level security;
alter table public.party_type_links enable row level security;
alter table public.party_contacts enable row level security;
alter table public.party_addresses enable row level security;

alter table public.product_types enable row level security;
alter table public.product_categories enable row level security;
alter table public.product_units enable row level security;
alter table public.products enable row level security;
alter table public.product_prices enable row level security;
alter table public.product_barcodes enable row level security;

-- ------------------------------------------------------------
-- 16. RLS: Global lookup tables
-- ------------------------------------------------------------

drop policy if exists party_types_select_authenticated
on public.party_types;

create policy party_types_select_authenticated
on public.party_types
for select
using (
  auth.role() = 'authenticated'
  or public.is_platform_admin()
);

drop policy if exists party_types_manage_platform_admin
on public.party_types;

create policy party_types_manage_platform_admin
on public.party_types
for all
using (
  public.is_platform_admin()
)
with check (
  public.is_platform_admin()
);

drop policy if exists product_types_select_authenticated
on public.product_types;

create policy product_types_select_authenticated
on public.product_types
for select
using (
  auth.role() = 'authenticated'
  or public.is_platform_admin()
);

drop policy if exists product_types_manage_platform_admin
on public.product_types;

create policy product_types_manage_platform_admin
on public.product_types
for all
using (
  public.is_platform_admin()
)
with check (
  public.is_platform_admin()
);

-- Product units can be global or tenant-specific.
drop policy if exists product_units_select_global_or_tenant
on public.product_units;

create policy product_units_select_global_or_tenant
on public.product_units
for select
using (
  tenant_id is null
  or public.user_has_tenant_access(tenant_id)
);

drop policy if exists product_units_manage_tenant_or_platform
on public.product_units;

create policy product_units_manage_tenant_or_platform
on public.product_units
for all
using (
  public.is_platform_admin()
  or (
    tenant_id is not null
    and public.user_has_permission(tenant_id, 'products.edit')
  )
)
with check (
  public.is_platform_admin()
  or (
    tenant_id is not null
    and public.user_has_permission(tenant_id, 'products.edit')
  )
);

-- ------------------------------------------------------------
-- 17. RLS: Parties and related tables
-- ------------------------------------------------------------

drop policy if exists parties_select_if_permission
on public.parties;

create policy parties_select_if_permission
on public.parties
for select
using (
  public.user_has_permission(tenant_id, 'parties.view')
  or public.user_has_permission(tenant_id, 'parties.create')
  or public.user_has_permission(tenant_id, 'sales.create')
  or public.user_has_permission(tenant_id, 'payments.create')
);

drop policy if exists parties_insert_if_permission
on public.parties;

create policy parties_insert_if_permission
on public.parties
for insert
with check (
  public.user_has_permission(tenant_id, 'parties.create')
);

drop policy if exists parties_update_if_permission
on public.parties;

create policy parties_update_if_permission
on public.parties
for update
using (
  public.user_has_permission(tenant_id, 'parties.edit')
)
with check (
  public.user_has_permission(tenant_id, 'parties.edit')
);

drop policy if exists party_type_links_select_if_tenant_member
on public.party_type_links;

create policy party_type_links_select_if_tenant_member
on public.party_type_links
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists party_type_links_manage_if_parties_permission
on public.party_type_links;

create policy party_type_links_manage_if_parties_permission
on public.party_type_links
for all
using (
  public.user_has_permission(tenant_id, 'parties.create')
  or public.user_has_permission(tenant_id, 'parties.edit')
)
with check (
  public.user_has_permission(tenant_id, 'parties.create')
  or public.user_has_permission(tenant_id, 'parties.edit')
);

drop policy if exists party_contacts_select_if_tenant_member
on public.party_contacts;

create policy party_contacts_select_if_tenant_member
on public.party_contacts
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists party_contacts_manage_if_parties_permission
on public.party_contacts;

create policy party_contacts_manage_if_parties_permission
on public.party_contacts
for all
using (
  public.user_has_permission(tenant_id, 'parties.create')
  or public.user_has_permission(tenant_id, 'parties.edit')
)
with check (
  public.user_has_permission(tenant_id, 'parties.create')
  or public.user_has_permission(tenant_id, 'parties.edit')
);

drop policy if exists party_addresses_select_if_tenant_member
on public.party_addresses;

create policy party_addresses_select_if_tenant_member
on public.party_addresses
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists party_addresses_manage_if_parties_permission
on public.party_addresses;

create policy party_addresses_manage_if_parties_permission
on public.party_addresses
for all
using (
  public.user_has_permission(tenant_id, 'parties.create')
  or public.user_has_permission(tenant_id, 'parties.edit')
)
with check (
  public.user_has_permission(tenant_id, 'parties.create')
  or public.user_has_permission(tenant_id, 'parties.edit')
);

-- ------------------------------------------------------------
-- 18. RLS: Product categories, products, prices, barcodes
-- ------------------------------------------------------------

drop policy if exists product_categories_select_if_products_view
on public.product_categories;

create policy product_categories_select_if_products_view
on public.product_categories
for select
using (
  public.user_has_permission(tenant_id, 'products.view')
  or public.user_has_permission(tenant_id, 'products.create')
  or public.user_has_permission(tenant_id, 'sales.create')
);

drop policy if exists product_categories_manage_if_products_edit
on public.product_categories;

create policy product_categories_manage_if_products_edit
on public.product_categories
for all
using (
  public.user_has_permission(tenant_id, 'products.create')
  or public.user_has_permission(tenant_id, 'products.edit')
)
with check (
  public.user_has_permission(tenant_id, 'products.create')
  or public.user_has_permission(tenant_id, 'products.edit')
);

drop policy if exists products_select_if_products_or_sales_permission
on public.products;

create policy products_select_if_products_or_sales_permission
on public.products
for select
using (
  public.user_has_permission(tenant_id, 'products.view')
  or public.user_has_permission(tenant_id, 'sales.create')
  or public.user_has_permission(tenant_id, 'inventory.view')
  or public.user_has_permission(tenant_id, 'mobile.stock_check')
);

drop policy if exists products_insert_if_products_create
on public.products;

create policy products_insert_if_products_create
on public.products
for insert
with check (
  public.user_has_permission(tenant_id, 'products.create')
);

drop policy if exists products_update_if_products_edit
on public.products;

create policy products_update_if_products_edit
on public.products
for update
using (
  public.user_has_permission(tenant_id, 'products.edit')
)
with check (
  public.user_has_permission(tenant_id, 'products.edit')
);

drop policy if exists product_prices_select_if_products_view
on public.product_prices;

create policy product_prices_select_if_products_view
on public.product_prices
for select
using (
  public.user_has_permission(tenant_id, 'products.view')
  or public.user_has_permission(tenant_id, 'sales.create')
);

drop policy if exists product_prices_manage_if_products_edit
on public.product_prices;

create policy product_prices_manage_if_products_edit
on public.product_prices
for all
using (
  public.user_has_permission(tenant_id, 'products.edit')
)
with check (
  public.user_has_permission(tenant_id, 'products.edit')
);

drop policy if exists product_barcodes_select_if_products_view
on public.product_barcodes;

create policy product_barcodes_select_if_products_view
on public.product_barcodes
for select
using (
  public.user_has_permission(tenant_id, 'products.view')
  or public.user_has_permission(tenant_id, 'sales.create')
  or public.user_has_permission(tenant_id, 'mobile.stock_check')
);

drop policy if exists product_barcodes_manage_if_products_edit
on public.product_barcodes;

create policy product_barcodes_manage_if_products_edit
on public.product_barcodes
for all
using (
  public.user_has_permission(tenant_id, 'products.edit')
)
with check (
  public.user_has_permission(tenant_id, 'products.edit')
);

-- ------------------------------------------------------------
-- End of Migration 004
-- ------------------------------------------------------------