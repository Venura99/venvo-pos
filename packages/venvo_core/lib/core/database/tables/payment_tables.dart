import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import 'master_tables.dart';
import 'sales_tables.dart';
import 'system_tables.dart';

/// Payments, their allocation to invoices, and cheque lifecycle.
///
/// Two rules shape this schema:
///
/// * A payment is recorded independently of any invoice. Allocations are a
///   separate many-to-many table, so one payment can settle several invoices
///   and one invoice can be settled by several payments. The unallocated
///   remainder of an inbound payment is the party's advance.
///
/// * **A cheque is not cash until it clears.** A cheque payment is created
///   with [PaymentStatus.pending] and its allocations exist from the start,
///   but every outstanding-balance and cash figure counts only allocations
///   whose payment is [PaymentStatus.cleared]. Pending cheques are reported in
///   their own bucket, and a bounce simply flips the status back out of
///   `cleared` - no history is rewritten.

@DataClassName('Payment')
@TableIndex(name: 'idx_payments_receipt', columns: {#receiptNumber})
@TableIndex(name: 'idx_payments_date', columns: {#paymentDate})
@TableIndex(
  name: 'idx_payments_party',
  columns: {#partyType, #agentId, #shopId},
)
@TableIndex(name: 'idx_payments_status', columns: {#status, #method})
class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get receiptNumber => text().withLength(min: 1, max: 32)();
  TextColumn get direction => textEnum<PaymentDirection>()();
  TextColumn get method => textEnum<PaymentMethod>()();

  /// Cash, bank transfer and card payments are created already cleared.
  /// Cheques start pending.
  TextColumn get status => textEnum<PaymentStatus>().withDefault(
    Constant(PaymentStatus.pending.name),
  )();
  DateTimeColumn get paymentDate => dateTime()();

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
  IntColumn get employeeId => integer().nullable().references(
    Employees,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get payerName => text().nullable().withLength(max: 180)();

  /// Gross amount of the instrument, always positive.
  IntColumn get amountCents =>
      integer().check(amountCents.isBiggerThanValue(0))();

  /// Cache of the sum of this payment's allocations, maintained in the same
  /// transaction as the allocations themselves. The difference against
  /// [amountCents] is the unallocated advance.
  IntColumn get allocatedCents => integer().withDefault(const Constant(0))();

  TextColumn get bankName => text().nullable().withLength(max: 120)();
  TextColumn get referenceNumber => text().nullable().withLength(max: 64)();
  TextColumn get notes => text().nullable().withLength(max: 1000)();

  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get clearedAt => dateTime().nullable()();
  DateTimeColumn get bouncedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  IntColumn get cancelledByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get cancelReason => text().nullable().withLength(max: 500)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {receiptNumber},
  ];
}

/// Links money to the invoices it settles. Append-only in normal operation:
/// an allocation is withdrawn by inserting a negative counter-allocation, so
/// the trail of who allocated what stays intact.
@DataClassName('PaymentAllocation')
@TableIndex(name: 'idx_alloc_payment', columns: {#paymentId})
@TableIndex(name: 'idx_alloc_invoice', columns: {#invoiceId})
class PaymentAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paymentId =>
      integer().references(Payments, #id, onDelete: KeyAction.restrict)();
  IntColumn get invoiceId =>
      integer().references(Invoices, #id, onDelete: KeyAction.restrict)();

  /// Positive when settling, negative when an earlier allocation is withdrawn.
  IntColumn get amountCents => integer().check(amountCents.isNotValue(0))();
  TextColumn get notes => text().nullable().withLength(max: 300)();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
}

/// Cheque instrument details and clearance lifecycle. One row per cheque
/// payment.
@DataClassName('Cheque')
@TableIndex(name: 'idx_cheques_status', columns: {#status})
@TableIndex(name: 'idx_cheques_date', columns: {#chequeDate})
class Cheques extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paymentId =>
      integer().references(Payments, #id, onDelete: KeyAction.cascade)();
  TextColumn get chequeNumber => text().withLength(min: 1, max: 32)();
  TextColumn get bankName => text().withLength(min: 1, max: 120)();
  TextColumn get branchName => text().nullable().withLength(max: 120)();

  /// Date written on the cheque, which may be later than the date received.
  DateTimeColumn get chequeDate => dateTime()();
  TextColumn get status => textEnum<ChequeStatus>().withDefault(
    Constant(ChequeStatus.pending.name),
  )();
  DateTimeColumn get depositedAt => dateTime().nullable()();
  DateTimeColumn get clearedAt => dateTime().nullable()();
  DateTimeColumn get bouncedAt => dateTime().nullable()();
  TextColumn get bounceReason => text().nullable().withLength(max: 300)();

  /// Bank charge recovered from the party when a cheque bounces.
  IntColumn get bounceChargeCents => integer().withDefault(const Constant(0))();

  /// A replacement cheque or cash payment received after a bounce.
  IntColumn get replacementPaymentId => integer().nullable().references(
    Payments,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get notes => text().nullable().withLength(max: 500)();
  IntColumn get updatedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {paymentId},
    {chequeNumber, bankName},
  ];
}

/// Every attempt to send a WhatsApp reminder about a cheque coming due.
///
/// One row per attempt per recipient. A delivered row is what stops the same
/// reminder going out twice; a failed row keeps the reason, so a reminder that
/// could not be sent is visible rather than silently lost, and is retried on
/// the next run up to a limit.
@DataClassName('ChequeReminder')
@TableIndex(name: 'idx_cheque_reminders_cheque', columns: {#chequeId})
class ChequeReminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get chequeId =>
      integer().references(Cheques, #id, onDelete: KeyAction.cascade)();

  /// The number it was sent to, in international form without the plus.
  TextColumn get recipient => text().withLength(min: 1, max: 32)();
  DateTimeColumn get attemptedAt => dateTime()();
  BoolColumn get delivered => boolean()();
  TextColumn get error => text().nullable().withLength(max: 500)();
}
