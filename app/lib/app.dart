import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_gate.dart';
import 'features/sync/offline_auto_sync.dart';

class SmeOsApp extends ConsumerWidget {
  const SmeOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep auto-sync controller alive for the app lifetime.
    ref.watch(offlineAutoSyncProvider);

    return OfflineAutoSyncLifecycle(
      child: MaterialApp(
        title: 'SME-OS',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        ),
        home: const AuthGate(),
      ),
    );
  }
}
