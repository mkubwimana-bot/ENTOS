import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money_format.dart';
import '../../core/supabase/supabase_providers.dart';
import 'dashboard_models.dart';
import 'dashboard_providers.dart';

/// Main business screen after sign-in.
///
/// Reads four Supabase views (RLS-scoped to the user's tenant):
/// - [vw_daily_sales] — today's sales total
/// - [vw_customer_balances] — money owed by customers
/// - [vw_low_stock] — products at or below reorder level
/// - [vw_pending_mobile_transactions] — offline drafts awaiting sync
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(dashboardSummaryProvider);
    await ref.read(dashboardSummaryProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final client = ref.watch(supabaseClientProvider);
    final email = client.auth.currentUser?.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SME-OS'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _refresh(ref),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _DashboardError(
          message: error.toString(),
          onRetry: () => ref.invalidate(dashboardSummaryProvider),
        ),
        data: (summary) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (email != null) ...[
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              _MetricGrid(summary: summary),
              if (summary.lowStockProducts.isNotEmpty) ...[
                const SizedBox(height: 24),
                _LowStockSection(products: summary.lowStockProducts),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 600 ? 2 : 1;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: crossAxisCount == 2 ? 1.6 : 2.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MetricCard(
              title: "Today's sales",
              value: formatRwf(summary.todaySales),
              subtitle: summary.todayInvoiceCount == 1
                  ? '1 invoice'
                  : '${summary.todayInvoiceCount} invoices',
              icon: Icons.point_of_sale_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            _MetricCard(
              title: 'Money owed',
              value: formatRwf(summary.moneyOwed),
              subtitle: 'Customer balances',
              icon: Icons.account_balance_wallet_outlined,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _MetricCard(
              title: 'Low stock',
              value: '${summary.lowStockCount}',
              subtitle: summary.lowStockCount == 1
                  ? 'product needs attention'
                  : 'products need attention',
              icon: Icons.inventory_2_outlined,
              color: summary.lowStockCount > 0
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.secondary,
            ),
            _MetricCard(
              title: 'Pending mobile',
              value: '${summary.pendingMobileCount}',
              subtitle: summary.pendingMobileCount == 1
                  ? 'transaction to sync'
                  : 'transactions to sync',
              icon: Icons.sync_problem_outlined,
              color: summary.pendingMobileCount > 0
                  ? Colors.orange.shade700
                  : Theme.of(context).colorScheme.secondary,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const Spacer(),
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LowStockSection extends StatelessWidget {
  const _LowStockSection({required this.products});

  final List<LowStockItem> products;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Low stock items', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < products.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: Text(products[i].productName),
                  subtitle: Text(
                    'Stock: ${products[i].currentQuantity.toStringAsFixed(0)} '
                    '/ reorder ${products[i].reorderLevel.toStringAsFixed(0)}',
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load dashboard',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
