import 'package:supabase_flutter/supabase_flutter.dart';

import '../sales/offline_sale_queue.dart';

/// Result of syncing locally queued offline sales to the server.
class OfflineSyncResult {
  const OfflineSyncResult({
    required this.synced,
    required this.failed,
    required this.stillOffline,
  });

  final int synced;
  final int failed;
  final bool stillOffline;

  bool get hasWork => synced > 0 || failed > 0 || stillOffline;
}

/// Posts pending local sales via post_sale_draft (shared by Sync Status and auto-sync).
Future<OfflineSyncResult> syncOfflineSales({
  required SupabaseClient client,
  required OfflineSaleQueue queue,
}) async {
  final pending = await queue.list();
  if (pending.isEmpty) {
    return const OfflineSyncResult(synced: 0, failed: 0, stillOffline: false);
  }

  var synced = 0;
  var failed = 0;
  var stillOffline = false;

  for (final sale in List<PendingSale>.from(pending)) {
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

  return OfflineSyncResult(
    synced: synced,
    failed: failed,
    stillOffline: stillOffline,
  );
}

String formatSyncResultMessage(OfflineSyncResult result) {
  final parts = <String>[];
  if (result.synced > 0) parts.add('${result.synced} synced');
  if (result.failed > 0) parts.add('${result.failed} failed');
  if (result.stillOffline) parts.add('still offline');
  if (parts.isEmpty) return 'Nothing to sync.';
  return '${parts.join(', ')}.';
}
