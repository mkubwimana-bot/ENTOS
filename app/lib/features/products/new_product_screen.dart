import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/product/product_code_generator.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _TenantContext {
  const _TenantContext({required this.tenantId});

  final String tenantId;
}

class _ProductTypeOption {
  const _ProductTypeOption({
    required this.id,
    required this.code,
    required this.name,
    required this.tracksInventory,
  });

  final String id;
  final String code;
  final String name;
  final bool tracksInventory;
}

class _ProductCategoryOption {
  const _ProductCategoryOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _ProductUnitOption {
  const _ProductUnitOption({required this.id, required this.code});

  final String id;
  final String code;
}

class _NewProductLookups {
  const _NewProductLookups({
    required this.tenant,
    required this.types,
    required this.categories,
    required this.units,
  });

  final _TenantContext tenant;
  final List<_ProductTypeOption> types;
  final List<_ProductCategoryOption> categories;
  final List<_ProductUnitOption> units;
}

final newProductLookupsProvider = FutureProvider.autoDispose<_NewProductLookups>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be signed in.');

  final membershipRows = await client
      .from('user_tenants')
      .select('tenant_id, membership_status')
      .eq('user_id', userId)
      .eq('membership_status', 'active')
      .limit(1);
  if ((membershipRows).isEmpty) {
    throw Exception('No active tenant membership found for this user.');
  }

  final tenantId = membershipRows.first['tenant_id'] as String;

  final results = await Future.wait<dynamic>([
    client
        .from('product_types')
        .select('id, type_code, type_name, tracks_inventory')
        .eq('is_active', true)
        .order('type_name'),
    client
        .from('product_categories')
        .select('id, category_name')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('category_name'),
    client
        .from('product_units')
        .select('id, unit_code, tenant_id')
        .or('tenant_id.is.null,tenant_id.eq.$tenantId')
        .eq('is_active', true)
        .order('unit_code'),
  ]);

  final typeRows = results[0] as List<dynamic>;
  final categoryRows = results[1] as List<dynamic>;
  final unitRows = results[2] as List<dynamic>;

  return _NewProductLookups(
    tenant: _TenantContext(tenantId: tenantId),
    types: typeRows
        .map((row) {
          final map = row as Map<String, dynamic>;
          return _ProductTypeOption(
            id: map['id'] as String,
            code: map['type_code'] as String? ?? '',
            name: map['type_name'] as String? ?? 'Unknown type',
            tracksInventory: map['tracks_inventory'] as bool? ?? false,
          );
        })
        .toList(),
    categories: categoryRows
        .map((row) {
          final map = row as Map<String, dynamic>;
          return _ProductCategoryOption(
            id: map['id'] as String,
            name: map['category_name'] as String? ?? 'Unknown category',
          );
        })
        .toList(),
    units: unitRows
        .map((row) {
          final map = row as Map<String, dynamic>;
          return _ProductUnitOption(
            id: map['id'] as String,
            code: map['unit_code'] as String? ?? '',
          );
        })
        .toList(),
  );
});

class NewProductScreen extends ConsumerStatefulWidget {
  const NewProductScreen({super.key});

  @override
  ConsumerState<NewProductScreen> createState() => _NewProductScreenState();
}

class _NewProductScreenState extends ConsumerState<NewProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _reorderLevelController = TextEditingController();

  String? _previewProductCode;
  String? _selectedTypeId;
  String? _selectedCategoryId;
  String? _selectedUnitId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _reorderLevelController.dispose();
    super.dispose();
  }

  void _updateCodePreview(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      setState(() => _previewProductCode = null);
      return;
    }
    setState(() {
      _previewProductCode =
          '${deriveProductCodePrefix(trimmed)}### (assigned on save)';
    });
  }

  Future<void> _save(_NewProductLookups lookups) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTypeId == null || _selectedUnitId == null) {
      setState(() => _errorMessage = 'Select product type and unit.');
      return;
    }

    final selectedType = lookups.types.firstWhere((t) => t.id == _selectedTypeId);
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) {
      setState(() => _errorMessage = 'Your session expired. Sign in again.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final productCode = await ref.read(supabaseClientProvider).rpc(
        'generate_product_code',
        params: {
          'target_tenant_id': lookups.tenant.tenantId,
          'product_name': _nameController.text.trim(),
        },
      ) as String;

      await ref.read(supabaseClientProvider).from('products').insert({
        'tenant_id': lookups.tenant.tenantId,
        'product_code': productCode,
        'product_name': _nameController.text.trim(),
        'product_type_id': _selectedTypeId,
        'category_id': _selectedCategoryId,
        'base_unit_id': _selectedUnitId,
        'selling_price': double.parse(_priceController.text.trim()),
        'is_inventory_tracked': selectedType.tracksInventory,
        'reorder_level': _reorderLevelController.text.trim().isEmpty
            ? null
            : double.parse(_reorderLevelController.text.trim()),
        'status': 'active',
        'created_by': userId,
      });
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
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter product name';
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

  String? _validateReorderLevel(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return 'Reorder level must be zero or greater';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lookupsAsync = ref.watch(newProductLookupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Product'),
        actions: const [MainMenuNavAction()],
      ),
      body: lookupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Could not load product setup: $error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(newProductLookupsProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (lookups) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Product name',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateName,
                    onChanged: _updateCodePreview,
                  ),
                  if (_previewProductCode != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Product code: $_previewProductCode',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTypeId,
                    decoration: const InputDecoration(
                      labelText: 'Product type',
                      border: OutlineInputBorder(),
                    ),
                    items: lookups.types
                        .map(
                          (type) => DropdownMenuItem<String>(
                            value: type.id,
                            child: Text(type.name),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _selectedTypeId = value),
                    validator: (value) => value == null ? 'Select product type' : null,
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
                      ...lookups.categories.map(
                        (category) => DropdownMenuItem<String?>(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      ),
                    ],
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _selectedCategoryId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedUnitId,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: lookups.units
                        .map(
                          (unit) => DropdownMenuItem<String>(
                            value: unit.id,
                            child: Text(unit.code),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _selectedUnitId = value),
                    validator: (value) => value == null ? 'Select unit' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _priceController,
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Selling price (RWF)',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validatePrice,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reorderLevelController,
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Reorder level (optional)',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateReorderLevel,
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
                    onPressed: _isSubmitting ? null : () => _save(lookups),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save product'),
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
