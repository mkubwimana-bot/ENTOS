-- Auto-generate party codes: CUST001 for customers, SUP001 for suppliers.

create or replace function public.generate_party_code(
  target_tenant_id uuid,
  party_kind text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text;
  v_next integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated.';
  end if;

  if party_kind not in ('customer', 'supplier') then
    raise exception 'party_kind must be customer or supplier.';
  end if;

  v_prefix := case party_kind when 'customer' then 'CUST' else 'SUP' end;

  select coalesce(
    max(
      nullif(
        substring(p.party_code from 5 for 3),
        ''
      )::integer
    ),
    0
  ) + 1
  into v_next
  from public.parties p
  where p.tenant_id = target_tenant_id
    and upper(p.party_code) ~ ('^' || v_prefix || '[0-9]{3}$');

  return v_prefix || lpad(v_next::text, 3, '0');
end;
$$;
