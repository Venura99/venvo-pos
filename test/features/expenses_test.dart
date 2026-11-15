import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/employees/domain/employee_models.dart';
import 'package:venvo_core/features/expenses/domain/expense_models.dart';
import 'package:venvo_core/features/petty_cash/domain/petty_cash_models.dart';

import '../helpers/master_data_fixtures.dart';

/// Expenses and the petty cash float.
///
/// The thing worth proving over and over: money that leaves the business is
/// recorded once. An expense paid from the float reduces the float and the
/// journal once each, never twice, and the float can never be driven below
/// what is actually in the box.
void main() {
  late MasterDataFixture fixture;
  late int transportId;
  late int rentId;

  setUp(() async {
    fixture = await MasterDataFixture.create();

    final categories = await fixture.expenseQueries.watchCategories().first;
    transportId = categories
        .firstWhere((c) => c.name.toLowerCase().contains('transport'))
        .id;
    rentId = categories
        .firstWhere((c) => c.name.toLowerCase().contains('rent'))
        .id;
  });

  tearDown(() => fixture.dispose());

  Future<Money> account(String code) => fixture.finance.balanceOf(code);

  Future<void> expectJournalSound() async {
    expect(await fixture.finance.findUnbalancedBatches(), isEmpty);
    final balance = await fixture.finance.trialBalance();
    expect(balance.totalDebits, balance.totalCredits);
  }

  Future<int> postExpense({
    int? categoryId,
    Money amount = const Money(500000),
    PaymentMethod method = PaymentMethod.cash,
    bool fromPettyCash = false,
    String description = 'Lorry hire to Kandy',
    int? paidByEmployeeId,
  }) {
    return fixture.expenses.postExpense(
      fixture.admin,
      ExpenseDraft(
        categoryId: categoryId ?? transportId,
        description: description,
        amount: amount,
        paymentMethod: method,
        fromPettyCash: fromPettyCash,
        paidByEmployeeId: paidByEmployeeId,
      ),
    );
  }

  /// Puts cash into the float so expenses can come out of it.
  Future<void> openFloat([Money amount = const Money(2000000)]) {
    return fixture.pettyCash.recordEntry(
      fixture.admin,
      PettyCashDraft(
        kind: PettyCashEntryKind.opening,
        amount: amount,
        description: 'Opening float',
      ),
    );
  }

  group('recording an expense', () {
    test('posts the voucher and the accounting together', () async {
      final expenseId = await postExpense(amount: Money.fromMajor(5000));

      final expense =
          (await fixture.expenseQueries
                  .watchExpenses(const ExpenseFilter())
                  .first)
              .single;

      expect(expense.id, expenseId);
      expect(expense.voucherNumber, startsWith('EXP-'));
      expect(expense.amount, Money.fromMajor(5000));
      expect(expense.categoryName, contains('Transport'));
      expect(expense.isPosted, isTrue);
      expect(expense.fromPettyCash, isFalse);

      expect(
        await account(AccountCodes.operatingExpenses),
        Money.fromMajor(5000),
      );
      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(-5000));
      await expectJournalSound();
    });

    test('a bank payment comes out of the bank, not the cash box', () async {
      await postExpense(
        amount: Money.fromMajor(12000),
        method: PaymentMethod.bankTransfer,
        categoryId: rentId,
        description: 'Warehouse rent, November',
      );

      expect(await account(AccountCodes.bank), Money.fromMajor(-12000));
      expect(await account(AccountCodes.cashOnHand), Money.zero);
      await expectJournalSound();
    });

    test('refuses an amount of zero or less', () async {
      await expectLater(
        postExpense(amount: Money.zero),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        postExpense(amount: Money.fromMajor(-100)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('requires a description', () async {
      await expectLater(
        postExpense(description: '   '),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('needs the expense permission', () async {
      final viewer = await fixture.createViewer();

      await expectLater(
        fixture.expenses.postExpense(
          viewer,
          ExpenseDraft(
            categoryId: transportId,
            description: 'Fuel',
            amount: Money.fromMajor(1000),
            paymentMethod: PaymentMethod.cash,
          ),
        ),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('records who spent the money when somebody did', () async {
      final employeeId = await fixture.employees.create(
        fixture.admin,
        const EmployeeDraft(name: 'Kamal Fernando', designation: 'Driver'),
      );

      await postExpense(paidByEmployeeId: employeeId);

      final expense =
          (await fixture.expenseQueries
                  .watchExpenses(const ExpenseFilter())
                  .first)
              .single;
      expect(expense.paidByEmployeeName, 'Kamal Fernando');
    });

    test('refuses a category that has been archived', () async {
      final customId = await fixture.expenses.createCategory(
        fixture.admin,
        name: 'Festival advances',
      );
      await fixture.expenses.archiveCategory(
        fixture.admin,
        categoryId: customId,
      );

      await expectLater(
        postExpense(categoryId: customId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'expense.category_must_be_active',
          ),
        ),
      );
    });

    test('records it in the audit log', () async {
      await postExpense(amount: Money.fromMajor(5000));

      final entry = (await fixture.auditEntries()).firstWhere(
        (row) => row.entityKind == EntityKind.expense,
      );
      expect(entry.action, AuditAction.post);
      expect(entry.summary, contains('EXP-'));
      expect(entry.summary, contains('Transport'));
    });
  });

  group('paying an expense out of petty cash', () {
    test('reduces the float once and the journal once', () async {
      await openFloat(Money.fromMajor(20000));
      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(20000));

      await postExpense(amount: Money.fromMajor(3000), fromPettyCash: true);

      // The float is down by the expense, and only by the expense.
      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(17000));
      expect(await account(AccountCodes.pettyCash), Money.fromMajor(17000));
      // The cash box is untouched beyond the original top-up: the money came
      // out of the float, and it is not counted twice.
      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(-20000));
      expect(
        await account(AccountCodes.operatingExpenses),
        Money.fromMajor(3000),
      );
      await expectJournalSound();
    });

    test('shows up in the petty cash book against the voucher', () async {
      await openFloat();
      await postExpense(amount: Money.fromMajor(3000), fromPettyCash: true);

      final rows = await fixture.pettyCash
          .watchEntries(const PettyCashFilter())
          .first;
      final expenseRow = rows.firstWhere((row) => row.isExpense);

      expect(expenseRow.amount, Money.fromMajor(3000));
      expect(expenseRow.signedAmount, Money.fromMajor(-3000));
      expect(expenseRow.expenseVoucherNumber, startsWith('EXP-'));
      expect(expenseRow.description, contains('Lorry hire'));
    });

    test('is refused when the float cannot stand it', () async {
      await openFloat(Money.fromMajor(1000));

      await expectLater(
        postExpense(amount: Money.fromMajor(5000), fromPettyCash: true),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'petty_cash.no_negative_float',
          ),
        ),
      );

      // Nothing half-written: no expense, no float movement beyond the float
      // being opened.
      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(1000));
      expect(
        await fixture.expenseQueries.watchExpenses(const ExpenseFilter()).first,
        isEmpty,
      );
      await expectJournalSound();
    });

    test('has to be recorded as cash, because the float is cash', () async {
      await openFloat();

      await expectLater(
        postExpense(fromPettyCash: true, method: PaymentMethod.bankTransfer),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'expense.petty_cash_is_cash',
          ),
        ),
      );
    });
  });

  group('cancelling an expense', () {
    test('keeps the voucher and takes the accounting back out', () async {
      final expenseId = await postExpense(amount: Money.fromMajor(5000));

      await fixture.expenses.cancelExpense(
        fixture.admin,
        expenseId: expenseId,
        reason: 'Booked to the wrong month',
      );

      final expense =
          (await fixture.expenseQueries
                  .watchExpenses(const ExpenseFilter())
                  .first)
              .single;
      expect(expense.isCancelled, isTrue);
      expect(expense.cancelReason, 'Booked to the wrong month');
      // Still readable: history is preserved, not erased.
      expect(expense.amount, Money.fromMajor(5000));

      expect(await account(AccountCodes.operatingExpenses), Money.zero);
      expect(await account(AccountCodes.cashOnHand), Money.zero);
      await expectJournalSound();
    });

    test('puts money back into the float it came from', () async {
      await openFloat(Money.fromMajor(20000));
      final expenseId = await postExpense(
        amount: Money.fromMajor(3000),
        fromPettyCash: true,
      );
      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(17000));

      await fixture.expenses.cancelExpense(
        fixture.admin,
        expenseId: expenseId,
        reason: 'Paid by the driver after all',
      );

      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(20000));
      // Both the payment and its reversal are in the book, so the cash trail
      // is complete rather than tidied up.
      final rows = await fixture.pettyCash
          .watchEntries(const PettyCashFilter())
          .first;
      expect(rows, hasLength(3));
      expect(await account(AccountCodes.pettyCash), Money.fromMajor(20000));
      await expectJournalSound();
    });

    test('cannot be done twice', () async {
      final expenseId = await postExpense();
      await fixture.expenses.cancelExpense(
        fixture.admin,
        expenseId: expenseId,
        reason: 'First',
      );

      await expectLater(
        fixture.expenses.cancelExpense(
          fixture.admin,
          expenseId: expenseId,
          reason: 'Second',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'expense.cancel_posted_only',
          ),
        ),
      );
    });

    test('requires a reason', () async {
      final expenseId = await postExpense();

      await expectLater(
        fixture.expenses.cancelExpense(
          fixture.admin,
          expenseId: expenseId,
          reason: '  ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('categories', () {
    test('the standard set is seeded, with "Other" protected', () async {
      final categories = await fixture.expenseQueries.watchCategories().first;

      expect(categories, isNotEmpty);
      expect(
        categories.map((c) => c.name),
        containsAll(<String>['Transport', 'Fuel', 'Warehouse Rent', 'Other']),
      );

      // "Other" is the fallback category, so it cannot be archived away.
      final other = categories.firstWhere((c) => c.name == 'Other');
      expect(other.isSystem, isTrue);
      await expectLater(
        fixture.expenses.archiveCategory(fixture.admin, categoryId: other.id),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'expense_category.system_kept',
          ),
        ),
      );

      // The rest are a convenience, and a business that does not use one can
      // put it away.
      final fuel = categories.firstWhere((c) => c.name == 'Fuel');
      expect(fuel.isSystem, isFalse);
      await fixture.expenses.archiveCategory(
        fixture.admin,
        categoryId: fuel.id,
      );
      expect(
        (await fixture.expenseQueries.watchCategories().first).map(
          (c) => c.name,
        ),
        isNot(contains('Fuel')),
      );
    });

    test(
      'a business can add its own, with a code derived from the name',
      () async {
        final id = await fixture.expenses.createCategory(
          fixture.admin,
          name: 'Shop Signage',
        );

        final added = (await fixture.expenseQueries.watchCategories().first)
            .firstWhere((c) => c.id == id);
        expect(added.name, 'Shop Signage');
        expect(added.code, 'SS');
        expect(added.isSystem, isFalse);
      },
    );

    test('refuses a duplicate name', () async {
      await fixture.expenses.createCategory(
        fixture.admin,
        name: 'Shop Signage',
      );

      await expectLater(
        fixture.expenses.createCategory(
          fixture.admin,
          name: '  shop signage  ',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'expense_category.unique_name',
          ),
        ),
      );
    });

    test('an archived category keeps its history readable', () async {
      final id = await fixture.expenses.createCategory(
        fixture.admin,
        name: 'One Off',
      );
      await postExpense(categoryId: id, amount: Money.fromMajor(400));
      await fixture.expenses.archiveCategory(fixture.admin, categoryId: id);

      final expense =
          (await fixture.expenseQueries
                  .watchExpenses(const ExpenseFilter())
                  .first)
              .single;
      expect(expense.categoryName, 'One Off');

      final archived =
          (await fixture.expenseQueries
                  .watchCategories(includeArchived: true)
                  .first)
              .firstWhere((c) => c.id == id);
      expect(archived.isArchived, isTrue);
      expect(archived.total, Money.fromMajor(400));
    });
  });

  group('the register', () {
    test('totals the period and breaks it down by category', () async {
      await postExpense(amount: Money.fromMajor(5000));
      await postExpense(
        amount: Money.fromMajor(3000),
        description: 'Fuel for the van',
      );
      await postExpense(
        categoryId: rentId,
        amount: Money.fromMajor(12000),
        description: 'Warehouse rent',
      );

      final totals = await fixture.expenseQueries.totals(const ExpenseFilter());

      expect(totals.count, 3);
      expect(totals.total, Money.fromMajor(20000));
      expect(totals.byCategory, hasLength(2));
      // Biggest first, so the breakdown reads as a ranking.
      expect(totals.byCategory.first.total, Money.fromMajor(12000));
      expect(totals.byCategory.first.count, 1);
      expect(totals.byCategory.last.total, Money.fromMajor(8000));
      expect(totals.byCategory.last.count, 2);
    });

    test('a cancelled voucher is listed but never counted', () async {
      final expenseId = await postExpense(amount: Money.fromMajor(5000));
      await postExpense(amount: Money.fromMajor(2000));
      await fixture.expenses.cancelExpense(
        fixture.admin,
        expenseId: expenseId,
        reason: 'Duplicate',
      );

      final totals = await fixture.expenseQueries.totals(const ExpenseFilter());
      expect(totals.count, 1);
      expect(totals.total, Money.fromMajor(2000));
      expect(totals.cancelledCount, 1);

      final rows = await fixture.expenseQueries
          .watchExpenses(const ExpenseFilter())
          .first;
      expect(rows, hasLength(2));
    });

    test('narrows by category, method and the petty cash flag', () async {
      await openFloat();
      await postExpense(amount: Money.fromMajor(5000));
      await postExpense(
        amount: Money.fromMajor(1000),
        fromPettyCash: true,
        description: 'Tea and sugar',
      );
      await postExpense(
        categoryId: rentId,
        amount: Money.fromMajor(12000),
        method: PaymentMethod.bankTransfer,
        description: 'Rent',
      );

      Future<int> count(ExpenseFilter filter) async =>
          (await fixture.expenseQueries.watchExpenses(filter).first).length;

      expect(await count(ExpenseFilter(categoryId: rentId)), 1);
      expect(
        await count(
          const ExpenseFilter(paymentMethod: PaymentMethod.bankTransfer),
        ),
        1,
      );
      expect(await count(const ExpenseFilter(pettyCashOnly: true)), 1);
      expect(await count(const ExpenseFilter(search: 'tea')), 1);
      expect(await count(const ExpenseFilter()), 3);
    });

    test('groups spend by day', () async {
      await postExpense(amount: Money.fromMajor(5000));
      await postExpense(amount: Money.fromMajor(2000));

      final daily = await fixture.expenseQueries.dailyTotals();
      expect(daily, hasLength(1));
      expect(daily.single.total, Money.fromMajor(7000));
      expect(daily.single.count, 2);
    });
  });

  group('the petty cash float', () {
    test('opens once and tops up thereafter', () async {
      await openFloat(Money.fromMajor(10000));

      await expectLater(
        openFloat(Money.fromMajor(5000)),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'petty_cash.one_opening_entry',
          ),
        ),
      );

      await fixture.pettyCash.recordEntry(
        fixture.admin,
        PettyCashDraft(
          kind: PettyCashEntryKind.cashReceived,
          amount: Money.fromMajor(5000),
          description: 'Top-up',
        ),
      );
      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(15000));
      await expectJournalSound();
    });

    test('moving cash in and out is a transfer, not a cost', () async {
      await openFloat(Money.fromMajor(10000));
      await fixture.pettyCash.recordEntry(
        fixture.admin,
        PettyCashDraft(
          kind: PettyCashEntryKind.cashIssued,
          amount: Money.fromMajor(4000),
          description: 'Returned to the cash box',
        ),
      );

      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(6000));
      expect(await account(AccountCodes.pettyCash), Money.fromMajor(6000));
      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(-6000));
      // Nothing was earned or spent by moving the business's own cash about.
      final report = await fixture.finance.profitAndLoss();
      expect(report.expenses, Money.zero);
      await expectJournalSound();
    });

    test('a shortage found when counting is a loss', () async {
      await openFloat(Money.fromMajor(10000));

      await fixture.pettyCash.recordEntry(
        fixture.admin,
        PettyCashDraft(
          kind: PettyCashEntryKind.adjustment,
          amount: Money.fromMajor(250),
          description: 'Counted short at the end of the week',
        ),
      );

      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(9750));
      expect(
        await account(AccountCodes.operatingExpenses),
        Money.fromMajor(250),
      );
      await expectJournalSound();
    });

    test('cash counted over is a gain', () async {
      await openFloat(Money.fromMajor(10000));

      await fixture.pettyCash.recordEntry(
        fixture.admin,
        PettyCashDraft(
          kind: PettyCashEntryKind.adjustment,
          amount: Money.fromMajor(100),
          description: 'Counted over',
          adjustmentAddsToFloat: true,
        ),
      );

      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(10100));
      expect(
        await account(AccountCodes.operatingExpenses),
        Money.fromMajor(-100),
      );
      await expectJournalSound();
    });

    test('will not go below what is in the box', () async {
      await openFloat(Money.fromMajor(1000));

      await expectLater(
        fixture.pettyCash.recordEntry(
          fixture.admin,
          PettyCashDraft(
            kind: PettyCashEntryKind.cashIssued,
            amount: Money.fromMajor(1500),
            description: 'More than there is',
          ),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'petty_cash.no_negative_float',
          ),
        ),
      );
      expect(await fixture.pettyCash.floatBalance(), Money.fromMajor(1000));
    });

    test('each row carries the balance as it stood, and they replay', () async {
      await openFloat(Money.fromMajor(10000));
      await postExpense(amount: Money.fromMajor(1500), fromPettyCash: true);
      await fixture.pettyCash.recordEntry(
        fixture.admin,
        PettyCashDraft(
          kind: PettyCashEntryKind.cashReceived,
          amount: Money.fromMajor(2000),
          description: 'Top-up',
        ),
      );

      final rows = await (fixture.db.select(
        fixture.db.pettyCashEntries,
      )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
      expect(rows.map((row) => row.balanceAfterCents), [
        1000000,
        850000,
        1050000,
      ]);

      // The caches agree with a replay of the book, which is the only thing
      // that makes a one-row balance read trustworthy.
      expect(await fixture.pettyCash.findBalanceDiscrepancies(), isEmpty);
      expect(await fixture.pettyCash.recomputeBalances(fixture.admin), 0);
    });

    test('reports the movement over the period and the float now', () async {
      await openFloat(Money.fromMajor(10000));
      await postExpense(amount: Money.fromMajor(1500), fromPettyCash: true);

      final snapshot = await fixture.pettyCash.snapshot(
        const PettyCashFilter(),
      );

      expect(snapshot.balance, Money.fromMajor(8500));
      expect(snapshot.entryCount, 2);
      expect(snapshot.receivedInPeriod, Money.fromMajor(10000));
      expect(snapshot.spentInPeriod, Money.fromMajor(1500));
      expect(snapshot.netInPeriod, Money.fromMajor(8500));
      expect(snapshot.lastEntryAt, isNotNull);
    });

    test('needs the petty cash permission', () async {
      final viewer = await fixture.createViewer();

      await expectLater(
        fixture.pettyCash.recordEntry(
          viewer,
          PettyCashDraft(
            kind: PettyCashEntryKind.opening,
            amount: Money.fromMajor(1000),
            description: 'Float',
          ),
        ),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });
}
