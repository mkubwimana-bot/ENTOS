import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inventory/merge_stock_by_product.dart';
import '../../core/inventory/product_filter_widgets.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import '../../core/widgets/report_period_filter.dart';

class CurrentStockItem {
  const CurrentStockItem({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.warehouseName,
    required this.currentQuantity,
    required this.reorderLevel,
  });

  final String productId;
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
        'product_id, product_code, product_name, warehouse_name, current_quantity, reorder_level',
      )
      .order('product_name');

  return mergeStockRowsByProduct(
    (rows as List<dynamic>).map((row) {
      return ProductStockRow.fromMap(row as Map<String, dynamic>);
    }).toList(),
  ).map((row) {
    return CurrentStockItem(
      productId: row.productId,
      productCode: row.productCode,
      productName: row.productName,
      warehouseName: row.warehouseName,
      currentQuantity: row.currentQuantity,
      reorderLevel: row.reorderLevel,
    );
  }).toList();
});

class CurrentStockScreen extends ConsumerStatefulWidget {
  const CurrentStockScreen({super.key});

  @override
  ConsumerState<CurrentStockScreen> createState() =>
      _CurrentStockScreenState();
}

class _CurrentStockScreenState extends ConsumerState<CurrentStockScreen> {
  String? _selectedProductId;

  Future<void> _refresh() async {
    ref.invalidate(currentStockProvider);
    await ref.read(currentStockProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(currentStockProvider);
    final period = ref.watch(stockPeriodProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Current Stock Count'),
        actions: const [MainMenuNavAction()],
      ),
      body: Column(
        children: [
          const StockPeriodBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: ProductFilterDropdown(
              selectedProductId: _selectedProductId,
              onChanged: (value) => setState(() => _selectedProductId = value),
            ),
          ),
          if (_selectedProductId != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ProductPeriodSummaryCard(
                productId: _selectedProductId!,
                start: period.range.start,
                end: period.range.end,
              ),
            ),
          ],
          Expanded(
            child: stockAsync.when(
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
              data: (items) {
                final filtered = _selectedProductId == null
                    ? items
                    : items
                        .where((i) => i.productId == _selectedProductId)
                        .toList();

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: filtered.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text('No stock movements recorded yet'),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final theme = Theme.of(context);
                            return Card(
                              color: item.isLowStock
                                  ? theme.colorScheme.errorContainer
                                      .withValues(alpha: 0.35)
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
