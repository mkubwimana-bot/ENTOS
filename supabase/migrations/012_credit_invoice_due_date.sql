-- ============================================================
-- SME-OS Migration 012
-- Set due_date on credit invoices posted via post_sale_draft.
-- ============================================================

create or replace function public.post_sale_draft(
  target_tenant_id uuid,
  target_branch_id uuid,
  target_warehouse_id uuid,
  p_client_reference_id text,
  p_sale_type text,
  p_party_id uuid,
  p_notes text,
  p_captured_at timestamptz,
  p_lines jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_draft_id uuid;
  v_draft_status text;
  v_posted_id uuid;
  v_document_number text;
  v_invoice_id uuid;
  v_line jsonb;
  v_line_number integer := 0;
  v_product_id uuid;
  v_quantity numeric(14,3);
  v_unit_price numeric(14,2);
  v_line_total numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_product_name text;
  v_base_unit_id uuid;
  v_cost_price numeric(18,4);
  v_is_tracked boolean;
  v_product_status text;
  v_credit_terms_days integer;
  v_due_date date;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated.';
  end if;

  if not (
    public.user_has_permission(target_tenant_id, 'mobile.quick_sale')
    or public.user_has_permission(target_tenant_id, 'offline.use')
  ) then
    raise exception 'You do not have permission to post mobile sales.';
  end if;

  if p_sale_type not in ('cash', 'credit') then
    raise exception 'Invalid sale type: %', p_sale_type;
  end if;

  if p_sale_type = 'credit' and p_party_id is null then
    raise exception 'Credit sales require a customer.';
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'Sale must have at least one line.';
  end if;

  select id, status, posted_document_id
  into v_draft_id, v_draft_status, v_posted_id
  from public.transaction_drafts
  where tenant_id = target_tenant_id
    and client_reference_id = p_client_reference_id;

  if v_draft_id is not null
     and v_draft_status = 'synced'
     and v_posted_id is not null then
    select invoice_number
    into v_document_number
    from public.invoices
    where id = v_posted_id;

    if v_document_number is not null then
      return v_document_number;
    end if;
  end if;

  if v_draft_id is null then
    insert into public.transaction_drafts (
      tenant_id,
      branch_id,
      warehouse_id,
      user_id,
      draft_type,
      client_reference_id,
      payload,
      status,
      source,
      created_offline_at,
      received_at
    ) values (
      target_tenant_id,
      target_branch_id,
      target_warehouse_id,
      v_user_id,
      'sale',
      p_client_reference_id,
      jsonb_build_object(
        'sale_type', p_sale_type,
        'party_id', p_party_id,
        'notes', p_notes,
        'captured_at', p_captured_at,
        'lines', p_lines
      ),
      'pending_sync',
      'offline',
      p_captured_at,
      now()
    )
    returning id into v_draft_id;
  end if;

  v_due_date := null;
  if p_sale_type = 'credit' then
    select coalesce(customer_credit_terms_days, 30)
    into v_credit_terms_days
    from public.parties
    where id = p_party_id
      and tenant_id = target_tenant_id;

    if v_credit_terms_days is null then
      v_credit_terms_days := 30;
    end if;

    v_due_date := current_date + v_credit_terms_days;
  end if;

  v_document_number := public.get_next_document_number(
    target_tenant_id,
    target_branch_id,
    'invoice'
  );

  insert into public.invoices (
    tenant_id,
    branch_id,
    warehouse_id,
    invoice_number,
    invoice_date,
    due_date,
    party_id,
    sale_type,
    status,
    subtotal_amount,
    discount_amount,
    tax_amount,
    total_amount,
    paid_amount,
    balance_amount,
    notes,
    created_by,
    posted_at
  ) values (
    target_tenant_id,
    target_branch_id,
    target_warehouse_id,
    v_document_number,
    current_date,
    v_due_date,
    p_party_id,
    p_sale_type,
    'posted',
    0,
    0,
    0,
    0,
    0,
    0,
    nullif(p_notes, ''),
    v_user_id,
    now()
  )
  returning id into v_invoice_id;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_line_number := v_line_number + 1;
    v_product_id := (v_line ->> 'product_id')::uuid;
    v_quantity := (v_line ->> 'quantity')::numeric;
    v_unit_price := (v_line ->> 'unit_price')::numeric;

    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Line quantity must be greater than zero.';
    end if;
    if v_unit_price is null or v_unit_price < 0 then
      raise exception 'Line unit price must be zero or greater.';
    end if;

    select product_name, base_unit_id, cost_price, is_inventory_tracked, status
    into v_product_name, v_base_unit_id, v_cost_price, v_is_tracked, v_product_status
    from public.products
    where id = v_product_id
      and tenant_id = target_tenant_id;

    if v_product_name is null then
      raise exception 'Product not found: %', v_product_id;
    end if;
    if v_product_status <> 'active' then
      raise exception 'Product % is not active.', v_product_name;
    end if;

    v_line_total := v_quantity * v_unit_price;
    v_subtotal := v_subtotal + v_line_total;

    insert into public.invoice_lines (
      tenant_id,
      invoice_id,
      line_number,
      product_id,
      description,
      quantity,
      unit_id,
      unit_price,
      discount_amount,
      tax_amount,
      line_total,
      cost_price_snapshot,
      warehouse_id,
      created_by
    ) values (
      target_tenant_id,
      v_invoice_id,
      v_line_number,
      v_product_id,
      v_product_name,
      v_quantity,
      v_base_unit_id,
      v_unit_price,
      0,
      0,
      v_line_total,
      v_cost_price,
      target_warehouse_id,
      v_user_id
    );

    if v_is_tracked then
      insert into public.stock_movements (
        tenant_id,
        branch_id,
        warehouse_id,
        product_id,
        movement_date,
        movement_type,
        quantity_in,
        quantity_out,
        unit_cost,
        total_cost,
        source_table,
        source_id,
        reference_number,
        reason,
        created_by
      ) values (
        target_tenant_id,
        target_branch_id,
        target_warehouse_id,
        v_product_id,
        current_date,
        'sale',
        0,
        v_quantity,
        v_cost_price,
        case when v_cost_price is null then null else v_cost_price * v_quantity end,
        'invoices',
        v_invoice_id,
        v_document_number,
        'Quick sale invoice',
        v_user_id
      );
    end if;
  end loop;

  update public.invoices
  set
    subtotal_amount = v_subtotal,
    total_amount = v_subtotal,
    paid_amount = case when p_sale_type = 'credit' then 0 else v_subtotal end,
    balance_amount = case when p_sale_type = 'credit' then v_subtotal else 0 end,
    updated_at = now()
  where id = v_invoice_id;

  update public.transaction_drafts
  set
    status = 'synced',
    provisional_number = v_document_number,
    posted_document_id = v_invoice_id,
    posted_document_table = 'invoices',
    error_message = null,
    received_at = now(),
    updated_at = now()
  where id = v_draft_id;

  return v_document_number;
end;
$$;

grant execute on function public.post_sale_draft(
  uuid, uuid, uuid, text, text, uuid, text, timestamptz, jsonb
) to authenticated;
