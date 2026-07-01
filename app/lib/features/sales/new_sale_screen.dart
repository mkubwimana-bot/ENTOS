import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _SaleContext {
  const _SaleContext({
    required this.tenantId,
    required this.userId,
    required this.branchId,
    required this.warehouseId,
    required this.products,
    required this.customers,
  });

  final String tenantId;
  final String userId;
  final String branchId;
  final String warehouseId;
  final List<_SaleProductOption> products;
  final List<_SaleCustomerOption> customers;
}

class _SaleProductOption {
  const _SaleProductOption({
    required this.id,
    required this.name,
    required this.sellingPrice,
    required this.baseUnitId,
    required this.isInventoryTracked,
    required this.costPrice,
  });

  final String id;
  final String name;
  final double sellingPrice;
  final String baseUnitId;
  final bool isInventoryTracked;
  final double? costPrice;
}

class _SaleCustomerOption {
  const _SaleCustomerOption({required this.id, required this.name});

  final String id;
  final String name;
}

final newSaleContextProvider = FutureProvider.autoDispose<_SaleContext>((ref) async {
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

  final results = await Future.wait<dynamic>([
    client
        .from('products')
        .select('id, product_name, selling_price, base_unit_id, is_inventory_tracked, cost_price')
        .eq('status', 'active')
        .order('product_name'),
    client
        .from('parties')
        .select('id, party_name')
        .eq('status', 'active')
        .isFilter('deleted_at', null)
        .order('party_name'),
  ]);

  final products = (results[0] as List<dynamic>)
      .map((row) {
        final map = row as Map<String, dynamic>;
        return _SaleProductOption(
          id: map['id'] as String,
          name: map['product_name'] as String? ?? 'Unnamed product',
          sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0,
          baseUnitId: map['base_unit_id'] as String,
          isInventoryTracked: map['is_inventory_tracked'] as bool? ?? false,
          costPrice: (map['cost_price'] as num?)?.toDouble(),
        );
      })
      .toList();

  final customers = (results[1] as List<dynamic>)
      .map((row) {
        final map = row as Map<String, dynamic>;
        return _SaleCustomerOption(
          id: map['id'] as String,
          name: map['party_name'] as String? ?? 'Unnamed customer',
        );
      })
      .toList();

  return _SaleContext(
    tenantId: tenantId,
    userId: userId,
    branchId: branchId,
    warehouseId: warehouseId,
    products: products,
    customers: customers,
  );
});

class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key});

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _unitPriceController = TextEditingController();
  final _notesController = TextEditingController();

  String _saleType = 'cash';
  String? _selectedProductId;
  String? _selectedCustomerId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _quantityController.dispose();
    _unitPriceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save(_SaleContext saleContext) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) {
      setState(() => _errorMessage = 'Select a product.');
      return;
    }
    if (_saleType == 'credit' && _selectedCustomerId == null) {
      setState(() => _errorMessage = 'Select customer for credit sale.');
      return;
    }

    final product = saleContext.products.firstWhere((p) => p.id == _selectedProductId);
    final quantity = double.parse(_quantityController.text.trim());
    final unitPrice = double.parse(_unitPriceController.text.trim());
    final total = quantity * unitPrice;

    setState(() => _isSubmitting = true);
    try {
      final invoiceNumber = await ref.read(supabaseClientProvider).rpc(
        'get_next_document_number',
        params: {
          'target_tenant_id': saleContext.tenantId,
          'target_branch_id': saleContext.branchId,
          'target_sequence_code': 'invoice',
        },
      ) as String;

      final invoiceDate = DateTime.now().toIso8601String().substring(0, 10);
      String? dueDate;
      if (_saleType == 'credit' && _selectedCustomerId != null) {
        final partyRows = await ref
            .read(supabaseClientProvider)
            .from('parties')
            .select('customer_credit_terms_days')
            .eq('id', _selectedCustomerId!)
            .limit(1);
        final terms = partyRows.isEmpty
            ? 30
            : (partyRows.first['customer_credit_terms_days'] as int?) ?? 30;
        dueDate = DateTime.now()
            .add(Duration(days: terms))
            .toIso8601String()
            .substring(0, 10);
      }

      final invoiceRows = await ref.read(supabaseClientProvider).from('invoices').insert({
        'tenant_id': saleContext.tenantId,
        'branch_id': saleContext.branchId,
        'warehouse_id': saleContext.warehouseId,
        'invoice_number': invoiceNumber,
        'invoice_date': invoiceDate,
        'due_date': dueDate,
        'party_id': _saleType == 'credit' ? _selectedCustomerId : _selectedCustomerId,
        'sale_type': _saleType,
        'status': 'posted',
        'subtotal_amount': total,
        'discount_amount': 0,
        'tax_amount': 0,
        'total_amount': total,
        'paid_amount': _saleType == 'credit' ? 0 : total,
        'balance_amount': _saleType == 'credit' ? total : 0,
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        'created_by': saleContext.userId,
        'posted_at': DateTime.now().toUtc().toIso8601String(),
      }).select('id').limit(1);

      final invoiceId = (invoiceRows as List).first['id'] as String;

      await ref.read(supabaseClientProvider).from('invoice_lines').insert({
        'tenant_id': saleContext.tenantId,
        'invoice_id': invoiceId,
        'line_number': 1,
        'product_id': product.id,
        'description': product.name,
        'quantity': quantity,
        'unit_id': product.baseUnitId,
        'unit_price': unitPrice,
        'discount_amount': 0,
        'tax_amount': 0,
        'line_total': total,
        'cost_price_snapshot': product.costPrice,
        'warehouse_id': saleContext.warehouseId,
        'created_by': saleContext.userId,
      });

      if (product.isInventoryTracked) {
        await ref.read(supabaseClientProvider).from('stock_movements').insert({
          'tenant_id': saleContext.tenantId,
          'branch_id': saleContext.branchId,
          'warehouse_id': saleContext.warehouseId,
          'product_id': product.id,
          'movement_date': DateTime.now().toIso8601String().substring(0, 10),
          'movement_type': 'sale',
          'quantity_in': 0,
          'quantity_out': quantity,
          'unit_cost': product.costPrice,
          'total_cost': product.costPrice == null ? null : product.costPrice! * quantity,
          'source_table': 'invoices',
          'source_id': invoiceId,
          'reference_number': invoiceNumber,
          'reason': 'Sale invoice',
          'created_by': saleContext.userId,
        });
      }

      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Could not save sale. Please try again.');
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

  String? _validateUnitPrice(String? value) {
    final text = value?.trim() ?? '';
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter unit price';
    if (parsed < 0) return 'Price must be zero or greater';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final saleContextAsync = ref.watch(newSaleContextProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Sale'),
        actions: const [MainMenuNavAction()],
      ),
      body: saleContextAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Could not load sale setup: $error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(newSaleContextProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (saleContext) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(value: 'cash', label: Text('Cash')),
                      ButtonSegment<String>(value: 'credit', label: Text('Credit')),
                    ],
                    selected: {_saleType},
                    onSelectionChanged: _isSubmitting
                        ? null
                        : (values) => setState(() => _saleType = values.first),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedProductId,
                    decoration: const InputDecoration(
                      labelText: 'Product',
                      border: OutlineInputBorder(),
                    ),
                    items: saleContext.products
                        .map(
                          (product) => DropdownMenuItem<String>(
                            value: product.id,
                            child: Text('${product.name} (${formatRwf(product.sellingPrice)})'),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) {
                            setState(() => _selectedProductId = value);
                            if (value != null) {
                              final selected =
                                  saleContext.products.firstWhere((p) => p.id == value);
                              _unitPriceController.text =
                                  selected.sellingPrice.toStringAsFixed(0);
                            }
                          },
                    validator: (value) => value == null ? 'Select product' : null,
                  ),
                  const SizedBox(height: 12),
                  if (_saleType == 'credit') ...[
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCustomerId,
                      decoration: const InputDecoration(
                        labelText: 'Customer',
                        border: OutlineInputBorder(),
                      ),
                      items: saleContext.customers
                          .map(
                            (customer) => DropdownMenuItem<String>(
                              value: customer.id,
                              child: Text(customer.name),
                            ),
                          )
                          .toList(),
                      onChanged: _isSubmitting
                          ? null
                          : (value) => setState(() => _selectedCustomerId = value),
                      validator: (value) =>
                          _saleType == 'credit' && value == null ? 'Select customer' : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _quantityController,
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateQuantity,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _unitPriceController,
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Unit price (RWF)',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateUnitPrice,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isSubmitting ? null : () => _save(saleContext),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Post sale'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
