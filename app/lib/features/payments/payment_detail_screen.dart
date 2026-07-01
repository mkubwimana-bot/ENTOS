import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _AllocationItem {
  const _AllocationItem({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.allocatedAmount,
  });

  final String invoiceNumber;
  final String invoiceDate;
  final double allocatedAmount;
}

class _PaymentDetail {
  const _PaymentDetail({
    required this.paymentNumber,
    required this.paymentDate,
    required this.partyName,
    required this.paymentMethod,
    required this.amount,
    required this.notes,
    required this.allocations,
  });

  final String paymentNumber;
  final String paymentDate;
  final String partyName;
  final String paymentMethod;
  final double amount;
  final String? notes;
  final List<_AllocationItem> allocations;
}

const _paymentMethodLabels = <String, String>{
  'cash': 'Cash',
  'momo': 'Mobile Money',
  'airtel': 'Airtel Money',
  'bank': 'Bank transfer',
  'card': 'Card',
  'other': 'Other',
};

final paymentDetailProvider =
    FutureProvider.autoDispose.family<_PaymentDetail, String>((ref, paymentId) async {
  final client = ref.read(supabaseClientProvider);

  final paymentRows = await client
      .from('payments')
      .select(
        'payment_number, payment_date, payment_method, amount, notes, parties(party_name)',
      )
      .eq('id', paymentId)
      .limit(1);
  if ((paymentRows as List).isEmpty) throw Exception('Payment not found.');
  final payment = paymentRows.first;
  final party = payment['parties'] as Map<String, dynamic>?;
  final method = payment['payment_method'] as String? ?? 'cash';

  final allocationRows = await client
      .from('payment_allocations')
      .select(
        'allocated_amount, invoices(invoice_number, invoice_date)',
      )
      .eq('payment_id', paymentId);

  final allocations = (allocationRows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    final invoice = map['invoices'] as Map<String, dynamic>?;
    return _AllocationItem(
      invoiceNumber: invoice?['invoice_number'] as String? ?? 'Invoice',
      invoiceDate: invoice?['invoice_date'] as String? ?? '',
      allocatedAmount: (map['allocated_amount'] as num?)?.toDouble() ?? 0,
    );
  }).toList();

  return _PaymentDetail(
    paymentNumber: payment['payment_number'] as String? ?? '',
    paymentDate: payment['payment_date'] as String? ?? '',
    partyName: party?['party_name'] as String? ?? 'Unknown customer',
    paymentMethod: _paymentMethodLabels[method] ?? method,
    amount: (payment['amount'] as num?)?.toDouble() ?? 0,
    notes: payment['notes'] as String?,
    allocations: allocations,
  );
});

class PaymentDetailScreen extends ConsumerWidget {
  const PaymentDetailScreen({required this.paymentId, super.key});

  final String paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(paymentDetailProvider(paymentId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Detail'),
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
                Text('Could not load payment: $error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(paymentDetailProvider(paymentId)),
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
                    Text(detail.paymentNumber,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Date: ${detail.paymentDate}'),
                    Text('Customer: ${detail.partyName}'),
                    Text('Method: ${detail.paymentMethod}'),
                    const Divider(height: 24),
                    Text(
                      'Amount: ${formatRwf(detail.amount)}',
                      style: Theme.of(context).textTheme.titleMedium,
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
            Text('Allocations', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (detail.allocations.isEmpty)
              const Text('No invoice allocations (may be opening balance payment)')
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < detail.allocations.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        title: Text(detail.allocations[i].invoiceNumber),
                        subtitle: Text(detail.allocations[i].invoiceDate),
                        trailing: Text(
                          formatRwf(detail.allocations[i].allocatedAmount),
                        ),
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
