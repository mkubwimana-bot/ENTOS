# SME-OS Supabase App Connection Notes

## Purpose

This document explains how the hand-coded Flutter (Dart) app connects to the
SME-OS Supabase backend. The app uses the official `supabase_flutter` package.
This is not a FlutterFlow project.

Supabase will provide:

- authentication
- database tables
- Row-Level Security
- tenant isolation
- storage later if needed
- edge functions later if needed

The Flutter app will provide:

- app screens and widgets
- forms
- navigation
- Supabase queries (via `supabase_flutter`)
- user actions
- mobile-friendly, offline-capable workflows

## Important Security Rule

The Flutter app must use the Supabase `anon public` key only.

The app must never embed or use:

- service role key
- database password
- JWT secret
- Supabase project password

The service role key is powerful and bypasses Row-Level Security. It must stay
private and server-side only. Shipping the `anon public` key inside the mobile
app is expected and safe as long as Row-Level Security is correct on every
tenant table.

## Supabase Project Values Needed

From the Supabase Dashboard (`Project Settings → API`), collect:

- Project URL (e.g. `https://<project-ref>.supabase.co`)
- `anon` `public` API key

## Initializing the Client in Flutter

Initialize Supabase once at app startup, then use the shared client everywhere:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://<project-ref>.supabase.co',
    anonKey: '<anon-public-key>',
  );

  runApp(const MyApp());
}

// Access the shared client anywhere:
final supabase = Supabase.instance.client;
```

Keep the URL and anon key out of source control where practical (for example,
via `--dart-define` build arguments or a config file listed in `.gitignore`),
even though the anon key is safe to ship in the built app.
