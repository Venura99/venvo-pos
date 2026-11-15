import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/services/app_paths.dart';
import 'package:venvo_core/core/services/document_pdf_service.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/data/delivery_note_pdf.dart';
import 'package:venvo_core/features/inventory/data/stock_query_repository.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/data/invoice_pdf.dart';
import 'package:venvo_core/features/invoices/data/invoice_query_repository.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/payments/data/payment_pdf.dart';
import 'package:venvo_core/features/payments/data/payment_query_repository.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';

/// The application cannot be run on this machine yet, so the PDF layout is
/// exercised here instead: these tests generate real documents from real
/// posted records and assert that each one produces a valid PDF.
void main() {
  late MasterDataFixture fixture;
  late DocumentPdfService pdf;
  late Directory tempDir;
  late int chargerId;
  late int cableId;
  late int shopId;
  late int agentId;
  late int agentLocationId;
  late int warehouseId;

  setUp(() async {
    fixture = await MasterDataFixture.create();
    tempDir = await Directory.systemTemp.createTemp('venvo_pdf_');

    pdf = DocumentPdfService(
      paths: await AppPaths.at(tempDir),
      business: const BusinessIdentity(
        name: 'Venvo Global (Pvt) Ltd',
        address: '42 Galle Road, Colombo 03',
        phone: '011 2345678',
        email: 'accounts@venvo.lk',
        taxId: '114223344-7000',
        footerNote:
            'Goods once sold are returnable only under the agreed '
            'return policy.',
      ),
    );

    final categoryId = await fixture.categories.create(
      fixture.admin,
      const CategoryDraft(name: 'Accessories'),
    );
    chargerId = await fixture.products.create(
      fixture.admin,
      ProductDraft(
        sku: 'CHG-25W',
        name: '25W Charger',
        categoryId: categoryId,
        costPrice: Money.fromMajor(2000),
        wholesalePrice: Money.fromMajor(3000),
      ),
    );
    cableId = await fixture.products.create(
      fixture.admin,
      ProductDraft(
        sku: 'CBL-C',
        name: 'Type-C Cable',
        categoryId: categoryId,
        costPrice: Money.fromMajor(300),
        wholesalePrice: Money.fromMajor(500),
      ),
    );

    warehouseId = (await fixture.locations.mainWarehouse()).id;
    agentId = await fixture.agents.create(
      fixture.admin,
      const AgentDraft(name: 'Sunil Distributors', phone: '0771234567'),
    );
    agentLocationId = (await fixture.locations.forAgent(agentId))!.id;
    shopId = await fixture.shops.create(
      fixture.admin,
      ShopDraft(
        name: 'Nugegoda Mobile Centre',
        assignedAgentId: agentId,
        address: '15 High Level Road, Nugegoda',
        phone: '0712223334',
      ),
    );

    await fixture.postOpeningStock(
      locationId: warehouseId,
      productId: chargerId,
      quantity: 300,
      unitCost: Money.fromMajor(2000),
    );
    await fixture.postOpeningStock(
      locationId: warehouseId,
      productId: cableId,
      quantity: 500,
      unitCost: Money.fromMajor(300),
    );
  });

  tearDown(() async {
    await fixture.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// A PDF file always starts with %PDF- and ends with the EOF marker.
  void expectValidPdf(List<int> bytes) {
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final tail = String.fromCharCodes(bytes.skip(bytes.length - 10));
    expect(tail, contains('EOF'));
  }

  Future<int> raiseShopInvoice({
    DiscountType invoiceDiscountType = DiscountType.none,
    int invoiceDiscountValue = 0,
    String? discountReason,
    ImmediatePayment? payment,
  }) async {
    final result = await fixture.invoices.postInvoice(
      fixture.admin,
      InvoiceRequest(
        kind: InvoiceKind.shopInvoice,
        shopId: shopId,
        agentId: agentId,
        dueDate: fixture.harness.clock.nowUtc().add(const Duration(days: 30)),
        invoiceDiscountType: invoiceDiscountType,
        invoiceDiscountValue: invoiceDiscountValue,
        discountReason: discountReason,
        payment: payment,
        notes: 'Delivered by the morning van.',
        lines: [
          InvoiceLineRequest(
            productId: chargerId,
            quantity: 10,
            unitPrice: Money.fromMajor(3000),
            discountType: DiscountType.percentage,
            discountValue: 500,
          ),
          InvoiceLineRequest(
            productId: cableId,
            quantity: 40,
            unitPrice: Money.fromMajor(500),
          ),
        ],
      ),
    );
    return result.invoiceId;
  }

  group('invoice PDF', () {
    test('renders a posted invoice', () async {
      final invoiceId = await raiseShopInvoice();
      final detail = await InvoiceQueryRepository(
        fixture.db,
      ).invoiceDetail(invoiceId);

      final spec = buildInvoicePdfSpec(detail);
      expect(spec.title, 'Invoice');
      expect(spec.partyName, 'Nugegoda Mobile Centre');
      expect(spec.lines.length, 2);
      expect(spec.watermark, isNull);
      // The line discount is printed the way it was entered.
      expect(spec.lines.first.discountLabel, '5%');

      expectValidPdf(await pdf.build(spec));
    });

    test('renders with the company logo in the header', () async {
      final invoiceId = await raiseShopInvoice();
      final detail = await InvoiceQueryRepository(
        fixture.db,
      ).invoiceDetail(invoiceId);
      // LOGO_FILE points at a real logo when checking one by hand; otherwise
      // a valid 1x1 PNG stands in.
      final logoFile = Platform.environment['LOGO_FILE'];
      final logo = logoFile != null
          ? File(logoFile).readAsBytesSync()
          : base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
              '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
            );
      final withLogo = DocumentPdfService(
        business: BusinessIdentity(name: 'Venvo Global (Pvt) Ltd', logo: logo),
      );
      final bytes = await withLogo.build(buildInvoicePdfSpec(detail));
      expectValidPdf(bytes);
      // The image is embedded as an XObject.
      expect(String.fromCharCodes(bytes), contains('/XObject'));
    });

    test('renders the discount and outstanding blocks', () async {
      final invoiceId = await raiseShopInvoice(
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
        payment: ImmediatePayment(
          method: PaymentMethod.cash,
          amount: Money.fromMajor(10000),
        ),
      );
      final detail = await InvoiceQueryRepository(
        fixture.db,
      ).invoiceDetail(invoiceId);
      final spec = buildInvoicePdfSpec(detail);

      final labels = spec.totals.map((total) => total.label).toList();
      expect(labels, contains('Line discounts'));
      expect(labels, contains('Invoice discount'));
      expect(labels, contains('Net payable'));
      expect(labels, contains('Received'));
      expect(labels, contains('Outstanding'));

      expectValidPdf(await pdf.build(spec));
    });

    test('says plainly that a pending cheque is not credited', () async {
      final invoiceId = await raiseShopInvoice(
        payment: ImmediatePayment(
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(10000),
          chequeNumber: '456123',
          bankName: 'Commercial Bank',
          chequeDate: fixture.harness.clock.nowUtc(),
        ),
      );
      final detail = await InvoiceQueryRepository(
        fixture.db,
      ).invoiceDetail(invoiceId);
      final spec = buildInvoicePdfSpec(detail);

      expect(
        spec.footnotes.any((note) => note.contains('awaiting clearance')),
        isTrue,
      );
      // The cheque is not in the received line.
      expect(spec.totals.any((total) => total.label == 'Received'), isFalse);
      expectValidPdf(await pdf.build(spec));
    });

    test('stamps a cancelled invoice', () async {
      final invoiceId = await raiseShopInvoice();
      await fixture.invoices.cancelInvoice(
        fixture.admin,
        invoiceId: invoiceId,
        reason: 'Duplicate',
      );

      final detail = await InvoiceQueryRepository(
        fixture.db,
      ).invoiceDetail(invoiceId);
      final spec = buildInvoicePdfSpec(detail);
      expect(spec.watermark, 'CANCELLED');
      expectValidPdf(await pdf.build(spec));
    });

    test('prints the product name as it was when billed', () async {
      final invoiceId = await raiseShopInvoice();
      await fixture.products.update(
        fixture.admin,
        ProductDraft(
          id: chargerId,
          sku: 'CHG-25W-V2',
          name: 'Renamed charger',
          categoryId:
              (await fixture.categories.selectableCategories()).first.id,
        ),
      );

      final detail = await InvoiceQueryRepository(
        fixture.db,
      ).invoiceDetail(invoiceId);
      final spec = buildInvoicePdfSpec(detail);
      expect(spec.lines.first.description, '25W Charger');
      expect(spec.lines.first.reference, 'CHG-25W');
    });

    test('saves to the exports folder under its own number', () async {
      final invoiceId = await raiseShopInvoice();
      final detail = await InvoiceQueryRepository(
        fixture.db,
      ).invoiceDetail(invoiceId);

      final file = await pdf.save(
        buildInvoicePdfSpec(detail),
        subfolder: 'invoices',
      );
      expect(file.existsSync(), isTrue);
      expect(file.path, contains('invoices'));
      expect(file.path, endsWith('${detail.summary.invoiceNumber}.pdf'));
      expectValidPdf(await file.readAsBytes());
    });
  });

  group('payment receipt PDF', () {
    Future<PaymentSummary> recordAndRead(PaymentRequest request) async {
      await fixture.payments.recordPayment(fixture.admin, request);
      final payments = await PaymentQueryRepository(
        fixture.db,
      ).watchPayments(const PaymentFilter()).first;
      return payments.first;
    }

    test('renders a cash receipt as paid', () async {
      final invoiceId = await raiseShopInvoice();
      final payment = await recordAndRead(
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(15000),
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoiceId,
              amount: Money.fromMajor(15000),
            ),
          ],
        ),
      );

      final spec = buildReceiptPdfSpec(payment);
      expect(spec.title, 'Payment receipt');
      expect(spec.watermark, isNull);
      expect(spec.showUnitPrices, isFalse);
      expectValidPdf(await pdf.build(spec));
    });

    test('a cheque receipt is stamped subject to clearance', () async {
      final payment = await recordAndRead(
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(20000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '778899',
            bankName: 'Sampath Bank',
            chequeDate: fixture.harness.clock.nowUtc(),
          ),
        ),
      );

      final spec = buildReceiptPdfSpec(payment);
      expect(spec.watermark, 'SUBJECT TO CLEARANCE');
      expect(
        spec.footnotes.any(
          (note) => note.contains('only when the cheque clears'),
        ),
        isTrue,
      );
      expectValidPdf(await pdf.build(spec));
    });

    test('a bounced cheque receipt says the amount is not credited', () async {
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(20000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '778899',
            bankName: 'Sampath Bank',
            chequeDate: fixture.harness.clock.nowUtc(),
          ),
        ),
      );
      final cheques = await PaymentQueryRepository(
        fixture.db,
      ).watchCheques(const ChequeFilter()).first;
      await fixture.payments.bounceCheque(
        fixture.admin,
        chequeId: cheques.single.id,
        reason: 'Insufficient funds',
      );

      final payment = (await PaymentQueryRepository(
        fixture.db,
      ).watchPayments(const PaymentFilter()).first).first;
      final spec = buildReceiptPdfSpec(payment);
      expect(spec.watermark, 'BOUNCED');
      expect(
        spec.footnotes.any((note) => note.contains('returned unpaid')),
        isTrue,
      );
      expectValidPdf(await pdf.build(spec));
    });

    test('an unapplied receipt says it is on account', () async {
      final payment = await recordAndRead(
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(5000),
          shopId: shopId,
        ),
      );

      final spec = buildReceiptPdfSpec(payment);
      expect(spec.footnotes.any((note) => note.contains('on account')), isTrue);
      expect(
        spec.totals.any((total) => total.label == 'Held on account'),
        isTrue,
      );
      expectValidPdf(await pdf.build(spec));
    });
  });

  group('delivery note PDF', () {
    test('renders a transfer and says it is not an invoice', () async {
      final transfer = await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          referenceNote: 'Morning van',
          lines: [
            StockMovementLine(
              productId: chargerId,
              quantity: 50,
              unitPrice: Money.fromMajor(3000),
            ),
            StockMovementLine(
              productId: cableId,
              quantity: 100,
              unitPrice: Money.fromMajor(500),
            ),
          ],
        ),
      );

      final detail = await StockQueryRepository(
        fixture.db,
      ).documentDetail(transfer.transactionId);
      final spec = buildDeliveryNotePdfSpec(detail);

      expect(spec.title, 'Delivery note');
      expect(spec.partyName, 'Sunil Distributors');
      expect(spec.lines.length, 2);
      expect(spec.showUnitPrices, isTrue);
      expect(
        spec.footnotes.any((note) => note.contains('not an invoice')),
        isTrue,
      );
      expectValidPdf(await pdf.build(spec));
    });

    test(
      'hides the price columns when the document carried no prices',
      () async {
        final transfer = await fixture.stockLedger.postMovement(
          fixture.admin,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentLocationId,
            lines: [StockMovementLine(productId: chargerId, quantity: 20)],
          ),
        );

        final detail = await StockQueryRepository(
          fixture.db,
        ).documentDetail(transfer.transactionId);
        final spec = buildDeliveryNotePdfSpec(detail);

        expect(spec.showUnitPrices, isFalse);
        expect(spec.totals, isEmpty);
        expectValidPdf(await pdf.build(spec));
      },
    );

    test('notes a reversal on both documents', () async {
      final transfer = await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [StockMovementLine(productId: chargerId, quantity: 20)],
        ),
      );
      final reversal = await fixture.stockLedger.cancelMovement(
        fixture.admin,
        transactionId: transfer.transactionId,
        reason: 'Wrong agent',
      );

      final queries = StockQueryRepository(fixture.db);
      final originalSpec = buildDeliveryNotePdfSpec(
        await queries.documentDetail(transfer.transactionId),
      );
      expect(originalSpec.watermark, 'CANCELLED');
      expect(
        originalSpec.footnotes.any(
          (note) => note.contains('has been reversed'),
        ),
        isTrue,
      );

      final reversalSpec = buildDeliveryNotePdfSpec(
        await queries.documentDetail(reversal.transactionId),
      );
      expect(
        reversalSpec.footnotes.any((note) => note.contains('reverses')),
        isTrue,
      );
      expectValidPdf(await pdf.build(reversalSpec));
    });
  });

  group('business identity', () {
    test('is read out of the settings table', () async {
      final settings = fixture.harness.bootstrap.settings;
      await settings.setString(SettingKeysForTest.name, 'Venvo Global');
      await settings.setString(SettingKeysForTest.phone, '011 1111111');

      final identity = await BusinessIdentity.fromSettings(settings);
      expect(identity.name, 'Venvo Global');
      expect(identity.contactLine, contains('011 1111111'));
    });

    test('leaves out details that have not been filled in', () async {
      final identity = await BusinessIdentity.fromSettings(
        fixture.harness.bootstrap.settings,
      );
      // The seed leaves the contact fields blank.
      expect(identity.address, isNull);
      expect(identity.phone, isNull);
      expect(identity.contactLine, isEmpty);
    });
  });
}

/// Setting keys used by the identity test, named locally so the test does not
/// reach into the constants file for two strings.
abstract final class SettingKeysForTest {
  static const String name = 'business.name';
  static const String phone = 'business.phone';
}
