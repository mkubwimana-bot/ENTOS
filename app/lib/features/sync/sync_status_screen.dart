import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import '../sales/offline_sale_queue.dart';

class SyncStatusScreen extends ConsumerStatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  ConsumerState<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends ConsumerState<SyncStatusScreen> {
  List<PendingSale> _pending = [];
  bool _loading = true;
  bool _syncing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sales = await ref.read(offlineSaleQueueProvider).list();
    if (!mounted) return;
    setState(() {
      _pending = sales;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    if (_pending.isEmpty || _syncing) return;
    setState(() {
      _syncing = true;
      _message = null;
    });

    final client = ref.read(supabaseClientProvider);
    final queue = ref.read(offlineSaleQueueProvider);
    var synced = 0;
    var stillOffline = false;
    var failed = 0;

    for (final sale in List<PendingSale>.from(_pending)) {
      try {
        await client.rpc(
          'post_sale_draft',
          params: {
            'target_tenant_id': sale.tenantId,
            'target_branch_id': sale.branchId,
            'target_warehouse_id': sale.warehouseId,
            'p_client_reference_id': sale.clientReferenceId,
            'p_sale_type': sale.saleType,
            'p_party_id': sale.partyId,
            'p_notes': sale.notes,
            'p_captured_at': sale.capturedAt.toIso8601String(),
            'p_lines': sale.lines
                .map((l) => {
                      'product_id': l.productId,
                      'quantity': l.quantity,
                      'unit_price': l.unitPrice,
                    })
                .toList(),
          },
        );
        await queue.removeByRef(sale.clientReferenceId);
        synced++;
      } on PostgrestException catch (e) {
        failed++;
        await queue.update(sale.copyWith(lastError: e.message));
      } catch (error) {
        if (isOfflineError(error)) {
          stillOffline = true;
          break;
        }
        failed++;
        await queue.update(
          sale.copyWith(lastError: 'Could not sync. Please try again.'),
        );
      }
    }

    ref.invalidate(offlinePendingCountProvider);
    await _load();
    if (!mounted) return;

    final parts = <String>[];
    if (synced > 0) parts.add('$synced synced');
    if (failed > 0) parts.add('$failed failed');
    if (stillOffline) parts.add('still offline');
    setState(() {
      _syncing = false;
      _message = parts.isEmpty ? 'Nothing to sync.' : '${parts.join(', ')}.';
    });
  }

  Future<void> _delete(PendingSale sale) async {
    await ref.read(offlineSaleQueueProvider).removeByRef(sale.clientReferenceId);
    ref.invalidate(offlinePendingCountProvider);
    await _load();
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status'),
        actions: const [MainMenuNavAction()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_message != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_message!),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'On this phone (${_pending.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed:
                            _pending.isEmpty || _syncing ? null : _syncNow,
                        icon: _syncing
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Sync Now'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sales saved on this device. They reach the server only '
                    'after you tap Sync Now.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (_pending.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text('No sales waiting to sync.'),
                      ),
                    )
                  else
                    ..._pending.map(_buildPendingCard),
                  const Divider(height: 32),
                  _ServerPendingSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildPendingCard(PendingSale sale) {
    final failed = sale.lastError != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  sale.saleType == 'credit' ? 'Credit sale' : 'Cash sale',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  formatRwf(sale.total),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${sale.itemCount} item(s) - captured ${_formatDateTime(sale.capturedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  failed ? Icons.error_outline : Icons.schedule,
                  size: 16,
                  color: failed
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    failed ? sale.lastError! : 'Pending sync',
                    style: TextStyle(
                      color: failed
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (failed)
                  TextButton(
                    onPressed: _syncing ? null : () => _delete(sale),
                    child: const Text('Discard'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only view of drafts the server already knows about
/// (vw_pending_mobile_transactions). Usually empty in the MVP online flow.
class _ServerPendingSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_serverPendingProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'On the server (pending review)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Drafts already uploaded to the server (after syncing, or from other '
          'devices). Your on-device sales above are not counted here until synced.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Text(
            isOfflineError(e)
                ? 'Offline - connect to see server drafts.'
                : 'Could not load server drafts: $e',
          ),
          data: (count) => Text(
            count == 0
                ? 'No server-side pending drafts.'
                : '$count draft(s) pending on the server.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

final _serverPendingProvider = FutureProvider.autoDispose<int>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('vw_pending_mobile_transactions')
      .select('draft_id');
  return (rows as List).length;
});
