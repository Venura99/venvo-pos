/// Immutable application-wide constants. Nothing secret belongs here.
class AppConstants {
  const AppConstants._();

  static const String appName = 'Venvo POS';
  static const String companyName = 'Venvo Global (Pvt) Ltd';
  static const String appVersion = '0.1.0';

  static const String currencySymbol = 'Rs. ';
  static const String currencyCode = 'LKR';

  /// Folder created under the Windows per-user application data directory.
  static const String dataFolderName = 'VenvoPOS';
  static const String databaseFileName = 'venvo_pos.sqlite';
  static const String attachmentsFolderName = 'attachments';
  static const String backupsFolderName = 'backups';
  static const String exportsFolderName = 'exports';

  /// Well-known codes of the locations created on first run.
  static const String mainWarehouseCode = 'WH-MAIN';
  static const String damagedLocationCode = 'LOC-DAMAGED';
  static const String supplierLocationCode = 'LOC-SUPPLIER';
  static const String customerLocationCode = 'LOC-CUSTOMER';
  static const String adjustmentLocationCode = 'LOC-ADJUSTMENT';
  static const String inTransitLocationCode = 'LOC-INTRANSIT';

  static const int passwordMinLength = 8;
  static const int pbkdf2Iterations = 120000;

  static const int defaultPageSize = 50;
  static const double minWindowWidth = 1180;
  static const double minWindowHeight = 720;
}

/// Keys of rows in the settings table.
class SettingKeys {
  const SettingKeys._();

  static const String businessName = 'business.name';
  static const String businessAddress = 'business.address';
  static const String businessPhone = 'business.phone';
  static const String businessEmail = 'business.email';
  static const String businessTaxId = 'business.tax_id';

  /// Changes whenever the logo is uploaded or removed (empty when there is
  /// none), so clients know to fetch it again. Written only by the server.
  static const String businessLogoVersion = 'business.logo_version';
  static const String invoiceFooterNote = 'invoice.footer_note';
  static const String themeMode = 'ui.theme_mode';
  static const String allowNegativeStock = 'inventory.allow_negative_stock';
  static const String lowStockOnlyActive = 'inventory.low_stock_active_only';
  static const String maxInvoiceDiscountBps = 'sales.max_invoice_discount_bps';
  static const String maxItemDiscountBps = 'sales.max_item_discount_bps';
  static const String autoBackupEnabled = 'backup.auto_enabled';
  static const String autoBackupRetentionCount = 'backup.retention_count';
  static const String lastAutoBackupAt = 'backup.last_auto_at';
  static const String seededVersion = 'system.seeded_version';

  /// Where cheque reminders go: one or more WhatsApp numbers, separated by
  /// commas, in international form (94771234567).
  static const String whatsappAdminNumbers = 'whatsapp.admin_numbers';

  /// How many days before a cheque's date the reminder is sent.
  static const String chequeReminderDaysBefore = 'cheques.reminder_days_before';
}

/// Keys of rows in the document_sequences table. A sequence is incremented
/// inside the same database transaction that inserts the document, which is
/// what guarantees unique document numbers under concurrent use.
class SequenceKeys {
  const SequenceKeys._();

  static const String agentTransfer = 'TRF';
  static const String shopSupply = 'SUP';
  static const String agentInvoice = 'AINV';
  static const String shopInvoice = 'SINV';
  static const String retailSale = 'RS';
  static const String stockAdjustment = 'ADJ';
  static const String openingStock = 'OPN';
  static const String purchase = 'PUR';
  static const String returnNote = 'RET';
  static const String creditNote = 'CN';
  static const String paymentReceipt = 'PAY';
  static const String expenseVoucher = 'EXP';
  static const String pettyCashVoucher = 'PC';
  static const String salaryVoucher = 'SAL';
  static const String reconciliation = 'REC';
  static const String journalBatch = 'JRN';
  static const String employeeAdvance = 'ADV';

  /// Master-record codes. These never reset on a new year, because an agent
  /// code is an identity rather than a document reference.
  static const String agentCode = 'AG';
  static const String shopCode = 'SH';
  static const String employeeCode = 'EMP';
  static const String warehouseCode = 'WH';
}

/// Stable codes of rows in the accounts table, used by the financial ledger.
class AccountCodes {
  const AccountCodes._();

  static const String cashOnHand = '1010';
  static const String pettyCash = '1020';
  static const String bank = '1030';
  static const String chequesInClearing = '1040';
  static const String receivableAgents = '1110';
  static const String receivableShops = '1120';

  /// What end customers owe on a shop's counter sales. Kept apart from
  /// [receivableShops] so a shop's wholesale debt is never mixed up with what
  /// its walk-in customers owe - the same separation the sales reports keep.
  static const String receivableRetail = '1130';

  /// Advances paid to employees, recovered from later salaries. An asset,
  /// because the employee owes the money back; paying one is therefore not a
  /// wage expense.
  static const String receivableEmployees = '1140';

  static const String inventory = '1200';
  static const String customerAdvances = '2010';
  static const String salariesPayable = '2020';
  static const String payableSuppliers = '2030';
  static const String ownersEquity = '3010';
  static const String salesRevenue = '4010';
  static const String salesDiscounts = '4020';
  static const String salesReturns = '4030';
  static const String costOfGoodsSold = '5010';
  static const String operatingExpenses = '5100';
  static const String salaryExpense = '5200';
  static const String stockWriteOff = '5300';
  static const String chequeBounceCharges = '5400';
}
