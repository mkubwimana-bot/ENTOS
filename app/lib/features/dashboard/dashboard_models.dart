/// Summary metrics shown on the main dashboard.
class DashboardSummary {
  const DashboardSummary({
    required this.todaySales,
    required this.todayInvoiceCount,
    required this.moneyOwed,
    required this.lowStockCount,
    required this.lowStockProducts,
    required this.pendingMobileCount,
    required this.todayEstimatedProfit,
  });

  final double todaySales;
  final int todayInvoiceCount;
  final double moneyOwed;
  final int lowStockCount;
  final List<LowStockItem> lowStockProducts;
  final int pendingMobileCount;
  final double todayEstimatedProfit;
}

class LowStockItem {
  const LowStockItem({
    required this.productName,
    required this.currentQuantity,
    required this.reorderLevel,
  });

  final String productName;
  final double currentQuantity;
  final double reorderLevel;
}
