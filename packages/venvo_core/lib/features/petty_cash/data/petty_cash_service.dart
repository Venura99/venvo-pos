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
import '../domain/petty_cash_models.dart';

/// The petty cash float and its book.
///
/// Each row carries the balance as it stood immediately after it, so the
/// closing float on any day is one row read rather than a replay of the whole
/// book. That cache is only ever written here, in the same transaction as the
/// entry itself, and [recomputeBalances] can rebuild every one of them from
/// the entries alone if they are ever doubted.
///
/// The float may not go below zero: you cannot take out of a cash box money
/// that is not in it. An entry that would is refused rather than recorded,
/// which is how a cash book stays worth reading.
///
/// Expenses settled out of the float are recorded as one entry here linked to
/// the expense, and the **expense** posts the accounting. Posting it on both
/// sides would count the same cash twice, which is why [appendEntry] takes
/// `postToJournal`.
class PettyCashService {
  const PettyCashService({
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

  /// Records a movement of the float.
  Future<int> recordEntry(AuthenticatedUser actor, PettyCashDraft draft) async {
    actor.require(
      Permissions.pettyCashManage,
      action: 'record petty cash movements',
    );

    return _db.transaction(() async {
      final entryId = await appendEntry(
        actor: actor,
        kind: draft.kind,
        amount: draft.amount,
        description: draft.description,
        addsToFloat: draft.addsToFloat,
        entryDate: draft.entryDate,
        referenceNumber: draft.referenceNumber,
        handledByEmployeeId: draft.handledByEmployeeId,
      );

      final balance = await floatBalance();
      await _audit.record(
        action: AuditAction.create,
        summary:
            '${pettyCashKindLabel(draft.kind)}: '
            '${draft.amount.formatted()} - ${draft.description}. '
            'Float now ${balance.formatted()}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.pettyCashEntry,
        entityId: entryId,
        after: {
          'kind': draft.kind.name,
          'amountCents': draft.amount.cents,
          'balanceAfterCents': balance.cents,
        },
      );

      return entryId;
    });
  }

  /// Writes one entry, maintaining the running balance.
  ///
  /// Public because the expenses module calls it inside its own transaction
  /// when an expense is settled from the float. [postToJournal] is false in
  /// that case: the expense posts the accounting, and doing it here as well
  /// would credit the float twice.
  ///
  /// Must be called inside a transaction.
  Future<int> appendEntry({
    required AuthenticatedUser actor,
    required PettyCashEntryKind kind,
    required Money amount,
    required String description,
    required bool addsToFloat,
    DateTime? entryDate,
    String? referenceNumber,
    int? handledByEmployeeId,
    int? expenseId,
    bool postToJournal = true,
  }) async {
    require(
      amount.isPositive,
      'A petty cash entry must be more than zero.',
      field: 'amount',
    );
    final cleanDescription = requireText(
      description,
      'Description',
      maxLength: 500,
    );

    final signed = addsToFloat ? amount : -amount;
    final previous = await floatBalance();
    final balanceAfter = previous + signed;

    requireRule(
      !balanceAfter.isNegative,
      'The float holds ${previous.formatted()}, so '
      '${amount.formatted()} cannot be taken out of it.',
      rule: 'petty_cash.no_negative_float',
    );

    if (kind == PettyCashEntryKind.opening) {
      final existing =
          await (_db.select(_db.pettyCashEntries)..where(
                (row) => row.kind.equalsValue(PettyCashEntryKind.opening),
              ))
              .get();
      requireRule(
        existing.isEmpty,
        'The opening float has already been recorded. Use "cash into float" '
        'to top it up.',
        rule: 'petty_cash.one_opening_entry',
      );
    }

    final when = entryDate ?? _clock.nowUtc();
    final voucherNumber = await _sequences.nextNumber(
      SequenceKeys.pettyCashVoucher,
      prefixOverride: SequenceKeys.pettyCashVoucher,
    );

    final entryId = await _db
        .into(_db.pettyCashEntries)
        .insert(
          PettyCashEntriesCompanion.insert(
            voucherNumber: voucherNumber,
            entryDate: when,
            kind: kind,
            amountCents: amount.cents,
            signedAmountCents: signed.cents,
            balanceAfterCents: balanceAfter.cents,
            description: cleanDescription,
            referenceNumber: Value(_clean(referenceNumber)),
            expenseId: Value(expenseId),
            handledByEmployeeId: Value(handledByEmployeeId),
            createdByUserId: actor.id,
            createdAt: _clock.nowUtc(),
          ),
        );

    if (postToJournal) {
      switch (kind) {
        case PettyCashEntryKind.opening:
        case PettyCashEntryKind.cashReceived:
        case PettyCashEntryKind.cashIssued:
          // Cash moving between the cash box and the float. Nothing is earned
          // or spent, so both sides are assets.
          await _finance.postPettyCashTransfer(
            actor: actor,
            entryId: entryId,
            voucherNumber: voucherNumber,
            entryDate: when,
            amount: amount,
            intoFloat: addsToFloat,
          );
        case PettyCashEntryKind.adjustment:
          // Cash counted short or over is a loss or a gain, not a movement.
          await _finance.postPettyCashAdjustment(
            actor: actor,
            entryId: entryId,
            voucherNumber: voucherNumber,
            entryDate: when,
            amount: amount,
            isIncrease: addsToFloat,
          );
        case PettyCashEntryKind.expense:
          // The expense posts its own accounting, which is what credits the
          // float. Nothing to do here.
          break;
      }
    }

    return entryId;
  }

  /// The float as it stands.
  ///
  /// Read from the entries rather than from the newest row's cache, so a
  /// back-dated entry cannot leave the figure stale.
  Future<Money> floatBalance({DateTime? asOf}) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(signed_amount_cents), 0) AS balance '
          'FROM petty_cash_entries '
          'WHERE (? IS NULL OR entry_date <= ?)',
          variables: [
            Variable<String>(_iso(asOf)),
            Variable<String>(_iso(asOf)),
          ],
          readsFrom: {_db.pettyCashEntries},
        )
        .getSingle();
    return Money(row.read<int>('balance'));
  }

  /// The book, newest first.
  Stream<List<PettyCashRow>> watchEntries(PettyCashFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT p.*, u.full_name AS created_by,
             e.name AS handled_by,
             x.voucher_number AS expense_voucher
      FROM petty_cash_entries p
      JOIN users u ON u.id = p.created_by_user_id
      LEFT JOIN employees e ON e.id = p.handled_by_employee_id
      LEFT JOIN expenses x ON x.id = p.expense_id
      WHERE 1 = 1
        AND (? IS NULL OR p.kind = ?)
        AND (? IS NULL OR p.entry_date >= ?)
        AND (? IS NULL OR p.entry_date <= ?)
        AND (? = '' OR LOWER(p.description) LIKE ?
             OR LOWER(p.voucher_number) LIKE ?
             OR LOWER(COALESCE(p.reference_number, '')) LIKE ?)
      ORDER BY p.entry_date DESC, p.id DESC
      LIMIT ?
      ''',
      variables: [
        Variable<String>(filter.kind?.name),
        Variable<String>(filter.kind?.name),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {_db.pettyCashEntries, _db.users, _db.employees, _db.expenses},
    );

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => PettyCashRow(
              id: row.read<int>('id'),
              voucherNumber: row.read<String>('voucher_number'),
              entryDate: row.read<DateTime>('entry_date'),
              kind: PettyCashEntryKind.values.byName(row.read<String>('kind')),
              amount: Money(row.read<int>('amount_cents')),
              signedAmount: Money(row.read<int>('signed_amount_cents')),
              balanceAfter: Money(row.read<int>('balance_after_cents')),
              description: row.read<String>('description'),
              createdBy: row.read<String>('created_by'),
              referenceNumber: row.readNullable<String>('reference_number'),
              expenseId: row.readNullable<int>('expense_id'),
              expenseVoucherNumber: row.readNullable<String>('expense_voucher'),
              handledByEmployeeName: row.readNullable<String>('handled_by'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The float plus the movement over the filtered period.
  Future<PettyCashSnapshot> snapshot(PettyCashFilter filter) async {
    final row = await _db
        .customSelect(
          '''
      SELECT
        COUNT(*) AS entry_count,
        COALESCE(SUM(CASE WHEN signed_amount_cents > 0
                     THEN signed_amount_cents ELSE 0 END), 0) AS received,
        COALESCE(SUM(CASE WHEN signed_amount_cents < 0
                     THEN -signed_amount_cents ELSE 0 END), 0) AS spent,
        MAX(entry_date) AS last_entry
      FROM petty_cash_entries
      WHERE (? IS NULL OR entry_date >= ?)
        AND (? IS NULL OR entry_date <= ?)
      ''',
          variables: [
            Variable<String>(_iso(filter.from)),
            Variable<String>(_iso(filter.from)),
            Variable<String>(_iso(filter.to)),
            Variable<String>(_iso(filter.to)),
          ],
          readsFrom: {_db.pettyCashEntries},
        )
        .getSingle();

    return PettyCashSnapshot(
      balance: await floatBalance(),
      entryCount: row.read<int>('entry_count'),
      receivedInPeriod: Money(row.read<int>('received')),
      spentInPeriod: Money(row.read<int>('spent')),
      lastEntryAt: row.readNullable<DateTime>('last_entry'),
    );
  }

  /// Rebuilds every running balance from the entries, in date order.
  ///
  /// The caches are written with each entry and should never need this. It
  /// exists so that a doubt about them can be settled rather than argued
  /// about, and [findBalanceDiscrepancies] is what a test uses to prove there
  /// is nothing to settle.
  Future<int> recomputeBalances(AuthenticatedUser actor) async {
    actor.require(
      Permissions.pettyCashManage,
      action: 'rebuild the petty cash balances',
    );

    return _db.transaction(() async {
      final entries =
          await (_db.select(_db.pettyCashEntries)..orderBy([
                (row) => OrderingTerm.asc(row.entryDate),
                (row) => OrderingTerm.asc(row.id),
              ]))
              .get();

      var running = Money.zero;
      var corrected = 0;
      for (final entry in entries) {
        running += Money(entry.signedAmountCents);
        if (entry.balanceAfterCents != running.cents) {
          await (_db.update(
            _db.pettyCashEntries,
          )..where((row) => row.id.equals(entry.id))).write(
            PettyCashEntriesCompanion(balanceAfterCents: Value(running.cents)),
          );
          corrected++;
        }
      }
      return corrected;
    });
  }

  /// Rows whose stored running balance disagrees with a replay of the book.
  Future<List<({String voucherNumber, Money stored, Money replayed})>>
  findBalanceDiscrepancies() async {
    final entries =
        await (_db.select(_db.pettyCashEntries)..orderBy([
              (row) => OrderingTerm.asc(row.entryDate),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();

    final problems = <({String voucherNumber, Money stored, Money replayed})>[];
    var running = Money.zero;
    for (final entry in entries) {
      running += Money(entry.signedAmountCents);
      if (entry.balanceAfterCents != running.cents) {
        problems.add((
          voucherNumber: entry.voucherNumber,
          stored: Money(entry.balanceAfterCents),
          replayed: running,
        ));
      }
    }
    return problems;
  }

  static String? _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();
}
