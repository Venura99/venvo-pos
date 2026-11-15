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
import '../domain/stock_models.dart';
import 'stock_ledger_service.dart';

/// Physical stock counts and the adjustments they produce.
///
/// A count is a working document: it is created with the system's current
/// quantities, somebody writes down what they actually found, and posting it
/// turns the differences into stock movements through the adjustment
/// counterparty.
///
/// A count can have surpluses and shortages at once, and a stock document
/// moves goods one way between two locations, so posting produces up to two
/// documents - an increase and a decrease. Both are recorded on the count.
class StockCountRepository {
  const StockCountRepository({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    required SequenceService sequences,
    required StockLedgerService ledger,
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _sequences = sequences,
       _ledger = ledger;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final SequenceService _sequences;
  final StockLedgerService _ledger;

  /// Opens a count sheet for a location, pre-filled with what the system
  /// believes is there.
  ///
  /// [includeZeroStock] adds every active product, not only the ones with a
  /// balance, which is what a full stock-take needs: a product the system
  /// thinks it has none of may well be sitting on the shelf.
  Future<int> createCount(
    AuthenticatedUser actor, {
    required int locationId,
    bool includeZeroStock = false,
    String? notes,
  }) async {
    actor.require(Permissions.stockReconcile, action: 'start a stock count');

    return _db.transaction(() async {
      final location = requireFound(
        await (_db.select(
          _db.inventoryLocations,
        )..where((l) => l.id.equals(locationId))).getSingleOrNull(),
        'That location no longer exists.',
      );
      requireRule(
        !location.kind.isVirtual,
        'Only a real location can be counted. "${location.name}" is a '
        'counterparty used to balance the ledger, not a place with goods in '
        'it.',
        rule: 'count.real_location_only',
      );

      final openCount =
          await (_db.select(_db.stockCounts)..where(
                (c) =>
                    c.locationId.equals(locationId) &
                    c.status.equalsValue(StockDocumentStatus.draft),
              ))
              .getSingleOrNull();
      requireRule(
        openCount == null,
        'There is already an open count for "${location.name}" '
        '(${openCount?.documentNumber}). Finish or discard it first.',
        rule: 'count.one_open_per_location',
      );

      final documentNumber = await _sequences.nextNumber(
        SequenceKeys.reconciliation,
      );
      final now = _clock.nowUtc();

      final countId = await _db
          .into(_db.stockCounts)
          .insert(
            StockCountsCompanion.insert(
              documentNumber: documentNumber,
              locationId: locationId,
              countDate: now,
              notes: Value(_clean(notes)),
              createdByUserId: actor.id,
              createdAt: now,
            ),
          );

      // The system quantities are captured now, so a movement posted while
      // the count is being taken cannot silently change the variance.
      final rows = await _db
          .customSelect(
            '''
        SELECT p.id AS product_id, COALESCE(sb.quantity, 0) AS quantity
        FROM products p
        LEFT JOIN stock_balances sb
          ON sb.product_id = p.id AND sb.location_id = ?
        WHERE p.status = ?
          AND (? = 1 OR COALESCE(sb.quantity, 0) <> 0)
        ORDER BY p.name
        ''',
            variables: [
              Variable<int>(locationId),
              Variable<String>(EntityStatus.active.name),
              Variable<int>(includeZeroStock ? 1 : 0),
            ],
            readsFrom: {_db.products, _db.stockBalances},
          )
          .get();

      for (final row in rows) {
        await _db
            .into(_db.stockCountItems)
            .insert(
              StockCountItemsCompanion.insert(
                stockCountId: countId,
                productId: row.read<int>('product_id'),
                systemQuantity: row.read<int>('quantity'),
              ),
            );
      }

      await _audit.record(
        action: AuditAction.create,
        summary:
            'Started stock count $documentNumber at "${location.name}" '
            'with ${rows.length} line(s).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.stockDocument,
        entityId: countId,
      );

      return countId;
    });
  }

  Stream<List<StockCountSheet>> watchCounts({int? locationId}) {
    final query = _db.customSelect(
      '''
      SELECT c.*, l.name AS location_name
      FROM stock_counts c
      JOIN inventory_locations l ON l.id = c.location_id
      WHERE (? IS NULL OR c.location_id = ?)
      ORDER BY c.count_date DESC, c.id DESC
      ''',
      variables: [Variable<int>(locationId), Variable<int>(locationId)],
      readsFrom: {_db.stockCounts, _db.inventoryLocations},
    );

    return query.watch().asyncMap((rows) async {
      final sheets = <StockCountSheet>[];
      for (final row in rows) {
        sheets.add(
          await _buildSheet(
            id: row.read<int>('id'),
            documentNumber: row.read<String>('document_number'),
            locationId: row.read<int>('location_id'),
            locationName: row.read<String>('location_name'),
            countDate: row.read<DateTime>('count_date'),
            status: StockDocumentStatus.values.byName(
              row.read<String>('status'),
            ),
            increaseTransactionId: row.readNullable<int>(
              'increase_transaction_id',
            ),
            decreaseTransactionId: row.readNullable<int>(
              'decrease_transaction_id',
            ),
            notes: row.readNullable<String>('notes'),
          ),
        );
      }
      return sheets;
    });
  }

  Future<StockCountSheet> loadCount(int countId) async {
    final row = await _db
        .customSelect(
          '''
      SELECT c.*, l.name AS location_name
      FROM stock_counts c
      JOIN inventory_locations l ON l.id = c.location_id
      WHERE c.id = ?
      ''',
          variables: [Variable<int>(countId)],
          readsFrom: {_db.stockCounts, _db.inventoryLocations},
        )
        .getSingleOrNull();

    final resolved = requireFound(row, 'That stock count no longer exists.');
    return _buildSheet(
      id: resolved.read<int>('id'),
      documentNumber: resolved.read<String>('document_number'),
      locationId: resolved.read<int>('location_id'),
      locationName: resolved.read<String>('location_name'),
      countDate: resolved.read<DateTime>('count_date'),
      status: StockDocumentStatus.values.byName(
        resolved.read<String>('status'),
      ),
      increaseTransactionId: resolved.readNullable<int>(
        'increase_transaction_id',
      ),
      decreaseTransactionId: resolved.readNullable<int>(
        'decrease_transaction_id',
      ),
      notes: resolved.readNullable<String>('notes'),
    );
  }

  /// Saves what was counted. Pass null for a product to clear its count.
  Future<void> saveCountedQuantities(
    AuthenticatedUser actor, {
    required int countId,
    required Map<int, int?> countedByProductId,
  }) async {
    actor.require(Permissions.stockReconcile, action: 'record a stock count');

    await _db.transaction(() async {
      final count = requireFound(
        await (_db.select(
          _db.stockCounts,
        )..where((c) => c.id.equals(countId))).getSingleOrNull(),
        'That stock count no longer exists.',
      );
      requireRule(
        count.status == StockDocumentStatus.draft,
        'That count has already been posted and cannot be changed.',
        rule: 'count.draft_only',
      );

      for (final entry in countedByProductId.entries) {
        final counted = entry.value;
        require(
          counted == null || counted >= 0,
          'A counted quantity cannot be negative.',
          field: 'countedQuantity',
        );
        await (_db.update(_db.stockCountItems)..where(
              (i) =>
                  i.stockCountId.equals(countId) &
                  i.productId.equals(entry.key),
            ))
            .write(StockCountItemsCompanion(countedQuantity: Value(counted)));
      }
    });
  }

  /// Posts the count: turns every variance into a stock movement.
  ///
  /// Returns the documents it created. A count with no variances posts nothing
  /// and is simply marked done, because there is nothing to correct.
  Future<List<StockMovementResult>> postCount(
    AuthenticatedUser actor, {
    required int countId,
    String? reason,
  }) async {
    actor.require(Permissions.stockReconcile, action: 'post a stock count');

    return _db.transaction(() async {
      final sheet = await loadCount(countId);
      requireRule(
        sheet.status == StockDocumentStatus.draft,
        'That count has already been posted.',
        rule: 'count.draft_only',
      );
      requireRule(
        sheet.countedLineCount > 0,
        'Nothing has been counted yet. Enter at least one counted quantity.',
        rule: 'count.needs_counts',
      );

      final adjustmentLocation =
          await (_db.select(_db.inventoryLocations)..where(
                (l) => l.code.equals(AppConstants.adjustmentLocationCode),
              ))
              .getSingle();

      final surpluses = sheet.variances
          .where((line) => line.variance > 0)
          .toList(growable: false);
      final shortages = sheet.variances
          .where((line) => line.variance < 0)
          .toList(growable: false);

      final results = <StockMovementResult>[];
      final narration =
          'Stock count ${sheet.documentNumber} at ${sheet.locationName}'
          '${reason == null || reason.trim().isEmpty ? '' : ': ${reason.trim()}'}';

      if (surpluses.isNotEmpty) {
        results.add(
          await _ledger.postMovement(
            actor,
            StockMovementRequest(
              documentType: StockDocumentType.reconciliation,
              sourceLocationId: adjustmentLocation.id,
              destinationLocationId: sheet.locationId,
              referenceNote: sheet.documentNumber,
              notes: narration,
              lines: surpluses
                  .map(
                    (line) => StockMovementLine(
                      productId: line.productId,
                      quantity: line.variance,
                      notes:
                          'Counted ${line.countedQuantity}, system said '
                          '${line.systemQuantity}',
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      }

      if (shortages.isNotEmpty) {
        results.add(
          await _ledger.postMovement(
            actor,
            StockMovementRequest(
              // A shortage moves goods out of the location, so the adjustment
              // counterparty is the destination.
              documentType: StockDocumentType.adjustmentDecrease,
              sourceLocationId: sheet.locationId,
              destinationLocationId: adjustmentLocation.id,
              referenceNote: sheet.documentNumber,
              notes: narration,
              lines: shortages
                  .map(
                    (line) => StockMovementLine(
                      productId: line.productId,
                      quantity: -line.variance,
                      notes:
                          'Counted ${line.countedQuantity}, system said '
                          '${line.systemQuantity}',
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      }

      final increaseId = surpluses.isEmpty ? null : results.first.transactionId;
      final decreaseId = shortages.isEmpty ? null : results.last.transactionId;

      await (_db.update(
        _db.stockCounts,
      )..where((c) => c.id.equals(countId))).write(
        StockCountsCompanion(
          status: const Value(StockDocumentStatus.posted),
          postedAt: Value(_clock.nowUtc()),
          increaseTransactionId: Value(increaseId),
          decreaseTransactionId: Value(decreaseId),
        ),
      );

      await _audit.record(
        action: AuditAction.post,
        summary:
            'Posted stock count ${sheet.documentNumber} at '
            '"${sheet.locationName}": ${surpluses.length} surplus and '
            '${shortages.length} shortage line(s), '
            '+${sheet.surplusUnits} / -${sheet.shortageUnits} units.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.stockDocument,
        entityId: countId,
        after: {
          'increaseTransactionId': increaseId,
          'decreaseTransactionId': decreaseId,
          'surplusUnits': sheet.surplusUnits,
          'shortageUnits': sheet.shortageUnits,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );

      return results;
    });
  }

  /// Discards an unposted count. Nothing it recorded affected stock, so the
  /// sheet itself is removed rather than kept as noise.
  Future<void> discardCount(AuthenticatedUser actor, int countId) async {
    actor.require(Permissions.stockReconcile, action: 'discard a stock count');

    await _db.transaction(() async {
      final count = requireFound(
        await (_db.select(
          _db.stockCounts,
        )..where((c) => c.id.equals(countId))).getSingleOrNull(),
        'That stock count no longer exists.',
      );
      requireRule(
        count.status == StockDocumentStatus.draft,
        'A posted count cannot be discarded. It affected stock, so it stays '
        'on the record.',
        rule: 'count.draft_only',
      );

      await (_db.delete(
        _db.stockCountItems,
      )..where((i) => i.stockCountId.equals(countId))).go();
      await (_db.delete(
        _db.stockCounts,
      )..where((c) => c.id.equals(countId))).go();

      await _audit.record(
        action: AuditAction.cancel,
        summary:
            'Discarded the unposted stock count '
            '${count.documentNumber}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.stockDocument,
        entityId: countId,
      );
    });
  }

  /// Value of a count's variances at the location's carrying cost, so the
  /// financial size of a discrepancy is visible before it is posted.
  Future<Money> varianceValue(int countId) async {
    final sheet = await loadCount(countId);
    final row = await _db
        .customSelect(
          '''
      SELECT ci.product_id,
             COALESCE(sb.average_cost_cents, p.cost_price_cents) AS unit_cost,
             ci.system_quantity,
             ci.counted_quantity
      FROM stock_count_items ci
      JOIN products p ON p.id = ci.product_id
      LEFT JOIN stock_balances sb
        ON sb.product_id = ci.product_id AND sb.location_id = ?
      WHERE ci.stock_count_id = ? AND ci.counted_quantity IS NOT NULL
      ''',
          variables: [Variable<int>(sheet.locationId), Variable<int>(countId)],
          readsFrom: {_db.stockCountItems, _db.products, _db.stockBalances},
        )
        .get();

    var total = Money.zero;
    for (final item in row) {
      final variance =
          item.read<int>('counted_quantity') -
          item.read<int>('system_quantity');
      total += Money(item.read<int>('unit_cost')) * variance;
    }
    return total;
  }

  Future<StockCountSheet> _buildSheet({
    required int id,
    required String documentNumber,
    required int locationId,
    required String locationName,
    required DateTime countDate,
    required StockDocumentStatus status,
    int? increaseTransactionId,
    int? decreaseTransactionId,
    String? notes,
  }) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT ci.product_id, ci.system_quantity, ci.counted_quantity, ci.notes,
             p.sku, p.name AS product_name
      FROM stock_count_items ci
      JOIN products p ON p.id = ci.product_id
      WHERE ci.stock_count_id = ?
      ORDER BY p.name
      ''',
          variables: [Variable<int>(id)],
          readsFrom: {_db.stockCountItems, _db.products},
        )
        .get();

    return StockCountSheet(
      id: id,
      documentNumber: documentNumber,
      locationId: locationId,
      locationName: locationName,
      countDate: countDate,
      status: status,
      increaseTransactionId: increaseTransactionId,
      decreaseTransactionId: decreaseTransactionId,
      notes: notes,
      lines: rows
          .map(
            (row) => StockCountLine(
              productId: row.read<int>('product_id'),
              sku: row.read<String>('sku'),
              productName: row.read<String>('product_name'),
              systemQuantity: row.read<int>('system_quantity'),
              countedQuantity: row.readNullable<int>('counted_quantity'),
              notes: row.readNullable<String>('notes'),
            ),
          )
          .toList(growable: false),
    );
  }

  static String? _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
