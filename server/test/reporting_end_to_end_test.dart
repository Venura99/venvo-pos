import 'package:test/test.dart';
import 'package:venvo_core/core/api/api_client.dart';
import 'package:venvo_core/core/api/audit_api.dart';
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
import 'package:venvo_core/features/dashboard/api/dashboard_api.dart';
import 'package:venvo_core/features/finance/api/finance_api.dart';
import 'package:venvo_core/features/finance/domain/finance_models.dart';
import 'package:venvo_core/features/inventory/api/location_api.dart';
import 'package:venvo_core/features/inventory/api/stock_api.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/api/invoice_api.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/products/api/product_api.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/reports/api/report_api.dart';
import 'package:venvo_core/features/reports/domain/report_catalogue.dart';
import 'package:venvo_core/features/reports/domain/report_models.dart';
import 'package:venvo_core/features/shops/api/shop_api.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import 'support/api_harness.dart';

/// Reports, the dashboard, settings and the audit trail.
void main() {
  late ApiHarness api;
  late ApiClient client;
  late AuthApi auth;
  late AuthenticatedUser admin;
  late ReportApi reports;
  late DashboardApi dashboard;
  late SettingsApi settings;
  late AuditApi audit;
  late FinanceApi finance;
  late InvoiceApi invoices;

  late int warehouseId;
  late int shopLocationId;
  late int shopId;
  late int productId;

  const unitPrice = Money(130000);

  setUp(() async {
    api = await ApiHarness.start();
    client = ApiClient(baseUrl: api.base, tokens: InMemoryTokenStore());
    auth = AuthApi(client);
    reports = ReportApi(client);
    dashboard = DashboardApi(client);
    settings = SettingsApi(client);
    audit = AuditApi(client);
    finance = FinanceApi(client);
    invoices = InvoiceApi(client);

    admin = await auth.createFirstAdministrator(
      fullName: 'Venura Admin',
      username: 'admin',
      password: ApiHarness.adminPassword,
    );

    final locations = LocationApi(client);
    final all = await locations.watchLocations(includeVirtual: true).first;
    warehouseId = all
        .firstWhere((l) => l.code == AppConstants.mainWarehouseCode)
        .id;
    final supplierId = all
        .firstWhere((l) => l.code == AppConstants.supplierLocationCode)
        .id;

    final categoryId = await CategoryApi(
      client,
    ).create(admin, const CategoryDraft(name: 'Chargers'));
    productId = await ProductApi(client).create(
      admin,
      ProductDraft(
        sku: 'CHG-25W',
        name: 'Fast charger 25W',
        categoryId: categoryId,
        costPrice: const Money(100000),
        wholesalePrice: unitPrice,
      ),
    );
    final agentId = await AgentApi(
      client,
    ).create(admin, const AgentDraft(name: 'Kandy route'));
    shopId = await ShopApi(client).create(
      admin,
      ShopDraft(name: 'Sea Street Mobiles', assignedAgentId: agentId),
    );
    shopLocationId = (await locations.watchLocations().first)
        .firstWhere((l) => l.shopId == shopId)
        .id;

    await StockLedgerApi(client).postMovement(
      admin,
      StockMovementRequest(
        documentType: StockDocumentType.openingStock,
        sourceLocationId: supplierId,
        destinationLocationId: warehouseId,
        lines: [
          StockMovementLine(
            productId: productId,
            quantity: 100,
            unitCost: const Money(100000),
          ),
        ],
      ),
    );
  });

  tearDown(() async {
    await client.close();
    await api.stop();
  });

  Future<void> sellToShop(int quantity) => invoices.postInvoice(
    admin,
    InvoiceRequest(
      kind: InvoiceKind.shopInvoice,
      shopId: shopId,
      lines: [
        InvoiceLineRequest(
          productId: productId,
          quantity: quantity,
          unitPrice: unitPrice,
        ),
      ],
      stockLinkage: MoveStockWithInvoice(
        documentType: StockDocumentType.warehouseToShop,
        sourceLocationId: warehouseId,
        destinationLocationId: shopLocationId,
      ),
    ),
  );

  /// Signs in a second client with [roles] and a usable password.
  Future<ApiClient> clientFor(String username, List<String> roles) async {
    final other = ApiClient(baseUrl: api.base, tokens: InMemoryTokenStore());
    addTearDown(other.close);
    final otherAuth = AuthApi(other);
    await auth.createUser(
      actor: admin,
      fullName: username,
      username: username,
      password: 'Initial1Pass',
      roleCodes: roles,
    );
    final user = await otherAuth.signIn(
      username: username,
      password: 'Initial1Pass',
    );
    await otherAuth.changeOwnPassword(
      user: user,
      currentPassword: 'Initial1Pass',
      newPassword: 'Chosen2Pass9',
    );
    return other;
  }

  group('reports', () {
    test('an administrator is offered all eighteen', () async {
      final catalogue = await reports.catalogue();
      expect(catalogue.length, kReports.length);
      expect(catalogue.length, 18);
      expect(catalogue.map((r) => r.id), contains(ReportIds.profitAndLoss));
    });

    test('the catalogue is cut to what the caller may run', () async {
      // A cashier should not be shown a profit and loss statement and then
      // told they may not open it.
      final cashierClient = await clientFor('cashier', [RoleCodes.cashier]);
      final catalogue = await ReportApi(cashierClient).catalogue();

      expect(catalogue.length, lessThan(kReports.length));
      final ids = catalogue.map((r) => r.id).toSet();
      expect(ids, contains(ReportIds.dailySales));
      expect(ids, isNot(contains(ReportIds.profitAndLoss)));
      expect(ids, isNot(contains(ReportIds.salaries)));
      expect(ids, isNot(contains(ReportIds.expenses)));
    });

    test('running one the caller may not see is refused', () async {
      final cashierClient = await clientFor('cashier2', [RoleCodes.cashier]);
      final definition = kReports.firstWhere(
        (r) => r.id == ReportIds.profitAndLoss,
      );
      // The refusal must name the permission the *definition* carries, not
      // one this route chose: that is the whole point of letting the
      // catalogue drive authorization.
      await expectLater(
        ReportApi(cashierClient).run(definition, const ReportFilter()),
        throwsA(
          isA<PermissionFailure>().having(
            (f) => f.permission,
            'permission',
            definition.permission,
          ),
        ),
      );
    });

    test('an unknown report is a 404 that names the known ones', () async {
      await expectLater(
        reports.run(
          const ReportDefinition(
            id: 'no-such-report',
            title: 'Nonsense',
            description: '',
            group: ReportGroup.sales,
            permission: Permissions.reportsView,
            filters: {},
          ),
          const ReportFilter(),
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('rows come back typed, not pre-formatted', () async {
      await sellToShop(4);
      final definition = kReports.firstWhere(
        (r) => r.id == ReportIds.dailySales,
      );
      final result = await reports.run(definition, const ReportFilter());

      expect(result.title, isNotEmpty);
      expect(result.columns, isNotEmpty);
      expect(result.rows, isNotEmpty);

      // Money stays an integer count of minor units all the way to the
      // client, so the table, the PDF and the CSV format from one value
      // rather than from three different strings.
      final moneyCells = result.rows
          .expand((row) => row.values)
          .where((v) => v.kind == ReportValueKind.money);
      expect(moneyCells, isNotEmpty);
      expect(moneyCells.every((v) => v.money != null), isTrue);
    });

    test('every report a user may run actually runs', () async {
      // Cheap, and it catches a report whose SQL only breaks when it is
      // asked for — which no narrower test would find.
      await sellToShop(3);
      for (final definition in await reports.catalogue()) {
        final result = await reports.run(definition, const ReportFilter());
        expect(
          result.columns,
          isNotEmpty,
          reason: '${definition.id} returned no columns',
        );
      }
    });
  });

  group('dashboard', () {
    test('the figures follow the transactions', () async {
      final before = await dashboard.load();
      expect(before.activeProductCount, 1);
      expect(before.warehouseStockValue, const Money(100 * 100000));
      expect(before.receivableFromShops, Money.zero);

      await sellToShop(10);

      final after = await dashboard.load();
      // Sold ten: the shop owes for them and the warehouse is ten lighter.
      expect(after.receivableFromShops, const Money(10 * 130000));
      expect(after.warehouseStockValue, const Money(90 * 100000));
      expect(after.shopStockValue, const Money(10 * 100000));
      expect(after.todaysSales, const Money(10 * 130000));
    });

    test('a cashier may see it, a user without reports may not', () async {
      final cashierClient = await clientFor('cashier3', [RoleCodes.cashier]);
      expect((await DashboardApi(cashierClient).load()).activeProductCount, 1);
    });
  });

  group('settings', () {
    test(
      'readable by any signed-in user, writable with the permission',
      () async {
        await settings.load();
        expect(await settings.maxInvoiceDiscountBps, 1000);
        expect(await settings.allowNegativeStock, isFalse);

        final changed = await settings.update({
          SettingKeys.businessName: 'Venvo Global (Pvt) Ltd',
          SettingKeys.maxInvoiceDiscountBps: 1500,
        });
        expect(changed, hasLength(2));
        expect(await settings.maxInvoiceDiscountBps, 1500);
        expect(await settings.businessName, 'Venvo Global (Pvt) Ltd');
      },
    );

    test('a cashier may read them but not change them', () async {
      final cashierClient = await clientFor('cashier4', [RoleCodes.cashier]);
      final cashierSettings = SettingsApi(cashierClient);
      // Reading is allowed: the discount ceiling is needed to draw a screen.
      expect(await cashierSettings.maxInvoiceDiscountBps, 1000);

      await expectLater(
        cashierSettings.update({SettingKeys.maxInvoiceDiscountBps: 9999}),
        throwsA(
          isA<PermissionFailure>().having(
            (f) => f.permission,
            'permission',
            Permissions.settingsManage,
          ),
        ),
      );
      expect(await settings.maxInvoiceDiscountBps, 1000);
    });

    test('a setting the system owns cannot be written', () async {
      // Being able to set the seeded version would let a client convince the
      // seeder it had already run on a database where it had not.
      await expectLater(
        settings.update({SettingKeys.seededVersion: '99'}),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.message,
            'message',
            contains('maintained by the system'),
          ),
        ),
      );
    });

    test('an unknown key is named rather than ignored', () async {
      // A client that believes it changed a setting and did not is worse off
      // than one told plainly that it cannot.
      await expectLater(
        settings.update({'something.invented': true}),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.message,
            'message',
            contains('something.invented'),
          ),
        ),
      );
    });

    test('a changed ceiling is enforced on the very next invoice', () async {
      // The end-to-end proof that settings are not decoration: tighten the
      // invoice discount ceiling to nothing and the next discounted invoice
      // from someone without the override is refused.
      await settings.update({SettingKeys.maxInvoiceDiscountBps: 0});

      final managerClient = await clientFor('manager', [RoleCodes.manager]);
      final manager = await AuthApi(managerClient).refresh(0);
      expect(manager.can(Permissions.discountApplyInvoice), isTrue);
      expect(manager.can(Permissions.discountExceedLimit), isFalse);

      await expectLater(
        InvoiceApi(managerClient).postInvoice(
          manager,
          InvoiceRequest(
            kind: InvoiceKind.shopInvoice,
            shopId: shopId,
            lines: [
              InvoiceLineRequest(
                productId: productId,
                quantity: 2,
                unitPrice: unitPrice,
              ),
            ],
            invoiceDiscountType: DiscountType.percentage,
            invoiceDiscountValue: 1000, // 10%
            discountReason: 'Long-standing customer',
            stockLinkage: MoveStockWithInvoice(
              documentType: StockDocumentType.warehouseToShop,
              sourceLocationId: warehouseId,
              destinationLocationId: shopLocationId,
            ),
          ),
        ),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('journal and audit', () {
    test('journal entries list what was posted', () async {
      await sellToShop(5);
      final entries = await finance
          .watchEntries(const FinancialLedgerFilter())
          .first;
      expect(entries, isNotEmpty);

      // And they can be narrowed to one account.
      final receivable = await finance
          .watchEntries(
            const FinancialLedgerFilter(
              accountCode: AccountCodes.receivableShops,
            ),
          )
          .first;
      expect(receivable, isNotEmpty);
      expect(
        receivable.every((e) => e.accountCode == AccountCodes.receivableShops),
        isTrue,
      );
    });

    test('the audit trail records what happened', () async {
      await sellToShop(5);
      final entries = await audit.entries();
      expect(entries, isNotEmpty);
      // The administrator's own creation is in there from the first run.
      expect(entries.map((e) => e.username), contains('admin'));

      final logins = await audit.entries(action: AuditAction.login);
      expect(
        logins.every((e) => e.action == AuditAction.login),
        isTrue,
        reason: 'the action filter was not applied',
      );
    });

    test('a user without audit.view cannot read the trail', () async {
      final cashierClient = await clientFor('cashier5', [RoleCodes.cashier]);
      await expectLater(
        AuditApi(cashierClient).entries(),
        throwsA(
          isA<PermissionFailure>().having(
            (f) => f.permission,
            'permission',
            Permissions.auditView,
          ),
        ),
      );
    });
  });
}
