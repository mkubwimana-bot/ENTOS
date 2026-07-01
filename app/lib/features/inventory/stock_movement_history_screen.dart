import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class StockMovementItem {
  const StockMovementItem({
    required this.movementDate,
    required this.movementType,
    required this.productName,
    required this.productCode,
    required this.warehouseName,
    required this.quantityIn,
    required this.quantityOut,
    required this.referenceNumber,
    required this.reason,
  });

  final String movementDate;
  final String movementType;
  final String productName;
  final String productCode;
  final String warehouseName;
  final double quantityIn;
  final double quantityOut;
  final String? referenceNumber;
  final String? reason;

  double get netQuantity => quantityIn - quantityOut;
}

final stockMovementHistoryProvider =
    FutureProvider.autoDispose<List<StockMovementItem>>((ref) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('stock_movements')
      .select(
        'movement_date, movement_type, quantity_in, quantity_out, reference_number, reason, '
        'products(product_code, product_name), warehouses(name)',
      )
      .isFilter('voided_at', null)
      .order('movement_date', ascending: false)
      .order('created_at', ascending: false)
      .limit(200);

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    final product = map['products'] as Map<String, dynamic>?;
    final warehouse = map['warehouses'] as Map<String, dynamic>?;
    return StockMovementItem(
      movementDate: map['movement_date'] as String? ?? '',
      movementType: map['movement_type'] as String? ?? '',
      productName: product?['product_name'] as String? ?? 'Unknown product',
      productCode: product?['product_code'] as String? ?? '',
      warehouseName: warehouse?['name'] as String? ?? 'Unknown warehouse',
      quantityIn: (map['quantity_in'] as num?)?.toDouble() ?? 0,
      quantityOut: (map['quantity_out'] as num?)?.toDouble() ?? 0,
      referenceNumber: map['reference_number'] as String?,
      reason: map['reason'] as String?,
    );
  }).toList();
});

class StockMovementHistoryScreen extends ConsumerWidget {
  const StockMovementHistoryScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(stockMovementHistoryProvider);
    await ref.read(stockMovementHistoryProvider.future);
  }

  String _formatType(String type) {
    return type.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(stockMovementHistoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Movements'),
        actions: const [MainMenuNavAction()],
      ),
      body: movementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Could not load movements: $error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(stockMovementHistoryProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (movements) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: movements.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No stock movements yet')),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: movements.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final movement = movements[index];
                    final theme = Theme.of(context);
                    final isIn = movement.netQuantity > 0;
                    final qtyLabel = isIn
                        ? '+${movement.quantityIn.toStringAsFixed(0)}'
                        : '-${movement.quantityOut.toStringAsFixed(0)}';

                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isIn ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isIn
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                        ),
                        title: Text(movement.productName),
                        subtitle: Text(
                          '${movement.movementDate} · ${_formatType(movement.movementType)}'
                          '${movement.referenceNumber != null ? ' · ${movement.referenceNumber}' : ''}'
                          '\n${movement.productCode} · ${movement.warehouseName}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          qtyLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: isIn
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
