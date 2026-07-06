# SME-OS

Rwanda-focused, multi-tenant SaaS platform for SMEs. The authoritative architecture
spec is `/docs/architecture.md` (SME-OS Volume 3, v1.3) — read it before proposing
schema or feature changes, and keep all work consistent with it, especially
**Section 32** (credit-footprint layer) and **Section 33** (data-protection compliance).

## Founder context
The founder has a strong relational-database and Microsoft Access/VBA background
(forms, queries, reports, business-process automation) plus domain expertise in
finance, and is still learning modern SaaS and Flutter development. When a Flutter,
Dart, or web concept is unfamiliar, explain it briefly using relational-database or
Access/VBA analogies (e.g. Dart widgets ≈ Access forms/controls).

## Stack
- **Frontend:** Flutter (Dart), hand-coded — do NOT use FlutterFlow. Primary target
  is Android (low-end devices common among Rwandan SMEs); iOS and Flutter web are
  secondary.
- **Supabase client:** official `supabase_flutter` package.
- **Auth:** Supabase Auth via `supabase_flutter`.
- **Offline storage:** local SQLite via Drift (relational, mirrors the Postgres
  schema), encrypted with SQLCipher (holds personal data). Keys/tokens in
  `flutter_secure_storage`.
- **Offline sync:** Volume 3 `transaction_drafts` + `sync_queue` pattern with a
  `client_reference_id` idempotency key and conflict logging. Keep it limited —
  do not build a full offline ERP in the MVP. (PowerSync is a possible managed
  option later if custom sync becomes a bottleneck — evaluate, don't adopt by
  default.)
- **State management:** Provider or Riverpod — keep it simple, avoid heavy
  architecture early.
- **Backend / database:** Supabase (PostgreSQL).
- **Version control:** GitHub — the repository is the single source of truth.
- **Environment:** you may run `flutter` and `dart` CLI commands; the founder
  runs emulator/device testing.

## Commands
- `flutter run` — run on connected device/emulator
- `flutter test` — run tests
- `dart format .` — format code
- `flutter analyze` — static analysis / lint

## Architecture rules (from Volume 3)
- Shared database, multi-tenant: every tenant-owned table carries `tenant_id`.
- UUID primary keys.
- Enforce Row-Level Security on every tenant table — never rely on client-side
  filtering for tenant isolation.
- Use `parties` instead of separate customers and suppliers tables.
- Use `products` for stock items, services, manufactured items, subscriptions,
  and non-stock items.
- `stock_movements` is the source of truth for inventory — never store a
  computed quantity as the truth.
- Use `transaction_drafts` and `sync_queue` for limited offline mobile capture.
- Soft-delete with audit logs, but provide a real erasure/anonymisation path for
  verified data-subject requests (see Data protection below).
- Prepare credit-readiness fields early (Section 32), but do not build external
  credit scoring or data sharing until the credit layer's DPIA is complete.

## MVP scope discipline
- Prioritise: sales, stock, parties, customer balances/receivables, dashboards,
  offline capture.
- Do NOT build in the MVP: full accounting, manufacturing, HR, payroll, EBM
  automation, or Mobile Money automation — reserve integration points only.
- Confirm each feature works on a real device build before moving to the next.

## Data protection (Law 058/2021) — build-phase guardrails
- During development use ONLY synthetic/seed data: clearly fake names, contacts,
  and TINs. This keeps the project in Stage 1, with no data-protection
  obligations.
- Do not wire up any flow that ingests real personal data of real people until
  the Section 33 pre-launch compliance gate is satisfied.
- Encrypt the on-device SQLite database (SQLCipher) — never store personal data
  on the device in cleartext.
- Treat health data (e.g. a future pharmacy module) as sensitive — do not enable
  it without Article 11 safeguards.

## Coding style
- Prefer simple, readable Dart and SQL — avoid overengineering.
- Follow standard Dart conventions (Effective Dart); run `dart format`.
- Comment non-obvious logic.
- Make small, reviewable commits with clear messages.
- Plan before implementing, and wait for approval on non-trivial changes.

## Security
- Never expose secrets, service-role keys, passwords, or private API keys in
  app code or in the repository.
- The Flutter app uses only the Supabase anon key, protected by RLS — shipping
  the anon key in a mobile app is expected and safe when RLS is correct. The
  service-role key is server-side only, never in the app.
- Validate and constrain all inputs — assume the client is untrusted.

## Known gotcha
- Rwanda is UTC+2. Dart `DateTime` arithmetic across local/UTC boundaries
  causes silent month-boundary errors. For grouping or comparing local business
  dates, use string-based `YYYY-MM-DD` arithmetic, or be explicit and
  consistent about UTC vs local everywhere.
