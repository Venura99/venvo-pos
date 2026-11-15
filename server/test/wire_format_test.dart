import 'dart:convert';

import 'package:test/test.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failure_codec.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';

/// The wire format itself, without a server.
///
/// These cover the pieces that are hand-written rather than generated, and the
/// ones where a silent misencoding would be expensive rather than obvious.
void main() {
  /// Encodes and decodes through real JSON text, so anything the encoder
  /// cannot represent fails here rather than passing on an in-memory map.
  Map<String, dynamic> roundTrip(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  group('money', () {
    test('survives as integer minor units', () {
      for (final cents in [0, 1, -1, 7, 33407, -98765, 999999999]) {
        final money = Money(cents);
        expect(money.toJson(), cents);
        expect(Money.fromJson(money.toJson()), money);
      }
    });

    test('is encoded as a number, not a string or a decimal', () {
      final encoded = jsonEncode({'price': const Money(123457).toJson()});
      expect(encoded, '{"price":123457}');
    });
  });

  group('invoice stock linkage', () {
    // A sealed hierarchy needs a discriminator, and this codec is written by
    // hand. Getting it wrong would mean an invoice moving stock when it
    // should only have referenced an existing delivery — goods counted out of
    // the warehouse twice.
    test('each subclass round-trips as itself', () {
      final cases = <InvoiceStockLinkage>[
        const NoStockMovement(),
        const BillExistingDelivery(42),
        const MoveStockWithInvoice(
          documentType: StockDocumentType.retailSale,
          sourceLocationId: 3,
          destinationLocationId: 7,
        ),
      ];

      for (final original in cases) {
        final decoded = InvoiceStockLinkage.fromJson(
          roundTrip(original.toJson()),
        );
        expect(
          decoded.runtimeType,
          original.runtimeType,
          reason: '${original.runtimeType} came back as ${decoded.runtimeType}',
        );
        expect(decoded.kind, original.kind);
      }
    });

    test('the referenced delivery and the locations survive', () {
      final billed =
          InvoiceStockLinkage.fromJson(
                roundTrip(const BillExistingDelivery(99).toJson()),
              )
              as BillExistingDelivery;
      expect(billed.stockTransactionId, 99);

      final moving =
          InvoiceStockLinkage.fromJson(
                roundTrip(
                  const MoveStockWithInvoice(
                    documentType: StockDocumentType.warehouseToShop,
                    sourceLocationId: 11,
                    destinationLocationId: 22,
                  ).toJson(),
                ),
              )
              as MoveStockWithInvoice;
      expect(moving.documentType, StockDocumentType.warehouseToShop);
      expect(moving.sourceLocationId, 11);
      expect(moving.destinationLocationId, 22);
    });

    test('a missing or unknown kind is refused, never guessed', () {
      // Inferring the subclass from which fields are present is exactly the
      // shortcut this codec exists to avoid.
      expect(
        () => InvoiceStockLinkage.fromJson(const {'stockTransactionId': 1}),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => InvoiceStockLinkage.fromJson(const {'kind': 'something_new'}),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('stock count quantities', () {
    test('an uncounted line stays null, distinct from a counted zero', () {
      // If null collapsed to 0 on the wire, posting a count would write off
      // every line nobody had reached yet.
      final sheet = const StockCountLine(
        productId: 5,
        sku: 'SKU-5',
        productName: 'Thing',
        systemQuantity: 12,
      );
      final decoded = StockCountLine.fromJson(roundTrip(sheet.toJson()));
      expect(decoded.countedQuantity, isNull);

      final counted = const StockCountLine(
        productId: 5,
        sku: 'SKU-5',
        productName: 'Thing',
        systemQuantity: 12,
        countedQuantity: 0,
      );
      expect(
        StockCountLine.fromJson(roundTrip(counted.toJson())).countedQuantity,
        0,
      );
    });
  });

  group('movement requests', () {
    test('lines, enums and money all survive a round trip', () {
      final request = StockMovementRequest(
        documentType: StockDocumentType.warehouseToAgent,
        sourceLocationId: 1,
        destinationLocationId: 2,
        documentDate: DateTime.utc(2026, 11, 15, 9, 30),
        lines: [
          StockMovementLine(
            productId: 10,
            quantity: 7,
            unitCost: const Money(12345),
            unitPrice: const Money(19999),
            discountType: DiscountType.percentage,
            discountValue: 250,
          ),
        ],
        allowNegativeStock: true,
        negativeStockReason: 'Customer waiting',
      );

      final decoded = StockMovementRequest.fromJson(
        roundTrip(request.toJson()),
      );
      expect(decoded.documentType, StockDocumentType.warehouseToAgent);
      expect(decoded.documentDate, DateTime.utc(2026, 11, 15, 9, 30));
      expect(decoded.allowNegativeStock, isTrue);
      expect(decoded.negativeStockReason, 'Customer waiting');

      final line = decoded.lines.single;
      expect(line.productId, 10);
      expect(line.quantity, 7);
      expect(line.unitCost, const Money(12345));
      expect(line.unitPrice, const Money(19999));
      expect(line.discountType, DiscountType.percentage);
      expect(line.discountValue, 250);
    });
  });

  group('failures', () {
    test('every failure type survives with its extra field', () {
      final cases = <AppFailure>[
        const ValidationFailure('bad', field: 'sku'),
        const BusinessRuleFailure('no', rule: 'stock.negative'),
        const PermissionFailure('nope', permission: 'stock.transfer'),
        const NotFoundFailure('gone'),
        const StorageFailure('disk'),
        const AuthFailure('who'),
      ];

      for (final original in cases) {
        final decoded = FailureCodec.fromJson(
          roundTrip(FailureCodec.toJson(original)),
        );
        expect(decoded.runtimeType, original.runtimeType);
        expect(decoded.message, original.message);
      }

      expect(
        (FailureCodec.fromJson(
                  roundTrip(
                    FailureCodec.toJson(
                      const ValidationFailure('bad', field: 'sku'),
                    ),
                  ),
                )
                as ValidationFailure)
            .field,
        'sku',
      );
      expect(
        (FailureCodec.fromJson(
                  roundTrip(
                    FailureCodec.toJson(
                      const BusinessRuleFailure('no', rule: 'stock.negative'),
                    ),
                  ),
                )
                as BusinessRuleFailure)
            .rule,
        'stock.negative',
      );
    });

    test('an unknown kind becomes a StorageFailure, not a business rule', () {
      // Blaming a business rule for a server bug would send a cashier looking
      // for a mistake they did not make.
      final decoded = FailureCodec.fromJson(const {
        'kind': 'something_from_a_newer_server',
        'message': 'Something went wrong.',
      });
      expect(decoded, isA<StorageFailure>());
      expect(decoded.message, 'Something went wrong.');
    });
  });
}
