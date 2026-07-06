import 'package:flutter/material.dart';

import '../format/money_format.dart';

/// Whether the user enters price per unit or the full line amount.
enum LineAmountMode { unitPrice, lineTotal }

/// Resolves quantity, unit price, and line total from user input.
({double quantity, double unitPrice, double lineTotal}) resolveLineAmounts({
  required double quantity,
  required LineAmountMode mode,
  required double enteredAmount,
}) {
  if (quantity <= 0) {
    return (quantity: quantity, unitPrice: 0, lineTotal: 0);
  }
  if (mode == LineAmountMode.unitPrice) {
    final total = quantity * enteredAmount;
    return (quantity: quantity, unitPrice: enteredAmount, lineTotal: total);
  }
  final unit = enteredAmount / quantity;
  return (quantity: quantity, unitPrice: unit, lineTotal: enteredAmount);
}

/// Quantity + unit label + toggle between unit price and line total.
class QuantityLinePricingFields extends StatelessWidget {
  const QuantityLinePricingFields({
    required this.unitCode,
    required this.quantityController,
    required this.amountController,
    required this.amountMode,
    required this.onAmountModeChanged,
    required this.enabled,
    this.unitPriceLabel = 'Unit price (RWF)',
    this.lineTotalLabel = 'Line total (RWF)',
    this.onChanged,
    super.key,
  });

  final String unitCode;
  final TextEditingController quantityController;
  final TextEditingController amountController;
  final LineAmountMode amountMode;
  final ValueChanged<LineAmountMode> onAmountModeChanged;
  final bool enabled;
  final String unitPriceLabel;
  final String lineTotalLabel;
  final VoidCallback? onChanged;

  String? _validateQuantity(String? value) {
    final text = value?.trim() ?? '';
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter quantity';
    if (parsed <= 0) return 'Quantity must be greater than zero';
    return null;
  }

  String? _validateAmount(String? value) {
    final text = value?.trim() ?? '';
    final parsed = double.tryParse(text);
    if (parsed == null) {
      return amountMode == LineAmountMode.unitPrice
          ? 'Enter unit price'
          : 'Enter line total';
    }
    if (parsed < 0) return 'Amount must be zero or greater';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final quantity = double.tryParse(quantityController.text.trim());
    final entered = double.tryParse(amountController.text.trim());
    String? computedHint;
    if (quantity != null && quantity > 0 && entered != null) {
      final resolved = resolveLineAmounts(
        quantity: quantity,
        mode: amountMode,
        enteredAmount: entered,
      );
      computedHint = amountMode == LineAmountMode.unitPrice
          ? 'Line total: ${formatRwf(resolved.lineTotal)}'
          : 'Unit price: ${formatRwf(resolved.unitPrice)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<LineAmountMode>(
          segments: const [
            ButtonSegment(
              value: LineAmountMode.unitPrice,
              label: Text('Unit price'),
            ),
            ButtonSegment(
              value: LineAmountMode.lineTotal,
              label: Text('Line total'),
            ),
          ],
          selected: {amountMode},
          onSelectionChanged: enabled
              ? (selection) => onAmountModeChanged(selection.first)
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: quantityController,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity',
            helperText: 'Measured in $unitCode',
            suffixText: unitCode,
            border: const OutlineInputBorder(),
          ),
          validator: _validateQuantity,
          onChanged: (_) => onChanged?.call(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: amountController,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: amountMode == LineAmountMode.unitPrice
                ? unitPriceLabel
                : lineTotalLabel,
            border: const OutlineInputBorder(),
          ),
          validator: _validateAmount,
          onChanged: (_) => onChanged?.call(),
        ),
        if (computedHint != null) ...[
          const SizedBox(height: 8),
          Text(
            computedHint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact unit + amount mode toggle for cart rows.
class LineAmountModeToggle extends StatelessWidget {
  const LineAmountModeToggle({
    required this.mode,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final LineAmountMode mode;
  final bool enabled;
  final ValueChanged<LineAmountMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LineAmountMode>(
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: LineAmountMode.unitPrice, label: Text('Unit')),
        ButtonSegment(value: LineAmountMode.lineTotal, label: Text('Total')),
      ],
      selected: {mode},
      onSelectionChanged: enabled
          ? (selection) => onChanged(selection.first)
          : null,
    );
  }
}
