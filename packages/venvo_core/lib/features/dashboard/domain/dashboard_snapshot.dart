import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'dashboard_snapshot.g.dart';

/// Everything the dashboard shows, read in one pass so the figures on screen
/// are all from the same instant.
@JsonSerializable()
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.generatedAt,
    required this.todaysSales,
    required this.todaysCollections,
    required this.todaysExpenses,
    required this.monthSales,
    required this.monthExpenses,
    required this.monthGrossProfit,
    required this.receivableFromAgents,
    required this.receivableFromShops,
    required this.warehouseStockValue,
    required this.agentStockValue,
    required this.shopStockValue,
    required this.damagedStockValue,
    required this.pendingChequeTotal,
    required this.pendingChequeCount,
    required this.lowStockCount,
    required this.activeProductCount,
    required this.activeAgentCount,
    required this.activeShopCount,
    required this.unallocatedAdvances,
    required this.returnsAwaitingInspection,
    required this.returnsAwaitingInspectionUnits,
    required this.unappliedCreditNotes,
    required this.pettyCashFloat,
    required this.unpaidSalaries,
    required this.outstandingEmployeeAdvances,
    required this.monthNetProfit,
    required this.monthRetailSales,
  });

  /// An empty snapshot, used as the initial value before the first load.
  factory DashboardSnapshot.empty(DateTime at) => DashboardSnapshot(
    generatedAt: at,
    todaysSales: Money.zero,
    todaysCollections: Money.zero,
    todaysExpenses: Money.zero,
    monthSales: Money.zero,
    monthExpenses: Money.zero,
    monthGrossProfit: Money.zero,
    receivableFromAgents: Money.zero,
    receivableFromShops: Money.zero,
    warehouseStockValue: Money.zero,
    agentStockValue: Money.zero,
    shopStockValue: Money.zero,
    damagedStockValue: Money.zero,
    pendingChequeTotal: Money.zero,
    pendingChequeCount: 0,
    lowStockCount: 0,
    activeProductCount: 0,
    activeAgentCount: 0,
    activeShopCount: 0,
    unallocatedAdvances: Money.zero,
    returnsAwaitingInspection: 0,
    returnsAwaitingInspectionUnits: 0,
    unappliedCreditNotes: Money.zero,
    pettyCashFloat: Money.zero,
    unpaidSalaries: Money.zero,
    outstandingEmployeeAdvances: Money.zero,
    monthNetProfit: Money.zero,
    monthRetailSales: Money.zero,
  );

  final DateTime generatedAt;

  final Money todaysSales;

  /// Cash and cleared bank receipts only. A cheque received today but not yet
  /// cleared is *not* a collection; it appears in [pendingChequeTotal].
  final Money todaysCollections;
  final Money todaysExpenses;

  final Money monthSales;
  final Money monthExpenses;

  /// Net sales less the cost snapshotted on each invoice line.
  final Money monthGrossProfit;

  final Money receivableFromAgents;
  final Money receivableFromShops;

  final Money warehouseStockValue;
  final Money agentStockValue;
  final Money shopStockValue;
  final Money damagedStockValue;

  final Money pendingChequeTotal;
  final int pendingChequeCount;

  final int lowStockCount;
  final int activeProductCount;
  final int activeAgentCount;
  final int activeShopCount;

  /// Money received that has not been allocated to any invoice.
  final Money unallocatedAdvances;

  /// Returns whose goods are sitting in transit, uninspected. They are nobody's
  /// sellable stock until somebody looks at them, which makes this a queue
  /// rather than a statistic.
  final int returnsAwaitingInspection;
  final int returnsAwaitingInspectionUnits;

  /// Posted credit the business still owes its parties.
  final Money unappliedCreditNotes;

  final Money pettyCashFloat;

  /// Approved salaries not yet paid in full.
  final Money unpaidSalaries;

  /// Advances employees owe back.
  final Money outstandingEmployeeAdvances;

  /// Read from the double-entry journal, so it agrees with the profit and
  /// loss rather than being a second opinion about it.
  final Money monthNetProfit;

  /// What shops sold over their own counters this month, reported apart from
  /// the wholesale supply that stocked them.
  final Money monthRetailSales;

  Money get totalReceivable => receivableFromAgents + receivableFromShops;

  Money get totalStockValue =>
      warehouseStockValue + agentStockValue + shopStockValue;

  /// Cash the business can lay hands on: the float plus whatever is in the
  /// cash box is not tracked here, so this is the float alone.
  bool get hasInspectionBacklog => returnsAwaitingInspection > 0;

  bool get isEmptyBusiness =>
      activeProductCount == 0 && activeAgentCount == 0 && activeShopCount == 0;

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) =>
      _$DashboardSnapshotFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardSnapshotToJson(this);
}
