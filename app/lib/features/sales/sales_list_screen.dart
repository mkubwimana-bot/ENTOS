import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import 'sale_detail_screen.dart';

class SalesListItem {
  const SalesListItem({
    required this.invoiceId,
    required this.productSummary,
    required this.totalQuantity,
    required this.invoiceDate,
    required this.saleType,
    required this.partyName,
    required this.totalAmount,
    required this.balanceAmount,
  });

  final String invoiceId;
  final String productSummary;
  final double totalQuantity;
  final String invoiceDate;
  final String saleType;
  final String partyName;
  final double totalAmount;
  final double balanceAmount;
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

final salesListProvider = FutureProvider.autoDispose<List<SalesListItem>>((
  ref,
) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('invoices')
      .select(
        'id, invoice_date, sale_type, total_amount, balance_amount, '
        'parties(party_name), invoice_lines(description, quantity)',
      )
      .eq('status', 'posted')
      .isFilter('voided_at', null)
      .order('invoice_date', ascending: false)
      .order('created_at', ascending: false)
      .limit(500);

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    final party = map['parties'] as Map<String, dynamic>?;
    final lines = map['invoice_lines'] as List<dynamic>?;
    return SalesListItem(
      invoiceId: map['id'] as String,
      productSummary: _productSummaryFromLines(lines),
      totalQuantity: _totalQuantityFromLines(lines),
      invoiceDate: map['invoice_date'] as String? ?? '',
      saleType: map['sale_type'] as String? ?? 'cash',
      partyName: party?['party_name'] as String? ?? 'Walk-in',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      balanceAmount: (map['balance_amount'] as num?)?.toDouble() ?? 0,
    );
  }).toList();
});

class SalesListScreen extends ConsumerWidget {
  const SalesListScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(salesListProvider);
    await ref.read(salesListProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: const [MainMenuNavAction()],
      ),
      body: salesAsync.when(
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
                  'Could not load sales: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(salesListProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (sales) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: sales.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No posted sales yet')),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: sales.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final sale = sales[index];
                    return Card(
                      child: ListTile(
                        title: Text(
                          sale.productSummary,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        subtitle: Text(
                          '${sale.invoiceDate} · qty ${_formatQty(sale.totalQuantity)} · '
                          '${sale.partyName} · ${sale.saleType}',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatRwf(sale.totalAmount),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (sale.balanceAmount > 0)
                              Text(
                                'Owed ${formatRwf(sale.balanceAmount)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                              ),
                          ],
                        ),
                        onTap: () async {
                          final deleted = await Navigator.of(context)
                              .push<bool>(
                                MaterialPageRoute<bool>(
                                  builder: (_) => SaleDetailScreen(
                                    invoiceId: sale.invoiceId,
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
        ),
      ),
    );
  }
}
