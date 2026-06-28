import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';

/// Decides which screen to show based on whether there is an active session.
///
/// Supabase restores any persisted session during `Supabase.initialize`, so
/// `currentSession` is already populated when the app starts. We also watch the
/// auth-state stream so the UI updates immediately on sign-in/sign-out.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    final session =
        authState.value?.session ??
        ref.read(supabaseClientProvider).auth.currentSession;

    if (session == null) {
      return const LoginScreen();
    }
    return const HomeScreen();
  }
}
