import 'package:test/test.dart';
import 'package:venvo_core/core/api/api_client.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/authentication/api/auth_api.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';
import 'package:venvo_core/features/employees/api/employee_api.dart';
import 'package:venvo_core/features/employees/domain/employee_models.dart';
import 'package:venvo_core/features/expenses/api/expense_api.dart';
import 'package:venvo_core/features/expenses/domain/expense_models.dart';
import 'package:venvo_core/features/finance/api/finance_api.dart';
import 'package:venvo_core/features/petty_cash/api/petty_cash_api.dart';
import 'package:venvo_core/features/petty_cash/domain/petty_cash_models.dart';
import 'package:venvo_core/features/salaries/api/salary_api.dart';
import 'package:venvo_core/features/salaries/domain/salary_models.dart';

import 'support/api_harness.dart';

/// Expenses, the petty cash float and payroll.
///
/// What is being checked: that money going *out* of the business is recorded
/// as carefully as money coming in. Every one of these posts to the journal,
/// and the journal is asserted balanced after each.
void main() {
  late ApiHarness api;
  late ApiClient client;
  late AuthApi auth;
  late AuthenticatedUser admin;
  late ExpenseApi expenses;
  late ExpenseQueryApi expenseQueries;
  late PettyCashApi pettyCash;
  late SalaryApi salaries;
  late SalaryQueryApi salaryQueries;
  late FinanceApi finance;

  late int categoryId;
  late int employeeId;

  const basicSalary = Money(6500000); // Rs 65,000.00

  setUp(() async {
    api = await ApiHarness.start();
    client = ApiClient(baseUrl: api.base, tokens: InMemoryTokenStore());
    auth = AuthApi(client);
    expenses = ExpenseApi(client);
    expenseQueries = ExpenseQueryApi(client);
    pettyCash = PettyCashApi(client);
    salaries = SalaryApi(client);
    salaryQueries = SalaryQueryApi(client);
    finance = FinanceApi(client);

    admin = await auth.createFirstAdministrator(
      fullName: 'Venura Admin',
      username: 'admin',
      password: ApiHarness.adminPassword,
    );

    // The seed ships a set of expense categories; use the first real one.
    final categories = await expenseQueries.watchCategories().first;
    expect(categories, isNotEmpty, reason: 'the seed provides categories');
    categoryId = categories.first.id;

    employeeId = await EmployeeApi(client).create(
      admin,
      const EmployeeDraft(
        name: 'Nimal Perera',
        designation: 'Driver',
        basicSalary: basicSalary,
      ),
    );
  });

  tearDown(() async {
    await client.close();
    await api.stop();
  });

  Future<void> expectBooksBalanced() async {
    expect(await finance.findUnbalancedBatches(), isEmpty);
    expect((await finance.trialBalance()).isBalanced, isTrue);
  }

  Future<Money> cash() => finance.balanceOf(AccountCodes.cashOnHand);

  /// Puts money into the float so there is something to spend.
  Future<void> topUpFloat(Money amount) => pettyCash.recordEntry(
    admin,
    PettyCashDraft(
      kind: PettyCashEntryKind.cashReceived,
      amount: amount,
      description: 'Float top-up',
    ),
  );

  group('expenses', () {
    test('an expense reaches the accounts', () async {
      final before = await cash();

      final id = await expenses.postExpense(
        admin,
        const ExpenseDraft(
          categoryId: 0, // replaced below
          description: 'Lorry diesel',
          amount: Money(2500000),
          paymentMethod: PaymentMethod.cash,
        ).copyForCategory(categoryId),
      );
      expect(id, greaterThan(0));

      final totals = await expenseQueries.totals(const ExpenseFilter());
      expect(totals.count, 1);
      expect(totals.total, const Money(2500000));

      // Cash went out of the business.
      expect(await cash(), before - const Money(2500000));
      await expectBooksBalanced();
    });

    test('an expense from the float moves both in one breath', () async {
      await topUpFloat(const Money(10000000));
      expect(await pettyCash.floatBalance(), const Money(10000000));

      await expenses.postExpense(
        admin,
        const ExpenseDraft(
          categoryId: 0,
          description: 'Tea and sugar',
          amount: Money(250000),
          paymentMethod: PaymentMethod.cash,
          fromPettyCash: true,
        ).copyForCategory(categoryId),
      );

      // The float paid for it, in the same transaction as the expense — the
      // two can never disagree about what was spent.
      expect(await pettyCash.floatBalance(), const Money(9750000));
      final totals = await expenseQueries.totals(const ExpenseFilter());
      expect(totals.fromPettyCash, const Money(250000));
      await expectBooksBalanced();
    });

    test('cancelling an expense reverses it', () async {
      final before = await cash();
      final id = await expenses.postExpense(
        admin,
        const ExpenseDraft(
          categoryId: 0,
          description: 'Booked in error',
          amount: Money(1000000),
          paymentMethod: PaymentMethod.cash,
        ).copyForCategory(categoryId),
      );
      expect(await cash(), before - const Money(1000000));

      await expenses.cancelExpense(
        admin,
        expenseId: id,
        reason: 'Duplicate entry',
      );

      expect(await cash(), before);
      final totals = await expenseQueries.totals(const ExpenseFilter());
      expect(totals.cancelledCount, 1);
      await expectBooksBalanced();
    });

    test('a duplicate category name is refused whatever the case', () async {
      await expenses.createCategory(admin, name: 'Vehicle Repairs');
      await expectLater(
        expenses.createCategory(admin, name: 'vehicle repairs'),
        throwsA(isA<AppFailure>()),
      );
    });

    test('an accountant may record expenses, a cashier may not', () async {
      final cashierClient = ApiClient(
        baseUrl: api.base,
        tokens: InMemoryTokenStore(),
      );
      addTearDown(cashierClient.close);
      final cashierAuth = AuthApi(cashierClient);
      await auth.createUser(
        actor: admin,
        fullName: 'Cashier',
        username: 'cashier',
        password: 'Initial1Pass',
        roleCodes: [RoleCodes.cashier],
      );
      final cashier = await cashierAuth.signIn(
        username: 'cashier',
        password: 'Initial1Pass',
      );
      await cashierAuth.changeOwnPassword(
        user: cashier,
        currentPassword: 'Initial1Pass',
        newPassword: 'Chosen2Pass9',
      );
      expect(cashier.can(Permissions.expenseManage), isFalse);

      await expectLater(
        ExpenseApi(cashierClient).postExpense(
          cashier,
          const ExpenseDraft(
            categoryId: 0,
            description: 'Not mine to record',
            amount: Money(100000),
            paymentMethod: PaymentMethod.cash,
          ).copyForCategory(categoryId),
        ),
        throwsA(
          isA<PermissionFailure>().having(
            (f) => f.permission,
            'permission',
            Permissions.expenseManage,
          ),
        ),
      );
      expect((await expenseQueries.totals(const ExpenseFilter())).count, 0);
    });
  });

  group('petty cash', () {
    test('the float is the sum of its entries', () async {
      expect(await pettyCash.floatBalance(), Money.zero);
      await topUpFloat(const Money(5000000));
      await pettyCash.recordEntry(
        admin,
        const PettyCashDraft(
          kind: PettyCashEntryKind.cashIssued,
          amount: Money(1200000),
          description: 'Advance to the driver for fuel',
        ),
      );

      expect(await pettyCash.floatBalance(), const Money(3800000));
      final snapshot = await pettyCash.snapshot(const PettyCashFilter());
      expect(snapshot.balance, const Money(3800000));
      expect(snapshot.entryCount, 2);
      await expectBooksBalanced();
    });

    test('recompute finds nothing to change on a healthy float', () async {
      await topUpFloat(const Money(5000000));
      await pettyCash.recordEntry(
        admin,
        const PettyCashDraft(
          kind: PettyCashEntryKind.cashIssued,
          amount: Money(900000),
          description: 'Stationery',
        ),
      );

      // The running balances are written as the entries are made, so a
      // replay should agree with every one of them. A non-zero answer here
      // would mean the stored float had drifted from its own history.
      expect(await pettyCash.recomputeBalances(admin), 0);
      expect(await pettyCash.floatBalance(), const Money(4100000));
    });
  });

  group('payroll', () {
    SalaryDraft draftFor({bool recoverAdvances = true}) => SalaryDraft(
      employeeId: employeeId,
      periodYear: 2026,
      periodMonth: 11,
      basicSalary: basicSalary,
      allowances: const Money(500000),
      bonus: Money.zero,
      deductions: const Money(200000),
      recoverAdvances: recoverAdvances,
    );

    test('compute works out the net without creating anything', () async {
      final computation = await salaries.compute(draftFor());
      // 65,000 + 5,000 − 2,000
      expect(computation.earned, const Money(6800000));
      expect(computation.advanceRecovered, Money.zero);
      expect(computation.net, const Money(6800000));

      // Nothing was written. Both counts matter: `count` covers approved
      // payroll and `draftCount` the rest, so checking only the first would
      // pass even if compute() had quietly created a draft.
      final totals = await salaryQueries.totals(const SalaryFilter());
      expect(totals.count, 0);
      expect(totals.draftCount, 0);
    });

    test('approval posts the liability, payment posts the cash', () async {
      final salaryId = await salaries.createSalary(admin, draftFor());
      final cashAfterCreate = await cash();

      await salaries.approveSalary(admin, salaryId: salaryId);
      // Approval records what is owed to the employee. No money has moved,
      // so the cash account is untouched.
      expect(await cash(), cashAfterCreate);
      await expectBooksBalanced();

      final paymentId = await salaries.paySalary(admin, salaryId: salaryId);
      expect(paymentId, greaterThan(0));
      expect(await cash(), cashAfterCreate - const Money(6800000));

      final detail = await salaryQueries.salaryDetail(salaryId);
      expect(detail.summary.status, SalaryStatus.paid);
      await expectBooksBalanced();
    });

    test('an advance is recovered out of the salary', () async {
      // The interaction that makes payroll more than arithmetic: money
      // already handed over has to come back off the payslip, or the employee
      // is paid twice.
      await salaries.recordAdvance(
        admin,
        employeeId: employeeId,
        amount: const Money(1500000),
      );
      expect(
        await salaries.outstandingAdvances(employeeId),
        const Money(1500000),
      );

      final computation = await salaries.compute(draftFor());
      expect(computation.earned, const Money(6800000));
      expect(computation.outstandingAdvances, const Money(1500000));
      expect(computation.advanceRecovered, const Money(1500000));
      expect(computation.net, const Money(5300000));

      final salaryId = await salaries.createSalary(admin, draftFor());
      await salaries.approveSalary(admin, salaryId: salaryId);
      final before = await cash();
      await salaries.paySalary(admin, salaryId: salaryId);

      // Only the net leaves the till, and the advance is settled.
      expect(await cash(), before - const Money(5300000));
      expect(await salaries.outstandingAdvances(employeeId), Money.zero);
      await expectBooksBalanced();
    });

    test('an advance can be left alone if asked', () async {
      await salaries.recordAdvance(
        admin,
        employeeId: employeeId,
        amount: const Money(1500000),
      );
      final computation = await salaries.compute(
        draftFor(recoverAdvances: false),
      );
      expect(computation.advanceRecovered, Money.zero);
      expect(computation.net, const Money(6800000));
      expect(
        await salaries.outstandingAdvances(employeeId),
        const Money(1500000),
      );
    });

    test('cancelling a salary puts the advance back', () async {
      await salaries.recordAdvance(
        admin,
        employeeId: employeeId,
        amount: const Money(1500000),
      );
      final salaryId = await salaries.createSalary(admin, draftFor());
      await salaries.approveSalary(admin, salaryId: salaryId);
      expect(await salaries.outstandingAdvances(employeeId), Money.zero);

      await salaries.cancelSalary(
        admin,
        salaryId: salaryId,
        reason: 'Wrong period',
      );

      // The recovery is undone, so the advance is owed again rather than
      // quietly written off against a salary that no longer exists.
      expect(
        await salaries.outstandingAdvances(employeeId),
        const Money(1500000),
      );
      await expectBooksBalanced();
    });

    test('the same period cannot be run twice for one employee', () async {
      await salaries.createSalary(admin, draftFor());
      await expectLater(
        salaries.createSalary(admin, draftFor()),
        throwsA(isA<AppFailure>()),
      );
      // One draft, and only one. `count` stays at zero because nothing has
      // been approved yet — totals mean committed payroll, not drafts.
      final totals = await salaryQueries.totals(const SalaryFilter());
      expect(totals.draftCount, 1);
      expect(totals.count, 0);
    });

    test('an accountant may run payroll, a storekeeper may not', () async {
      final keeperClient = ApiClient(
        baseUrl: api.base,
        tokens: InMemoryTokenStore(),
      );
      addTearDown(keeperClient.close);
      final keeperAuth = AuthApi(keeperClient);
      await auth.createUser(
        actor: admin,
        fullName: 'Store Keeper',
        username: 'keeper',
        password: 'Initial1Pass',
        roleCodes: [RoleCodes.storeKeeper],
      );
      final keeper = await keeperAuth.signIn(
        username: 'keeper',
        password: 'Initial1Pass',
      );
      await keeperAuth.changeOwnPassword(
        user: keeper,
        currentPassword: 'Initial1Pass',
        newPassword: 'Chosen2Pass9',
      );
      expect(keeper.can(Permissions.salaryManage), isFalse);

      await expectLater(
        SalaryApi(keeperClient).createSalary(keeper, draftFor()),
        throwsA(isA<PermissionFailure>()),
      );
      final totals = await salaryQueries.totals(const SalaryFilter());
      expect(totals.count, 0);
      expect(totals.draftCount, 0, reason: 'no draft should have been left');
    });
  });
}

/// Rebuilds a draft with the real category id.
///
/// The drafts above are written as `const` for readability, which means the
/// category id cannot be interpolated; this swaps it in.
extension on ExpenseDraft {
  ExpenseDraft copyForCategory(int id) => ExpenseDraft(
    categoryId: id,
    description: description,
    amount: amount,
    paymentMethod: paymentMethod,
    expenseDate: expenseDate,
    paidByEmployeeId: paidByEmployeeId,
    referenceNumber: referenceNumber,
    fromPettyCash: fromPettyCash,
    notes: notes,
  );
}
