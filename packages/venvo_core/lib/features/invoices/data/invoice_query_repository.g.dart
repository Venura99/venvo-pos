// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_query_repository.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UnbilledDelivery _$UnbilledDeliveryFromJson(Map<String, dynamic> json) =>
    $checkedCreate('UnbilledDelivery', json, ($checkedConvert) {
      final val = UnbilledDelivery(
        stockTransactionId: $checkedConvert(
          'stockTransactionId',
          (v) => (v as num).toInt(),
        ),
        documentNumber: $checkedConvert('documentNumber', (v) => v as String),
        documentType: $checkedConvert(
          'documentType',
          (v) => $enumDecode(_$StockDocumentTypeEnumMap, v),
        ),
        documentDate: $checkedConvert(
          'documentDate',
          (v) => DateTime.parse(v as String),
        ),
        totalQuantity: $checkedConvert(
          'totalQuantity',
          (v) => (v as num).toInt(),
        ),
        documentValue: $checkedConvert(
          'documentValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        sourceName: $checkedConvert('sourceName', (v) => v as String),
        destinationName: $checkedConvert('destinationName', (v) => v as String),
        agentName: $checkedConvert('agentName', (v) => v as String?),
        shopName: $checkedConvert('shopName', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$UnbilledDeliveryToJson(UnbilledDelivery instance) =>
    <String, dynamic>{
      'stockTransactionId': instance.stockTransactionId,
      'documentNumber': instance.documentNumber,
      'documentType': _$StockDocumentTypeEnumMap[instance.documentType]!,
      'documentDate': instance.documentDate.toIso8601String(),
      'totalQuantity': instance.totalQuantity,
      'documentValue': instance.documentValue.toJson(),
      'sourceName': instance.sourceName,
      'destinationName': instance.destinationName,
      'agentName': ?instance.agentName,
      'shopName': ?instance.shopName,
    };

const _$StockDocumentTypeEnumMap = {
  StockDocumentType.openingStock: 'openingStock',
  StockDocumentType.purchaseIn: 'purchaseIn',
  StockDocumentType.warehouseToAgent: 'warehouseToAgent',
  StockDocumentType.agentToShop: 'agentToShop',
  StockDocumentType.warehouseToShop: 'warehouseToShop',
  StockDocumentType.retailSale: 'retailSale',
  StockDocumentType.customerToShopReturn: 'customerToShopReturn',
  StockDocumentType.shopToAgentReturn: 'shopToAgentReturn',
  StockDocumentType.agentToWarehouseReturn: 'agentToWarehouseReturn',
  StockDocumentType.shopToWarehouseReturn: 'shopToWarehouseReturn',
  StockDocumentType.damageWriteOff: 'damageWriteOff',
  StockDocumentType.adjustmentIncrease: 'adjustmentIncrease',
  StockDocumentType.adjustmentDecrease: 'adjustmentDecrease',
  StockDocumentType.reconciliation: 'reconciliation',
  StockDocumentType.interLocationTransfer: 'interLocationTransfer',
};

InvoiceTotalsSnapshot _$InvoiceTotalsSnapshotFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('InvoiceTotalsSnapshot', json, ($checkedConvert) {
  final val = InvoiceTotalsSnapshot(
    count: $checkedConvert('count', (v) => (v as num).toInt()),
    gross: $checkedConvert('gross', (v) => Money.fromJson((v as num).toInt())),
    discount: $checkedConvert(
      'discount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    net: $checkedConvert('net', (v) => Money.fromJson((v as num).toInt())),
    cost: $checkedConvert('cost', (v) => Money.fromJson((v as num).toInt())),
    settled: $checkedConvert(
      'settled',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    outstanding: $checkedConvert(
      'outstanding',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    pendingCheques: $checkedConvert(
      'pendingCheques',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    cancelledCount: $checkedConvert(
      'cancelledCount',
      (v) => (v as num).toInt(),
    ),
  );
  return val;
});

Map<String, dynamic> _$InvoiceTotalsSnapshotToJson(
  InvoiceTotalsSnapshot instance,
) => <String, dynamic>{
  'count': instance.count,
  'gross': instance.gross.toJson(),
  'discount': instance.discount.toJson(),
  'net': instance.net.toJson(),
  'cost': instance.cost.toJson(),
  'settled': instance.settled.toJson(),
  'outstanding': instance.outstanding.toJson(),
  'pendingCheques': instance.pendingCheques.toJson(),
  'cancelledCount': instance.cancelledCount,
};
