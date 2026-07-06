import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/inventory/merge_stock_by_product.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class InventoryValuationItem {
  const InventoryValuationItem({
    required this.productCode,
    required this.productName,
    required this.warehouseName,
    required this.currentQuantity,
    required this.costPrice,
    required this.inventoryValue,
  });

  final String productCode;
  final String productName;
  final String warehouseName;
  final double currentQuantity;
  final double costPrice;
  final double inventoryValue;
}

final inventoryValuationProvider =
    FutureProvider.autoDispose<List<InventoryValuationItem>>((ref) async {
      final client = ref.read(supabaseClientProvider);

      final results = await Future.wait<dynamic>([
        client
            .from('vw_current_stock')
            .select(
              'product_id, product_code, product_name, warehouse_name, current_quantity',
            )
            .order('product_name'),
        client.from('products').select('id, cost_price'),
      ]);

      final costByProductId = <String, double>{};
      for (final row in results[1] as List<dynamic>) {
        final map = row as Map<String, dynamic>;
        costByProductId[map['id'] as String] =
            (map['cost_price'] as num?)?.toDouble() ?? 0;
      }

      final valuationRows = (results[0] as List<dynamic>).map((row) {
        final map = row as Map<String, dynamic>;
        final productId = map['product_id'] as String;
        return ProductValuationRow(
          productId: productId,
          productCode: map['product_code'] as String? ?? '',
          productName: map['product_name'] as String? ?? 'Unnamed product',
          warehouseName:
              map['warehouse_name'] as String? ?? 'Unknown warehouse',
          currentQuantity: (map['current_quantity'] as num?)?.toDouble() ?? 0,
          costPrice: costByProductId[productId] ?? 0,
        );
      }).toList();

      return mergeValuationRowsByProduct(valuationRows)
          .where((row) => row.currentQuantity > 0)
          .map(
            (row) => InventoryValuationItem(
              productCode: row.productCode,
              productName: row.productName,
              warehouseName: row.warehouseName,
              currentQuantity: row.currentQuantity,
              costPrice: row.costPrice,
              inventoryValue: row.inventoryValue,
            ),
          )
          .toList();
    });

class InventoryValuationScreen extends ConsumerWidget {
  const InventoryValuationScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(inventoryValuationProvider);
    await ref.read(inventoryValuationProvider.future);
  }

  String _formatQty(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valuationAsync = ref.watch(inventoryValuationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Valuation'),
        actions: const [MainMenuNavAction()],
      ),
      body: valuationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(inventoryValuationProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          final totalValue = items.fold<double>(
            0,
            (sum, item) => sum + item.inventoryValue,
          );

          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No inventory value to show')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => _refresh(ref),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Card(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Total inventory value: ${formatRwf(totalValue)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  );
                }

                final item = items[index - 1];
                return Card(
                  child: ListTile(
                    title: Text(
                      item.productName,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    subtitle: Text(
                      '${item.productCode} · ${item.warehouseName}\n'
                      'Qty ${_formatQty(item.currentQuantity)} '
                      '@ ${formatRwf(item.costPrice)}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      formatRwf(item.inventoryValue),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
