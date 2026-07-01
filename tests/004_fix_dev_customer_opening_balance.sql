-- ============================================================
-- SME-OS Dev Fix 004
-- Corrects Development Customer opening_balance (was 0, should be 100000).
--
-- Root cause: 002 originally put 100000 in customer_credit_limit by mistake.
-- Run once in Supabase SQL editor, then refresh the app dashboard.
-- ============================================================

update public.parties
set opening_balance = 100000
where party_code = 'CUST-DEV-001'
  and opening_balance = 0;
