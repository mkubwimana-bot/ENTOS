import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';
import '../sales/offline_sale_queue.dart';

class OpenConflictItem {
  const OpenConflictItem({
    required this.id,
    required this.conflictType,
    required this.severity,
    required this.description,
    required this.createdAt,
    required this.draftType,
    required this.provisionalNumber,
    required this.clientReferenceId,
  });

  final String id;
  final String conflictType;
  final String severity;
  final String description;
  final String createdAt;
  final String? draftType;
  final String? provisionalNumber;
  final String? clientReferenceId;
}

class ProblemDraftItem {
  const ProblemDraftItem({
    required this.draftId,
    required this.draftType,
    required this.status,
    required this.provisionalNumber,
    required this.clientReferenceId,
    required this.errorMessage,
    required this.queueStatus,
    required this.lastError,
    required this.createdAt,
  });

  final String draftId;
  final String draftType;
  final String status;
  final String? provisionalNumber;
  final String? clientReferenceId;
  final String? errorMessage;
  final String? queueStatus;
  final String? lastError;
  final String createdAt;
}

class SyncReviewData {
  const SyncReviewData({
    required this.openConflicts,
    required this.problemDrafts,
  });

  final List<OpenConflictItem> openConflicts;
  final List<ProblemDraftItem> problemDrafts;

  int get totalIssues => openConflicts.length + problemDrafts.length;
}

final syncReviewDataProvider = FutureProvider.autoDispose<SyncReviewData>((
  ref,
) async {
  final client = ref.read(supabaseClientProvider);

  final conflictRows = await client
      .from('conflict_logs')
      .select(
        'id, conflict_type, severity, description, created_at, '
        'transaction_drafts(draft_type, provisional_number, client_reference_id)',
      )
      .eq('resolution_status', 'open')
      .order('created_at', ascending: false)
      .limit(100);

  final openConflicts = (conflictRows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    final draft = map['transaction_drafts'] as Map<String, dynamic>?;
    return OpenConflictItem(
      id: map['id'] as String,
      conflictType: map['conflict_type'] as String? ?? 'other',
      severity: map['severity'] as String? ?? 'medium',
      description: map['description'] as String? ?? 'Conflict needs review',
      createdAt: map['created_at'] as String? ?? '',
      draftType: draft?['draft_type'] as String?,
      provisionalNumber: draft?['provisional_number'] as String?,
      clientReferenceId: draft?['client_reference_id'] as String?,
    );
  }).toList();

  final draftRows = await client
      .from('vw_pending_mobile_transactions')
      .select(
        'draft_id, draft_type, status, provisional_number, client_reference_id, '
        'error_message, queue_status, last_error, created_at',
      )
      .inFilter('status', ['failed', 'conflict'])
      .order('created_at', ascending: false)
      .limit(100);

  final problemDrafts = (draftRows as List<dynamic>).map((row) {
    final map = row as Map<String, dynamic>;
    return ProblemDraftItem(
      draftId: map['draft_id'] as String,
      draftType: map['draft_type'] as String? ?? 'unknown',
      status: map['status'] as String? ?? 'failed',
      provisionalNumber: map['provisional_number'] as String?,
      clientReferenceId: map['client_reference_id'] as String?,
      errorMessage: map['error_message'] as String?,
      queueStatus: map['queue_status'] as String?,
      lastError: map['last_error'] as String?,
      createdAt: map['created_at'] as String? ?? '',
    );
  }).toList();

  return SyncReviewData(
    openConflicts: openConflicts,
    problemDrafts: problemDrafts,
  );
});

/// Count of server-side issues needing review (for badges on Sync Status).
final syncReviewIssueCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final data = await ref.watch(syncReviewDataProvider.future);
  return data.totalIssues;
});

class SyncConflictReviewScreen extends ConsumerWidget {
  const SyncConflictReviewScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(syncReviewDataProvider);
    ref.invalidate(syncReviewIssueCountProvider);
    await ref.read(syncReviewDataProvider.future);
  }

  Future<void> _resolveConflict(
    BuildContext context,
    WidgetRef ref,
    OpenConflictItem conflict,
    String resolutionStatus,
  ) async {
    final client = ref.read(supabaseClientProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await client
          .from('conflict_logs')
          .update({
            'resolution_status': resolutionStatus,
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
            'resolved_by': userId,
            'resolution_notes': resolutionStatus == 'ignored'
                ? 'Dismissed from mobile review'
                : 'Marked resolved from mobile review',
          })
          .eq('id', conflict.id);

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Conflict updated')));
      }
      await _refresh(ref);
    } on PostgrestException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  String _formatLabel(String value) => value.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(syncReviewDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Review'),
        actions: const [MainMenuNavAction()],
      ),
      body: reviewAsync.when(
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
                  isOfflineError(error)
                      ? 'Offline — connect to review server issues.'
                      : 'Could not load: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(syncReviewDataProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: data.totalIssues == 0
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No server conflicts or failed drafts')),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Open conflicts (${data.openConflicts.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (data.openConflicts.isEmpty)
                      const Text('No open conflict logs.')
                    else
                      ...data.openConflicts.map(
                        (conflict) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatLabel(conflict.conflictType),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(conflict.description),
                                if (conflict.clientReferenceId != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Ref: ${conflict.clientReferenceId}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _resolveConflict(
                                        context,
                                        ref,
                                        conflict,
                                        'ignored',
                                      ),
                                      child: const Text('Dismiss'),
                                    ),
                                    TextButton(
                                      onPressed: () => _resolveConflict(
                                        context,
                                        ref,
                                        conflict,
                                        'resolved',
                                      ),
                                      child: const Text('Mark resolved'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const Divider(height: 32),
                    Text(
                      'Failed server drafts (${data.problemDrafts.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Drafts uploaded to the server that could not be posted. '
                      'Fix the underlying issue, then retry from Sync Status.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (data.problemDrafts.isEmpty)
                      const Text('No failed server drafts.')
                    else
                      ...data.problemDrafts.map(
                        (draft) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              draft.provisionalNumber ??
                                  draft.clientReferenceId ??
                                  draft.draftId,
                            ),
                            subtitle: Text(
                              '${_formatLabel(draft.draftType)} · '
                              '${_formatLabel(draft.status)}'
                              '${draft.queueStatus != null ? ' · queue ${draft.queueStatus}' : ''}'
                              '\n${draft.errorMessage ?? draft.lastError ?? 'Unknown error'}',
                            ),
                            isThreeLine: true,
                            leading: Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
