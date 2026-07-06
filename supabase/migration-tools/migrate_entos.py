#!/usr/bin/env python3
"""
Entos (old single-ledger) → SME-OS full history migration.

Reads CSV exports, generates import SQL with historical dates preserved,
and optionally executes against PostgreSQL (DATABASE_URL).

Usage:
  python migrate_entos.py --config migration_config.json --dry-run
  python migrate_entos.py --config migration_config.json --execute
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def sql_str(value: str | None) -> str:
    if value is None or value == "":
        return "null"
    return "'" + value.replace("'", "''") + "'"


def sql_uuid(value: str | uuid.UUID | None) -> str:
    if value is None or value == "":
        return "null"
    return f"'{value}'::uuid"


def sql_decimal(value: Decimal | float | int | None, places: int = 2) -> str:
    if value is None or value == "":
        return "null"
    d = Decimal(str(value)).quantize(Decimal(10) ** -places, rounding=ROUND_HALF_UP)
    return str(d)


def sql_bool(value: bool) -> str:
    return "true" if value else "false"


def sql_ts(value: str | None) -> str:
    if not value:
        return "null"
    return f"'{value}'::timestamptz"


def parse_bool(value: str | None) -> bool:
    return str(value or "").strip().lower() in ("true", "t", "1", "yes")


def parse_decimal(value: str | None, default: Decimal = Decimal("0")) -> Decimal:
    if value is None or str(value).strip() == "":
        return default
    return Decimal(str(value).strip())


def parse_date(value: str | None) -> date:
    if not value:
        raise ValueError("missing date")
    return date.fromisoformat(value.strip()[:10])


def derive_product_code_prefix(product_name: str) -> str:
    """Mirror public.derive_product_code_prefix from migration 015."""
    words = [w for w in re.split(r"\s+", (product_name or "").strip().lower()) if w]
    if not words:
        return "prd"
    if len(words) >= 3:
        parts = [re.sub(r"[^a-z0-9]", "", words[i])[:1] for i in range(3)]
        return "".join(p or "x" for p in parts)
    if len(words) == 2:
        w0 = re.sub(r"[^a-z0-9]", "", words[0])
        w1 = re.sub(r"[^a-z0-9]", "", words[1])
        third = (w1[1:2] if len(w1) > 1 else None) or (w0[1:2] if len(w0) > 1 else None) or "x"
        return (w0[:1] or "x") + (w1[:1] or "x") + third
    w0 = re.sub(r"[^a-z0-9]", "", words[0])
    return (w0[:3] or "xxx").ljust(3, "x")


UNIT_ALIASES: dict[str, str] = {
    "pcs": "pcs",
    "piece": "pcs",
    "m": "m",
    "meter": "m",
    "metre": "m",
    "liters": "l",
    "liter": "l",
    "litre": "l",
    "l": "l",
}


def normalize_unit(raw: str | None) -> str:
    key = (raw or "pcs").strip().lower()
    return UNIT_ALIASES.get(key, key or "pcs")


def normalize_category(raw: str | None) -> str | None:
    if not raw or not str(raw).strip():
        return None
    name = str(raw).strip()
    if name.lower() == "imipira":
        return "Imipira"
    return name


def normalize_product_code(sku: str | None, product_name: str, used_codes: set[str]) -> str:
    if sku and str(sku).strip():
        code = str(sku).strip()
    else:
        prefix = derive_product_code_prefix(product_name)
        n = 1
        while True:
            code = f"{prefix}{n:03d}"
            if code not in used_codes:
                break
            n += 1
    used_codes.add(code)
    return code


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

@dataclass
class MigrationConfig:
    tenant_id: str
    branch_id: str
    warehouse_id: str
    created_by: str
    csv_dir: Path
    org_created_at: str = "2026-05-30"
    org_name: str = "Alpho Shop"
    reuse_legacy_uuids: bool = True
    import_voided_history: bool = True

    @classmethod
    def load(cls, path: Path) -> MigrationConfig:
        data = json.loads(path.read_text(encoding="utf-8"))
        base = path.parent
        csv_dir = Path(data["csv_dir"])
        if not csv_dir.is_absolute():
            csv_dir = (base / csv_dir).resolve()
        return cls(
            tenant_id=data["tenant_id"],
            branch_id=data["branch_id"],
            warehouse_id=data["warehouse_id"],
            created_by=data["created_by"],
            csv_dir=csv_dir,
            org_created_at=data.get("org_created_at", "2026-05-30"),
            org_name=data.get("org_name", "Alpho Shop"),
            reuse_legacy_uuids=data.get("reuse_legacy_uuids", True),
            import_voided_history=data.get("import_voided_history", True),
        )


# ---------------------------------------------------------------------------
# SQL builder
# ---------------------------------------------------------------------------

class SqlBuilder:
    def __init__(self) -> None:
        self.lines: list[str] = []

    def add(self, line: str = "") -> None:
        self.lines.append(line)

    def section(self, title: str) -> None:
        self.add("")
        self.add(f"-- {'=' * 60}")
        self.add(f"-- {title}")
        self.add(f"-- {'=' * 60}")

    def to_text(self) -> str:
        return "\n".join(self.lines) + "\n"


# ---------------------------------------------------------------------------
# Expected reconciliation (from CSV, for dry-run report)
# ---------------------------------------------------------------------------

def compute_expected_from_csv(
    products: list[dict[str, str]],
    movements: list[dict[str, str]],
    customers: list[dict[str, str]],
) -> dict[str, Any]:
    product_names = {r["id"]: r["name"] for r in products}
    customer_names = {r["id"]: r["name"] for r in customers}

    stock: dict[str, Decimal] = defaultdict(Decimal)
    for p in products:
        if not parse_bool(p.get("deleted")):
            stock[p["id"]] += parse_decimal(p.get("opening_qty"))

    balances: dict[str, Decimal] = defaultdict(Decimal)
    counts = {"in": 0, "out": 0, "adjustment": 0, "voided": 0, "active": 0}

    def apply_movement(row: dict[str, str], include: bool) -> None:
        if not include:
            return
        pid = row["product_id"]
        qty = parse_decimal(row.get("qty"))
        mtype = row["type"].strip().lower()
        if mtype == "in":
            stock[pid] += qty
        elif mtype == "out":
            stock[pid] -= qty
            if not parse_bool(row.get("paid")) and row.get("customer_id"):
                total = qty * parse_decimal(row.get("unit_price"))
                balances[row["customer_id"]] += total
        elif mtype == "adjustment":
            stock[pid] += qty

    for row in movements:
        deleted = parse_bool(row.get("deleted"))
        if deleted:
            counts["voided"] += 1
        else:
            counts["active"] += 1
            apply_movement(row, True)
            mtype = row["type"].strip().lower()
            if mtype in counts:
                counts[mtype] += 1

    return {
        "stock_by_product": {
            product_names.get(pid, pid): float(q) for pid, q in sorted(stock.items())
        },
        "customer_balances": {
            customer_names.get(cid, cid): float(b) for cid, b in sorted(balances.items()) if b != 0
        },
        "movement_counts": counts,
        "total_active_movements": counts["active"],
    }


# ---------------------------------------------------------------------------
# Main migration generator
# ---------------------------------------------------------------------------

@dataclass
class IdMaps:
    party: dict[str, str] = field(default_factory=dict)
    product: dict[str, str] = field(default_factory=dict)
    category: dict[str, str] = field(default_factory=dict)
    purchase: dict[str, str] = field(default_factory=dict)
    invoice: dict[str, str] = field(default_factory=dict)
    adjustment: dict[str, str] = field(default_factory=dict)


def new_id(cfg: MigrationConfig, legacy_id: str | None = None) -> str:
    if cfg.reuse_legacy_uuids and legacy_id:
        return legacy_id
    return str(uuid.uuid4())


def generate_sql(cfg: MigrationConfig) -> tuple[str, IdMaps, dict[str, Any], list[str]]:
    warnings: list[str] = []
    csv_dir = cfg.csv_dir
    products_raw = read_csv(csv_dir / "products_rows.csv")
    customers_raw = read_csv(csv_dir / "customers_rows.csv")
    suppliers_raw = read_csv(csv_dir / "suppliers_rows.csv")
    movements_raw = read_csv(csv_dir / "movements_rows.csv")

    expected = compute_expected_from_csv(products_raw, movements_raw, customers_raw)
    maps = IdMaps()
    sql = SqlBuilder()
    tid, bid, wid, uid = cfg.tenant_id, cfg.branch_id, cfg.warehouse_id, cfg.created_by

    sql.add("-- Entos → SME-OS full history import")
    sql.add(f"-- Tenant: {cfg.org_name} ({tid})")
    sql.add("-- Generated by migrate_entos.py")
    sql.add("-- Prerequisite: run supabase/migrations/016_import_staging.sql once on this project.")
    sql.add("begin;")

    sql.section("Run log")
    run_id = str(uuid.uuid4())
    sql.add(
        f"insert into public.migration_run_log (id, tenant_id, run_label, phase, status) "
        f"values ({sql_uuid(run_id)}, {sql_uuid(tid)}, 'entos_full_history', 'import', 'started');"
    )

    # --- Categories ---
    sql.section("Product categories")
    categories: set[str] = set()
    for p in products_raw:
        cat = normalize_category(p.get("category"))
        if cat:
            categories.add(cat)
    for cat_name in sorted(categories):
        cat_id = str(uuid.uuid4())
        maps.category[cat_name] = cat_id
        code = re.sub(r"[^A-Za-z0-9]", "_", cat_name)[:20].upper() or "CAT"
        sql.add(
            f"insert into public.product_categories (id, tenant_id, category_code, category_name, created_by) "
            f"values ({sql_uuid(cat_id)}, {sql_uuid(tid)}, {sql_str(code)}, {sql_str(cat_name)}, {sql_uuid(uid)}) "
            f"on conflict (tenant_id, category_name) do nothing;"
        )
        sql.add(
            f"insert into public.migration_id_map (tenant_id, entity_type, legacy_id, new_id, legacy_ref) "
            f"select {sql_uuid(tid)}, 'category', {sql_uuid(cat_id)}, id, {sql_str(cat_name)} "
            f"from public.product_categories where tenant_id = {sql_uuid(tid)} and category_name = {sql_str(cat_name)} "
            f"on conflict do nothing;"
        )

    # --- Tenant-specific unit: liters alias ---
    sql.section("Product units (tenant overrides if needed)")
    extra_units = {"liters": ("Liters", 3)}
    for unit_code, (unit_name, dec) in extra_units.items():
        sql.add(
            f"insert into public.product_units (tenant_id, unit_code, unit_name, decimal_places) "
            f"select {sql_uuid(tid)}, {sql_str(unit_code)}, {sql_str(unit_name)}, {dec} "
            f"where not exists ("
            f"  select 1 from public.product_units u "
            f"  where u.unit_code = {sql_str(normalize_unit(unit_code))} "
            f"    and (u.tenant_id is null or u.tenant_id = {sql_uuid(tid)})"
            f");"
        )

    # --- Staging parties ---
    sql.section("Stage parties")
    for row in customers_raw:
        sql.add(
            f"insert into public.stg_entos_parties (tenant_id, legacy_id, party_kind, name, phone, email, note, deleted, updated_at) "
            f"values ({sql_uuid(tid)}, {sql_uuid(row['id'])}, 'customer', {sql_str(row.get('name'))}, "
            f"{sql_str(row.get('phone') or None)}, {sql_str(row.get('email') or None)}, "
            f"{sql_str(row.get('note') or None)}, {sql_bool(parse_bool(row.get('deleted')))}, "
            f"{sql_ts(row.get('updated_at'))}) on conflict do nothing;"
        )
    for row in suppliers_raw:
        sql.add(
            f"insert into public.stg_entos_parties (tenant_id, legacy_id, party_kind, name, phone, email, note, deleted, updated_at) "
            f"values ({sql_uuid(tid)}, {sql_uuid(row['id'])}, 'supplier', {sql_str(row.get('name'))}, "
            f"{sql_str(row.get('phone') or None)}, {sql_str(row.get('email') or None)}, "
            f"{sql_str(row.get('note') or None)}, {sql_bool(parse_bool(row.get('deleted')))}, "
            f"{sql_ts(row.get('updated_at'))}) on conflict do nothing;"
        )

    # --- Parties ---
    sql.section("Parties — customers")
    cust_n = 0
    for row in customers_raw:
        cust_n += 1
        party_id = new_id(cfg, row["id"])
        maps.party[row["id"]] = party_id
        deleted = parse_bool(row.get("deleted"))
        status = "inactive" if deleted else "active"
        deleted_at = sql_ts(row.get("updated_at")) if deleted else "null"
        sql.add(
            f"insert into public.parties (id, tenant_id, party_code, party_name, primary_phone, primary_email, "
            f"notes, status, opening_balance, deleted_at, created_by) values ("
            f"{sql_uuid(party_id)}, {sql_uuid(tid)}, {sql_str(f'CUST-{cust_n:03d}')}, {sql_str(row.get('name'))}, "
            f"{sql_str(row.get('phone') or None)}, {sql_str(row.get('email') or None)}, "
            f"{sql_str(row.get('note') or None)}, {sql_str(status)}, 0, {deleted_at}, {sql_uuid(uid)});"
        )
        sql.add(
            f"insert into public.party_type_links (tenant_id, party_id, party_type_id, is_primary) "
            f"select {sql_uuid(tid)}, {sql_uuid(party_id)}, pt.id, true from public.party_types pt "
            f"where pt.type_code = 'customer';"
        )
        sql.add(
            f"insert into public.migration_id_map (tenant_id, entity_type, legacy_id, new_id, legacy_ref) "
            f"values ({sql_uuid(tid)}, 'party', {sql_uuid(row['id'])}, {sql_uuid(party_id)}, 'customer');"
        )

    sql.section("Parties — suppliers")
    sup_n = 0
    for row in suppliers_raw:
        sup_n += 1
        party_id = new_id(cfg, row["id"])
        maps.party[row["id"]] = party_id
        deleted = parse_bool(row.get("deleted"))
        status = "inactive" if deleted else "active"
        deleted_at = sql_ts(row.get("updated_at")) if deleted else "null"
        sql.add(
            f"insert into public.parties (id, tenant_id, party_code, party_name, primary_phone, primary_email, "
            f"notes, status, opening_balance, deleted_at, created_by) values ("
            f"{sql_uuid(party_id)}, {sql_uuid(tid)}, {sql_str(f'SUP-{sup_n:03d}')}, {sql_str(row.get('name'))}, "
            f"{sql_str(row.get('phone') or None)}, {sql_str(row.get('email') or None)}, "
            f"{sql_str(row.get('note') or None)}, {sql_str(status)}, 0, {deleted_at}, {sql_uuid(uid)});"
        )
        sql.add(
            f"insert into public.party_type_links (tenant_id, party_id, party_type_id, is_primary) "
            f"select {sql_uuid(tid)}, {sql_uuid(party_id)}, pt.id, true from public.party_types pt "
            f"where pt.type_code = 'supplier';"
        )
        sql.add(
            f"insert into public.migration_id_map (tenant_id, entity_type, legacy_id, new_id, legacy_ref) "
            f"values ({sql_uuid(tid)}, 'party', {sql_uuid(row['id'])}, {sql_uuid(party_id)}, 'supplier');"
        )

    # --- Products ---
    sql.section("Products")
    used_codes: set[str] = set()
    product_meta: dict[str, dict[str, Any]] = {}
    stock_item_subq = "(select id from public.product_types where type_code = 'stock_item' limit 1)"

    for row in products_raw:
        pid = new_id(cfg, row["id"])
        maps.product[row["id"]] = pid
        code = normalize_product_code(row.get("sku"), row.get("name", ""), used_codes)
        cat = normalize_category(row.get("category"))
        cat_id_sql = sql_uuid(maps.category[cat]) if cat and cat in maps.category else "null"
        unit_code = normalize_unit(row.get("unit"))
        unit_subq = (
            f"(select id from public.product_units where unit_code = {sql_str(unit_code)} "
            f"and (tenant_id is null or tenant_id = {sql_uuid(tid)}) order by tenant_id nulls last limit 1)"
        )
        deleted = parse_bool(row.get("deleted"))
        deleted_at = sql_ts(row.get("updated_at")) if deleted else "null"
        status = "inactive" if deleted else "active"
        opening_qty = parse_decimal(row.get("opening_qty"))
        product_meta[row["id"]] = {
            "name": row.get("name"),
            "cost": parse_decimal(row.get("cost_price")),
            "opening_qty": opening_qty,
            "updated_at": row.get("updated_at"),
        }
        sql.add(
            f"insert into public.stg_entos_products (tenant_id, legacy_id, sku, name, category, unit, "
            f"cost_price, sale_price, reorder_level, opening_qty, deleted, updated_at) "
            f"values ({sql_uuid(tid)}, {sql_uuid(row['id'])}, {sql_str(row.get('sku') or None)}, "
            f"{sql_str(row.get('name'))}, {sql_str(row.get('category') or None)}, {sql_str(row.get('unit') or None)}, "
            f"{sql_decimal(parse_decimal(row.get('cost_price')), 4)}, {sql_decimal(parse_decimal(row.get('sale_price')))}, "
            f"{sql_decimal(parse_decimal(row.get('reorder_level')), 3)}, {sql_decimal(opening_qty, 3)}, "
            f"{sql_bool(deleted)}, {sql_ts(row.get('updated_at'))}) on conflict do nothing;"
        )
        sql.add(
            f"insert into public.products (id, tenant_id, product_code, product_name, product_type_id, "
            f"category_id, base_unit_id, barcode, cost_price, selling_price, reorder_level, "
            f"is_inventory_tracked, status, deleted_at, created_by) values ("
            f"{sql_uuid(pid)}, {sql_uuid(tid)}, {sql_str(code)}, {sql_str(row.get('name'))}, {stock_item_subq}, "
            f"{cat_id_sql}, {unit_subq}, {sql_str(row.get('barcode') or None)}, "
            f"{sql_decimal(parse_decimal(row.get('cost_price')), 4)}, {sql_decimal(parse_decimal(row.get('sale_price')))}, "
            f"{sql_decimal(parse_decimal(row.get('reorder_level')), 3)}, true, {sql_str(status)}, {deleted_at}, {sql_uuid(uid)});"
        )
        sql.add(
            f"insert into public.migration_id_map (tenant_id, entity_type, legacy_id, new_id, legacy_ref) "
            f"values ({sql_uuid(tid)}, 'product', {sql_uuid(row['id'])}, {sql_uuid(pid)}, {sql_str(code)});"
        )

    # Earliest movement date per product for opening date
    earliest_mv: dict[str, date] = {}
    org_date = parse_date(cfg.org_created_at)
    for mv in movements_raw:
        pid = mv["product_id"]
        d = parse_date(mv.get("date"))
        earliest_mv[pid] = min(earliest_mv.get(pid, d), d)

    # --- Opening stock ---
    sql.section("Opening stock")
    for legacy_pid, meta in product_meta.items():
        qty = meta["opening_qty"]
        if qty <= 0:
            continue
        new_pid = maps.product[legacy_pid]
        mv_date = min(org_date, earliest_mv.get(legacy_pid, org_date))
        sm_id = str(uuid.uuid4())
        cost = meta["cost"]
        sql.add(
            f"insert into public.stock_movements (id, tenant_id, branch_id, warehouse_id, product_id, "
            f"movement_date, movement_type, quantity_in, quantity_out, unit_cost, total_cost, reason, created_by) "
            f"values ({sql_uuid(sm_id)}, {sql_uuid(tid)}, {sql_uuid(bid)}, {sql_uuid(wid)}, {sql_uuid(new_pid)}, "
            f"'{mv_date.isoformat()}', 'opening', {sql_decimal(qty, 3)}, 0, {sql_decimal(cost, 4)}, "
            f"{sql_decimal(qty * cost, 4)}, 'Entos opening_qty import', {sql_uuid(uid)});"
        )

    # --- Movements replay ---
    def sort_key(r: dict[str, str]) -> tuple:
        return (parse_date(r.get("date")), r.get("updated_at") or "", r.get("id") or "")

    active_mvs = [m for m in movements_raw if not parse_bool(m.get("deleted"))]
    voided_mvs = [m for m in movements_raw if parse_bool(m.get("deleted"))]

    pur_seq = 0
    inv_seq = 0
    adj_seq = 0

    def replay_movements(rows: list[dict[str, str]], voided: bool) -> None:
        nonlocal pur_seq, inv_seq, adj_seq
        title = "Voided movements (import as voided)" if voided else "Active movements (chronological replay)"
        sql.section(title)

        for row in sorted(rows, key=sort_key):
            legacy_mid = row["id"]
            mtype = row["type"].strip().lower()
            legacy_pid = row["product_id"]
            if legacy_pid not in maps.product:
                warnings.append(f"Movement {legacy_mid}: unknown product {legacy_pid}")
                continue
            new_pid = maps.product[legacy_pid]
            qty = parse_decimal(row.get("qty"))
            unit_price = parse_decimal(row.get("unit_price"))
            mv_date = parse_date(row.get("date"))
            updated_at = row.get("updated_at")
            voided_at = sql_ts(updated_at) if voided else "null"
            status_void = ", voided_at, voided_by" if voided else ""
            vals_void = f", {voided_at}, {sql_uuid(uid)}" if voided else ""
            doc_status = "'voided'" if voided else "'posted'"
            sm_void = f", voided_at, voided_by" if voided else ""
            sm_void_vals = f", {voided_at}, {sql_uuid(uid)}" if voided else ""

            sql.add(
                f"insert into public.stg_entos_movements (tenant_id, legacy_id, product_id, movement_type, qty, "
                f"unit_price, movement_date, supplier_id, customer_id, paid, deleted, updated_at) "
                f"values ({sql_uuid(tid)}, {sql_uuid(legacy_mid)}, {sql_uuid(legacy_pid)}, {sql_str(mtype)}, "
                f"{sql_decimal(qty, 3)}, {sql_decimal(unit_price)}, '{mv_date.isoformat()}', "
                f"{sql_uuid(row.get('supplier_id') or None)}, {sql_uuid(row.get('customer_id') or None)}, "
                f"{sql_bool(parse_bool(row.get('paid')))}, {sql_bool(voided)}, {sql_ts(updated_at)}) on conflict do nothing;"
            )

            if mtype == "in":
                pur_seq += 1
                doc_id = str(uuid.uuid4())
                maps.purchase[legacy_mid] = doc_id
                party_sql = sql_uuid(maps.party[row["supplier_id"]]) if row.get("supplier_id") and row["supplier_id"] in maps.party else "null"
                line_total = (qty * unit_price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
                pur_num = f"MIG-PUR-{pur_seq:06d}"
                pl_id = str(uuid.uuid4())
                sm_id = str(uuid.uuid4())

                sql.add(
                    f"insert into public.purchases (id, tenant_id, branch_id, warehouse_id, purchase_number, "
                    f"purchase_date, party_id, status, subtotal_amount, total_amount, notes, created_by, posted_at"
                    f"{status_void}) values ({sql_uuid(doc_id)}, {sql_uuid(tid)}, {sql_uuid(bid)}, {sql_uuid(wid)}, "
                    f"{sql_str(pur_num)}, '{mv_date.isoformat()}', {party_sql}, {doc_status}, "
                    f"{sql_decimal(line_total)}, {sql_decimal(line_total)}, "
                    f"{sql_str(f'legacy_movement:{legacy_mid}')}, {sql_uuid(uid)}, {sql_ts(updated_at)}"
                    f"{vals_void});"
                )
                sql.add(
                    f"insert into public.purchase_lines (id, tenant_id, purchase_id, line_number, product_id, "
                    f"description, quantity, unit_id, unit_cost, line_total, warehouse_id, created_by) "
                    f"select {sql_uuid(pl_id)}, {sql_uuid(tid)}, {sql_uuid(doc_id)}, 1, {sql_uuid(new_pid)}, "
                    f"p.product_name, {sql_decimal(qty, 3)}, p.base_unit_id, {sql_decimal(unit_price)}, "
                    f"{sql_decimal(line_total)}, {sql_uuid(wid)}, {sql_uuid(uid)} from public.products p where p.id = {sql_uuid(new_pid)};"
                )
                if not voided:
                    sql.add(
                        f"update public.products p set cost_price = case "
                        f"when coalesce((select sum(sm.quantity_in - sm.quantity_out) from public.stock_movements sm "
                        f"  where sm.product_id = p.id and sm.tenant_id = {sql_uuid(tid)} and sm.voided_at is null), 0) + {sql_decimal(qty, 3)} > 0 "
                        f"then (coalesce((select sum(sm.quantity_in - sm.quantity_out) from public.stock_movements sm "
                        f"  where sm.product_id = p.id and sm.tenant_id = {sql_uuid(tid)} and sm.voided_at is null), 0) "
                        f"  * coalesce(p.cost_price, 0) + {sql_decimal(qty, 3)} * {sql_decimal(unit_price)}) "
                        f"  / (coalesce((select sum(sm.quantity_in - sm.quantity_out) from public.stock_movements sm "
                        f"  where sm.product_id = p.id and sm.tenant_id = {sql_uuid(tid)} and sm.voided_at is null), 0) + {sql_decimal(qty, 3)}) "
                        f"else {sql_decimal(unit_price, 4)} end, updated_at = now() where p.id = {sql_uuid(new_pid)};"
                    )
                sql.add(
                    f"insert into public.stock_movements (id, tenant_id, branch_id, warehouse_id, product_id, "
                    f"movement_date, movement_type, quantity_in, quantity_out, unit_cost, total_cost, "
                    f"source_table, source_id, reference_number, created_by{sm_void}) "
                    f"values ({sql_uuid(sm_id)}, {sql_uuid(tid)}, {sql_uuid(bid)}, {sql_uuid(wid)}, {sql_uuid(new_pid)}, "
                    f"'{mv_date.isoformat()}', 'purchase', {sql_decimal(qty, 3)}, 0, {sql_decimal(unit_price, 4)}, "
                    f"{sql_decimal(qty * unit_price, 4)}, 'purchases', {sql_uuid(doc_id)}, {sql_str(pur_num)}, "
                    f"{sql_uuid(uid)}{sm_void_vals});"
                )
                sql.add(
                    f"insert into public.migration_id_map (tenant_id, entity_type, legacy_id, new_id, legacy_ref) "
                    f"values ({sql_uuid(tid)}, 'purchase', {sql_uuid(legacy_mid)}, {sql_uuid(doc_id)}, {sql_str(pur_num)});"
                )

            elif mtype == "out":
                inv_seq += 1
                doc_id = str(uuid.uuid4())
                maps.invoice[legacy_mid] = doc_id
                paid = parse_bool(row.get("paid"))
                cust_id = row.get("customer_id")
                party_sql = sql_uuid(maps.party[cust_id]) if cust_id and cust_id in maps.party else "null"
                if not paid and not cust_id:
                    warnings.append(f"Movement {legacy_mid}: credit sale without customer — treated as cash")
                    paid = True
                sale_type = "cash" if paid else "credit"
                sale_qty = abs(qty)
                if sale_qty <= 0:
                    warnings.append(f"Movement {legacy_mid}: out qty <= 0 — skipped")
                    continue
                line_total = (sale_qty * unit_price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
                paid_amt = line_total if paid else Decimal("0")
                balance_amt = Decimal("0") if paid else line_total
                inv_num = f"MIG-INV-{inv_seq:06d}"
                il_id = str(uuid.uuid4())
                sm_id = str(uuid.uuid4())

                sql.add(
                    f"insert into public.invoices (id, tenant_id, branch_id, warehouse_id, invoice_number, "
                    f"invoice_date, party_id, sale_type, status, subtotal_amount, total_amount, paid_amount, "
                    f"balance_amount, notes, created_by, posted_at{status_void}) values ("
                    f"{sql_uuid(doc_id)}, {sql_uuid(tid)}, {sql_uuid(bid)}, {sql_uuid(wid)}, {sql_str(inv_num)}, "
                    f"'{mv_date.isoformat()}', {party_sql}, {sql_str(sale_type)}, {doc_status}, "
                    f"{sql_decimal(line_total)}, {sql_decimal(line_total)}, {sql_decimal(paid_amt)}, "
                    f"{sql_decimal(balance_amt)}, {sql_str(f'legacy_movement:{legacy_mid}')}, {sql_uuid(uid)}, "
                    f"{sql_ts(updated_at)}{vals_void});"
                )
                sql.add(
                    f"insert into public.invoice_lines (id, tenant_id, invoice_id, line_number, product_id, "
                    f"description, quantity, unit_id, unit_price, line_total, cost_price_snapshot, warehouse_id, created_by) "
                    f"select {sql_uuid(il_id)}, {sql_uuid(tid)}, {sql_uuid(doc_id)}, 1, {sql_uuid(new_pid)}, "
                    f"p.product_name, {sql_decimal(sale_qty, 3)}, p.base_unit_id, {sql_decimal(unit_price)}, "
                    f"{sql_decimal(line_total)}, p.cost_price, {sql_uuid(wid)}, {sql_uuid(uid)} "
                    f"from public.products p where p.id = {sql_uuid(new_pid)};"
                )
                sql.add(
                    f"insert into public.stock_movements (id, tenant_id, branch_id, warehouse_id, product_id, "
                    f"movement_date, movement_type, quantity_in, quantity_out, unit_cost, total_cost, "
                    f"source_table, source_id, reference_number, created_by{sm_void}) "
                    f"values ({sql_uuid(sm_id)}, {sql_uuid(tid)}, {sql_uuid(bid)}, {sql_uuid(wid)}, {sql_uuid(new_pid)}, "
                    f"'{mv_date.isoformat()}', 'sale', 0, {sql_decimal(sale_qty, 3)}, "
                    f"(select cost_price from public.products where id = {sql_uuid(new_pid)}), "
                    f"null, 'invoices', {sql_uuid(doc_id)}, {sql_str(inv_num)}, {sql_uuid(uid)}{sm_void_vals});"
                )
                sql.add(
                    f"insert into public.migration_id_map (tenant_id, entity_type, legacy_id, new_id, legacy_ref) "
                    f"values ({sql_uuid(tid)}, 'invoice', {sql_uuid(legacy_mid)}, {sql_uuid(doc_id)}, {sql_str(inv_num)});"
                )

            elif mtype == "adjustment":
                adj_seq += 1
                adj_id = str(uuid.uuid4())
                maps.adjustment[legacy_mid] = adj_id
                sm_id = str(uuid.uuid4())
                ref = f"MIG-ADJ-{adj_seq:06d}"
                if qty >= 0:
                    qin, qout = qty, Decimal("0")
                else:
                    qin, qout = Decimal("0"), abs(qty)
                sql.add(
                    f"insert into public.stock_movements (id, tenant_id, branch_id, warehouse_id, product_id, "
                    f"movement_date, movement_type, quantity_in, quantity_out, unit_cost, total_cost, "
                    f"reference_number, reason, created_by{sm_void}) "
                    f"values ({sql_uuid(sm_id)}, {sql_uuid(tid)}, {sql_uuid(bid)}, {sql_uuid(wid)}, {sql_uuid(new_pid)}, "
                    f"'{mv_date.isoformat()}', 'adjustment', {sql_decimal(qin, 3)}, {sql_decimal(qout, 3)}, "
                    f"{sql_decimal(unit_price, 4)}, {sql_decimal(abs(qty) * unit_price, 4)}, {sql_str(ref)}, "
                    f"{sql_str(f'legacy_movement:{legacy_mid}')}, {sql_uuid(uid)}{sm_void_vals});"
                )
                sql.add(
                    f"insert into public.migration_id_map (tenant_id, entity_type, legacy_id, new_id, legacy_ref) "
                    f"values ({sql_uuid(tid)}, 'adjustment', {sql_uuid(legacy_mid)}, {sql_uuid(sm_id)}, {sql_str(ref)});"
                )
            else:
                warnings.append(f"Movement {legacy_mid}: unknown type '{mtype}' — skipped")

    replay_movements(active_mvs, voided=False)
    if cfg.import_voided_history:
        replay_movements(voided_mvs, voided=True)

    sql.section("Complete run log")
    total_docs = pur_seq + inv_seq + adj_seq
    sql.add(
        f"update public.migration_run_log set status = 'completed', row_count = {total_docs}, "
        f"finished_at = now(), details = jsonb_build_object("
        f"'purchases', {pur_seq}, 'invoices', {inv_seq}, 'adjustments', {adj_seq}, "
        f"'warnings', {sql_str(json.dumps(warnings))}::jsonb) "
        f"where id = {sql_uuid(run_id)};"
    )
    sql.add("commit;")

    expected["generated_counts"] = {
        "purchases": pur_seq,
        "invoices": inv_seq,
        "adjustments": adj_seq,
        "warnings": len(warnings),
    }
    expected["warnings"] = warnings

    return sql.to_text(), maps, expected, warnings


def write_outputs(
    out_dir: Path,
    sql_text: str,
    maps: IdMaps,
    expected: dict[str, Any],
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "import.sql").write_text(sql_text, encoding="utf-8")
    id_map = {
        "party": maps.party,
        "product": maps.product,
        "category": maps.category,
        "purchase": maps.purchase,
        "invoice": maps.invoice,
        "adjustment": maps.adjustment,
    }
    (out_dir / "id_map.json").write_text(json.dumps(id_map, indent=2), encoding="utf-8")
    (out_dir / "validation_report.json").write_text(json.dumps(expected, indent=2), encoding="utf-8")


def execute_sql(sql_text: str, database_url: str) -> None:
    try:
        import psycopg2
    except ImportError as exc:
        raise SystemExit("Install psycopg2-binary for --execute: pip install psycopg2-binary") from exc

    conn = psycopg2.connect(database_url)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute(sql_text)
        conn.commit()
        print("Import SQL executed successfully.")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Entos → SME-OS full history migration")
    parser.add_argument("--config", type=Path, default=Path("migration_config.json"))
    parser.add_argument("--dry-run", action="store_true", help="Generate SQL only (default)")
    parser.add_argument("--execute", action="store_true", help="Execute against DATABASE_URL")
    parser.add_argument("--output-dir", type=Path, default=Path("output"))
    args = parser.parse_args()

    if not args.config.exists():
        print(f"Config not found: {args.config}", file=sys.stderr)
        print("Copy migration_config.example.json → migration_config.json and fill in tenant IDs.", file=sys.stderr)
        return 1

    cfg = MigrationConfig.load(args.config)
    if not cfg.csv_dir.exists():
        print(f"CSV directory not found: {cfg.csv_dir}", file=sys.stderr)
        return 1

    sql_text, maps, expected, warnings = generate_sql(cfg)
    out_dir = args.output_dir
    if not out_dir.is_absolute():
        out_dir = (Path(__file__).parent / out_dir).resolve()
    write_outputs(out_dir, sql_text, maps, expected)

    print(f"Wrote {out_dir / 'import.sql'} ({len(sql_text.splitlines())} lines)")
    print(f"Wrote {out_dir / 'id_map.json'}")
    print(f"Wrote {out_dir / 'validation_report.json'}")
    print(f"Expected: {expected.get('generated_counts')}")
    if warnings:
        print(f"Warnings ({len(warnings)}):")
        for w in warnings[:20]:
            print(f"  - {w}")
        if len(warnings) > 20:
            print(f"  ... and {len(warnings) - 20} more")

    if args.execute:
        import os

        url = os.environ.get("DATABASE_URL")
        if not url:
            print("Set DATABASE_URL to execute.", file=sys.stderr)
            return 1
        execute_sql(sql_text, url)
    elif not args.dry_run:
        print("Use --dry-run (default) or --execute.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
