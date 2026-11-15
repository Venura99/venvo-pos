/// Shared enumerations persisted by the application.
///
/// Every enumeration stored in the database is persisted by its **name**
/// (text), never by index, so that reordering a Dart enum can never silently
/// re-interpret historical rows.
library;

/// Lifecycle flag for master records. Master data is soft-deleted by moving to
/// [EntityStatus.archived]; it is never physically removed, so historical
/// transactions keep resolving their foreign keys.
enum EntityStatus { active, inactive, archived }

/// Kind of inventory location. The last four are *virtual* locations used to
/// make the stock ledger balance to zero: every posted movement writes paired
/// signed entries, so the sum of qty_delta over all locations for a product is
/// always 0 and no quantity can leak.
enum LocationKind {
  warehouse,
  agent,
  shop,

  /// Physical quarantine for damaged / defective goods awaiting disposal.
  damaged,

  /// Virtual counterparty for goods bought into the business.
  supplier,

  /// Virtual counterparty for goods sold to end customers.
  customer,

  /// Virtual counterparty for stock-take variances and authorised overrides.
  adjustment,

  /// Virtual holding location for goods dispatched but not yet received.
  inTransit;

  bool get isVirtual =>
      this == supplier ||
      this == customer ||
      this == adjustment ||
      this == inTransit;

  /// Virtual locations may go negative; real ones may not.
  bool get allowsNegativeBalance => isVirtual;

  /// Real locations whose stock is owned by the business and valued in
  /// inventory reports.
  bool get isStockHolding => !isVirtual;
}

/// Type of stock document. Determines which pair of locations the ledger
/// entries are written against.
enum StockDocumentType {
  openingStock,
  purchaseIn,
  warehouseToAgent,
  agentToShop,
  warehouseToShop,
  retailSale,
  customerToShopReturn,
  shopToAgentReturn,
  agentToWarehouseReturn,
  shopToWarehouseReturn,
  damageWriteOff,
  adjustmentIncrease,
  adjustmentDecrease,
  reconciliation,
  interLocationTransfer,
}

/// A document affects stock balances only once it is [posted]. Posted
/// documents are immutable: they are undone by [cancelled] plus a
/// compensating ledger, never edited or deleted.
enum StockDocumentStatus { draft, posted, cancelled }

/// Financial document discriminator. A stock transfer and a chargeable
/// invoice are deliberately separate concepts: moving goods to an agent
/// produces revenue only when an [InvoiceKind.agentInvoice] is explicitly
/// raised against that transfer.
enum InvoiceKind {
  /// Chargeable invoice raised on an agent (warehouse to agent).
  agentInvoice,

  /// Wholesale supply invoice raised on a shop (agent to shop).
  shopInvoice,

  /// Over-the-counter sale by a shop to an end customer.
  retailSale,
}

enum InvoiceStatus { draft, posted, cancelled }

/// Derived from *cleared* allocations only - see [PaymentStatus].
enum PaymentSettlementStatus { unpaid, partiallyPaid, paid, overpaid }

enum PartyType { agent, shop, customer, employee, supplier }

enum PaymentDirection {
  /// Money coming into the business (collections from agents and shops).
  inbound,

  /// Money leaving the business (expenses, salaries, refunds).
  outbound,
}

enum PaymentMethod {
  cash,
  bankTransfer,
  cheque,
  cardOrDigital,
  creditNote,
  openingBalance,
}

/// A payment affects outstanding balances and cash only once it is [cleared].
/// Cash and bank transfers are created already cleared; cheques start
/// [pending] and must be cleared or bounced explicitly.
enum PaymentStatus { pending, cleared, bounced, cancelled }

enum ChequeStatus { pending, deposited, cleared, bounced, returned, cancelled }

enum DiscountType { none, percentage, fixedAmount }

enum DiscountScope { item, invoice }

/// Direction of a goods return.
enum ReturnRoute {
  customerToShop,
  shopToAgent,
  agentToWarehouse,

  /// Bypasses the agent; requires an explicit authorisation permission.
  shopToWarehouse,
}

enum ReturnReason {
  customerPaymentFailure,
  defectiveItem,
  damagedItem,
  wrongProduct,
  excessStock,
  other,
}

/// Returned goods never re-enter available stock automatically. Each returned
/// line waits in [pending] until a disposition is recorded.
enum InspectionStatus {
  pending,

  /// Good condition - returns to the receiving location's available stock.
  acceptedToStock,

  /// Defective or damaged - moves to the damaged / quarantine location.
  movedToDamaged,

  /// Written off entirely.
  scrapped,
}

enum ReturnStatus { draft, posted, inspected, completed, cancelled }

/// Classification for the financial ledger.
enum AccountType { asset, liability, equity, income, expense }

enum PettyCashEntryKind {
  opening,
  cashReceived,
  cashIssued,
  expense,
  adjustment,
}

enum AttachmentKind {
  shopBill,
  supplierInvoice,
  paymentReceipt,
  chequeImage,
  returnDocument,
  expenseReceipt,
  salarySlip,
  other,
}

/// Owning record type for an attachment or an audit-log row.
enum EntityKind {
  product,
  category,
  agent,
  shop,
  employee,
  inventoryLocation,
  stockDocument,
  invoice,
  payment,
  cheque,
  returnDocument,
  creditNote,
  expense,
  pettyCashEntry,
  salary,
  salaryPayment,

  /// An advance paid to an employee. Its own kind rather than a [salary],
  /// because the two are different tables whose ids overlap: sharing a kind
  /// would let a lookup by source match the wrong record.
  employeeAdvance,
  user,
  setting,
  backup,
}

enum AuditAction {
  create,
  update,
  archive,
  post,
  cancel,
  reverse,
  login,
  loginFailed,
  logout,
  permissionOverride,
  backup,
  restore,
  export,
}

enum SalaryStatus { draft, approved, partiallyPaid, paid, cancelled }

/// Unit a product is counted in. Stock is always stored in base units; packs
/// are converted at entry time using the product's unitsPerPack.
enum UnitOfMeasure { piece, pack, box, dozen, set, pair, meter, kilogram }
