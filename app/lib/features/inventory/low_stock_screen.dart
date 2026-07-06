import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inventory/merge_stock_by_product.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class LowStockReportItem {
  const LowStockReportItem({
    required this.productCode,
    required this.productName,
    required this.warehouseName,
    required this.currentQuantity,
    required this.reorderLevel,
  });

  final String productCode;
  final String productName;
  final String warehouseName;
  final double currentQuantity;
  final double reorderLevel;
}

final lowStockProvider = FutureProvider.autoDispose<List<LowStockReportItem>>((
  ref,
) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('vw_current_stock')
      .select(
        'product_id, product_code, product_name, warehouse_name, current_quantity, reorder_level',
      )
      .order('current_quantity');

  return mergeStockRowsByProduct(
        (rows as List<dynamic>).map((row) {
          return ProductStockRow.fromMap(row as Map<String, dynamic>);
        }).toList(),
      )
      .where(
        (row) =>
            row.reorderLevel != null &&
            row.currentQuantity <= row.reorderLevel!,
      )
      .map((row) {
        return LowStockReportItem(
          productCode: row.productCode,
          productName: row.productName,
          warehouseName: row.warehouseName,
          currentQuantity: row.currentQuantity,
          reorderLevel: row.reorderLevel!,
        );
      })
      .toList();
});

/// Full list of products at or below reorder level.
class LowStockScreen extends ConsumerWidget {
  const LowStockScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(lowStockProvider);
    await ref.read(lowStockProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(lowStockProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Low Stock'),
        actions: const [MainMenuNavAction()],
      ),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Could not load low stock items',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(lowStockProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: items.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('All products are above reorder level')),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.35,
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.warning_amber_outlined,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(item.productName),
                        subtitle: Text(
                          '${item.productCode} • ${item.warehouseName}',
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              item.currentQuantity.toStringAsFixed(0),
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              'Reorder ${item.reorderLevel.toStringAsFixed(0)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
