# Production cutover checklist

Complete these steps on cutover day after dry-run validation passes.

## Before cutover

- [ ] Migrations **001–016** applied on SME-OS Supabase project
- [ ] Owner signed up; `migration_config.json` filled with real IDs
- [ ] Final CSVs exported from old Entos (freeze writes first)
- [ ] `prep_tenant.sql` run on target tenant (clears dev/test data)
- [ ] `migrate_entos.py --dry-run` reviewed; `validation_report.json` acceptable
  - Note: negative expected stock (e.g. Congo Original) reflects old ledger — verify against old app Current Stock before go-live

## Import

1. Run [016_import_staging.sql](../migrations/016_import_staging.sql) if not already applied
2. Generate SQL: `python migrate_entos.py --config migration_config.json --dry-run`
3. Apply `output/import.sql` in Supabase SQL Editor (or `psql` / `--execute` with `DATABASE_URL`)
4. Run [validate_import.sql](validate_import.sql) — all mismatch queries must return **zero rows**
5. Run [cutover.sql](cutover.sql) — resets invoice/purchase sequences

## Smoke test (Flutter app)

- [ ] Current Stock Count matches old app (within rounding)
- [ ] Sales List shows historical sales with product names
- [ ] Purchase List shows historical purchases
- [ ] Reports → Daily sales includes migrated dates
- [ ] Reports → Aging shows Felicien / Milindi Antoine credit balances
- [ ] New Sale gets live `INV-*` number (not `MIG-INV-*`)
- [ ] New Purchase gets live `PUR-*` number

## After cutover

- [ ] Old Entos app set to read-only
- [ ] Team trained: void-only edits on posted docs in SME-OS
- [ ] Keep `output/id_map.json` and CSV exports archived for audit
