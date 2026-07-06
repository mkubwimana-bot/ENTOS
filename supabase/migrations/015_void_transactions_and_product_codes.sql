-- Void transactions (sales, payments, purchases), product code generation,
-- purchase date parameter, and manager void permission for purchases.

-- ------------------------------------------------------------
-- 1. Product code helpers
-- ------------------------------------------------------------

create or replace function public.derive_product_code_prefix(product_name text)
returns text
language plpgsql
immutable
as $$
declare
  words text[];
  w0 text;
  w1 text;
begin
  words := regexp_split_to_array(lower(trim(coalesce(product_name, ''))), '\s+');
  words := array_remove(words, '');

  if coalesce(array_length(words, 1), 0) = 0 then
    return 'prd';
  elsif array_length(words, 1) >= 3 then
    return left(regexp_replace(words[1], '[^a-z0-9]', '', 'g'), 1)
      || left(regexp_replace(words[2], '[^a-z0-9]', '', 'g'), 1)
      || left(regexp_replace(words[3], '[^a-z0-9]', '', 'g'), 1);
  elsif array_length(words, 1) = 2 then
    w0 := regexp_replace(words[1], '[^a-z0-9]', '', 'g');
    w1 := regexp_replace(words[2], '[^a-z0-9]', '', 'g');
    return coalesce(left(w0, 1), 'x')
      || coalesce(left(w1, 1), 'x')
      || coalesce(
        case when length(w1) > 1 then substring(w1, 2, 1) else null end,
        case when length(w0) > 1 then substring(w0, 2, 1) else null end,
        'x'
      );
  else
    w0 := regexp_replace(words[1], '[^a-z0-9]', '', 'g');
    return lpad(left(w0, 3), 3, 'x');
  end if;
end;
$$;

create or replace function public.generate_product_code(
  target_tenant_id uuid,
  product_name text
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

  v_prefix := public.derive_product_code_prefix(product_name);

  select coalesce(
    max(
      nullif(
        substring(p.product_code from 4 for 3),
        ''
      )::integer
    ),
    0
  ) + 1
  into v_next
  from public.products p
  where p.tenant_id = target_tenant_id
    and lower(p.product_code) ~ ('^' || lower(v_prefix) || '[0-9]{3}$');

  return v_prefix || lpad(v_next::text, 3, '0');
end;
$$;

-- ------------------------------------------------------------
-- 2. Recalculate product cost after purchase void
-- ------------------------------------------------------------

create or replace function public.recalculate_product_cost_from_purchases(
  target_product_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_weighted numeric(18,4);
begin
  select
    sum(sm.quantity_in * sm.unit_cost) / nullif(sum(sm.quantity_in), 0)
  into v_weighted
  from public.stock_movements sm
  where sm.product_id = target_product_id
    and sm.movement_type = 'purchase'
    and sm.voided_at is null;

  if v_weighted is not null then
    update public.products
    set
      cost_price = round(v_weighted, 2),
      updated_at = now()
    where id = target_product_id;
  end if;
end;
$$;

-- ------------------------------------------------------------
-- 3. Void invoice (sale)
-- ------------------------------------------------------------

create or replace function public.void_invoice(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_paid numeric(14,2);
  v_user_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated.';
  end if;

  select i.tenant_id, i.paid_amount
  into v_tenant_id, v_paid
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

  if coalesce(v_paid, 0) > 0 then
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

-- ------------------------------------------------------------
-- 4. Void payment
-- ------------------------------------------------------------

create or replace function public.void_payment(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_party_id uuid;
  v_amount numeric(14,2);
  v_user_id uuid;
  v_allocation_count integer;
  v_invoice_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated.';
  end if;

  select p.tenant_id, p.party_id, p.amount
  into v_tenant_id, v_party_id, v_amount
  from public.payments p
  where p.id = p_payment_id
    and p.status = 'posted'
    and p.voided_at is null;

  if v_tenant_id is null then
    raise exception 'Payment not found or already voided.';
  end if;

  if not public.user_has_permission(v_tenant_id, 'payments.void') then
    raise exception 'You do not have permission to delete payments.';
  end if;

  select count(*)
  into v_allocation_count
  from public.payment_allocations pa
  where pa.payment_id = p_payment_id;

  update public.payments
  set
    status = 'voided',
    voided_at = now(),
    voided_by = v_user_id,
    updated_at = now()
  where id = p_payment_id;

  if v_allocation_count = 0 and v_party_id is not null then
    update public.parties
    set
      opening_balance = coalesce(opening_balance, 0) + coalesce(v_amount, 0),
      updated_at = now()
    where id = v_party_id;
  end if;

  for v_invoice_id in
    select pa.invoice_id
    from public.payment_allocations pa
    where pa.payment_id = p_payment_id
  loop
    perform public.recalculate_invoice_payment_totals(v_invoice_id);
  end loop;
end;
$$;

-- ------------------------------------------------------------
-- 5. Void purchase
-- ------------------------------------------------------------

create or replace function public.void_purchase(p_purchase_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_user_id uuid;
  v_product_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated.';
  end if;

  select pu.tenant_id
  into v_tenant_id
  from public.purchases pu
  where pu.id = p_purchase_id
    and pu.status = 'posted'
    and pu.voided_at is null;

  if v_tenant_id is null then
    raise exception 'Purchase not found or already voided.';
  end if;

  if not public.user_has_permission(v_tenant_id, 'purchases.void') then
    raise exception 'You do not have permission to delete purchases.';
  end if;

  update public.purchases
  set
    status = 'voided',
    voided_at = now(),
    voided_by = v_user_id,
    updated_at = now()
  where id = p_purchase_id;

  update public.stock_movements sm
  set
    voided_at = now(),
    voided_by = v_user_id
  from public.purchase_lines pl
  where pl.purchase_id = p_purchase_id
    and sm.source_table = 'purchase_lines'
    and sm.source_id = pl.id
    and sm.voided_at is null;

  for v_product_id in
    select distinct pl.product_id
    from public.purchase_lines pl
    where pl.purchase_id = p_purchase_id
  loop
    perform public.recalculate_product_cost_from_purchases(v_product_id);
  end loop;
end;
$$;

-- ------------------------------------------------------------
-- 6. post_purchase: accept purchase date
-- ------------------------------------------------------------

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
      raise exception 'Product not found: %', v_product_id;
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

-- ------------------------------------------------------------
-- 7. Allow managers to void purchases
-- ------------------------------------------------------------

insert into public.role_permissions (role_id, permission_id, is_allowed)
select r.id, p.id, true
from public.roles r
join public.permissions p on p.permission_code = 'purchases.void'
where r.tenant_id is null
  and r.role_code = 'manager'
on conflict do nothing;
