import 'package:drift/drift.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/services/password_hasher.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/data/agent_repository.dart';
import 'package:venvo_core/features/authentication/data/auth_repository.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';
import 'package:venvo_core/features/categories/data/category_repository.dart';
import 'package:venvo_core/features/dashboard/data/dashboard_repository.dart';
import 'package:venvo_core/features/employees/data/employee_repository.dart';
import 'package:venvo_core/features/expenses/data/expense_query_repository.dart';
import 'package:venvo_core/features/expenses/data/expense_service.dart';
import 'package:venvo_core/features/finance/data/financial_ledger_service.dart';
import 'package:venvo_core/features/inventory/data/location_repository.dart';
import 'package:venvo_core/features/inventory/data/stock_ledger_service.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/data/invoice_service.dart';
import 'package:venvo_core/features/payments/data/payment_service.dart';
import 'package:venvo_core/features/petty_cash/data/petty_cash_service.dart';
import 'package:venvo_core/features/products/data/product_repository.dart';
import 'package:venvo_core/features/reports/data/report_repository.dart';
import 'package:venvo_core/features/returns/data/return_query_repository.dart';
import 'package:venvo_core/features/returns/data/return_service.dart';
import 'package:venvo_core/features/salaries/data/salary_query_repository.dart';
import 'package:venvo_core/features/salaries/data/salary_service.dart';
import 'package:venvo_core/features/shops/data/shop_repository.dart';

import 'test_harness.dart';

/// Assembles the master-data repositories over a test harness, with an
/// administrator already signed in.
///
/// Every Phase 2 test starts from one of these, so the wiring under test is
/// the same wiring the application uses rather than a simplified stand-in.
class MasterDataFixture {
  MasterDataFixture._({
    required this.harness,
    required this.admin,
    required this.auth,
    required this.stockLedger,
    required this.payments,
    required this.invoices,
    required this.returns,
    required this.finance,
    required this.expenses,
    required this.expenseQueries,
    required this.pettyCash,
    required this.salaries,
    required this.salaryQueries,
    required this.reports,
    required this.dashboard,
    required this.returnQueries,
    required this.categories,
    required this.products,
    required this.locations,
    required this.agents,
    required this.shops,
    required this.employees,
  });

  static Future<MasterDataFixture> create({DateTime? at}) async {
    final harness = await TestHarness.create(at: at);
    final bootstrap = harness.bootstrap;

    final auth = AuthRepository(
      database: harness.db,
      clock: harness.clock,
      audit: bootstrap.audit,
      // Low cost: these tests are about master data, not password hashing.
      hasher: const PasswordHasher(iterations: 1000),
    );
    final admin = await auth.createFirstAdministrator(
      fullName: 'Nimal Perera',
      username: 'nimal',
      password: 'Warehouse42',
    );

    final locations = LocationRepository(
      database: harness.db,
      clock: harness.clock,
      audit: bootstrap.audit,
      sequences: bootstrap.sequences,
    );
    final finance = FinancialLedgerService(
      database: harness.db,
      clock: harness.clock,
      sequences: bootstrap.sequences,
    );
    final ledger = StockLedgerService(
      database: harness.db,
      clock: harness.clock,
      audit: bootstrap.audit,
      sequences: bootstrap.sequences,
      settings: bootstrap.settings,
      finance: finance,
    );
    final pettyCash = PettyCashService(
      database: harness.db,
      clock: harness.clock,
      audit: bootstrap.audit,
      sequences: bootstrap.sequences,
      finance: finance,
    );
    final paymentService = PaymentService(
      database: harness.db,
      clock: harness.clock,
      audit: bootstrap.audit,
      sequences: bootstrap.sequences,
      finance: finance,
    );

    return MasterDataFixture._(
      harness: harness,
      admin: admin,
      auth: auth,
      stockLedger: ledger,
      payments: paymentService,
      finance: finance,
      invoices: InvoiceService(
        database: harness.db,
        clock: harness.clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        settings: bootstrap.settings,
        ledger: ledger,
        payments: paymentService,
        finance: finance,
      ),
      returns: ReturnService(
        database: harness.db,
        clock: harness.clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        ledger: ledger,
        locations: locations,
        finance: finance,
      ),
      returnQueries: ReturnQueryRepository(harness.db),
      expenses: ExpenseService(
        database: harness.db,
        clock: harness.clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        finance: finance,
        pettyCash: pettyCash,
      ),
      expenseQueries: ExpenseQueryRepository(harness.db),
      pettyCash: pettyCash,
      salaries: SalaryService(
        database: harness.db,
        clock: harness.clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        finance: finance,
      ),
      salaryQueries: SalaryQueryRepository(harness.db),
      reports: ReportRepository(
        database: harness.db,
        clock: harness.clock,
        finance: finance,
      ),
      dashboard: DashboardRepository(harness.db, harness.clock),
      categories: CategoryRepository(
        database: harness.db,
        clock: harness.clock,
        audit: bootstrap.audit,
      ),
      products: ProductRepository(
        database: harness.db,
        clock: harness.clock,
        audit: bootstrap.audit,
      ),
      locations: locations,
      agents: AgentRepository(
        database: harness.db,
        clock: harness.clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        locations: locations,
      ),
      shops: ShopRepository(
        database: harness.db,
        clock: harness.clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
        locations: locations,
      ),
      employees: EmployeeRepository(
        database: harness.db,
        clock: harness.clock,
        audit: bootstrap.audit,
        sequences: bootstrap.sequences,
      ),
    );
  }

  final TestHarness harness;
  final AuthenticatedUser admin;
  final AuthRepository auth;
  final StockLedgerService stockLedger;
  final PaymentService payments;
  final InvoiceService invoices;
  final ReturnService returns;
  final FinancialLedgerService finance;
  final ExpenseService expenses;
  final ExpenseQueryRepository expenseQueries;
  final PettyCashService pettyCash;
  final SalaryService salaries;
  final SalaryQueryRepository salaryQueries;
  final ReportRepository reports;
  final DashboardRepository dashboard;
  final ReturnQueryRepository returnQueries;
  final CategoryRepository categories;
  final ProductRepository products;
  final LocationRepository locations;
  final AgentRepository agents;
  final ShopRepository shops;
  final EmployeeRepository employees;

  AppDatabase get db => harness.db;

  Future<void> dispose() => harness.dispose();

  /// A user holding only view permissions, for checking that writes are
  /// refused rather than silently allowed.
  Future<AuthenticatedUser> createViewer() async {
    return auth.createUser(
      actor: admin,
      fullName: 'Ravi Jayasuriya',
      username: 'ravi',
      password: 'Viewer123',
      roleCodes: const ['VIEWER'],
    );
  }

  // --- Convenience builders ----------------------------------------------

  /// Puts stock somewhere by posting a real opening-stock document through the
  /// ledger service, so the balances, the ledger and the document all exist
  /// exactly as they would in use.
  Future<StockMovementResult> postOpeningStock({
    required int locationId,
    required int productId,
    required int quantity,
    Money unitCost = const Money(200000),
  }) async {
    final supplier = await locations.byCode(AppConstants.supplierLocationCode);
    return stockLedger.postMovement(
      admin,
      StockMovementRequest(
        documentType: StockDocumentType.openingStock,
        sourceLocationId: supplier.id,
        destinationLocationId: locationId,
        lines: [
          StockMovementLine(
            productId: productId,
            quantity: quantity,
            unitCost: unitCost,
          ),
        ],
      ),
    );
  }

  /// Inserts a stock balance directly, bypassing the ledger.
  ///
  /// Used only where a test needs a balance to *exist* so a rule that depends
  /// on it can be exercised, and the ledger itself is not what is under test.
  /// Tests of the ledger use [postOpeningStock] instead.
  Future<void> giveStock({
    required int locationId,
    required int productId,
    required int quantity,
    Money unitCost = const Money(200000),
  }) async {
    await db
        .into(db.stockBalances)
        .insert(
          StockBalancesCompanion.insert(
            locationId: locationId,
            productId: productId,
            quantity: Value(quantity),
            averageCostCents: Value(unitCost.cents),
            updatedAt: harness.clock.nowUtc(),
          ),
        );
  }

  /// Posts an invoice against a party, for the outstanding-balance tests.
  Future<int> postInvoice({
    required String number,
    required Money netTotal,
    int? agentId,
    int? shopId,
    InvoiceKind kind = InvoiceKind.shopInvoice,
    PartyType partyType = PartyType.shop,
  }) {
    return db
        .into(db.invoices)
        .insert(
          InvoicesCompanion.insert(
            invoiceNumber: number,
            kind: kind,
            status: const Value(InvoiceStatus.posted),
            invoiceDate: harness.clock.nowUtc(),
            partyType: partyType,
            agentId: Value(agentId),
            shopId: Value(shopId),
            grossTotalCents: Value(netTotal.cents),
            netTotalCents: Value(netTotal.cents),
            createdByUserId: admin.id,
            createdAt: harness.clock.nowUtc(),
            postedAt: Value(harness.clock.nowUtc()),
          ),
        );
  }

  /// Records a payment and, optionally, allocates it to an invoice.
  Future<int> recordPayment({
    required String number,
    required Money amount,
    required PaymentMethod method,
    required PaymentStatus status,
    int? agentId,
    int? shopId,
    int? allocateToInvoiceId,
    ChequeStatus? chequeStatus,
  }) async {
    final paymentId = await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            receiptNumber: number,
            direction: PaymentDirection.inbound,
            method: method,
            status: Value(status),
            paymentDate: harness.clock.nowUtc(),
            partyType: agentId != null ? PartyType.agent : PartyType.shop,
            agentId: Value(agentId),
            shopId: Value(shopId),
            amountCents: amount.cents,
            allocatedCents: Value(
              allocateToInvoiceId == null ? 0 : amount.cents,
            ),
            createdByUserId: admin.id,
            createdAt: harness.clock.nowUtc(),
          ),
        );

    if (allocateToInvoiceId != null) {
      await db
          .into(db.paymentAllocations)
          .insert(
            PaymentAllocationsCompanion.insert(
              paymentId: paymentId,
              invoiceId: allocateToInvoiceId,
              amountCents: amount.cents,
              createdByUserId: admin.id,
              createdAt: harness.clock.nowUtc(),
            ),
          );
    }

    if (method == PaymentMethod.cheque) {
      await db
          .into(db.cheques)
          .insert(
            ChequesCompanion.insert(
              paymentId: paymentId,
              chequeNumber: 'CHQ-$number',
              bankName: 'Commercial Bank',
              chequeDate: harness.clock.nowUtc(),
              status: Value(chequeStatus ?? ChequeStatus.pending),
              createdAt: harness.clock.nowUtc(),
              updatedAt: harness.clock.nowUtc(),
            ),
          );
    }

    return paymentId;
  }

  /// Reads the audit log newest first.
  Future<List<AuditLog>> auditEntries() {
    return (db.select(
      db.auditLogs,
    )..orderBy([(row) => OrderingTerm.desc(row.id)])).get();
  }
}
