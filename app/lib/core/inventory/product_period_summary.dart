import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';
import '../widgets/report_period_filter.dart';

class ProductPeriodSummary {
  const ProductPeriodSummary({
    required this.quantityAtHand,
    required this.purchasedInPeriod,
    required this.soldInPeriod,
    required this.salesValue,
    required this.grossProfit,
  });

  final double quantityAtHand;
  final double purchasedInPeriod;
  final double soldInPeriod;
  final double salesValue;
  final double grossProfit;
}

class ProductFilterOption {
  const ProductFilterOption({
    required this.id,
    required this.name,
    required this.code,
  });

  final String id;
  final String name;
  final String code;
}

final productFilterOptionsProvider =
    FutureProvider.autoDispose<List<ProductFilterOption>>((ref) async {
      final rows = await ref
          .read(supabaseClientProvider)
          .from('products')
          .select('id, product_name, product_code')
          .eq('status', 'active')
          .order('product_name');

      return (rows as List<dynamic>).map((row) {
        final map = row as Map<String, dynamic>;
        return ProductFilterOption(
          id: map['id'] as String,
          name: map['product_name'] as String? ?? 'Unnamed product',
          code: map['product_code'] as String? ?? '',
        );
      }).toList();
    });

typedef ProductPeriodParams = ({
  String productId,
  DateTime start,
  DateTime end,
});

final productPeriodSummaryProvider = FutureProvider.autoDispose
    .family<ProductPeriodSummary, ProductPeriodParams>((ref, params) async {
      final client = ref.read(supabaseClientProvider);
      final startIso = formatIsoDate(params.start);
      final endIso = formatIsoDate(params.end);

      final results = await Future.wait<dynamic>([
        client
            .from('vw_current_stock')
            .select('current_quantity')
            .eq('product_id', params.productId),
        client
            .from('stock_movements')
            .select('movement_type, quantity_in, quantity_out')
            .eq('product_id', params.productId)
            .isFilter('voided_at', null)
            .gte('movement_date', startIso)
            .lte('movement_date', endIso),
        client
            .from('invoice_lines')
            .select(
              'line_total, quantity, cost_price_snapshot, invoices!inner(invoice_date, status, voided_at)',
            )
            .eq('product_id', params.productId)
            .eq('invoices.status', 'posted')
            .isFilter('invoices.voided_at', null)
            .gte('invoices.invoice_date', startIso)
            .lte('invoices.invoice_date', endIso),
      ]);

      double quantityAtHand = 0;
      for (final row in results[0] as List<dynamic>) {
        final map = row as Map<String, dynamic>;
        quantityAtHand += (map['current_quantity'] as num?)?.toDouble() ?? 0;
      }

      double purchased = 0;
      double sold = 0;
      for (final row in results[1] as List<dynamic>) {
        final map = row as Map<String, dynamic>;
        final type = map['movement_type'] as String? ?? '';
        if (type == 'purchase') {
          purchased += (map['quantity_in'] as num?)?.toDouble() ?? 0;
        } else if (type == 'sale') {
          sold += (map['quantity_out'] as num?)?.toDouble() ?? 0;
        }
      }

      double salesValue = 0;
      double costTotal = 0;
      for (final row in results[2] as List<dynamic>) {
        final map = row as Map<String, dynamic>;
        final qty = (map['quantity'] as num?)?.toDouble() ?? 0;
        final lineTotal = (map['line_total'] as num?)?.toDouble() ?? 0;
        final costSnapshot =
            (map['cost_price_snapshot'] as num?)?.toDouble() ?? 0;
        salesValue += lineTotal;
        costTotal += costSnapshot * qty;
      }

      return ProductPeriodSummary(
        quantityAtHand: quantityAtHand,
        purchasedInPeriod: purchased,
        soldInPeriod: sold,
        salesValue: salesValue,
        grossProfit: salesValue - costTotal,
      );
    });
