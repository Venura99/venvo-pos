import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import 'master_tables.dart';
import 'system_tables.dart';

/// The stock ledger.
///
/// Three layers, in order of authority:
///
/// 1. [StockTransactions] / [StockTransactionItems] - the business document
///    (a transfer, a supply, an adjustment). What a user sees and prints.
/// 2. [StockLedgerEntries] - the append-only truth. Each posted document line
///    writes a *pair* of signed entries (one negative at the source location,
///    one positive at the destination), so the sum of `qtyDelta` across all
///    locations for a product is always zero.
/// 3. [StockBalances] - a cache of the current quantity per
///    (location, product), written in the same database transaction as the
///    ledger entries and fully reconstructable by replaying layer 2.
///
/// Nothing in the application may write to [StockBalances] without writing the
/// matching [StockLedgerEntries] rows in the same transaction.

/// Header of a stock document. The brief calls this `stock_transactions`.
@DataClassName('StockTransaction')
@TableIndex(name: 'idx_stock_tx_number', columns: {#documentNumber})
@TableIndex(name: 'idx_stock_tx_date', columns: {#documentDate})
@TableIndex(name: 'idx_stock_tx_type_status', columns: {#documentType, #status})
@TableIndex(name: 'idx_stock_tx_source', columns: {#sourceLocationId})
@TableIndex(name: 'idx_stock_tx_dest', columns: {#destinationLocationId})
class StockTransactions extends Table {
  @override
  String get tableName => 'stock_transactions';

  IntColumn get id => integer().autoIncrement()();

  /// Unique, prefixed and zero-padded, e.g. `TRF-2026-00014`.
  TextColumn get documentNumber => text().withLength(min: 1, max: 32)();
  TextColumn get documentType => textEnum<StockDocumentType>()();
  TextColumn get status => textEnum<StockDocumentStatus>().withDefault(
    Constant(StockDocumentStatus.draft.name),
  )();
  DateTimeColumn get documentDate => dateTime()();

  /// Where the goods leave from. Virtual locations are used for purchases
  /// (supplier), retail sales (customer) and adjustments.
  IntColumn get sourceLocationId => integer().references(
    InventoryLocations,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Where the goods arrive.
  IntColumn get destinationLocationId => integer().references(
    InventoryLocations,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Denormalised party pointers, kept so agent-wise and shop-wise reports do
  /// not have to walk the location table on every row.
  IntColumn get agentId => integer().nullable().references(
    Agents,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get shopId => integer().nullable().references(
    Shops,
    #id,
    onDelete: KeyAction.restrict,
  )();

  IntColumn get totalQuantity => integer().withDefault(const Constant(0))();

  /// Indicative values. A stock document carries a value for the delivery
  /// note, but it becomes revenue only when an invoice is raised against it.
  IntColumn get subtotalCents => integer().withDefault(const Constant(0))();
  IntColumn get discountTotalCents =>
      integer().withDefault(const Constant(0))();
  IntColumn get totalCents => integer().withDefault(const Constant(0))();

  /// True when a user with `stock.negative_override` knowingly posted a
  /// movement that drives a real location negative.
  BoolColumn get negativeStockOverride =>
      boolean().withDefault(const Constant(false))();
  IntColumn get overrideApprovedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get overrideReason => text().nullable().withLength(max: 500)();

  /// Set on a compensating document that reverses an earlier posted one.
  IntColumn get reversesTransactionId => integer().nullable().references(
    StockTransactions,
    #id,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get referenceNote => text().nullable().withLength(max: 200)();
  TextColumn get notes => text().nullable().withLength(max: 1000)();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get postedAt => dateTime().nullable()();
  IntColumn get postedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  IntColumn get cancelledByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get cancelReason => text().nullable().withLength(max: 500)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {documentNumber},
  ];
}

/// Lines of a stock document. The brief calls this `stock_transaction_items`.
@DataClassName('StockTransactionItem')
@TableIndex(name: 'idx_stock_tx_item_tx', columns: {#transactionId})
@TableIndex(name: 'idx_stock_tx_item_product', columns: {#productId})
class StockTransactionItems extends Table {
  @override
  String get tableName => 'stock_transaction_items';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer().references(
    StockTransactions,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get lineNumber => integer()();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();

  /// Snapshots taken when the line was created, so a later rename or
  /// re-pricing of the product cannot rewrite history.
  TextColumn get productNameSnapshot => text().withLength(min: 1, max: 180)();
  TextColumn get skuSnapshot => text().withLength(min: 1, max: 40)();

  /// Always in base units and strictly positive; direction comes from the
  /// document's source and destination.
  IntColumn get quantity => integer().check(quantity.isBiggerThanValue(0))();

  /// Valuation cost per base unit at the moment of the movement.
  IntColumn get unitCostCents => integer().withDefault(const Constant(0))();

  /// Price per base unit charged on the accompanying document, if any.
  IntColumn get unitPriceCents => integer().withDefault(const Constant(0))();
  TextColumn get discountType =>
      textEnum<DiscountType>().withDefault(Constant(DiscountType.none.name))();

  /// Basis points when [discountType] is percentage, cents when fixed amount.
  IntColumn get discountValue => integer().withDefault(const Constant(0))();
  IntColumn get discountCents => integer().withDefault(const Constant(0))();
  IntColumn get lineTotalCents => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable().withLength(max: 300)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {transactionId, lineNumber},
  ];
}

/// Append-only stock ledger. Rows are inserted, never updated or deleted; a
/// mistake is corrected by posting a compensating document.
@DataClassName('StockLedgerEntry')
@TableIndex(name: 'idx_ledger_loc_product', columns: {#locationId, #productId})
@TableIndex(name: 'idx_ledger_occurred', columns: {#occurredAt})
@TableIndex(name: 'idx_ledger_tx', columns: {#transactionId})
@TableIndex(name: 'idx_ledger_product', columns: {#productId})
// The movement history is always "this product, over this period, newest
// first". One index on the product and another on the date leaves SQLite to
// sort the result in a temporary B-tree; this one is walked in order.
@TableIndex(
  name: 'idx_ledger_product_occurred',
  columns: {#productId, #occurredAt},
)
class StockLedgerEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer().references(
    StockTransactions,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get transactionItemId => integer().nullable().references(
    StockTransactionItems,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get locationId => integer().references(
    InventoryLocations,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();

  /// Signed change in base units: negative at the source, positive at the
  /// destination. Never zero.
  IntColumn get quantityDelta => integer().check(quantityDelta.isNotValue(0))();

  /// Running quantity at this location for this product immediately after the
  /// entry was applied. Written from the locked balance row in the same
  /// transaction, so it is a genuine audit trail rather than a guess.
  IntColumn get balanceAfter => integer()();
  IntColumn get unitCostCents => integer().withDefault(const Constant(0))();

  /// Copy of the document type, so ledger reports need no join.
  TextColumn get entryType => textEnum<StockDocumentType>()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get recordedAt => dateTime()();
  IntColumn get recordedByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  TextColumn get narration => text().nullable().withLength(max: 300)();
}

/// Current quantity per (location, product). A cache of
/// [StockLedgerEntries]; see the file header.
@DataClassName('StockBalance')
@TableIndex(name: 'idx_balance_product', columns: {#productId})
class StockBalances extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get locationId => integer().references(
    InventoryLocations,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantity => integer().withDefault(const Constant(0))();

  /// Weighted average cost per base unit held at this location, maintained on
  /// inbound movements and used for stock valuation reports.
  IntColumn get averageCostCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {locationId, productId},
  ];
}

/// A physical stock count and the variance it produced. Posting a
/// reconciliation creates an adjustment [StockTransactions] document; the
/// count itself is kept for audit.
@DataClassName('StockCount')
@TableIndex(name: 'idx_count_location', columns: {#locationId})
class StockCounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get documentNumber => text().withLength(min: 1, max: 32)();
  IntColumn get locationId => integer().references(
    InventoryLocations,
    #id,
    onDelete: KeyAction.restrict,
  )();
  DateTimeColumn get countDate => dateTime()();
  TextColumn get status => textEnum<StockDocumentStatus>().withDefault(
    Constant(StockDocumentStatus.draft.name),
  )();

  /// The adjustment documents generated when the count was posted.
  ///
  /// A count can produce variances in both directions, and a stock document
  /// moves goods one way between two locations, so posting a count with
  /// surpluses *and* shortages produces two documents. Both are recorded here
  /// so the count can always be traced to its effect on the ledger.
  IntColumn get increaseTransactionId => integer().nullable().references(
    StockTransactions,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get decreaseTransactionId => integer().nullable().references(
    StockTransactions,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get notes => text().nullable().withLength(max: 1000)();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get postedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {documentNumber},
  ];
}

@DataClassName('StockCountItem')
@TableIndex(name: 'idx_count_item_count', columns: {#stockCountId})
class StockCountItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get stockCountId =>
      integer().references(StockCounts, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();

  /// Balance the system believed was on hand when the sheet was generated.
  IntColumn get systemQuantity => integer()();

  /// Quantity actually found. Null until the counter fills it in.
  IntColumn get countedQuantity => integer().nullable()();
  TextColumn get notes => text().nullable().withLength(max: 300)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {stockCountId, productId},
  ];
}
