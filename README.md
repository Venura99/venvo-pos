# Venvo POS

Offline-first wholesale POS and inventory management for **Venvo Global (Pvt) Ltd** —
a Flutter Windows desktop application covering the warehouse, agents, shops,
billing, collections, returns and finances of a mobile-accessories distribution
business.

Everything runs on one Windows computer with no internet connection. The
architecture is prepared for a later move to a shared SQL Server and multiple
clients, but nothing in Phase 1 depends on a network.

---

## Current status

**All eight phases are complete.** 673 tests pass and `flutter analyze` reports
no issues.

| Phase | Scope | State |
|---|---|---|
| 1 | Project, architecture, database, migrations, theme, navigation, dashboard, authentication, settings, audit log | **Done** |
| 2 | Products, categories, agents, shops, employees, warehouses | **Done** |
| 3 | Opening stock, stock ledger, agent transfers, shop supply, reconciliation | **Done** |
| 4 | Invoices, discounts, payments, cheques, PDF documents | **Done** |
| 5 | Returns, inspection, damaged stock, credit notes | **Done** |
| 6 | Expenses, petty cash, salaries, financial ledger | **Done** |
| 7 | Dashboard KPIs, the 18 reports, PDF/CSV export | **Done** |
| 8 | Backup/restore, installer, performance, user documentation | **Done** |

What works today, against real data:

- First-run creation of the administrator account, sign-in with lockout after
  repeated failures, and forced password change after an administrator reset.
- Six seeded roles with a documented permission set each; user and role
  administration.
- An audit log that records every sign-in, failure, lockout and settings
  change, with filtering and search.
- Settings: business details, the negative-stock policy, discount ceilings,
  backup preferences and light/dark/system theme — all persisted.
- A dashboard whose figures are read live from the schema. On an empty
  database every figure is a true zero, and it lights up as later phases add
  data.
- **Product catalogue** with cost, wholesale and retail prices, pack sizes,
  reorder levels, live margin feedback, and stock shown per location kind.
  Search, filters and sorting run in SQL.
- **Categories**, optionally nested, with cycle protection and a refusal to
  archive anything still carrying active products.
- **Agents**, each with their own stock location created in the same database
  transaction, commission rate, opening balance, and an outstanding balance
  that counts only cleared money.
- **Shops**, each with their own stock location, a credit limit that is
  tracked and flagged, and agent reassignment that moves one pointer and
  leaves every past document untouched.
- **Employees** with designations, joining dates, basic salary, and the
  advances and unpaid salary they carry.
- **Warehouses and locations**, including additional warehouses and a view of
  the virtual counterparty locations that make the ledger balance.
- **The stock ledger.** Opening stock, purchases, warehouse-to-agent
  transfers, agent-to-shop supply, direct supply, inter-warehouse moves,
  adjustments and damage write-offs. Each posting writes a balanced pair of
  ledger entries and updates both balance caches in one transaction.
- **Stock overview** by product across the warehouse, agents, shops, transit
  and quarantine, with valuation and low-stock flags.
- **Movement history** reading the append-only ledger, with the running
  balance each entry left behind and an option to show the counterparty legs.
- **Stock reconciliation**: open a count sheet (system quantities snapshotted
  at that moment), record what was found, and post the variances as
  adjustment documents.
- **Cancel and reverse** a posted document: the original and its ledger rows
  are kept, and a compensating document puts the goods back.
- **Invoices** for agents, shops and retail sales, with item-level and
  invoice-level discounts, ceilings enforced per user, and a discount history.
- **Billing a delivery**: posted transfers that have not been invoiced are
  listed on the invoice screen, which is where a delivery note becomes
  revenue.
- **Payments** by cash, bank transfer, cheque or card, allocated across
  invoices, with an oldest-first auto-apply and unapplied money held as an
  advance.
- **Cheque register** tracking each cheque from received, through banked, to
  cleared or bounced, with post-dated cheques blocked from banking early.
- **PDF invoices, receipts and delivery notes**, saved under the exports
  folder and reprintable from the stored record.
- **Returns** from a customer to a shop, a shop to its agent, an agent to the
  warehouse, or a shop straight to the warehouse with explicit authorisation.
  Posting a return takes the goods out of the returning location at once but
  parks them in goods-in-transit, so nothing re-enters sellable stock unseen.
- **Inspection** of every returned line, splitting it between accepted,
  damaged and scrapped. Accepted units go to the receiving location, damaged
  units to the quarantine store, scrapped units out through the adjustment
  counterparty. The split must account for every unit that came back.
- **Credit notes** raised only against an inspected return and only up to what
  the inspection accepted, applied to invoices exactly the way payments are
  allocated — so credit can be spread over several invoices, withdrawn again,
  and never vanishes into a balance. Scrapped goods earn no credit.
- **Expenses** by category, paid from the cash box, the bank or the petty
  cash float, with the per-category breakdown on the same screen as the
  vouchers. Cancelling one keeps the voucher and reverses the accounting.
- **Petty cash** as a proper cash book: an opening float, top-ups, cash
  returned, and shortages or surpluses found when counting. Every row carries
  the balance as it stood after it, the float can never be driven below what
  is in the box, and an expense paid from it reduces it exactly once.
- **Salaries** computed as a draft, approved to become payable, then paid in
  full or in parts. An advance is an asset the employee owes back, recovered
  by deduction at approval, oldest advance first - so the wage is counted as a
  cost once and never twice.
- **The financial ledger**: a double-entry journal that every invoice,
  payment, cheque, credit note, stock write-off, expense and salary posts to,
  in the same transaction as the record itself. With a profit and loss and a
  trial balance read from it, and any figure traceable back to what caused it.
- **The eighteen reports** the brief asks for - five on sales, five on stock,
  four on money, four on finance - built from the same definitions the screens
  use, so a figure on a report and the register it came from cannot disagree.
  Each one carries its own caveats, and they print.
- **Export to PDF and CSV.** The PDF is laid out for reading (landscape for a
  wide report, the period in the header, the caveats under the table); the CSV
  holds bare numbers so a spreadsheet can add them up, with a byte-order mark
  so Excel on Windows reads it as UTF-8.
- **A dashboard** that now covers the whole business: today, the month, an
  inspection queue and what needs attention, and the cash and advances. Net
  profit is read from the journal rather than estimated, so it agrees with the
  profit and loss.
- **Backups**: one archive holding the database and every attachment, with
  the write-ahead log folded in first so it always has the newest changes.
  An automatic one a day, kept to a retention limit; ones taken by hand are
  never pruned.
- **Restore**, which validates before it trusts: the archive is opened,
  SQLite checks it over, and the row counts shown are read out of the file
  rather than from its manifest. The live data is archived first, and the
  restore is staged and applied on the next start - the only moment the file
  can safely be swapped.
- **A Windows installer script** (Inno Setup) that installs per-user without
  administrator rights and leaves the data folder alone on both upgrade and
  uninstall.
- **A user guide** at [docs/user-guide.md](docs/user-guide.md), written for
  whoever has to use this every day.

Every module in the sidebar is built. Through the earlier phases the ones not
yet written opened a page that said so plainly and listed what it would do;
there is nothing left pointing at it, which is what finishing phase 8 means.
Nothing in the application presents a non-functional control as if it worked.

---

## Requirements

- Flutter 3.32 or newer, on the stable channel (currently built and tested
  against Flutter 3.47.9)
- **Visual Studio 2022 Build Tools with the "Desktop development with C++"
  workload** — required to compile the Windows runner

Windows is the only platform this project targets, and deliberately so: the
database is a SQLite file opened over `dart:ffi`, attachments and backups are
real files on a local disk, and none of that exists in a browser. Do not add a
web target — selecting Chrome or Edge as the run device compiles
`package:sqlite3` against a platform that has no `dart:ffi` and fails with a
wall of *"Type 'ffi.NativeFunction' not found"* errors.

> **The application builds and runs.** Verified on 14 November 2026 against
> Visual Studio Community 2026 (18.11) with the Desktop development with C++
> workload: `flutter build windows --debug` completes in about 30 seconds, the
> executable starts, `window_manager` sets the window, and the first run
> creates its data directory and seeds the database. Earlier revisions of this
> file said the toolchain was missing; it is not.
>
> If you are setting up a fresh machine and `flutter doctor` reports *"Unable
> to find suitable Visual Studio toolchain"*, install the workload with:
>
> ```
> winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
> ```

## Working on the project

```bash
flutter pub get                                      # dependencies
dart run build_runner build --delete-conflicting-outputs   # Drift codegen
flutter analyze                                      # must report no issues
flutter test                                          # must be fully green
flutter run -d windows                                # needs the C++ toolchain
```

Re-run `build_runner` after any change to a file under
`lib/core/database/tables/`.

To produce an installer, once the C++ toolchain is in place:

```bash
flutter build windows --release
iscc installer\venvo-pos.iss
```

That needs [Inno Setup 6](https://jrsoftware.org/isinfo.php) and writes to
`installer/output/`. The script installs per-user, so it needs no
administrator rights, and leaves `%APPDATA%\lk.venvoglobal\VenvoPOS` alone on
both upgrade and uninstall — the program folder and the business's data are
deliberately separate. **It has not been run** yet; it is written against
Inno Setup's
documented behaviour and the known layout of a Flutter release build, and
verifying it is the first thing to do once the toolchain is installed.

---

## Architecture

Clean architecture, with one folder per feature and three layers inside each.

```
lib/
  core/
    bootstrap/      composes the object graph before the first frame
    constants/      app constants, setting keys, sequence keys, permissions
    database/       Drift schema, connection, migrations, seed
      tables/       table definitions, grouped by domain
    enums/          every enumeration persisted in the database
    errors/         AppFailure hierarchy and the guard helpers
    providers/      Riverpod providers for the shared services
    router/         routes, navigation model, GoRouter configuration
    services/       paths, clock, password hashing, sequences, settings, audit
    theme/          design tokens and the Material 3 themes
    widgets/        the reusable component library and the app shell
  features/
    <feature>/
      data/         repositories: all SQL lives here
      domain/       entities and business rules, no Flutter imports
      presentation/ screens, controllers, widgets
```

**State management** is Riverpod. `appBootstrapProvider` is the single root of
the dependency graph and is overridden in `main` with the composed
`AppBootstrap`; tests override it with the same graph over an in-memory
database. Nothing reaches for a singleton.

**Business logic never lives in a widget.** Permission checks happen in the
repository (`AuthenticatedUser.require`), not in the UI, so an operation cannot
be reached another way and skip its check.

---

## The decisions that matter

### 1. Money is integer cents; percentages are basis points

Every amount is an `int` of minor currency units, stored as SQLite `INTEGER`
and carried in Dart as the `Money` value type. No `double` touches money
anywhere. Percentage discounts are stored in **basis points** (10% = 1000), so
a discount is an exact integer and `Money.percentage` rounds half away from
zero rather than drifting.

Rs. 20,000 less 10% is exactly Rs. 18,000, and the test suite says so.

### 2. Quantities are whole base units, with pack conversion at entry

Stock is counted in whole base units. Packs are handled by
`Product.unitsPerPack`: "2 boxes of 12" is converted to 24 units when it is
typed in. Decimal quantities across a ledger invite rounding drift for no
benefit on discrete accessories.

### 3. The stock ledger is double-entry

Three layers, in order of authority:

1. `stock_transactions` / `stock_transaction_items` — the business document a
   user sees and prints.
2. `stock_ledger_entries` — **the truth**. Append-only. Each posted line
   writes a *pair* of signed entries: negative at the source, positive at the
   destination.
3. `stock_balances` — a cache of the current quantity per
   (location, product), written in the same transaction and fully
   reconstructable by replaying layer 2.

Four **virtual locations** (`SUPPLIER`, `CUSTOMER`, `ADJUSTMENT`, `IN_TRANSIT`)
give every movement a counterparty, so the sum of `quantity_delta` across all
locations for a product is always zero. A purchase is a transfer from
`SUPPLIER`; a retail sale is a transfer to `CUSTOMER`; a stock-take variance is
a transfer to or from `ADJUSTMENT`. Nothing can leak, and reconciliation is a
single `SUM`.

Nothing in the application may write to `stock_balances` without writing the
matching ledger rows in the same database transaction.

### 4. A cheque is not cash until it clears

A cheque payment is created with status `pending` and its allocations exist
from the start — but **every outstanding-balance and collections figure counts
only allocations whose payment is `cleared`.** Cash and bank transfers are
created already cleared; cheques must be cleared or bounced explicitly, and
sit in a `Cheques in Clearing` account meanwhile.

A bounce flips the status back out of `cleared`, which restores the receivable
without editing or deleting a single historical row. The common shortcut —
reducing the receivable on receipt — silently overstates collections, so it is
not used here.

### 5. A transfer is not a sale

Moving goods from the warehouse to an agent writes a stock document. Revenue is
recognised only when an `invoices` row of kind `agentInvoice` is explicitly
raised, optionally pointing at that document. A delivery note can therefore
never be double counted as revenue.

Retail sales share the `invoices` table with an `invoice_kind` discriminator
rather than duplicating the entire payment and allocation machinery. They
remain separate *transactions*; reports filter by kind.

### 6. History is immutable

- Posted documents are never edited or deleted. They are reversed by a
  cancellation plus a compensating ledger.
- Invoice lines snapshot the product name, SKU, unit price, discount and unit
  cost as they were when billed, so a later rename or re-pricing cannot rewrite
  what a customer was charged.
- Master data is soft-deleted by moving to `archived`, so historical foreign
  keys keep resolving.
- `stock_ledger_entries`, `financial_ledger_entries` and `audit_logs` are
  append-only.

### 7. A return is two movements, with inspection between them

Returned goods are not stock. If a return posted straight into the receiving
location, the goods would be sellable the moment they arrived — before anybody
had looked at them — and an agent could promise units that turn out to be
defective.

So a return posts in two legs, each a real ledger movement:

1. **Receipt.** Out of the returning location, into the virtual
   **goods-in-transit** location. The returning party's balance drops at once,
   because they genuinely no longer hold the goods.
2. **Disposition**, after inspection. Out of transit: accepted units to the
   return's receiving location, damaged units to the quarantine store,
   scrapped units out through the adjustment counterparty.

The ledger enforces this. `_assertRouteValid` checks a return's source and
destination **as a pair**, so a shop-to-agent document that skips transit —
and therefore skips inspection — is rejected rather than quietly accepted.

The inspection must account for every returned unit: accepted + damaged +
scrapped has to equal what came back, or nothing posts. That is what stops a
quantity being stranded in transit, where no stock report would look for it.

One consequence is deliberate and worth stating: while goods sit in transit
they are **not** counted in inventory valuation, because `inTransit` is a
virtual location. Between receipt and inspection the goods belong to nobody's
balance sheet, which matches the rule that no credit is raised until somebody
has inspected them. Whether returns in transit should instead be valued is
open question 13 in `docs/business-rules.md`.

### 8. Every financial event posts to one journal

The operational records — invoices, payments, returns, expenses, salaries —
each answer their own question. The journal is the one place where they are
all reconciled, and it is what stops the same money being counted twice.

Three rules make it trustworthy:

- **A batch must balance.** `FinancialLedgerService.post` refuses a posting
  whose debits and credits differ, so an unbalanced journal is not a state the
  application can get into. `findUnbalancedBatches()` is checked by a test and
  shown on the ledger screen rather than assumed.
- **It is written in the same transaction as the record it describes.** A
  business event and its accounting either both exist or neither does.
- **It is append-only.** A mistake is corrected by `reverse()`, which posts
  the mirror image of a batch. Cancelling a document reverses *the batch it
  actually posted* rather than guessing which accounts the opposite movement
  would touch — which is why cancelling opening stock credits inventory
  against owner's equity instead of booking a loss.

Where the accounts are chosen deliberately:

| Event | Posting | Why |
|---|---|---|
| Cheque received | Dr **Cheques in Clearing**, Cr Customer Advances | Paper in a drawer is neither cash nor bank money |
| Cheque cleared | Dr Bank, Cr Cheques in Clearing — *and only now* the receivable comes down | Matches `outstandingOf`, which counts cleared money only |
| Cheque bounced after clearing | Cr **Bank**, not clearing | The money really had reached the bank |
| Money received, not yet applied | Cr **Customer Advances**, a liability | The business owes goods or a refund, and has earned nothing |
| Invoice posted | Cr Sales Revenue at the **full** price, Dr Sales Discounts separately | A discount is visible as a discount, not as a smaller sale |
| Employee advance | Dr **Receivable – Employees**, an asset | The employee owes it back, so paying it is not a wage cost |
| Salary approved | Dr Salary Expense, Cr Salaries Payable **and** Cr Receivable – Employees | The advance is settled by deduction; the wage is a cost exactly once |
| Expense from petty cash | Cr **Petty Cash**, with one linked entry in the cash book | The cash movement exists once, not twice |
| Transfer between own locations | nothing | Nothing the business owns has changed |

The subtle one is the third and fourth rows together. Allocating an uncleared
cheque to an invoice posts **nothing**: it reserves the invoice against
further allocation but settles nothing, and the settlement is posted when the
cheque clears. Without that, the journal would show an invoice as paid while
every other report in the application correctly showed it outstanding.

### 9. A report cannot disagree with its screen

A report is what leaves the building. It gets printed, emailed and taken to a
meeting, where nobody can ask what a column means. So two rules:

**One definition, used everywhere.** Every report computes settlement, posting
status and party balances exactly as the screen it mirrors does — cleared
money only, posted credit notes count, retail kept apart from wholesale. The
report tests assert the agreement directly rather than re-deriving it: the
agent-wise sales report's "outstanding now" is compared against
`payments.outstandingOf`, and the outstanding-balances report against what the
shop screen shows.

**The caveats travel with the figures.** A `ReportResult` carries its own
`notes`, and they are printed under the PDF table and written into the CSV. A
collections total that counts only cleared money says so on the page; the
profit-and-loss report states whether the trial balance for that period
balanced, and says plainly that the figures cannot be relied on if it did not.

The export formats differ on purpose. The PDF is for reading: landscape once a
report has more than six columns, the period in the header, page numbers in the
footer. The CSV is for a spreadsheet, so money goes out as a bare
`27000.00` rather than `Rs. 27,000.00` — an export that cannot be summed in
Excel is not much of an export — with a UTF-8 byte-order mark, without which
Excel on Windows reads the file in the system codepage and mangles every
separator.

### 10. A backup is only worth having if it can be restored

Three things make the difference between a backup and a file that looks like
one.

**The write-ahead log is folded in first.** SQLite in WAL mode keeps recent
commits in a side file, so copying `venvo_pos.sqlite` alone can silently leave
the newest transactions out. Every backup runs
`PRAGMA wal_checkpoint(TRUNCATE)` before the copy. Without it an archive looks
fine and quietly misses the last few invoices — the worst possible failure,
because you only find out when you need it.

**An archive is validated by opening it.** `validate` unpacks the database to a
scratch file, opens it **read-only**, runs SQLite's own `integrity_check`, and
counts the rows it would be restoring. The figures shown before a restore come
out of the archive, not from its manifest. An archive written by a newer
release is refused — the same refusal the database itself makes on open,
because reading a newer file with older column expectations corrupts data
silently.

**A restore is staged, not applied in place.** The database this process has
open cannot be swapped underneath it: repositories, providers and open query
streams all hold the live connection. So the current data is archived first,
the incoming files are written beside the live ones, and a marker is left that
`AppBootstrap.initialise` acts on during the next start, before anything opens
the database. The live file is moved aside rather than deleted, and the old
`-wal` and `-shm` sidecars are removed — leaving a log belonging to one
database beside a different one is how a restored file gets corrupted.

Taking a backup and restoring one are separate permissions. Somebody who can
protect the data cannot necessarily overwrite it.

### 11. Performance is checked by query plan, not by stopwatch

`test/core/performance_test.dart` asks SQLite how it would run each hot query
and fails if it says it would scan a table that grows with the business, or
sort one in a temporary B-tree. That is deterministic — it does not depend on
how fast the machine happens to be — and it fails the moment an access pattern
appears that no index covers, which is when it is cheap to fix.

It found two on the first run: the stock movement history and the invoice
register both read "this one thing, newest first", and with separate indexes
on the key and on the date SQLite used one for the filter and then sorted the
whole result. Three composite indexes fixed it, which is what schema version 2
adds.

One nuance worth recording, because it is easy to get backwards: SQLite words
an index-ordered traversal as `SCAN t USING INDEX idx`, which is exactly what
is wanted. The two things worth failing on are a bare `SCAN t` and a
`USE TEMP B-TREE FOR ORDER BY`.

Beside that, the same file posts a few thousand rows through the real services
and checks the invariants still hold and the headline reads still come back
promptly. The time bounds are generous on purpose: they are there to catch an
accidental O(n²), not to benchmark a machine.

### 12. Failures leave nothing half-applied

Every multi-step stock or financial operation runs inside one database
transaction. Document numbers are allocated by incrementing a counter row
*inside that same transaction*, which is what makes them unique and what stops
a failed posting from burning a number. Both facts are covered by tests.

### 13. Security

- Passwords are hashed with PBKDF2-HMAC-SHA256, a random 16-byte salt per user
  and the iteration count stored per hash, so the cost can be raised later
  without locking anyone out. The implementation is checked against a
  published test vector.
- **No credential is hardcoded anywhere.** The first administrator is created
  by whoever installs the software, through the first-run screen. There is no
  default password.
- Wrong password and unknown username return the identical message, so the
  sign-in screen cannot be used to discover valid usernames.
- Accounts lock for 5 minutes after 5 failed attempts.
- The last active administrator cannot be disabled or stripped of the
  administrator role — on an offline database that would lock everybody out
  with no recovery path.
- Opening a database file written by a *newer* release is refused rather than
  read with the wrong column expectations. (Drift migrates forward but does
  not guard this itself.)

---

## Database

40 tables, grouped by domain. Full definitions are in
`lib/core/database/tables/`, and the rules each one enforces are documented
alongside the columns.

| Group | Tables |
|---|---|
| System & security | `users`, `roles`, `permissions`, `role_permissions`, `user_roles`, `settings`, `document_sequences`, `audit_logs`, `attachments`, `backup_records` |
| Master data | `categories`, `products`, `agents`, `shops`, `employees`, `inventory_locations` |
| Inventory | `stock_transactions`, `stock_transaction_items`, `stock_ledger_entries`, `stock_balances`, `stock_counts`, `stock_count_items` |
| Billing | `invoices`, `invoice_items`, `discounts` |
| Payments | `payments`, `payment_allocations`, `cheques` |
| Returns | `returns`, `return_items`, `credit_notes`, `credit_note_applications` |
| Finance | `accounts`, `financial_ledger_entries`, `expense_categories`, `expenses`, `petty_cash_entries`, `employee_advances`, `salaries`, `salary_payments` |

Conventions:

- Primary keys are `INTEGER` autoincrement; foreign keys are declared with
  `RESTRICT`/`SET NULL`/`CASCADE` chosen per relationship, and
  `PRAGMA foreign_keys = ON` is set on every connection.
- Money columns end in `Cents` and are `INTEGER`.
- Dates are ISO-8601 **UTC text**: readable in any SQLite browser, sortable as
  text, unambiguous across time zones. The UI converts to local time.
- Enums are stored by **name**, never by index, so reordering a Dart enum can
  never re-interpret historical rows.
- `CHECK` constraints enforce what the type system cannot: a document line
  quantity must be positive, a ledger delta must be non-zero, a payment amount
  must be positive.
- Indexes cover every foreign key and every column the reports filter or sort
  on.

Schema changes add a branch to `AppDatabase._upgradeStep` and bump
`schemaVersion`. A missing step throws a named error rather than failing
quietly. Shipped branches are append-only.

The schema is at **version 2**. Version 2 adds three composite indexes
(`idx_ledger_product_occurred`, `idx_invoices_shop_date`,
`idx_invoices_agent_date`) that the query-plan checks found were missing; the
migration is covered by a test that drops them, stamps a database back to
version 1, reopens it and asserts they come back with the data intact.

File layout on disk, under `%APPDATA%\lk.venvoglobal\VenvoPOS\` — the
organisation folder comes from `getApplicationSupportDirectory()`, and this
path is what a real first run actually produced:

```
venvo_pos.sqlite        the database
attachments/2026/11/    uploaded bills, receipts, cheque images
backups/                generated archives
exports/                generated PDF and CSV output
```

Attachment binaries live on disk and are only referenced from SQLite, so the
database file stays small and quick to copy.

---

## Tests

```bash
flutter test
```

673 tests, all passing:

| File | Covers |
|---|---|
| `test/core/money_test.dart` | Exact arithmetic, discount rounding, allocation without losing a cent, input parsing |
| `test/core/password_hasher_test.dart` | PBKDF2 against a published vector, salting, cost upgrades, the password policy |
| `test/core/database_schema_test.dart` | Schema creation, FK enforcement, `CHECK` constraints, date and enum storage, seed correctness and idempotency |
| `test/core/database_migration_test.dart` | The real on-disk path: create, close, reopen, WAL, refusing a newer schema version |
| `test/core/sequence_service_test.dart` | Unique document numbers, yearly reset, and that a rolled-back transaction leaves nothing behind |
| `test/features/auth_test.dart` | First-run setup, sign-in, lockout, permissions per role, password changes, administrator guards, audit trail |
| `test/features/dashboard_test.dart` | Every reporting definition, including the cheque pending/cleared/bounced behaviour and stock valuation |
| `test/features/categories_test.dart` | Name uniqueness, nesting, cycle protection, archive guards, product counts |
| `test/features/products_test.dart` | SKU and barcode uniqueness, margins, stock aggregation per location kind, low stock, SQL filtering and sorting, archive guards, price audit trail |
| `test/features/agents_test.dart` | Code allocation, the agent-plus-location transaction and its rollback, outstanding balance with cleared vs pending money, archive guards |
| `test/features/shops_test.dart` | Code allocation, agent reassignment preserving history, credit limits, retail sales kept separate from supply, archive guards |
| `test/features/employees_test.dart` | Code allocation, advances and unpaid salary, archiving with open balances, filtering |
| `test/features/locations_test.dart` | Seeded and party-owned locations, per-location stock totals, negative-stock surfacing, additional warehouses |
| `test/features/stock_ledger_test.dart` | The acceptance scenarios, paired ledger entries, balance-replay agreement, the negative-stock policy and its override, cost flow, route and document validation, cancellation by reversal |
| `test/features/stock_reconciliation_test.dart` | Count sheets, snapshotted system quantities, variance maths and valuation, one-way and two-way postings, uncounted lines, posting and discard guards |
| `test/features/billing_test.dart` | Discount order and exactness, ceilings per role, allocation rules, the cheque lifecycle, billing a delivery once, retail sales, invoice cancellation |
| `test/features/billing_queries_test.dart` | The register SQL: settlement, pending cheques, unbilled deliveries, payment and cheque registers, totals |
| `test/features/document_pdf_test.dart` | Real PDF generation for invoices, receipts and delivery notes, including the cheque wording and the cancelled stamp |
| `test/features/returns_test.dart` | The two-leg return path, the inspection split and its arithmetic, invoice-traced caps and effective pricing, credit notes against an outstanding balance, withdrawal and cancellation, and the rollback of a part-posted return |
| `test/features/financial_ledger_test.dart` | The posting primitive and its balance guard, reversal, what each kind of stock movement posts, revenue and cost on an invoice, the cheque lifecycle through clearing, credit notes, the profit and loss, and a trial balance that still balances after a full round of business |
| `test/features/expenses_test.dart` | Expenses and their accounting, the petty cash float and its running balances, an expense paid from the float counted once, the no-negative-float rule, and the category list |
| `test/features/salaries_test.dart` | Advances as an asset, the salary computation and its caps, approval making the wage an expense once, oldest-first advance recovery, partial payments, cancellation putting an advance back, and the payroll read end to end in the accounts |
| `test/features/reports_test.dart` | All eighteen reports: that the catalogue is complete and every report runs on an empty database, the figures each one computes, that retail is kept out of the wholesale totals, that each agrees with the register it mirrors, and the PDF and CSV exports |
| `test/features/backup_test.dart` | Archiving the database and attachments, that the newest writes are in it, the automatic daily backup and its retention, validating a damaged or foreign or too-new archive, staging and cancelling a restore, applying one at start-up, and that a restore does not consume the archive it restores from |
| `test/core/performance_test.dart` | Every hot query asked of SQLite by query plan and failed if it would scan a growing table or sort in a temporary B-tree; the indexes named rather than counted; and the invariants plus the headline reads at a few thousand rows |
| `test/app_boot_test.dart` | Boots the real application over a temporary database and drives it through the interface: first-run setup, sign-in, every implemented screen rendering with no layout or render error, the settings toggles, adding master data through the forms, signing out and back in |

`test/helpers/master_data_fixtures.dart` assembles the real repositories over
an in-memory database, so the Phase 2 tests exercise the same wiring the
application uses rather than a simplified stand-in.

Under `flutter test` the code runs on the Dart VM, so the SQLite library
bundled for the application is not loaded; `test/helpers/test_harness.dart`
points SQLite at Windows' own `winsqlite3.dll`. The shipped application is
unaffected.

**All ten acceptance scenarios in the brief now pass.**

- **Scenarios 1, 2, 3, 6 and 7** (the warehouse to agent to shop to customer
  chain, and the returns back up it) run as one sequence of real postings in
  `stock_ledger_test.dart`. Scenarios 6 and 7 go through the returns module
  itself — posted, inspected, accepted — because that is now the only way a
  return can reach stock. The end balances are the brief's, and the test also
  asserts that nothing is left behind in transit
- **Scenario 4 & 5** (partial payments reducing the outstanding balance) —
  `billing_test.dart`, through the real invoice and payment services
- **Scenario 8** (10% discount giving a Rs. 18,000 net, then a Rs. 9,000
  payment leaving Rs. 9,000) — `billing_test.dart`, with the arithmetic itself
  in `money_test.dart`
- **Scenario 9** (a pending cheque is not cleared cash) — `billing_test.dart`,
  which also checks it cannot be double-allocated and that clearing it
  settles the debt while bouncing it brings the debt back
- **Scenario 10** (a failure leaves nothing partially applied) — three times
  over: a rolled-back document number in `sequence_service_test.dart`, an
  agent whose stock location fails to create in `agents_test.dart`, and a
  two-line transfer whose second line is short in `stock_ledger_test.dart`,
  where the first line's balances have already been written when it fails

---

## Further reading

- [`docs/user-guide.md`](docs/user-guide.md) — how to use the application,
  organised by what you are trying to do rather than by what is on the menu.
- [`docs/business-rules.md`](docs/business-rules.md) — the enforced rules, and
  the decisions still needed from the business.
- [`installer/venvo-pos.iss`](installer/venvo-pos.iss) — the Windows installer
  script, and what it deliberately leaves alone.
