-- ============================================================
-- SME-OS Migration 020
-- Cash sales: allow void/delete; support in-place correction
--
-- void_invoice blocked all paid_amount > 0 sales, including cash
-- sales settled at sale time (no payment_allocation rows).
--
-- update_cash_invoice lets users fix mistaken cash sales on device.
-- ============================================================

create or replace function public.void_invoice(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_user_id uuid;
  v_has_allocations boolean;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated.';
  end if;

  select i.tenant_id
  into v_tenant_id
  from public.invoices i
  where i.id = p_invoice_id
    and i.status = 'posted'
    and i.voided_at is null;

  if v_tenant_id is null then
    raise exception 'Sale not found or already voided.';
  end if;

  if not public.user_has_permission(v_tenant_id, 'sales.void') then
    raise exception 'You do not have permission to delete sales.';
  end if;

  select exists (
    select 1
    from public.payment_allocations pa
    join public.payments pay
      on pay.id = pa.payment_id
     and pay.tenant_id = pa.tenant_id
    where pa.invoice_id = p_invoice_id
      and pay.status = 'posted'
      and pay.voided_at is null
  )
  into v_has_allocations;

  if v_has_allocations then
    raise exception 'Cannot delete a sale that has payments applied. Void the payments first.';
  end if;

  update public.invoices
  set
    status = 'voided',
    voided_at = now(),
    voided_by = v_user_id,
    updated_at = now()
  where id = p_invoice_id;

  update public.stock_movements
  set
    voided_at = now(),
    voided_by = v_user_id
  where source_table = 'invoices'
    and source_id = p_invoice_id
    and voided_at is null;
end;
$$;

create or replace function public.update_cash_invoice(
  p_invoice_id uuid,
  p_lines jsonb,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_tenant_id uuid;
  v_branch_id uuid;
  v_warehouse_id uuid;
  v_invoice_number text;
  v_sale_type text;
  v_has_allocations boolean;
  v_line jsonb;
  v_line_number integer := 0;
  v_product_id uuid;
  v_quantity numeric(14,3);
  v_unit_price numeric(14,2);
  v_line_total numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_product_name text;
  v_base_unit_id uuid;
  v_cost_price numeric(14,4);
  v_is_tracked boolean;
  v_product_status text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated.';
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one line item.';
  end if;

  select
    i.tenant_id,
    i.branch_id,
    i.warehouse_id,
    i.invoice_number,
    i.sale_type
  into
    v_tenant_id,
    v_branch_id,
    v_warehouse_id,
    v_invoice_number,
    v_sale_type
  from public.invoices i
  where i.id = p_invoice_id
    and i.status = 'posted'
    and i.voided_at is null;

  if v_tenant_id is null then
    raise exception 'Sale not found or already voided.';
  end if;

  if v_sale_type <> 'cash' then
    raise exception 'Only cash sales can be edited. Delete credit sales after voiding payments.';
  end if;

  if not public.user_has_permission(v_tenant_id, 'sales.void') then
    raise exception 'You do not have permission to edit sales.';
  end if;

  select exists (
    select 1
    from public.payment_allocations pa
    join public.payments pay
      on pay.id = pa.payment_id
     and pay.tenant_id = pa.tenant_id
    where pa.invoice_id = p_invoice_id
      and pay.status = 'posted'
      and pay.voided_at is null
  )
  into v_has_allocations;

  if v_has_allocations then
    raise exception 'Cannot edit a sale that has clearing-debt payments applied. Void the payments first.';
  end if;

  update public.stock_movements
  set
    voided_at = now(),
    voided_by = v_user_id
  where source_table = 'invoices'
    and source_id = p_invoice_id
    and voided_at is null;

  delete from public.invoice_lines
  where invoice_id = p_invoice_id
    and tenant_id = v_tenant_id;

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
      and tenant_id = v_tenant_id;

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
      v_tenant_id,
      p_invoice_id,
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
      v_warehouse_id,
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
        v_tenant_id,
        v_branch_id,
        v_warehouse_id,
        v_product_id,
        current_date,
        'sale',
        0,
        v_quantity,
        v_cost_price,
        case when v_cost_price is null then null else v_cost_price * v_quantity end,
        'invoices',
        p_invoice_id,
        v_invoice_number,
        'Cash sale correction',
        v_user_id
      );
    end if;
  end loop;

  update public.invoices
  set
    subtotal_amount = v_subtotal,
    total_amount = v_subtotal,
    paid_amount = v_subtotal,
    balance_amount = 0,
    notes = nullif(trim(p_notes), ''),
    updated_at = now(),
    updated_by = v_user_id
  where id = p_invoice_id;
end;
$$;

grant execute on function public.update_cash_invoice(uuid, jsonb, text) to authenticated;
