# Cursor Prompt: Database Design

You are helping me build SME-OS, a Rwanda-focused multi-tenant SaaS for SMEs.

Generate PostgreSQL/Supabase SQL for the requested table or module.

Rules:

- Use UUID primary keys.

- Use tenant_id on all tenant-owned business tables.

- Add created_at and updated_at where appropriate.

- Add soft delete fields where appropriate.

- Add foreign keys.

- Add useful indexes.

- Add check constraints for status fields where useful.

- Keep the design MVP-friendly.

- Do not overengineer.

- Explain the SQL after generating it using Access/VBA analogies.