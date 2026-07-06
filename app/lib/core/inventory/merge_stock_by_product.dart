/// Raw row shape from [vw_current_stock].
class ProductStockRow {
  const ProductStockRow({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.warehouseName,
    required this.currentQuantity,
    required this.reorderLevel,
  });

  final String productId;
  final String productCode;
  final String productName;
  final String warehouseName;
  final double currentQuantity;
  final double? reorderLevel;

  factory ProductStockRow.fromMap(Map<String, dynamic> map) {
    return ProductStockRow(
      productId: map['product_id'] as String,
      productCode: map['product_code'] as String? ?? '',
      productName: map['product_name'] as String? ?? 'Unnamed product',
      warehouseName: map['warehouse_name'] as String? ?? 'Unknown warehouse',
      currentQuantity: (map['current_quantity'] as num?)?.toDouble() ?? 0,
      reorderLevel: (map['reorder_level'] as num?)?.toDouble(),
    );
  }
}

/// One line per product — sums quantity across warehouses/locations.
///
/// Alpho-style tenants can end up with two warehouse rows both named
/// "Main Store" (import vs app default). The DB view is correct; the
/// shop still has one logical store.
List<ProductStockRow> mergeStockRowsByProduct(List<ProductStockRow> rows) {
  final merged = <String, ProductStockRow>{};
  final warehouseNames = <String, Set<String>>{};

  for (final row in rows) {
    warehouseNames.putIfAbsent(row.productId, () => {}).add(row.warehouseName);

    final existing = merged[row.productId];
    if (existing == null) {
      merged[row.productId] = row;
      continue;
    }

    merged[row.productId] = ProductStockRow(
      productId: row.productId,
      productCode: row.productCode,
      productName: row.productName,
      warehouseName: _warehouseLabel(warehouseNames[row.productId]!),
      currentQuantity: existing.currentQuantity + row.currentQuantity,
      reorderLevel: row.reorderLevel ?? existing.reorderLevel,
    );
  }

  // Re-label warehouses now that all names are collected.
  return merged.values.map((row) {
    final names = warehouseNames[row.productId]!;
    return ProductStockRow(
      productId: row.productId,
      productCode: row.productCode,
      productName: row.productName,
      warehouseName: _warehouseLabel(names),
      currentQuantity: row.currentQuantity,
      reorderLevel: row.reorderLevel,
    );
  }).toList()..sort((a, b) => a.productName.compareTo(b.productName));
}

String warehouseLabelForProduct(Set<String> names) {
  if (names.isEmpty) return 'Unknown warehouse';
  if (names.length <= 1) return names.first;
  final sorted = names.toList()..sort();
  return '${sorted.first} (+${names.length - 1} more)';
}

String _warehouseLabel(Set<String> names) => warehouseLabelForProduct(names);

/// Merged valuation row (quantity summed across warehouses).
class ProductValuationRow {
  const ProductValuationRow({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.warehouseName,
    required this.currentQuantity,
    required this.costPrice,
  });

  final String productId;
  final String productCode;
  final String productName;
  final String warehouseName;
  final double currentQuantity;
  final double costPrice;

  double get inventoryValue => currentQuantity * costPrice;
}

List<ProductValuationRow> mergeValuationRowsByProduct(
  List<ProductValuationRow> rows,
) {
  final mergedQty = <String, double>{};
  final meta = <String, ProductValuationRow>{};
  final warehouseNames = <String, Set<String>>{};

  for (final row in rows) {
    warehouseNames.putIfAbsent(row.productId, () => {}).add(row.warehouseName);
    mergedQty[row.productId] =
        (mergedQty[row.productId] ?? 0) + row.currentQuantity;
    meta[row.productId] = row;
  }

  return mergedQty.entries.map((entry) {
    final sample = meta[entry.key]!;
    return ProductValuationRow(
      productId: entry.key,
      productCode: sample.productCode,
      productName: sample.productName,
      warehouseName: warehouseLabelForProduct(warehouseNames[entry.key]!),
      currentQuantity: entry.value,
      costPrice: sample.costPrice,
    );
  }).toList()..sort((a, b) => a.productName.compareTo(b.productName));
}
