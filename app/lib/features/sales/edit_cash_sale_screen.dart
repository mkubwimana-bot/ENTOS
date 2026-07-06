import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import '../../core/widgets/quantity_line_pricing_fields.dart';

class _EditProduct {
  const _EditProduct({
    required this.id,
    required this.name,
    required this.sellingPrice,
    required this.unitCode,
  });

  final String id;
  final String name;
  final double sellingPrice;
  final String unitCode;
}

class _EditLineSeed {
  const _EditLineSeed({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
  });

  final String productId;
  final double quantity;
  final double unitPrice;
}

class _EditCashSaleBootstrap {
  const _EditCashSaleBootstrap({
    required this.invoiceNumber,
    required this.notes,
    required this.lines,
    required this.products,
  });

  final String invoiceNumber;
  final String? notes;
  final List<_EditLineSeed> lines;
  final List<_EditProduct> products;
}

final editCashSaleBootstrapProvider =
    FutureProvider.autoDispose.family<_EditCashSaleBootstrap, String>((
  ref,
  invoiceId,
) async {
  final client = ref.read(supabaseClientProvider);

  final invoiceRows = await client
      .from('invoices')
      .select('invoice_number, sale_type, notes')
      .eq('id', invoiceId)
      .limit(1);
  if (invoiceRows.isEmpty) throw Exception('Sale not found.');
  final invoice = invoiceRows.first;
  if ((invoice['sale_type'] as String? ?? '') != 'cash') {
    throw Exception('Only cash sales can be edited here.');
  }

  final lineRows = await client
      .from('invoice_lines')
      .select('product_id, quantity, unit_price')
      .eq('invoice_id', invoiceId)
      .order('line_number');

  final productRows = await client
      .from('products')
      .select(
        'id, product_name, selling_price, product_units(unit_code)',
      )
      .eq('status', 'active')
      .order('product_name');

  final products = (productRows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    final unit = map['product_units'] as Map<String, dynamic>?;
    return _EditProduct(
      id: map['id'] as String,
      name: map['product_name'] as String? ?? 'Unnamed product',
      sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0,
      unitCode: unit?['unit_code'] as String? ?? 'unit',
    );
  }).toList();

  final lines = (lineRows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return _EditLineSeed(
      productId: map['product_id'] as String,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
    );
  }).toList();

  return _EditCashSaleBootstrap(
    invoiceNumber: invoice['invoice_number'] as String? ?? '',
    notes: invoice['notes'] as String?,
    lines: lines,
    products: products,
  );
});

class _EditCartLine {
  _EditCartLine({
    required this.product,
    required double quantity,
    required double unitPrice,
  })
      : quantityController =
            TextEditingController(text: quantity.toStringAsFixed(0)),
        amountController =
            TextEditingController(text: unitPrice.toStringAsFixed(0));

  final _EditProduct product;
  final TextEditingController quantityController;
  final TextEditingController amountController;
  LineAmountMode amountMode = LineAmountMode.unitPrice;

  double get quantity => double.tryParse(quantityController.text.trim()) ?? 0;

  double get enteredAmount =>
      double.tryParse(amountController.text.trim()) ?? 0;

  double get unitPrice => resolveLineAmounts(
        quantity: quantity,
        mode: amountMode,
        enteredAmount: enteredAmount,
      ).unitPrice;

  double get lineTotal => resolveLineAmounts(
        quantity: quantity,
        mode: amountMode,
        enteredAmount: enteredAmount,
      ).lineTotal;

  void dispose() {
    quantityController.dispose();
    amountController.dispose();
  }
}

class EditCashSaleScreen extends ConsumerStatefulWidget {
  const EditCashSaleScreen({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  ConsumerState<EditCashSaleScreen> createState() =>
      _EditCashSaleScreenState();
}

class _EditCashSaleScreenState extends ConsumerState<EditCashSaleScreen> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final List<_EditCartLine> _cart = [];

  String _search = '';
  bool _isSubmitting = false;
  bool _cartInitialized = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    for (final line in _cart) {
      line.dispose();
    }
    super.dispose();
  }

  void _initializeCart(_EditCashSaleBootstrap bootstrap) {
    if (_cartInitialized) return;
    _cartInitialized = true;
    _notesController.text = bootstrap.notes ?? '';
    final productById = {
      for (final product in bootstrap.products) product.id: product,
    };
    for (final seed in bootstrap.lines) {
      final product = productById[seed.productId];
      if (product == null) continue;
      _cart.add(
        _EditCartLine(
          product: product,
          quantity: seed.quantity,
          unitPrice: seed.unitPrice,
        ),
      );
    }
  }

  void _addProduct(_EditProduct product) {
    final existing = _cart.where((line) => line.product.id == product.id);
    if (existing.isNotEmpty) {
      _changeQuantity(existing.first, 1);
      return;
    }
    setState(() {
      _cart.add(
        _EditCartLine(
          product: product,
          quantity: 1,
          unitPrice: product.sellingPrice,
        ),
      );
    });
  }

  void _changeQuantity(_EditCartLine line, double delta) {
    final next = line.quantity + delta;
    if (next <= 0) {
      setState(() {
        line.dispose();
        _cart.remove(line);
      });
      return;
    }
    setState(() {
      line.quantityController.text = next.toStringAsFixed(0);
    });
  }

  double get _grandTotal =>
      _cart.fold<double>(0, (sum, line) => sum + line.lineTotal);

  Future<void> _save() async {
    setState(() => _errorMessage = null);
    if (_cart.isEmpty) {
      setState(() => _errorMessage = 'Add at least one product.');
      return;
    }
    for (final line in _cart) {
      if (line.quantity <= 0) {
        setState(() => _errorMessage = 'Quantity must be greater than zero.');
        return;
      }
      if (line.unitPrice < 0) {
        setState(() => _errorMessage = 'Price must be zero or greater.');
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final lines = _cart
          .map(
            (line) => {
              'product_id': line.product.id,
              'quantity': line.quantity,
              'unit_price': line.unitPrice,
            },
          )
          .toList();

      await ref.read(supabaseClientProvider).rpc(
        'update_cash_invoice',
        params: {
          'p_invoice_id': widget.invoiceId,
          'p_lines': lines,
          'p_notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash sale updated')),
      );
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not update sale. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bootstrapAsync =
        ref.watch(editCashSaleBootstrapProvider(widget.invoiceId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit cash sale'),
        actions: const [MainMenuNavAction()],
      ),
      body: bootstrapAsync.when(
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
                  onPressed: () => ref.invalidate(
                    editCashSaleBootstrapProvider(widget.invoiceId),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (bootstrap) {
          _initializeCart(bootstrap);
          final query = _search.trim().toLowerCase();
          final filtered = query.isEmpty
              ? bootstrap.products
              : bootstrap.products
                  .where((p) => p.name.toLowerCase().contains(query))
                  .toList();

          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        bootstrap.invoiceNumber,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesController,
                        enabled: !_isSubmitting,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
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
                  child: ListView(
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
                          subtitle: Text(
                            '${formatRwf(product.sellingPrice)} · ${product.unitCode}',
                          ),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: _isSubmitting
                              ? null
                              : () => _addProduct(product),
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_errorMessage != null) ...[
                          Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total',
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                            Text(
                              formatRwf(_grandTotal),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _isSubmitting ? null : _save,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCartRow(_EditCartLine line) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed:
                      _isSubmitting ? null : () => _changeQuantity(line, -1),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed:
                      _isSubmitting ? null : () => _changeQuantity(line, 1),
                ),
              ],
            ),
            TextField(
              controller: line.quantityController,
              enabled: !_isSubmitting,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Quantity',
                suffixText: line.product.unitCode,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            LineAmountModeToggle(
              mode: line.amountMode,
              enabled: !_isSubmitting,
              onChanged: (mode) => setState(() => line.amountMode = mode),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: line.amountController,
              enabled: !_isSubmitting,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                labelText: line.amountMode == LineAmountMode.unitPrice
                    ? 'Unit price (RWF)'
                    : 'Line total (RWF)',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}
