-- ============================================================
-- SME-OS Migration 022
-- post_purchase: verify caller belongs to target tenant
-- ============================================================

create or replace function public.post_purchase(
  target_tenant_id uuid,
  target_branch_id uuid,
  target_warehouse_id uuid,
  p_lines jsonb,
  p_party_id uuid default null,
  p_notes text default null,
  p_purchase_date date default current_date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_document_number text;
  v_purchase_id uuid;
  v_line jsonb;
  v_line_number integer := 0;
  v_product_id uuid;
  v_quantity numeric(14,3);
  v_unit_cost numeric(14,2);
  v_line_total numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_product_name text;
  v_base_unit_id uuid;
  v_is_tracked boolean;
  v_product_status text;
  v_line_id uuid;
  v_old_qty numeric(14,3);
  v_old_cost numeric(18,4);
  v_new_cost numeric(18,4);
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated.';
  end if;

  if not public.user_has_tenant_access(target_tenant_id) then
    raise exception 'You do not belong to this tenant.';
  end if;

  if not public.user_has_permission(target_tenant_id, 'purchases.create') then
    raise exception 'You do not have permission to create purchases.';
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'Purchase must have at least one line.';
  end if;

  if p_purchase_date > current_date then
    raise exception 'Purchase date cannot be in the future.';
  end if;

  if p_party_id is not null then
    if not exists (
      select 1
      from public.parties p
      where p.id = p_party_id
        and p.tenant_id = target_tenant_id
        and p.deleted_at is null
    ) then
      raise exception 'Supplier not found for this tenant.';
    end if;
  end if;

  perform public.ensure_purchase_number_sequence(
    target_tenant_id,
    target_branch_id
  );

  v_document_number := public.get_next_document_number(
    target_tenant_id,
    target_branch_id,
    'purchase'
  );

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line ->> 'product_id')::uuid;
    v_quantity := (v_line ->> 'quantity')::numeric(14,3);
    v_unit_cost := (v_line ->> 'unit_cost')::numeric(14,2);

    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Each line must have quantity greater than zero.';
    end if;

    if v_unit_cost is null or v_unit_cost < 0 then
      raise exception 'Each line must have a valid unit cost.';
    end if;

    select
      product_name,
      base_unit_id,
      is_inventory_tracked,
      status
    into
      v_product_name,
      v_base_unit_id,
      v_is_tracked,
      v_product_status
    from public.products
    where id = v_product_id
      and tenant_id = target_tenant_id;

    if v_product_name is null then
      raise exception
        'Product not found for this business. Sign out and back in, or ask support to remove the extra empty company on your account.';
    end if;

    if v_product_status <> 'active' then
      raise exception 'Product % is not active.', v_product_name;
    end if;

    v_line_total := round(v_quantity * v_unit_cost, 2);
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  insert into public.purchases (
    tenant_id,
    branch_id,
    warehouse_id,
    purchase_number,
    purchase_date,
    party_id,
    status,
    subtotal_amount,
    discount_amount,
    tax_amount,
    total_amount,
    notes,
    created_by,
    posted_at
  )
  values (
    target_tenant_id,
    target_branch_id,
    target_warehouse_id,
    v_document_number,
    p_purchase_date,
    p_party_id,
    'posted',
    v_subtotal,
    0,
    0,
    v_subtotal,
    nullif(p_notes, ''),
    v_user_id,
    now()
  )
  returning id into v_purchase_id;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_line_number := v_line_number + 1;
    v_product_id := (v_line ->> 'product_id')::uuid;
    v_quantity := (v_line ->> 'quantity')::numeric(14,3);
    v_unit_cost := (v_line ->> 'unit_cost')::numeric(14,2);
    v_line_total := round(v_quantity * v_unit_cost, 2);

    select product_name, base_unit_id, is_inventory_tracked
    into v_product_name, v_base_unit_id, v_is_tracked
    from public.products
    where id = v_product_id;

    insert into public.purchase_lines (
      tenant_id,
      purchase_id,
      line_number,
      product_id,
      description,
      quantity,
      unit_id,
      unit_cost,
      discount_amount,
      tax_amount,
      line_total,
      warehouse_id,
      created_by
    )
    values (
      target_tenant_id,
      v_purchase_id,
      v_line_number,
      v_product_id,
      v_product_name,
      v_quantity,
      v_base_unit_id,
      v_unit_cost,
      0,
      0,
      v_line_total,
      target_warehouse_id,
      v_user_id
    )
    returning id into v_line_id;

    select coalesce(sum(sm.quantity_in - sm.quantity_out), 0)
    into v_old_qty
    from public.stock_movements sm
    where sm.tenant_id = target_tenant_id
      and sm.product_id = v_product_id
      and sm.voided_at is null;

    select p.cost_price
    into v_old_cost
    from public.products p
    where p.id = v_product_id;

    if coalesce(v_old_qty, 0) + v_quantity > 0 then
      v_new_cost :=
        (
          coalesce(v_old_qty, 0) * coalesce(v_old_cost, 0)
          + v_quantity * v_unit_cost
        ) / (coalesce(v_old_qty, 0) + v_quantity);
    else
      v_new_cost := v_unit_cost;
    end if;

    update public.products
    set
      cost_price = v_new_cost,
      updated_at = now()
    where id = v_product_id;

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
      )
      values (
        target_tenant_id,
        target_branch_id,
        target_warehouse_id,
        v_product_id,
        p_purchase_date,
        'purchase',
        v_quantity,
        0,
        v_unit_cost,
        round(v_quantity * v_unit_cost, 4),
        'purchase_lines',
        v_line_id,
        v_document_number,
        'Purchase receipt',
        v_user_id
      );
    end if;
  end loop;

  return v_document_number;
end;
$$;
