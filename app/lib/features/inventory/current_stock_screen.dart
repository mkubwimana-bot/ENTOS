import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class CurrentStockItem {
  const CurrentStockItem({
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
  final double? reorderLevel;

  bool get isLowStock =>
      reorderLevel != null && currentQuantity <= reorderLevel!;
}

final currentStockProvider = FutureProvider.autoDispose<List<CurrentStockItem>>((
  ref,
) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('vw_current_stock')
      .select(
        'product_code, product_name, warehouse_name, current_quantity, reorder_level',
      )
      .order('product_name');

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return CurrentStockItem(
      productCode: map['product_code'] as String? ?? '',
      productName: map['product_name'] as String? ?? 'Unnamed product',
      warehouseName: map['warehouse_name'] as String? ?? 'Unknown warehouse',
      currentQuantity: (map['current_quantity'] as num?)?.toDouble() ?? 0,
      reorderLevel: (map['reorder_level'] as num?)?.toDouble(),
    );
  }).toList();
});

class CurrentStockScreen extends ConsumerWidget {
  const CurrentStockScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(currentStockProvider);
    await ref.read(currentStockProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(currentStockProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Current Stock'),
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
                  'Could not load stock',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(currentStockProvider),
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
                    Center(child: Text('No stock movements recorded yet')),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final theme = Theme.of(context);
                    return Card(
                      color: item.isLowStock
                          ? theme.colorScheme.errorContainer.withValues(
                              alpha: 0.35,
                            )
                          : null,
                      child: ListTile(
                        leading: Icon(
                          item.isLowStock
                              ? Icons.warning_amber_outlined
                              : Icons.inventory_outlined,
                          color: item.isLowStock
                              ? theme.colorScheme.error
                              : null,
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
                            if (item.reorderLevel != null)
                              Text(
                                'Reorder ${item.reorderLevel!.toStringAsFixed(0)}',
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
