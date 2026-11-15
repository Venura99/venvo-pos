// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

JournalLine _$JournalLineFromJson(Map<String, dynamic> json) =>
    $checkedCreate('JournalLine', json, ($checkedConvert) {
      final val = JournalLine(
        accountCode: $checkedConvert('accountCode', (v) => v as String),
        amount: $checkedConvert(
          'amount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        isDebit: $checkedConvert('isDebit', (v) => v as bool),
        description: $checkedConvert('description', (v) => v as String?),
        agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
        shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$JournalLineToJson(JournalLine instance) =>
    <String, dynamic>{
      'accountCode': instance.accountCode,
      'amount': instance.amount.toJson(),
      'isDebit': instance.isDebit,
      'description': ?instance.description,
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
    };

JournalRow _$JournalRowFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('JournalRow', json, ($checkedConvert) {
  final val = JournalRow(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    batchId: $checkedConvert('batchId', (v) => v as String),
    entryDate: $checkedConvert('entryDate', (v) => DateTime.parse(v as String)),
    accountCode: $checkedConvert('accountCode', (v) => v as String),
    accountName: $checkedConvert('accountName', (v) => v as String),
    accountType: $checkedConvert(
      'accountType',
      (v) => $enumDecode(_$AccountTypeEnumMap, v),
    ),
    debit: $checkedConvert('debit', (v) => Money.fromJson((v as num).toInt())),
    credit: $checkedConvert(
      'credit',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    sourceKind: $checkedConvert(
      'sourceKind',
      (v) => $enumDecode(_$EntityKindEnumMap, v),
    ),
    description: $checkedConvert('description', (v) => v as String),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    sourceId: $checkedConvert('sourceId', (v) => (v as num?)?.toInt()),
    reversesBatchId: $checkedConvert('reversesBatchId', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$JournalRowToJson(JournalRow instance) =>
    <String, dynamic>{
      'id': instance.id,
      'batchId': instance.batchId,
      'entryDate': instance.entryDate.toIso8601String(),
      'accountCode': instance.accountCode,
      'accountName': instance.accountName,
      'accountType': _$AccountTypeEnumMap[instance.accountType]!,
      'debit': instance.debit.toJson(),
      'credit': instance.credit.toJson(),
      'sourceKind': _$EntityKindEnumMap[instance.sourceKind]!,
      'sourceId': ?instance.sourceId,
      'description': instance.description,
      'createdBy': instance.createdBy,
      'reversesBatchId': ?instance.reversesBatchId,
    };

const _$AccountTypeEnumMap = {
  AccountType.asset: 'asset',
  AccountType.liability: 'liability',
  AccountType.equity: 'equity',
  AccountType.income: 'income',
  AccountType.expense: 'expense',
};

const _$EntityKindEnumMap = {
  EntityKind.product: 'product',
  EntityKind.category: 'category',
  EntityKind.agent: 'agent',
  EntityKind.shop: 'shop',
  EntityKind.employee: 'employee',
  EntityKind.inventoryLocation: 'inventoryLocation',
  EntityKind.stockDocument: 'stockDocument',
  EntityKind.invoice: 'invoice',
  EntityKind.payment: 'payment',
  EntityKind.cheque: 'cheque',
  EntityKind.returnDocument: 'returnDocument',
  EntityKind.creditNote: 'creditNote',
  EntityKind.expense: 'expense',
  EntityKind.pettyCashEntry: 'pettyCashEntry',
  EntityKind.salary: 'salary',
  EntityKind.salaryPayment: 'salaryPayment',
  EntityKind.employeeAdvance: 'employeeAdvance',
  EntityKind.user: 'user',
  EntityKind.setting: 'setting',
  EntityKind.backup: 'backup',
};

TrialBalanceRow _$TrialBalanceRowFromJson(Map<String, dynamic> json) =>
    $checkedCreate('TrialBalanceRow', json, ($checkedConvert) {
      final val = TrialBalanceRow(
        accountCode: $checkedConvert('accountCode', (v) => v as String),
        accountName: $checkedConvert('accountName', (v) => v as String),
        accountType: $checkedConvert(
          'accountType',
          (v) => $enumDecode(_$AccountTypeEnumMap, v),
        ),
        debits: $checkedConvert(
          'debits',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        credits: $checkedConvert(
          'credits',
          (v) => Money.fromJson((v as num).toInt()),
        ),
      );
      return val;
    });

Map<String, dynamic> _$TrialBalanceRowToJson(TrialBalanceRow instance) =>
    <String, dynamic>{
      'accountCode': instance.accountCode,
      'accountName': instance.accountName,
      'accountType': _$AccountTypeEnumMap[instance.accountType]!,
      'debits': instance.debits.toJson(),
      'credits': instance.credits.toJson(),
    };

TrialBalance _$TrialBalanceFromJson(Map<String, dynamic> json) =>
    $checkedCreate('TrialBalance', json, ($checkedConvert) {
      final val = TrialBalance(
        rows: $checkedConvert(
          'rows',
          (v) => (v as List<dynamic>)
              .map((e) => TrialBalanceRow.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        from: $checkedConvert(
          'from',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        to: $checkedConvert(
          'to',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$TrialBalanceToJson(TrialBalance instance) =>
    <String, dynamic>{
      'rows': instance.rows.map((e) => e.toJson()).toList(),
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
    };

ProfitAndLoss _$ProfitAndLossFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ProfitAndLoss', json, ($checkedConvert) {
      final val = ProfitAndLoss(
        grossSales: $checkedConvert(
          'grossSales',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        discounts: $checkedConvert(
          'discounts',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        returns: $checkedConvert(
          'returns',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        costOfGoodsSold: $checkedConvert(
          'costOfGoodsSold',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        operatingExpenses: $checkedConvert(
          'operatingExpenses',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        salaryExpense: $checkedConvert(
          'salaryExpense',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        stockWriteOff: $checkedConvert(
          'stockWriteOff',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        otherExpenses: $checkedConvert(
          'otherExpenses',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        revenue: $checkedConvert(
          'revenue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        expenses: $checkedConvert(
          'expenses',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        from: $checkedConvert(
          'from',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        to: $checkedConvert(
          'to',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ProfitAndLossToJson(ProfitAndLoss instance) =>
    <String, dynamic>{
      'grossSales': instance.grossSales.toJson(),
      'discounts': instance.discounts.toJson(),
      'returns': instance.returns.toJson(),
      'costOfGoodsSold': instance.costOfGoodsSold.toJson(),
      'operatingExpenses': instance.operatingExpenses.toJson(),
      'salaryExpense': instance.salaryExpense.toJson(),
      'stockWriteOff': instance.stockWriteOff.toJson(),
      'otherExpenses': instance.otherExpenses.toJson(),
      'revenue': instance.revenue.toJson(),
      'expenses': instance.expenses.toJson(),
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
    };

UnbalancedBatch _$UnbalancedBatchFromJson(Map<String, dynamic> json) =>
    $checkedCreate('UnbalancedBatch', json, ($checkedConvert) {
      final val = UnbalancedBatch(
        batchId: $checkedConvert('batchId', (v) => v as String),
        debits: $checkedConvert(
          'debits',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        credits: $checkedConvert(
          'credits',
          (v) => Money.fromJson((v as num).toInt()),
        ),
      );
      return val;
    });

Map<String, dynamic> _$UnbalancedBatchToJson(UnbalancedBatch instance) =>
    <String, dynamic>{
      'batchId': instance.batchId,
      'debits': instance.debits.toJson(),
      'credits': instance.credits.toJson(),
    };

FinancialLedgerFilter _$FinancialLedgerFilterFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('FinancialLedgerFilter', json, ($checkedConvert) {
  final val = FinancialLedgerFilter(
    search: $checkedConvert('search', (v) => v as String? ?? ''),
    accountCode: $checkedConvert('accountCode', (v) => v as String?),
    sourceKind: $checkedConvert(
      'sourceKind',
      (v) => $enumDecodeNullable(_$EntityKindEnumMap, v),
    ),
    from: $checkedConvert(
      'from',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    to: $checkedConvert(
      'to',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    limit: $checkedConvert('limit', (v) => (v as num?)?.toInt() ?? 500),
  );
  return val;
});

Map<String, dynamic> _$FinancialLedgerFilterToJson(
  FinancialLedgerFilter instance,
) => <String, dynamic>{
  'search': instance.search,
  'accountCode': ?instance.accountCode,
  'sourceKind': ?_$EntityKindEnumMap[instance.sourceKind],
  'from': ?instance.from?.toIso8601String(),
  'to': ?instance.to?.toIso8601String(),
  'limit': instance.limit,
};
