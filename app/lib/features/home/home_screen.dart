import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import '../customers/customers_screen.dart';
import '../dashboard/dashboard_providers.dart';
import '../dashboard/dashboard_screen.dart';
import '../inventory/stock_hub_tab.dart';
import '../products/products_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/offline_sale_queue.dart';
import '../sales/sales_hub_tab.dart';
import '../settings/business_setup_screen.dart';
import '../settings/subscription_status_screen.dart';
import '../sync/offline_auto_sync.dart';
import '../sync/sync_conflict_review_screen.dart';
import '../sync/sync_status_screen.dart';
import 'home_dashboard_tab.dart';
import 'home_submenu_screen.dart';

/// Signed-in shell: dashboard home tab + bottom navigation.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _tabIndex = 0;

  void _openSubMenu(String title, List<HomeSubMenuItem> items) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HomeSubMenuScreen(title: title, items: items),
      ),
    );
  }

  List<HomeSubMenuItem> _settingsItems() => [
    HomeSubMenuItem(
      label: 'Business Setup',
      icon: Icons.storefront_outlined,
      onTap: (context, _) async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const BusinessSetupScreen()),
        );
      },
    ),
    HomeSubMenuItem(
      label: 'Subscription',
      icon: Icons.card_membership_outlined,
      onTap: (context, _) async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const SubscriptionStatusScreen(),
          ),
        );
      },
    ),
    HomeSubMenuItem(
      label: 'My Profile',
      icon: Icons.person_outline,
      onTap: (context, _) async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
        );
      },
    ),
  ];

  void _openSalesTab() => setState(() => _tabIndex = 1);

  void _openStockTab() => setState(() => _tabIndex = 2);

  void _openReportsTab() => setState(() => _tabIndex = 3);

  List<HomeSubMenuItem> _moreItems() {
    final pendingSync =
        ref.read(offlinePendingCountProvider).asData?.value ?? 0;
    final syncIssues =
        ref.read(syncReviewIssueCountProvider).asData?.value ?? 0;
    return [
      HomeSubMenuItem(
        label: 'Full Dashboard',
        icon: Icons.dashboard_outlined,
        onTap: (context, _) async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
          );
        },
      ),
      HomeSubMenuItem(
        label: 'Sync Status${pendingSync > 0 ? ' ($pendingSync)' : ''}',
        icon: Icons.sync_outlined,
        onTap: (context, ref) async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const SyncStatusScreen()),
          );
          ref.invalidate(offlinePendingCountProvider);
          ref.invalidate(dashboardSummaryProvider);
          requestOfflineAutoSync(ref);
        },
      ),
      HomeSubMenuItem(
        label: 'Sync Review${syncIssues > 0 ? ' ($syncIssues)' : ''}',
        icon: Icons.rule_folder_outlined,
        onTap: (context, ref) async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const SyncConflictReviewScreen(),
            ),
          );
          ref.invalidate(syncReviewIssueCountProvider);
        },
      ),
      ..._settingsItems(),
    ];
  }

  Future<void> _openSync() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SyncStatusScreen()),
    );
    ref.invalidate(offlinePendingCountProvider);
    ref.invalidate(dashboardSummaryProvider);
    requestOfflineAutoSync(ref);
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    const navGreen = Color(0xFF2E7D3E);

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Full Dashboard'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DashboardScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  _openSubMenu('Settings', _settingsItems());
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () {
                  Navigator.pop(context);
                  client.auth.signOut();
                },
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          HomeDashboardTab(
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            onSalesTap: _openSalesTab,
            onProductsTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProductsScreen()),
              );
            },
            onCustomersTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomersScreen(),
                ),
              );
            },
            onStockTap: _openStockTab,
            onReportsTap: _openReportsTab,
            onSyncTap: _openSync,
          ),
          const SalesHubTab(),
          const StockHubTab(),
          const ReportsScreen(embeddedInShell: true),
          _HomeTabList(title: 'More', items: _moreItems()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        backgroundColor: Colors.white,
        indicatorColor: navGreen.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home, color: navGreen),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.point_of_sale_outlined),
            selectedIcon: const Icon(Icons.point_of_sale, color: navGreen),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2, color: navGreen),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart, color: navGreen),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            selectedIcon: const Icon(Icons.more_horiz, color: navGreen),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _HomeTabList extends ConsumerWidget {
  const _HomeTabList({required this.title, required this.items});

  final String title;
  final List<HomeSubMenuItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }
            final item = items[index - 1];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE6EBF0)),
              ),
              child: ListTile(
                leading: Icon(item.icon, color: const Color(0xFF2E7D3E)),
                title: Text(item.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => item.onTap(context, ref),
              ),
            );
          },
        ),
      ),
    );
  }
}
