import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ReportPeriodKind { today, thisWeek, thisMonth, custom }

class ReportPeriodSelection {
  const ReportPeriodSelection({
    required this.kind,
    this.customStart,
    this.customEnd,
  });

  final ReportPeriodKind kind;
  final DateTime? customStart;
  final DateTime? customEnd;

  ReportPeriodSelection copyWith({
    ReportPeriodKind? kind,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    return ReportPeriodSelection(
      kind: kind ?? this.kind,
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
    );
  }

  ({DateTime start, DateTime end}) get range {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    switch (kind) {
      case ReportPeriodKind.today:
        return (start: todayDate, end: todayDate);
      case ReportPeriodKind.thisWeek:
        final start = todayDate.subtract(Duration(days: todayDate.weekday - 1));
        return (start: start, end: todayDate);
      case ReportPeriodKind.thisMonth:
        final start = DateTime(todayDate.year, todayDate.month, 1);
        return (start: start, end: todayDate);
      case ReportPeriodKind.custom:
        final start = customStart ?? todayDate;
        final end = customEnd ?? todayDate;
        if (start.isAfter(end)) return (start: end, end: start);
        return (start: start, end: end);
    }
  }

  String get label {
    final r = range;
    final start = formatIsoDate(r.start);
    final end = formatIsoDate(r.end);
    switch (kind) {
      case ReportPeriodKind.today:
        return 'Today ($start)';
      case ReportPeriodKind.thisWeek:
        return 'This week ($start – $end)';
      case ReportPeriodKind.thisMonth:
        return 'This month ($start – $end)';
      case ReportPeriodKind.custom:
        return 'Custom ($start – $end)';
    }
  }
}

String formatIsoDate(DateTime date) {
  final y = date.year;
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class ReportPeriodNotifier extends Notifier<ReportPeriodSelection> {
  @override
  ReportPeriodSelection build() =>
      const ReportPeriodSelection(kind: ReportPeriodKind.thisMonth);

  void setKind(ReportPeriodKind kind) {
    state = ReportPeriodSelection(kind: kind);
  }

  void setCustom(DateTime start, DateTime end) {
    state = ReportPeriodSelection(
      kind: ReportPeriodKind.custom,
      customStart: start,
      customEnd: end,
    );
  }
}

final reportPeriodProvider =
    NotifierProvider<ReportPeriodNotifier, ReportPeriodSelection>(
  ReportPeriodNotifier.new,
);

class StockPeriodNotifier extends Notifier<ReportPeriodSelection> {
  @override
  ReportPeriodSelection build() =>
      const ReportPeriodSelection(kind: ReportPeriodKind.thisMonth);

  void setKind(ReportPeriodKind kind) {
    state = ReportPeriodSelection(kind: kind);
  }

  void setCustom(DateTime start, DateTime end) {
    state = ReportPeriodSelection(
      kind: ReportPeriodKind.custom,
      customStart: start,
      customEnd: end,
    );
  }
}

final stockPeriodProvider =
    NotifierProvider<StockPeriodNotifier, ReportPeriodSelection>(
  StockPeriodNotifier.new,
);

class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({
    required this.period,
    required this.onSetKind,
    required this.onSetCustom,
    this.hint,
  });

  final ReportPeriodSelection period;
  final void Function(ReportPeriodKind kind) onSetKind;
  final void Function(DateTime start, DateTime end) onSetCustom;
  final String? hint;

  Future<void> _pickCustomRange(BuildContext context) async {
    final initialRange = DateTimeRange(
      start: period.customStart ?? period.range.start,
      end: period.customEnd ?? period.range.end,
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: initialRange,
    );
    if (picked == null) return;
    onSetCustom(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Period', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Today'),
                  selected: period.kind == ReportPeriodKind.today,
                  onSelected: (_) => onSetKind(ReportPeriodKind.today),
                ),
                ChoiceChip(
                  label: const Text('This week'),
                  selected: period.kind == ReportPeriodKind.thisWeek,
                  onSelected: (_) => onSetKind(ReportPeriodKind.thisWeek),
                ),
                ChoiceChip(
                  label: const Text('This month'),
                  selected: period.kind == ReportPeriodKind.thisMonth,
                  onSelected: (_) => onSetKind(ReportPeriodKind.thisMonth),
                ),
                ChoiceChip(
                  label: const Text('Custom'),
                  selected: period.kind == ReportPeriodKind.custom,
                  onSelected: (_) => _pickCustomRange(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              period.label + (hint != null ? ' · $hint' : ''),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (period.kind == ReportPeriodKind.custom) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _pickCustomRange(context),
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: const Text('Change dates'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ReportPeriodBar extends ConsumerWidget {
  const ReportPeriodBar({super.key, this.hint});

  final String? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final notifier = ref.read(reportPeriodProvider.notifier);
    return _PeriodBar(
      period: period,
      hint: hint,
      onSetKind: notifier.setKind,
      onSetCustom: notifier.setCustom,
    );
  }
}

class StockPeriodBar extends ConsumerWidget {
  const StockPeriodBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stockPeriodProvider);
    final notifier = ref.read(stockPeriodProvider.notifier);
    return _PeriodBar(
      period: period,
      hint: 'filters movements and period totals',
      onSetKind: notifier.setKind,
      onSetCustom: notifier.setCustom,
    );
  }
}
