import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import '../customers/customers_screen.dart';
import '../dashboard/dashboard_providers.dart';
import '../dashboard/dashboard_screen.dart';
import '../inventory/current_stock_screen.dart';
import '../inventory/low_stock_screen.dart';
import '../inventory/stock_adjustment_screen.dart';
import '../inventory/stock_check_screen.dart';
import '../inventory/stock_movement_history_screen.dart';
import '../payments/mobile_payment_screen.dart';
import '../payments/payments_list_screen.dart';
import '../payments/record_payment_screen.dart';
import '../products/products_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/new_sale_screen.dart';
import '../sales/offline_sale_queue.dart';
import '../sales/quick_sale_screen.dart';
import '../sales/sales_list_screen.dart';
import '../settings/business_setup_screen.dart';
import '../settings/subscription_status_screen.dart';
import '../sync/offline_auto_sync.dart';
import '../sync/sync_conflict_review_screen.dart';
import '../sync/sync_status_screen.dart';

/// Main menu after sign-in. Navigation hub for all business screens.
///
/// Dashboard metrics (today's sales, money owed, etc.) live on [DashboardScreen]
/// and are opened from here — not shown on this menu by default.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final email = client.auth.currentUser?.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SME-OS'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
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
            const SizedBox(height: 24),
          ],
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DashboardScreen(),
                ),
              );
            },
            icon: const Icon(Icons.dashboard_outlined),
            label: const Text('Dashboard'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BusinessSetupScreen(),
                ),
              );
            },
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Business Setup'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SubscriptionStatusScreen(),
                ),
              );
            },
            icon: const Icon(Icons.card_membership_outlined),
            label: const Text('Subscription'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProfileScreen(),
                ),
              );
            },
            icon: const Icon(Icons.person_outline),
            label: const Text('My Profile'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProductsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Open Product List'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomersScreen(),
                ),
              );
            },
            icon: const Icon(Icons.people_alt_outlined),
            label: const Text('Open Customer List'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final recorded = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const NewSaleScreen(),
                ),
              );
              if (recorded == true) {
                ref.invalidate(dashboardSummaryProvider);
              }
            },
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('New Sale'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final recorded = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const QuickSaleScreen(),
                ),
              );
              if (recorded == true) {
                ref.invalidate(dashboardSummaryProvider);
                ref.invalidate(offlinePendingCountProvider);
                requestOfflineAutoSync(ref);
              }
            },
            icon: const Icon(Icons.bolt_outlined),
            label: const Text('Mobile Quick Sale'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SalesListScreen(),
                ),
              );
            },
            icon: const Icon(Icons.list_alt_outlined),
            label: const Text('Sales List'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final recorded = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const RecordPaymentScreen(),
                ),
              );
              if (recorded == true) {
                ref.invalidate(dashboardSummaryProvider);
              }
            },
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Record Payment'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PaymentsListScreen(),
                ),
              );
            },
            icon: const Icon(Icons.receipt_outlined),
            label: const Text('Payments List'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final recorded = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const MobilePaymentScreen(),
                ),
              );
              if (recorded == true) {
                ref.invalidate(dashboardSummaryProvider);
              }
            },
            icon: const Icon(Icons.smartphone_outlined),
            label: const Text('Mobile Payment'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CurrentStockScreen(),
                ),
              );
            },
            icon: const Icon(Icons.warehouse_outlined),
            label: const Text('Current Stock'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StockCheckScreen(),
                ),
              );
            },
            icon: const Icon(Icons.search_outlined),
            label: const Text('Stock Check'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final adjusted = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const StockAdjustmentScreen(),
                ),
              );
              if (adjusted == true) {
                ref.invalidate(dashboardSummaryProvider);
              }
            },
            icon: const Icon(Icons.tune_outlined),
            label: const Text('Stock Adjustment'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StockMovementHistoryScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history_outlined),
            label: const Text('Stock Movements'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LowStockScreen(),
                ),
              );
            },
            icon: const Icon(Icons.warning_amber_outlined),
            label: const Text('Low Stock'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReportsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.bar_chart_outlined),
            label: const Text('Reports'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SyncConflictReviewScreen(),
                ),
              );
              ref.invalidate(syncReviewIssueCountProvider);
            },
            icon: const Icon(Icons.rule_folder_outlined),
            label: const _SyncReviewLabel(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SyncStatusScreen(),
                ),
              );
              ref.invalidate(offlinePendingCountProvider);
              ref.invalidate(dashboardSummaryProvider);
              requestOfflineAutoSync(ref);
            },
            icon: const Icon(Icons.sync_outlined),
            label: const _SyncStatusLabel(),
          ),
        ],
      ),
    );
  }
}

/// Shows "Sync Review" with a count of open server-side issues.
class _SyncReviewLabel extends ConsumerWidget {
  const _SyncReviewLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(syncReviewIssueCountProvider).asData?.value ?? 0;
    return Text(count > 0 ? 'Sync Review ($count)' : 'Sync Review');
  }
}

/// Shows "Sync Status" with a count of locally queued (unsynced) sales.
class _SyncStatusLabel extends ConsumerWidget {
  const _SyncStatusLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(offlinePendingCountProvider).asData?.value ?? 0;
    return Text(count > 0 ? 'Sync Status ($count)' : 'Sync Status');
  }
}
