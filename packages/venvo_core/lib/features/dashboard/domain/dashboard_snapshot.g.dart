// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_snapshot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DashboardSnapshot _$DashboardSnapshotFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DashboardSnapshot', json, ($checkedConvert) {
      final val = DashboardSnapshot(
        generatedAt: $checkedConvert(
          'generatedAt',
          (v) => DateTime.parse(v as String),
        ),
        todaysSales: $checkedConvert(
          'todaysSales',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        todaysCollections: $checkedConvert(
          'todaysCollections',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        todaysExpenses: $checkedConvert(
          'todaysExpenses',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        monthSales: $checkedConvert(
          'monthSales',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        monthExpenses: $checkedConvert(
          'monthExpenses',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        monthGrossProfit: $checkedConvert(
          'monthGrossProfit',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        receivableFromAgents: $checkedConvert(
          'receivableFromAgents',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        receivableFromShops: $checkedConvert(
          'receivableFromShops',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        warehouseStockValue: $checkedConvert(
          'warehouseStockValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        agentStockValue: $checkedConvert(
          'agentStockValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        shopStockValue: $checkedConvert(
          'shopStockValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        damagedStockValue: $checkedConvert(
          'damagedStockValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        pendingChequeTotal: $checkedConvert(
          'pendingChequeTotal',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        pendingChequeCount: $checkedConvert(
          'pendingChequeCount',
          (v) => (v as num).toInt(),
        ),
        lowStockCount: $checkedConvert(
          'lowStockCount',
          (v) => (v as num).toInt(),
        ),
        activeProductCount: $checkedConvert(
          'activeProductCount',
          (v) => (v as num).toInt(),
        ),
        activeAgentCount: $checkedConvert(
          'activeAgentCount',
          (v) => (v as num).toInt(),
        ),
        activeShopCount: $checkedConvert(
          'activeShopCount',
          (v) => (v as num).toInt(),
        ),
        unallocatedAdvances: $checkedConvert(
          'unallocatedAdvances',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        returnsAwaitingInspection: $checkedConvert(
          'returnsAwaitingInspection',
          (v) => (v as num).toInt(),
        ),
        returnsAwaitingInspectionUnits: $checkedConvert(
          'returnsAwaitingInspectionUnits',
          (v) => (v as num).toInt(),
        ),
        unappliedCreditNotes: $checkedConvert(
          'unappliedCreditNotes',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        pettyCashFloat: $checkedConvert(
          'pettyCashFloat',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        unpaidSalaries: $checkedConvert(
          'unpaidSalaries',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        outstandingEmployeeAdvances: $checkedConvert(
          'outstandingEmployeeAdvances',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        monthNetProfit: $checkedConvert(
          'monthNetProfit',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        monthRetailSales: $checkedConvert(
          'monthRetailSales',
          (v) => Money.fromJson((v as num).toInt()),
        ),
      );
      return val;
    });

Map<String, dynamic> _$DashboardSnapshotToJson(
  DashboardSnapshot instance,
) => <String, dynamic>{
  'generatedAt': instance.generatedAt.toIso8601String(),
  'todaysSales': instance.todaysSales.toJson(),
  'todaysCollections': instance.todaysCollections.toJson(),
  'todaysExpenses': instance.todaysExpenses.toJson(),
  'monthSales': instance.monthSales.toJson(),
  'monthExpenses': instance.monthExpenses.toJson(),
  'monthGrossProfit': instance.monthGrossProfit.toJson(),
  'receivableFromAgents': instance.receivableFromAgents.toJson(),
  'receivableFromShops': instance.receivableFromShops.toJson(),
  'warehouseStockValue': instance.warehouseStockValue.toJson(),
  'agentStockValue': instance.agentStockValue.toJson(),
  'shopStockValue': instance.shopStockValue.toJson(),
  'damagedStockValue': instance.damagedStockValue.toJson(),
  'pendingChequeTotal': instance.pendingChequeTotal.toJson(),
  'pendingChequeCount': instance.pendingChequeCount,
  'lowStockCount': instance.lowStockCount,
  'activeProductCount': instance.activeProductCount,
  'activeAgentCount': instance.activeAgentCount,
  'activeShopCount': instance.activeShopCount,
  'unallocatedAdvances': instance.unallocatedAdvances.toJson(),
  'returnsAwaitingInspection': instance.returnsAwaitingInspection,
  'returnsAwaitingInspectionUnits': instance.returnsAwaitingInspectionUnits,
  'unappliedCreditNotes': instance.unappliedCreditNotes.toJson(),
  'pettyCashFloat': instance.pettyCashFloat.toJson(),
  'unpaidSalaries': instance.unpaidSalaries.toJson(),
  'outstandingEmployeeAdvances': instance.outstandingEmployeeAdvances.toJson(),
  'monthNetProfit': instance.monthNetProfit.toJson(),
  'monthRetailSales': instance.monthRetailSales.toJson(),
};
