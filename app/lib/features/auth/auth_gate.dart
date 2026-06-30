import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';
import 'reset_password_screen.dart';

/// Decides which screen to show based on whether there is an active session.
///
/// Supabase restores any persisted session during `Supabase.initialize`, so
/// `currentSession` is already populated when the app starts. We also watch the
/// auth-state stream so the UI updates immediately on sign-in/sign-out.
///
/// When the user opens a password-reset deep link, Supabase emits
/// [AuthChangeEvent.passwordRecovery] once; we latch that in
/// [passwordRecoveryModeProvider] and show [ResetPasswordScreen] until the new
/// password is saved.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authStateChangesProvider, (previous, next) {
      if (next.value?.event == AuthChangeEvent.passwordRecovery) {
        ref.read(passwordRecoveryModeProvider.notifier).enable();
      }
    });

    final passwordRecovery = ref.watch(passwordRecoveryModeProvider);
    final authState = ref.watch(authStateChangesProvider);
    final session =
        authState.value?.session ??
        ref.read(supabaseClientProvider).auth.currentSession;

    if (passwordRecovery && session != null) {
      return const ResetPasswordScreen();
    }
    if (session == null) {
      return const LoginScreen();
    }
    return const HomeScreen();
  }
}
