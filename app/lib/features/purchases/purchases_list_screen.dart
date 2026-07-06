import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import 'purchase_detail_screen.dart';

class PurchasesListItem {
  const PurchasesListItem({
    required this.purchaseId,
    required this.productSummary,
    required this.totalQuantity,
    required this.purchaseDate,
    required this.supplierName,
    required this.totalAmount,
  });

  final String purchaseId;
  final String productSummary;
  final double totalQuantity;
  final String purchaseDate;
  final String supplierName;
  final double totalAmount;
}

String _formatQty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

String _productSummaryFromLines(List<dynamic>? lines) {
  if (lines == null || lines.isEmpty) return 'No products';
  final names = <String>[];
  for (final line in lines) {
    final map = line as Map<String, dynamic>;
    final name = (map['description'] as String?)?.trim();
    if (name != null && name.isNotEmpty) names.add(name);
  }
  if (names.isEmpty) return 'No products';
  if (names.length == 1) return names.first;
  if (names.length == 2) return '${names[0]}, ${names[1]}';
  return '${names[0]}, ${names[1]} +${names.length - 2} more';
}

double _totalQuantityFromLines(List<dynamic>? lines) {
  if (lines == null || lines.isEmpty) return 0;
  var total = 0.0;
  for (final line in lines) {
    final map = line as Map<String, dynamic>;
    total += (map['quantity'] as num?)?.toDouble() ?? 0;
  }
  return total;
}

final purchasesListProvider =
    FutureProvider.autoDispose<List<PurchasesListItem>>((ref) async {
      final rows = await ref
          .read(supabaseClientProvider)
          .from('purchases')
          .select(
            'id, purchase_date, total_amount, parties(party_name), '
            'purchase_lines(description, quantity)',
          )
          .eq('status', 'posted')
          .isFilter('voided_at', null)
          .order('purchase_date', ascending: false)
          .limit(200);

      return (rows as List<dynamic>).map((row) {
        final map = row as Map<String, dynamic>;
        final party = map['parties'] as Map<String, dynamic>?;
        final lines = map['purchase_lines'] as List<dynamic>?;
        return PurchasesListItem(
          purchaseId: map['id'] as String,
          productSummary: _productSummaryFromLines(lines),
          totalQuantity: _totalQuantityFromLines(lines),
          purchaseDate: map['purchase_date'] as String? ?? '',
          supplierName: party?['party_name'] as String? ?? 'No supplier',
          totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
    });

class PurchasesListScreen extends ConsumerWidget {
  const PurchasesListScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(purchasesListProvider);
    await ref.read(purchasesListProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchasesAsync = ref.watch(purchasesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: const [MainMenuNavAction()],
      ),
      body: purchasesAsync.when(
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
                  onPressed: () => ref.invalidate(purchasesListProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (purchases) {
          if (purchases.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No purchases yet')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => _refresh(ref),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: purchases.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final purchase = purchases[index];
                return Card(
                  child: ListTile(
                    title: Text(
                      purchase.productSummary,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    subtitle: Text(
                      '${purchase.purchaseDate} · qty ${_formatQty(purchase.totalQuantity)} · '
                      '${purchase.supplierName}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      formatRwf(purchase.totalAmount),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    onTap: () async {
                      final deleted = await Navigator.of(context).push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (_) => PurchaseDetailScreen(
                            purchaseId: purchase.purchaseId,
                          ),
                        ),
                      );
                      if (deleted == true) {
                        await _refresh(ref);
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
