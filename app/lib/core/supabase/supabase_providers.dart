import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The shared Supabase client. `Supabase.initialize` must run first (in main).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Emits an event whenever the auth state changes (sign in, sign out, token
/// refresh, initial session). Widgets watch this to react to login/logout.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// True after the user opens a password-recovery deep link from their email.
///
/// The auth stream emits [AuthChangeEvent.passwordRecovery] only once, so we
/// latch this flag until the user finishes setting a new password.
class PasswordRecoveryMode extends Notifier<bool> {
  @override
  bool build() => false;

  void enable() => state = true;

  void clear() => state = false;
}

final passwordRecoveryModeProvider =
    NotifierProvider<PasswordRecoveryMode, bool>(PasswordRecoveryMode.new);
