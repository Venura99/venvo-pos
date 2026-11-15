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
import '../domain/payment_models.dart';

/// Records money and applies it to invoices.
///
/// Two separate notions of "how much is left on an invoice" live here, and
/// keeping them apart is the whole point of the module:
///
/// * [outstandingOf] is what the party still **owes**. It counts cleared
///   payments and posted credit notes only. A cheque sitting in a drawer has
///   not paid anything yet.
/// * [allocatableRemaining] is what may still be **promised** against the
///   invoice. It counts pending payments too, so the same invoice cannot be
///   allocated twice - once by a cheque and again by cash - and end up
///   overpaid when the cheque clears.
///
/// A bounce needs no reversal: the payment's status moves out of `cleared`,
/// and because every balance is computed from cleared allocations, the
/// receivable comes back on its own with no history rewritten.
class PaymentService {
  PaymentService({
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

  /// Records a payment, its allocations and, for a cheque, the instrument.
  Future<PaymentResult> recordPayment(
    AuthenticatedUser actor,
    PaymentRequest request,
  ) async {
    actor.require(Permissions.paymentRecord, action: 'record payments');
    if (request.allocations.isNotEmpty) {
      actor.require(
        Permissions.paymentAllocate,
        action: 'apply a payment to an invoice',
      );
    }

    require(
      request.amount.isPositive,
      'A payment must be more than zero.',
      field: 'amount',
    );
    require(
      request.allocatedTotal <= request.amount,
      'The amounts applied to invoices come to '
      '${request.allocatedTotal.formatted()}, which is more than the payment '
      'of ${request.amount.formatted()}.',
      field: 'allocations',
    );

    final cheque = request.cheque;
    if (request.method == PaymentMethod.cheque) {
      requireFound(cheque, 'Enter the cheque number, bank and date.');
      requireText(cheque!.chequeNumber, 'Cheque number', maxLength: 32);
      requireText(cheque.bankName, 'Bank name', maxLength: 120);
    } else {
      requireRule(
        cheque == null,
        'Cheque details were given for a payment that is not a cheque.',
        rule: 'payment.cheque_details_only_for_cheques',
      );
    }

    return _db.transaction(() async {
      final receiptNumber = await _sequences.nextNumber(
        SequenceKeys.paymentReceipt,
      );
      final now = _clock.nowUtc();
      final paymentDate = request.paymentDate ?? now;
      final status = request.initialStatus;

      final partyType =
          request.partyType ??
          (request.agentId != null
              ? PartyType.agent
              : request.shopId != null
              ? PartyType.shop
              : request.employeeId != null
              ? PartyType.employee
              : PartyType.customer);

      final paymentId = await _db
          .into(_db.payments)
          .insert(
            PaymentsCompanion.insert(
              receiptNumber: receiptNumber,
              direction: request.direction,
              method: request.method,
              status: Value(status),
              paymentDate: paymentDate,
              partyType: partyType,
              agentId: Value(request.agentId),
              shopId: Value(request.shopId),
              employeeId: Value(request.employeeId),
              payerName: Value(_clean(request.payerName)),
              amountCents: request.amount.cents,
              bankName: Value(_clean(request.bankName ?? cheque?.bankName)),
              referenceNumber: Value(_clean(request.referenceNumber)),
              notes: Value(_clean(request.notes)),
              createdByUserId: actor.id,
              createdAt: now,
              clearedAt: Value(status == PaymentStatus.cleared ? now : null),
            ),
          );

      int? chequeId;
      if (cheque != null) {
        chequeId = await _db
            .into(_db.cheques)
            .insert(
              ChequesCompanion.insert(
                paymentId: paymentId,
                chequeNumber: cheque.chequeNumber.trim(),
                bankName: cheque.bankName.trim(),
                branchName: Value(_clean(cheque.branchName)),
                chequeDate: cheque.chequeDate,
                status: const Value(ChequeStatus.pending),
                updatedByUserId: Value(actor.id),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      // Money in becomes an asset and a liability: the business holds it, and
      // owes the party either goods or a refund until it is applied to an
      // invoice. A cheque lands in Cheques in Clearing rather than in cash or
      // the bank, which is what stops uncleared paper counting as money.
      //
      // Money *out* posts nothing here: an expense, a salary or a refund is
      // accounted for by whatever caused it, which is also what credits the
      // cash it came from. Posting here as well would count it twice.
      if (request.direction == PaymentDirection.inbound) {
        await _finance.postPaymentReceived(
          actor: actor,
          paymentId: paymentId,
          receiptNumber: receiptNumber,
          paymentDate: paymentDate,
          amount: request.amount,
          method: request.method,
          isCleared: status == PaymentStatus.cleared,
          agentId: request.agentId,
          shopId: request.shopId,
        );
      }

      var allocated = Money.zero;
      for (final allocation in request.allocations) {
        allocated += await _insertAllocation(
          actor: actor,
          paymentId: paymentId,
          invoiceId: allocation.invoiceId,
          amount: allocation.amount,
          notes: allocation.notes,
        );
      }

      await _setAllocatedCache(paymentId, allocated);

      await _audit.record(
        action: AuditAction.create,
        summary:
            'Recorded $receiptNumber: '
            '${paymentMethodLabel(request.method)} '
            '${request.amount.formatted()}'
            '${status == PaymentStatus.pending ? ' (pending clearance)' : ''}'
            '${allocated.isZero ? ' held as an advance' : ', '
                      '${allocated.formatted()} applied to '
                      '${request.allocations.length} invoice(s)'}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.payment,
        entityId: paymentId,
        after: {
          'receiptNumber': receiptNumber,
          'method': request.method.name,
          'status': status.name,
          'amountCents': request.amount.cents,
          'allocatedCents': allocated.cents,
          if (cheque != null) 'chequeNumber': cheque.chequeNumber,
        },
      );

      return PaymentResult(
        paymentId: paymentId,
        receiptNumber: receiptNumber,
        status: status,
        amount: request.amount,
        allocated: allocated,
        chequeId: chequeId,
      );
    });
  }

  /// Applies an existing payment's unallocated remainder to invoices. This is
  /// how an advance is settled later.
  Future<void> allocate(
    AuthenticatedUser actor, {
    required int paymentId,
    required List<PaymentAllocationRequest> allocations,
  }) async {
    actor.require(
      Permissions.paymentAllocate,
      action: 'apply a payment to an invoice',
    );
    require(allocations.isNotEmpty, 'Choose at least one invoice.');

    await _db.transaction(() async {
      final payment = await _requirePayment(paymentId);
      requireRule(
        payment.status != PaymentStatus.cancelled &&
            payment.status != PaymentStatus.bounced,
        'A ${paymentStatusLabel(payment.status).toLowerCase()} payment cannot '
        'be applied to an invoice.',
        rule: 'payment.allocate_live_only',
      );

      final requested = allocations.map((a) => a.amount).sum;
      final remaining =
          Money(payment.amountCents) - Money(payment.allocatedCents);
      require(
        requested <= remaining,
        'Only ${remaining.formatted()} of ${payment.receiptNumber} is '
        'unapplied, but ${requested.formatted()} was entered.',
        field: 'allocations',
      );

      var added = Money.zero;
      for (final allocation in allocations) {
        added += await _insertAllocation(
          actor: actor,
          paymentId: paymentId,
          invoiceId: allocation.invoiceId,
          amount: allocation.amount,
          notes: allocation.notes,
        );
      }

      await _setAllocatedCache(
        paymentId,
        Money(payment.allocatedCents) + added,
      );

      await _audit.record(
        action: AuditAction.update,
        summary:
            'Applied ${added.formatted()} of ${payment.receiptNumber} to '
            '${allocations.length} invoice(s).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.payment,
        entityId: paymentId,
      );
    });
  }

  /// Withdraws an allocation by recording a negative counter-allocation, so
  /// the trail of who applied what and when stays intact.
  Future<void> releaseAllocation(
    AuthenticatedUser actor, {
    required int paymentId,
    required int invoiceId,
    Money? amount,
    String? reason,
  }) async {
    actor.require(
      Permissions.paymentAllocate,
      action: 'withdraw a payment allocation',
    );

    await _db.transaction(() async {
      final payment = await _requirePayment(paymentId);
      final applied = await _allocatedToInvoiceByPayment(paymentId, invoiceId);
      requireRule(
        applied.isPositive,
        'That payment is not applied to this invoice.',
        rule: 'payment.release_requires_allocation',
      );

      final release = amount ?? applied;
      require(
        release.isPositive && release <= applied,
        'Up to ${applied.formatted()} can be withdrawn.',
        field: 'amount',
      );

      await _db
          .into(_db.paymentAllocations)
          .insert(
            PaymentAllocationsCompanion.insert(
              paymentId: paymentId,
              invoiceId: invoiceId,
              amountCents: -release.cents,
              notes: Value(_clean(reason) ?? 'Allocation withdrawn'),
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
            ),
          );

      await _setAllocatedCache(
        paymentId,
        Money(payment.allocatedCents) - release,
      );

      final invoice = await _requireInvoice(invoiceId);
      // Mirrors the condition in [_insertAllocation]: only settlement that
      // was posted can be taken back.
      if (payment.direction == PaymentDirection.inbound &&
          payment.status == PaymentStatus.cleared) {
        await _finance.postAllocation(
          actor: actor,
          paymentId: paymentId,
          receiptNumber: payment.receiptNumber,
          invoiceNumber: invoice.invoiceNumber,
          invoiceKind: invoice.kind,
          entryDate: _clock.nowUtc(),
          amount: release,
          isWithdrawal: true,
          agentId: invoice.agentId,
          shopId: invoice.shopId,
        );
      }

      await _audit.record(
        action: AuditAction.update,
        summary:
            'Withdrew ${release.formatted()} of '
            '${payment.receiptNumber} from ${invoice.invoiceNumber}.'
            '${reason == null || reason.trim().isEmpty ? '' : ' Reason: ${reason.trim()}'}',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.payment,
        entityId: paymentId,
      );
    });
  }

  /// Frees every allocation against an invoice, turning the money back into
  /// unapplied advances. Called when an invoice is cancelled: the money was
  /// still received, it simply no longer settles anything.
  ///
  /// Must be called inside the caller's transaction.
  Future<Money> releaseAllocationsForInvoice({
    required AuthenticatedUser actor,
    required int invoiceId,
    required String reason,
  }) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT payment_id, SUM(amount_cents) AS applied
      FROM payment_allocations
      WHERE invoice_id = ?
      GROUP BY payment_id
      HAVING SUM(amount_cents) > 0
      ''',
          variables: [Variable<int>(invoiceId)],
          readsFrom: {_db.paymentAllocations},
        )
        .get();

    var released = Money.zero;
    for (final row in rows) {
      final paymentId = row.read<int>('payment_id');
      final applied = Money(row.read<int>('applied'));

      await _db
          .into(_db.paymentAllocations)
          .insert(
            PaymentAllocationsCompanion.insert(
              paymentId: paymentId,
              invoiceId: invoiceId,
              amountCents: -applied.cents,
              notes: Value(reason),
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
            ),
          );

      final payment = await _requirePayment(paymentId);
      await _setAllocatedCache(
        paymentId,
        Money(payment.allocatedCents) - applied,
      );

      if (payment.direction == PaymentDirection.inbound &&
          payment.status == PaymentStatus.cleared) {
        final invoice = await _requireInvoice(invoiceId);
        await _finance.postAllocation(
          actor: actor,
          paymentId: paymentId,
          receiptNumber: payment.receiptNumber,
          invoiceNumber: invoice.invoiceNumber,
          invoiceKind: invoice.kind,
          entryDate: _clock.nowUtc(),
          amount: applied,
          isWithdrawal: true,
          agentId: invoice.agentId,
          shopId: invoice.shopId,
        );
      }

      released += applied;
    }
    return released;
  }

  // --- Cheque lifecycle ---------------------------------------------------

  /// Marks a cheque as banked. Still not cash: it is in clearing.
  Future<void> depositCheque(
    AuthenticatedUser actor, {
    required int chequeId,
    DateTime? depositedOn,
  }) async {
    actor.require(Permissions.chequeManage, action: 'bank cheques');

    await _db.transaction(() async {
      final cheque = await _requireCheque(chequeId);
      requireRule(
        cheque.status == ChequeStatus.pending,
        'Only a pending cheque can be banked. This one is '
        '${chequeStatusLabel(cheque.status).toLowerCase()}.',
        rule: 'cheque.deposit_pending_only',
      );

      final when = depositedOn ?? _clock.nowUtc();
      requireRule(
        !cheque.chequeDate.isAfter(when),
        'That cheque is dated '
        '${cheque.chequeDate.toLocal().toIso8601String().split('T').first} '
        'and cannot be banked before then.',
        rule: 'cheque.not_before_its_date',
      );

      await (_db.update(
        _db.cheques,
      )..where((c) => c.id.equals(chequeId))).write(
        ChequesCompanion(
          status: const Value(ChequeStatus.deposited),
          depositedAt: Value(when),
          updatedByUserId: Value(actor.id),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await _audit.record(
        action: AuditAction.update,
        summary:
            'Banked cheque ${cheque.chequeNumber} '
            '(${cheque.bankName}). It is in clearing, not yet cash.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.cheque,
        entityId: chequeId,
      );
    });
  }

  /// Clears a cheque. **This is the moment the money becomes real**: the
  /// payment moves to cleared, and every balance that counts cleared
  /// allocations changes as a result.
  Future<void> clearCheque(
    AuthenticatedUser actor, {
    required int chequeId,
    DateTime? clearedOn,
  }) async {
    actor.require(Permissions.chequeManage, action: 'clear cheques');

    await _db.transaction(() async {
      final cheque = await _requireCheque(chequeId);
      requireRule(
        cheque.status == ChequeStatus.pending ||
            cheque.status == ChequeStatus.deposited,
        'Only a pending or banked cheque can be cleared. This one is '
        '${chequeStatusLabel(cheque.status).toLowerCase()}.',
        rule: 'cheque.clear_outstanding_only',
      );

      final when = clearedOn ?? _clock.nowUtc();
      final payment = await _requirePayment(cheque.paymentId);

      await (_db.update(
        _db.cheques,
      )..where((c) => c.id.equals(chequeId))).write(
        ChequesCompanion(
          status: const Value(ChequeStatus.cleared),
          clearedAt: Value(when),
          updatedByUserId: Value(actor.id),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await (_db.update(
        _db.payments,
      )..where((p) => p.id.equals(cheque.paymentId))).write(
        PaymentsCompanion(
          status: const Value(PaymentStatus.cleared),
          clearedAt: Value(when),
        ),
      );

      // Only now does the money reach the bank. Until this moment it was
      // sitting in Cheques in Clearing, which is the whole reason that
      // account exists.
      await _finance.postChequeCleared(
        actor: actor,
        paymentId: payment.id,
        chequeNumber: cheque.chequeNumber,
        clearedOn: when,
        amount: Money(payment.amountCents),
        agentId: payment.agentId,
        shopId: payment.shopId,
      );

      // And only now does whatever this cheque was applied to count as
      // settled, which is the moment the receivable comes down.
      await _postAllocationsFor(
        actor,
        payment: payment,
        entryDate: when,
        isWithdrawal: false,
      );

      await _audit.record(
        action: AuditAction.update,
        summary:
            'Cleared cheque ${cheque.chequeNumber} for '
            '${Money(payment.amountCents).formatted()}. '
            '${payment.receiptNumber} now counts as settled money.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.cheque,
        entityId: chequeId,
        before: {'status': cheque.status.name},
        after: {'status': ChequeStatus.cleared.name},
      );
    });
  }

  /// Records a bounce.
  ///
  /// Nothing is deleted and no allocation is reversed: the payment simply
  /// stops being cleared, and because receivables count cleared allocations
  /// only, the debt reappears by itself. An optional bank charge is recorded
  /// on the cheque for recovery.
  Future<void> bounceCheque(
    AuthenticatedUser actor, {
    required int chequeId,
    required String reason,
    Money bounceCharge = Money.zero,
    DateTime? bouncedOn,
  }) async {
    actor.require(Permissions.chequeManage, action: 'record a bounced cheque');
    final cleanReason = requireText(reason, 'Reason', maxLength: 300);
    require(
      !bounceCharge.isNegative,
      'A bounce charge cannot be negative.',
      field: 'bounceCharge',
    );

    await _db.transaction(() async {
      final cheque = await _requireCheque(chequeId);
      requireRule(
        cheque.status != ChequeStatus.bounced,
        'That cheque is already recorded as bounced.',
        rule: 'cheque.bounce_once',
      );
      requireRule(
        cheque.status != ChequeStatus.cancelled,
        'A cancelled cheque cannot bounce.',
        rule: 'cheque.bounce_live_only',
      );

      final when = bouncedOn ?? _clock.nowUtc();
      final payment = await _requirePayment(cheque.paymentId);

      await (_db.update(
        _db.cheques,
      )..where((c) => c.id.equals(chequeId))).write(
        ChequesCompanion(
          status: const Value(ChequeStatus.bounced),
          bouncedAt: Value(when),
          bounceReason: Value(cleanReason),
          bounceChargeCents: Value(bounceCharge.cents),
          clearedAt: const Value(null),
          updatedByUserId: Value(actor.id),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await (_db.update(
        _db.payments,
      )..where((p) => p.id.equals(cheque.paymentId))).write(
        PaymentsCompanion(
          status: const Value(PaymentStatus.bounced),
          bouncedAt: Value(when),
          clearedAt: const Value(null),
        ),
      );

      final hadCleared = cheque.status == ChequeStatus.cleared;

      // If the cheque had cleared, whatever it was covering stops being
      // settled, so the receivable comes back before the money is taken out.
      if (hadCleared) {
        await _postAllocationsFor(
          actor,
          payment: payment,
          entryDate: when,
          isWithdrawal: true,
        );
      }

      await _finance.postChequeBounced(
        actor: actor,
        paymentId: payment.id,
        chequeNumber: cheque.chequeNumber,
        bouncedOn: when,
        amount: Money(payment.amountCents),
        wasCleared: hadCleared,
        charges: bounceCharge,
        agentId: payment.agentId,
        shopId: payment.shopId,
      );

      await _audit.record(
        action: AuditAction.reverse,
        summary:
            'Cheque ${cheque.chequeNumber} for '
            '${Money(payment.amountCents).formatted()} bounced: $cleanReason. '
            '${payment.receiptNumber} no longer settles anything, so the '
            'balance it had covered is owed again.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.cheque,
        entityId: chequeId,
        before: {'status': cheque.status.name},
        after: {
          'status': ChequeStatus.bounced.name,
          'reason': cleanReason,
          if (!bounceCharge.isZero) 'bounceChargeCents': bounceCharge.cents,
        },
      );
    });
  }

  /// Links a replacement payment to a bounced cheque, so the two are
  /// connected without the bounce being erased.
  Future<void> linkReplacementPayment(
    AuthenticatedUser actor, {
    required int chequeId,
    required int replacementPaymentId,
  }) async {
    actor.require(Permissions.chequeManage, action: 'record a replacement');

    await _db.transaction(() async {
      final cheque = await _requireCheque(chequeId);
      requireRule(
        cheque.status == ChequeStatus.bounced ||
            cheque.status == ChequeStatus.returned,
        'Only a bounced or returned cheque needs a replacement.',
        rule: 'cheque.replacement_for_failed_only',
      );
      final replacement = await _requirePayment(replacementPaymentId);

      await (_db.update(
        _db.cheques,
      )..where((c) => c.id.equals(chequeId))).write(
        ChequesCompanion(
          replacementPaymentId: Value(replacementPaymentId),
          updatedByUserId: Value(actor.id),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await _audit.record(
        action: AuditAction.update,
        summary:
            'Recorded ${replacement.receiptNumber} as the replacement '
            'for bounced cheque ${cheque.chequeNumber}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.cheque,
        entityId: chequeId,
      );
    });
  }

  /// Cancels a payment entered in error. Its allocations stop being effective
  /// because every balance counts cleared allocations only.
  Future<void> cancelPayment(
    AuthenticatedUser actor, {
    required int paymentId,
    required String reason,
  }) async {
    actor.require(Permissions.paymentCancel, action: 'cancel a payment');
    final cleanReason = requireText(reason, 'Reason', maxLength: 500);

    await _db.transaction(() async {
      final payment = await _requirePayment(paymentId);
      requireRule(
        payment.status != PaymentStatus.cancelled,
        'That payment has already been cancelled.',
        rule: 'payment.cancel_once',
      );

      await (_db.update(
        _db.payments,
      )..where((p) => p.id.equals(paymentId))).write(
        PaymentsCompanion(
          status: const Value(PaymentStatus.cancelled),
          cancelledAt: Value(_clock.nowUtc()),
          cancelledByUserId: Value(actor.id),
          cancelReason: Value(cleanReason),
          clearedAt: const Value(null),
        ),
      );

      final cheque = await (_db.select(
        _db.cheques,
      )..where((c) => c.paymentId.equals(paymentId))).getSingleOrNull();
      if (cheque != null) {
        await (_db.update(
          _db.cheques,
        )..where((c) => c.id.equals(cheque.id))).write(
          ChequesCompanion(
            status: const Value(ChequeStatus.cancelled),
            updatedByUserId: Value(actor.id),
            updatedAt: Value(_clock.nowUtc()),
          ),
        );
      }

      // Everything this payment posted is mirrored back out: the receipt, any
      // settlement it had been applied to, and the clearance if it had
      // cleared. The original batches stay in the journal.
      //
      // A bounced payment is skipped, because bouncing already took its
      // accounting back out; reversing it again would only add two batches
      // that cancel each other.
      final needsUnposting =
          payment.status == PaymentStatus.pending ||
          payment.status == PaymentStatus.cleared;
      if (payment.direction == PaymentDirection.inbound && needsUnposting) {
        for (final kind in [EntityKind.payment, EntityKind.cheque]) {
          for (final batchId in {
            for (final row in await _finance.entriesForSource(
              sourceKind: kind,
              sourceId: paymentId,
            ))
              if (!row.isReversal) row.batchId,
          }) {
            await _finance.reverse(
              actor: actor,
              batchId: batchId,
              reason: 'Payment ${payment.receiptNumber} cancelled',
            );
          }
        }
      }

      await _audit.record(
        action: AuditAction.cancel,
        summary:
            'Cancelled ${payment.receiptNumber} '
            '(${Money(payment.amountCents).formatted()}): $cleanReason',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.payment,
        entityId: paymentId,
        before: {'status': payment.status.name},
        after: {'status': PaymentStatus.cancelled.name},
      );
    });
  }

  // --- Balances -----------------------------------------------------------

  /// What an invoice still owes. Cleared money and posted credit notes only.
  Future<Money> outstandingOf(int invoiceId) async {
    final row = await _db
        .customSelect(
          '''
      SELECT
        i.net_total_cents AS net,
        i.status AS status,
        COALESCE((
          SELECT SUM(pa.amount_cents) FROM payment_allocations pa
          JOIN payments p ON p.id = pa.payment_id
          WHERE pa.invoice_id = i.id AND p.status = ?
        ), 0) AS settled,
        COALESCE((
          SELECT SUM(cna.amount_cents) FROM credit_note_applications cna
          JOIN credit_notes cn ON cn.id = cna.credit_note_id
          WHERE cna.invoice_id = i.id AND cn.status = ?
        ), 0) AS credited
      FROM invoices i
      WHERE i.id = ?
      ''',
          variables: [
            Variable<String>(PaymentStatus.cleared.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<int>(invoiceId),
          ],
          readsFrom: {
            _db.invoices,
            _db.payments,
            _db.paymentAllocations,
            _db.creditNotes,
            _db.creditNoteApplications,
          },
        )
        .getSingleOrNull();

    final resolved = requireFound(row, 'That invoice no longer exists.');
    if (resolved.read<String>('status') != InvoiceStatus.posted.name) {
      return Money.zero;
    }
    return Money(resolved.read<int>('net')) -
        Money(resolved.read<int>('settled')) -
        Money(resolved.read<int>('credited'));
  }

  /// What may still be promised against an invoice.
  ///
  /// Counts pending payments as well as cleared ones, so a cheque already
  /// given against an invoice stops that invoice being allocated again.
  Future<Money> allocatableRemaining(int invoiceId) async {
    final row = await _db
        .customSelect(
          '''
      SELECT
        i.net_total_cents AS net,
        i.status AS status,
        COALESCE((
          SELECT SUM(pa.amount_cents) FROM payment_allocations pa
          JOIN payments p ON p.id = pa.payment_id
          WHERE pa.invoice_id = i.id AND p.status IN (?, ?)
        ), 0) AS promised,
        COALESCE((
          SELECT SUM(cna.amount_cents) FROM credit_note_applications cna
          JOIN credit_notes cn ON cn.id = cna.credit_note_id
          WHERE cna.invoice_id = i.id AND cn.status = ?
        ), 0) AS credited
      FROM invoices i
      WHERE i.id = ?
      ''',
          variables: [
            Variable<String>(PaymentStatus.cleared.name),
            Variable<String>(PaymentStatus.pending.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<int>(invoiceId),
          ],
          readsFrom: {
            _db.invoices,
            _db.payments,
            _db.paymentAllocations,
            _db.creditNotes,
            _db.creditNoteApplications,
          },
        )
        .getSingleOrNull();

    final resolved = requireFound(row, 'That invoice no longer exists.');
    if (resolved.read<String>('status') != InvoiceStatus.posted.name) {
      return Money.zero;
    }
    final remaining =
        Money(resolved.read<int>('net')) -
        Money(resolved.read<int>('promised')) -
        Money(resolved.read<int>('credited'));
    return remaining.isNegative ? Money.zero : remaining;
  }

  /// Invoices a party can still have money applied to, newest first.
  Future<List<AllocatableInvoice>> allocatableInvoices({
    int? agentId,
    int? shopId,
  }) async {
    requireRule(
      agentId != null || shopId != null,
      'Choose an agent or a shop.',
      rule: 'payment.party_required',
    );

    final rows = await _db
        .customSelect(
          '''
      SELECT
        i.id,
        i.invoice_number,
        i.invoice_date,
        i.due_date,
        i.net_total_cents AS net,
        COALESCE(cleared.total, 0) AS settled,
        COALESCE(promised.total, 0) AS promised,
        COALESCE(credited.total, 0) AS credited,
        COALESCE(pending_cheques.total, 0) AS pending_cheques
      FROM invoices i
      LEFT JOIN (
        SELECT pa.invoice_id, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        WHERE p.status = ?
        GROUP BY pa.invoice_id
      ) cleared ON cleared.invoice_id = i.id
      LEFT JOIN (
        SELECT pa.invoice_id, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        WHERE p.status IN (?, ?)
        GROUP BY pa.invoice_id
      ) promised ON promised.invoice_id = i.id
      LEFT JOIN (
        SELECT cna.invoice_id, SUM(cna.amount_cents) AS total
        FROM credit_note_applications cna
        JOIN credit_notes cn ON cn.id = cna.credit_note_id
        WHERE cn.status = ?
        GROUP BY cna.invoice_id
      ) credited ON credited.invoice_id = i.id
      LEFT JOIN (
        SELECT pa.invoice_id, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        WHERE p.status = ?
        GROUP BY pa.invoice_id
      ) pending_cheques ON pending_cheques.invoice_id = i.id
      WHERE i.status = ?
        AND (? IS NULL OR i.agent_id = ?)
        AND (? IS NULL OR i.shop_id = ?)
        AND i.net_total_cents
            - COALESCE(promised.total, 0)
            - COALESCE(credited.total, 0) > 0
      ORDER BY i.invoice_date, i.id
      ''',
          variables: [
            Variable<String>(PaymentStatus.cleared.name),
            Variable<String>(PaymentStatus.cleared.name),
            Variable<String>(PaymentStatus.pending.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(PaymentStatus.pending.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<int>(agentId),
            Variable<int>(agentId),
            Variable<int>(shopId),
            Variable<int>(shopId),
          ],
          readsFrom: {
            _db.invoices,
            _db.payments,
            _db.paymentAllocations,
            _db.creditNotes,
            _db.creditNoteApplications,
          },
        )
        .get();

    return rows
        .map((row) {
          final net = Money(row.read<int>('net'));
          final settled = Money(row.read<int>('settled'));
          final promised = Money(row.read<int>('promised'));
          final credited = Money(row.read<int>('credited'));

          return AllocatableInvoice(
            invoiceId: row.read<int>('id'),
            invoiceNumber: row.read<String>('invoice_number'),
            invoiceDate: row.read<DateTime>('invoice_date'),
            dueDate: row.readNullable<DateTime>('due_date'),
            net: net,
            outstanding: net - settled - credited,
            allocatable: net - promised - credited,
            pendingCheques: Money(row.read<int>('pending_cheques')),
          );
        })
        .toList(growable: false);
  }

  /// Unapplied inbound money held for a party.
  Future<Money> advanceBalance({int? agentId, int? shopId}) async {
    final row = await _db
        .customSelect(
          '''
      SELECT COALESCE(SUM(amount_cents - allocated_cents), 0) AS advance
      FROM payments
      WHERE direction = ? AND status = ?
        AND (? IS NULL OR agent_id = ?)
        AND (? IS NULL OR shop_id = ?)
      ''',
          variables: [
            Variable<String>(PaymentDirection.inbound.name),
            Variable<String>(PaymentStatus.cleared.name),
            Variable<int>(agentId),
            Variable<int>(agentId),
            Variable<int>(shopId),
            Variable<int>(shopId),
          ],
          readsFrom: {_db.payments},
        )
        .getSingle();

    return Money(row.read<int>('advance'));
  }

  // --- Internals ----------------------------------------------------------

  /// Inserts one allocation after checking there is room for it.
  Future<Money> _insertAllocation({
    required AuthenticatedUser actor,
    required int paymentId,
    required int invoiceId,
    required Money amount,
    String? notes,
  }) async {
    require(
      amount.isPositive,
      'An amount applied to an invoice must be more than zero.',
      field: 'amount',
    );

    final invoice = await _requireInvoice(invoiceId);
    requireRule(
      invoice.status == InvoiceStatus.posted,
      'Invoice ${invoice.invoiceNumber} is '
      '${invoice.status.name} and cannot have money applied to it.',
      rule: 'payment.invoice_posted_only',
    );

    final room = await allocatableRemaining(invoiceId);
    requireRule(
      amount <= room,
      room.isZero
          ? 'Invoice ${invoice.invoiceNumber} is already fully covered.'
          : 'Only ${room.formatted()} can still be applied to '
                '${invoice.invoiceNumber}, but ${amount.formatted()} was '
                'entered.',
      rule: 'payment.no_over_allocation',
    );

    await _db
        .into(_db.paymentAllocations)
        .insert(
          PaymentAllocationsCompanion.insert(
            paymentId: paymentId,
            invoiceId: invoiceId,
            amountCents: amount.cents,
            notes: Value(_clean(notes)),
            createdByUserId: actor.id,
            createdAt: _clock.nowUtc(),
          ),
        );

    // Pointing money at an invoice is what turns a liability into settlement:
    // the advance the business held is released and the receivable comes down.
    //
    // Only **cleared** money does that, which is the same rule
    // [outstandingOf] applies. Allocating a cheque that has not cleared
    // reserves the invoice against further allocation but settles nothing, so
    // it posts nothing; [clearCheque] posts the settlement when the money
    // actually arrives. Without that, the journal would show an invoice as
    // paid while every other report in the application correctly showed it as
    // outstanding.
    final payment = await _requirePayment(paymentId);
    if (payment.direction == PaymentDirection.inbound &&
        payment.status == PaymentStatus.cleared) {
      await _finance.postAllocation(
        actor: actor,
        paymentId: paymentId,
        receiptNumber: payment.receiptNumber,
        invoiceNumber: invoice.invoiceNumber,
        invoiceKind: invoice.kind,
        entryDate: _clock.nowUtc(),
        amount: amount,
        agentId: invoice.agentId,
        shopId: invoice.shopId,
      );
    }

    return amount;
  }

  /// Net allocation per invoice for one payment, withdrawals already netted
  /// off. Used when a cheque clears or bounces, to move the receivable for
  /// whatever that payment is actually covering at that moment.
  Future<List<({int invoiceId, Money amount})>> _allocationsByInvoice(
    int paymentId,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT invoice_id, SUM(amount_cents) AS applied '
          'FROM payment_allocations WHERE payment_id = ? '
          'GROUP BY invoice_id HAVING SUM(amount_cents) <> 0',
          variables: [Variable<int>(paymentId)],
          readsFrom: {_db.paymentAllocations},
        )
        .get();

    return rows
        .map(
          (row) => (
            invoiceId: row.read<int>('invoice_id'),
            amount: Money(row.read<int>('applied')),
          ),
        )
        .toList(growable: false);
  }

  /// Moves the receivable for everything a payment covers, in one direction or
  /// the other. Called when a cheque clears, and again if it later bounces.
  Future<void> _postAllocationsFor(
    AuthenticatedUser actor, {
    required Payment payment,
    required DateTime entryDate,
    required bool isWithdrawal,
  }) async {
    for (final allocation in await _allocationsByInvoice(payment.id)) {
      final invoice = await _requireInvoice(allocation.invoiceId);
      await _finance.postAllocation(
        actor: actor,
        paymentId: payment.id,
        receiptNumber: payment.receiptNumber,
        invoiceNumber: invoice.invoiceNumber,
        invoiceKind: invoice.kind,
        entryDate: entryDate,
        amount: allocation.amount,
        isWithdrawal: isWithdrawal,
        agentId: invoice.agentId,
        shopId: invoice.shopId,
      );
    }
  }

  Future<void> _setAllocatedCache(int paymentId, Money allocated) async {
    await (_db.update(_db.payments)..where((p) => p.id.equals(paymentId)))
        .write(PaymentsCompanion(allocatedCents: Value(allocated.cents)));
  }

  Future<Money> _allocatedToInvoiceByPayment(
    int paymentId,
    int invoiceId,
  ) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(amount_cents), 0) AS applied '
          'FROM payment_allocations WHERE payment_id = ? AND invoice_id = ?',
          variables: [Variable<int>(paymentId), Variable<int>(invoiceId)],
          readsFrom: {_db.paymentAllocations},
        )
        .getSingle();
    return Money(row.read<int>('applied'));
  }

  Future<Payment> _requirePayment(int paymentId) async {
    return requireFound(
      await (_db.select(
        _db.payments,
      )..where((p) => p.id.equals(paymentId))).getSingleOrNull(),
      'That payment no longer exists.',
    );
  }

  Future<Invoice> _requireInvoice(int invoiceId) async {
    return requireFound(
      await (_db.select(
        _db.invoices,
      )..where((i) => i.id.equals(invoiceId))).getSingleOrNull(),
      'That invoice no longer exists.',
    );
  }

  Future<Cheque> _requireCheque(int chequeId) async {
    return requireFound(
      await (_db.select(
        _db.cheques,
      )..where((c) => c.id.equals(chequeId))).getSingleOrNull(),
      'That cheque no longer exists.',
    );
  }

  static String? _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
