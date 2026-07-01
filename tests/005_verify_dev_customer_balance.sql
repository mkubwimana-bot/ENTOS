-- ============================================================
-- Diagnostic: Development Customer balance breakdown
-- Run in Supabase SQL Editor after recording payments.
-- ============================================================

select
  'PARTY' as section,
  p.party_code,
  p.party_name,
  p.opening_balance,
  null::numeric as invoice_total,
  null::numeric as invoice_balance,
  null::numeric as allocated,
  null::numeric as computed_balance
from public.parties p
where p.party_code = 'CUST-DEV-001'

union all

select
  'INVOICE' as section,
  p.party_code,
  i.invoice_number,
  null::numeric,
  i.total_amount,
  i.balance_amount,
  i.paid_amount,
  null::numeric
from public.invoices i
join public.parties p on p.id = i.party_id
where p.party_code = 'CUST-DEV-001'
  and i.status = 'posted'
  and i.voided_at is null
order by section, party_name;

select
  party_code,
  party_name,
  opening_balance,
  total_invoiced,
  total_paid,
  balance
from public.vw_customer_balances
where party_code = 'CUST-DEV-001';
