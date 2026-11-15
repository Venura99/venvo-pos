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
import '../domain/stock_models.dart';

/// The single way stock ever moves.
///
/// Everything in the application that changes a quantity goes through
/// [postMovement]. Nothing else may write to `stock_balances`.
///
/// What one call does, inside one database transaction:
///
/// 1. Validates the request, including that the two locations suit the kind of
///    document being posted.
/// 2. Allocates the document number.
/// 3. Writes the document header and its lines, snapshotting the product name,
///    SKU and cost as they are now.
/// 4. For each line, writes a **pair** of signed rows to
///    `stock_ledger_entries`: negative at the source, positive at the
///    destination. The sum of every `quantity_delta` for a product is
///    therefore always zero.
/// 5. Updates the `stock_balances` cache for both ends, maintaining the
///    weighted average cost at the receiving end.
///
/// Because all of that shares one transaction, a failure at any point leaves
/// neither end of the movement updated - there is no state in which the
/// warehouse has shipped goods that nobody received.
///
/// **Cost flow.** When goods leave a real location the cost travels with them:
/// moving your own stock from a warehouse to an agent does not change what it
/// cost you. A cost is only *stated* when goods enter from a virtual
/// counterparty - a purchase, opening stock, or an adjustment increase.
class StockLedgerService {
  StockLedgerService({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    required SequenceService sequences,
    required SettingsService settings,
    required FinancialLedgerService finance,
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _sequences = sequences,
       _settings = settings,
       _finance = finance;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final SequenceService _sequences;
  final SettingsService _settings;
  final FinancialLedgerService _finance;

  /// Posts a movement and returns what it did.
  Future<StockMovementResult> postMovement(
    AuthenticatedUser actor,
    StockMovementRequest request,
  ) async {
    _validateRequest(request);
    actor.require(
      _permissionFor(request.documentType),
      action: _actionDescriptionFor(request.documentType),
    );

    final allowNegativeByPolicy = await _settings.allowNegativeStock;
    if (request.allowNegativeStock) {
      actor.require(
        Permissions.stockNegativeOverride,
        action: 'post a movement that takes stock below zero',
      );
      require(
        (request.negativeStockReason ?? '').trim().isNotEmpty,
        'Give a reason for allowing stock to go below zero.',
        field: 'negativeStockReason',
      );
    }

    return _db.transaction(() async {
      final source = await _requireLocation(request.sourceLocationId, 'source');
      final destination = await _requireLocation(
        request.destinationLocationId,
        'destination',
      );
      _assertRouteValid(request.documentType, source, destination);

      final occurredAt = request.documentDate ?? _clock.nowUtc();
      final documentNumber = await _sequences.nextNumber(
        _sequenceKeyFor(request.documentType),
      );

      final transactionId = await _db
          .into(_db.stockTransactions)
          .insert(
            StockTransactionsCompanion.insert(
              documentNumber: documentNumber,
              documentType: request.documentType,
              status: const Value(StockDocumentStatus.posted),
              documentDate: occurredAt,
              sourceLocationId: source.id,
              destinationLocationId: destination.id,
              agentId: Value(
                request.agentId ?? source.agentId ?? destination.agentId,
              ),
              shopId: Value(
                request.shopId ?? source.shopId ?? destination.shopId,
              ),
              negativeStockOverride: Value(request.allowNegativeStock),
              overrideApprovedByUserId: Value(
                request.allowNegativeStock ? actor.id : null,
              ),
              overrideReason: Value(
                request.allowNegativeStock ? request.negativeStockReason : null,
              ),
              referenceNote: Value(_clean(request.referenceNote)),
              notes: Value(_clean(request.notes)),
              createdByUserId: actor.id,
              createdAt: _clock.nowUtc(),
              postedAt: Value(_clock.nowUtc()),
              postedByUserId: Value(actor.id),
            ),
          );

      final sourceBalances = <int, int>{};
      final destinationBalances = <int, int>{};
      var lineNumber = 0;
      // Value of the goods at the cost they are carried at, which is what the
      // journal posts when the movement is one that changes what the business
      // owns rather than merely where it keeps it.
      var costTotal = Money.zero;

      for (final line in request.lines) {
        lineNumber++;
        final product = await _requireProduct(line.productId);
        final unitCost = await _resolveUnitCost(
          source: source,
          product: product,
          providedCost: line.unitCost,
        );
        costTotal += unitCost * line.quantity;

        final itemId = await _db
            .into(_db.stockTransactionItems)
            .insert(
              StockTransactionItemsCompanion.insert(
                transactionId: transactionId,
                lineNumber: lineNumber,
                productId: product.id,
                productNameSnapshot: product.name,
                skuSnapshot: product.sku,
                quantity: line.quantity,
                unitCostCents: Value(unitCost.cents),
                unitPriceCents: Value(line.unitPrice.cents),
                discountType: Value(line.discountType),
                discountValue: Value(line.discountValue),
                discountCents: Value(line.discount.cents),
                lineTotalCents: Value(line.lineTotal.cents),
                notes: Value(_clean(line.notes)),
              ),
            );

        // The outbound leg. Checked against the negative-stock policy before
        // anything is written for this line.
        final sourceBalance = await _applyToBalance(
          location: source,
          product: product,
          delta: -line.quantity,
          unitCost: unitCost,
          allowNegative: request.allowNegativeStock || allowNegativeByPolicy,
        );
        final destinationBalance = await _applyToBalance(
          location: destination,
          product: product,
          delta: line.quantity,
          unitCost: unitCost,
          allowNegative: request.allowNegativeStock || allowNegativeByPolicy,
        );

        sourceBalances[product.id] = sourceBalance;
        destinationBalances[product.id] = destinationBalance;

        await _writeLedgerPair(
          actor: actor,
          transactionId: transactionId,
          itemId: itemId,
          documentType: request.documentType,
          occurredAt: occurredAt,
          source: source,
          destination: destination,
          productId: product.id,
          quantity: line.quantity,
          unitCost: unitCost,
          sourceBalanceAfter: sourceBalance,
          destinationBalanceAfter: destinationBalance,
          narration: '$documentNumber: ${source.name} to ${destination.name}',
        );
      }

      await (_db.update(
        _db.stockTransactions,
      )..where((t) => t.id.equals(transactionId))).write(
        StockTransactionsCompanion(
          totalQuantity: Value(request.totalQuantity),
          subtotalCents: Value(request.subtotal.cents),
          discountTotalCents: Value(request.discountTotal.cents),
          totalCents: Value(request.total.cents),
        ),
      );

      // Accounting for the movement, in the same transaction. Moving your own
      // goods between your own locations posts nothing, because nothing the
      // business owns has changed; buying, writing off or adjusting does.
      await _finance.postStockMovement(
        actor: actor,
        transactionId: transactionId,
        documentNumber: documentNumber,
        documentType: request.documentType,
        documentDate: occurredAt,
        cost: costTotal,
      );

      await _audit.record(
        action: AuditAction.post,
        summary:
            'Posted $documentNumber: '
            '${stockDocumentTypeLabel(request.documentType)}, '
            '${request.totalQuantity} unit(s) from ${source.name} to '
            '${destination.name}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.stockDocument,
        entityId: transactionId,
        after: {
          'documentNumber': documentNumber,
          'lines': request.lines.length,
          'totalQuantity': request.totalQuantity,
          if (request.allowNegativeStock)
            'negativeStockOverride': request.negativeStockReason,
        },
      );

      if (request.allowNegativeStock) {
        await _audit.record(
          action: AuditAction.permissionOverride,
          summary:
              'Allowed stock to go below zero on $documentNumber: '
              '${request.negativeStockReason}',
          userId: actor.id,
          username: actor.username,
          entityKind: EntityKind.stockDocument,
          entityId: transactionId,
        );
      }

      return StockMovementResult(
        transactionId: transactionId,
        documentNumber: documentNumber,
        lineCount: request.lines.length,
        totalQuantity: request.totalQuantity,
        sourceBalances: sourceBalances,
        destinationBalances: destinationBalances,
      );
    });
  }

  /// Cancels a posted document by posting a compensating movement.
  ///
  /// The original document and its ledger entries are never touched: the
  /// original is marked cancelled, and a new document with the two locations
  /// swapped puts the goods back. The ledger therefore records what actually
  /// happened - a movement and its reversal - rather than pretending the first
  /// one never did.
  Future<StockMovementResult> cancelMovement(
    AuthenticatedUser actor, {
    required int transactionId,
    required String reason,
  }) async {
    final cleanReason = requireText(reason, 'Reason', maxLength: 500);

    return _db.transaction(() async {
      final original = requireFound(
        await (_db.select(
          _db.stockTransactions,
        )..where((t) => t.id.equals(transactionId))).getSingleOrNull(),
        'That document no longer exists.',
      );

      actor.require(
        _permissionFor(original.documentType),
        action:
            'cancel a ${stockDocumentTypeLabel(original.documentType)} '
            'document',
      );

      requireRule(
        original.status == StockDocumentStatus.posted,
        original.status == StockDocumentStatus.cancelled
            ? 'That document has already been cancelled.'
            : 'Only a posted document can be cancelled.',
        rule: 'stock.cancel_posted_only',
      );

      final alreadyReversed =
          await (_db.select(_db.stockTransactions)
                ..where((t) => t.reversesTransactionId.equals(transactionId)))
              .getSingleOrNull();
      requireRule(
        alreadyReversed == null,
        'That document has already been reversed by '
        '${alreadyReversed?.documentNumber}.',
        rule: 'stock.cancel_once',
      );

      final items =
          await (_db.select(_db.stockTransactionItems)
                ..where((i) => i.transactionId.equals(transactionId))
                ..orderBy([(i) => OrderingTerm.asc(i.lineNumber)]))
              .get();
      requireRule(
        items.isNotEmpty,
        'That document has no lines to reverse.',
        rule: 'stock.cancel_has_lines',
      );

      final source = await _requireLocation(
        original.sourceLocationId,
        'source',
      );
      final destination = await _requireLocation(
        original.destinationLocationId,
        'destination',
      );

      // Reversing sends the goods back, so the destination becomes the source.
      // The destination of a reversal is a real location that is receiving
      // goods back, which cannot go negative; the new source might, if the
      // goods have since moved on. That is exactly when the user has to be
      // told rather than quietly allowed.
      final occurredAt = _clock.nowUtc();
      final documentNumber = await _sequences.nextNumber(
        _sequenceKeyFor(original.documentType),
      );

      final reversalId = await _db
          .into(_db.stockTransactions)
          .insert(
            StockTransactionsCompanion.insert(
              documentNumber: documentNumber,
              documentType: original.documentType,
              status: const Value(StockDocumentStatus.posted),
              documentDate: occurredAt,
              sourceLocationId: destination.id,
              destinationLocationId: source.id,
              agentId: Value(original.agentId),
              shopId: Value(original.shopId),
              reversesTransactionId: Value(transactionId),
              referenceNote: Value('Reverses ${original.documentNumber}'),
              notes: Value(cleanReason),
              createdByUserId: actor.id,
              createdAt: occurredAt,
              postedAt: Value(occurredAt),
              postedByUserId: Value(actor.id),
            ),
          );

      final sourceBalances = <int, int>{};
      final destinationBalances = <int, int>{};
      var totalQuantity = 0;
      var lineNumber = 0;

      for (final item in items) {
        lineNumber++;
        totalQuantity += item.quantity;
        final product = await _requireProduct(item.productId);
        final unitCost = Money(item.unitCostCents);

        final reversalItemId = await _db
            .into(_db.stockTransactionItems)
            .insert(
              StockTransactionItemsCompanion.insert(
                transactionId: reversalId,
                lineNumber: lineNumber,
                productId: item.productId,
                productNameSnapshot: item.productNameSnapshot,
                skuSnapshot: item.skuSnapshot,
                quantity: item.quantity,
                unitCostCents: Value(item.unitCostCents),
                unitPriceCents: Value(item.unitPriceCents),
                notes: const Value('Reversal'),
              ),
            );

        // Goods go back the way they came.
        final fromBalance = await _applyToBalance(
          location: destination,
          product: product,
          delta: -item.quantity,
          unitCost: unitCost,
          allowNegative: await _settings.allowNegativeStock,
        );
        final toBalance = await _applyToBalance(
          location: source,
          product: product,
          delta: item.quantity,
          unitCost: unitCost,
          allowNegative: true,
        );

        sourceBalances[item.productId] = fromBalance;
        destinationBalances[item.productId] = toBalance;

        await _writeLedgerPair(
          actor: actor,
          transactionId: reversalId,
          itemId: reversalItemId,
          documentType: original.documentType,
          occurredAt: occurredAt,
          source: destination,
          destination: source,
          productId: item.productId,
          quantity: item.quantity,
          unitCost: unitCost,
          sourceBalanceAfter: fromBalance,
          destinationBalanceAfter: toBalance,
          narration: '$documentNumber reverses ${original.documentNumber}',
        );
      }

      await (_db.update(
        _db.stockTransactions,
      )..where((t) => t.id.equals(reversalId))).write(
        StockTransactionsCompanion(
          totalQuantity: Value(totalQuantity),
          subtotalCents: Value(original.subtotalCents),
          discountTotalCents: Value(original.discountTotalCents),
          totalCents: Value(original.totalCents),
        ),
      );

      // The original keeps every one of its ledger rows; only its status and
      // the cancellation metadata change.
      await (_db.update(
        _db.stockTransactions,
      )..where((t) => t.id.equals(transactionId))).write(
        StockTransactionsCompanion(
          status: const Value(StockDocumentStatus.cancelled),
          cancelledAt: Value(occurredAt),
          cancelledByUserId: Value(actor.id),
          cancelReason: Value(cleanReason),
        ),
      );

      // The accounting is undone by mirroring the batch the original posted,
      // not by guessing which accounts the opposite movement would touch:
      // cancelling opening stock has to credit inventory against owner's
      // equity, where cancelling a write-off has to credit the loss account.
      // The original batch stays in the journal untouched.
      final originalBatches = await _finance.entriesForSource(
        sourceKind: EntityKind.stockDocument,
        sourceId: transactionId,
      );
      for (final batchId in {for (final row in originalBatches) row.batchId}) {
        await _finance.reverse(
          actor: actor,
          batchId: batchId,
          reason: 'Document ${original.documentNumber} cancelled',
          entryDate: occurredAt,
        );
      }

      await _audit.record(
        action: AuditAction.cancel,
        summary:
            'Cancelled ${original.documentNumber} by posting the '
            'reversing document $documentNumber. Reason: $cleanReason',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.stockDocument,
        entityId: transactionId,
        after: {
          'reversalDocumentNumber': documentNumber,
          'reversalTransactionId': reversalId,
        },
      );

      return StockMovementResult(
        transactionId: reversalId,
        documentNumber: documentNumber,
        lineCount: items.length,
        totalQuantity: totalQuantity,
        sourceBalances: sourceBalances,
        destinationBalances: destinationBalances,
      );
    });
  }

  /// Current balance of one product at one location.
  Future<int> balanceOf({
    required int locationId,
    required int productId,
  }) async {
    final row = await _balanceRow(locationId, productId);
    return row?.quantity ?? 0;
  }

  /// Recomputes a balance by replaying the ledger, and reports whether the
  /// cached value agrees.
  ///
  /// The ledger is the authority; `stock_balances` is a cache. This is what
  /// makes that claim checkable rather than merely stated.
  Future<({int cached, int fromLedger, bool matches})> verifyBalance({
    required int locationId,
    required int productId,
  }) async {
    final cached = await balanceOf(
      locationId: locationId,
      productId: productId,
    );

    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(quantity_delta), 0) AS replayed '
          'FROM stock_ledger_entries '
          'WHERE location_id = ? AND product_id = ?',
          variables: [Variable<int>(locationId), Variable<int>(productId)],
          readsFrom: {_db.stockLedgerEntries},
        )
        .getSingle();
    final replayed = row.read<int>('replayed');

    return (cached: cached, fromLedger: replayed, matches: cached == replayed);
  }

  /// Replays the whole ledger and reports every balance that disagrees with
  /// its cached value. Used by the integrity check and by the tests.
  Future<List<({int locationId, int productId, int cached, int fromLedger})>>
  findBalanceDiscrepancies() async {
    final rows = await _db
        .customSelect(
          '''
      SELECT
        ledger.location_id,
        ledger.product_id,
        COALESCE(balances.quantity, 0) AS cached,
        ledger.replayed AS from_ledger
      FROM (
        SELECT location_id, product_id, SUM(quantity_delta) AS replayed
        FROM stock_ledger_entries
        GROUP BY location_id, product_id
      ) ledger
      LEFT JOIN stock_balances balances
        ON balances.location_id = ledger.location_id
       AND balances.product_id = ledger.product_id
      WHERE COALESCE(balances.quantity, 0) <> ledger.replayed
      ''',
          readsFrom: {_db.stockLedgerEntries, _db.stockBalances},
        )
        .get();

    return rows
        .map(
          (row) => (
            locationId: row.read<int>('location_id'),
            productId: row.read<int>('product_id'),
            cached: row.read<int>('cached'),
            fromLedger: row.read<int>('from_ledger'),
          ),
        )
        .toList(growable: false);
  }

  /// Confirms that the ledger balances to zero for every product, which is the
  /// invariant the paired entries exist to guarantee.
  Future<List<({int productId, int netDelta})>> findUnbalancedProducts() async {
    final rows = await _db
        .customSelect(
          'SELECT product_id, SUM(quantity_delta) AS net_delta '
          'FROM stock_ledger_entries GROUP BY product_id '
          'HAVING SUM(quantity_delta) <> 0',
          readsFrom: {_db.stockLedgerEntries},
        )
        .get();

    return rows
        .map(
          (row) => (
            productId: row.read<int>('product_id'),
            netDelta: row.read<int>('net_delta'),
          ),
        )
        .toList(growable: false);
  }

  // --- Internals ----------------------------------------------------------

  void _validateRequest(StockMovementRequest request) {
    require(
      request.lines.isNotEmpty,
      'Add at least one product to the document.',
      field: 'lines',
    );
    require(
      request.sourceLocationId != request.destinationLocationId,
      'The source and destination must be different locations.',
      field: 'destinationLocationId',
    );

    final seen = <int>{};
    for (final line in request.lines) {
      require(
        line.quantity > 0,
        'Every line needs a quantity of at least 1.',
        field: 'quantity',
      );
      require(
        !line.unitPrice.isNegative,
        'A unit price cannot be negative.',
        field: 'unitPrice',
      );
      require(
        line.discount <= line.grossValue,
        'A line discount cannot exceed the line value.',
        field: 'discountValue',
      );
      requireRule(
        seen.add(line.productId),
        'The same product appears on more than one line. Combine them into a '
        'single line.',
        rule: 'stock.no_duplicate_products',
      );
    }
  }

  Future<InventoryLocation> _requireLocation(int id, String role) async {
    final location = await (_db.select(
      _db.inventoryLocations,
    )..where((l) => l.id.equals(id))).getSingleOrNull();
    final resolved = requireFound(
      location,
      'The $role location no longer exists.',
    );
    requireRule(
      resolved.isActive || resolved.kind.isVirtual,
      'The $role location "${resolved.name}" is not active.',
      rule: 'stock.location_active',
    );
    return resolved;
  }

  Future<Product> _requireProduct(int id) async {
    final product = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    final resolved = requireFound(
      product,
      'A product on this document no '
      'longer exists.',
    );
    requireRule(
      resolved.status != EntityStatus.archived,
      '"${resolved.name}" is archived and cannot be put on a new document.',
      rule: 'stock.product_not_archived',
    );
    return resolved;
  }

  /// See the class comment on cost flow.
  Future<Money> _resolveUnitCost({
    required InventoryLocation source,
    required Product product,
    required Money? providedCost,
  }) async {
    if (!source.kind.isVirtual) {
      final balance = await _balanceRow(source.id, product.id);
      if (balance != null && balance.quantity > 0) {
        return Money(balance.averageCostCents);
      }
    }
    return providedCost ?? Money(product.costPriceCents);
  }

  Future<StockBalance?> _balanceRow(int locationId, int productId) {
    return (_db.select(_db.stockBalances)..where(
          (b) =>
              b.locationId.equals(locationId) & b.productId.equals(productId),
        ))
        .getSingleOrNull();
  }

  /// Applies [delta] to one location's balance and returns the new quantity.
  ///
  /// Refuses to drive a *real* location below zero unless explicitly allowed.
  /// Virtual counterparties are expected to go negative - that is how they
  /// mirror everything that has entered or left the business.
  Future<int> _applyToBalance({
    required InventoryLocation location,
    required Product product,
    required int delta,
    required Money unitCost,
    required bool allowNegative,
  }) async {
    final existing = await _balanceRow(location.id, product.id);
    final currentQuantity = existing?.quantity ?? 0;
    final newQuantity = currentQuantity + delta;

    if (newQuantity < 0 &&
        !location.kind.allowsNegativeBalance &&
        !allowNegative) {
      throw BusinessRuleFailure(
        'There is not enough stock. "${product.name}" has $currentQuantity '
        'unit(s) at ${location.name}, and this document needs '
        '${delta.abs()}.',
        details:
            'Reduce the quantity, or ask somebody with the stock '
            'override permission to post it with a recorded reason.',
        rule: 'stock.no_negative_balance',
      );
    }

    // Cost is only recomputed where goods arrive. Taking goods out does not
    // change what the remaining units cost.
    final newAverageCost = delta > 0
        ? _weightedAverageCost(
            currentQuantity: currentQuantity,
            currentAverageCents: existing?.averageCostCents ?? 0,
            incomingQuantity: delta,
            incomingCostCents: unitCost.cents,
          )
        : existing?.averageCostCents ?? unitCost.cents;

    if (existing == null) {
      await _db
          .into(_db.stockBalances)
          .insert(
            StockBalancesCompanion.insert(
              locationId: location.id,
              productId: product.id,
              quantity: Value(newQuantity),
              averageCostCents: Value(newAverageCost),
              updatedAt: _clock.nowUtc(),
            ),
          );
    } else {
      await (_db.update(
        _db.stockBalances,
      )..where((b) => b.id.equals(existing.id))).write(
        StockBalancesCompanion(
          quantity: Value(newQuantity),
          averageCostCents: Value(newAverageCost),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );
    }

    return newQuantity;
  }

  /// Weighted average cost, rounded the same way every other figure in the
  /// application is rounded.
  static int _weightedAverageCost({
    required int currentQuantity,
    required int currentAverageCents,
    required int incomingQuantity,
    required int incomingCostCents,
  }) {
    // A location at or below zero has no meaningful average to blend with, so
    // the arriving cost simply becomes the cost.
    if (currentQuantity <= 0) return incomingCostCents;

    final totalQuantity = currentQuantity + incomingQuantity;
    if (totalQuantity <= 0) return incomingCostCents;

    final totalValue =
        currentQuantity * currentAverageCents +
        incomingQuantity * incomingCostCents;
    return Money.divideRounded(totalValue, totalQuantity);
  }

  /// Writes the two signed rows that make up one movement of one product.
  Future<void> _writeLedgerPair({
    required AuthenticatedUser actor,
    required int transactionId,
    required int itemId,
    required StockDocumentType documentType,
    required DateTime occurredAt,
    required InventoryLocation source,
    required InventoryLocation destination,
    required int productId,
    required int quantity,
    required Money unitCost,
    required int sourceBalanceAfter,
    required int destinationBalanceAfter,
    required String narration,
  }) async {
    final recordedAt = _clock.nowUtc();

    await _db
        .into(_db.stockLedgerEntries)
        .insert(
          StockLedgerEntriesCompanion.insert(
            transactionId: transactionId,
            transactionItemId: Value(itemId),
            locationId: source.id,
            productId: productId,
            quantityDelta: -quantity,
            balanceAfter: sourceBalanceAfter,
            unitCostCents: Value(unitCost.cents),
            entryType: documentType,
            occurredAt: occurredAt,
            recordedAt: recordedAt,
            recordedByUserId: actor.id,
            narration: Value(narration),
          ),
        );

    await _db
        .into(_db.stockLedgerEntries)
        .insert(
          StockLedgerEntriesCompanion.insert(
            transactionId: transactionId,
            transactionItemId: Value(itemId),
            locationId: destination.id,
            productId: productId,
            quantityDelta: quantity,
            balanceAfter: destinationBalanceAfter,
            unitCostCents: Value(unitCost.cents),
            entryType: documentType,
            occurredAt: occurredAt,
            recordedAt: recordedAt,
            recordedByUserId: actor.id,
            narration: Value(narration),
          ),
        );
  }

  /// Checks that the two locations are the right kinds for the document.
  ///
  /// Without this, a "warehouse to agent" document could be posted between two
  /// shops, and every agent-wise report built on the document type would be
  /// quietly wrong.
  void _assertRouteValid(
    StockDocumentType type,
    InventoryLocation source,
    InventoryLocation destination,
  ) {
    void expect({Set<LocationKind>? from, Set<LocationKind>? to}) {
      if (from != null) {
        requireRule(
          from.contains(source.kind),
          '${stockDocumentTypeLabel(type)} must come from '
          '${from.map(_kindName).join(' or ')}, but "${source.name}" is '
          '${_kindName(source.kind)}.',
          rule: 'stock.route_source_kind',
        );
      }
      if (to != null) {
        requireRule(
          to.contains(destination.kind),
          '${stockDocumentTypeLabel(type)} must go to '
          '${to.map(_kindName).join(' or ')}, but "${destination.name}" is '
          '${_kindName(destination.kind)}.',
          rule: 'stock.route_destination_kind',
        );
      }
    }

    /// Accepts the movement only if it matches one of [legs] as a whole pair.
    ///
    /// A return is posted in two legs - out of the returning location into
    /// goods-in-transit, then out of transit once inspected - and checking
    /// source and destination independently would also wave through the
    /// shortcut that skips inspection entirely.
    void expectLeg(List<(LocationKind, LocationKind)> legs) {
      final matches = legs.any(
        (leg) => leg.$1 == source.kind && leg.$2 == destination.kind,
      );
      requireRule(
        matches,
        '${stockDocumentTypeLabel(type)} cannot go from '
        '${_kindName(source.kind)} to ${_kindName(destination.kind)}. '
        'Allowed: '
        '${legs.map((leg) => '${_kindName(leg.$1)} to ${_kindName(leg.$2)}').join(', ')}.',
        rule: 'stock.route_leg',
      );
    }

    switch (type) {
      case StockDocumentType.openingStock:
      case StockDocumentType.purchaseIn:
        expect(
          from: {LocationKind.supplier},
          to: {LocationKind.warehouse, LocationKind.agent, LocationKind.shop},
        );
      case StockDocumentType.warehouseToAgent:
        expect(from: {LocationKind.warehouse}, to: {LocationKind.agent});
      case StockDocumentType.agentToShop:
        expect(from: {LocationKind.agent}, to: {LocationKind.shop});
      case StockDocumentType.warehouseToShop:
        expect(from: {LocationKind.warehouse}, to: {LocationKind.shop});
      case StockDocumentType.retailSale:
        expect(from: {LocationKind.shop}, to: {LocationKind.customer});
      case StockDocumentType.customerToShopReturn:
        expectLeg(const [
          (LocationKind.customer, LocationKind.inTransit),
          (LocationKind.inTransit, LocationKind.shop),
        ]);
      case StockDocumentType.shopToAgentReturn:
        expectLeg(const [
          (LocationKind.shop, LocationKind.inTransit),
          (LocationKind.inTransit, LocationKind.agent),
        ]);
      case StockDocumentType.agentToWarehouseReturn:
        expectLeg(const [
          (LocationKind.agent, LocationKind.inTransit),
          (LocationKind.inTransit, LocationKind.warehouse),
        ]);
      case StockDocumentType.shopToWarehouseReturn:
        expectLeg(const [
          (LocationKind.shop, LocationKind.inTransit),
          (LocationKind.inTransit, LocationKind.warehouse),
        ]);
      case StockDocumentType.damageWriteOff:
        expect(
          from: {
            LocationKind.warehouse,
            LocationKind.agent,
            LocationKind.shop,
            // Goods condemned at inspection, on their way back from a party.
            LocationKind.inTransit,
          },
          to: {LocationKind.damaged},
        );
      case StockDocumentType.adjustmentIncrease:
      case StockDocumentType.reconciliation:
        expect(from: {LocationKind.adjustment});
      case StockDocumentType.adjustmentDecrease:
        expect(to: {LocationKind.adjustment});
      case StockDocumentType.interLocationTransfer:
        expect(from: {LocationKind.warehouse}, to: {LocationKind.warehouse});
    }
  }

  static String _kindName(LocationKind kind) => switch (kind) {
    LocationKind.warehouse => 'a warehouse',
    LocationKind.agent => 'an agent',
    LocationKind.shop => 'a shop',
    LocationKind.damaged => 'the damaged store',
    LocationKind.supplier => 'suppliers',
    LocationKind.customer => 'customers',
    LocationKind.adjustment => 'adjustments',
    LocationKind.inTransit => 'goods in transit',
  };

  static String _permissionFor(StockDocumentType type) => switch (type) {
    StockDocumentType.openingStock ||
    StockDocumentType.purchaseIn => Permissions.stockOpening,
    StockDocumentType.warehouseToAgent ||
    StockDocumentType.agentToShop ||
    StockDocumentType.warehouseToShop ||
    StockDocumentType.interLocationTransfer => Permissions.stockTransfer,
    StockDocumentType.retailSale => Permissions.retailSaleRecord,
    StockDocumentType.customerToShopReturn ||
    StockDocumentType.shopToAgentReturn ||
    StockDocumentType.agentToWarehouseReturn ||
    StockDocumentType.shopToWarehouseReturn => Permissions.returnCreate,
    StockDocumentType.damageWriteOff ||
    StockDocumentType.adjustmentIncrease ||
    StockDocumentType.adjustmentDecrease => Permissions.stockAdjust,
    StockDocumentType.reconciliation => Permissions.stockReconcile,
  };

  static String _actionDescriptionFor(StockDocumentType type) => switch (type) {
    StockDocumentType.openingStock => 'enter opening stock',
    StockDocumentType.purchaseIn => 'record a purchase',
    StockDocumentType.warehouseToAgent ||
    StockDocumentType.agentToShop ||
    StockDocumentType.warehouseToShop ||
    StockDocumentType.interLocationTransfer => 'transfer stock',
    StockDocumentType.retailSale => 'record a retail sale',
    StockDocumentType.customerToShopReturn ||
    StockDocumentType.shopToAgentReturn ||
    StockDocumentType.agentToWarehouseReturn ||
    StockDocumentType.shopToWarehouseReturn => 'record a return',
    StockDocumentType.damageWriteOff => 'write off damaged stock',
    StockDocumentType.adjustmentIncrease ||
    StockDocumentType.adjustmentDecrease => 'adjust stock',
    StockDocumentType.reconciliation => 'post a reconciliation',
  };

  static String _sequenceKeyFor(StockDocumentType type) => switch (type) {
    StockDocumentType.openingStock => SequenceKeys.openingStock,
    StockDocumentType.purchaseIn => SequenceKeys.purchase,
    StockDocumentType.warehouseToAgent ||
    StockDocumentType.warehouseToShop ||
    StockDocumentType.interLocationTransfer => SequenceKeys.agentTransfer,
    StockDocumentType.agentToShop => SequenceKeys.shopSupply,
    StockDocumentType.retailSale => SequenceKeys.retailSale,
    StockDocumentType.customerToShopReturn ||
    StockDocumentType.shopToAgentReturn ||
    StockDocumentType.agentToWarehouseReturn ||
    StockDocumentType.shopToWarehouseReturn => SequenceKeys.returnNote,
    StockDocumentType.damageWriteOff ||
    StockDocumentType.adjustmentIncrease ||
    StockDocumentType.adjustmentDecrease => SequenceKeys.stockAdjustment,
    StockDocumentType.reconciliation => SequenceKeys.reconciliation,
  };

  static String? _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
