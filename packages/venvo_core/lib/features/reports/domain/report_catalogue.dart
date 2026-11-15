import '../../../core/constants/permissions.dart';
import 'report_models.dart';

/// The eighteen reports the brief asks for.
///
/// Each one declares which filters it offers and which permission it needs, so
/// the screen can build itself from this list rather than hardcoding a menu,
/// and a user only ever sees reports over data they are allowed to see.
class ReportIds {
  const ReportIds._();

  // Sales
  static const String dailySales = 'sales-daily';
  static const String monthlySales = 'sales-monthly';
  static const String agentSales = 'sales-agent';
  static const String shopSales = 'sales-shop';
  static const String productSales = 'sales-product';

  // Stock
  static const String warehouseStock = 'stock-warehouse';
  static const String agentStock = 'stock-agent';
  static const String shopStock = 'stock-shop';
  static const String stockMovement = 'stock-movement';
  static const String stockValuation = 'stock-valuation';

  // Money
  static const String collections = 'money-collections';
  static const String outstanding = 'money-outstanding';
  static const String discounts = 'money-discounts';
  static const String returns = 'money-returns';

  // Finance
  static const String expenses = 'finance-expenses';
  static const String pettyCash = 'finance-petty-cash';
  static const String salaries = 'finance-salaries';
  static const String profitAndLoss = 'finance-profit-and-loss';
}

const List<ReportDefinition> kReports = [
  // --- Sales ---------------------------------------------------------------
  ReportDefinition(
    id: ReportIds.dailySales,
    title: 'Daily sales',
    description:
        'One row per day: what was invoiced, what it cost and what was made '
        'on it.',
    group: ReportGroup.sales,
    permission: Permissions.reportsView,
  ),
  ReportDefinition(
    id: ReportIds.monthlySales,
    title: 'Monthly sales',
    description: 'The same figures rolled up by month.',
    group: ReportGroup.sales,
    permission: Permissions.reportsView,
  ),
  ReportDefinition(
    id: ReportIds.agentSales,
    title: 'Agent-wise sales',
    description:
        'What each agent was invoiced, what it earned, and what they still '
        'owe.',
    group: ReportGroup.sales,
    permission: Permissions.reportsView,
    filters: {ReportFilterField.period, ReportFilterField.agent},
  ),
  ReportDefinition(
    id: ReportIds.shopSales,
    title: 'Shop-wise sales',
    description:
        'Wholesale supply per shop, kept apart from what that shop sold over '
        'its own counter.',
    group: ReportGroup.sales,
    permission: Permissions.reportsView,
    filters: {
      ReportFilterField.period,
      ReportFilterField.shop,
      ReportFilterField.agent,
    },
  ),
  ReportDefinition(
    id: ReportIds.productSales,
    title: 'Product-wise sales',
    description:
        'Units sold, revenue, cost and margin per product - which lines are '
        'actually worth stocking.',
    group: ReportGroup.sales,
    permission: Permissions.reportsView,
    filters: {
      ReportFilterField.period,
      ReportFilterField.category,
      ReportFilterField.product,
    },
  ),

  // --- Stock ---------------------------------------------------------------
  ReportDefinition(
    id: ReportIds.warehouseStock,
    title: 'Warehouse stock',
    description: 'What is in the warehouse now, at what it cost.',
    group: ReportGroup.stock,
    permission: Permissions.stockView,
    filters: {ReportFilterField.location, ReportFilterField.category},
  ),
  ReportDefinition(
    id: ReportIds.agentStock,
    title: 'Agent-wise stock',
    description: 'What each agent is holding, and what it is worth.',
    group: ReportGroup.stock,
    permission: Permissions.stockView,
    filters: {ReportFilterField.agent},
  ),
  ReportDefinition(
    id: ReportIds.shopStock,
    title: 'Shop-wise stock',
    description: 'What each shop is holding, and what it is worth.',
    group: ReportGroup.stock,
    permission: Permissions.stockView,
    filters: {ReportFilterField.shop},
  ),
  ReportDefinition(
    id: ReportIds.stockMovement,
    title: 'Stock movement',
    description:
        'Every movement in the period, read from the append-only ledger, with '
        'the balance each one left behind.',
    group: ReportGroup.stock,
    permission: Permissions.stockView,
    filters: {
      ReportFilterField.period,
      ReportFilterField.product,
      ReportFilterField.location,
    },
  ),
  ReportDefinition(
    id: ReportIds.stockValuation,
    title: 'Stock valuation',
    description:
        'Every product across the warehouse, agents, shops and quarantine, '
        'valued at weighted average cost.',
    group: ReportGroup.stock,
    permission: Permissions.stockView,
    filters: {ReportFilterField.category},
  ),

  // --- Money ---------------------------------------------------------------
  ReportDefinition(
    id: ReportIds.collections,
    title: 'Collections',
    description:
        'Money received in the period. Cheques awaiting clearance are listed '
        'but not counted as collected.',
    group: ReportGroup.money,
    permission: Permissions.paymentView,
    filters: {
      ReportFilterField.period,
      ReportFilterField.agent,
      ReportFilterField.shop,
    },
  ),
  ReportDefinition(
    id: ReportIds.outstanding,
    title: 'Outstanding balances',
    description:
        'What every agent and shop owes, built the same way as every other '
        'balance in the application: cleared money and posted credit notes '
        'only.',
    group: ReportGroup.money,
    permission: Permissions.paymentView,
    filters: {},
  ),
  ReportDefinition(
    id: ReportIds.discounts,
    title: 'Discounts given',
    description:
        'Every discount, who approved it and whether it went past the '
        'ceiling.',
    group: ReportGroup.money,
    permission: Permissions.reportsFinancial,
    filters: {
      ReportFilterField.period,
      ReportFilterField.agent,
      ReportFilterField.shop,
    },
  ),
  ReportDefinition(
    id: ReportIds.returns,
    title: 'Returns and credit',
    description:
        'Goods that came back, what the inspection decided, and the credit '
        'raised against them.',
    group: ReportGroup.money,
    permission: Permissions.returnView,
    filters: {
      ReportFilterField.period,
      ReportFilterField.agent,
      ReportFilterField.shop,
    },
  ),

  // --- Finance -------------------------------------------------------------
  ReportDefinition(
    id: ReportIds.expenses,
    title: 'Expenses',
    description: 'What was spent in the period, by category.',
    group: ReportGroup.finance,
    permission: Permissions.expenseView,
    filters: {ReportFilterField.period, ReportFilterField.category},
  ),
  ReportDefinition(
    id: ReportIds.pettyCash,
    title: 'Petty cash book',
    description:
        'The float: every movement in and out, with the running balance.',
    group: ReportGroup.finance,
    permission: Permissions.pettyCashView,
  ),
  ReportDefinition(
    id: ReportIds.salaries,
    title: 'Salaries',
    description:
        'The wage bill: what was earned, what advances were recovered, and '
        'what is still owed.',
    group: ReportGroup.finance,
    permission: Permissions.salaryView,
    filters: {ReportFilterField.period, ReportFilterField.employee},
  ),
  ReportDefinition(
    id: ReportIds.profitAndLoss,
    title: 'Profit and loss',
    description:
        'Read from the double-entry journal, so it agrees with the trial '
        'balance by construction.',
    group: ReportGroup.finance,
    permission: Permissions.financialLedgerView,
  ),
];

ReportDefinition? reportById(String id) {
  for (final report in kReports) {
    if (report.id == id) return report;
  }
  return null;
}
