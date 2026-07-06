import 'package:supabase_flutter/supabase_flutter.dart';

class ActiveTenantMembership {
  const ActiveTenantMembership({
    required this.tenantId,
    required this.defaultBranchId,
  });

  final String tenantId;
  final String? defaultBranchId;
}

/// Resolves the tenant used for posting transactions.
///
/// Pilot users may have both an empty signup tenant and a linked import
/// tenant (e.g. Alpho). [limit(1)] on memberships without ordering caused
/// purchases/sales to post against the wrong tenant while the product list
/// showed catalogue rows from another.
Future<ActiveTenantMembership> resolveActiveTenantMembership(
  SupabaseClient client,
) async {
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    throw Exception('You must be signed in.');
  }

  final membershipRows = await client
      .from('user_tenants')
      .select('tenant_id, default_branch_id, membership_status')
      .eq('user_id', userId)
      .eq('membership_status', 'active');

  final memberships = membershipRows as List<dynamic>;
  if (memberships.isEmpty) {
    throw Exception('No active tenant membership found for this user.');
  }

  if (memberships.length == 1) {
    final row = memberships.first as Map<String, dynamic>;
    return ActiveTenantMembership(
      tenantId: row['tenant_id'] as String,
      defaultBranchId: row['default_branch_id'] as String?,
    );
  }

  final tenantIds = memberships
      .map((row) => (row as Map<String, dynamic>)['tenant_id'] as String)
      .toList();

  final productRows = await client
      .from('products')
      .select('tenant_id')
      .inFilter('tenant_id', tenantIds)
      .eq('status', 'active');

  final productCounts = {for (final id in tenantIds) id: 0};
  for (final row in productRows as List<dynamic>) {
    final map = row as Map<String, dynamic>;
    final tenantId = map['tenant_id'] as String;
    productCounts[tenantId] = (productCounts[tenantId] ?? 0) + 1;
  }

  final chosenTenantId = productCounts.entries
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;

  final chosen = memberships.cast<Map<String, dynamic>>().firstWhere(
    (row) => row['tenant_id'] == chosenTenantId,
    orElse: () => memberships.first as Map<String, dynamic>,
  );

  return ActiveTenantMembership(
    tenantId: chosen['tenant_id'] as String,
    defaultBranchId: chosen['default_branch_id'] as String?,
  );
}

Future<String> resolveDefaultBranchId({
  required SupabaseClient client,
  required String tenantId,
  required String? defaultBranchId,
}) async {
  if (defaultBranchId != null) return defaultBranchId;

  final branchRows = await client
      .from('branches')
      .select('id')
      .eq('tenant_id', tenantId)
      .eq('is_default', true)
      .limit(1);
  if ((branchRows as List).isEmpty) {
    throw Exception('No default branch found for tenant.');
  }
  return branchRows.first['id'] as String;
}

Future<String> resolveDefaultWarehouseId({
  required SupabaseClient client,
  required String tenantId,
  required String branchId,
}) async {
  final warehouseRows = await client
      .from('warehouses')
      .select('id')
      .eq('tenant_id', tenantId)
      .eq('branch_id', branchId)
      .eq('is_default', true)
      .limit(1);
  if ((warehouseRows as List).isEmpty) {
    throw Exception('No default warehouse found for branch.');
  }
  return warehouseRows.first['id'] as String;
}
