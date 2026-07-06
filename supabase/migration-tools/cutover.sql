-- ============================================================
-- Cutover: reset live document sequences after MIG-* import
-- Replace e9aefc3f-cc08-4bfe-9b42-c354c62388c5 and 85933064-4bbd-482d-bc3b-445b7da2f55e before running.
-- Run AFTER validate_import.sql passes.
-- ============================================================

begin;

-- Invoice sequence → next live number after migrated docs
update public.number_sequences ns
set current_value = greatest(
  ns.current_value,
  coalesce((
    select max(
      nullif(
        regexp_replace(i.invoice_number, '^MIG-INV-', ''),
        ''
      )::integer
    )
    from public.invoices i
    where i.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
      and i.invoice_number ~ '^MIG-INV-[0-9]+$'
  ), 0)
)
where ns.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and ns.branch_id = '85933064-4bbd-482d-bc3b-445b7da2f55e'::uuid
  and ns.sequence_code = 'invoice';

-- Purchase sequence
update public.number_sequences ns
set current_value = greatest(
  ns.current_value,
  coalesce((
    select max(
      nullif(
        regexp_replace(p.purchase_number, '^MIG-PUR-', ''),
        ''
      )::integer
    )
    from public.purchases p
    where p.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
      and p.purchase_number ~ '^MIG-PUR-[0-9]+$'
  ), 0)
)
where ns.tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and ns.branch_id = '85933064-4bbd-482d-bc3b-445b7da2f55e'::uuid
  and ns.sequence_code = 'purchase';

-- Optional: verify next numbers (informational)
select
  sequence_code,
  prefix,
  current_value,
  padding_length
from public.number_sequences
where tenant_id = 'e9aefc3f-cc08-4bfe-9b42-c354c62388c5'::uuid
  and branch_id = '85933064-4bbd-482d-bc3b-445b7da2f55e'::uuid
  and sequence_code in ('invoice', 'purchase');

commit;

-- Post-cutover checklist:
-- 1. New Sale creates INV-* (not MIG-INV-*)
-- 2. New Purchase creates PUR-* (not MIG-PUR-*)
-- 3. Reports → Daily sales shows historical + new activity
-- 4. Aging tab matches unpaid credit customers
-- 5. Freeze old Entos app
