import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import 'payment_detail_screen.dart';

class PaymentListItem {
  const PaymentListItem({
    required this.paymentId,
    required this.paymentNumber,
    required this.paymentDate,
    required this.partyName,
    required this.paymentMethod,
    required this.amount,
  });

  final String paymentId;
  final String paymentNumber;
  final String paymentDate;
  final String partyName;
  final String paymentMethod;
  final double amount;
}

const _paymentMethodLabels = <String, String>{
  'cash': 'Cash',
  'momo': 'Mobile Money',
  'airtel': 'Airtel Money',
  'bank': 'Bank transfer',
  'card': 'Card',
  'other': 'Other',
};

final paymentsListProvider =
    FutureProvider.autoDispose<List<PaymentListItem>>((ref) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('payments')
      .select(
        'id, payment_number, payment_date, payment_method, amount, parties(party_name)',
      )
      .eq('status', 'posted')
      .isFilter('voided_at', null)
      .order('payment_date', ascending: false)
      .order('payment_number', ascending: false)
      .limit(200);

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    final party = map['parties'] as Map<String, dynamic>?;
    final method = map['payment_method'] as String? ?? 'cash';
    return PaymentListItem(
      paymentId: map['id'] as String,
      paymentNumber: map['payment_number'] as String? ?? '',
      paymentDate: map['payment_date'] as String? ?? '',
      partyName: party?['party_name'] as String? ?? 'Unknown customer',
      paymentMethod: _paymentMethodLabels[method] ?? method,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
    );
  }).toList();
});

class PaymentsListScreen extends ConsumerWidget {
  const PaymentsListScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(paymentsListProvider);
    await ref.read(paymentsListProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(paymentsListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        actions: const [MainMenuNavAction()],
      ),
      body: paymentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text('Could not load payments: $error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(paymentsListProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (payments) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: payments.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No posted payments yet')),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: payments.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final payment = payments[index];
                    return Card(
                      child: ListTile(
                        title: Text(payment.paymentNumber),
                        subtitle: Text(
                          '${payment.paymentDate} · ${payment.partyName} · ${payment.paymentMethod}',
                        ),
                        trailing: Text(
                          formatRwf(payment.amount),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PaymentDetailScreen(
                                paymentId: payment.paymentId,
                              ),
                            ),
                          );
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
