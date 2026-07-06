import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _StockProductOption {
  const _StockProductOption({
    required this.id,
    required this.name,
    required this.costPrice,
  });

  final String id;
  final String name;
  final double? costPrice;
}

class _StockAdjustmentContext {
  const _StockAdjustmentContext({
    required this.tenantId,
    required this.userId,
    required this.branchId,
    required this.warehouseId,
    required this.products,
  });

  final String tenantId;
  final String userId;
  final String branchId;
  final String warehouseId;
  final List<_StockProductOption> products;
}

final stockAdjustmentContextProvider =
    FutureProvider.autoDispose<_StockAdjustmentContext>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be signed in.');

  final membershipRows = await client
      .from('user_tenants')
      .select('tenant_id, default_branch_id, membership_status')
      .eq('user_id', userId)
      .eq('membership_status', 'active')
      .limit(1);
  if ((membershipRows as List).isEmpty) {
    throw Exception('No active tenant membership found for this user.');
  }

  final membership = membershipRows.first;
  final tenantId = membership['tenant_id'] as String;
  var branchId = membership['default_branch_id'] as String?;

  if (branchId == null) {
    final branchRows = await client
        .from('branches')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('is_default', true)
        .limit(1);
    if ((branchRows as List).isEmpty) {
      throw Exception('No default branch found for tenant.');
    }
    branchId = branchRows.first['id'] as String;
  }

  final warehouseRows = await client
      .from('warehouses')
      .select('id')
      .eq('tenant_id', tenantId)
      .eq('branch_id', branchId)
      .eq('is_default', true)
      .limit(1);
  if ((warehouseRows as List).isEmpty) {
    throw Exception('No default warehouse found for branch.');
  }
  final warehouseId = warehouseRows.first['id'] as String;

  final productRows = await client
      .from('products')
      .select('id, product_name, cost_price, is_inventory_tracked')
      .eq('status', 'active')
      .eq('is_inventory_tracked', true)
      .order('product_name');

  final products = (productRows as List<dynamic>)
      .map((row) {
        final map = row as Map<String, dynamic>;
        return _StockProductOption(
          id: map['id'] as String,
          name: map['product_name'] as String? ?? 'Unnamed product',
          costPrice: (map['cost_price'] as num?)?.toDouble(),
        );
      })
      .toList();

  return _StockAdjustmentContext(
    tenantId: tenantId,
    userId: userId,
    branchId: branchId,
    warehouseId: warehouseId,
    products: products,
  );
});

/// Use the warehouse where this product already has movement history so
/// adjustments merge with imported stock instead of opening a second row.
Future<({String branchId, String warehouseId})> _resolveStockLocation({
  required SupabaseClient client,
  required String tenantId,
  required String defaultBranchId,
  required String defaultWarehouseId,
  required String productId,
}) async {
  final rows = await client
      .from('stock_movements')
      .select('warehouse_id')
      .eq('tenant_id', tenantId)
      .eq('product_id', productId)
      .isFilter('voided_at', null);

  final movements = rows as List<dynamic>;
  if (movements.isEmpty) {
    return (branchId: defaultBranchId, warehouseId: defaultWarehouseId);
  }

  final counts = <String, int>{};
  for (final row in movements) {
    final map = row as Map<String, dynamic>;
    final warehouseId = map['warehouse_id'] as String;
    counts[warehouseId] = (counts[warehouseId] ?? 0) + 1;
  }

  final warehouseId = counts.entries
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;

  if (warehouseId == defaultWarehouseId) {
    return (branchId: defaultBranchId, warehouseId: defaultWarehouseId);
  }

  final warehouseRows = await client
      .from('warehouses')
      .select('branch_id')
      .eq('id', warehouseId)
      .limit(1);
  if ((warehouseRows as List).isEmpty) {
    return (branchId: defaultBranchId, warehouseId: defaultWarehouseId);
  }

  final branchId = warehouseRows.first['branch_id'] as String;
  return (branchId: branchId, warehouseId: warehouseId);
}

class StockAdjustmentScreen extends ConsumerStatefulWidget {
  const StockAdjustmentScreen({super.key});

  @override
  ConsumerState<StockAdjustmentScreen> createState() =>
      _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends ConsumerState<StockAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();

  String? _selectedProductId;
  bool _isStockIn = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit(_StockAdjustmentContext adjustmentContext) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) {
      setState(() => _errorMessage = 'Select a product.');
      return;
    }

    final quantity = double.parse(_quantityController.text.trim());
    final product =
        adjustmentContext.products.firstWhere((p) => p.id == _selectedProductId);
    final reason = _reasonController.text.trim();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final client = ref.read(supabaseClientProvider);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final unitCost = product.costPrice;
      final totalCost = unitCost == null ? null : unitCost * quantity;
      final location = await _resolveStockLocation(
        client: client,
        tenantId: adjustmentContext.tenantId,
        defaultBranchId: adjustmentContext.branchId,
        defaultWarehouseId: adjustmentContext.warehouseId,
        productId: product.id,
      );

      await client.from('stock_movements').insert({
        'tenant_id': adjustmentContext.tenantId,
        'branch_id': location.branchId,
        'warehouse_id': location.warehouseId,
        'product_id': product.id,
        'movement_date': today,
        'movement_type': 'adjustment',
        'quantity_in': _isStockIn ? quantity : 0,
        'quantity_out': _isStockIn ? 0 : quantity,
        'unit_cost': unitCost,
        'total_cost': totalCost,
        'reason': reason.isEmpty ? 'Manual stock adjustment' : reason,
        'created_by': adjustmentContext.userId,
      });

      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not save adjustment. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _validateQuantity(String? value) {
    final text = value?.trim() ?? '';
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter quantity';
    if (parsed <= 0) return 'Quantity must be greater than zero';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final contextAsync = ref.watch(stockAdjustmentContextProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Adjustment'),
        actions: const [MainMenuNavAction()],
      ),
      body: contextAsync.when(
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
                  onPressed: () => ref.invalidate(stockAdjustmentContextProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (adjustmentContext) {
          if (adjustmentContext.products.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No inventory-tracked products found.'),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Stock In')),
                      ButtonSegment(value: false, label: Text('Stock Out')),
                    ],
                    selected: {_isStockIn},
                    onSelectionChanged: _isSubmitting
                        ? null
                        : (selection) {
                            setState(() => _isStockIn = selection.first);
                          },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedProductId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Product',
                      border: OutlineInputBorder(),
                    ),
                    items: adjustmentContext.products
                        .map(
                          (product) => DropdownMenuItem(
                            value: product.id,
                            child: Text(
                              product.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _selectedProductId = value),
                    validator: (value) =>
                        value == null ? 'Select a product' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_isSubmitting,
                    validator: _validateQuantity,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    enabled: !_isSubmitting,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => _submit(adjustmentContext),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Adjustment'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
