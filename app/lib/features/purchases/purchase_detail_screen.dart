import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/role_providers.dart';
import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _PurchaseLineItem {
  const _PurchaseLineItem({
    required this.lineNumber,
    required this.description,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
  });

  final int lineNumber;
  final String description;
  final double quantity;
  final double unitCost;
  final double lineTotal;
}

class _PurchaseDetail {
  const _PurchaseDetail({
    required this.purchaseNumber,
    required this.purchaseDate,
    required this.supplierName,
    required this.totalAmount,
    required this.notes,
    required this.lines,
  });

  final String purchaseNumber;
  final String purchaseDate;
  final String supplierName;
  final double totalAmount;
  final String? notes;
  final List<_PurchaseLineItem> lines;
}

final purchaseDetailProvider = FutureProvider.autoDispose
    .family<_PurchaseDetail, String>((ref, purchaseId) async {
      final client = ref.read(supabaseClientProvider);

      final purchaseRows = await client
          .from('purchases')
          .select(
            'purchase_number, purchase_date, total_amount, notes, parties(party_name)',
          )
          .eq('id', purchaseId)
          .limit(1);
      if (purchaseRows.isEmpty) {
        throw Exception('Purchase not found.');
      }
      final purchase = purchaseRows.first;
      final party = purchase['parties'] as Map<String, dynamic>?;

      final lineRows = await client
          .from('purchase_lines')
          .select('line_number, description, quantity, unit_cost, line_total')
          .eq('purchase_id', purchaseId)
          .order('line_number');

      final lines = (lineRows as List<dynamic>).map((row) {
        final map = row as Map<String, dynamic>;
        return _PurchaseLineItem(
          lineNumber: (map['line_number'] as num?)?.toInt() ?? 0,
          description: map['description'] as String? ?? 'Line item',
          quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
          unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0,
          lineTotal: (map['line_total'] as num?)?.toDouble() ?? 0,
        );
      }).toList();

      return _PurchaseDetail(
        purchaseNumber: purchase['purchase_number'] as String? ?? '',
        purchaseDate: purchase['purchase_date'] as String? ?? '',
        supplierName: party?['party_name'] as String? ?? 'No supplier',
        totalAmount: (purchase['total_amount'] as num?)?.toDouble() ?? 0,
        notes: purchase['notes'] as String?,
        lines: lines,
      );
    });

class PurchaseDetailScreen extends ConsumerStatefulWidget {
  const PurchaseDetailScreen({required this.purchaseId, super.key});

  final String purchaseId;

  @override
  ConsumerState<PurchaseDetailScreen> createState() =>
      _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends ConsumerState<PurchaseDetailScreen> {
  bool _isVoiding = false;

  Future<bool> _confirmVoid() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: const Text(
          'Posted purchases cannot be edited. Delete this purchase, then '
          'record it again correctly.\n\n'
          'This voids the purchase and reverses its stock receipt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _voidPurchase() async {
    if (!await _confirmVoid()) return;

    setState(() => _isVoiding = true);
    try {
      await ref
          .read(supabaseClientProvider)
          .rpc('void_purchase', params: {'p_purchase_id': widget.purchaseId});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Purchase deleted')));
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isVoiding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(purchaseDetailProvider(widget.purchaseId));
    final canVoid =
        ref.watch(canVoidTransactionsProvider).asData?.value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Detail'),
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
                Text(
                  'Could not load purchase: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(purchaseDetailProvider(widget.purchaseId)),
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
                    Text(
                      detail.purchaseNumber,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Date: ${detail.purchaseDate}'),
                    Text('Supplier: ${detail.supplierName}'),
                    const Divider(height: 24),
                    Text(
                      'Total: ${formatRwf(detail.totalAmount)}',
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
                          'Qty ${detail.lines[i].quantity.toStringAsFixed(detail.lines[i].quantity == detail.lines[i].quantity.roundToDouble() ? 0 : 2)} '
                          '@ ${formatRwf(detail.lines[i].unitCost)}',
                        ),
                        trailing: Text(formatRwf(detail.lines[i].lineTotal)),
                      ),
                    ],
                  ],
                ),
              ),
            if (canVoid) ...[
              const SizedBox(height: 24),
              Card(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Mistakes cannot be edited. Delete this purchase, then '
                    'record it again correctly.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isVoiding ? null : _voidPurchase,
                icon: _isVoiding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: const Text('Delete purchase'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
