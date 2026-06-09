-- ============================================================
-- SME-OS Migration 003
-- Subscriptions and Localization
--
-- Creates:
--   - subscription_plans
--   - subscriptions
--   - billing_events
--   - languages
--   - translations
--   - tenant_language_settings
--
-- No-Docker workflow:
-- Save this file in Cursor, then copy and run it in Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Subscription Plans
-- Defines commercial plans available to tenants.
-- ------------------------------------------------------------

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),

  plan_code text not null,
  plan_name text not null,

  monthly_price numeric(14,2) not null default 0,
  currency_code text not null default 'RWF',

  max_users integer,
  max_branches integer,
  max_products integer,

  features jsonb,

  is_public boolean not null default true,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint subscription_plans_plan_code_unique
    unique (plan_code),

  constraint subscription_plans_monthly_price_check
    check (monthly_price >= 0),

  constraint subscription_plans_currency_code_check
    check (currency_code in ('RWF', 'USD'))
);

create index if not exists idx_subscription_plans_active_public
on public.subscription_plans (is_active, is_public);

create trigger trg_subscription_plans_set_updated_at
before update on public.subscription_plans
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 2. Subscriptions
-- Stores each tenant's subscription, trial, and billing status.
-- ------------------------------------------------------------

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id) on delete restrict,

  status text not null default 'trialing',

  trial_start_date date,
  trial_end_date date,

  current_period_start date,
  current_period_end date,

  billing_cycle text not null default 'monthly',
  payment_method_preference text,

  cancelled_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint subscriptions_tenant_unique
    unique (tenant_id),

  constraint subscriptions_status_check
    check (status in (
      'trialing',
      'active',
      'past_due',
      'suspended',
      'cancelled'
    )),

  constraint subscriptions_billing_cycle_check
    check (billing_cycle in (
      'monthly',
      'quarterly',
      'annual'
    )),

  constraint subscriptions_payment_method_check
    check (
      payment_method_preference is null
      or payment_method_preference in (
        'momo',
        'airtel',
        'bank',
        'card',
        'manual'
      )
    )
);

create index if not exists idx_subscriptions_tenant_status
on public.subscriptions (tenant_id, status);

create index if not exists idx_subscriptions_trial_end_date
on public.subscriptions (trial_end_date);

create index if not exists idx_subscriptions_current_period_end
on public.subscriptions (current_period_end);

create trigger trg_subscriptions_set_updated_at
before update on public.subscriptions
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3. Billing Events
-- Logs invoices, payments, failed payments, renewals,
-- reminders, manual adjustments, and future provider events.
-- ------------------------------------------------------------

create table if not exists public.billing_events (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  subscription_id uuid references public.subscriptions(id) on delete set null,

  event_type text not null,
  amount numeric(14,2),
  currency_code text default 'RWF',

  provider text,
  provider_reference text,

  event_status text not null default 'pending',
  event_payload jsonb,

  notes text,

  created_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,

  constraint billing_events_event_type_check
    check (event_type in (
      'invoice_created',
      'payment_received',
      'payment_failed',
      'payment_reversed',
      'reminder_sent',
      'subscription_started',
      'subscription_renewed',
      'subscription_cancelled',
      'manual_adjustment'
    )),

  constraint billing_events_event_status_check
    check (event_status in (
      'pending',
      'successful',
      'failed',
      'reversed',
      'cancelled'
    )),

  constraint billing_events_provider_check
    check (
      provider is null
      or provider in (
        'manual',
        'momo',
        'airtel',
        'bank',
        'card',
        'other'
      )
    ),

  constraint billing_events_amount_check
    check (amount is null or amount >= 0)
);

create index if not exists idx_billing_events_tenant_created_at
on public.billing_events (tenant_id, created_at);

create index if not exists idx_billing_events_subscription_id
on public.billing_events (subscription_id);

create index if not exists idx_billing_events_provider_reference
on public.billing_events (provider, provider_reference);

-- ------------------------------------------------------------
-- 4. Languages
-- Defines platform-supported languages.
-- ------------------------------------------------------------

create table if not exists public.languages (
  code text primary key,

  language_name text not null,
  native_name text,

  is_active boolean not null default true,
  is_default boolean not null default false,

  display_order integer,

  created_at timestamptz not null default now(),

  constraint languages_code_check
    check (code in ('en', 'fr', 'rw', 'sw'))
);

create unique index if not exists idx_languages_one_default
on public.languages (is_default)
where is_default = true;

-- ------------------------------------------------------------
-- 5. Translations
-- Stores UI translation strings by stable key.
--
-- Important:
-- Do not hardcode labels in the app if you want multilingual
-- support later. Use keys such as menu.sales or button.save.
-- ------------------------------------------------------------

create table if not exists public.translations (
  id uuid primary key default gen_random_uuid(),

  translation_key text not null,
  language_code text not null references public.languages(code) on delete cascade,

  translation_text text not null,

  context text,
  module_code text,

  is_approved boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint translations_key_language_unique
    unique (translation_key, language_code),

  constraint translations_key_not_blank
    check (length(trim(translation_key)) > 0)
);

create index if not exists idx_translations_language_code
on public.translations (language_code);

create index if not exists idx_translations_module_code
on public.translations (module_code);

create trigger trg_translations_set_updated_at
before update on public.translations
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 6. Tenant Language Settings
-- Stores language preferences per tenant.
-- ------------------------------------------------------------

create table if not exists public.tenant_language_settings (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,

  default_language_code text not null references public.languages(code) on delete restrict,

  enabled_languages text[],

  created_at timestamptz not null default now(),
  updated_at timestamptz,

  constraint tenant_language_settings_tenant_unique
    unique (tenant_id)
);

create index if not exists idx_tenant_language_settings_tenant_id
on public.tenant_language_settings (tenant_id);

create trigger trg_tenant_language_settings_set_updated_at
before update on public.tenant_language_settings
for each row
execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 7. Seed Languages
-- ------------------------------------------------------------

insert into public.languages (
  code,
  language_name,
  native_name,
  is_active,
  is_default,
  display_order
)
values
  ('en', 'English', 'English', true, true, 1),
  ('fr', 'French', 'Français', true, false, 2),
  ('rw', 'Kinyarwanda', 'Ikinyarwanda', true, false, 3),
  ('sw', 'Swahili', 'Kiswahili', false, false, 4)
on conflict (code) do update
set
  language_name = excluded.language_name,
  native_name = excluded.native_name,
  is_active = excluded.is_active,
  is_default = excluded.is_default,
  display_order = excluded.display_order;

-- ------------------------------------------------------------
-- 8. Seed Subscription Plans
-- ------------------------------------------------------------

insert into public.subscription_plans (
  plan_code,
  plan_name,
  monthly_price,
  currency_code,
  max_users,
  max_branches,
  max_products,
  features,
  is_public,
  is_active
)
values
  (
    'starter',
    'Starter',
    10000,
    'RWF',
    1,
    1,
    500,
    '{
      "sales": true,
      "inventory": true,
      "customers": true,
      "basic_reports": true,
      "mobile_transactions": true,
      "offline_drafts": true,
      "advanced_reports": false,
      "multi_branch": false,
      "credit_readiness": false
    }'::jsonb,
    true,
    true
  ),
  (
    'business',
    'Business',
    25000,
    'RWF',
    5,
    2,
    3000,
    '{
      "sales": true,
      "inventory": true,
      "customers": true,
      "basic_reports": true,
      "mobile_transactions": true,
      "offline_drafts": true,
      "advanced_reports": true,
      "multi_branch": true,
      "credit_readiness": false
    }'::jsonb,
    true,
    true
  ),
  (
    'premium',
    'Premium',
    50000,
    'RWF',
    null,
    null,
    null,
    '{
      "sales": true,
      "inventory": true,
      "customers": true,
      "basic_reports": true,
      "mobile_transactions": true,
      "offline_drafts": true,
      "advanced_reports": true,
      "multi_branch": true,
      "credit_readiness": true
    }'::jsonb,
    true,
    true
  )
on conflict (plan_code) do update
set
  plan_name = excluded.plan_name,
  monthly_price = excluded.monthly_price,
  currency_code = excluded.currency_code,
  max_users = excluded.max_users,
  max_branches = excluded.max_branches,
  max_products = excluded.max_products,
  features = excluded.features,
  is_public = excluded.is_public,
  is_active = excluded.is_active;

-- ------------------------------------------------------------
-- 9. Seed Initial English Translation Keys
-- These are enough to start designing the UI.
-- More translations can be added gradually.
-- ------------------------------------------------------------

insert into public.translations (
  translation_key,
  language_code,
  translation_text,
  context,
  module_code,
  is_approved
)
values
  ('app.name', 'en', 'SME-OS', 'Application name', 'global', true),

  ('menu.dashboard', 'en', 'Dashboard', 'Main navigation', 'navigation', true),
  ('menu.sales', 'en', 'Sales', 'Main navigation', 'navigation', true),
  ('menu.customers', 'en', 'Customers', 'Main navigation', 'navigation', true),
  ('menu.products', 'en', 'Products', 'Main navigation', 'navigation', true),
  ('menu.stock', 'en', 'Stock', 'Main navigation', 'navigation', true),
  ('menu.reports', 'en', 'Reports', 'Main navigation', 'navigation', true),
  ('menu.settings', 'en', 'Settings', 'Main navigation', 'navigation', true),

  ('button.save', 'en', 'Save', 'Button', 'global', true),
  ('button.cancel', 'en', 'Cancel', 'Button', 'global', true),
  ('button.delete', 'en', 'Delete', 'Button', 'global', true),
  ('button.edit', 'en', 'Edit', 'Button', 'global', true),
  ('button.new_sale', 'en', 'New Sale', 'Button', 'sales', true),
  ('button.record_payment', 'en', 'Record Payment', 'Button', 'payments', true),
  ('button.sync_now', 'en', 'Sync Now', 'Button', 'mobile', true),

  ('label.customer', 'en', 'Customer', 'Form label', 'parties', true),
  ('label.product', 'en', 'Product', 'Form label', 'products', true),
  ('label.quantity', 'en', 'Quantity', 'Form label', 'sales', true),
  ('label.price', 'en', 'Price', 'Form label', 'sales', true),
  ('label.total', 'en', 'Total', 'Form label', 'sales', true),
  ('label.amount_paid', 'en', 'Amount Paid', 'Form label', 'payments', true),
  ('label.balance', 'en', 'Balance', 'Form label', 'sales', true),

  ('status.pending_sync', 'en', 'Pending Sync', 'Offline status', 'mobile', true),
  ('status.synced', 'en', 'Synced', 'Offline status', 'mobile', true),
  ('status.failed', 'en', 'Failed', 'Offline status', 'mobile', true),
  ('status.conflict', 'en', 'Needs Review', 'Offline status', 'mobile', true),

  ('dashboard.today_sales', 'en', 'Today''s Sales', 'Dashboard card', 'dashboard', true),
  ('dashboard.money_owed', 'en', 'Money Owed', 'Dashboard card', 'dashboard', true),
  ('dashboard.low_stock', 'en', 'Low Stock', 'Dashboard card', 'dashboard', true),
  ('dashboard.pending_sync', 'en', 'Pending Mobile Transactions', 'Dashboard card', 'dashboard', true)
on conflict (translation_key, language_code) do update
set
  translation_text = excluded.translation_text,
  context = excluded.context,
  module_code = excluded.module_code,
  is_approved = excluded.is_approved;

-- ------------------------------------------------------------
-- 10. Enable Row-Level Security
-- ------------------------------------------------------------

alter table public.subscription_plans enable row level security;
alter table public.subscriptions enable row level security;
alter table public.billing_events enable row level security;
alter table public.languages enable row level security;
alter table public.translations enable row level security;
alter table public.tenant_language_settings enable row level security;

-- ------------------------------------------------------------
-- 11. RLS Policies: subscription_plans
-- Public active plans can be read by authenticated users.
-- Platform admin can manage plans.
-- ------------------------------------------------------------

drop policy if exists subscription_plans_select_active_public
on public.subscription_plans;

create policy subscription_plans_select_active_public
on public.subscription_plans
for select
using (
  is_active = true
  and is_public = true
);

drop policy if exists subscription_plans_manage_platform_admin
on public.subscription_plans;

create policy subscription_plans_manage_platform_admin
on public.subscription_plans
for all
using (
  public.is_platform_admin()
)
with check (
  public.is_platform_admin()
);

-- ------------------------------------------------------------
-- 12. RLS Policies: subscriptions
-- Tenant members can read their subscription.
-- Only platform admin or users with settings.edit can update.
-- ------------------------------------------------------------

drop policy if exists subscriptions_select_if_tenant_member
on public.subscriptions;

create policy subscriptions_select_if_tenant_member
on public.subscriptions
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists subscriptions_manage_platform_or_owner
on public.subscriptions;

create policy subscriptions_manage_platform_or_owner
on public.subscriptions
for all
using (
  public.is_platform_admin()
  or public.user_has_permission(tenant_id, 'settings.edit')
)
with check (
  public.is_platform_admin()
  or public.user_has_permission(tenant_id, 'settings.edit')
);

-- ------------------------------------------------------------
-- 13. RLS Policies: billing_events
-- Tenant owner/settings users can read billing events.
-- Platform admin can manage all.
-- ------------------------------------------------------------

drop policy if exists billing_events_select_if_settings_view
on public.billing_events;

create policy billing_events_select_if_settings_view
on public.billing_events
for select
using (
  public.is_platform_admin()
  or public.user_has_permission(tenant_id, 'settings.view')
  or public.user_has_permission(tenant_id, 'settings.edit')
);

drop policy if exists billing_events_manage_platform_admin
on public.billing_events;

create policy billing_events_manage_platform_admin
on public.billing_events
for all
using (
  public.is_platform_admin()
)
with check (
  public.is_platform_admin()
);

-- ------------------------------------------------------------
-- 14. RLS Policies: languages
-- Languages are safe for all authenticated users to read.
-- ------------------------------------------------------------

drop policy if exists languages_select_authenticated
on public.languages;

create policy languages_select_authenticated
on public.languages
for select
using (
  auth.role() = 'authenticated'
  or public.is_platform_admin()
);

drop policy if exists languages_manage_platform_admin
on public.languages;

create policy languages_manage_platform_admin
on public.languages
for all
using (
  public.is_platform_admin()
)
with check (
  public.is_platform_admin()
);

-- ------------------------------------------------------------
-- 15. RLS Policies: translations
-- Translations are safe for authenticated users to read.
-- Only platform admin should manage them in MVP.
-- ------------------------------------------------------------

drop policy if exists translations_select_authenticated
on public.translations;

create policy translations_select_authenticated
on public.translations
for select
using (
  auth.role() = 'authenticated'
  or public.is_platform_admin()
);

drop policy if exists translations_manage_platform_admin
on public.translations;

create policy translations_manage_platform_admin
on public.translations
for all
using (
  public.is_platform_admin()
)
with check (
  public.is_platform_admin()
);

-- ------------------------------------------------------------
-- 16. RLS Policies: tenant_language_settings
-- ------------------------------------------------------------

drop policy if exists tenant_language_settings_select_if_tenant_member
on public.tenant_language_settings;

create policy tenant_language_settings_select_if_tenant_member
on public.tenant_language_settings
for select
using (
  public.user_has_tenant_access(tenant_id)
);

drop policy if exists tenant_language_settings_manage_if_settings_edit
on public.tenant_language_settings;

create policy tenant_language_settings_manage_if_settings_edit
on public.tenant_language_settings
for all
using (
  public.user_has_permission(tenant_id, 'settings.edit')
)
with check (
  public.user_has_permission(tenant_id, 'settings.edit')
);

-- ------------------------------------------------------------
-- End of Migration 003
-- ------------------------------------------------------------