import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import 'offline_sale_queue.dart';
import '../sync/offline_auto_sync.dart';

class _QuickSaleContext {
  const _QuickSaleContext({
    required this.tenantId,
    required this.userId,
    required this.branchId,
    required this.warehouseId,
    required this.products,
    required this.customers,
    this.cachedAt,
    this.fromOfflineCache = false,
  });

  final String tenantId;
  final String userId;
  final String branchId;
  final String warehouseId;
  final List<_QuickSaleProduct> products;
  final List<_QuickSaleCustomer> customers;
  final DateTime? cachedAt;
  final bool fromOfflineCache;

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'user_id': userId,
        'branch_id': branchId,
        'warehouse_id': warehouseId,
        'products': products.map((p) => p.toJson()).toList(),
        'customers': customers.map((c) => c.toJson()).toList(),
        if (cachedAt != null) 'cached_at': cachedAt!.toIso8601String(),
      };

  factory _QuickSaleContext.fromJson(Map<String, dynamic> json) {
    return _QuickSaleContext(
      tenantId: json['tenant_id'] as String,
      userId: json['user_id'] as String,
      branchId: json['branch_id'] as String,
      warehouseId: json['warehouse_id'] as String,
      products: (json['products'] as List<dynamic>? ?? [])
          .map((e) => _QuickSaleProduct.fromJson(e as Map<String, dynamic>))
          .toList(),
      customers: (json['customers'] as List<dynamic>? ?? [])
          .map((e) => _QuickSaleCustomer.fromJson(e as Map<String, dynamic>))
          .toList(),
      cachedAt: DateTime.tryParse(json['cached_at'] as String? ?? ''),
      fromOfflineCache: true,
    );
  }
}

class _QuickSaleProduct {
  const _QuickSaleProduct({
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'selling_price': sellingPrice,
        'base_unit_id': baseUnitId,
        'is_inventory_tracked': isInventoryTracked,
        'cost_price': costPrice,
      };

  factory _QuickSaleProduct.fromJson(Map<String, dynamic> json) {
    return _QuickSaleProduct(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed product',
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0,
      baseUnitId: json['base_unit_id'] as String,
      isInventoryTracked: json['is_inventory_tracked'] as bool? ?? false,
      costPrice: (json['cost_price'] as num?)?.toDouble(),
    );
  }
}

class _QuickSaleCustomer {
  const _QuickSaleCustomer({
    required this.id,
    required this.name,
    this.balanceOwed,
  });

  final String id;
  final String name;
  final double? balanceOwed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (balanceOwed != null) 'balance_owed': balanceOwed,
      };

  factory _QuickSaleCustomer.fromJson(Map<String, dynamic> json) {
    return _QuickSaleCustomer(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed customer',
      balanceOwed: (json['balance_owed'] as num?)?.toDouble(),
    );
  }
}

/// Caches the last successfully loaded Quick Sale setup so the screen can open
/// while offline. Backed by encrypted on-device storage.
class _QuickSaleContextCache {
  const _QuickSaleContextCache();

  static const _storage = FlutterSecureStorage();
  static const _key = 'sme_os.offline.quicksale_context';

  Future<void> save(_QuickSaleContext context) async {
    await _storage.write(key: _key, value: jsonEncode(context.toJson()));
  }

  Future<_QuickSaleContext?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return _QuickSaleContext.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One product line captured in the quick-sale cart. Owns its own price
/// controller so the cashier can override the default selling price inline.
class _CartLine {
  _CartLine({required this.product, required this.quantity})
      : unitPriceController = TextEditingController(
          text: product.sellingPrice.toStringAsFixed(0),
        );

  final _QuickSaleProduct product;
  int quantity;
  final TextEditingController unitPriceController;

  double get unitPrice => double.tryParse(unitPriceController.text.trim()) ?? 0;
  double get lineTotal => quantity * unitPrice;

  void dispose() => unitPriceController.dispose();
}

final quickSaleContextProvider =
    FutureProvider.autoDispose<_QuickSaleContext>((ref) async {
  final client = ref.read(supabaseClientProvider);
  const cache = _QuickSaleContextCache();
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be signed in.');

  try {
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
          .select(
              'id, product_name, selling_price, base_unit_id, is_inventory_tracked, cost_price')
          .eq('status', 'active')
          .order('product_name'),
      client
          .from('parties')
          .select('id, party_name')
          .eq('status', 'active')
          .isFilter('deleted_at', null)
          .order('party_name'),
      client
          .from('vw_customer_balances')
          .select('party_id, balance'),
    ]);

    final balanceByParty = <String, double>{};
    for (final row in results[2] as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      balanceByParty[map['party_id'] as String] =
          (map['balance'] as num?)?.toDouble() ?? 0;
    }

    final products = (results[0] as List<dynamic>).map((row) {
      final map = row as Map<String, dynamic>;
      return _QuickSaleProduct(
        id: map['id'] as String,
        name: map['product_name'] as String? ?? 'Unnamed product',
        sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0,
        baseUnitId: map['base_unit_id'] as String,
        isInventoryTracked: map['is_inventory_tracked'] as bool? ?? false,
        costPrice: (map['cost_price'] as num?)?.toDouble(),
      );
    }).toList();

    final customers = (results[1] as List<dynamic>).map((row) {
      final map = row as Map<String, dynamic>;
      final id = map['id'] as String;
      return _QuickSaleCustomer(
        id: id,
        name: map['party_name'] as String? ?? 'Unnamed customer',
        balanceOwed: balanceByParty[id],
      );
    }).toList();

    final context = _QuickSaleContext(
      tenantId: tenantId,
      userId: userId,
      branchId: branchId,
      warehouseId: warehouseId,
      products: products,
      customers: customers,
      cachedAt: DateTime.now(),
    );

    // Cache the setup so Quick Sale can still be opened while offline.
    await cache.save(context);
    return context;
  } catch (error) {
    if (isOfflineError(error)) {
      final cached = await cache.load();
      if (cached != null) return cached;
      throw Exception(
        'You are offline and no saved products are available yet. '
        'Open Quick Sale once while online to enable offline sales.',
      );
    }
    rethrow;
  }
});

class QuickSaleScreen extends ConsumerStatefulWidget {
  const QuickSaleScreen({super.key});

  @override
  ConsumerState<QuickSaleScreen> createState() => _QuickSaleScreenState();
}

class _QuickSaleScreenState extends ConsumerState<QuickSaleScreen> {
  final _searchController = TextEditingController();
  final List<_CartLine> _cart = [];

  String _saleType = 'cash';
  String? _selectedCustomerId;
  String _search = '';
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    for (final line in _cart) {
      line.dispose();
    }
    super.dispose();
  }

  double get _grandTotal =>
      _cart.fold<double>(0, (sum, line) => sum + line.lineTotal);

  String _formatCachedAt(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  void _addProduct(_QuickSaleProduct product) {
    setState(() {
      final existing = _cart.where((line) => line.product.id == product.id);
      if (existing.isNotEmpty) {
        existing.first.quantity += 1;
      } else {
        _cart.add(_CartLine(product: product, quantity: 1));
      }
    });
  }

  void _changeQuantity(_CartLine line, int delta) {
    setState(() {
      final next = line.quantity + delta;
      if (next <= 0) {
        line.dispose();
        _cart.remove(line);
      } else {
        line.quantity = next;
      }
    });
  }

  Future<void> _save(_QuickSaleContext saleContext) async {
    setState(() => _errorMessage = null);

    if (_cart.isEmpty) {
      setState(() => _errorMessage = 'Add at least one product.');
      return;
    }
    if (_saleType == 'credit' && _selectedCustomerId == null) {
      setState(() => _errorMessage = 'Select customer for credit sale.');
      return;
    }
    for (final line in _cart) {
      if (line.unitPrice < 0) {
        setState(() => _errorMessage = 'Unit price must be zero or greater.');
        return;
      }
    }

    final client = ref.read(supabaseClientProvider);
    final clientReferenceId =
        OfflineSaleQueue.newClientReferenceId(saleContext.userId);
    final capturedAt = DateTime.now().toUtc();

    final lines = _cart
        .map((line) => {
              'product_id': line.product.id,
              'quantity': line.quantity.toDouble(),
              'unit_price': line.unitPrice,
            })
        .toList();

    const String? notes = null;

    setState(() => _isSubmitting = true);
    try {
      await client.rpc(
        'post_sale_draft',
        params: {
          'target_tenant_id': saleContext.tenantId,
          'target_branch_id': saleContext.branchId,
          'target_warehouse_id': saleContext.warehouseId,
          'p_client_reference_id': clientReferenceId,
          'p_sale_type': _saleType,
          'p_party_id': _selectedCustomerId,
          'p_notes': notes,
          'p_captured_at': capturedAt.toIso8601String(),
          'p_lines': lines,
        },
      );

      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (error) {
      if (isOfflineError(error)) {
        await _queueOffline(saleContext, clientReferenceId, capturedAt, notes);
        return;
      }
      if (mounted) {
        setState(() => _errorMessage = 'Could not save sale. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _queueOffline(
    _QuickSaleContext saleContext,
    String clientReferenceId,
    DateTime capturedAt,
    String? notes,
  ) async {
    final pending = PendingSale(
      clientReferenceId: clientReferenceId,
      tenantId: saleContext.tenantId,
      branchId: saleContext.branchId,
      warehouseId: saleContext.warehouseId,
      saleType: _saleType,
      partyId: _selectedCustomerId,
      notes: notes,
      capturedAt: capturedAt,
      lines: _cart
          .map((line) => PendingSaleLine(
                productId: line.product.id,
                productName: line.product.name,
                quantity: line.quantity.toDouble(),
                unitPrice: line.unitPrice,
              ))
          .toList(),
    );

    await ref.read(offlineSaleQueueProvider).add(pending);
    ref.invalidate(offlinePendingCountProvider);
    requestOfflineAutoSync(ref);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved offline. Sync it from Sync Status when back online.'),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final saleContextAsync = ref.watch(quickSaleContextProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Sale'),
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
                Text('Could not load sale setup: $error',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(quickSaleContextProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (saleContext) => _buildBody(saleContext),
      ),
    );
  }

  Widget _buildBody(_QuickSaleContext saleContext) {
    final query = _search.trim().toLowerCase();
    final filtered = query.isEmpty
        ? saleContext.products
        : saleContext.products
            .where((p) => p.name.toLowerCase().contains(query))
            .toList();

    _QuickSaleCustomer? selectedCustomer;
    if (_selectedCustomerId != null) {
      for (final customer in saleContext.customers) {
        if (customer.id == _selectedCustomerId) {
          selectedCustomer = customer;
          break;
        }
      }
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saleContext.fromOfflineCache && saleContext.cachedAt != null)
            MaterialBanner(
              content: Text(
                'Offline — product and customer data from '
                '${_formatCachedAt(saleContext.cachedAt!)}',
              ),
              leading: const Icon(Icons.cloud_off_outlined),
              actions: const [SizedBox.shrink()],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(value: 'cash', label: Text('Cash')),
                    ButtonSegment<String>(
                        value: 'credit', label: Text('Credit')),
                  ],
                  selected: {_saleType},
                  onSelectionChanged: _isSubmitting
                      ? null
                      : (values) => setState(() => _saleType = values.first),
                ),
                if (_saleType == 'credit') ...[
                  const SizedBox(height: 12),
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
                        : (value) =>
                            setState(() => _selectedCustomerId = value),
                  ),
                  if (selectedCustomer?.balanceOwed != null &&
                      selectedCustomer!.balanceOwed! > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      saleContext.fromOfflineCache
                          ? 'Amount owed (as of ${_formatCachedAt(saleContext.cachedAt ?? DateTime.now())}): '
                              '${formatRwf(selectedCustomer.balanceOwed!)}'
                          : 'Amount owed: ${formatRwf(selectedCustomer.balanceOwed!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  enabled: !_isSubmitting,
                  decoration: InputDecoration(
                    labelText: 'Search product',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _cart.isEmpty && filtered.isEmpty
                ? const Center(child: Text('No products found.'))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      if (_cart.isNotEmpty) ...[
                        Text('Cart',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        ..._cart.map(_buildCartRow),
                        const Divider(height: 24),
                      ],
                      Text('Products',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      ...filtered.map(
                        (product) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(product.name),
                          subtitle: Text(formatRwf(product.sellingPrice)),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: _isSubmitting
                              ? null
                              : () => _addProduct(product),
                        ),
                      ),
                    ],
                  ),
          ),
          _buildFooter(saleContext),
        ],
      ),
    );
  }

  Widget _buildCartRow(_CartLine line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.product.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  formatRwf(line.lineTotal),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: line.unitPriceController,
              enabled: !_isSubmitting,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Price',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed:
                _isSubmitting ? null : () => _changeQuantity(line, -1),
          ),
          Text('${line.quantity}'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _isSubmitting ? null : () => _changeQuantity(line, 1),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(_QuickSaleContext saleContext) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  formatRwf(_grandTotal),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
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
    );
  }
}
