# SME-OS Supabase App Connection Notes

## Purpose

This document explains how FlutterFlow will connect to the SME-OS Supabase backend.

Supabase will provide:

- authentication
- database tables
- Row-Level Security
- tenant isolation
- storage later if needed
- edge functions later if needed

FlutterFlow will provide:

- app screens
- forms
- navigation
- Supabase queries
- user actions
- mobile-friendly workflows

## Important Security Rule

FlutterFlow must use the Supabase `anon public` key.

FlutterFlow must never use:

- service role key
- database password
- JWT secret
- Supabase project password

The service role key is powerful and bypasses Row-Level Security. It must stay private.

## Supabase Project Values Needed

From Supabase Dashboard:

```text
Project Settings → API