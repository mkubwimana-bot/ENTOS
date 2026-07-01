import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import 'new_customer_screen.dart';

class CustomerListItem {
  const CustomerListItem({
    required this.partyCode,
    required this.partyName,
    required this.status,
    required this.openingBalance,
    required this.creditLimit,
  });

  final String partyCode;
  final String partyName;
  final String status;
  final double openingBalance;
  final double? creditLimit;
}

final customerListProvider = FutureProvider.autoDispose<List<CustomerListItem>>((
  ref,
) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('parties')
      .select('party_code, party_name, status, opening_balance, customer_credit_limit')
      .isFilter('deleted_at', null)
      .order('party_name');

  return (rows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return CustomerListItem(
      partyCode: map['party_code'] as String? ?? '',
      partyName: map['party_name'] as String? ?? 'Unnamed customer',
      status: map['status'] as String? ?? 'unknown',
      openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
      creditLimit: (map['customer_credit_limit'] as num?)?.toDouble(),
    );
  }).toList();
});

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(customerListProvider);
    await ref.read(customerListProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customerListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(builder: (_) => const NewCustomerScreen()),
          );
          if (created == true) {
            ref.invalidate(customerListProvider);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('New Customer'),
      ),
      body: customersAsync.when(
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
                  'Could not load customers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(customerListProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (customers) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: customers.isEmpty
              ? const Center(child: Text('No customers yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: customers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final customer = customers[index];
                    return Card(
                      child: ListTile(
                        title: Text(customer.partyName),
                        subtitle: Text(
                          '${customer.partyCode} • ${customer.status}',
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Owed: ${formatRwf(customer.openingBalance)}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              'Limit: ${customer.creditLimit == null ? '-' : formatRwf(customer.creditLimit!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
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
