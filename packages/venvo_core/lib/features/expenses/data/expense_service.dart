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
import '../../petty_cash/data/petty_cash_service.dart';
import '../domain/expense_models.dart';

/// Daily expenses.
///
/// An expense is posted straight away - there is no draft to forget about -
/// and posting does three things in one transaction: the voucher, the
/// accounting, and, when the money came out of the petty cash float, the one
/// entry that reduces it.
///
/// The float is deliberately reduced by a *linked* petty cash entry rather
/// than by a second journal posting. That way the cash movement exists once,
/// the petty cash book shows what the money was spent on, and the expense
/// report and the float can never disagree about it.
class ExpenseService {
  const ExpenseService({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    required SequenceService sequences,
    required FinancialLedgerService finance,
    required PettyCashService pettyCash,
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _sequences = sequences,
       _finance = finance,
       _pettyCash = pettyCash;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final SequenceService _sequences;
  final FinancialLedgerService _finance;
  final PettyCashService _pettyCash;

  /// Records and posts an expense.
  Future<int> postExpense(AuthenticatedUser actor, ExpenseDraft draft) async {
    actor.require(Permissions.expenseManage, action: 'record expenses');
    require(
      draft.amount.isPositive,
      'An expense must be more than zero.',
      field: 'amount',
    );
    final description = requireText(
      draft.description,
      'Description',
      maxLength: 500,
    );
    if (draft.fromPettyCash) {
      requireRule(
        draft.paymentMethod == PaymentMethod.cash,
        'Money out of the petty cash float is cash. Choose cash as the '
        'method, or pay it from the bank instead.',
        rule: 'expense.petty_cash_is_cash',
      );
    }

    return _db.transaction(() async {
      final category = requireFound(
        await (_db.select(
          _db.expenseCategories,
        )..where((c) => c.id.equals(draft.categoryId))).getSingleOrNull(),
        'That expense category no longer exists.',
      );
      requireRule(
        category.status == EntityStatus.active,
        'The category "${category.name}" is archived, so nothing new can be '
        'booked against it.',
        rule: 'expense.category_must_be_active',
      );

      final when = draft.expenseDate ?? _clock.nowUtc();
      final voucherNumber = await _sequences.nextNumber(
        SequenceKeys.expenseVoucher,
        prefixOverride: SequenceKeys.expenseVoucher,
      );

      final expenseId = await _db
          .into(_db.expenses)
          .insert(
            ExpensesCompanion.insert(
              voucherNumber: voucherNumber,
              expenseDate: when,
              categoryId: category.id,
              description: description,
              amountCents: draft.amount.cents,
              paymentMethod: draft.paymentMethod,
              paidByEmployeeId: Value(draft.paidByEmployeeId),
              referenceNumber: Value(_clean(draft.referenceNumber)),
              status: const Value(InvoiceStatus.posted),
              notes: Value(_clean(draft.notes)),
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
              postedAt: Value(_clock.nowUtc()),
            ),
          );

      // The cash side, when it came out of the float. This also checks the
      // float can stand it, so an expense cannot drive petty cash negative.
      if (draft.fromPettyCash) {
        final entryId = await _pettyCash.appendEntry(
          actor: actor,
          kind: PettyCashEntryKind.expense,
          amount: draft.amount,
          description: '$voucherNumber: $description',
          addsToFloat: false,
          entryDate: when,
          referenceNumber: draft.referenceNumber,
          handledByEmployeeId: draft.paidByEmployeeId,
          expenseId: expenseId,
          // The expense posts the accounting for both sides.
          postToJournal: false,
        );
        await (_db.update(_db.expenses)..where((e) => e.id.equals(expenseId)))
            .write(ExpensesCompanion(pettyCashEntryId: Value(entryId)));
      }

      await _finance.postExpense(
        actor: actor,
        expenseId: expenseId,
        voucherNumber: voucherNumber,
        expenseDate: when,
        amount: draft.amount,
        method: draft.paymentMethod,
        expenseAccountCode: await _accountCodeFor(category),
        fromPettyCash: draft.fromPettyCash,
      );

      await _audit.record(
        action: AuditAction.post,
        summary:
            'Expense $voucherNumber: ${draft.amount.formatted()} on '
            '${category.name} - $description'
            '${draft.fromPettyCash ? ' (from petty cash)' : ''}',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.expense,
        entityId: expenseId,
        after: {
          'voucherNumber': voucherNumber,
          'category': category.name,
          'amountCents': draft.amount.cents,
          'method': draft.paymentMethod.name,
          'fromPettyCash': draft.fromPettyCash,
        },
      );

      return expenseId;
    });
  }

  /// Cancels a posted expense.
  ///
  /// The voucher is kept and marked cancelled; the accounting is mirrored back
  /// out, and money taken from the float is put back by an opposing entry so
  /// the petty cash book shows both the payment and its reversal.
  Future<void> cancelExpense(
    AuthenticatedUser actor, {
    required int expenseId,
    required String reason,
  }) async {
    actor.require(Permissions.expenseManage, action: 'cancel expenses');
    final cleanReason = requireText(reason, 'Reason', maxLength: 500);

    await _db.transaction(() async {
      final expense = requireFound(
        await (_db.select(
          _db.expenses,
        )..where((e) => e.id.equals(expenseId))).getSingleOrNull(),
        'That expense no longer exists.',
      );
      requireRule(
        expense.status == InvoiceStatus.posted,
        expense.status == InvoiceStatus.cancelled
            ? 'That expense has already been cancelled.'
            : 'Only a posted expense can be cancelled.',
        rule: 'expense.cancel_posted_only',
      );

      if (expense.pettyCashEntryId != null) {
        await _pettyCash.appendEntry(
          actor: actor,
          kind: PettyCashEntryKind.cashReceived,
          amount: Money(expense.amountCents),
          description: 'Reversal of ${expense.voucherNumber}: $cleanReason',
          addsToFloat: true,
          entryDate: _clock.nowUtc(),
          expenseId: expenseId,
          postToJournal: false,
        );
      }

      for (final batchId in {
        for (final row in await _finance.entriesForSource(
          sourceKind: EntityKind.expense,
          sourceId: expenseId,
        ))
          if (!row.isReversal) row.batchId,
      }) {
        await _finance.reverse(
          actor: actor,
          batchId: batchId,
          reason: 'Expense ${expense.voucherNumber} cancelled',
        );
      }

      await (_db.update(
        _db.expenses,
      )..where((e) => e.id.equals(expenseId))).write(
        ExpensesCompanion(
          status: const Value(InvoiceStatus.cancelled),
          cancelledAt: Value(_clock.nowUtc()),
          cancelReason: Value(cleanReason),
        ),
      );

      await _audit.record(
        action: AuditAction.cancel,
        summary:
            'Cancelled expense ${expense.voucherNumber} '
            '(${Money(expense.amountCents).formatted()}): $cleanReason',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.expense,
        entityId: expenseId,
        before: {'status': expense.status.name},
        after: {'status': InvoiceStatus.cancelled.name},
      );
    });
  }

  // --- Categories ---------------------------------------------------------

  /// Adds a category. The seeded ones cover the usual ground; this is for
  /// whatever a particular business also needs.
  Future<int> createCategory(
    AuthenticatedUser actor, {
    required String name,
    String? code,
  }) async {
    actor.require(Permissions.expenseManage, action: 'add expense categories');
    final cleanName = requireText(name, 'Name', maxLength: 120);

    return _db.transaction(() async {
      // Case-insensitive, because "Shop signage" and "Shop Signage" are the
      // same category to everybody except a byte comparison.
      final existing =
          await (_db.select(_db.expenseCategories)
                ..where((c) => c.name.lower().equals(cleanName.toLowerCase())))
              .getSingleOrNull();
      requireRule(
        existing == null,
        'There is already a category called "${existing?.name}".',
        rule: 'expense_category.unique_name',
      );

      final resolvedCode =
          _clean(code) ?? _codeFrom(cleanName, await _categoryCodes());

      final id = await _db
          .into(_db.expenseCategories)
          .insert(
            ExpenseCategoriesCompanion.insert(
              code: resolvedCode,
              name: cleanName,
              createdAt: _clock.nowUtc(),
            ),
          );

      await _audit.record(
        action: AuditAction.create,
        summary: 'Added expense category "$cleanName" ($resolvedCode).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.expense,
        entityId: id,
      );
      return id;
    });
  }

  /// Archives a category so nothing new can be booked against it. Existing
  /// vouchers keep pointing at it, so history still reads correctly.
  Future<void> archiveCategory(
    AuthenticatedUser actor, {
    required int categoryId,
  }) async {
    actor.require(
      Permissions.expenseManage,
      action: 'archive expense categories',
    );

    await _db.transaction(() async {
      final category = requireFound(
        await (_db.select(
          _db.expenseCategories,
        )..where((c) => c.id.equals(categoryId))).getSingleOrNull(),
        'That category no longer exists.',
      );
      requireRule(
        !category.isSystem,
        'The category "${category.name}" is part of the standard set and '
        'cannot be archived.',
        rule: 'expense_category.system_kept',
      );
      requireRule(
        category.status != EntityStatus.archived,
        'That category is already archived.',
        rule: 'expense_category.archive_once',
      );

      await (_db.update(
        _db.expenseCategories,
      )..where((c) => c.id.equals(categoryId))).write(
        const ExpenseCategoriesCompanion(status: Value(EntityStatus.archived)),
      );

      await _audit.record(
        action: AuditAction.archive,
        summary: 'Archived expense category "${category.name}".',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.expense,
        entityId: categoryId,
      );
    });
  }

  // --- Internals ----------------------------------------------------------

  /// The expense account a category posts against, falling back to Operating
  /// Expenses when the category does not name one.
  Future<String?> _accountCodeFor(ExpenseCategory category) async {
    if (category.accountId == null) return null;
    final account = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(category.accountId!))).getSingleOrNull();
    return account?.code;
  }

  Future<Set<String>> _categoryCodes() async {
    final rows = await _db.select(_db.expenseCategories).get();
    return rows.map((row) => row.code).toSet();
  }

  /// A short code from the name, made unique by a numeric suffix.
  static String _codeFrom(String name, Set<String> taken) {
    final letters = name
        .toUpperCase()
        .replaceAll(RegExp('[^A-Z0-9 ]'), '')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final base = letters.isEmpty
        ? 'EXP'
        : letters.map((part) => part[0]).take(4).join();

    if (!taken.contains(base)) return base;
    for (var suffix = 2; suffix < 100; suffix++) {
      final candidate = '$base$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
    return '$base${DateTime.now().millisecondsSinceEpoch % 1000}';
  }

  static String? _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
