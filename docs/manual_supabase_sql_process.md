# Manual Supabase SQL Process

Because this project is being developed without Docker, SQL migrations are executed manually in Supabase Cloud.

## Process

1. Open the migration file in Cursor.
2. Review the SQL carefully.
3. Open Supabase Dashboard.
4. Go to SQL Editor.
5. Paste the full SQL migration.
6. Run the SQL.
7. If successful, update `docs/deployment_log.md`.
8. Commit the migration file and deployment log to GitHub.

## Rules

- Never run SQL that has not been saved in the migration folder.
- Never edit tables manually without updating the migration file.
- Never commit database passwords, API secret keys, or service role keys.
- Always test with development project first.
- Production project will be created later.