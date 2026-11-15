# Business rules

Two parts: the rules the system enforces, and the questions the business still
has to answer. The second list matters — each item is a place where a wrong
assumption would produce wrong money.

---

## Part 1 — Rules the system enforces

### Inventory

| # | Rule | Where |
|---|---|---|
| I1 | Every stock movement writes a balanced pair of entries to `stock_ledger_entries`. | Phase 3 service; schema in place |
| I2 | `stock_balances` is never written without the matching ledger rows in the same transaction. | Phase 3 service |
| I3 | Any balance is reconstructable by replaying the ledger. | Guaranteed by the double-entry design |
| I4 | A real location may not go below zero. Only a user holding `stock.negative_override` can post anyway, and the override, the approver and the reason are recorded on the document. | `allow_negative_stock` setting + `StockTransactions.negativeStockOverride` |
| I5 | Both sides of a transfer are updated atomically, or neither is. | One database transaction |
| I6 | Posted documents are immutable; corrections are compensating documents. | `StockDocumentStatus`, `reversesTransactionId` |
| I7 | Returned goods do not become available stock until a disposition is recorded. A return posts in two legs, through goods-in-transit, and the ledger rejects a return document that skips transit. | `ReturnService.postReturn` + `recordInspection`; `stock.route_leg` |
| I8 | Defective and damaged quantities go to the quarantine location, never back to sellable stock. | `InspectionStatus.movedToDamaged` |
| I11 | An inspection must account for every returned unit: accepted + damaged + scrapped equals what came back, or nothing posts. | `return.inspection_accounts_for_every_unit` |
| I12 | A return cannot be cancelled while credit stands against it; the credit note is withdrawn first. | `return.cancel_requires_no_credit` |
| I9 | Document lines carry a strictly positive quantity; direction comes from the document's source and destination. | `CHECK` constraint |
| I10 | A ledger entry's quantity delta is never zero. | `CHECK` constraint |

### Billing

| # | Rule | Where |
|---|---|---|
| B1 | Every posted invoice has a unique number, allocated inside the posting transaction. | `document_sequences` + `UNIQUE` |
| B2 | A stock transfer is not revenue. Revenue requires an explicit invoice. | `InvoiceKind`, `Invoices.stockTransactionId` |
| B3 | Shop retail sales and wholesale supply to a shop are separate transactions. | `InvoiceKind.retailSale` vs `shopInvoice` |
| B4 | Lines snapshot name, SKU, unit price, discount and unit cost as billed. | `InvoiceItems.*Snapshot` |
| B5 | Discount input is preserved alongside the resolved cash amount, so a printed invoice can still show "10%" years later. | `discountType` + `discountValue` + `discountCents` |
| B6 | A discount beyond the configured ceiling requires `discount.exceed_limit`, and the approver is recorded. | `discounts.exceededLimit`, `approvedByUserId` |
| B7 | Every discount is recorded in the discount history regardless of size. | `discounts` table |
| B8 | Totals are stored, not recomputed on read. | `Invoices.netTotalCents` etc. |

### Money

| # | Rule | Where |
|---|---|---|
| M1 | Payments are recorded independently of invoices; allocation is a separate many-to-many. | `payment_allocations` |
| M2 | One payment may settle several invoices, and one invoice may be settled by several payments. | Same |
| M3 | Unallocated inbound money is the party's advance, not income. | `amountCents - allocatedCents` |
| M4 | **Outstanding balances count only allocations whose payment is `cleared`.** | Every receivable query |
| M5 | A cheque starts `pending` and is never counted as cash or as a collection until cleared. | `PaymentStatus`, `ChequeStatus` |
| M6 | A bounce restores the receivable by changing status, never by deleting a payment or an allocation. | `PaymentStatus.bounced` |
| M7 | An allocation is withdrawn by inserting a negative counter-allocation, so the trail stays intact. | `payment_allocations.amountCents` may be negative |
| M8 | Credit notes are applied to invoices the same way payments are, so credit cannot vanish into a balance. | `credit_note_applications` |
| M9 | Goods returns and financial credit are separate records, linked. A credit note is issued only against an inspected return, and never for more than the inspection accepted. | `credit_note.requires_inspection`, `credit_note.within_returned_value` |
| M11 | Scrapped goods earn no credit; damaged goods still do, because they came back. | `ReturnLineView.creditableValue` |
| M12 | A credit note belongs to one party and can only be applied to that party's invoices. | `credit_note.same_party` |
| M13 | Credit and a cheque in clearing cannot both claim the same part of an invoice. | `credit_note.no_over_allocation` |
| M10 | Every financial event posts a balanced batch of double-entry rows; a cheque receipt debits *Cheques in Clearing*, not *Cash*. A posting that does not balance is refused. | `finance.batch_must_balance` |
| M14 | The receivable moves only on **cleared** money, in the journal as well as in the registers: allocating an uncleared cheque posts nothing, and clearing it posts the settlement. | `PaymentService._insertAllocation`, `clearCheque` |
| M15 | Money received but not applied to an invoice is a liability, not income. | Credited to *Customer Advances* |
| M16 | A journal batch is corrected by a reversing batch, never by editing or deleting rows, and a batch can only be reversed once. | `finance.reverse_once` |
| M17 | Cancelling a document reverses the batch it posted, rather than inferring the opposite accounts. | `FinancialLedgerService.reverse` |
| M18 | An employee advance is an asset, not a wage cost; recovering it from a salary is a deduction, so the wage is an expense exactly once. | *Receivable - Employee Advances* |
| M19 | A salary is an expense when it is **approved**, not when it is paid. Paying it settles a debt. | `postSalaryApproved` vs `postSalaryPaid` |
| M20 | An expense paid from petty cash reduces the float through one linked entry and posts one journal batch. | `Expenses.pettyCashEntryId`, `appendEntry(postToJournal: false)` |
| M21 | The petty cash float may not go below zero. | `petty_cash.no_negative_float` |
| M22 | Moving the business own cash between the cash box and the float is a transfer, not a cost; cash counted short or over is a loss or a gain. | `postPettyCashTransfer` vs `postPettyCashAdjustment` |

### Security and audit

| # | Rule | Where |
|---|---|---|
| S1 | No credential is hardcoded; the first administrator is created at first run. | `DatabaseSeeder` creates no user |
| S2 | Passwords are PBKDF2-HMAC-SHA256 with a per-user salt and a stored cost. | `PasswordHasher` |
| S3 | Permission checks live in the repository, not the UI. | `AuthenticatedUser.require` |
| S4 | Wrong password and unknown username are indistinguishable to the caller. | `AuthRepository.signIn` |
| S5 | The last active administrator cannot be disabled or demoted. | `auth.keep_one_admin` |
| S6 | Every significant action is written to the append-only audit log, inside the operation's own transaction. | `AuditService` |
| S7 | No password appears in any log, audit row or error message. | Asserted by test |
| S8 | A database from a newer release is refused rather than misread. | `AppDatabase.migration.beforeOpen` |
| S9 | Taking a backup and restoring one are separate permissions: protecting the data and overwriting it are different acts. | `backup.run` vs `backup.restore` |

### Backup and restore

| # | Rule | Where |
|---|---|---|
| K1 | The write-ahead log is folded into the database file before it is copied, so an archive always holds the newest commits. | `BackupService._checkpoint` |
| K2 | An archive is validated by opening its database read-only and running SQLite's own integrity check, not by trusting that it unzipped. | `BackupService.validate` |
| K3 | An archive written by a newer release is refused, the same way the database itself refuses a newer file. | `validate`, schema version check |
| K4 | A restore archives the live data first, so it can itself be undone. | `BackupService.restore` |
| K5 | A restore is staged and applied at the next start, before the database is opened; the live file is moved aside rather than deleted, and its write-ahead sidecars are removed. | `applyPendingRestore` |
| K6 | A staged restore can be cancelled, leaving the live data untouched. | `cancelPendingRestore` |
| K7 | Two backups in the same second get different names, so the safety copy taken before a restore cannot overwrite the archive being restored from. | `_nextFreeName` |
| K8 | Automatic backups are pruned to the retention limit; a backup taken by hand is never deleted for the user. | `pruneOldBackups` |
| K9 | An attachment path inside an archive that would escape the attachments folder is ignored: an archive is a file from outside the application. | `_escapesFolder` |

### Reporting

| # | Rule | Where |
|---|---|---|
| R1 | A report computes every figure the same way as the screen it mirrors; the tests assert the agreement rather than re-deriving it. | `reports_test.dart` |
| R2 | A report carries its own caveats, and they print on the PDF and are written into the CSV. | `ReportResult.notes` |
| R3 | The profit and loss states whether the trial balance for the period balanced, and says the figures cannot be relied on if it did not. | `ReportRepository._profitAndLoss` |
| R4 | A report is only offered to a user who holds the permission of the module it reads. | `ReportDefinition.permission`, `visibleReportsProvider` |
| R5 | A CSV export holds bare numbers so a spreadsheet can total them, with a UTF-8 byte-order mark. | `ReportExportService.buildCsv` |
| R6 | A totals row sums only the columns where a sum means something; a margin is recomputed and a running balance is left alone. | `ReportColumn.totalled` |

---

## Part 2 — Decisions still needed

These are not implementation gaps. They are places where the brief does not say
what the business wants, and where I have had to pick a default. Each default
is safe and reversible, but **please confirm or correct them before the relevant
phase**, because changing them after real data exists means a data migration.

### 1. Does a pending cheque reduce what a shop owes? — *decided, please confirm*

**My default: no.** A cheque reduces nothing until it clears. It is visible on
the invoice as "Rs. 10,000 received, pending clearance", and the receivable
stays at the full amount.

This is the conservative reading and matches Scenario 9 and Rule 9. The
alternative (receivable drops on receipt, with a separate "cheques in hand"
asset) is also defensible and is what some distributors do. If agents are used
to being told their balance is cleared the moment they hand over a cheque, say
so now.

### 2. Who bears the cost of a bounced cheque?

The schema has `cheques.bounceChargeCents`. Nothing yet says whether the bank
charge is recovered from the shop, absorbed as an expense, or both. **Default:
recorded on the cheque and recoverable from the party, but not automatically
invoiced.** Phase 4 needs the answer.

### 3. Does an agent own the stock he holds, or is it on consignment?

This is the most consequential open question in the whole system.

- **Consignment** — the goods stay the company's asset until the agent sells
  them. A warehouse-to-agent transfer is then *only* a stock movement and
  creates no receivable.
- **Sale to the agent** — the agent owes for the goods on delivery. The
  transfer creates a receivable immediately.

The brief asks for both to be possible ("Support both stock transfers and
financially chargeable agent invoices as separate concepts"), which is what the
schema does. But the business needs a **default** for daily operation, because
staff should not be deciding this per transfer. **My default: consignment** —
a transfer moves stock only, and an agent invoice is raised explicitly. Please
confirm.

### 4. Stock valuation method

**Default: weighted average cost**, maintained per location on
`stock_balances.averageCostCents`. FIFO was not chosen because it needs cost
layers per receipt, which roughly doubles the ledger's complexity for a
business whose purchase prices move slowly. If the accountant requires FIFO,
now is the time to say so — retrofitting it later is a migration.

### 5. Gross profit on inter-location movements

Profit is currently recognised once, on the invoice to the final party, using
the cost snapshotted on each line. A warehouse-to-agent transfer at a marked-up
"transfer price" does **not** create profit. This is correct accounting, but
means an agent-wise profit report measures the margin on *invoices to that
agent*, not the margin the agent makes. Confirm this is the intended reading.

### 6. Shop credit limit — warn or block?

`shops.creditLimitCents` exists. **Default: warn on exceeding it, and let a
user with invoice-posting permission continue.** A hard block would stop a
delivery van at the door. If it should be a hard block requiring an override
permission, that needs to be a separate permission.

### 7. Is a shop's retail sale the company's revenue?

Recording what a shop sold to end customers is needed for stock accuracy and
for sales reports. But if a shop is an independent business that has already
bought the goods, its retail sales are **its** revenue, not Venvo's, and
including them in "today's sales" would double count the same goods.

**Default: retail sales are recorded and reported separately, and are not added
to company revenue alongside the wholesale invoice for the same goods.** The
dashboard currently sums all posted invoices.

Phase 6 has made the separation concrete rather than notional: a retail sale
posts to its own *Receivable - Retail Customers* account, so a shop's
wholesale debt and what its walk-in customers owe are separate figures in the
journal as well as in the reports. It does still credit *Sales Revenue*, which
means the profit and loss includes retail sales. **Please confirm whether it
should.** If a shop is an independent business, the honest answer is probably
that it should not, and the fix is a separate revenue account for retail - a
small change while the question is still open, a migration once there is data.

Phase 7 holds the line everywhere it can: the sales reports cover wholesale
invoices only, and the dashboard shows retail on its own line rather than
folding it into the month's sales. So the only place the two are added
together today is the profit and loss, which is exactly the figure the answer
to this question changes.

### 8. Agent commission — when is it earned and how is it paid?

`agents.commissionBps` is stored but nothing computes it. Is commission earned
on goods delivered, on goods the shop paid for, or on collections received?
Is it deducted from the agent's payable or paid as a separate expense? Phase 6
needs this.

### 9. Opening balances: one figure, or open items?

`agents.openingBalanceCents` and `shops.openingBalanceCents` carry a single
pre-system balance, included in receivables. That figure cannot be aged or
allocated against a specific old invoice. If the business needs to track which
pre-system invoices are still unpaid, those invoices must be entered
individually instead. **Default: a single figure.**

### 10. Returns beyond the quantity originally sold

`invoice_items.returnedQuantity` caps a return at what was billed on that line.
Returns that cannot be traced to an invoice are allowed, but then nothing caps
them. **Default: an untraced return requires a reason and is permitted**, and
that is what is built: the quantity is still capped by what the returning
location actually holds, because the receipt leg goes through the stock ledger
like any other movement. Confirm whether an untraced return should instead
require an authorisation permission of its own.

### 11. Tax

No tax or VAT handling exists. `settings` has a `business.tax_id` field and
invoices have no tax columns. If Venvo must charge VAT, that is a schema change
(tax rate per product, tax amount per line, a tax summary per invoice) and it
is far cheaper to add in Phase 4 than in Phase 7. **Please confirm tax is out
of scope.**

### 12. Multi-currency

Everything is LKR. Nothing stores a currency code. Confirm this is correct for
the foreseeable future.

### 13. Are returns in transit part of inventory value?

Between the receipt leg and the inspection, returned goods sit in the virtual
`inTransit` location, which is excluded from inventory valuation. For the
length of the inspection window the goods are therefore on nobody's balance
sheet: the returning party no longer holds them, and the business has not yet
accepted them.

That matches the credit rule - nothing is credited until somebody has looked
at the goods - and it keeps a disputed return out of the stock value until it
is resolved. The cost of it is that a large return left uninspected understates
inventory. **Default: not valued while in transit.** Confirm, or say that
returns in transit should be valued at the price they were billed at.



### 14. Is a bounced-cheque charge recovered from the party?

A bank charge on a bounced cheque is currently the business expense: it is
debited to *Cheque Bounce Charges* and credited to the bank. Many wholesalers
pass it on to whoever gave them the cheque.

**Default: the business bears it.** Confirm, or say that it should be added to
what the party owes - which would mean a debit to their receivable rather than
to an expense, and a line on their statement.

---

## Rounding

One rule, applied everywhere: **integer arithmetic, rounding half away from
zero.**

- A percentage discount is `amount × bps ÷ 10000`, rounded half away from zero.
  10% of Rs. 0.05 is 1 cent, not 0.
- Splitting an invoice-level discount across lines uses
  `Money.allocateEvenly`, which spreads the remainder cents over the leading
  shares so the parts always sum exactly to the whole.
- No amount is ever rounded for display and then stored.

