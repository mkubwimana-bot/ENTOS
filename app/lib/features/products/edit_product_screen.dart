import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _ProductCategoryOption {
  const _ProductCategoryOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _EditProductData {
  const _EditProductData({
    required this.productId,
    required this.userId,
    required this.productCode,
    required this.productName,
    required this.typeName,
    required this.unitCode,
    required this.sellingPrice,
    required this.costPrice,
    required this.reorderLevel,
    required this.categoryId,
    required this.status,
    required this.categories,
  });

  final String productId;
  final String userId;
  final String productCode;
  final String productName;
  final String typeName;
  final String unitCode;
  final double sellingPrice;
  final double? costPrice;
  final double? reorderLevel;
  final String? categoryId;
  final String status;
  final List<_ProductCategoryOption> categories;
}

final editProductProvider =
    FutureProvider.autoDispose.family<_EditProductData, String>((
  ref,
  productId,
) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be signed in.');

  final membershipRows = await client
      .from('user_tenants')
      .select('tenant_id')
      .eq('user_id', userId)
      .eq('membership_status', 'active')
      .limit(1);
  if ((membershipRows as List).isEmpty) {
    throw Exception('No active tenant membership found.');
  }
  final tenantId = membershipRows.first['tenant_id'] as String;

  final results = await Future.wait<dynamic>([
    client
        .from('products')
        .select(
          'id, product_code, product_name, product_type_id, base_unit_id, '
          'category_id, selling_price, cost_price, reorder_level, status',
        )
        .eq('id', productId)
        .limit(1),
    client
        .from('product_types')
        .select('id, type_name')
        .eq('is_active', true),
    client
        .from('product_units')
        .select('id, unit_code')
        .or('tenant_id.is.null,tenant_id.eq.$tenantId')
        .eq('is_active', true),
    client
        .from('product_categories')
        .select('id, category_name')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('category_name'),
  ]);

  final productRows = results[0] as List<dynamic>;
  if (productRows.isEmpty) throw Exception('Product not found.');
  final product = productRows.first as Map<String, dynamic>;

  final typesById = <String, String>{};
  for (final row in results[1] as List<dynamic>) {
    final map = row as Map<String, dynamic>;
    typesById[map['id'] as String] = map['type_name'] as String? ?? '';
  }
  final unitsById = <String, String>{};
  for (final row in results[2] as List<dynamic>) {
    final map = row as Map<String, dynamic>;
    unitsById[map['id'] as String] = map['unit_code'] as String? ?? '';
  }
  final categories = (results[3] as List<dynamic>)
      .map((row) {
        final map = row as Map<String, dynamic>;
        return _ProductCategoryOption(
          id: map['id'] as String,
          name: map['category_name'] as String? ?? 'Unknown',
        );
      })
      .toList();

  final typeId = product['product_type_id'] as String;
  final unitId = product['base_unit_id'] as String;

  return _EditProductData(
    productId: product['id'] as String,
    userId: userId,
    productCode: product['product_code'] as String? ?? '',
    productName: product['product_name'] as String? ?? '',
    typeName: typesById[typeId] ?? 'Unknown',
    unitCode: unitsById[unitId] ?? '—',
    sellingPrice: (product['selling_price'] as num?)?.toDouble() ?? 0,
    costPrice: (product['cost_price'] as num?)?.toDouble(),
    categoryId: product['category_id'] as String?,
    reorderLevel: (product['reorder_level'] as num?)?.toDouble(),
    status: product['status'] as String? ?? 'active',
    categories: categories,
  );
});

class EditProductScreen extends ConsumerStatefulWidget {
  const EditProductScreen({required this.productId, super.key});

  final String productId;

  @override
  ConsumerState<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends ConsumerState<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController();
  final _reorderLevelController = TextEditingController();

  String? _selectedCategoryId;
  String _status = 'active';
  bool _isSubmitting = false;
  bool _initialized = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _reorderLevelController.dispose();
    super.dispose();
  }

  void _initFromData(_EditProductData data) {
    if (_initialized) return;
    _nameController.text = data.productName;
    _priceController.text = data.sellingPrice.toStringAsFixed(0);
    _costController.text = data.costPrice?.toStringAsFixed(0) ?? '';
    _reorderLevelController.text =
        data.reorderLevel?.toStringAsFixed(0) ?? '';
    _selectedCategoryId = data.categoryId;
    _status = data.status;
    _initialized = true;
  }

  Future<void> _save(_EditProductData data) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final costText = _costController.text.trim();
      await ref.read(supabaseClientProvider).from('products').update({
        'product_name': _nameController.text.trim(),
        'category_id': _selectedCategoryId,
        'selling_price': double.parse(_priceController.text.trim()),
        'cost_price': costText.isEmpty ? null : double.parse(costText),
        'reorder_level': _reorderLevelController.text.trim().isEmpty
            ? null
            : double.parse(_reorderLevelController.text.trim()),
        'status': _status,
        'updated_by': data.userId,
      }).eq('id', data.productId);

      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not save product. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _validateName(String? value) {
    if ((value?.trim() ?? '').isEmpty) return 'Enter product name';
    return null;
  }

  String? _validatePrice(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter selling price';
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return 'Price must be zero or greater';
    return null;
  }

  String? _validateOptionalMoney(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return 'Amount must be zero or greater';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(editProductProvider(widget.productId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Product'),
        actions: const [MainMenuNavAction()],
      ),
      body: productAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Could not load product: $error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(editProductProvider(widget.productId)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          _initFromData(data);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      initialValue: data.productCode,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Product code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: '${data.typeName} · ${data.unitCode}',
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Type · Unit',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Product name',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateName,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Category (optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None'),
                        ),
                        ...data.categories.map(
                          (category) => DropdownMenuItem<String?>(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        ),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) =>
                              setState(() => _selectedCategoryId = value),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceController,
                      enabled: !_isSubmitting,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Selling price (RWF)',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validatePrice,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _costController,
                      enabled: !_isSubmitting,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Cost price (RWF, optional)',
                        helperText: 'Used for gross profit estimates',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateOptionalMoney,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reorderLevelController,
                      enabled: !_isSubmitting,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Reorder level (optional)',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateOptionalMoney,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('Active')),
                        DropdownMenuItem(
                            value: 'inactive', child: Text('Inactive')),
                        DropdownMenuItem(
                            value: 'discontinued', child: Text('Discontinued')),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) => setState(() => _status = value ?? 'active'),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _isSubmitting ? null : () => _save(data),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save changes'),
                      ),
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
