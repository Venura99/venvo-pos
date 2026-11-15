import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/sequence_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../../finance/data/financial_ledger_service.dart';
import '../../inventory/data/stock_ledger_service.dart';
import '../../inventory/domain/stock_models.dart';
import '../../payments/data/payment_service.dart';
import '../../payments/domain/payment_models.dart';
import '../domain/invoice_models.dart';
import 'package:json_annotation/json_annotation.dart';

part 'invoice_service.g.dart';

/// Raises invoices.
///
/// An invoice is where money becomes owed. A stock document is where goods
/// move. They are deliberately separate records, linked through
/// [InvoiceStockLinkage]:
///
/// * [NoStockMovement] - a charge on its own.
/// * [BillExistingDelivery] - bills goods already delivered on a posted stock
///   document. The document is untouched; this is the explicit decision that
///   turns a delivery note into revenue.
/// * [MoveStockWithInvoice] - posts the movement and the invoice in one
///   transaction, which is what a retail sale needs.
///
/// Discounts are applied in a fixed order: per-line first, then the
/// invoice-level discount on what is left. Both are checked against the
/// configured ceilings, and exceeding one requires an explicit permission and
/// is recorded.
class InvoiceService {
  InvoiceService({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    required SequenceService sequences,
    required SettingsService settings,
    required StockLedgerService ledger,
    required PaymentService payments,
    required FinancialLedgerService finance,
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _sequences = sequences,
       _settings = settings,
       _ledger = ledger,
       _payments = payments,
       _finance = finance;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final SequenceService _sequences;
  final SettingsService _settings;
  final StockLedgerService _ledger;
  final PaymentService _payments;
  final FinancialLedgerService _finance;

  /// Raises and posts an invoice.
  Future<InvoicePostResult> postInvoice(
    AuthenticatedUser actor,
    InvoiceRequest request,
  ) async {
    actor.require(Permissions.invoiceCreate, action: 'raise invoices');
    actor.require(Permissions.invoicePost, action: 'post invoices');
    if (request.kind == InvoiceKind.retailSale) {
      actor.require(
        Permissions.retailSaleRecord,
        action: 'record a retail sale',
      );
    }

    _validateLines(request);
    await _validateDiscountPermissions(actor, request);

    return _db.transaction(() async {
      final party = await _resolveParty(request);
      final totals = request.totals;

      // The goods side, where there is one.
      final stock = await _applyStockLinkage(actor, request);

      final sequenceKey = switch (request.kind) {
        InvoiceKind.agentInvoice => SequenceKeys.agentInvoice,
        InvoiceKind.shopInvoice => SequenceKeys.shopInvoice,
        InvoiceKind.retailSale => SequenceKeys.retailSale,
      };
      final invoiceNumber = await _sequences.nextNumber(sequenceKey);
      final now = _clock.nowUtc();
      final invoiceDate = request.invoiceDate ?? now;

      final exceeded = await _discountExceedsCeiling(request);

      final invoiceId = await _db
          .into(_db.invoices)
          .insert(
            InvoicesCompanion.insert(
              invoiceNumber: invoiceNumber,
              kind: request.kind,
              status: const Value(InvoiceStatus.posted),
              invoiceDate: invoiceDate,
              dueDate: Value(request.dueDate),
              partyType: request.partyType,
              agentId: Value(request.agentId ?? party.agentId),
              shopId: Value(request.shopId),
              customerName: Value(_clean(request.customerName)),
              customerPhone: Value(_clean(request.customerPhone)),
              stockTransactionId: Value(stock?.transactionId),
              grossTotalCents: Value(totals.gross.cents),
              itemDiscountTotalCents: Value(totals.itemDiscount.cents),
              invoiceDiscountType: Value(request.invoiceDiscountType),
              invoiceDiscountValue: Value(request.invoiceDiscountValue),
              invoiceDiscountCents: Value(totals.invoiceDiscount.cents),
              netTotalCents: Value(totals.net.cents),
              discountReason: Value(_clean(request.discountReason)),
              discountApprovedByUserId: Value(exceeded ? actor.id : null),
              notes: Value(_clean(request.notes)),
              createdByUserId: actor.id,
              createdAt: now,
              postedAt: Value(now),
              postedByUserId: Value(actor.id),
            ),
          );

      // Lines, with their cost snapshotted for gross profit.
      var costTotal = Money.zero;
      var lineNumber = 0;
      for (final line in request.lines) {
        lineNumber++;
        final product = await _requireProduct(line.productId);
        final unitCost = await _resolveUnitCost(
          product: product,
          request: request,
        );
        costTotal += unitCost * line.quantity;

        final itemId = await _db
            .into(_db.invoiceItems)
            .insert(
              InvoiceItemsCompanion.insert(
                invoiceId: invoiceId,
                lineNumber: lineNumber,
                productId: product.id,
                productNameSnapshot: product.name,
                skuSnapshot: product.sku,
                quantity: line.quantity,
                unitPriceCents: line.unitPrice.cents,
                grossCents: line.gross.cents,
                discountType: Value(line.discountType),
                discountValue: Value(line.discountValue),
                discountCents: Value(line.discount.cents),
                netCents: line.net.cents,
                unitCostSnapshotCents: Value(unitCost.cents),
                notes: Value(_clean(line.notes)),
              ),
            );

        // Every discount is recorded, whatever its size, so the discount
        // report can be produced per user, reason and period without
        // scanning invoices.
        if (!line.discount.isZero) {
          await _recordDiscount(
            actor: actor,
            invoiceId: invoiceId,
            invoiceItemId: itemId,
            productId: product.id,
            scope: DiscountScope.item,
            type: line.discountType,
            value: line.discountValue,
            amount: line.discount,
            base: line.gross,
            reason: request.discountReason,
            exceededLimit: await _itemDiscountExceedsCeiling(line),
          );
        }
      }

      if (!totals.invoiceDiscount.isZero) {
        await _recordDiscount(
          actor: actor,
          invoiceId: invoiceId,
          scope: DiscountScope.invoice,
          type: request.invoiceDiscountType,
          value: request.invoiceDiscountValue,
          amount: totals.invoiceDiscount,
          base: totals.afterItemDiscounts,
          reason: request.discountReason,
          exceededLimit: exceeded,
        );
      }

      await (_db.update(_db.invoices)..where((i) => i.id.equals(invoiceId)))
          .write(InvoicesCompanion(costTotalCents: Value(costTotal.cents)));

      // Revenue, the discount given and the cost of the goods, all in the
      // same transaction as the invoice itself. The receivable is debited
      // here; any money taken at the counter is accounted for by the payment
      // below, so cash is never recognised twice.
      await _finance.postInvoice(
        actor: actor,
        invoiceId: invoiceId,
        invoiceNumber: invoiceNumber,
        kind: request.kind,
        invoiceDate: invoiceDate,
        gross: totals.gross,
        discount: totals.itemDiscount + totals.invoiceDiscount,
        net: totals.net,
        cost: costTotal,
        agentId: request.agentId ?? party.agentId,
        shopId: request.shopId,
      );

      // Money taken at the counter, if any.
      PaymentResult? payment;
      final immediate = request.payment;
      if (immediate != null) {
        payment = await _recordImmediatePayment(
          actor: actor,
          request: request,
          invoiceId: invoiceId,
          invoiceNet: totals.net,
          immediate: immediate,
        );
      }

      await _audit.record(
        action: AuditAction.post,
        summary:
            'Posted $invoiceNumber: ${invoiceKindLabel(request.kind)} '
            'on ${party.name} for ${totals.net.formatted()}'
            '${totals.totalDiscount.isZero ? '' : ' after '
                      '${totals.totalDiscount.formatted()} discount'}'
            '${payment == null ? '' : ', ${payment.amount.formatted()} '
                      'received by ${paymentMethodLabel(immediate!.method)}'}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.invoice,
        entityId: invoiceId,
        after: {
          'invoiceNumber': invoiceNumber,
          'kind': request.kind.name,
          'grossCents': totals.gross.cents,
          'itemDiscountCents': totals.itemDiscount.cents,
          'invoiceDiscountCents': totals.invoiceDiscount.cents,
          'netCents': totals.net.cents,
          'costCents': costTotal.cents,
          if (stock != null) 'stockDocument': stock.documentNumber,
          if (exceeded) 'discountCeilingExceeded': true,
        },
      );

      if (exceeded) {
        await _audit.record(
          action: AuditAction.permissionOverride,
          summary:
              'Authorised a discount above the configured ceiling on '
              '$invoiceNumber: ${totals.invoiceDiscount.formatted()} '
              '(${formatBps(totals.invoiceDiscountBps)}).'
              '${request.discountReason == null ? '' : ' Reason: '
                        '${request.discountReason}'}',
          userId: actor.id,
          username: actor.username,
          entityKind: EntityKind.invoice,
          entityId: invoiceId,
        );
      }

      return InvoicePostResult(
        invoiceId: invoiceId,
        invoiceNumber: invoiceNumber,
        totals: totals,
        cost: costTotal,
        stockDocumentNumber: stock?.documentNumber,
        stockTransactionId: stock?.transactionId,
        payment: payment,
      );
    });
  }

  /// Bills a posted stock document that has not been invoiced yet.
  ///
  /// The lines and prices come from the delivery note, so what is billed is
  /// what was delivered. This is the step that turns a transfer into revenue.
  Future<InvoicePostResult> billDelivery(
    AuthenticatedUser actor, {
    required int stockTransactionId,
    DateTime? invoiceDate,
    DateTime? dueDate,
    DiscountType invoiceDiscountType = DiscountType.none,
    int invoiceDiscountValue = 0,
    String? discountReason,
    String? notes,
    ImmediatePayment? payment,
    Map<int, Money>? priceOverrides,
  }) async {
    final document = requireFound(
      await (_db.select(
        _db.stockTransactions,
      )..where((t) => t.id.equals(stockTransactionId))).getSingleOrNull(),
      'That stock document no longer exists.',
    );

    requireRule(
      document.status == StockDocumentStatus.posted,
      'Only a posted stock document can be billed. '
      '${document.documentNumber} is ${document.status.name}.',
      rule: 'invoice.bill_posted_document_only',
    );

    final existing = await (_db.select(
      _db.invoices,
    )..where((i) => i.stockTransactionId.equals(stockTransactionId))).get();
    final live = existing
        .where((i) => i.status != InvoiceStatus.cancelled)
        .toList();
    requireRule(
      live.isEmpty,
      '${document.documentNumber} has already been billed on '
      '${live.firstOrNull?.invoiceNumber}.',
      rule: 'invoice.bill_document_once',
    );

    final kind = switch (document.documentType) {
      StockDocumentType.warehouseToAgent => InvoiceKind.agentInvoice,
      StockDocumentType.agentToShop ||
      StockDocumentType.warehouseToShop => InvoiceKind.shopInvoice,
      _ => throw BusinessRuleFailure(
        '${stockDocumentTypeLabel(document.documentType)} documents are not '
        'billable. Only transfers to an agent or a shop are.',
        rule: 'invoice.billable_document_types',
      ),
    };

    final items =
        await (_db.select(_db.stockTransactionItems)
              ..where((i) => i.transactionId.equals(stockTransactionId))
              ..orderBy([(i) => OrderingTerm.asc(i.lineNumber)]))
            .get();
    requireRule(
      items.isNotEmpty,
      'That stock document has no lines to bill.',
      rule: 'invoice.bill_requires_lines',
    );

    final lines = <InvoiceLineRequest>[];
    for (final item in items) {
      final price =
          priceOverrides?[item.productId] ??
          (item.unitPriceCents > 0
              ? Money(item.unitPriceCents)
              : await _wholesalePriceOf(item.productId));
      require(
        price.isPositive,
        'Set a price for "${item.productNameSnapshot}": the delivery note did '
        'not carry one.',
        field: 'unitPrice',
      );

      lines.add(
        InvoiceLineRequest(
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: price,
          // Discounts on the delivery note are carried onto the invoice.
          discountType: item.discountType,
          discountValue: item.discountValue,
        ),
      );
    }

    return postInvoice(
      actor,
      InvoiceRequest(
        kind: kind,
        lines: lines,
        agentId: document.agentId,
        shopId: document.shopId,
        invoiceDate: invoiceDate,
        dueDate: dueDate,
        invoiceDiscountType: invoiceDiscountType,
        invoiceDiscountValue: invoiceDiscountValue,
        discountReason: discountReason,
        stockLinkage: BillExistingDelivery(stockTransactionId),
        payment: payment,
        notes: notes,
      ),
    );
  }

  /// Cancels a posted invoice.
  ///
  /// The invoice and its lines stay exactly as they are; only the status and
  /// the cancellation details change. Money already received is *not* taken
  /// back - it was received - so its allocations are released and it becomes
  /// an unapplied advance for the party.
  ///
  /// Whether the goods come back is the **caller's** decision, through
  /// [reverseStockMovement], and it defaults to leaving them where they are.
  /// Cancelling a bill is not the same as un-shipping: the lorry may well have
  /// been, and reversing the movement would then invent stock the warehouse
  /// does not have.
  ///
  /// When the flag is set, the reversal applies to whatever stock document the
  /// invoice is linked to — **including a delivery that was posted
  /// separately**. There is no distinction here between a movement the invoice
  /// created and one it merely billed, so cancelling the bill for an existing
  /// delivery with the flag set does send those goods back. That is a real
  /// operation (the goods returned *and* the bill was wrong), but it is not
  /// the obvious reading of "cancel this invoice", which is exactly why the
  /// default is false.
  Future<InvoiceCancelResult> cancelInvoice(
    AuthenticatedUser actor, {
    required int invoiceId,
    required String reason,
    bool reverseStockMovement = false,
  }) async {
    actor.require(Permissions.invoiceCancel, action: 'cancel invoices');
    final cleanReason = requireText(reason, 'Reason', maxLength: 500);

    return _db.transaction(() async {
      final invoice = requireFound(
        await (_db.select(
          _db.invoices,
        )..where((i) => i.id.equals(invoiceId))).getSingleOrNull(),
        'That invoice no longer exists.',
      );
      requireRule(
        invoice.status == InvoiceStatus.posted,
        invoice.status == InvoiceStatus.cancelled
            ? 'That invoice has already been cancelled.'
            : 'Only a posted invoice can be cancelled.',
        rule: 'invoice.cancel_posted_only',
      );

      final releasedMoney = await _payments.releaseAllocationsForInvoice(
        actor: actor,
        invoiceId: invoiceId,
        reason: 'Invoice ${invoice.invoiceNumber} cancelled',
      );

      String? reversalNumber;
      final linkedTransactionId = invoice.stockTransactionId;
      if (reverseStockMovement && linkedTransactionId != null) {
        final reversal = await _ledger.cancelMovement(
          actor,
          transactionId: linkedTransactionId,
          reason: 'Invoice ${invoice.invoiceNumber} cancelled: $cleanReason',
        );
        reversalNumber = reversal.documentNumber;
      }

      await (_db.update(
        _db.invoices,
      )..where((i) => i.id.equals(invoiceId))).write(
        InvoicesCompanion(
          status: const Value(InvoiceStatus.cancelled),
          cancelledAt: Value(_clock.nowUtc()),
          cancelledByUserId: Value(actor.id),
          cancelReason: Value(cleanReason),
        ),
      );

      // The revenue, the discount and the cost of goods are all taken back
      // out by mirroring the batch the invoice posted. Any stock reversal and
      // any released allocation post their own reversals.
      for (final batchId in {
        for (final row in await _finance.entriesForSource(
          sourceKind: EntityKind.invoice,
          sourceId: invoiceId,
        ))
          row.batchId,
      }) {
        await _finance.reverse(
          actor: actor,
          batchId: batchId,
          reason: 'Invoice ${invoice.invoiceNumber} cancelled',
        );
      }

      await _audit.record(
        action: AuditAction.cancel,
        summary:
            'Cancelled ${invoice.invoiceNumber} '
            '(${Money(invoice.netTotalCents).formatted()}): $cleanReason'
            '${releasedMoney.isZero ? '' : '. ${releasedMoney.formatted()} of '
                      'received money is now an unapplied advance'}'
            '${reversalNumber == null ? '' : '. Stock reversed by '
                      '$reversalNumber'}',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.invoice,
        entityId: invoiceId,
        before: {'status': InvoiceStatus.posted.name},
        after: {
          'status': InvoiceStatus.cancelled.name,
          'releasedMoneyCents': releasedMoney.cents,
          if (reversalNumber != null) 'stockReversal': reversalNumber,
        },
      );

      return InvoiceCancelResult(
        invoiceNumber: invoice.invoiceNumber,
        releasedMoney: releasedMoney,
        stockReversalDocumentNumber: reversalNumber,
      );
    });
  }

  // --- Rules --------------------------------------------------------------

  void _validateLines(InvoiceRequest request) {
    require(
      request.lines.isNotEmpty,
      'Add at least one line to the invoice.',
      field: 'lines',
    );

    final seen = <int>{};
    for (final line in request.lines) {
      require(
        line.quantity > 0,
        'Every line needs a quantity of at least 1.',
        field: 'quantity',
      );
      require(
        line.unitPrice.isPositive,
        'Every line needs a unit price above zero.',
        field: 'unitPrice',
      );
      requireRule(
        seen.add(line.productId),
        'The same product is on more than one line. Combine them into a '
        'single line.',
        rule: 'invoice.no_duplicate_products',
      );
      if (line.discountType == DiscountType.percentage) {
        require(
          line.discountValue >= 0 && line.discountValue <= Money.bpsScale,
          'A line discount must be between 0% and 100%.',
          field: 'discountValue',
        );
      }
      if (line.discountType == DiscountType.fixedAmount) {
        require(
          line.discountValue >= 0,
          'A line discount cannot be negative.',
          field: 'discountValue',
        );
      }
    }

    if (request.invoiceDiscountType == DiscountType.percentage) {
      require(
        request.invoiceDiscountValue >= 0 &&
            request.invoiceDiscountValue <= Money.bpsScale,
        'An invoice discount must be between 0% and 100%.',
        field: 'invoiceDiscountValue',
      );
    }

    final totals = request.totals;
    require(
      totals.net.isPositive || totals.net.isZero,
      'The discounts come to more than the invoice value.',
      field: 'invoiceDiscountValue',
    );

    final immediate = request.payment;
    if (immediate != null) {
      require(
        immediate.amount.isPositive,
        'A payment taken with the invoice must be more than zero.',
        field: 'payment',
      );
      require(
        immediate.amount <= totals.net,
        'The payment of ${immediate.amount.formatted()} is more than the '
        'invoice total of ${totals.net.formatted()}. Record the excess as a '
        'separate advance.',
        field: 'payment',
      );
      if (immediate.isCheque) {
        requireText(immediate.chequeNumber, 'Cheque number', maxLength: 32);
        requireText(immediate.bankName, 'Bank name', maxLength: 120);
        requireFound(immediate.chequeDate, 'Enter the cheque date.');
      }
    }
  }

  /// Checks that the user may grant the discounts on the request at all, and
  /// that they may exceed a ceiling if they are doing so.
  Future<void> _validateDiscountPermissions(
    AuthenticatedUser actor,
    InvoiceRequest request,
  ) async {
    final hasItemDiscount = request.lines.any((line) => !line.discount.isZero);
    if (hasItemDiscount) {
      actor.require(
        Permissions.discountApplyItem,
        action: 'apply a discount to a line',
      );
    }
    if (!request.totals.invoiceDiscount.isZero) {
      actor.require(
        Permissions.discountApplyInvoice,
        action: 'apply a discount to an invoice',
      );
    }

    final maxItemBps = await _settings.maxItemDiscountBps;
    for (final line in request.lines) {
      if (line.discount.isZero) continue;
      if (line.effectiveDiscountBps > maxItemBps) {
        actor.require(
          Permissions.discountExceedLimit,
          action:
              'grant a line discount above '
              '${formatBps(maxItemBps)}',
        );
        require(
          (request.discountReason ?? '').trim().isNotEmpty,
          'A discount above the ceiling needs a reason.',
          field: 'discountReason',
        );
      }
    }

    final maxInvoiceBps = await _settings.maxInvoiceDiscountBps;
    final totals = request.totals;
    if (!totals.invoiceDiscount.isZero &&
        totals.invoiceDiscountBps > maxInvoiceBps) {
      actor.require(
        Permissions.discountExceedLimit,
        action: 'grant an invoice discount above ${formatBps(maxInvoiceBps)}',
      );
      require(
        (request.discountReason ?? '').trim().isNotEmpty,
        'A discount above the ceiling needs a reason.',
        field: 'discountReason',
      );
    }
  }

  Future<bool> _discountExceedsCeiling(InvoiceRequest request) async {
    final totals = request.totals;
    if (totals.invoiceDiscount.isZero) return false;
    return totals.invoiceDiscountBps > await _settings.maxInvoiceDiscountBps;
  }

  Future<bool> _itemDiscountExceedsCeiling(InvoiceLineRequest line) async {
    if (line.discount.isZero) return false;
    return line.effectiveDiscountBps > await _settings.maxItemDiscountBps;
  }

  Future<void> _recordDiscount({
    required AuthenticatedUser actor,
    required int invoiceId,
    required DiscountScope scope,
    required DiscountType type,
    required int value,
    required Money amount,
    required Money base,
    required bool exceededLimit,
    int? invoiceItemId,
    int? productId,
    String? reason,
  }) async {
    await _db
        .into(_db.discountRecords)
        .insert(
          DiscountRecordsCompanion.insert(
            scope: scope,
            invoiceId: invoiceId,
            invoiceItemId: Value(invoiceItemId),
            productId: Value(productId),
            discountType: type,
            discountValue: value,
            discountCents: amount.cents,
            baseAmountCents: base.cents,
            reason: Value(_clean(reason)),
            exceededLimit: Value(exceededLimit),
            grantedByUserId: actor.id,
            approvedByUserId: Value(exceededLimit ? actor.id : null),
            grantedAt: _clock.nowUtc(),
          ),
        );
  }

  /// Resolves which party the invoice is raised on, and checks it suits the
  /// kind of invoice.
  Future<_InvoiceParty> _resolveParty(InvoiceRequest request) async {
    switch (request.kind) {
      case InvoiceKind.agentInvoice:
        final agentId = requireFound(
          request.agentId,
          'Choose the agent this invoice is raised on.',
        );
        final agent = requireFound(
          await (_db.select(
            _db.agents,
          )..where((a) => a.id.equals(agentId))).getSingleOrNull(),
          'That agent no longer exists.',
        );
        requireRule(
          agent.status != EntityStatus.archived,
          '"${agent.name}" is archived and cannot be invoiced.',
          rule: 'invoice.party_not_archived',
        );
        return _InvoiceParty(name: agent.name, agentId: agent.id);

      case InvoiceKind.shopInvoice:
        final shopId = requireFound(
          request.shopId,
          'Choose the shop this invoice is raised on.',
        );
        final shop = requireFound(
          await (_db.select(
            _db.shops,
          )..where((s) => s.id.equals(shopId))).getSingleOrNull(),
          'That shop no longer exists.',
        );
        requireRule(
          shop.status != EntityStatus.archived,
          '"${shop.name}" is archived and cannot be invoiced.',
          rule: 'invoice.party_not_archived',
        );
        await _warnOnCreditLimit(shop, request.totals.net);
        return _InvoiceParty(
          name: shop.name,
          shopId: shop.id,
          agentId: request.agentId ?? shop.assignedAgentId,
        );

      case InvoiceKind.retailSale:
        final shopId = requireFound(
          request.shopId,
          'Choose the shop that made the sale.',
        );
        final shop = requireFound(
          await (_db.select(
            _db.shops,
          )..where((s) => s.id.equals(shopId))).getSingleOrNull(),
          'That shop no longer exists.',
        );
        return _InvoiceParty(
          name: _clean(request.customerName) ?? 'Walk-in customer',
          shopId: shop.id,
          agentId: shop.assignedAgentId,
        );
    }
  }

  /// A shop's credit limit is a warning, not a wall: refusing the invoice
  /// would stop a delivery van at the door. The breach is recorded so it can
  /// be reported on.
  Future<void> _warnOnCreditLimit(Shop shop, Money invoiceNet) async {
    final limitCents = shop.creditLimitCents;
    if (limitCents == null || limitCents == 0) return;

    final row = await _db
        .customSelect(
          '''
      SELECT COALESCE(SUM(
        i.net_total_cents
        - COALESCE((
            SELECT SUM(pa.amount_cents) FROM payment_allocations pa
            JOIN payments p ON p.id = pa.payment_id
            WHERE pa.invoice_id = i.id AND p.status = ?
          ), 0)
      ), 0) AS owed
      FROM invoices i
      WHERE i.shop_id = ? AND i.status = ? AND i.kind = ?
      ''',
          variables: [
            Variable<String>(PaymentStatus.cleared.name),
            Variable<int>(shop.id),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceKind.shopInvoice.name),
          ],
          readsFrom: {_db.invoices, _db.payments, _db.paymentAllocations},
        )
        .getSingle();

    final owed =
        Money(row.read<int>('owed')) +
        Money(shop.openingBalanceCents) +
        invoiceNet;
    if (owed > Money(limitCents)) {
      await _audit.record(
        action: AuditAction.permissionOverride,
        summary:
            'Invoice raised on "${shop.name}" takes it over its credit '
            'limit of ${Money(limitCents).formatted()}: it would owe '
            '${owed.formatted()}.',
        entityKind: EntityKind.shop,
        entityId: shop.id,
      );
    }
  }

  /// Posts or links the goods side of the invoice.
  Future<StockMovementResult?> _applyStockLinkage(
    AuthenticatedUser actor,
    InvoiceRequest request,
  ) async {
    switch (request.stockLinkage) {
      case NoStockMovement():
        return null;

      case BillExistingDelivery(:final stockTransactionId):
        // Nothing is posted: the goods already moved. The invoice records the
        // link, which is what makes the delivery billable exactly once.
        final document = requireFound(
          await (_db.select(
            _db.stockTransactions,
          )..where((t) => t.id.equals(stockTransactionId))).getSingleOrNull(),
          'That stock document no longer exists.',
        );
        return StockMovementResult(
          transactionId: document.id,
          documentNumber: document.documentNumber,
          lineCount: 0,
          totalQuantity: document.totalQuantity,
          sourceBalances: const {},
          destinationBalances: const {},
        );

      case MoveStockWithInvoice(
        :final documentType,
        :final sourceLocationId,
        :final destinationLocationId,
      ):
        return _ledger.postMovement(
          actor,
          StockMovementRequest(
            documentType: documentType,
            sourceLocationId: sourceLocationId,
            destinationLocationId: destinationLocationId,
            documentDate: request.invoiceDate,
            agentId: request.agentId,
            shopId: request.shopId,
            allowNegativeStock: request.allowNegativeStock,
            negativeStockReason: request.negativeStockReason,
            lines: request.lines
                .map(
                  (line) => StockMovementLine(
                    productId: line.productId,
                    quantity: line.quantity,
                    unitPrice: line.unitPrice,
                    discountType: line.discountType,
                    discountValue: line.discountValue,
                  ),
                )
                .toList(growable: false),
          ),
        );
    }
  }

  Future<PaymentResult> _recordImmediatePayment({
    required AuthenticatedUser actor,
    required InvoiceRequest request,
    required int invoiceId,
    required Money invoiceNet,
    required ImmediatePayment immediate,
  }) {
    return _payments.recordPayment(
      actor,
      PaymentRequest(
        direction: PaymentDirection.inbound,
        method: immediate.method,
        amount: immediate.amount,
        partyType: request.partyType,
        agentId: request.agentId,
        shopId: request.shopId,
        payerName: request.customerName,
        paymentDate: request.invoiceDate,
        bankName: immediate.bankName,
        referenceNumber: immediate.referenceNumber,
        notes: 'Received with the invoice',
        allocations: [
          PaymentAllocationRequest(
            invoiceId: invoiceId,
            amount: immediate.amount,
          ),
        ],
        cheque: immediate.isCheque
            ? ChequeDetails(
                chequeNumber: immediate.chequeNumber!,
                bankName: immediate.bankName!,
                chequeDate: immediate.chequeDate!,
                branchName: immediate.chequeBranch,
              )
            : null,
      ),
    );
  }

  /// Cost per unit to snapshot on the line.
  ///
  /// Where goods are leaving a known location, their carrying cost there is
  /// the cost of the sale. Otherwise the product's own cost price is used.
  Future<Money> _resolveUnitCost({
    required Product product,
    required InvoiceRequest request,
  }) async {
    final linkage = request.stockLinkage;
    int? sourceLocationId;
    if (linkage is MoveStockWithInvoice) {
      sourceLocationId = linkage.sourceLocationId;
    } else if (linkage is BillExistingDelivery) {
      final document =
          await (_db.select(_db.stockTransactions)
                ..where((t) => t.id.equals(linkage.stockTransactionId)))
              .getSingleOrNull();
      sourceLocationId = document?.sourceLocationId;
    }

    if (sourceLocationId != null) {
      final balance =
          await (_db.select(_db.stockBalances)..where(
                (b) =>
                    b.locationId.equals(sourceLocationId!) &
                    b.productId.equals(product.id),
              ))
              .getSingleOrNull();
      if (balance != null && balance.averageCostCents > 0) {
        return Money(balance.averageCostCents);
      }
    }
    return Money(product.costPriceCents);
  }

  Future<Product> _requireProduct(int productId) async {
    final product = requireFound(
      await (_db.select(
        _db.products,
      )..where((p) => p.id.equals(productId))).getSingleOrNull(),
      'A product on this invoice no longer exists.',
    );
    requireRule(
      product.status != EntityStatus.archived,
      '"${product.name}" is archived and cannot be put on a new invoice.',
      rule: 'invoice.product_not_archived',
    );
    return product;
  }

  Future<Money> _wholesalePriceOf(int productId) async {
    final product = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(productId))).getSingleOrNull();
    return Money(product?.wholesalePriceCents ?? 0);
  }

  static String? _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}

/// What posting an invoice produced.
@JsonSerializable()
class InvoicePostResult {
  const InvoicePostResult({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.totals,
    required this.cost,
    this.stockDocumentNumber,
    this.stockTransactionId,
    this.payment,
  });

  final int invoiceId;
  final String invoiceNumber;
  final InvoiceTotals totals;
  final Money cost;
  final String? stockDocumentNumber;
  final int? stockTransactionId;

  /// The payment taken at the same time, if any.
  final PaymentResult? payment;

  /// What is still owed immediately after posting. A pending cheque does not
  /// reduce this.
  Money get outstanding {
    final received = payment;
    if (received == null || received.status != PaymentStatus.cleared) {
      return totals.net;
    }
    return totals.net - received.allocated;
  }

  Money get grossProfit => totals.net - cost;

  factory InvoicePostResult.fromJson(Map<String, dynamic> json) =>
      _$InvoicePostResultFromJson(json);

  Map<String, dynamic> toJson() => _$InvoicePostResultToJson(this);
}

/// What cancelling an invoice produced.
@JsonSerializable()
class InvoiceCancelResult {
  const InvoiceCancelResult({
    required this.invoiceNumber,
    required this.releasedMoney,
    this.stockReversalDocumentNumber,
  });

  final String invoiceNumber;

  /// Money that had been applied to this invoice and is now an unapplied
  /// advance for the party.
  final Money releasedMoney;
  final String? stockReversalDocumentNumber;

  factory InvoiceCancelResult.fromJson(Map<String, dynamic> json) =>
      _$InvoiceCancelResultFromJson(json);

  Map<String, dynamic> toJson() => _$InvoiceCancelResultToJson(this);
}

class _InvoiceParty {
  const _InvoiceParty({required this.name, this.agentId, this.shopId});

  final String name;
  final int? agentId;
  final int? shopId;
}
