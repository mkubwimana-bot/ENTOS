import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/tenant/active_tenant.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import 'edit_product_screen.dart';
import 'new_product_screen.dart';

class ProductListItem {
  const ProductListItem({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.sellingPrice,
    required this.status,
    required this.isInventoryTracked,
  });

  final String productId;
  final String productCode;
  final String productName;
  final double sellingPrice;
  final String status;
  final bool isInventoryTracked;
}

final productListProvider = FutureProvider.autoDispose<List<ProductListItem>>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final tenantId = (await resolveActiveTenantMembership(client)).tenantId;

  final rows = await client
      .from('products')
      .select(
        'id, product_code, product_name, selling_price, status, is_inventory_tracked',
      )
      .eq('tenant_id', tenantId)
      .order('product_name');

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return ProductListItem(
      productId: map['id'] as String,
      productCode: map['product_code'] as String? ?? '',
      productName: map['product_name'] as String? ?? 'Unnamed product',
      sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'unknown',
      isInventoryTracked: map['is_inventory_tracked'] as bool? ?? false,
    );
  }).toList();
});

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(productListProvider);
    await ref.read(productListProvider.future);
  }

  List<ProductListItem> _filterProducts(List<ProductListItem> products) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return products;
    return products
        .where(
          (p) =>
              p.productName.toLowerCase().contains(query) ||
              p.productCode.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: const [MainMenuNavAction()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(builder: (_) => const NewProductScreen()),
          );
          if (created == true) {
            ref.invalidate(productListProvider);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('New Product'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search by name or code',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => _search = value),
              trailing: _search.isEmpty
                  ? null
                  : [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      ),
                    ],
            ),
          ),
          Expanded(
            child: productsAsync.when(
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
                        'Could not load products',
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
                        onPressed: () => ref.invalidate(productListProvider),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (products) {
                final filtered = _filterProducts(products);
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: filtered.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.3,
                            ),
                            Center(
                              child: Text(
                                _search.isEmpty
                                    ? 'No products yet'
                                    : 'No products match your search',
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final product = filtered[index];
                            return Card(
                              child: ListTile(
                                title: Text(product.productName),
                                subtitle: Text(
                                  '${product.productCode} • ${product.isInventoryTracked ? 'Stock item' : 'Service'} • ${product.status}',
                                ),
                                trailing: Text(
                                  formatRwf(product.sellingPrice),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                onTap: () async {
                                  final updated = await Navigator.of(context)
                                      .push<bool>(
                                        MaterialPageRoute<bool>(
                                          builder: (_) => EditProductScreen(
                                            productId: product.productId,
                                          ),
                                        ),
                                      );
                                  if (updated == true) {
                                    ref.invalidate(productListProvider);
                                  }
                                },
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
