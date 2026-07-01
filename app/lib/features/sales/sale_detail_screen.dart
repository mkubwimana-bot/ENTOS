import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _SaleLineItem {
  const _SaleLineItem({
    required this.lineNumber,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final int lineNumber;
  final String description;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
}

class _SaleDetail {
  const _SaleDetail({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.dueDate,
    required this.saleType,
    required this.partyName,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.notes,
    required this.lines,
  });

  final String invoiceNumber;
  final String invoiceDate;
  final String? dueDate;
  final String saleType;
  final String partyName;
  final double totalAmount;
  final double paidAmount;
  final double balanceAmount;
  final String? notes;
  final List<_SaleLineItem> lines;
}

final saleDetailProvider =
    FutureProvider.autoDispose.family<_SaleDetail, String>((ref, invoiceId) async {
  final client = ref.read(supabaseClientProvider);

  final invoiceRows = await client
      .from('invoices')
      .select(
        'invoice_number, invoice_date, due_date, sale_type, total_amount, '
        'paid_amount, balance_amount, notes, parties(party_name)',
      )
      .eq('id', invoiceId)
      .limit(1);
  if ((invoiceRows as List).isEmpty) throw Exception('Sale not found.');
  final invoice = invoiceRows.first;
  final party = invoice['parties'] as Map<String, dynamic>?;

  final lineRows = await client
      .from('invoice_lines')
      .select('line_number, description, quantity, unit_price, line_total')
      .eq('invoice_id', invoiceId)
      .order('line_number');

  final lines = (lineRows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return _SaleLineItem(
      lineNumber: (map['line_number'] as num?)?.toInt() ?? 0,
      description: map['description'] as String? ?? 'Line item',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      lineTotal: (map['line_total'] as num?)?.toDouble() ?? 0,
    );
  }).toList();

  return _SaleDetail(
    invoiceNumber: invoice['invoice_number'] as String? ?? '',
    invoiceDate: invoice['invoice_date'] as String? ?? '',
    dueDate: invoice['due_date'] as String?,
    saleType: invoice['sale_type'] as String? ?? 'cash',
    partyName: party?['party_name'] as String? ?? 'Walk-in',
    totalAmount: (invoice['total_amount'] as num?)?.toDouble() ?? 0,
    paidAmount: (invoice['paid_amount'] as num?)?.toDouble() ?? 0,
    balanceAmount: (invoice['balance_amount'] as num?)?.toDouble() ?? 0,
    notes: invoice['notes'] as String?,
    lines: lines,
  );
});

class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(saleDetailProvider(invoiceId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale Detail'),
        actions: const [MainMenuNavAction()],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Could not load sale: $error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(saleDetailProvider(invoiceId)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (detail) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detail.invoiceNumber,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Date: ${detail.invoiceDate}'),
                    Text('Customer: ${detail.partyName}'),
                    Text('Type: ${detail.saleType}'),
                    if (detail.dueDate != null) Text('Due: ${detail.dueDate}'),
                    const Divider(height: 24),
                    Text('Total: ${formatRwf(detail.totalAmount)}'),
                    Text('Paid: ${formatRwf(detail.paidAmount)}'),
                    Text(
                      'Balance: ${formatRwf(detail.balanceAmount)}',
                      style: detail.balanceAmount > 0
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            )
                          : null,
                    ),
                    if (detail.notes != null && detail.notes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Notes: ${detail.notes}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Line items', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (detail.lines.isEmpty)
              const Text('No line items')
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < detail.lines.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        title: Text(detail.lines[i].description),
                        subtitle: Text(
                          'Qty ${detail.lines[i].quantity.toStringAsFixed(0)} '
                          '@ ${formatRwf(detail.lines[i].unitPrice)}',
                        ),
                        trailing: Text(formatRwf(detail.lines[i].lineTotal)),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
