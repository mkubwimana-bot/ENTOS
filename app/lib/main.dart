import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/storage/secure_local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    AppConfig.isConfigured,
    'Missing Supabase configuration. Run the app with --dart-define, e.g.:\n'
    '  flutter run \\\n'
    '    --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \\\n'
    '    --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY',
  );

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // The anon/publishable key is safe to ship in the app; RLS protects data.
    // Never put the service-role key here.
    publishableKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: SecureLocalStorage(),
    ),
  );

  runApp(const ProviderScope(child: SmeOsApp()));
}
