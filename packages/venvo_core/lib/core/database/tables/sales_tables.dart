import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import 'inventory_tables.dart';
import 'master_tables.dart';
import 'system_tables.dart';

/// Billing: invoices, their lines, and the discount history.
///
/// A stock movement and a chargeable invoice are separate records. Moving
/// goods from the warehouse to an agent writes a [StockTransactions] document;
/// revenue is recognised only when an [Invoices] row of kind
/// [InvoiceKind.agentInvoice] is raised, optionally pointing at that document
/// through [Invoices.stockTransactionId]. This is why a delivery note can
/// never be double counted as a sale.
///
/// Totals are stored, not computed on read, because the figures a customer was
/// billed must survive any later change to prices, discounts or rounding
/// rules.

@DataClassName('Invoice')
@TableIndex(name: 'idx_invoices_number', columns: {#invoiceNumber})
@TableIndex(name: 'idx_invoices_kind_status', columns: {#kind, #status})
@TableIndex(name: 'idx_invoices_date', columns: {#invoiceDate})
@TableIndex(name: 'idx_invoices_agent', columns: {#agentId})
@TableIndex(name: 'idx_invoices_shop', columns: {#shopId})
// The register is always "this party, newest first". Covering the date as
// well lets SQLite walk the index in order instead of sorting the result.
@TableIndex(name: 'idx_invoices_shop_date', columns: {#shopId, #invoiceDate})
@TableIndex(name: 'idx_invoices_agent_date', columns: {#agentId, #invoiceDate})
class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Unique across every kind of invoice, e.g. `SINV-2026-00231`.
  TextColumn get invoiceNumber => text().withLength(min: 1, max: 32)();
  TextColumn get kind => textEnum<InvoiceKind>()();
  TextColumn get status => textEnum<InvoiceStatus>().withDefault(
    Constant(InvoiceStatus.draft.name),
  )();
  DateTimeColumn get invoiceDate => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();

  TextColumn get partyType => textEnum<PartyType>()();

  /// The agent being billed, or the agent responsible for a shop invoice.
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

  /// Walk-in customer details for a retail sale. Retail sales are deliberately
  /// not forced to create a party record.
  TextColumn get customerName => text().nullable().withLength(max: 180)();
  TextColumn get customerPhone => text().nullable().withLength(max: 32)();

  /// The goods movement this invoice bills for, when there is one.
  IntColumn get stockTransactionId => integer().nullable().references(
    StockTransactions,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Sum of line gross amounts before any discount.
  IntColumn get grossTotalCents => integer().withDefault(const Constant(0))();

  /// Sum of the per-line discounts.
  IntColumn get itemDiscountTotalCents =>
      integer().withDefault(const Constant(0))();

  TextColumn get invoiceDiscountType =>
      textEnum<DiscountType>().withDefault(Constant(DiscountType.none.name))();

  /// Basis points when the type is percentage, cents when fixed amount.
  IntColumn get invoiceDiscountValue =>
      integer().withDefault(const Constant(0))();

  /// Resolved cash value of the invoice-level discount.
  IntColumn get invoiceDiscountCents =>
      integer().withDefault(const Constant(0))();

  /// `grossTotal - itemDiscountTotal - invoiceDiscount`. What the party owes.
  IntColumn get netTotalCents => integer().withDefault(const Constant(0))();

  /// Cost of the goods sold, snapshotted at posting time for gross profit
  /// reporting that does not drift when costs change.
  IntColumn get costTotalCents => integer().withDefault(const Constant(0))();

  TextColumn get discountReason => text().nullable().withLength(max: 300)();

  /// Set when a discount beyond the configured ceiling was authorised.
  IntColumn get discountApprovedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();

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
    {invoiceNumber},
  ];
}

@DataClassName('InvoiceItem')
@TableIndex(name: 'idx_invoice_items_invoice', columns: {#invoiceId})
@TableIndex(name: 'idx_invoice_items_product', columns: {#productId})
class InvoiceItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId =>
      integer().references(Invoices, #id, onDelete: KeyAction.cascade)();
  IntColumn get lineNumber => integer()();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();

  /// Snapshots of the product as it was when billed.
  TextColumn get productNameSnapshot => text().withLength(min: 1, max: 180)();
  TextColumn get skuSnapshot => text().withLength(min: 1, max: 40)();

  IntColumn get quantity => integer().check(quantity.isBiggerThanValue(0))();

  /// Price actually charged per base unit, preserved for the life of the row.
  IntColumn get unitPriceCents => integer()();

  /// `quantity * unitPriceCents`.
  IntColumn get grossCents => integer()();

  TextColumn get discountType =>
      textEnum<DiscountType>().withDefault(Constant(DiscountType.none.name))();

  /// Basis points when the type is percentage, cents when fixed amount. The
  /// original input is kept alongside the resolved amount so a printed invoice
  /// can still show "10%" years later.
  IntColumn get discountValue => integer().withDefault(const Constant(0))();
  IntColumn get discountCents => integer().withDefault(const Constant(0))();

  /// `grossCents - discountCents`.
  IntColumn get netCents => integer()();

  /// Unit cost at the time of sale, for gross profit by product.
  IntColumn get unitCostSnapshotCents =>
      integer().withDefault(const Constant(0))();

  /// Quantity already returned against this line, maintained by the returns
  /// module so a line cannot be over-returned.
  IntColumn get returnedQuantity => integer().withDefault(const Constant(0))();

  TextColumn get notes => text().nullable().withLength(max: 300)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {invoiceId, lineNumber},
  ];
}

/// Audit history of every discount granted. The resolved amounts also live on
/// the invoice and its lines; this table exists so the discount report can be
/// produced per user, per reason and per period without scanning invoices.
@DataClassName('DiscountRecord')
@TableIndex(name: 'idx_discounts_invoice', columns: {#invoiceId})
@TableIndex(name: 'idx_discounts_granted', columns: {#grantedAt})
class DiscountRecords extends Table {
  @override
  String get tableName => 'discounts';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get scope => textEnum<DiscountScope>()();
  IntColumn get invoiceId =>
      integer().references(Invoices, #id, onDelete: KeyAction.cascade)();
  IntColumn get invoiceItemId => integer().nullable().references(
    InvoiceItems,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get productId => integer().nullable().references(
    Products,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get discountType => textEnum<DiscountType>()();
  IntColumn get discountValue => integer()();
  IntColumn get discountCents => integer()();

  /// Amount the discount was applied to, so the effective rate is verifiable.
  IntColumn get baseAmountCents => integer()();
  TextColumn get reason => text().nullable().withLength(max: 300)();

  /// True when the discount exceeded the configured ceiling and was allowed
  /// by a user holding `discount.exceed_limit`.
  BoolColumn get exceededLimit =>
      boolean().withDefault(const Constant(false))();
  IntColumn get grantedByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  IntColumn get approvedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get grantedAt => dateTime()();
}
