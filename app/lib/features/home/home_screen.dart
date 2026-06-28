import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';

/// Placeholder screen shown after a successful sign-in.
///
/// This exists to prove the auth + session flow end-to-end; real dashboard
/// content comes in later slices.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final email = client.auth.currentUser?.email ?? 'unknown user';

    return Scaffold(
      appBar: AppBar(
        title: const Text('SME-OS'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 64,
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              Text(
                'You are signed in',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(email, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
