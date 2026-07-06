# Entos → SME-OS Full History Migration

One-off import pipeline for Alpho Shop (and similar old Entos tenants).

## Before you start

1. Apply Supabase migrations **001–016** on the SME-OS project.
2. Sign up in the SME-OS app as **owner** and note these IDs from Supabase:

```sql
select t.id as tenant_id, t.trading_name,
       b.id as branch_id, w.id as warehouse_id,
       u.id as owner_app_user_id
from tenants t
join branches b on b.tenant_id = t.id and b.is_default = true
join warehouses w on w.branch_id = b.id and w.is_default = true
join user_tenants ut on ut.tenant_id = t.id and ut.membership_status = 'active'
join app_users u on u.id = ut.user_id
where t.deleted_at is null
limit 1;
```

3. Copy `migration_config.example.json` → `migration_config.json` and fill in the IDs.
4. Export final CSVs from the old Entos project into `supabase/migrations/samples/` (or another folder; set `csv_dir` in config).

## Wipe dev/test data (same tenant only)

Run [prep_tenant.sql](prep_tenant.sql) in Supabase SQL Editor after replacing `:tenant_id` with your real tenant UUID. This removes transactional data but keeps tenant, branch, warehouse, and users.

## Run migration

### Dry-run (generates SQL + local validation report — no DB connection)

```powershell
cd supabase/migration-tools
python migrate_entos.py --config migration_config.json --dry-run
```

Outputs:

- `output/import.sql` — run in Supabase SQL Editor (or psql)
- `output/id_map.json` — old → new UUID map
- `output/validation_report.json` — expected stock/balances from CSV

### Apply to database

If `import.sql` is **too large for SQL Editor**, either:

**A — Run split chunks** (after dry-run):

```powershell
python split_import_sql.py
```

Then run every file in `output/chunks/` **in numeric order** (01 → 16+).

**B — Direct database connection** (recommended for full import):

1. Supabase Dashboard → **Project Settings** → **Database** → copy **URI** (Session mode).
2. Replace `[YOUR-PASSWORD]` with your DB password.

```powershell
cd supabase/migration-tools
$env:DATABASE_URL = "postgresql://postgres.xxxx:[YOUR-PASSWORD]@aws-0-eu-central-1.pooler.supabase.com:5432/postgres"
python migrate_entos.py --config migration_config.json --execute
```

Or with psql:

```powershell
psql $env:DATABASE_URL -f output/import.sql
```

**C — SQL Editor chunks:** paste/run `output/import.sql` in sections (masters → opening → movements → voided) if each part is small enough.

## Post-import validation

Run [validate_import.sql](validate_import.sql) in SQL Editor (set `tenant_id` at top). All checks should return zero mismatch rows.

## Cutover

1. Run [cutover.sql](cutover.sql) to reset live document number sequences.
2. Smoke-test: Sales List, Purchase List, Current Stock Count, Reports (Daily sales, Aging).
3. Freeze the old Entos app (read-only).

## Files

| File | Purpose |
|------|---------|
| `migrate_entos.py` | CSV reader, SQL generator, optional executor |
| `migration_config.example.json` | Tenant/branch/warehouse IDs and paths |
| `prep_tenant.sql` | Clear transactional data before import |
| `../migrations/016_import_staging.sql` | Staging tables + id map (run once) |
| `validate_import.sql` | Post-import reconciliation queries |
| `cutover.sql` | Bump `number_sequences` after MIG-* import |
| `identify_test_data.sql` | List dev/test rows vs migrated rows |
| `remove_test_data_keep_migrated.sql` | Delete test data only; keep Entos import |
