import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether an error looks like a connectivity failure (so callers can fall back
/// to on-device data/queueing) rather than a validation or server rejection.
bool isOfflineError(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection closed') ||
      text.contains('connection refused') ||
      text.contains('network is unreachable') ||
      text.contains('timed out');
}

/// One line item of a queued (unsynced) sale.
class PendingSaleLine {
  const PendingSaleLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;

  double get lineTotal => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
      };

  factory PendingSaleLine.fromJson(Map<String, dynamic> json) => PendingSaleLine(
        productId: json['product_id'] as String,
        productName: json['product_name'] as String? ?? 'Product',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      );
}

/// A sale captured on-device that still needs to be posted to Supabase.
class PendingSale {
  const PendingSale({
    required this.clientReferenceId,
    required this.tenantId,
    required this.branchId,
    required this.warehouseId,
    required this.saleType,
    required this.partyId,
    required this.notes,
    required this.capturedAt,
    required this.lines,
    this.lastError,
  });

  final String clientReferenceId;
  final String tenantId;
  final String branchId;
  final String warehouseId;
  final String saleType;
  final String? partyId;
  final String? notes;
  final DateTime capturedAt;
  final List<PendingSaleLine> lines;

  /// Last failure reason from a sync attempt (null while simply pending).
  final String? lastError;

  double get total => lines.fold<double>(0, (sum, l) => sum + l.lineTotal);
  int get itemCount => lines.length;

  PendingSale copyWith({String? lastError, bool clearError = false}) {
    return PendingSale(
      clientReferenceId: clientReferenceId,
      tenantId: tenantId,
      branchId: branchId,
      warehouseId: warehouseId,
      saleType: saleType,
      partyId: partyId,
      notes: notes,
      capturedAt: capturedAt,
      lines: lines,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => {
        'client_reference_id': clientReferenceId,
        'tenant_id': tenantId,
        'branch_id': branchId,
        'warehouse_id': warehouseId,
        'sale_type': saleType,
        'party_id': partyId,
        'notes': notes,
        'captured_at': capturedAt.toIso8601String(),
        'lines': lines.map((l) => l.toJson()).toList(),
        'last_error': lastError,
      };

  factory PendingSale.fromJson(Map<String, dynamic> json) => PendingSale(
        clientReferenceId: json['client_reference_id'] as String,
        tenantId: json['tenant_id'] as String,
        branchId: json['branch_id'] as String,
        warehouseId: json['warehouse_id'] as String,
        saleType: json['sale_type'] as String? ?? 'cash',
        partyId: json['party_id'] as String?,
        notes: json['notes'] as String?,
        capturedAt: DateTime.tryParse(json['captured_at'] as String? ?? '') ??
            DateTime.now(),
        lines: (json['lines'] as List<dynamic>? ?? [])
            .map((e) => PendingSaleLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        lastError: json['last_error'] as String?,
      );
}

/// Persists unsynced sales in encrypted on-device storage
/// (flutter_secure_storage), as a single JSON list under one key.
class OfflineSaleQueue {
  OfflineSaleQueue({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _key = 'sme_os.offline.sales';

  Future<List<PendingSale>> list() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => PendingSale.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<int> count() async => (await list()).length;

  Future<void> _writeAll(List<PendingSale> sales) async {
    final encoded = jsonEncode(sales.map((s) => s.toJson()).toList());
    await _storage.write(key: _key, value: encoded);
  }

  Future<void> add(PendingSale sale) async {
    final sales = await list();
    sales.add(sale);
    await _writeAll(sales);
  }

  Future<void> removeByRef(String clientReferenceId) async {
    final sales = await list();
    sales.removeWhere((s) => s.clientReferenceId == clientReferenceId);
    await _writeAll(sales);
  }

  Future<void> update(PendingSale sale) async {
    final sales = await list();
    final index = sales
        .indexWhere((s) => s.clientReferenceId == sale.clientReferenceId);
    if (index >= 0) {
      sales[index] = sale;
      await _writeAll(sales);
    }
  }

  /// Generates a client reference id that is unique per device/user and stable
  /// across retries once assigned at capture time.
  static String newClientReferenceId(String userId) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(1 << 32).toRadixString(16);
    return '$userId-$micros-$rand';
  }
}

final offlineSaleQueueProvider = Provider<OfflineSaleQueue>((ref) {
  return OfflineSaleQueue();
});

/// Number of sales still waiting to be synced. Invalidate after enqueue/sync.
final offlinePendingCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.read(offlineSaleQueueProvider).count();
});
