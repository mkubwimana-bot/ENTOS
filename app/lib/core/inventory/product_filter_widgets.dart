import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import 'product_period_summary.dart';

class ProductPeriodSummaryCard extends ConsumerWidget {
  const ProductPeriodSummaryCard({
    super.key,
    required this.productId,
    required this.start,
    required this.end,
  });

  final String productId;
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(
      productPeriodSummaryProvider((
        productId: productId,
        start: start,
        end: end,
      )),
    );

    return summaryAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Could not load summary: $error'),
        ),
      ),
      data: (summary) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Product summary',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Quantity at hand',
                value: summary.quantityAtHand.toStringAsFixed(0),
              ),
              _SummaryRow(
                label: 'Purchased (period)',
                value: summary.purchasedInPeriod.toStringAsFixed(0),
              ),
              _SummaryRow(
                label: 'Sold (period)',
                value: summary.soldInPeriod.toStringAsFixed(0),
              ),
              _SummaryRow(
                label: 'Sales value',
                value: formatRwf(summary.salesValue),
              ),
              _SummaryRow(
                label: 'Gross profit',
                value: formatRwf(summary.grossProfit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class ProductFilterDropdown extends ConsumerWidget {
  const ProductFilterDropdown({
    super.key,
    required this.selectedProductId,
    required this.onChanged,
  });

  final String? selectedProductId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productFilterOptionsProvider);

    return productsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const SizedBox.shrink(),
      data: (products) {
        return DropdownButtonFormField<String?>(
          initialValue: selectedProductId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Product',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All products'),
            ),
            ...products.map(
              (p) => DropdownMenuItem<String?>(
                value: p.id,
                child: Text(
                  '${p.name} (${p.code})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}
