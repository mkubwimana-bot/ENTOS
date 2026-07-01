import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import '../dashboard/dashboard_providers.dart';
import '../sales/offline_sale_queue.dart';
import 'offline_sync_service.dart';

/// Global messenger so auto-sync can show feedback without a BuildContext.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Keeps auto-sync alive for the whole signed-in session (not tied to HomeScreen).
final offlineAutoSyncProvider = Provider<OfflineAutoSyncController>((ref) {
  ref.keepAlive();
  final controller = OfflineAutoSyncController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Call after enqueueing an offline sale or returning to Home.
void requestOfflineAutoSync(WidgetRef ref) {
  final controller = ref.read(offlineAutoSyncProvider);
  unawaited(controller.ensurePolling());
  controller.scheduleSync(showFeedback: true);
}

class OfflineAutoSyncController {
  OfflineAutoSyncController(this._ref) {
    _ref.listen(authStateChangesProvider, (previous, next) {
      final session = next.asData?.value.session;
      if (session != null) {
        _start();
      } else {
        _stop();
      }
    });

    if (_ref.read(supabaseClientProvider).auth.currentSession != null) {
      _start();
    }
  }

  final Ref _ref;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;
  Timer? _pollTimer;
  bool _syncing = false;
  int _retryCount = 0;

  static const _debounceDelay = Duration(milliseconds: 800);
  static const _retryDelay = Duration(seconds: 3);
  static const _pollInterval = Duration(seconds: 10);
  static const _maxRetries = 8;

  void _start() {
    if (_connectivitySub != null) return;
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_onConnectivity);
    unawaited(ensurePolling());
    scheduleSync();
  }

  void _stop() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _retryCount = 0;
  }

  void dispose() => _stop();

  void onAppResumed() => scheduleSync();

  void _onConnectivity(List<ConnectivityResult> results) {
    if (_isOffline(results)) {
      _retryCount = 0;
      return;
    }
    scheduleSync(showFeedback: true);
  }

  bool _isOffline(List<ConnectivityResult> results) {
    if (results.isEmpty) return true;
    return results.every((r) => r == ConnectivityResult.none);
  }

  void scheduleSync({bool showFeedback = false}) {
    unawaited(ensurePolling());
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      unawaited(_trySync(showFeedback: showFeedback));
    });
  }

  /// Starts periodic sync attempts while the local queue has pending sales.
  Future<void> ensurePolling() async {
    final count = await _ref.read(offlineSaleQueueProvider).count();
    if (count > 0) {
      _pollTimer ??= Timer.periodic(_pollInterval, (_) {
        scheduleSync();
      });
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _trySync({required bool showFeedback}) async {
    if (_syncing) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (_isOffline(connectivity)) {
      await ensurePolling();
      return;
    }

    final queue = _ref.read(offlineSaleQueueProvider);
    final count = await queue.count();
    if (count == 0) {
      _retryCount = 0;
      await ensurePolling();
      return;
    }

    _syncing = true;
    try {
      final client = _ref.read(supabaseClientProvider);

      // Session may be stale after extended offline use.
      try {
        await client.auth.refreshSession();
      } catch (_) {}

      final result = await syncOfflineSales(client: client, queue: queue);
      _ref.invalidate(offlinePendingCountProvider);
      _ref.invalidate(dashboardSummaryProvider);

      if (result.stillOffline && _retryCount < _maxRetries) {
        _retryCount++;
        _debounceTimer?.cancel();
        _debounceTimer = Timer(_retryDelay, () {
          unawaited(_trySync(showFeedback: showFeedback));
        });
        return;
      }

      // Retry when items remain (e.g. connectivity_plus said online but RPC failed).
      final remaining = await queue.count();
      if (remaining > 0 &&
          result.synced == 0 &&
          result.failed > 0 &&
          _retryCount < _maxRetries) {
        _retryCount++;
        _debounceTimer?.cancel();
        _debounceTimer = Timer(_retryDelay, () {
          unawaited(_trySync(showFeedback: showFeedback));
        });
        return;
      }

      if (result.synced > 0) {
        _retryCount = 0;
        if (showFeedback) {
          final label = result.synced == 1
              ? '1 offline sale synced'
              : '${result.synced} offline sales synced';
          rootScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(label)),
          );
        }
      } else if (!result.stillOffline) {
        _retryCount = 0;
      }
    } finally {
      _syncing = false;
      await ensurePolling();
    }
  }
}

/// Wires app lifecycle resume to the auto-sync controller.
class OfflineAutoSyncLifecycle extends ConsumerStatefulWidget {
  const OfflineAutoSyncLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<OfflineAutoSyncLifecycle> createState() =>
      _OfflineAutoSyncLifecycleState();
}

class _OfflineAutoSyncLifecycleState extends ConsumerState<OfflineAutoSyncLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(offlineAutoSyncProvider).onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
