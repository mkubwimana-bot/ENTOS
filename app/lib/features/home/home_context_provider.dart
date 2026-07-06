import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/tenant/active_tenant.dart';
import '../dashboard/dashboard_providers.dart';
import '../sales/offline_sale_queue.dart';

class HomeContext {
  const HomeContext({
    required this.userName,
    required this.businessLine,
    required this.pendingSyncCount,
  });

  final String userName;
  final String businessLine;
  final int pendingSyncCount;
}

final homeContextProvider = FutureProvider.autoDispose<HomeContext>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  final email = client.auth.currentUser?.email ?? '';
  if (userId == null) throw Exception('You must be signed in.');

  final membership = await resolveActiveTenantMembership(client);
  final tenantId = membership.tenantId;
  final branchId = await resolveDefaultBranchId(
    client: client,
    tenantId: tenantId,
    defaultBranchId: membership.defaultBranchId,
  );

  final results = await Future.wait<dynamic>([
    client.from('app_users').select('full_name').eq('id', userId).limit(1),
    client
        .from('tenants')
        .select('trading_name, legal_name')
        .eq('id', tenantId)
        .limit(1),
    client.from('branches').select('name').eq('id', branchId).limit(1),
  ]);

  final userRow = (results[0] as List<dynamic>).isEmpty
      ? null
      : (results[0] as List<dynamic>).first as Map<String, dynamic>;
  final tenantRow = (results[1] as List<dynamic>).first as Map<String, dynamic>;
  final branchRow = (results[2] as List<dynamic>).first as Map<String, dynamic>;

  final fullName = userRow?['full_name'] as String?;
  final userName = (fullName != null && fullName.trim().isNotEmpty)
      ? fullName.trim()
      : email.split('@').first;

  final businessName =
      (tenantRow['trading_name'] as String?)?.trim().isNotEmpty == true
      ? tenantRow['trading_name'] as String
      : tenantRow['legal_name'] as String? ?? 'Your business';
  final branchName = branchRow['name'] as String? ?? 'Main Branch';

  final pendingSync = ref.watch(offlinePendingCountProvider).asData?.value ?? 0;

  return HomeContext(
    userName: userName,
    businessLine: '$businessName · $branchName',
    pendingSyncCount: pendingSync,
  );
});

/// Today vs yesterday sales for the trend chip on the home hero card.
final homeSalesTrendProvider = FutureProvider.autoDispose<double?>((ref) async {
  ref.watch(dashboardSummaryProvider);
  final client = ref.read(supabaseClientProvider);
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  final y = yesterday.year.toString();
  final m = yesterday.month.toString().padLeft(2, '0');
  final d = yesterday.day.toString().padLeft(2, '0');
  final dateIso = '$y-$m-$d';

  final rows = await client
      .from('vw_daily_sales')
      .select('total_sales')
      .eq('invoice_date', dateIso);

  var yesterdayTotal = 0.0;
  for (final row in rows as List<dynamic>) {
    final map = row as Map<String, dynamic>;
    yesterdayTotal += (map['total_sales'] as num?)?.toDouble() ?? 0;
  }

  final today = await ref.read(dashboardSummaryProvider.future);
  if (yesterdayTotal <= 0) return null;
  return ((today.todaySales - yesterdayTotal) / yesterdayTotal) * 100;
});
