// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_service.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InvoicePostResult _$InvoicePostResultFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('InvoicePostResult', json, ($checkedConvert) {
  final val = InvoicePostResult(
    invoiceId: $checkedConvert('invoiceId', (v) => (v as num).toInt()),
    invoiceNumber: $checkedConvert('invoiceNumber', (v) => v as String),
    totals: $checkedConvert(
      'totals',
      (v) => InvoiceTotals.fromJson(v as Map<String, dynamic>),
    ),
    cost: $checkedConvert('cost', (v) => Money.fromJson((v as num).toInt())),
    stockDocumentNumber: $checkedConvert(
      'stockDocumentNumber',
      (v) => v as String?,
    ),
    stockTransactionId: $checkedConvert(
      'stockTransactionId',
      (v) => (v as num?)?.toInt(),
    ),
    payment: $checkedConvert(
      'payment',
      (v) =>
          v == null ? null : PaymentResult.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$InvoicePostResultToJson(InvoicePostResult instance) =>
    <String, dynamic>{
      'invoiceId': instance.invoiceId,
      'invoiceNumber': instance.invoiceNumber,
      'totals': instance.totals.toJson(),
      'cost': instance.cost.toJson(),
      'stockDocumentNumber': ?instance.stockDocumentNumber,
      'stockTransactionId': ?instance.stockTransactionId,
      'payment': ?instance.payment?.toJson(),
    };

InvoiceCancelResult _$InvoiceCancelResultFromJson(Map<String, dynamic> json) =>
    $checkedCreate('InvoiceCancelResult', json, ($checkedConvert) {
      final val = InvoiceCancelResult(
        invoiceNumber: $checkedConvert('invoiceNumber', (v) => v as String),
        releasedMoney: $checkedConvert(
          'releasedMoney',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        stockReversalDocumentNumber: $checkedConvert(
          'stockReversalDocumentNumber',
          (v) => v as String?,
        ),
      );
      return val;
    });

Map<String, dynamic> _$InvoiceCancelResultToJson(
  InvoiceCancelResult instance,
) => <String, dynamic>{
  'invoiceNumber': instance.invoiceNumber,
  'releasedMoney': instance.releasedMoney.toJson(),
  'stockReversalDocumentNumber': ?instance.stockReversalDocumentNumber,
};
