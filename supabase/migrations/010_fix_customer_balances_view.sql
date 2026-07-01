-- ============================================================
-- SME-OS Migration 010
-- Fix vw_customer_balances to use outstanding invoice balances
--
-- Problem: the old formula used sum(invoice total_amount) minus
-- payment allocations. That ignored cash sales already settled at
-- sale time and could miscount when joins fanned out.
--
-- Correct MVP formula:
--   balance = opening_balance + sum(posted invoice balance_amount)
--
-- invoice.balance_amount is maintained by the payment_allocations
-- trigger (recalculate_invoice_payment_totals).
-- ============================================================

create or replace view public.vw_customer_balances as
select
  p.tenant_id,
  p.id as party_id,
  p.party_code,
  p.party_name,
  p.opening_balance,
  coalesce((
    select sum(i.total_amount)
    from public.invoices i
    where i.tenant_id = p.tenant_id
      and i.party_id = p.id
      and i.status = 'posted'
      and i.voided_at is null
  ), 0) as total_invoiced,
  coalesce((
    select sum(pa.allocated_amount)
    from public.payment_allocations pa
    join public.payments pay
      on pay.id = pa.payment_id
     and pay.tenant_id = pa.tenant_id
    join public.invoices i
      on i.id = pa.invoice_id
     and i.tenant_id = pa.tenant_id
    where i.tenant_id = p.tenant_id
      and i.party_id = p.id
      and pay.status = 'posted'
      and pay.voided_at is null
  ), 0) as total_paid,
  p.opening_balance
    + coalesce((
        select sum(i.balance_amount)
        from public.invoices i
        where i.tenant_id = p.tenant_id
          and i.party_id = p.id
          and i.status = 'posted'
          and i.voided_at is null
      ), 0) as balance
from public.parties p
where p.deleted_at is null;

-- Repair cached invoice balances from existing payment allocations.
do $$
declare
  v_invoice_id uuid;
begin
  for v_invoice_id in
    select i.id
    from public.invoices i
    where i.status = 'posted'
      and i.voided_at is null
  loop
    perform public.recalculate_invoice_payment_totals(v_invoice_id);
  end loop;
end;
$$;
