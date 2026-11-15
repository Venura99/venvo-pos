import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:venvo_core/core/api/api_client.dart';
import 'package:venvo_core/core/api/settings_api.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/api/agent_api.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/authentication/api/auth_api.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';
import 'package:venvo_core/features/categories/api/category_api.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/api/location_api.dart';
import 'package:venvo_core/features/inventory/api/stock_api.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/api/invoice_api.dart';
import 'package:venvo_core/features/invoices/data/invoice_service.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/payments/api/cheque_extras_api.dart';
import 'package:venvo_core/features/payments/api/payment_api.dart';
import 'package:venvo_core/features/payments/data/cheque_reminders.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/products/api/product_api.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/shops/api/shop_api.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';
import 'package:venvo_server/notifications/whatsapp_sender.dart';

import 'support/api_harness.dart';

/// Stands in for WhatsApp: records what would have been sent.
class FakeSender implements ReminderSender {
  final sent = <({String to, DueCheque cheque})>[];
  bool configured = true;
  String? failWith;

  @override
  bool get isConfigured => configured;

  @override
  Future<void> send({required String to, required DueCheque cheque}) async {
    if (failWith != null) throw StateError(failWith!);
    sent.add((to: to, cheque: cheque));
  }
}

/// A few bytes that are, by their signature, a JPEG — all the server checks.
final Uint8List jpeg = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  ...List.filled(64, 0x20),
  0xFF, 0xD9,
]);

void main() {
  late ApiHarness api;
  late FakeSender sender;
  late ApiClient adminClient;
  late AuthenticatedUser admin;
  late ApiClient agentClient;
  late AuthenticatedUser agentUser;
  late int shopId;
  late InvoicePostResult invoice;

  setUp(() async {
    sender = FakeSender();
    api = await ApiHarness.start(reminderSender: sender);
    adminClient = ApiClient(baseUrl: api.base, tokens: InMemoryTokenStore());
    admin = await AuthApi(adminClient).createFirstAdministrator(
      fullName: 'Venura Admin',
      username: 'admin',
      password: ApiHarness.adminPassword,
    );

    final locations = await LocationApi(
      adminClient,
    ).watchLocations(includeVirtual: true).first;
    final warehouseId = locations
        .firstWhere((l) => l.code == AppConstants.mainWarehouseCode)
        .id;
    final supplierId = locations
        .firstWhere((l) => l.code == AppConstants.supplierLocationCode)
        .id;
    final categoryId = await CategoryApi(
      adminClient,
    ).create(admin, const CategoryDraft(name: 'Chargers'));
    final productId = await ProductApi(adminClient).create(
      admin,
      ProductDraft(
        sku: 'CHG-25W',
        name: 'Fast charger 25W',
        categoryId: categoryId,
        costPrice: const Money(100000),
        wholesalePrice: const Money(130000),
      ),
    );
    final agentId = await AgentApi(
      adminClient,
    ).create(admin, const AgentDraft(name: 'Kandy route'));
    shopId = await ShopApi(adminClient).create(
      admin,
      ShopDraft(name: 'Sea Street Mobiles', assignedAgentId: agentId),
    );
    final shopLocationId = (await LocationApi(
      adminClient,
    ).watchLocations().first).firstWhere((l) => l.shopId == shopId).id;
    await StockLedgerApi(adminClient).postMovement(
      admin,
      StockMovementRequest(
        documentType: StockDocumentType.openingStock,
        sourceLocationId: supplierId,
        destinationLocationId: warehouseId,
        lines: [
          StockMovementLine(
            productId: productId,
            quantity: 50,
            unitCost: const Money(100000),
          ),
        ],
      ),
    );
    invoice = await InvoiceApi(adminClient).postInvoice(
      admin,
      InvoiceRequest(
        kind: InvoiceKind.shopInvoice,
        shopId: shopId,
        lines: [
          InvoiceLineRequest(
            productId: productId,
            quantity: 10,
            unitPrice: const Money(130000),
          ),
        ],
        stockLinkage: MoveStockWithInvoice(
          documentType: StockDocumentType.warehouseToShop,
          sourceLocationId: warehouseId,
          destinationLocationId: shopLocationId,
        ),
      ),
    );

    // The agent signs in on their own phone with the Agent role.
    await AuthApi(adminClient).createUser(
      actor: admin,
      fullName: 'Kamal (agent)',
      username: 'kamal',
      password: 'Initial1Pass',
      roleCodes: [RoleCodes.agent],
    );
    agentClient = ApiClient(baseUrl: api.base, tokens: InMemoryTokenStore());
    final agentAuth = AuthApi(agentClient);
    agentUser = await agentAuth.signIn(
      username: 'kamal',
      password: 'Initial1Pass',
    );
    await agentAuth.changeOwnPassword(
      user: agentUser,
      currentPassword: 'Initial1Pass',
      newPassword: 'Chosen2Pass9',
    );
  });

  tearDown(() async {
    await adminClient.close();
    await agentClient.close();
    await api.stop();
  });

  /// The agent records the shop's cheque, dated [daysAhead] from today.
  Future<PaymentResult> agentTakesCheque({int daysAhead = 1}) =>
      PaymentApi(agentClient).recordPayment(
        agentUser,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: invoice.totals.net,
          partyType: PartyType.shop,
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '456789',
            bankName: 'Commercial Bank',
            chequeDate: DateTime.now().toUtc().add(Duration(days: daysAhead)),
          ),
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: invoice.totals.net,
            ),
          ],
        ),
      );

  Future<void> setReminderNumbers(String numbers, {int days = 1}) async {
    await SettingsApi(adminClient).update({
      SettingKeys.whatsappAdminNumbers: numbers,
      SettingKeys.chequeReminderDaysBefore: days,
    });
  }

  group('an agent and a cheque', () {
    test(
      'the agent role can record the cheque but not manage the books',
      () async {
        expect(agentUser.can(Permissions.paymentRecord), isTrue);
        expect(agentUser.can(Permissions.stockTransfer), isFalse);
        expect(agentUser.can(Permissions.invoiceCancel), isFalse);
        expect(agentUser.can(Permissions.chequeManage), isFalse);
        expect(agentUser.can(Permissions.settingsManage), isFalse);

        final payment = await agentTakesCheque();
        expect(payment.chequeId, isNotNull);
      },
    );

    test('the agent uploads a photo and the office can see it', () async {
      final payment = await agentTakesCheque();
      final chequeId = payment.chequeId!;

      final uploaded = await ChequeExtrasApi(agentClient).uploadChequeImage(
        chequeId: chequeId,
        bytes: jpeg,
        fileName: 'IMG_2041.jpg',
        mimeType: 'image/jpeg',
      );
      expect(uploaded.mimeType, 'image/jpeg');
      expect(uploaded.isImage, isTrue);

      final office = ChequeExtrasApi(adminClient);
      final list = await office.chequeAttachments(chequeId);
      expect(list.single.fileName, 'IMG_2041.jpg');
      expect(await office.attachmentBytes(list.single.id), jpeg);
    });

    test(
      'a file that is not a photo or PDF is refused, whatever its name',
      () async {
        final payment = await agentTakesCheque();
        await expectLater(
          ChequeExtrasApi(agentClient).uploadChequeImage(
            chequeId: payment.chequeId!,
            bytes: Uint8List.fromList(utf8.encode('#!/bin/sh\nrm -rf /\n')),
            fileName: 'cheque.jpg',
            mimeType: 'image/jpeg',
          ),
          throwsA(isA<ValidationFailure>()),
        );
        expect(
          await ChequeExtrasApi(
            adminClient,
          ).chequeAttachments(payment.chequeId!),
          isEmpty,
        );
      },
    );

    test('a file name cannot steer where the file is stored', () async {
      final payment = await agentTakesCheque();
      final uploaded = await ChequeExtrasApi(agentClient).uploadChequeImage(
        chequeId: payment.chequeId!,
        bytes: jpeg,
        fileName: '../../../etc/passwd.jpg',
      );
      expect(uploaded.fileName, isNot(contains('/')));
      expect(uploaded.fileName, isNot(contains('..')));
    });
  });

  group('WhatsApp reminders', () {
    test('a cheque due tomorrow is sent to the admin, once', () async {
      await setReminderNumbers('0771234567');
      final payment = await agentTakesCheque(daysAhead: 1);

      final first = await ChequeExtrasApi(adminClient).runReminders();
      expect(first['sent'], 1);
      // The local number was turned into the international form.
      expect(sender.sent.single.to, '94771234567');
      expect(sender.sent.single.cheque.chequeNumber, '456789');
      expect(sender.sent.single.cheque.partyName, 'Sea Street Mobiles');
      expect(sender.sent.single.cheque.amount, invoice.totals.net);

      // Running again does not send it again.
      final second = await ChequeExtrasApi(adminClient).runReminders();
      expect(second['sent'], 0);
      expect(sender.sent, hasLength(1));

      final history = await ChequeExtrasApi(
        adminClient,
      ).reminderHistory(payment.chequeId!);
      expect(history.single.delivered, isTrue);
    });

    test('every configured number gets it', () async {
      await setReminderNumbers('94771234567, 94712345678');
      await agentTakesCheque();
      await ChequeExtrasApi(adminClient).runReminders();
      expect(
        sender.sent.map((s) => s.to),
        unorderedEquals(['94771234567', '94712345678']),
      );
    });

    test('a cheque dated further out is not reminded yet', () async {
      await setReminderNumbers('94771234567', days: 1);
      await agentTakesCheque(daysAhead: 10);
      final result = await ChequeExtrasApi(adminClient).runReminders();
      expect(result['due'], 0);
      expect(sender.sent, isEmpty);
    });

    test('a cleared cheque is not reminded', () async {
      await setReminderNumbers('94771234567');
      final payment = await agentTakesCheque();
      await PaymentApi(
        adminClient,
      ).clearCheque(admin, chequeId: payment.chequeId!);
      final result = await ChequeExtrasApi(adminClient).runReminders();
      expect(result['due'], 0);
      expect(sender.sent, isEmpty);
    });

    test('a failure is kept with its reason and retried later', () async {
      await setReminderNumbers('94771234567');
      final payment = await agentTakesCheque();

      sender.failWith = 'template not approved';
      final failed = await ChequeExtrasApi(adminClient).runReminders();
      expect(failed['failed'], 1);
      final history = await ChequeExtrasApi(
        adminClient,
      ).reminderHistory(payment.chequeId!);
      expect(history.single.delivered, isFalse);
      expect(history.single.error, contains('template not approved'));

      sender.failWith = null;
      final retried = await ChequeExtrasApi(adminClient).runReminders();
      expect(retried['sent'], 1);
    });

    test('a missing setup is reported, not silently ignored', () async {
      await agentTakesCheque();
      // No number in settings.
      final noNumber = await ChequeExtrasApi(adminClient).runReminders();
      expect(noNumber['notConfigured'], contains('Settings'));

      await setReminderNumbers('94771234567');
      sender.configured = false;
      final noCredentials = await ChequeExtrasApi(adminClient).runReminders();
      expect(noCredentials['notConfigured'], contains('server'));
      expect(sender.sent, isEmpty);
    });

    test('the agent may not trigger reminders', () async {
      await expectLater(
        ChequeExtrasApi(agentClient).runReminders(),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('the WhatsApp numbers are an ordinary setting', () async {
      await setReminderNumbers('0771234567');
      final settings = SettingsApi(adminClient);
      await settings.load();
      expect(
        settings.getStringSync(SettingKeys.whatsappAdminNumbers),
        '0771234567',
      );
      expect(settings.getIntSync(SettingKeys.chequeReminderDaysBefore), 1);
    });
  });

  group('the WhatsApp sender', () {
    final cheque = DueCheque(
      chequeId: 1,
      chequeNumber: '456789',
      bankName: 'Commercial Bank',
      chequeDate: DateTime.utc(2026, 11, 20),
      amount: const Money(1300000),
      partyName: 'Sea Street Mobiles',
      receiptNumber: 'RCP-1',
    );

    test(
      'sends the approved template with the cheque in its five slots',
      () async {
        late http.Request captured;
        final sender = WhatsAppCloudSender(
          accessToken: 'token-123',
          phoneNumberId: '555',
          templateName: 'cheque_reminder',
          templateLanguage: 'en',
          client: MockClient((request) async {
            captured = request;
            return http.Response('{"messages":[{"id":"x"}]}', 200);
          }),
        );
        await sender.send(to: '94771234567', cheque: cheque);

        expect(captured.url.path, '/v21.0/555/messages');
        expect(captured.headers['authorization'], 'Bearer token-123');
        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['to'], '94771234567');
        expect(body['template']['name'], 'cheque_reminder');
        final params = (body['template']['components'][0]['parameters'] as List)
            .map((p) => (p as Map)['text'])
            .toList();
        expect(params, [
          'Sea Street Mobiles',
          '456789',
          'Commercial Bank',
          'Rs. 13,000.00',
          '20 Nov 2026',
        ]);
      },
    );

    test('a refusal carries Meta\'s explanation', () async {
      final sender = WhatsAppCloudSender(
        accessToken: 't',
        phoneNumberId: '1',
        templateName: 'cheque_reminder',
        templateLanguage: 'en',
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"message":"Template name does not exist"}}',
            404,
          ),
        ),
      );
      await expectLater(
        sender.send(to: '94771234567', cheque: cheque),
        throwsA(
          predicate((e) => '$e'.contains('Template name does not exist')),
        ),
      );
    });

    test('without credentials it says so', () {
      final sender = WhatsAppCloudSender.fromEnvironment(const {});
      expect(sender.isConfigured, isFalse);
    });
  });

  test('local numbers are turned into international ones', () {
    expect(
      ChequeReminderService.parseNumbers(' 077 123 4567, +94 71 234 5678;bad '),
      ['94771234567', '94712345678'],
    );
  });
}
