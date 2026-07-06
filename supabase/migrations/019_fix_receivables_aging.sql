-- ============================================================
-- SME-OS Migration 019
-- Fix vw_receivables_aging to use invoice.balance_amount
--
-- Problem: outstanding was computed as total_amount minus payment
-- allocations only. That counts cash sales (and migrated paid sales)
-- as fully outstanding because they have paid_amount set on the
-- invoice but no payment_allocation rows.
--
-- Migration 010 fixed vw_customer_balances the same way; align aging.
-- ============================================================

-- CREATE OR REPLACE cannot change column types (allocated_amount was plain
-- numeric from sum(); paid_amount is numeric(14,2)). Drop and recreate.

drop view if exists public.vw_receivables_aging;

create view public.vw_receivables_aging as
select
  i.tenant_id,
  i.party_id as customer_id,
  p.party_code,
  p.party_name,
  i.id as invoice_id,
  i.invoice_number,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.paid_amount as allocated_amount,
  i.balance_amount as outstanding,
  case
    when i.due_date is null then 'no_due_date'
    when current_date <= i.due_date then 'current'
    when current_date <= i.due_date + interval '30 day' then '1_30'
    when current_date <= i.due_date + interval '60 day' then '31_60'
    when current_date <= i.due_date + interval '90 day' then '61_90'
    else 'over_90'
  end as aging_bucket
from public.invoices i
join public.parties p
  on p.id = i.party_id
 and p.tenant_id = i.tenant_id
where i.status = 'posted'
  and i.voided_at is null
  and i.party_id is not null
  and i.balance_amount > 0;

alter view if exists public.vw_receivables_aging set (security_invoker = true);
