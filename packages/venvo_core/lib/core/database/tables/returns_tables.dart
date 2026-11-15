import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import 'inventory_tables.dart';
import 'master_tables.dart';
import 'payment_tables.dart';
import 'sales_tables.dart';
import 'system_tables.dart';

/// Returns and credit notes.
///
/// Three rules shape this schema:
///
/// * Goods and money are handled separately but linked. A return moves stock;
///   a [CreditNotes] row reduces what the party owes. One can exist without
///   the other (a defective item written off gives no credit).
/// * Returned goods are not available stock. A line arrives
///   [InspectionStatus.pending] and goes into the receiving location only when
///   a disposition says so; defective quantities move to the damaged location.
/// * Nothing is deleted. The original invoice and its payments stay exactly as
///   they were; the return is a new document that references them.

@DataClassName('ReturnDocument')
@TableIndex(name: 'idx_returns_number', columns: {#returnNumber})
@TableIndex(name: 'idx_returns_date', columns: {#returnDate})
@TableIndex(name: 'idx_returns_status', columns: {#status})
@TableIndex(name: 'idx_returns_origin_invoice', columns: {#originInvoiceId})
class ReturnDocuments extends Table {
  @override
  String get tableName => 'returns';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get returnNumber => text().withLength(min: 1, max: 32)();
  TextColumn get route => textEnum<ReturnRoute>()();
  TextColumn get status =>
      textEnum<ReturnStatus>().withDefault(Constant(ReturnStatus.draft.name))();
  DateTimeColumn get returnDate => dateTime()();

  /// The invoice being returned against, when the goods can be traced to one.
  IntColumn get originInvoiceId => integer().nullable().references(
    Invoices,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// The transfer or supply document the goods originally came on.
  IntColumn get originStockTransactionId => integer().nullable().references(
    StockTransactions,
    #id,
    onDelete: KeyAction.restrict,
  )();

  IntColumn get fromLocationId => integer().references(
    InventoryLocations,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Where accepted goods will land. Rejected quantities always go to the
  /// damaged location instead, regardless of this value.
  IntColumn get toLocationId => integer().references(
    InventoryLocations,
    #id,
    onDelete: KeyAction.restrict,
  )();

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

  TextColumn get reason => textEnum<ReturnReason>()();
  TextColumn get reasonNote => text().nullable().withLength(max: 500)();

  /// Required for [ReturnRoute.shopToWarehouse], which bypasses the agent.
  IntColumn get authorisedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// The movement that took the goods out of the returning location.
  IntColumn get receiptTransactionId => integer().nullable().references(
    StockTransactions,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// The movement that placed inspected goods into stock or quarantine.
  IntColumn get dispositionTransactionId => integer().nullable().references(
    StockTransactions,
    #id,
    onDelete: KeyAction.restrict,
  )();

  IntColumn get totalQuantity => integer().withDefault(const Constant(0))();

  /// Value of the returned goods at the prices they were originally billed.
  IntColumn get totalValueCents => integer().withDefault(const Constant(0))();

  TextColumn get notes => text().nullable().withLength(max: 1000)();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get postedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  TextColumn get cancelReason => text().nullable().withLength(max: 500)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {returnNumber},
  ];
}

@DataClassName('ReturnItem')
@TableIndex(name: 'idx_return_items_return', columns: {#returnId})
@TableIndex(name: 'idx_return_items_product', columns: {#productId})
class ReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId =>
      integer().references(ReturnDocuments, #id, onDelete: KeyAction.cascade)();
  IntColumn get lineNumber => integer()();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  TextColumn get productNameSnapshot => text().withLength(min: 1, max: 180)();
  TextColumn get skuSnapshot => text().withLength(min: 1, max: 40)();

  /// The invoice line the goods were billed on, used to cap the returnable
  /// quantity and to recover the original price.
  IntColumn get originInvoiceItemId => integer().nullable().references(
    InvoiceItems,
    #id,
    onDelete: KeyAction.restrict,
  )();

  IntColumn get quantity => integer().check(quantity.isBiggerThanValue(0))();

  /// Price the goods were originally billed at, used for the credit note.
  IntColumn get unitPriceCents => integer().withDefault(const Constant(0))();
  IntColumn get lineValueCents => integer().withDefault(const Constant(0))();

  TextColumn get inspectionStatus => textEnum<InspectionStatus>().withDefault(
    Constant(InspectionStatus.pending.name),
  )();

  /// The disposition split. These must sum to [quantity] once inspected.
  IntColumn get acceptedQuantity => integer().withDefault(const Constant(0))();
  IntColumn get damagedQuantity => integer().withDefault(const Constant(0))();
  IntColumn get scrappedQuantity => integer().withDefault(const Constant(0))();

  TextColumn get inspectionNote => text().nullable().withLength(max: 500)();
  IntColumn get inspectedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get inspectedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable().withLength(max: 300)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {returnId, lineNumber},
  ];
}

/// Reduces what a party owes. Applied to invoices through
/// [CreditNoteApplications], mirroring how payments are allocated, so a
/// credit never silently disappears into a balance.
@DataClassName('CreditNote')
@TableIndex(name: 'idx_credit_notes_number', columns: {#creditNoteNumber})
@TableIndex(
  name: 'idx_credit_notes_party',
  columns: {#partyType, #agentId, #shopId},
)
class CreditNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get creditNoteNumber => text().withLength(min: 1, max: 32)();
  TextColumn get status => textEnum<InvoiceStatus>().withDefault(
    Constant(InvoiceStatus.draft.name),
  )();
  DateTimeColumn get issueDate => dateTime()();

  /// The return that justifies this credit, when there is one.
  IntColumn get returnId => integer().nullable().references(
    ReturnDocuments,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// The invoice the credit relates to. Application to invoices is recorded
  /// separately so a credit can be spread across several of them.
  IntColumn get originInvoiceId => integer().nullable().references(
    Invoices,
    #id,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get partyType => textEnum<PartyType>()();
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

  IntColumn get amountCents =>
      integer().check(amountCents.isBiggerThanValue(0))();

  /// Cache of the sum of applications; the remainder is available credit.
  IntColumn get appliedCents => integer().withDefault(const Constant(0))();

  TextColumn get reason => text().nullable().withLength(max: 300)();
  TextColumn get notes => text().nullable().withLength(max: 1000)();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get postedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  TextColumn get cancelReason => text().nullable().withLength(max: 500)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {creditNoteNumber},
  ];
}

@DataClassName('CreditNoteApplication')
@TableIndex(name: 'idx_cn_app_note', columns: {#creditNoteId})
@TableIndex(name: 'idx_cn_app_invoice', columns: {#invoiceId})
class CreditNoteApplications extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get creditNoteId =>
      integer().references(CreditNotes, #id, onDelete: KeyAction.restrict)();
  IntColumn get invoiceId =>
      integer().references(Invoices, #id, onDelete: KeyAction.restrict)();

  /// Positive when applying credit, negative when withdrawing it.
  IntColumn get amountCents => integer().check(amountCents.isNotValue(0))();

  /// Set when the credit was refunded in money rather than offset against an
  /// invoice.
  IntColumn get refundPaymentId => integer().nullable().references(
    Payments,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
}
