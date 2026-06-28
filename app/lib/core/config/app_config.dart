/// App configuration sourced from `--dart-define` values at build time.
///
/// Pass these when running or building so project values never live in source
/// control, e.g.:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Whether both required Supabase values were provided at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
