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
import '../../inventory/data/location_repository.dart';
import '../../inventory/data/stock_ledger_service.dart';
import '../../inventory/domain/stock_models.dart';
import '../domain/return_models.dart';

/// Handles goods coming back, and the credit that may follow.
///
/// A return is deliberately **two** stock movements, not one:
///
/// 1. **Receipt.** The goods leave the returning location and land in
///    goods-in-transit. The returning party's stock drops immediately - they
///    no longer hold the goods - but nothing has entered sellable stock, so
///    nobody can promise units that have not been looked at yet.
/// 2. **Disposition.** Once inspected, the goods leave transit: accepted units
///    to the return's receiving location, defective units to the damaged
///    store, written-off units out through the adjustment counterparty.
///
/// Money is handled separately from goods and only ever moves forward. A
/// return never edits the original invoice or its payments: credit is a new
/// [CreditNotes] row, applied to invoices the same way a payment is allocated.
/// A scrapped unit moves stock but earns no credit, and a return with credit
/// against it cannot be cancelled until that credit is withdrawn - so the
/// goods and the money can never disagree.
class ReturnService {
  ReturnService({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    required SequenceService sequences,
    required StockLedgerService ledger,
    required LocationRepository locations,
    required FinancialLedgerService finance,
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _sequences = sequences,
       _ledger = ledger,
       _locations = locations,
       _finance = finance;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final SequenceService _sequences;
  final StockLedgerService _ledger;
  final LocationRepository _locations;
  final FinancialLedgerService _finance;

  // --- Returns ------------------------------------------------------------

  /// Records a return and posts the receipt leg.
  ///
  /// Everything happens in one transaction: the document number, the returns
  /// header, its lines, the stock movement out of the returning location and
  /// the returned-quantity counters on the original invoice. A failure
  /// anywhere leaves none of it behind.
  Future<ReturnPostResult> postReturn(
    AuthenticatedUser actor,
    ReturnDraft draft,
  ) async {
    actor.require(Permissions.returnCreate, action: 'record returns');
    if (draft.route == ReturnRoute.shopToWarehouse) {
      actor.require(
        Permissions.returnDirectToWarehouse,
        action: 'send a return straight from a shop to the warehouse',
      );
    }
    require(
      draft.lines.isNotEmpty,
      'Add at least one product to the return.',
      field: 'lines',
    );
    for (final line in draft.lines) {
      require(
        line.quantity > 0,
        'Every returned line needs a quantity of at least 1.',
        field: 'quantity',
      );
    }
    final reasonNote = draft.reason == ReturnReason.other
        ? requireText(draft.reasonNote, 'Reason note', maxLength: 500)
        : _clean(draft.reasonNote);

    return _db.transaction(() async {
      final from = await _requireLocation(
        draft.fromLocationId,
        'returned from',
      );
      final to = await _requireLocation(draft.toLocationId, 'returned to');
      final transit = await _locations.byCode(
        AppConstants.inTransitLocationCode,
      );

      _assertRouteLocations(draft.route, from, to);

      final resolved = await _resolveLines(draft);
      final returnDate = draft.returnDate ?? _clock.nowUtc();
      final totalValue = resolved.map((line) => line.lineValue).sum;

      // The goods leave the returning location now, but land in transit
      // rather than in stock: an uninspected return is not available to sell.
      final receipt = await _ledger.postMovement(
        actor,
        StockMovementRequest(
          documentType: _documentTypeFor(draft.route),
          sourceLocationId: from.id,
          destinationLocationId: transit.id,
          documentDate: returnDate,
          agentId: draft.agentId,
          shopId: draft.shopId,
          referenceNote: draft.originInvoiceId == null
              ? null
              : 'Return against invoice #${draft.originInvoiceId}',
          notes: draft.notes,
          lines: [
            for (final line in resolved)
              StockMovementLine(
                productId: line.productId,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
              ),
          ],
        ),
      );

      final returnNumber = await _sequences.nextNumber(
        SequenceKeys.returnNote,
        prefixOverride: SequenceKeys.returnNote,
      );

      final returnId = await _db
          .into(_db.returnDocuments)
          .insert(
            ReturnDocumentsCompanion.insert(
              returnNumber: returnNumber,
              route: draft.route,
              status: const Value(ReturnStatus.posted),
              returnDate: returnDate,
              originInvoiceId: Value(draft.originInvoiceId),
              originStockTransactionId: Value(draft.originStockTransactionId),
              fromLocationId: from.id,
              toLocationId: to.id,
              agentId: Value(draft.agentId),
              shopId: Value(draft.shopId),
              reason: draft.reason,
              reasonNote: Value(reasonNote),
              authorisedByUserId: Value(
                draft.route == ReturnRoute.shopToWarehouse ? actor.id : null,
              ),
              receiptTransactionId: Value(receipt.transactionId),
              totalQuantity: Value(draft.totalQuantity),
              totalValueCents: Value(totalValue.cents),
              notes: Value(_clean(draft.notes)),
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
              postedAt: Value(_clock.nowUtc()),
            ),
          );

      var lineNumber = 0;
      for (final line in resolved) {
        lineNumber++;
        await _db
            .into(_db.returnItems)
            .insert(
              ReturnItemsCompanion.insert(
                returnId: returnId,
                lineNumber: lineNumber,
                productId: line.productId,
                productNameSnapshot: line.productName,
                skuSnapshot: line.sku,
                originInvoiceItemId: Value(line.originInvoiceItemId),
                quantity: line.quantity,
                unitPriceCents: Value(line.unitPrice.cents),
                lineValueCents: Value(line.lineValue.cents),
                notes: Value(line.notes),
              ),
            );

        // Stops the same units being returned twice across two returns.
        if (line.originInvoiceItemId != null) {
          await _db.customUpdate(
            'UPDATE invoice_items SET returned_quantity = '
            'returned_quantity + ? WHERE id = ?',
            variables: [
              Variable<int>(line.quantity),
              Variable<int>(line.originInvoiceItemId!),
            ],
            updates: {_db.invoiceItems},
          );
        }
      }

      await _audit.record(
        action: AuditAction.post,
        summary:
            'Return $returnNumber: ${draft.totalQuantity} unit(s) back from '
            '"${from.name}" (${totalValue.formatted()}), awaiting inspection.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.returnDocument,
        entityId: returnId,
        after: {
          'returnNumber': returnNumber,
          'route': draft.route.name,
          'reason': draft.reason.name,
          'totalQuantity': draft.totalQuantity,
          'totalValueCents': totalValue.cents,
          'receiptDocument': receipt.documentNumber,
        },
      );

      return ReturnPostResult(
        returnId: returnId,
        returnNumber: returnNumber,
        receiptTransactionId: receipt.transactionId,
        receiptDocumentNumber: receipt.documentNumber,
        totalQuantity: draft.totalQuantity,
        totalValue: totalValue,
      );
    });
  }

  /// Records the inspection and moves the goods out of transit.
  ///
  /// Every line must be decided and every returned unit accounted for, so no
  /// quantity is left sitting in transit where no report would look for it.
  Future<InspectionResult> recordInspection(
    AuthenticatedUser actor,
    InspectionRequest request,
  ) async {
    actor.require(Permissions.returnInspect, action: 'inspect returns');

    return _db.transaction(() async {
      final document = await _requireReturn(request.returnId);
      requireRule(
        document.status == ReturnStatus.posted,
        document.status == ReturnStatus.cancelled
            ? 'Return ${document.returnNumber} has been cancelled.'
            : 'Return ${document.returnNumber} has already been inspected.',
        rule: 'return.inspect_posted_only',
      );

      final items =
          await (_db.select(_db.returnItems)
                ..where((row) => row.returnId.equals(request.returnId))
                ..orderBy([(row) => OrderingTerm.asc(row.lineNumber)]))
              .get();

      final byId = {for (final item in items) item.id: item};
      final decisions = <int, InspectionDecision>{};
      for (final decision in request.decisions) {
        final item = requireFound(
          byId[decision.returnItemId],
          'One of the inspected lines is not part of '
          '${document.returnNumber}.',
        );
        requireRule(
          decisions[decision.returnItemId] == null,
          'Line ${item.lineNumber} was inspected twice in the same request.',
          rule: 'return.one_decision_per_line',
        );
        require(
          decision.acceptedQuantity >= 0 &&
              decision.damagedQuantity >= 0 &&
              decision.scrappedQuantity >= 0,
          'Inspected quantities cannot be negative.',
          field: 'quantity',
        );
        requireRule(
          decision.total == item.quantity,
          'Line ${item.lineNumber} (${item.productNameSnapshot}) came back '
          'with ${item.quantity} unit(s), but '
          '${decision.total} were accounted for. Accepted, damaged and '
          'scrapped quantities must add up to what was returned.',
          rule: 'return.inspection_accounts_for_every_unit',
        );
        decisions[decision.returnItemId] = decision;
      }

      requireRule(
        decisions.length == items.length,
        'Every line has to be inspected before the return can be closed: '
        '${items.length - decisions.length} still undecided.',
        rule: 'return.inspect_every_line',
      );

      final transit = await _locations.byCode(
        AppConstants.inTransitLocationCode,
      );
      final damagedStore = await _locations.byCode(
        AppConstants.damagedLocationCode,
      );
      final adjustments = await _locations.byCode(
        AppConstants.adjustmentLocationCode,
      );
      final destination = await _requireLocation(
        document.toLocationId,
        'returned to',
      );

      final now = _clock.nowUtc();
      final accepted = <StockMovementLine>[];
      final damaged = <StockMovementLine>[];
      final scrapped = <StockMovementLine>[];
      var acceptedUnits = 0;
      var damagedUnits = 0;
      var scrappedUnits = 0;
      var creditableValue = Money.zero;

      for (final item in items) {
        final decision = decisions[item.id]!;
        final unitPrice = Money(item.unitPriceCents);

        if (decision.acceptedQuantity > 0) {
          accepted.add(
            StockMovementLine(
              productId: item.productId,
              quantity: decision.acceptedQuantity,
              unitPrice: unitPrice,
            ),
          );
          acceptedUnits += decision.acceptedQuantity;
        }
        if (decision.damagedQuantity > 0) {
          damaged.add(
            StockMovementLine(
              productId: item.productId,
              quantity: decision.damagedQuantity,
              unitPrice: unitPrice,
            ),
          );
          damagedUnits += decision.damagedQuantity;
        }
        if (decision.scrappedQuantity > 0) {
          scrapped.add(
            StockMovementLine(
              productId: item.productId,
              quantity: decision.scrappedQuantity,
              unitPrice: unitPrice,
            ),
          );
          scrappedUnits += decision.scrappedQuantity;
        }

        // A scrapped unit is a write-off, so it earns no credit. A damaged one
        // still came back and is credited: the loss sits with the business,
        // which is what the damaged store exists to report.
        creditableValue +=
            unitPrice * (decision.acceptedQuantity + decision.damagedQuantity);

        await (_db.update(
          _db.returnItems,
        )..where((r) => r.id.equals(item.id))).write(
          ReturnItemsCompanion(
            inspectionStatus: Value(decision.status),
            acceptedQuantity: Value(decision.acceptedQuantity),
            damagedQuantity: Value(decision.damagedQuantity),
            scrappedQuantity: Value(decision.scrappedQuantity),
            inspectionNote: Value(_clean(decision.note)),
            inspectedByUserId: Value(actor.id),
            inspectedAt: Value(now),
          ),
        );
      }

      StockMovementResult? acceptedMove;
      StockMovementResult? damagedMove;
      StockMovementResult? scrappedMove;

      if (accepted.isNotEmpty) {
        acceptedMove = await _ledger.postMovement(
          actor,
          StockMovementRequest(
            documentType: _documentTypeFor(document.route),
            sourceLocationId: transit.id,
            destinationLocationId: destination.id,
            documentDate: now,
            agentId: document.agentId,
            shopId: document.shopId,
            referenceNote: 'Accepted on ${document.returnNumber}',
            lines: accepted,
          ),
        );
      }
      if (damaged.isNotEmpty) {
        damagedMove = await _ledger.postMovement(
          actor,
          StockMovementRequest(
            documentType: StockDocumentType.damageWriteOff,
            sourceLocationId: transit.id,
            destinationLocationId: damagedStore.id,
            documentDate: now,
            agentId: document.agentId,
            shopId: document.shopId,
            referenceNote: 'Rejected on ${document.returnNumber}',
            lines: damaged,
          ),
        );
      }
      if (scrapped.isNotEmpty) {
        scrappedMove = await _ledger.postMovement(
          actor,
          StockMovementRequest(
            documentType: StockDocumentType.adjustmentDecrease,
            sourceLocationId: transit.id,
            destinationLocationId: adjustments.id,
            documentDate: now,
            agentId: document.agentId,
            shopId: document.shopId,
            referenceNote: 'Scrapped on ${document.returnNumber}',
            lines: scrapped,
          ),
        );
      }

      // Nothing creditable left means the return is finished; otherwise it
      // stays open until the credit decision has been made.
      final status = creditableValue.isPositive
          ? ReturnStatus.inspected
          : ReturnStatus.completed;

      await (_db.update(
        _db.returnDocuments,
      )..where((r) => r.id.equals(request.returnId))).write(
        ReturnDocumentsCompanion(
          status: Value(status),
          dispositionTransactionId: Value(
            acceptedMove?.transactionId ??
                damagedMove?.transactionId ??
                scrappedMove?.transactionId,
          ),
          completedAt: Value(status == ReturnStatus.completed ? now : null),
          notes: Value(_mergeNotes(document.notes, request.notes)),
        ),
      );

      await _audit.record(
        action: AuditAction.update,
        summary:
            'Inspected ${document.returnNumber}: $acceptedUnits accepted, '
            '$damagedUnits to the damaged store, $scrappedUnits scrapped '
            '(${creditableValue.formatted()} creditable).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.returnDocument,
        entityId: request.returnId,
        before: {'status': document.status.name},
        after: {
          'status': status.name,
          'acceptedQuantity': acceptedUnits,
          'damagedQuantity': damagedUnits,
          'scrappedQuantity': scrappedUnits,
          'creditableValueCents': creditableValue.cents,
        },
      );

      return InspectionResult(
        returnId: request.returnId,
        acceptedQuantity: acceptedUnits,
        damagedQuantity: damagedUnits,
        scrappedQuantity: scrappedUnits,
        creditableValue: creditableValue,
        acceptedTransactionId: acceptedMove?.transactionId,
        damagedTransactionId: damagedMove?.transactionId,
        scrappedTransactionId: scrappedMove?.transactionId,
      );
    });
  }

  /// Cancels a return by reversing its movements.
  ///
  /// The document itself is kept and marked cancelled; the goods are put back
  /// where they came from through compensating ledger entries, never by
  /// editing the originals.
  Future<void> cancelReturn(
    AuthenticatedUser actor, {
    required int returnId,
    required String reason,
  }) async {
    actor.require(Permissions.returnCreate, action: 'cancel returns');
    final cleanReason = requireText(reason, 'Reason', maxLength: 500);

    await _db.transaction(() async {
      final document = await _requireReturn(returnId);
      requireRule(
        document.status != ReturnStatus.cancelled,
        'Return ${document.returnNumber} has already been cancelled.',
        rule: 'return.cancel_once',
      );

      final credited = await _postedCreditTotal(returnId);
      requireRule(
        credited.isZero,
        'Return ${document.returnNumber} has ${credited.formatted()} of '
        'credit against it. Cancel the credit note first, so the goods and '
        'the money stay in step.',
        rule: 'return.cancel_requires_no_credit',
      );

      // Newest first: the disposition has to be undone before the receipt,
      // or the reversal would try to take goods out of an empty transit.
      for (final transactionId in [
        document.dispositionTransactionId,
        document.receiptTransactionId,
      ]) {
        if (transactionId == null) continue;
        await _ledger.cancelMovement(
          actor,
          transactionId: transactionId,
          reason: 'Return ${document.returnNumber} cancelled: $cleanReason',
        );
      }

      // Those units are returnable again.
      final items = await (_db.select(
        _db.returnItems,
      )..where((row) => row.returnId.equals(returnId))).get();
      for (final item in items) {
        if (item.originInvoiceItemId == null) continue;
        await _db.customUpdate(
          'UPDATE invoice_items SET returned_quantity = '
          'MAX(0, returned_quantity - ?) WHERE id = ?',
          variables: [
            Variable<int>(item.quantity),
            Variable<int>(item.originInvoiceItemId!),
          ],
          updates: {_db.invoiceItems},
        );
      }

      await (_db.update(
        _db.returnDocuments,
      )..where((r) => r.id.equals(returnId))).write(
        ReturnDocumentsCompanion(
          status: const Value(ReturnStatus.cancelled),
          cancelledAt: Value(_clock.nowUtc()),
          cancelReason: Value(cleanReason),
        ),
      );

      await _audit.record(
        action: AuditAction.cancel,
        summary:
            'Cancelled return ${document.returnNumber} '
            '(${document.totalQuantity} unit(s)): $cleanReason',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.returnDocument,
        entityId: returnId,
        before: {'status': document.status.name},
        after: {'status': ReturnStatus.cancelled.name},
      );
    });
  }

  // --- Credit notes -------------------------------------------------------

  /// Issues a posted credit note against an inspected return.
  ///
  /// [amount] defaults to what the inspection found creditable and can never
  /// exceed it: a credit note is evidence that goods came back, not a
  /// free-form discount.
  Future<int> issueCreditNote(
    AuthenticatedUser actor, {
    required int returnId,
    Money? amount,
    String? reason,
    String? notes,
    DateTime? issueDate,
  }) async {
    actor.require(Permissions.creditNoteIssue, action: 'issue credit notes');

    return _db.transaction(() async {
      final document = await _requireReturn(returnId);
      requireRule(
        document.status == ReturnStatus.inspected ||
            document.status == ReturnStatus.completed,
        document.status == ReturnStatus.cancelled
            ? 'Return ${document.returnNumber} has been cancelled.'
            : 'Return ${document.returnNumber} has not been inspected yet. '
                  'Credit follows inspection, so that nothing is credited '
                  'before somebody has looked at it.',
        rule: 'credit_note.requires_inspection',
      );

      final creditable = await _creditableValue(returnId);
      final alreadyCredited = await _postedCreditTotal(returnId);
      final available = creditable - alreadyCredited;
      requireRule(
        available.isPositive,
        creditable.isZero
            ? 'Nothing on ${document.returnNumber} qualifies for credit: '
                  'scrapped goods are written off, not credited.'
            : 'Return ${document.returnNumber} has already been credited in '
                  'full (${alreadyCredited.formatted()}).',
        rule: 'credit_note.nothing_left_to_credit',
      );

      final requested = amount ?? available;
      require(
        requested.isPositive,
        'A credit note must be for more than zero.',
        field: 'amount',
      );
      requireRule(
        requested <= available,
        'Only ${available.formatted()} can still be credited on '
        '${document.returnNumber}, but ${requested.formatted()} was entered.',
        rule: 'credit_note.within_returned_value',
      );

      final partyType = _partyTypeFor(document);
      final number = await _sequences.nextNumber(
        SequenceKeys.creditNote,
        prefixOverride: SequenceKeys.creditNote,
      );
      final now = _clock.nowUtc();

      final creditNoteId = await _db
          .into(_db.creditNotes)
          .insert(
            CreditNotesCompanion.insert(
              creditNoteNumber: number,
              status: const Value(InvoiceStatus.posted),
              issueDate: issueDate ?? now,
              returnId: Value(returnId),
              originInvoiceId: Value(document.originInvoiceId),
              partyType: partyType,
              agentId: Value(document.agentId),
              shopId: Value(document.shopId),
              amountCents: requested.cents,
              reason: Value(
                _clean(reason) ?? 'Goods returned on ${document.returnNumber}',
              ),
              notes: Value(_clean(notes)),
              createdByUserId: actor.id,
              createdAt: now,
              postedAt: Value(now),
            ),
          );

      // The return is done once it has been credited for everything it can be.
      if (requested == available) {
        await (_db.update(
          _db.returnDocuments,
        )..where((r) => r.id.equals(returnId))).write(
          ReturnDocumentsCompanion(
            status: const Value(ReturnStatus.completed),
            completedAt: Value(now),
          ),
        );
      }

      // A sales return, held to the party's account. It reduces revenue now;
      // it reduces what they owe only when it is applied to an invoice, the
      // same way a receipt does.
      await _finance.postCreditNoteIssued(
        actor: actor,
        creditNoteId: creditNoteId,
        creditNoteNumber: number,
        issueDate: issueDate ?? now,
        amount: requested,
        agentId: document.agentId,
        shopId: document.shopId,
      );

      await _audit.record(
        action: AuditAction.post,
        summary:
            'Credit note $number for ${requested.formatted()} against '
            '${document.returnNumber}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.creditNote,
        entityId: creditNoteId,
        after: {
          'creditNoteNumber': number,
          'amountCents': requested.cents,
          'returnNumber': document.returnNumber,
          'partyType': partyType.name,
        },
      );

      return creditNoteId;
    });
  }

  /// Offsets part of a credit note against a posted invoice.
  ///
  /// Deliberately the same shape as allocating a payment: the application is
  /// its own row, so the credit can be spread over several invoices and can be
  /// withdrawn again without anything being overwritten.
  Future<void> applyToInvoice(
    AuthenticatedUser actor, {
    required int creditNoteId,
    required int invoiceId,
    required Money amount,
  }) async {
    actor.require(Permissions.creditNoteIssue, action: 'apply credit notes');
    require(
      amount.isPositive,
      'An amount applied to an invoice must be more than zero.',
      field: 'amount',
    );

    await _db.transaction(() async {
      final note = await _requireCreditNote(creditNoteId);
      requireRule(
        note.status == InvoiceStatus.posted,
        'Credit note ${note.creditNoteNumber} is ${note.status.name} and '
        'cannot be applied.',
        rule: 'credit_note.apply_posted_only',
      );

      final remaining = Money(note.amountCents) - Money(note.appliedCents);
      requireRule(
        amount <= remaining,
        remaining.isZero
            ? 'Credit note ${note.creditNoteNumber} has already been used in '
                  'full.'
            : 'Only ${remaining.formatted()} is left on '
                  '${note.creditNoteNumber}, but ${amount.formatted()} was '
                  'entered.',
        rule: 'credit_note.no_over_application',
      );

      final invoice = requireFound(
        await (_db.select(
          _db.invoices,
        )..where((i) => i.id.equals(invoiceId))).getSingleOrNull(),
        'That invoice no longer exists.',
      );
      requireRule(
        invoice.status == InvoiceStatus.posted,
        'Invoice ${invoice.invoiceNumber} is ${invoice.status.name} and '
        'cannot have credit applied to it.',
        rule: 'credit_note.invoice_posted_only',
      );
      _assertSameParty(note, invoice);

      final room = await _invoiceRoom(invoiceId);
      requireRule(
        amount <= room,
        room.isZero
            ? 'Invoice ${invoice.invoiceNumber} is already fully covered.'
            : 'Only ${room.formatted()} can still be applied to '
                  '${invoice.invoiceNumber}, but ${amount.formatted()} was '
                  'entered.',
        rule: 'credit_note.no_over_allocation',
      );

      await _db
          .into(_db.creditNoteApplications)
          .insert(
            CreditNoteApplicationsCompanion.insert(
              creditNoteId: creditNoteId,
              invoiceId: invoiceId,
              amountCents: amount.cents,
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
            ),
          );
      await _refreshApplied(creditNoteId);

      await _finance.postCreditApplied(
        actor: actor,
        creditNoteId: creditNoteId,
        creditNoteNumber: note.creditNoteNumber,
        invoiceNumber: invoice.invoiceNumber,
        invoiceKind: invoice.kind,
        entryDate: _clock.nowUtc(),
        amount: amount,
        agentId: invoice.agentId,
        shopId: invoice.shopId,
      );

      await _audit.record(
        action: AuditAction.update,
        summary:
            'Applied ${amount.formatted()} of ${note.creditNoteNumber} to '
            '${invoice.invoiceNumber}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.creditNote,
        entityId: creditNoteId,
        after: {
          'invoiceNumber': invoice.invoiceNumber,
          'amountCents': amount.cents,
        },
      );
    });
  }

  /// Withdraws one application, putting the credit back in the party's hands.
  ///
  /// Recorded as an opposing row rather than a deletion, so the invoice's
  /// history still shows that the credit was once applied.
  Future<void> withdrawApplication(
    AuthenticatedUser actor, {
    required int applicationId,
    required String reason,
  }) async {
    actor.require(Permissions.creditNoteIssue, action: 'withdraw credit');
    final cleanReason = requireText(reason, 'Reason', maxLength: 300);

    await _db.transaction(() async {
      final application = requireFound(
        await (_db.select(
          _db.creditNoteApplications,
        )..where((a) => a.id.equals(applicationId))).getSingleOrNull(),
        'That credit application no longer exists.',
      );
      requireRule(
        application.amountCents > 0,
        'That row is already a withdrawal.',
        rule: 'credit_note.withdraw_positive_only',
      );

      final note = await _requireCreditNote(application.creditNoteId);
      final invoice = requireFound(
        await (_db.select(
          _db.invoices,
        )..where((i) => i.id.equals(application.invoiceId))).getSingleOrNull(),
        'That invoice no longer exists.',
      );

      await _db
          .into(_db.creditNoteApplications)
          .insert(
            CreditNoteApplicationsCompanion.insert(
              creditNoteId: application.creditNoteId,
              invoiceId: application.invoiceId,
              amountCents: -application.amountCents,
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
            ),
          );
      await _refreshApplied(application.creditNoteId);

      await _finance.postCreditApplied(
        actor: actor,
        creditNoteId: application.creditNoteId,
        creditNoteNumber: note.creditNoteNumber,
        invoiceNumber: invoice.invoiceNumber,
        invoiceKind: invoice.kind,
        entryDate: _clock.nowUtc(),
        amount: Money(application.amountCents),
        isWithdrawal: true,
        agentId: invoice.agentId,
        shopId: invoice.shopId,
      );

      await _audit.record(
        action: AuditAction.reverse,
        summary:
            'Withdrew ${Money(application.amountCents).formatted()} of '
            '${note.creditNoteNumber} from ${invoice.invoiceNumber}: '
            '$cleanReason',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.creditNote,
        entityId: application.creditNoteId,
        before: {'appliedToInvoice': invoice.invoiceNumber},
        after: {'withdrawnCents': application.amountCents},
      );
    });
  }

  /// Cancels a credit note that has not been used.
  Future<void> cancelCreditNote(
    AuthenticatedUser actor, {
    required int creditNoteId,
    required String reason,
  }) async {
    actor.require(Permissions.creditNoteIssue, action: 'cancel credit notes');
    final cleanReason = requireText(reason, 'Reason', maxLength: 500);

    await _db.transaction(() async {
      final note = await _requireCreditNote(creditNoteId);
      requireRule(
        note.status == InvoiceStatus.posted,
        'Credit note ${note.creditNoteNumber} is already '
        '${note.status.name}.',
        rule: 'credit_note.cancel_posted_only',
      );
      requireRule(
        note.appliedCents == 0,
        '${Money(note.appliedCents).formatted()} of '
        '${note.creditNoteNumber} has already been applied. Withdraw it from '
        'the invoices first.',
        rule: 'credit_note.cancel_requires_no_applications',
      );

      await (_db.update(
        _db.creditNotes,
      )..where((c) => c.id.equals(creditNoteId))).write(
        CreditNotesCompanion(
          status: const Value(InvoiceStatus.cancelled),
          cancelledAt: Value(_clock.nowUtc()),
          cancelReason: Value(cleanReason),
        ),
      );

      // The return can be credited again, so it is no longer finished.
      if (note.returnId != null) {
        final document = await _requireReturn(note.returnId!);
        if (document.status == ReturnStatus.completed) {
          final creditable = await _creditableValue(note.returnId!);
          if (creditable.isPositive) {
            await (_db.update(
              _db.returnDocuments,
            )..where((r) => r.id.equals(note.returnId!))).write(
              const ReturnDocumentsCompanion(
                status: Value(ReturnStatus.inspected),
                completedAt: Value(null),
              ),
            );
          }
        }
      }

      // The sales return is taken back out. Applications have to be withdrawn
      // first, so there is only ever the issue batch to mirror here.
      for (final batchId in {
        for (final row in await _finance.entriesForSource(
          sourceKind: EntityKind.creditNote,
          sourceId: creditNoteId,
        ))
          if (!row.isReversal) row.batchId,
      }) {
        await _finance.reverse(
          actor: actor,
          batchId: batchId,
          reason: 'Credit note ${note.creditNoteNumber} cancelled',
        );
      }

      await _audit.record(
        action: AuditAction.cancel,
        summary:
            'Cancelled credit note ${note.creditNoteNumber} '
            '(${Money(note.amountCents).formatted()}): $cleanReason',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.creditNote,
        entityId: creditNoteId,
        before: {'status': note.status.name},
        after: {'status': InvoiceStatus.cancelled.name},
      );
    });
  }

  // --- Reads used while composing a return --------------------------------

  /// The lines of a posted invoice with how much of each is still returnable.
  ///
  /// [ReturnableInvoiceLine.effectiveUnitPrice] is what the party actually
  /// paid per unit: the billed price less the line discount, less the line's
  /// share of any invoice-level discount. Crediting at the headline price
  /// would hand back more money than was ever taken.
  Future<List<ReturnableInvoiceLine>> returnableLines(int invoiceId) async {
    final invoice = requireFound(
      await (_db.select(
        _db.invoices,
      )..where((i) => i.id.equals(invoiceId))).getSingleOrNull(),
      'That invoice no longer exists.',
    );
    requireRule(
      invoice.status == InvoiceStatus.posted,
      'Invoice ${invoice.invoiceNumber} is ${invoice.status.name}, so nothing '
      'can be returned against it.',
      rule: 'return.origin_invoice_posted_only',
    );

    final items =
        await (_db.select(_db.invoiceItems)
              ..where((i) => i.invoiceId.equals(invoiceId))
              ..orderBy([(i) => OrderingTerm.asc(i.lineNumber)]))
            .get();

    final itemNetTotal = items.map((item) => Money(item.netCents)).sum;
    final headerDiscount = Money(invoice.invoiceDiscountCents);

    return [
      for (final item in items)
        ReturnableInvoiceLine(
          invoiceItemId: item.id,
          lineNumber: item.lineNumber,
          productId: item.productId,
          productName: item.productNameSnapshot,
          sku: item.skuSnapshot,
          billedQuantity: item.quantity,
          returnedQuantity: item.returnedQuantity,
          effectiveUnitPrice: _effectiveUnitPrice(
            lineNet: Money(item.netCents),
            lineQuantity: item.quantity,
            itemNetTotal: itemNetTotal,
            headerDiscount: headerDiscount,
          ),
        ),
    ];
  }

  // --- Internals ----------------------------------------------------------

  /// What one unit of a line really cost, after both discount levels.
  static Money _effectiveUnitPrice({
    required Money lineNet,
    required int lineQuantity,
    required Money itemNetTotal,
    required Money headerDiscount,
  }) {
    if (lineQuantity <= 0) return Money.zero;
    var net = lineNet;
    if (headerDiscount.isPositive && itemNetTotal.isPositive) {
      final share = Money(
        Money.divideRounded(
          headerDiscount.cents * lineNet.cents,
          itemNetTotal.cents,
        ),
      );
      net -= share;
    }
    return Money(Money.divideRounded(net.cents, lineQuantity));
  }

  Future<List<_ResolvedReturnLine>> _resolveLines(ReturnDraft draft) async {
    final returnable = draft.originInvoiceId == null
        ? const <ReturnableInvoiceLine>[]
        : await returnableLines(draft.originInvoiceId!);
    final byItemId = {for (final line in returnable) line.invoiceItemId: line};

    final seenInvoiceItems = <int>{};
    final seenProducts = <int>{};
    final resolved = <_ResolvedReturnLine>[];

    for (final line in draft.lines) {
      final product = requireFound(
        await (_db.select(
          _db.products,
        )..where((p) => p.id.equals(line.productId))).getSingleOrNull(),
        'One of the returned products no longer exists.',
      );

      ReturnableInvoiceLine? origin;
      if (line.originInvoiceItemId != null) {
        requireRule(
          draft.originInvoiceId != null,
          'A return line cannot point at an invoice line when the return '
          'itself is not against an invoice.',
          rule: 'return.line_origin_needs_invoice',
        );
        final matched = requireFound<ReturnableInvoiceLine>(
          byItemId[line.originInvoiceItemId],
          'One of the returned lines is not on invoice '
          '#${draft.originInvoiceId}.',
        );
        origin = matched;
        requireRule(
          matched.productId == line.productId,
          'Line for "${product.name}" points at an invoice line for '
          '"${matched.productName}".',
          rule: 'return.line_product_matches_invoice',
        );
        requireRule(
          seenInvoiceItems.add(matched.invoiceItemId),
          '"${product.name}" is on the return twice against the same invoice '
          'line. Combine them.',
          rule: 'return.one_line_per_invoice_line',
        );
        requireRule(
          line.quantity <= matched.returnableQuantity,
          matched.returnableQuantity <= 0
              ? 'All ${matched.billedQuantity} unit(s) of "${product.name}" '
                    'billed on that invoice have already been returned.'
              : 'Only ${matched.returnableQuantity} of the '
                    '${matched.billedQuantity} unit(s) of "${product.name}" '
                    'billed on that invoice can still be returned, but '
                    '${line.quantity} were entered.',
          rule: 'return.within_billed_quantity',
        );
      } else {
        requireRule(
          seenProducts.add(line.productId),
          '"${product.name}" is on the return twice. Combine the lines.',
          rule: 'return.one_line_per_product',
        );
      }

      // The billed price wins whenever there is one: a credit note repays what
      // was charged, not what somebody types today.
      final unitPrice =
          origin?.effectiveUnitPrice ?? line.unitPrice ?? Money.zero;

      resolved.add(
        _ResolvedReturnLine(
          productId: line.productId,
          productName: product.name,
          sku: product.sku,
          quantity: line.quantity,
          unitPrice: unitPrice,
          lineValue: unitPrice * line.quantity,
          originInvoiceItemId: origin?.invoiceItemId,
          notes: _clean(line.notes),
        ),
      );
    }

    return resolved;
  }

  /// Checks the two locations suit the route before anything is written.
  void _assertRouteLocations(
    ReturnRoute route,
    InventoryLocation from,
    InventoryLocation to,
  ) {
    void expect(LocationKind source, LocationKind destination) {
      requireRule(
        from.kind == source,
        'A ${returnRouteLabel(route).toLowerCase()} return must come from '
        '${_kindLabel(source)}, but "${from.name}" is '
        '${_kindLabel(from.kind)}.',
        rule: 'return.route_source_kind',
      );
      requireRule(
        to.kind == destination,
        'A ${returnRouteLabel(route).toLowerCase()} return must go to '
        '${_kindLabel(destination)}, but "${to.name}" is '
        '${_kindLabel(to.kind)}.',
        rule: 'return.route_destination_kind',
      );
    }

    switch (route) {
      case ReturnRoute.customerToShop:
        expect(LocationKind.customer, LocationKind.shop);
      case ReturnRoute.shopToAgent:
        expect(LocationKind.shop, LocationKind.agent);
      case ReturnRoute.agentToWarehouse:
        expect(LocationKind.agent, LocationKind.warehouse);
      case ReturnRoute.shopToWarehouse:
        expect(LocationKind.shop, LocationKind.warehouse);
    }
  }

  Future<InventoryLocation> _requireLocation(int id, String role) async {
    final row = await (_db.select(
      _db.inventoryLocations,
    )..where((l) => l.id.equals(id))).getSingleOrNull();
    return requireFound(row, 'The location the goods were $role is missing.');
  }

  Future<ReturnDocument> _requireReturn(int returnId) async {
    final row = await (_db.select(
      _db.returnDocuments,
    )..where((r) => r.id.equals(returnId))).getSingleOrNull();
    return requireFound(row, 'That return no longer exists.');
  }

  Future<CreditNote> _requireCreditNote(int creditNoteId) async {
    final row = await (_db.select(
      _db.creditNotes,
    )..where((c) => c.id.equals(creditNoteId))).getSingleOrNull();
    return requireFound(row, 'That credit note no longer exists.');
  }

  /// Value of the inspected units that qualify for credit.
  Future<Money> _creditableValue(int returnId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(unit_price_cents * '
          '(accepted_quantity + damaged_quantity)), 0) AS creditable '
          'FROM return_items WHERE return_id = ?',
          variables: [Variable<int>(returnId)],
          readsFrom: {_db.returnItems},
        )
        .getSingle();
    return Money(row.read<int>('creditable'));
  }

  /// Credit already raised against a return, cancelled notes excluded.
  Future<Money> _postedCreditTotal(int returnId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(amount_cents), 0) AS credited '
          'FROM credit_notes WHERE return_id = ? AND status = ?',
          variables: [
            Variable<int>(returnId),
            Variable<String>(InvoiceStatus.posted.name),
          ],
          readsFrom: {_db.creditNotes},
        )
        .getSingle();
    return Money(row.read<int>('credited'));
  }

  /// What may still be put against an invoice, counting pending payments and
  /// posted credit the same way the payment service does, so a cheque in
  /// clearing and a credit note cannot both claim the same balance.
  Future<Money> _invoiceRoom(int invoiceId) async {
    final row = await _db
        .customSelect(
          '''
      SELECT
        i.net_total_cents AS net,
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
        .getSingle();

    final remaining =
        Money(row.read<int>('net')) -
        Money(row.read<int>('promised')) -
        Money(row.read<int>('credited'));
    return remaining.isPositive ? remaining : Money.zero;
  }

  /// Recomputes the applied cache from the application rows, so the cache can
  /// never drift away from what actually happened.
  Future<void> _refreshApplied(int creditNoteId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(amount_cents), 0) AS applied '
          'FROM credit_note_applications WHERE credit_note_id = ?',
          variables: [Variable<int>(creditNoteId)],
          readsFrom: {_db.creditNoteApplications},
        )
        .getSingle();

    await (_db.update(
      _db.creditNotes,
    )..where((c) => c.id.equals(creditNoteId))).write(
      CreditNotesCompanion(appliedCents: Value(row.read<int>('applied'))),
    );
  }

  /// A credit note belongs to one party, and so does an invoice. Applying one
  /// to the other's balance would move money between two people's accounts.
  void _assertSameParty(CreditNote note, Invoice invoice) {
    requireRule(
      note.agentId == null || note.agentId == invoice.agentId,
      'Credit note ${note.creditNoteNumber} belongs to a different agent from '
      'invoice ${invoice.invoiceNumber}.',
      rule: 'credit_note.same_party',
    );
    requireRule(
      note.shopId == null || note.shopId == invoice.shopId,
      'Credit note ${note.creditNoteNumber} belongs to a different shop from '
      'invoice ${invoice.invoiceNumber}.',
      rule: 'credit_note.same_party',
    );
  }

  static PartyType _partyTypeFor(ReturnDocument document) {
    if (document.shopId != null) return PartyType.shop;
    if (document.agentId != null) return PartyType.agent;
    return PartyType.customer;
  }

  static StockDocumentType _documentTypeFor(ReturnRoute route) =>
      switch (route) {
        ReturnRoute.customerToShop => StockDocumentType.customerToShopReturn,
        ReturnRoute.shopToAgent => StockDocumentType.shopToAgentReturn,
        ReturnRoute.agentToWarehouse =>
          StockDocumentType.agentToWarehouseReturn,
        ReturnRoute.shopToWarehouse => StockDocumentType.shopToWarehouseReturn,
      };

  static String _kindLabel(LocationKind kind) => switch (kind) {
    LocationKind.warehouse => 'a warehouse',
    LocationKind.agent => 'an agent',
    LocationKind.shop => 'a shop',
    LocationKind.damaged => 'the damaged store',
    LocationKind.supplier => 'suppliers',
    LocationKind.customer => 'retail customers',
    LocationKind.adjustment => 'adjustments',
    LocationKind.inTransit => 'goods in transit',
  };

  static String? _mergeNotes(String? existing, String? addition) {
    final extra = _clean(addition);
    if (extra == null) return existing;
    final base = _clean(existing);
    final merged = base == null ? extra : '$base\nInspection: $extra';
    return merged.length > 1000 ? merged.substring(0, 1000) : merged;
  }

  static String? _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}

/// A return line after validation, with its snapshots resolved.
class _ResolvedReturnLine {
  const _ResolvedReturnLine({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unitPrice,
    required this.lineValue,
    this.originInvoiceItemId,
    this.notes,
  });

  final int productId;
  final String productName;
  final String sku;
  final int quantity;
  final Money unitPrice;
  final Money lineValue;
  final int? originInvoiceItemId;
  final String? notes;
}
