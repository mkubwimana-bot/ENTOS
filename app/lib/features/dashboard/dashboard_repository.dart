import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard_models.dart';

/// Loads dashboard metrics from Supabase views (RLS filters by tenant).
class DashboardRepository {
  DashboardRepository(this._client);

  final SupabaseClient _client;

  Future<DashboardSummary> fetchSummary() async {
    final today = _formatDate(DateTime.now());

    final results = await Future.wait<dynamic>([
      _client.from('vw_daily_sales').select().eq('invoice_date', today),
      _client.from('vw_customer_balances').select('balance').gt('balance', 0),
      _client
          .from('vw_low_stock')
          .select('product_name, current_quantity, reorder_level')
          .order('current_quantity'),
      _client.from('vw_pending_mobile_transactions').select('draft_id'),
    ]);

    final salesRows = results[0] as List<dynamic>;
    final balanceRows = results[1] as List<dynamic>;
    final lowStockRows = results[2] as List<dynamic>;
    final pendingRows = results[3] as List<dynamic>;

    var todaySales = 0.0;
    var todayInvoiceCount = 0;
    for (final row in salesRows) {
      final map = row as Map<String, dynamic>;
      todaySales += _asDouble(map['total_sales']);
      todayInvoiceCount += _asInt(map['invoice_count']);
    }

    var moneyOwed = 0.0;
    for (final row in balanceRows) {
      moneyOwed += _asDouble((row as Map<String, dynamic>)['balance']);
    }

    final lowStockProducts = lowStockRows
        .map((row) {
          final map = row as Map<String, dynamic>;
          return LowStockItem(
            productName: map['product_name'] as String? ?? 'Unknown product',
            currentQuantity: _asDouble(map['current_quantity']),
            reorderLevel: _asDouble(map['reorder_level']),
          );
        })
        .toList();

    return DashboardSummary(
      todaySales: todaySales,
      todayInvoiceCount: todayInvoiceCount,
      moneyOwed: moneyOwed,
      lowStockCount: lowStockProducts.length,
      lowStockProducts: lowStockProducts.take(5).toList(),
      pendingMobileCount: pendingRows.length,
    );
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }
}
