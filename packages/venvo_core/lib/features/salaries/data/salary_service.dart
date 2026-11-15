import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/sequence_service.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../../finance/data/financial_ledger_service.dart';
import '../domain/salary_models.dart';

/// Monthly salaries, advances and their recovery.
///
/// A salary goes through three states on purpose:
///
/// * **Draft** - computed and checkable, but owing nothing. Nothing is posted.
/// * **Approved** - the wage becomes an expense and a debt to the employee.
///   This is where an advance is recovered: by deduction, not by the employee
///   handing cash back.
/// * **Paid**, in one go or in parts.
///
/// An advance is an asset while it is outstanding - the employee owes it back -
/// so paying one is not a wage expense and recovering it is not a second one.
/// Getting that wrong would show the same money as a cost twice, which is the
/// classic way a payroll overstates its expenses.
class SalaryService {
  const SalaryService({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    required SequenceService sequences,
    required FinancialLedgerService finance,
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _sequences = sequences,
       _finance = finance;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final SequenceService _sequences;
  final FinancialLedgerService _finance;

  // --- Advances -----------------------------------------------------------

  /// Records an advance paid to an employee.
  Future<int> recordAdvance(
    AuthenticatedUser actor, {
    required int employeeId,
    required Money amount,
    PaymentMethod method = PaymentMethod.cash,
    DateTime? advanceDate,
    String? notes,
  }) async {
    actor.require(
      Permissions.salaryManage,
      action: 'give an employee an advance',
    );
    require(
      amount.isPositive,
      'An advance must be more than zero.',
      field: 'amount',
    );

    return _db.transaction(() async {
      final employee = await _requireEmployee(employeeId);
      requireRule(
        employee.status == EntityStatus.active,
        '${employee.name} is not an active employee.',
        rule: 'salary.advance_active_employees_only',
      );

      final when = advanceDate ?? _clock.nowUtc();
      final advanceId = await _db
          .into(_db.employeeAdvances)
          .insert(
            EmployeeAdvancesCompanion.insert(
              employeeId: employeeId,
              advanceDate: when,
              amountCents: amount.cents,
              paymentMethod: method,
              notes: Value(_clean(notes)),
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
            ),
          );

      // An asset, not an expense: the employee owes it back.
      await _finance.postEmployeeAdvance(
        actor: actor,
        advanceId: advanceId,
        advanceDate: when,
        amount: amount,
        method: method,
        employeeName: employee.name,
      );

      await _audit.record(
        action: AuditAction.create,
        summary:
            'Advance of ${amount.formatted()} to ${employee.name}, '
            'recoverable from later salaries.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.employeeAdvance,
        entityId: advanceId,
        after: {
          'employee': employee.name,
          'amountCents': amount.cents,
          'method': method.name,
        },
      );

      return advanceId;
    });
  }

  /// What an employee still owes in advances.
  Future<Money> outstandingAdvances(int employeeId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(amount_cents - recovered_cents), 0) AS owed '
          'FROM employee_advances WHERE employee_id = ?',
          variables: [Variable<int>(employeeId)],
          readsFrom: {_db.employeeAdvances},
        )
        .getSingle();
    return Money(row.read<int>('owed'));
  }

  // --- Salaries -----------------------------------------------------------

  /// What a salary would come to, without writing anything.
  ///
  /// The form calls this as the figures are typed and [createSalary] calls it
  /// again when it posts, so what was shown is what gets recorded.
  Future<SalaryComputation> compute(SalaryDraft draft) async {
    final earned = draft.earned;
    final owed = await outstandingAdvances(draft.employeeId);

    var recovery = Money.zero;
    if (draft.recoverAdvances && owed.isPositive && earned.isPositive) {
      // Never more than the employee owes, never more than this salary can
      // stand - a salary cannot go negative - and never more than the cap.
      recovery = owed < earned ? owed : earned;
      final cap = draft.advanceRecoveryCap;
      if (cap != null && cap < recovery) recovery = cap;
    }

    return SalaryComputation(
      earned: earned,
      outstandingAdvances: owed,
      advanceRecovered: recovery,
      net: earned - recovery,
    );
  }

  /// Computes and stores a salary as a draft. Nothing is posted yet.
  Future<int> createSalary(AuthenticatedUser actor, SalaryDraft draft) async {
    actor.require(Permissions.salaryManage, action: 'compute salaries');
    require(
      draft.periodMonth >= 1 && draft.periodMonth <= 12,
      'The month must be between 1 and 12.',
      field: 'periodMonth',
    );
    require(
      draft.periodYear >= 2000 && draft.periodYear <= 2200,
      'That year does not look right.',
      field: 'periodYear',
    );
    require(
      !draft.basicSalary.isNegative &&
          !draft.allowances.isNegative &&
          !draft.bonus.isNegative &&
          !draft.deductions.isNegative,
      'Salary figures cannot be negative.',
      field: 'amount',
    );

    return _db.transaction(() async {
      final employee = await _requireEmployee(draft.employeeId);

      final existing =
          await (_db.select(_db.salaries)..where(
                (s) =>
                    s.employeeId.equals(draft.employeeId) &
                    s.periodYear.equals(draft.periodYear) &
                    s.periodMonth.equals(draft.periodMonth),
              ))
              .getSingleOrNull();
      requireRule(
        existing == null,
        '${employee.name} already has a salary for '
        '${salaryMonthName(draft.periodMonth)} ${draft.periodYear} '
        '(${existing?.voucherNumber}). Cancel it before computing another.',
        rule: 'salary.one_per_employee_per_month',
      );

      final computed = await compute(draft);
      requireRule(
        !computed.net.isNegative,
        'The deductions come to more than the pay, which would make the net '
        'salary negative.',
        rule: 'salary.net_not_negative',
      );

      final voucherNumber = await _sequences.nextNumber(
        SequenceKeys.salaryVoucher,
        prefixOverride: SequenceKeys.salaryVoucher,
      );

      final salaryId = await _db
          .into(_db.salaries)
          .insert(
            SalariesCompanion.insert(
              voucherNumber: voucherNumber,
              employeeId: draft.employeeId,
              periodYear: draft.periodYear,
              periodMonth: draft.periodMonth,
              basicSalaryCents: Value(draft.basicSalary.cents),
              allowancesCents: Value(draft.allowances.cents),
              bonusCents: Value(draft.bonus.cents),
              deductionsCents: Value(draft.deductions.cents),
              advanceDeductedCents: Value(computed.advanceRecovered.cents),
              netSalaryCents: Value(computed.net.cents),
              status: const Value(SalaryStatus.draft),
              notes: Value(_clean(draft.notes)),
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
            ),
          );

      await _audit.record(
        action: AuditAction.create,
        summary:
            'Computed salary $voucherNumber for ${employee.name}, '
            '${salaryMonthName(draft.periodMonth)} ${draft.periodYear}: '
            'net ${computed.net.formatted()}'
            '${computed.recoversAnything ? ' after recovering '
                      '${computed.advanceRecovered.formatted()} of advances' : ''}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.salary,
        entityId: salaryId,
        after: {
          'voucherNumber': voucherNumber,
          'employee': employee.name,
          'earnedCents': computed.earned.cents,
          'advanceRecoveredCents': computed.advanceRecovered.cents,
          'netSalaryCents': computed.net.cents,
        },
      );

      return salaryId;
    });
  }

  /// Approves a salary: the wage becomes an expense and a debt, and the
  /// advance it recovers is settled against the oldest advances first.
  Future<void> approveSalary(
    AuthenticatedUser actor, {
    required int salaryId,
  }) async {
    actor.require(Permissions.salaryManage, action: 'approve salaries');

    await _db.transaction(() async {
      final salary = await _requireSalary(salaryId);
      requireRule(
        salary.status == SalaryStatus.draft,
        salary.status == SalaryStatus.cancelled
            ? 'That salary has been cancelled.'
            : 'That salary has already been approved.',
        rule: 'salary.approve_draft_only',
      );

      final employee = await _requireEmployee(salary.employeeId);
      final recovery = Money(salary.advanceDeductedCents);

      // Recompute against what is owed *now*: an advance may have been
      // recovered by another salary since this draft was made, and deducting
      // it twice would take money the employee no longer owes.
      final owedNow = await outstandingAdvances(salary.employeeId);
      requireRule(
        recovery <= owedNow,
        '${employee.name} now owes only ${owedNow.formatted()} in '
        'advances, but this salary deducts ${recovery.formatted()}. '
        'Recompute it.',
        rule: 'salary.advance_recovery_still_owed',
      );

      if (recovery.isPositive) {
        await _applyRecovery(salary.employeeId, recovery);
      }

      final now = _clock.nowUtc();
      await (_db.update(
        _db.salaries,
      )..where((s) => s.id.equals(salaryId))).write(
        SalariesCompanion(
          status: const Value(SalaryStatus.approved),
          approvedByUserId: Value(actor.id),
          approvedAt: Value(now),
        ),
      );

      await _finance.postSalaryApproved(
        actor: actor,
        salaryId: salaryId,
        voucherNumber: salary.voucherNumber,
        entryDate: now,
        earned: Money(
          salary.basicSalaryCents +
              salary.allowancesCents +
              salary.bonusCents -
              salary.deductionsCents,
        ),
        advanceRecovered: recovery,
        net: Money(salary.netSalaryCents),
      );

      await _audit.record(
        action: AuditAction.post,
        summary:
            'Approved salary ${salary.voucherNumber} for '
            '${employee.name}: '
            '${Money(salary.netSalaryCents).formatted()} now payable'
            '${recovery.isZero ? '' : ', ${recovery.formatted()} of advances '
                      'recovered'}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.salary,
        entityId: salaryId,
        before: {'status': SalaryStatus.draft.name},
        after: {
          'status': SalaryStatus.approved.name,
          'netSalaryCents': salary.netSalaryCents,
        },
      );
    });
  }

  /// Pays a salary, or part of one.
  Future<int> paySalary(
    AuthenticatedUser actor, {
    required int salaryId,
    Money? amount,
    PaymentMethod method = PaymentMethod.cash,
    DateTime? paymentDate,
    String? referenceNumber,
    String? notes,
  }) async {
    actor.require(Permissions.salaryManage, action: 'pay salaries');

    return _db.transaction(() async {
      final salary = await _requireSalary(salaryId);
      requireRule(
        salary.status == SalaryStatus.approved ||
            salary.status == SalaryStatus.partiallyPaid,
        salary.status == SalaryStatus.draft
            ? 'Approve the salary before paying it.'
            : salary.status == SalaryStatus.paid
            ? 'That salary has already been paid in full.'
            : 'That salary has been cancelled.',
        rule: 'salary.pay_approved_only',
      );

      final outstanding =
          Money(salary.netSalaryCents) - Money(salary.paidCents);
      final paying = amount ?? outstanding;
      require(
        paying.isPositive,
        'A salary payment must be more than zero.',
        field: 'amount',
      );
      requireRule(
        paying <= outstanding,
        '${outstanding.formatted()} is outstanding on '
        '${salary.voucherNumber}, but ${paying.formatted()} was entered.',
        rule: 'salary.no_overpayment',
      );

      final when = paymentDate ?? _clock.nowUtc();
      final paymentId = await _db
          .into(_db.salaryPayments)
          .insert(
            SalaryPaymentsCompanion.insert(
              salaryId: salaryId,
              paymentDate: when,
              amountCents: paying.cents,
              method: method,
              referenceNumber: Value(_clean(referenceNumber)),
              notes: Value(_clean(notes)),
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
            ),
          );

      final paid = Money(salary.paidCents) + paying;
      await (_db.update(
        _db.salaries,
      )..where((s) => s.id.equals(salaryId))).write(
        SalariesCompanion(
          paidCents: Value(paid.cents),
          status: Value(
            paid.cents >= salary.netSalaryCents
                ? SalaryStatus.paid
                : SalaryStatus.partiallyPaid,
          ),
        ),
      );

      await _finance.postSalaryPaid(
        actor: actor,
        salaryId: salaryId,
        voucherNumber: salary.voucherNumber,
        paymentDate: when,
        amount: paying,
        method: method,
      );

      final employee = await _requireEmployee(salary.employeeId);
      await _audit.record(
        action: AuditAction.update,
        summary:
            'Paid ${paying.formatted()} of salary '
            '${salary.voucherNumber} to ${employee.name}'
            '${paid.cents >= salary.netSalaryCents ? ' (settled in full)' : ', '
                      '${(Money(salary.netSalaryCents) - paid).formatted()} '
                      'still owed'}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.salaryPayment,
        entityId: paymentId,
        after: {
          'salaryVoucher': salary.voucherNumber,
          'amountCents': paying.cents,
          'method': method.name,
        },
      );

      return paymentId;
    });
  }

  /// Cancels a salary that has not been paid.
  ///
  /// Any advance it recovered goes back to being outstanding, because the
  /// deduction that settled it is being undone.
  Future<void> cancelSalary(
    AuthenticatedUser actor, {
    required int salaryId,
    required String reason,
  }) async {
    actor.require(Permissions.salaryManage, action: 'cancel salaries');
    final cleanReason = requireText(reason, 'Reason', maxLength: 500);

    await _db.transaction(() async {
      final salary = await _requireSalary(salaryId);
      requireRule(
        salary.status != SalaryStatus.cancelled,
        'That salary has already been cancelled.',
        rule: 'salary.cancel_once',
      );
      requireRule(
        salary.paidCents == 0,
        '${Money(salary.paidCents).formatted()} of '
        '${salary.voucherNumber} has already been paid, so it cannot be '
        'cancelled.',
        rule: 'salary.cancel_requires_no_payment',
      );

      if (salary.status != SalaryStatus.draft) {
        // Put the recovered advance back, oldest first, and mirror the
        // accounting the approval posted.
        if (salary.advanceDeductedCents > 0) {
          await _unapplyRecovery(
            salary.employeeId,
            Money(salary.advanceDeductedCents),
          );
        }
        for (final batchId in {
          for (final row in await _finance.entriesForSource(
            sourceKind: EntityKind.salary,
            sourceId: salaryId,
          ))
            if (!row.isReversal) row.batchId,
        }) {
          await _finance.reverse(
            actor: actor,
            batchId: batchId,
            reason: 'Salary ${salary.voucherNumber} cancelled',
          );
        }
      }

      await (_db.update(
        _db.salaries,
      )..where((s) => s.id.equals(salaryId))).write(
        SalariesCompanion(
          status: const Value(SalaryStatus.cancelled),
          cancelledAt: Value(_clock.nowUtc()),
        ),
      );

      await _audit.record(
        action: AuditAction.cancel,
        summary:
            'Cancelled salary ${salary.voucherNumber} '
            '(${Money(salary.netSalaryCents).formatted()}): $cleanReason',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.salary,
        entityId: salaryId,
        before: {'status': salary.status.name},
        after: {'status': SalaryStatus.cancelled.name},
      );
    });
  }

  // --- Internals ----------------------------------------------------------

  /// Settles [amount] against the employee's advances, oldest first.
  ///
  /// Oldest first because that is what both sides expect: the advance taken
  /// out in January is the one cleared in February.
  Future<void> _applyRecovery(int employeeId, Money amount) async {
    var left = amount;
    final advances =
        await (_db.select(_db.employeeAdvances)
              ..where((a) => a.employeeId.equals(employeeId))
              ..orderBy([
                (a) => OrderingTerm.asc(a.advanceDate),
                (a) => OrderingTerm.asc(a.id),
              ]))
            .get();

    for (final advance in advances) {
      if (!left.isPositive) break;
      final owed = Money(advance.amountCents - advance.recoveredCents);
      if (!owed.isPositive) continue;

      final take = owed < left ? owed : left;
      await (_db.update(
        _db.employeeAdvances,
      )..where((a) => a.id.equals(advance.id))).write(
        EmployeeAdvancesCompanion(
          recoveredCents: Value(advance.recoveredCents + take.cents),
        ),
      );
      left -= take;
    }

    requireRule(
      !left.isPositive,
      'Only ${(amount - left).formatted()} of advances could be recovered.',
      rule: 'salary.advance_recovery_exceeds_outstanding',
    );
  }

  /// Puts a recovery back, newest first - the mirror of [_applyRecovery].
  Future<void> _unapplyRecovery(int employeeId, Money amount) async {
    var left = amount;
    final advances =
        await (_db.select(_db.employeeAdvances)
              ..where((a) => a.employeeId.equals(employeeId))
              ..orderBy([
                (a) => OrderingTerm.desc(a.advanceDate),
                (a) => OrderingTerm.desc(a.id),
              ]))
            .get();

    for (final advance in advances) {
      if (!left.isPositive) break;
      final recovered = Money(advance.recoveredCents);
      if (!recovered.isPositive) continue;

      final give = recovered < left ? recovered : left;
      await (_db.update(
        _db.employeeAdvances,
      )..where((a) => a.id.equals(advance.id))).write(
        EmployeeAdvancesCompanion(
          recoveredCents: Value(advance.recoveredCents - give.cents),
        ),
      );
      left -= give;
    }
  }

  Future<Employee> _requireEmployee(int employeeId) async {
    return requireFound(
      await (_db.select(
        _db.employees,
      )..where((e) => e.id.equals(employeeId))).getSingleOrNull(),
      'That employee no longer exists.',
    );
  }

  Future<Salary> _requireSalary(int salaryId) async {
    return requireFound(
      await (_db.select(
        _db.salaries,
      )..where((s) => s.id.equals(salaryId))).getSingleOrNull(),
      'That salary no longer exists.',
    );
  }

  static String? _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
