/// Permission identifiers. Roles are collections of these strings; every
/// restricted operation checks one by name, so adding a capability never
/// requires a schema change.
class Permissions {
  const Permissions._();

  // Master data
  static const String productsView = 'products.view';
  static const String productsManage = 'products.manage';
  static const String agentsView = 'agents.view';
  static const String agentsManage = 'agents.manage';
  static const String shopsView = 'shops.view';
  static const String shopsManage = 'shops.manage';
  static const String employeesView = 'employees.view';
  static const String employeesManage = 'employees.manage';

  // Inventory
  static const String stockView = 'stock.view';
  static const String stockTransfer = 'stock.transfer';
  static const String stockOpening = 'stock.opening';
  static const String stockAdjust = 'stock.adjust';

  /// Lets an authorised user post a movement that drives a real location
  /// negative. The override is always recorded on the document itself.
  static const String stockNegativeOverride = 'stock.negative_override';
  static const String stockReconcile = 'stock.reconcile';

  // Sales & billing
  static const String invoiceView = 'invoice.view';
  static const String invoiceCreate = 'invoice.create';
  static const String invoicePost = 'invoice.post';
  static const String invoiceCancel = 'invoice.cancel';
  static const String retailSaleRecord = 'retail_sale.record';

  // Discounts
  static const String discountApplyItem = 'discount.apply_item';
  static const String discountApplyInvoice = 'discount.apply_invoice';

  /// Lets an authorised user exceed the configured discount ceilings.
  static const String discountExceedLimit = 'discount.exceed_limit';

  // Payments
  static const String paymentView = 'payment.view';
  static const String paymentRecord = 'payment.record';
  static const String paymentAllocate = 'payment.allocate';
  static const String paymentCancel = 'payment.cancel';
  static const String chequeManage = 'cheque.manage';

  // Returns
  static const String returnView = 'return.view';
  static const String returnCreate = 'return.create';
  static const String returnInspect = 'return.inspect';
  static const String returnDirectToWarehouse = 'return.direct_to_warehouse';
  static const String creditNoteIssue = 'credit_note.issue';

  // Finance
  static const String expenseView = 'expense.view';
  static const String expenseManage = 'expense.manage';
  static const String pettyCashView = 'petty_cash.view';
  static const String pettyCashManage = 'petty_cash.manage';
  static const String salaryView = 'salary.view';
  static const String salaryManage = 'salary.manage';
  static const String financialLedgerView = 'finance.ledger_view';

  // Reports
  static const String reportsView = 'reports.view';
  static const String reportsFinancial = 'reports.financial';
  static const String reportsExport = 'reports.export';

  // System
  static const String settingsManage = 'settings.manage';
  static const String usersManage = 'users.manage';
  static const String auditView = 'audit.view';
  static const String backupRun = 'backup.run';
  static const String backupRestore = 'backup.restore';

  /// Every permission known to the application, seeded into the database on
  /// first run.
  static const List<String> all = [
    productsView,
    productsManage,
    agentsView,
    agentsManage,
    shopsView,
    shopsManage,
    employeesView,
    employeesManage,
    stockView,
    stockTransfer,
    stockOpening,
    stockAdjust,
    stockNegativeOverride,
    stockReconcile,
    invoiceView,
    invoiceCreate,
    invoicePost,
    invoiceCancel,
    retailSaleRecord,
    discountApplyItem,
    discountApplyInvoice,
    discountExceedLimit,
    paymentView,
    paymentRecord,
    paymentAllocate,
    paymentCancel,
    chequeManage,
    returnView,
    returnCreate,
    returnInspect,
    returnDirectToWarehouse,
    creditNoteIssue,
    expenseView,
    expenseManage,
    pettyCashView,
    pettyCashManage,
    salaryView,
    salaryManage,
    financialLedgerView,
    reportsView,
    reportsFinancial,
    reportsExport,
    settingsManage,
    usersManage,
    auditView,
    backupRun,
    backupRestore,
  ];
}

/// Codes of the roles seeded on first run.
class RoleCodes {
  const RoleCodes._();

  static const String administrator = 'ADMIN';
  static const String manager = 'MANAGER';
  static const String storeKeeper = 'STORE_KEEPER';
  static const String cashier = 'CASHIER';
  static const String accountant = 'ACCOUNTANT';
  static const String viewer = 'VIEWER';

  /// A sales agent signing in from a phone in the field. Records what a shop
  /// hands over — cash or a cheque, with a photo of the cheque — and sees the
  /// invoices it can be applied to. Cannot move stock, change prices or
  /// cancel anything.
  static const String agent = 'AGENT';

  /// Permission sets granted to each seeded role. The administrator role is
  /// granted every permission in [Permissions.all] and is not listed here.
  static const Map<String, List<String>> defaultGrants = {
    manager: [
      Permissions.productsView,
      Permissions.productsManage,
      Permissions.agentsView,
      Permissions.agentsManage,
      Permissions.shopsView,
      Permissions.shopsManage,
      Permissions.employeesView,
      Permissions.stockView,
      Permissions.stockTransfer,
      Permissions.stockOpening,
      Permissions.stockAdjust,
      Permissions.stockReconcile,
      Permissions.invoiceView,
      Permissions.invoiceCreate,
      Permissions.invoicePost,
      Permissions.invoiceCancel,
      Permissions.retailSaleRecord,
      Permissions.discountApplyItem,
      Permissions.discountApplyInvoice,
      Permissions.paymentView,
      Permissions.paymentRecord,
      Permissions.paymentAllocate,
      Permissions.chequeManage,
      Permissions.returnView,
      Permissions.returnCreate,
      Permissions.returnInspect,
      Permissions.creditNoteIssue,
      Permissions.expenseView,
      Permissions.expenseManage,
      Permissions.pettyCashView,
      Permissions.pettyCashManage,
      Permissions.salaryView,
      Permissions.reportsView,
      Permissions.reportsFinancial,
      Permissions.reportsExport,
      Permissions.auditView,
      Permissions.backupRun,
    ],
    storeKeeper: [
      Permissions.productsView,
      Permissions.agentsView,
      Permissions.shopsView,
      Permissions.stockView,
      Permissions.stockTransfer,
      Permissions.returnView,
      Permissions.returnCreate,
      Permissions.returnInspect,
      Permissions.reportsView,
    ],
    cashier: [
      Permissions.productsView,
      Permissions.agentsView,
      Permissions.shopsView,
      Permissions.stockView,
      Permissions.invoiceView,
      Permissions.invoiceCreate,
      Permissions.invoicePost,
      Permissions.retailSaleRecord,
      Permissions.discountApplyItem,
      Permissions.paymentView,
      Permissions.paymentRecord,
      Permissions.paymentAllocate,
      Permissions.reportsView,
    ],
    accountant: [
      Permissions.productsView,
      Permissions.agentsView,
      Permissions.shopsView,
      Permissions.employeesView,
      Permissions.stockView,
      Permissions.invoiceView,
      Permissions.paymentView,
      Permissions.paymentRecord,
      Permissions.paymentAllocate,
      Permissions.chequeManage,
      Permissions.returnView,
      Permissions.creditNoteIssue,
      Permissions.expenseView,
      Permissions.expenseManage,
      Permissions.pettyCashView,
      Permissions.pettyCashManage,
      Permissions.salaryView,
      Permissions.salaryManage,
      Permissions.financialLedgerView,
      Permissions.reportsView,
      Permissions.reportsFinancial,
      Permissions.reportsExport,
    ],
    agent: [
      Permissions.productsView,
      Permissions.agentsView,
      Permissions.shopsView,
      Permissions.stockView,
      Permissions.invoiceView,
      Permissions.paymentView,
      Permissions.paymentRecord,
      Permissions.paymentAllocate,
    ],
    viewer: [
      Permissions.productsView,
      Permissions.agentsView,
      Permissions.shopsView,
      Permissions.stockView,
      Permissions.invoiceView,
      Permissions.paymentView,
      Permissions.returnView,
      Permissions.reportsView,
    ],
  };
}
