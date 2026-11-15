import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/employees/domain/employee_models.dart';
import 'package:venvo_core/features/salaries/domain/salary_models.dart';

import '../helpers/master_data_fixtures.dart';

/// Salaries, advances and their recovery.
///
/// The arithmetic that has to be right: an advance is money the employee owes
/// back, so paying one is not a wage cost and recovering it is not a second
/// one. If that is wrong, the payroll shows the same money as an expense
/// twice - which is the usual way a wage bill ends up overstated.
void main() {
  late MasterDataFixture fixture;
  late int kamalId;
  late int sunilId;

  setUp(() async {
    fixture = await MasterDataFixture.create();

    kamalId = await fixture.employees.create(
      fixture.admin,
      EmployeeDraft(
        name: 'Kamal Fernando',
        designation: 'Driver',
        basicSalary: Money.fromMajor(45000),
      ),
    );
    sunilId = await fixture.employees.create(
      fixture.admin,
      EmployeeDraft(
        name: 'Sunil Silva',
        designation: 'Store keeper',
        basicSalary: Money.fromMajor(60000),
      ),
    );
  });

  tearDown(() => fixture.dispose());

  Future<Money> account(String code) => fixture.finance.balanceOf(code);

  Future<void> expectJournalSound() async {
    expect(await fixture.finance.findUnbalancedBatches(), isEmpty);
    final balance = await fixture.finance.trialBalance();
    expect(balance.totalDebits, balance.totalCredits);
  }

  Future<int> createSalary({
    int? employeeId,
    Money basic = const Money(4500000),
    Money allowances = Money.zero,
    Money bonus = Money.zero,
    Money deductions = Money.zero,
    bool recoverAdvances = true,
    Money? cap,
    int month = 11,
    int year = 2026,
  }) {
    return fixture.salaries.createSalary(
      fixture.admin,
      SalaryDraft(
        employeeId: employeeId ?? kamalId,
        periodYear: year,
        periodMonth: month,
        basicSalary: basic,
        allowances: allowances,
        bonus: bonus,
        deductions: deductions,
        recoverAdvances: recoverAdvances,
        advanceRecoveryCap: cap,
      ),
    );
  }

  Future<SalarySummary> salaryOf(int salaryId) async {
    return (await fixture.salaryQueries.salaryDetail(salaryId)).summary;
  }

  group('advances', () {
    test('are an asset, not a wage cost', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(10000),
      );

      expect(
        await account(AccountCodes.receivableEmployees),
        Money.fromMajor(10000),
      );
      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(-10000));
      // The point: giving an advance has not cost the business anything yet.
      expect(await account(AccountCodes.salaryExpense), Money.zero);
      final report = await fixture.finance.profitAndLoss();
      expect(report.salaryExpense, Money.zero);
      await expectJournalSound();
    });

    test('show up as outstanding against the employee', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(10000),
      );
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(5000),
      );

      expect(
        await fixture.salaries.outstandingAdvances(kamalId),
        Money.fromMajor(15000),
      );
      expect(await fixture.salaries.outstandingAdvances(sunilId), Money.zero);

      // And on the employee record, which reads the same table.
      final employees = await fixture.employees
          .watchEmployees(const EmployeeFilter())
          .first;
      final kamal = employees.firstWhere((e) => e.id == kamalId);
      expect(kamal.outstandingAdvances, Money.fromMajor(15000));
      expect(kamal.hasOpenBalances, isTrue);
    });

    test('are refused for an employee who has left', () async {
      await fixture.employees.archive(fixture.admin, sunilId);

      await expectLater(
        fixture.salaries.recordAdvance(
          fixture.admin,
          employeeId: sunilId,
          amount: Money.fromMajor(1000),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'salary.advance_active_employees_only',
          ),
        ),
      );
    });

    test('need the salary permission', () async {
      final viewer = await fixture.createViewer();

      await expectLater(
        fixture.salaries.recordAdvance(
          viewer,
          employeeId: kamalId,
          amount: Money.fromMajor(1000),
        ),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('are listed oldest first, with what is left on each', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(10000),
        notes: 'For the festival',
      );

      final rows = await fixture.salaryQueries
          .watchAdvances(employeeId: kamalId)
          .first;
      expect(rows, hasLength(1));
      expect(rows.single.amount, Money.fromMajor(10000));
      expect(rows.single.recovered, Money.zero);
      expect(rows.single.outstanding, Money.fromMajor(10000));
      expect(rows.single.isSettled, isFalse);
      expect(rows.single.notes, 'For the festival');
      expect(rows.single.employeeName, 'Kamal Fernando');
    });
  });

  group('computing a salary', () {
    test('adds up the pay and takes the advance out of it', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(10000),
      );

      final computed = await fixture.salaries.compute(
        SalaryDraft(
          employeeId: kamalId,
          periodYear: 2026,
          periodMonth: 11,
          basicSalary: Money.fromMajor(45000),
          allowances: Money.fromMajor(5000),
          bonus: Money.fromMajor(2000),
          deductions: Money.fromMajor(1000),
        ),
      );

      // 45,000 + 5,000 + 2,000 - 1,000 = 51,000 earned.
      expect(computed.earned, Money.fromMajor(51000));
      expect(computed.outstandingAdvances, Money.fromMajor(10000));
      expect(computed.advanceRecovered, Money.fromMajor(10000));
      expect(computed.net, Money.fromMajor(41000));
      expect(computed.advancesRemaining, Money.zero);
      expect(computed.isPartialRecovery, isFalse);
    });

    test('never recovers more than the salary can stand', () async {
      // The advance is bigger than a month's pay.
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(60000),
      );

      final computed = await fixture.salaries.compute(
        SalaryDraft(
          employeeId: kamalId,
          periodYear: 2026,
          periodMonth: 11,
          basicSalary: Money.fromMajor(45000),
        ),
      );

      // The whole salary goes to the advance, and the employee takes home
      // nothing - but never a negative amount.
      expect(computed.advanceRecovered, Money.fromMajor(45000));
      expect(computed.net, Money.zero);
      expect(computed.advancesRemaining, Money.fromMajor(15000));
      expect(computed.isPartialRecovery, isTrue);
    });

    test('honours a cap, so an advance can be paid back over months', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(30000),
      );

      final computed = await fixture.salaries.compute(
        SalaryDraft(
          employeeId: kamalId,
          periodYear: 2026,
          periodMonth: 11,
          basicSalary: Money.fromMajor(45000),
          advanceRecoveryCap: Money.fromMajor(10000),
        ),
      );

      expect(computed.advanceRecovered, Money.fromMajor(10000));
      expect(computed.net, Money.fromMajor(35000));
      expect(computed.advancesRemaining, Money.fromMajor(20000));
    });

    test('can be told to leave the advance alone', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(10000),
      );

      final computed = await fixture.salaries.compute(
        SalaryDraft(
          employeeId: kamalId,
          periodYear: 2026,
          periodMonth: 11,
          basicSalary: Money.fromMajor(45000),
          recoverAdvances: false,
        ),
      );

      expect(computed.advanceRecovered, Money.zero);
      expect(computed.net, Money.fromMajor(45000));
    });

    test('stores a draft that owes nothing yet', () async {
      final salaryId = await createSalary();
      final salary = await salaryOf(salaryId);

      expect(salary.voucherNumber, startsWith('SAL-'));
      expect(salary.isDraft, isTrue);
      expect(salary.netSalary, Money.fromMajor(45000));
      expect(salary.periodLabel, 'November 2026');

      // A draft is not a liability, so nothing is posted.
      expect(await account(AccountCodes.salaryExpense), Money.zero);
      expect(await account(AccountCodes.salariesPayable), Money.zero);

      final totals = await fixture.salaryQueries.totals(const SalaryFilter());
      expect(totals.count, 0);
      expect(totals.draftCount, 1);
      expect(totals.net, Money.zero);
    });

    test('refuses a second salary for the same employee and month', () async {
      await createSalary();

      await expectLater(
        createSalary(),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'salary.one_per_employee_per_month',
          ),
        ),
      );

      // Another month, or another employee, is fine.
      await createSalary(month: 12);
      await createSalary(employeeId: sunilId, basic: Money.fromMajor(60000));
    });

    test('refuses deductions larger than the pay', () async {
      await expectLater(
        createSalary(
          basic: Money.fromMajor(45000),
          deductions: Money.fromMajor(50000),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'salary.net_not_negative',
          ),
        ),
      );
    });

    test('refuses a month outside 1 to 12 and a negative figure', () async {
      await expectLater(
        createSalary(month: 13),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        createSalary(basic: Money.fromMajor(-100)),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('approving a salary', () {
    test('makes the wage an expense and a debt to the employee', () async {
      final salaryId = await createSalary(
        basic: Money.fromMajor(45000),
        allowances: Money.fromMajor(5000),
      );

      await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);

      final salary = await salaryOf(salaryId);
      expect(salary.isApproved, isTrue);
      expect(salary.approvedBy, 'Nimal Perera');
      expect(salary.outstanding, Money.fromMajor(50000));

      expect(await account(AccountCodes.salaryExpense), Money.fromMajor(50000));
      expect(
        await account(AccountCodes.salariesPayable),
        Money.fromMajor(-50000),
      );
      // Nothing has been handed over yet, so no cash has moved.
      expect(await account(AccountCodes.cashOnHand), Money.zero);
      await expectJournalSound();
    });

    test('settles the advance by deduction, counting the cost once', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(10000),
      );
      final salaryId = await createSalary(basic: Money.fromMajor(45000));

      await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);

      // The wage cost is the whole 45,000 - the advance was part of it all
      // along, just paid early.
      expect(await account(AccountCodes.salaryExpense), Money.fromMajor(45000));
      // Only 35,000 is still owed to the employee.
      expect(
        await account(AccountCodes.salariesPayable),
        Money.fromMajor(-35000),
      );
      // And the advance has been cleared, so it is no longer an asset.
      expect(await account(AccountCodes.receivableEmployees), Money.zero);
      expect(await fixture.salaries.outstandingAdvances(kamalId), Money.zero);
      await expectJournalSound();
    });

    test('clears advances oldest first', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(8000),
        advanceDate: DateTime.utc(2026, 9, 10),
      );
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(9000),
        advanceDate: DateTime.utc(2026, 10, 10),
      );

      // Only 10,000 of the 17,000 can come out of this salary.
      final salaryId = await createSalary(
        basic: Money.fromMajor(45000),
        cap: Money.fromMajor(10000),
      );
      await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);

      final advances = await fixture.salaryQueries
          .watchAdvances(employeeId: kamalId, outstandingOnly: false)
          .first;
      final september = advances.firstWhere(
        (row) => row.advanceDate.month == 9,
      );
      final october = advances.firstWhere((row) => row.advanceDate.month == 10);

      // September's is settled in full; October's takes the remainder.
      expect(september.recovered, Money.fromMajor(8000));
      expect(september.isSettled, isTrue);
      expect(october.recovered, Money.fromMajor(2000));
      expect(october.outstanding, Money.fromMajor(7000));
      await expectJournalSound();
    });

    test('refuses a stale deduction the employee no longer owes', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(10000),
      );
      // Two drafts, each planning to recover the same advance.
      final november = await createSalary(month: 11);
      final december = await createSalary(month: 12);

      await fixture.salaries.approveSalary(fixture.admin, salaryId: november);

      // The advance is gone, so the second draft's deduction is stale and
      // would take money the employee does not owe.
      await expectLater(
        fixture.salaries.approveSalary(fixture.admin, salaryId: december),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'salary.advance_recovery_still_owed',
          ),
        ),
      );
      await expectJournalSound();
    });

    test('cannot be done twice', () async {
      final salaryId = await createSalary();
      await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);

      await expectLater(
        fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'salary.approve_draft_only',
          ),
        ),
      );
    });
  });

  group('paying a salary', () {
    Future<int> approved({Money basic = const Money(4500000)}) async {
      final salaryId = await createSalary(basic: basic);
      await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);
      return salaryId;
    }

    test('settles the debt and moves the cash', () async {
      final salaryId = await approved();

      await fixture.salaries.paySalary(fixture.admin, salaryId: salaryId);

      final salary = await salaryOf(salaryId);
      expect(salary.isFullyPaid, isTrue);
      expect(salary.paid, Money.fromMajor(45000));
      expect(salary.outstanding, Money.zero);

      expect(await account(AccountCodes.salariesPayable), Money.zero);
      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(-45000));
      // The cost was recognised on approval, not again on payment.
      expect(await account(AccountCodes.salaryExpense), Money.fromMajor(45000));
      await expectJournalSound();
    });

    test('can be paid in parts, with the balance still owed', () async {
      final salaryId = await approved();

      await fixture.salaries.paySalary(
        fixture.admin,
        salaryId: salaryId,
        amount: Money.fromMajor(20000),
      );

      var salary = await salaryOf(salaryId);
      expect(salary.status, SalaryStatus.partiallyPaid);
      expect(salary.paid, Money.fromMajor(20000));
      expect(salary.outstanding, Money.fromMajor(25000));
      expect(salary.canBePaid, isTrue);
      expect(
        await account(AccountCodes.salariesPayable),
        Money.fromMajor(-25000),
      );

      await fixture.salaries.paySalary(
        fixture.admin,
        salaryId: salaryId,
        amount: Money.fromMajor(25000),
      );

      salary = await salaryOf(salaryId);
      expect(salary.isFullyPaid, isTrue);
      expect(salary.outstanding, Money.zero);
      expect(await account(AccountCodes.salariesPayable), Money.zero);

      final detail = await fixture.salaryQueries.salaryDetail(salaryId);
      expect(detail.payments, hasLength(2));
      await expectJournalSound();
    });

    test('refuses more than is outstanding', () async {
      final salaryId = await approved();

      await expectLater(
        fixture.salaries.paySalary(
          fixture.admin,
          salaryId: salaryId,
          amount: Money.fromMajor(50000),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'salary.no_overpayment',
          ),
        ),
      );
    });

    test('refuses to pay a salary nobody has approved', () async {
      final salaryId = await createSalary();

      await expectLater(
        fixture.salaries.paySalary(fixture.admin, salaryId: salaryId),
        throwsA(
          isA<BusinessRuleFailure>()
              .having(
                (failure) => failure.rule,
                'rule',
                'salary.pay_approved_only',
              )
              .having(
                (failure) => failure.message,
                'message',
                contains('Approve the salary'),
              ),
        ),
      );
    });

    test('a bank payment comes out of the bank', () async {
      final salaryId = await approved();

      await fixture.salaries.paySalary(
        fixture.admin,
        salaryId: salaryId,
        method: PaymentMethod.bankTransfer,
        referenceNumber: 'NEFT-9912',
      );

      expect(await account(AccountCodes.bank), Money.fromMajor(-45000));
      expect(await account(AccountCodes.cashOnHand), Money.zero);

      final detail = await fixture.salaryQueries.salaryDetail(salaryId);
      expect(detail.payments.single.method, PaymentMethod.bankTransfer);
      expect(detail.payments.single.referenceNumber, 'NEFT-9912');
    });
  });

  group('cancelling a salary', () {
    test('a draft simply goes away, having posted nothing', () async {
      final salaryId = await createSalary();

      await fixture.salaries.cancelSalary(
        fixture.admin,
        salaryId: salaryId,
        reason: 'Computed on the wrong employee',
      );

      final salary = await salaryOf(salaryId);
      expect(salary.isCancelled, isTrue);
      expect(await account(AccountCodes.salaryExpense), Money.zero);
      await expectJournalSound();
    });

    test('an approved one gives the advance back and unposts', () async {
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(10000),
      );
      final salaryId = await createSalary(basic: Money.fromMajor(45000));
      await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);
      expect(await fixture.salaries.outstandingAdvances(kamalId), Money.zero);

      await fixture.salaries.cancelSalary(
        fixture.admin,
        salaryId: salaryId,
        reason: 'Approved too early',
      );

      // The deduction that settled the advance is undone, so it is owed again.
      expect(
        await fixture.salaries.outstandingAdvances(kamalId),
        Money.fromMajor(10000),
      );
      expect(
        await account(AccountCodes.receivableEmployees),
        Money.fromMajor(10000),
      );
      expect(await account(AccountCodes.salaryExpense), Money.zero);
      expect(await account(AccountCodes.salariesPayable), Money.zero);
      await expectJournalSound();
    });

    test('is refused once any of it has been handed over', () async {
      final salaryId = await createSalary();
      await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);
      await fixture.salaries.paySalary(
        fixture.admin,
        salaryId: salaryId,
        amount: Money.fromMajor(1000),
      );

      await expectLater(
        fixture.salaries.cancelSalary(
          fixture.admin,
          salaryId: salaryId,
          reason: 'Changed our mind',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'salary.cancel_requires_no_payment',
          ),
        ),
      );
    });

    test('requires a reason', () async {
      final salaryId = await createSalary();

      await expectLater(
        fixture.salaries.cancelSalary(
          fixture.admin,
          salaryId: salaryId,
          reason: '  ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('the register', () {
    test('totals the month and keeps drafts out of the liability', () async {
      final first = await createSalary(employeeId: kamalId);
      await createSalary(employeeId: sunilId, basic: Money.fromMajor(60000));
      await fixture.salaries.approveSalary(fixture.admin, salaryId: first);
      await fixture.salaries.paySalary(
        fixture.admin,
        salaryId: first,
        amount: Money.fromMajor(20000),
      );

      final totals = await fixture.salaryQueries.totals(const SalaryFilter());

      // Only the approved one counts.
      expect(totals.count, 1);
      expect(totals.net, Money.fromMajor(45000));
      expect(totals.paid, Money.fromMajor(20000));
      expect(totals.outstanding, Money.fromMajor(25000));
      expect(totals.draftCount, 1);
    });

    test('narrows by employee, period, status and what is unpaid', () async {
      final kamalNovember = await createSalary(month: 11);
      await createSalary(month: 12);
      await createSalary(
        employeeId: sunilId,
        basic: Money.fromMajor(60000),
        month: 11,
      );
      await fixture.salaries.approveSalary(
        fixture.admin,
        salaryId: kamalNovember,
      );

      Future<int> count(SalaryFilter filter) async =>
          (await fixture.salaryQueries.watchSalaries(filter).first).length;

      expect(await count(const SalaryFilter()), 3);
      expect(await count(SalaryFilter(employeeId: kamalId)), 2);
      expect(await count(const SalaryFilter(periodMonth: 11)), 2);
      expect(await count(const SalaryFilter(status: SalaryStatus.draft)), 2);
      expect(await count(const SalaryFilter(unpaidOnly: true)), 1);
      expect(await count(const SalaryFilter(search: 'sunil')), 1);
    });

    test('lists the periods that have salaries, newest first', () async {
      await createSalary(month: 11);
      await createSalary(month: 12);
      await createSalary(employeeId: sunilId, month: 12);

      final periods = await fixture.salaryQueries.periods();

      expect(periods, hasLength(2));
      expect(periods.first.month, 12);
      expect(periods.first.count, 2);
      expect(periods.last.month, 11);
      expect(periods.last.count, 1);
    });

    test(
      'a slip shows the pay, the deduction and what is left owing',
      () async {
        await fixture.salaries.recordAdvance(
          fixture.admin,
          employeeId: kamalId,
          amount: Money.fromMajor(20000),
        );
        final salaryId = await createSalary(
          basic: Money.fromMajor(45000),
          allowances: Money.fromMajor(5000),
          bonus: Money.fromMajor(2000),
          deductions: Money.fromMajor(1000),
          cap: Money.fromMajor(10000),
        );
        await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);

        final detail = await fixture.salaryQueries.salaryDetail(salaryId);

        expect(detail.summary.basicSalary, Money.fromMajor(45000));
        expect(detail.summary.allowances, Money.fromMajor(5000));
        expect(detail.summary.bonus, Money.fromMajor(2000));
        expect(detail.summary.deductions, Money.fromMajor(1000));
        expect(detail.summary.earned, Money.fromMajor(51000));
        expect(detail.summary.advanceDeducted, Money.fromMajor(10000));
        expect(detail.summary.netSalary, Money.fromMajor(41000));
        expect(detail.summary.employeeName, 'Kamal Fernando');
        expect(detail.summary.designation, 'Driver');
        // Still owed after this month's deduction.
        expect(detail.outstandingAdvances, Money.fromMajor(10000));
      },
    );
  });

  group('the payroll in the accounts', () {
    test('a full month reads correctly end to end', () async {
      // An advance in October, recovered from November's pay.
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: kamalId,
        amount: Money.fromMajor(10000),
        advanceDate: DateTime.utc(2026, 10, 15),
      );

      final kamal = await createSalary(
        employeeId: kamalId,
        basic: Money.fromMajor(45000),
      );
      final sunil = await createSalary(
        employeeId: sunilId,
        basic: Money.fromMajor(60000),
      );
      await fixture.salaries.approveSalary(fixture.admin, salaryId: kamal);
      await fixture.salaries.approveSalary(fixture.admin, salaryId: sunil);
      await fixture.salaries.paySalary(fixture.admin, salaryId: kamal);
      await fixture.salaries.paySalary(
        fixture.admin,
        salaryId: sunil,
        amount: Money.fromMajor(40000),
      );

      final report = await fixture.finance.profitAndLoss();
      // The wage bill is the full 105,000 earned, counted once, whatever was
      // advanced or still unpaid.
      expect(report.salaryExpense, Money.fromMajor(105000));
      expect(report.netProfit, Money.fromMajor(-105000));

      // Cash out: Kamal's 35,000 net, Sunil's 40,000 part payment, and the
      // 10,000 advance back in October.
      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(-85000));
      // Sunil is still owed 20,000.
      expect(
        await account(AccountCodes.salariesPayable),
        Money.fromMajor(-20000),
      );
      expect(await account(AccountCodes.receivableEmployees), Money.zero);

      final totals = await fixture.salaryQueries.totals(const SalaryFilter());
      expect(totals.outstanding, Money.fromMajor(20000));
      // The accounts and the register agree on what is still owed.
      expect(
        totals.outstanding,
        -(await account(AccountCodes.salariesPayable)),
      );
      await expectJournalSound();
    });
  });
}
