import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/tenant/active_tenant.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import '../../core/widgets/quantity_line_pricing_fields.dart';
import '../../core/widgets/transaction_date_field.dart';

String _unitCodeFromProductRow(Map<String, dynamic> map) {
  final unit = map['product_units'] as Map<String, dynamic>?;
  return unit?['unit_code'] as String? ?? 'unit';
}

class _PurchaseContext {
  const _PurchaseContext({
    required this.tenantId,
    required this.userId,
    required this.branchId,
    required this.warehouseId,
    required this.products,
    required this.suppliers,
  });

  final String tenantId;
  final String userId;
  final String branchId;
  final String warehouseId;
  final List<_PurchaseProductOption> products;
  final List<_PurchaseSupplierOption> suppliers;
}

class _PurchaseProductOption {
  const _PurchaseProductOption({
    required this.id,
    required this.name,
    required this.unitCode,
    required this.costPrice,
  });

  final String id;
  final String name;
  final String unitCode;
  final double? costPrice;
}

class _PurchaseSupplierOption {
  const _PurchaseSupplierOption({required this.id, required this.name});

  final String id;
  final String name;
}

final newPurchaseContextProvider =
    FutureProvider.autoDispose<_PurchaseContext>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final membership = await resolveActiveTenantMembership(client);
  final tenantId = membership.tenantId;
  final userId = client.auth.currentUser!.id;
  final branchId = await resolveDefaultBranchId(
    client: client,
    tenantId: tenantId,
    defaultBranchId: membership.defaultBranchId,
  );
  final warehouseId = await resolveDefaultWarehouseId(
    client: client,
    tenantId: tenantId,
    branchId: branchId,
  );

  final results = await Future.wait<dynamic>([
    client
        .from('products')
        .select(
          'id, product_name, cost_price, is_inventory_tracked, product_units(unit_code)',
        )
        .eq('tenant_id', tenantId)
        .eq('status', 'active')
        .eq('is_inventory_tracked', true)
        .order('product_name'),
    client
        .from('party_type_links')
        .select('parties(id, party_name, status), party_types(type_code)')
        .eq('tenant_id', tenantId),
  ]);

  final productRows = results[0] as List<dynamic>;
  final supplierLinkRows = results[1] as List<dynamic>;

  final products = productRows
      .map((row) {
        final map = row as Map<String, dynamic>;
        return _PurchaseProductOption(
          id: map['id'] as String,
          name: map['product_name'] as String? ?? 'Unnamed product',
          unitCode: _unitCodeFromProductRow(map),
          costPrice: (map['cost_price'] as num?)?.toDouble(),
        );
      })
      .toList();

  final suppliers = <_PurchaseSupplierOption>[];
  final seenSupplierIds = <String>{};
  for (final row in supplierLinkRows) {
    final map = row as Map<String, dynamic>;
    final partyTypes = map['party_types'] as Map<String, dynamic>?;
    if (partyTypes?['type_code'] != 'supplier') continue;
    final party = map['parties'] as Map<String, dynamic>?;
    if (party == null) continue;
    if ((party['status'] as String?) != 'active') continue;
    final id = party['id'] as String?;
    if (id == null || seenSupplierIds.contains(id)) continue;
    seenSupplierIds.add(id);
    suppliers.add(
      _PurchaseSupplierOption(
        id: id,
        name: party['party_name'] as String? ?? 'Unnamed supplier',
      ),
    );
  }
  suppliers.sort((a, b) => a.name.compareTo(b.name));

  return _PurchaseContext(
    tenantId: tenantId,
    userId: userId,
    branchId: branchId,
    warehouseId: warehouseId,
    products: products,
    suppliers: suppliers,
  );
});

class NewPurchaseScreen extends ConsumerStatefulWidget {
  const NewPurchaseScreen({super.key});

  @override
  ConsumerState<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends ConsumerState<NewPurchaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedProductId;
  String? _selectedSupplierId;
  LineAmountMode _amountMode = LineAmountMode.unitPrice;
  DateTime _transactionDate = TransactionDateField.todayDate();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _quantityController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onProductChanged(String? productId, _PurchaseContext context) {
    setState(() {
      _selectedProductId = productId;
      if (productId != null) {
        final product =
            context.products.firstWhere((p) => p.id == productId);
        if (product.costPrice != null) {
          _amountController.text = product.costPrice!.toStringAsFixed(0);
        }
      }
    });
  }

  Future<void> _save(_PurchaseContext purchaseContext) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) {
      setState(() => _errorMessage = 'Select a product.');
      return;
    }

    final quantity = double.parse(_quantityController.text.trim());
    final enteredAmount = double.parse(_amountController.text.trim());
    final unitCost = resolveLineAmounts(
      quantity: quantity,
      mode: _amountMode,
      enteredAmount: enteredAmount,
    ).unitPrice;

    setState(() => _isSubmitting = true);
    try {
      final purchaseNumber = await ref.read(supabaseClientProvider).rpc(
        'post_purchase',
        params: {
          'target_tenant_id': purchaseContext.tenantId,
          'target_branch_id': purchaseContext.branchId,
          'target_warehouse_id': purchaseContext.warehouseId,
          'p_party_id': _selectedSupplierId,
          'p_notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          'p_purchase_date': TransactionDateField.toIsoDate(_transactionDate),
          'p_lines': [
            {
              'product_id': _selectedProductId,
              'quantity': quantity,
              'unit_cost': unitCost,
            },
          ],
        },
      ) as String;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase $purchaseNumber saved')),
      );
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not save purchase. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contextAsync = ref.watch(newPurchaseContextProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Purchase'),
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
                  onPressed: () =>
                      ref.invalidate(newPurchaseContextProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (purchaseContext) {
          if (purchaseContext.products.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No inventory-tracked products found. Add a stock item product first.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          var unitCode = 'unit';
          if (_selectedProductId != null) {
            for (final product in purchaseContext.products) {
              if (product.id == _selectedProductId) {
                unitCode = product.unitCode;
                break;
              }
            }
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TransactionDateField(
                      selectedDate: _transactionDate,
                      enabled: !_isSubmitting,
                      onChanged: (date) =>
                          setState(() => _transactionDate = date),
                    ),
                    const SizedBox(height: 12),
                    if (purchaseContext.suppliers.isEmpty)
                      Text(
                        'No suppliers linked yet — you can still receive stock.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      )
                    else
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedSupplierId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Supplier (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No supplier'),
                          ),
                          ...purchaseContext.suppliers.map(
                            (supplier) => DropdownMenuItem(
                              value: supplier.id,
                              child: Text(
                                supplier.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ],
                        onChanged: _isSubmitting
                            ? null
                            : (value) =>
                                setState(() => _selectedSupplierId = value),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedProductId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Product',
                        border: OutlineInputBorder(),
                      ),
                      items: purchaseContext.products
                          .map(
                            (product) => DropdownMenuItem(
                              value: product.id,
                              child: Text(
                                '${product.name} · ${product.unitCode}',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _isSubmitting
                          ? null
                          : (value) =>
                              _onProductChanged(value, purchaseContext),
                      validator: (value) =>
                          value == null ? 'Select a product' : null,
                    ),
                    if (_selectedProductId != null) ...[
                      const SizedBox(height: 12),
                      QuantityLinePricingFields(
                        unitCode: unitCode,
                        quantityController: _quantityController,
                        amountController: _amountController,
                        amountMode: _amountMode,
                        onAmountModeChanged: (mode) =>
                            setState(() => _amountMode = mode),
                        enabled: !_isSubmitting,
                        unitPriceLabel: 'Unit cost (RWF)',
                        lineTotalLabel: 'Line total (RWF)',
                        onChanged: () => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => _save(purchaseContext),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Post Purchase'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
