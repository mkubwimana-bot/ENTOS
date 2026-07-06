import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inventory/merge_stock_by_product.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class StockCheckItem {
  const StockCheckItem({
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

final stockCheckCatalogProvider = FutureProvider.autoDispose<List<StockCheckItem>>((
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
    return StockCheckItem(
      productCode: row.productCode,
      productName: row.productName,
      warehouseName: row.warehouseName,
      currentQuantity: row.currentQuantity,
      reorderLevel: row.reorderLevel,
    );
  }).toList();
});

class StockCheckScreen extends ConsumerStatefulWidget {
  const StockCheckScreen({super.key});

  @override
  ConsumerState<StockCheckScreen> createState() => _StockCheckScreenState();
}

class _StockCheckScreenState extends ConsumerState<StockCheckScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StockCheckItem> _filter(List<StockCheckItem> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((item) {
      return item.productName.toLowerCase().contains(q) ||
          item.productCode.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(stockCheckCatalogProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Check'),
        actions: const [MainMenuNavAction()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search by product name or code',
              leading: const Icon(Icons.search),
              trailing: _query.isEmpty
                  ? null
                  : [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                    ],
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: catalogAsync.when(
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
                        'Could not load stock: $error',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(stockCheckCatalogProvider),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (items) {
                final filtered = _filter(items);
                if (_query.trim().isNotEmpty && filtered.isEmpty) {
                  return const Center(child: Text('No matching products'));
                }
                if (items.isEmpty) {
                  return const Center(child: Text('No stock recorded yet'));
                }
                if (_query.trim().isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Type a product name or code to check available stock.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(stockCheckCatalogProvider);
                    await ref.read(stockCheckCatalogProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
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
                                : theme.colorScheme.primary,
                          ),
                          title: Text(item.productName),
                          subtitle: Text(
                            '${item.productCode} · ${item.warehouseName}',
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                item.currentQuantity.toStringAsFixed(0),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: item.isLowStock
                                      ? theme.colorScheme.error
                                      : null,
                                ),
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
