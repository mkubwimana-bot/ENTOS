import 'package:flutter/material.dart';

/// Past-or-today date picker for recording sales, payments, and purchases.
class TransactionDateField extends StatelessWidget {
  const TransactionDateField({
    required this.selectedDate,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  static DateTime todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static String toIsoDate(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _pickDate(BuildContext context) async {
    final today = todayDate();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate.isAfter(today) ? today : selectedDate,
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: 'Transaction date',
    );
    if (picked != null) {
      onChanged(DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = toIsoDate(selectedDate);
    final isToday = selectedDate == todayDate();

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Date',
        border: OutlineInputBorder(),
      ),
      child: InkWell(
        onTap: enabled ? () => _pickDate(context) : null,
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isToday ? 'Today ($label)' : label,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (enabled)
              const Icon(Icons.edit_calendar_outlined, size: 20),
          ],
        ),
      ),
    );
  }
}
