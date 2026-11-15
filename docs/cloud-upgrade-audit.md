# Cloud upgrade — audit, architecture and plan

Step 1 and 2 of the upgrade brief: what exists today, measured against the
requested features, plus the architecture recommendation and a phased plan.

> **Superseded in part — read §10 first.** The business has since confirmed
> **online-only, no offline mode**, and implementation has begun. That single
> answer removes phases C1, C4 and C5 — including the UUID migration of all 40
> tables and the whole sync engine, which §5 and §7 call the two places this
> upgrade succeeds or fails. §10 records what the plan actually is now and what
> has been built. Sections 1–3 (the audit) remain accurate; §5's sync design
> and §7's phase table are kept as the record of what was avoided.

Audited against the working tree at 673 passing tests, `flutter analyze`
clean, schema version 2.

---

## 0. Decisions taken

Answered by the business on 14 November 2026. These close four of the six
blocking questions in §6 and reduce the scope materially.

| Question | Answer | Effect |
|---|---|---|
| Credit to named end customers? | **No — shops owe us** | No `customers` table. Credit stays against agents and shops, which is **already built and tested**. The largest functional gap in the audit closes to nothing |
| Hosting | **Paid, budget-friendly, managed; SQL or NoSQL both acceptable; the business will run a backend** | Confirms the Dart server recommendation. See §4.1 for concrete hosting and costs |
| Devices | **Windows + Android** | No web build. The riskiest target is off the table. Android phones and tablets need real layout work over the existing 26 screens |
| Document numbers | **Per-device prefix** | `SINV-A-2026-00042`. Decided, so C1 can proceed — **and since reversed by the online-only decision, see §10** |

Still open: open question 7 in `business-rules.md` (retail sales in the profit
and loss). The offline question (§6.1) is now answered — see §10.

### Timeline

The business has asked for a handover **tomorrow**. The cloud upgrade cannot
be built honestly in a day — C1 alone rewrites the primary key of all 40
tables, and C4 is the correctness heart of the whole thing. Anything shipped
tomorrow calling itself "cloud" would be a dummy implementation, which the
brief's rule 8 forbids and which would be worse than nothing, because it
would look finished.

What **is** achievable tomorrow is a handover of the finished offline Windows
POS: it is complete, tested and documented. See §9.

---

## 1. What the existing system is

| | |
|---|---|
| Client | Flutter desktop (Windows), Material 3, Riverpod, GoRouter |
| Data | SQLite via Drift — 40 tables, 66 indexes, FK constraints, CHECK constraints |
| Backend | **None.** No server, no API, no network code of any kind |
| Business logic | Dart, in the client, inside database transactions |
| Tests | 673, over the real services against a real database |

The important structural fact for everything below: **the business rules live
in Dart service classes that take a `QueryExecutor`.** `StockLedgerService`,
`InvoiceService`, `PaymentService`, `ReturnService`, `SalaryService` and the
rest know nothing about SQLite specifically, and nothing about the UI. That is
what makes a cloud upgrade feasible without a rewrite — and it is the asset to
protect.

The second important fact: **money and stock are already modelled as
double-entry ledgers.** Stock movements write balanced pairs of signed rows;
financial events post balanced journal batches. Both are append-only. This
matters enormously for synchronisation, because append-only ledgers merge
across devices far more safely than mutable balance columns do.

---

## 2. Feature audit

Classified as the brief asks: **(1)** working, **(2)** partial, **(3)** not
implemented, **(4)** works but needs improvement.

### Phase 4.1 — On-hand stock management

| Feature | | Where / what is missing |
|---|---|---|
| View current available stock | 1 | Inventory → Stock Overview |
| Stock by individual shop | 1 | Per-location balances; shop-wise stock report |
| Consolidated stock across shops | 1 | Stock valuation report, warehouse/agent/shop/damaged columns |
| Track stock movements | 1 | Append-only `stock_ledger_entries`, with balance-after on every row |
| Stock transfers between shops | **2** | Warehouse→agent, agent→shop, warehouse→shop all work. **Shop→shop does not**: `interLocationTransfer` is restricted to warehouse→warehouse |
| Accurate balances after sales and purchases | 1 | Enforced; `findBalanceDiscrepancies()` proves the cache replays |
| Low-stock alerts | 1 | Reorder level per product, dashboard count, low-stock filter |
| Out-of-stock alerts | **2** | Low stock covers "at or below reorder level". Zero is not surfaced as its own alert |
| Stock movement history | 1 | Inventory → Stock Movements, and the stock movement report |

### Phase 4.2 — Shop / branch management

| Feature | | Where / what is missing |
|---|---|---|
| Add, edit, manage shops | 1 | Master Data → Shops |
| **Assign users to shops** | **3** | Users have roles but **no shop**. There is no shop-level data scoping anywhere. This is a prerequisite for Phase 6 |
| Shop-specific inventory | 1 | One location per shop, created in the same transaction as the shop |
| Individual shop performance | 1 | Shop-wise sales report |
| Consolidated business performance | 1 | Dashboard, profit and loss |
| Transfer stock between branches | **2** | As above — shop→shop is not a valid route |
| Branch-level access permissions | **3** | Permissions are global, not per shop |

### Phase 4.3 — Product management

| Feature | | Where / what is missing |
|---|---|---|
| Add / edit / manage products | 1 | Full catalogue with cost, wholesale, retail, pack size |
| Product categories | 1 | Nested, with cycle protection |
| Prices and costs | 1 | Price changes are audited |
| **Barcodes** | **2** | The field exists and is unique, and search matches it. There is **no scanner input** anywhere |
| Stock quantities | 1 | Via the ledger, never written directly |
| Product-level reporting | 1 | Product-wise sales; product stock history |
| Changes synchronise across devices | **3** | No sync exists |

### Phase 4.4 — Sales management

| Feature | | Where / what is missing |
|---|---|---|
| Sales by individual shop | 1 | Invoice register filtered by shop; shop-wise report |
| All business sales from admin | 1 | Invoice register, daily/monthly reports |
| Filter by date, shop, payment method | 1 | All present |
| **Filter by cashier** | **3** | `createdByUserId` is stored on every invoice but is not a filter |
| Transaction details | 1 | Invoice detail dialog with lines, discounts, payments |
| Returns and cancellations | 1 | Full returns module with inspection; cancellation by compensating document |
| Accurate sales totals | 1 | Stored, not recomputed; integer cents throughout |

### Phase 4.5 — Cheque and bank management

| Feature | | Where / what is missing |
|---|---|---|
| Record received cheques | 1 | Money → Payments, cheque method |
| **Record issued cheques** | **2** | Outbound payments exist, and salaries can be paid by cheque, but there is no cheque *instrument* record on the outbound side — only inbound cheques go in the `cheques` table |
| Number, bank, amount, date, party | 1 | All on the cheque record |
| Status: deposited / cleared / bounced / pending | 1 | Full lifecycle, with post-dated cheques blocked from early banking |
| **Cheque reminders** | **3** | Nothing reminds anybody of anything |
| Bank transaction history | **2** | The journal has a Bank account with every movement on it; there is no bank-statement screen as such |

### Phase 4.6 — Customer credit management

This is the **largest functional gap** between the brief and the system.

| Feature | | Where / what is missing |
|---|---|---|
| Maintain outstanding balances | **2** | Fully built **for agents and shops**. There is **no customer entity at all** — a retail sale stores a customer *name and phone as text* |
| Record credit sales | **2** | Credit terms, due dates and partial settlement all work, against agents and shops |
| Partial and full payments | 1 | Allocation across invoices, advances, withdrawal |
| Payment history | 1 | Per invoice and per party |
| Overdue balances | **2** | Invoices carry a due date and the register has an overdue filter; there is no overdue *report* |
| Customer credit limits | **2** | Shops have a credit limit. Customers do not exist |
| Outstanding reports | 1 | For agents and shops |
| Payment reminders | **3** | Not implemented |

**Decision needed.** The system models a wholesale chain: warehouse → agent →
shop → walk-in customer. Credit is tracked against agents and shops, which is
who actually owes the business money. The brief asks for per-customer credit,
which implies either (a) end customers of a shop owe *the shop*, not Venvo —
in which case this is out of scope — or (b) Venvo sells on credit directly to
named customers, which needs a new `customers` table and a fourth party type.
See §6.

### Phase 4.7 — Reminders and notifications

| | | |
|---|---|---|
| All of it | **3** | No notification, reminder or scheduling machinery exists |

### Phase 4.8 — Sales reports

| Feature | | Where / what is missing |
|---|---|---|
| Daily, monthly, custom range | 1 | Reports → Daily sales, Monthly sales, with a period filter on both |
| **Weekly** | **2** | A 7-day custom range works; there is no weekly bucket |
| Shop-wise, consolidated | 1 | Both |
| **Cash vs credit sales split** | **2** | Payment method is recorded on payments, not as a sales classification. A "cash sale" is inferrable but not reported |
| Payment-method breakdown | 1 | Collections report |
| Sales return reports | 1 | Returns and credit report |

### Phase 4.9 — Collection reports

| Feature | | Where / what is missing |
|---|---|---|
| Daily / monthly / custom | 1 | Collections report with a period filter |
| **Weekly** | **2** | As above |
| Customer-wise | **2** | Party-wise (agent/shop). No customers |
| Shop-wise | 1 | Filterable |
| Outstanding payment reports | 1 | Outstanding balances report |
| **Overdue collection reports** | **2** | The data is there; no dedicated report |
| Collection history | 1 | Payment register |

### Phase 4.10 — Admin dashboard

Every figure already comes from the database; there are no hardcoded numbers,
and a test asserts true zeros on an empty database.

| Feature | | |
|---|---|---|
| Total sales, collections, outstanding credit, stock value | 1 | |
| Shop-wise performance | **2** | On the shop-wise report, not on the dashboard |
| **Best-selling products** | **2** | Product-wise sales report is ranked by revenue; not on the dashboard |
| Low-stock products | 1 | Count on the dashboard, list in the report |
| Payment breakdown | 1 | |
| Recent transactions | **2** | Each register is newest-first; there is no combined recent-activity feed |
| Business performance summaries | 1 | Including net profit read from the journal |

### Phase 4.11 — Stock reports

All nine requested reports exist: current, shop-wise, consolidated, movement,
transfer, low-stock, out-of-stock (as low-stock), valuation, product history.
**1** across the board, with the out-of-stock caveat from §4.1.

### Phase 4.12 — Themes

| Feature | | Where / what is missing |
|---|---|---|
| Light and dark modes | 1 | Light / dark / follow-Windows |
| Persist preference | 1 | In the settings table |
| Consistent styling | 1 | One token file, no ad-hoc colours |
| **Multiple colour themes** | **3** | One brand seed colour. Choosing between schemes is not offered |

### Phases 2, 3, 5 — cloud, sync, multi-device

| | | |
|---|---|---|
| Everything | **3** | No server, no API, no auth tokens, no sync, no mobile or tablet layout, no browser build. The app is Windows-only by design and cannot run on web (it opens a SQLite file over `dart:ffi`) |

### Phase 6 — Security

| Feature | | Where / what is missing |
|---|---|---|
| Authentication | 1 | PBKDF2-HMAC-SHA256, per-user salt, stored cost, lockout, forced password change |
| Role-based access control | 1 | Six roles; checks in the services, not the UI |
| **Shop-level data permissions** | **3** | As §4.2 |
| **Secure API endpoints** | **3** | No API |
| Input validation | 1 | Guard functions on every service entry point |
| **Session management** | **2** | In-memory session, correct for a single-user desktop app. No tokens, no expiry, no revocation |
| Audit logs | 1 | Append-only, written inside the operation's own transaction |
| Backup and recovery | 1 | Validated archives, staged restore, automatic daily backup |
| Concurrent transactions | **2** | Safe within one process (SQLite transactions, WAL). Nothing handles two *devices* |

### Phase 7 — Performance

| Feature | | Where / what is missing |
|---|---|---|
| Indexing | 1 | 66 indexes; query plans asserted by test |
| Query optimisation | 1 | Reports are explicit SQL with the definitions stated |
| **Pagination** | **4** | Every list has a `limit` (300–2000). Nothing pages. Fine at today's volumes, wrong at a hundred thousand invoices |
| Caching | **2** | Settings cached; balance caches maintained transactionally |
| Avoid unnecessary rebuilds | 1 | Riverpod stream providers scoped per screen |
| **Efficient API requests** | **3** | No API |
| Report generation | 1 | Measured at a few thousand rows |

### Also not implemented

- **Printing.** PDFs are generated and saved to the exports folder. The
  `printing` package is a dependency but **is never called** — there is no
  print dialog, no printer selection. The brief asks for "proper printer
  support" on desktop.

---

## 3. Summary of the gap

Phase 4's business features are, with the exceptions listed, **already built
and tested**. The genuine functional gaps are small and well-defined:

1. Customers as an entity (if in scope — see §6)
2. Users scoped to shops, and shop-level permissions
3. Shop-to-shop stock transfer
4. Reminders and notifications
5. Printing (the dependency is there, unused)
6. Weekly buckets, overdue and cash/credit reports
7. Barcode scanner input
8. Multiple colour themes
9. Dashboard additions: shop-wise performance, best sellers, activity feed
10. Pagination

**The real work of this upgrade is Phases 2, 3, 5 and 6** — which is
infrastructure that does not exist at all, not features that need improving.
Roughly: the feature audit is the easy part, and the honest estimate is that
the cloud layer is more work than Phases 4 through 8 of the original build
combined.

---

## 4. Architecture recommendation

### The constraint that decides it

Every repository and service in this application is written against Drift's
`QueryExecutor`, and every business rule runs **inside a database
transaction**. The invariants depend on that: a stock movement and its
balanced ledger pair, an invoice and its document number, a salary and its
advance recovery, all commit together or not at all.

Any architecture that moves the database behind a network boundary without
moving the logic with it destroys those transactions.

### Three options, and why one wins

**A. Thin client + REST backend, logic re-implemented server-side.**
Rewrite every repository as an HTTP client and re-implement the business rules
on the server. This is a rewrite of the data and service layers of all eight
phases, discarding 673 tests' worth of proven behaviour. It is what the
brief's rules 1, 2, 3, 4 and 12 exist to prevent. **Rejected.**

**B. Keep the local database; run the same services on a server; sync between
them.** The client keeps working exactly as it does. A Dart backend hosts the
*same service classes* over a server-side database. A sync layer ships local
changes up and remote changes down. **Recommended.**

**C. Point Drift at a remote Postgres directly.** Exposing a database to the
internet is not acceptable, and every transaction would pay network latency —
billing would get slower, which rule 11 forbids. **Rejected.**

### The recommendation in detail

| Layer | Choice | Why |
|---|---|---|
| Server language | **Dart** (`shelf`) | The business logic is Dart. A Dart server runs `StockLedgerService` and friends **verbatim**, which is the whole point. Any other language means re-implementing and re-testing them |
| Server database | **SQLite** first, Postgres only if outgrown | Removes all dialect risk (see the risk table). This workload — one wholesale business, a few shops, a handful of devices — is far inside what server-side SQLite handles. Postgres is the upgrade path, not the starting point |
| API shape | Thin REST over the existing service methods | The endpoints are a transport for calls that already exist. No new business logic on the server |
| Auth | Reuse the `users` table and `PasswordHasher`; issue short-lived JWTs with refresh | The password hashing is already right and tested. Do not introduce a second identity system |
| Client | **The same Flutter app**, plus a sync service | No UI rewrite. Mobile and tablet are new *layouts* over the same screens |
| Sync | Append-only change log, pull-by-cursor, push-queue | Suits the ledgers the system already is |

**Managed alternative, honestly stated.** Supabase (Postgres + PostgREST +
Auth + Realtime) would remove server hosting work. The cost is that the
business logic would have to move into the client with the database open to
it, or be re-implemented as Postgres functions — and the reports use SQLite
SQL (`STRFTIME`, `DATE()`, `GROUP_CONCAT`, `PRAGMA`) throughout, which would
all need porting. If managed hosting matters more than reusing the logic, this
is the trade to discuss. I do not recommend it for this codebase.

### 4.1 Hosting, concretely

Asked for: paid, budget-friendly, fast and reliable, SQL or NoSQL both
acceptable, and the business is willing to run a backend.

That combination points at one small server rather than a managed platform,
because the thing being hosted is a *Dart application* and the database is
incidental to it.

| | Recommendation | Rough cost |
|---|---|---|
| Server | **Hetzner CX22** (2 vCPU, 4 GB) or **DigitalOcean** basic droplet, Docker, one Dart container behind Caddy for automatic TLS | €4–6 / month |
| Database | **SQLite on that server's disk**, WAL mode, the same engine the client uses | included |
| Backups | The existing `BackupService` archive format, written to **Backblaze B2** or **Cloudflare R2** nightly | under $1 / month |
| TLS and DNS | Caddy with Let's Encrypt; a subdomain such as `pos.venvo.lk` | free |
| Android delivery | Signed APK, distributed directly or through Play internal testing | $25 one-off for Play |

**Why SQLite rather than a managed Postgres.** Not thrift. Every report in
this system is explicit SQLite SQL, and every service runs inside a SQLite
transaction. Keeping the same engine on both sides means the business logic
and the reports move **unchanged** — nothing re-implemented, nothing
re-proven. A managed Postgres is a fine destination later if the business
outgrows one server, and the Dart server is the right place to make that
switch when it comes; it is the wrong thing to pay for on day one in porting
effort.

**NoSQL is not a good fit here** and the offer to move to it should be
declined. The data is deeply relational — a ledger entry references a
transaction, a location, a product and a user, and the invariants are
enforced with foreign keys and multi-table transactions. A document store
would mean re-implementing in application code the guarantees the database
currently gives for free, which is how balances start disagreeing.

---

## 5. Database and synchronisation strategy

Four schema problems have to be solved **before** any sync code is written.
They are the real content of this upgrade.

### 5.1 Primary keys collide across devices

Every table uses `integer().autoIncrement()`. Two devices both creating an
invoice offline both get id 42. Options:

- **UUID v7 text primary keys** — globally unique, time-ordered so index
  locality is preserved. Touches every table and every foreign key.
- **Device-prefixed integers** — each device gets a range. Cheaper to migrate,
  uglier, and runs out.

**Recommendation: UUID v7**, done as one migration with the old integer ids
kept alongside during the transition. This is the single largest and riskiest
change in the whole upgrade.

### 5.2 Document numbers collide across devices

`SequenceService` increments a counter row inside the caller's transaction —
exactly right for one process, and guaranteed to produce two `SINV-2026-00042`
invoices if two devices are offline. Options:

- **Per-device prefix**: `SINV-A-2026-00042`. Works offline, changes every
  printed document.
- **Server allocates**: needs connectivity to bill. Violates offline-first.
- **Provisional then renumber on sync**: never — a printed invoice number must
  not change.

**Recommendation: per-device prefix**, with the device code shown in settings.
This needs the business's agreement because it changes how invoice numbers
look.

### 5.3 Rows need versions and tombstones

Add to every synced table: `updatedAt` (already on many), `rowVersion`,
`deviceId`, `deletedAt`. Nothing is hard-deleted today, which helps — but the
sync layer needs tombstones for the few places rows do disappear.

### 5.4 Conflict resolution, per kind of data

Not one policy — the right policy differs, and the ledger design makes most of
it easy:

| Data | Policy | Why |
|---|---|---|
| Ledger rows (stock, journal, audit, allocations) | **Union, never merge** | Append-only. Two devices posting independently both happened; both rows are true. Balances are recomputed from them |
| Balance caches (`stock_balances`, `paidCents`, `appliedCents`) | **Recompute, never sync** | They are derived. `findBalanceDiscrepancies()` already exists to rebuild them |
| Master data (products, agents, shops, settings) | **Last-write-wins on `updatedAt`**, with the loser kept in a conflict log | Low contention, and a price edited twice is not a crisis — but it must be visible |
| Posted documents | **Immutable; conflict impossible** | They are never edited |
| Negative-stock guard | **Re-checked server-side on sync** | Two devices can each sell the last unit. The server must reject the second and surface it, not silently allow a negative |

That last row is the one to worry about, and it is where "never silently
discard transactions" bites: a sale that cannot be reconciled must land in a
visible failed-sync queue for a person to resolve, not be dropped and not be
force-applied.

---

## 6. Questions that block implementation

1. **Offline: in or out?** The brief says offline is "extremely important"
   (Phase 3, rule 10). Your message says "no need offline POS". These cannot
   both hold. My recommendation either way is to **keep the local database**:
   it already exists, every screen reads from it, and removing it means
   rewriting the data layer — the expensive option. Offline then costs
   nothing extra. What changes with your answer is how much sync *polish* is
   worth building (status indicators, failed-sync queue, conflict UI).
2. **Customers.** Does Venvo sell on credit directly to named customers, or do
   a shop's walk-in customers owe the shop rather than Venvo? The first needs
   a new `customers` table and a fourth party type throughout; the second
   means §4.6 is largely out of scope.
3. **Invoice number format.** Is a per-device prefix acceptable?
4. **Hosting.** Who runs the server, and where? That decides SQLite vs
   Postgres and self-hosted vs managed.
5. **Devices.** How many, and which — Windows only, or Android tablets at the
   counter too? Browser access changes the build target materially (the app
   cannot currently run on web at all).
6. **Open question 7 from `business-rules.md`** is now urgent: retail sales
   still credit `Sales Revenue`, so the profit and loss includes them. With
   multi-shop reporting this will be visible to more people.

---

## 7. Phased plan

Each phase ends with the full existing suite green. No phase begins before the
one above it is done, because each depends on the last.

| # | Phase | Depends on | Main risk |
|---|---|---|---|
| **C1** | Schema for sync: UUID keys, row versions, tombstones, device identity, per-device document numbers | — | **High.** Touches all 40 tables. Mitigated by the 673 existing tests, which must stay green throughout |
| **C2** | Dart server: `shelf`, the existing services over a server-side database, JWT auth reusing `PasswordHasher` | C1 | Medium. New deployment surface |
| **C3** | Shop scoping: users belong to shops, permissions become shop-aware, server enforces it | C2 | Medium. Changes the permission model that everything checks |
| **C4** | Sync engine: change log, pull-by-cursor, push-queue, idempotent writes, conflict policies from §5.4 | C1–C3 | **High.** The correctness heart of the upgrade |
| **C5** | Sync UX: status indicator, pending/failed queues, conflict resolution screens | C4 | Low |
| **C6** | Responsive layouts: Android phone and tablet over the same screens. **No web build** — decided out of scope | — (parallel) | Medium. 26 screens; the data tables need real rework for narrow widths |
| **C7** | Missing features from §3: shop-to-shop transfer, reminders, printing, the extra reports, barcode input, colour themes, pagination. **Customers dropped** — decided out of scope | C3 | Low each, and one fewer now |
| **C8** | Regression and performance: concurrency tests, two-device sync tests, load at scale | all | Medium |

C6 can run alongside C1–C5; it touches presentation only.

**Honest note on sequencing.** C1 and C4 are where this upgrade succeeds or
fails. Everything else is ordinary work. If you want to see the shape of it
early, C2 against the current integer-keyed schema makes a usable
single-device "cloud" build quickly — but it is a detour, because C1 has to
happen anyway and redoing C2 afterwards is waste.

---

## 8. What a handover tomorrow can honestly contain

The offline Windows POS is finished: 673 tests, analyze clean, 26 screens, all
ten acceptance scenarios from the original brief. That is a real product and
it can be handed over tomorrow. Four things stand between here and there, in
order:

| | Step | State | Who |
|---|---|---|---|
| 1 | **The toolchain** | ✅ **Done.** Nothing needed installing — Visual Studio Community 2026 (18.11) was already present with the Desktop development with C++ workload and CMake. `flutter doctor` reports it as a tick | — |
| 2 | **Compile it** | ✅ **Done.** `flutter build windows --debug` in 30.6 s, producing `venvo_pos.exe`. All four plugins' native registration compiled | — |
| 3 | **Launch it** | ✅ **Done.** Starts, `window_manager` sets the window title, the data directory is created and the database seeded to 628 KB with WAL active. It sat on the first-run screen as expected | — |
| 4 | **Commit the work.** 173 files, zero commits on `master` | ⬜ There is no version history at all. One bad command and eight phases are gone | me, on your word |
| 5 | **Work through the user guide once by hand** | ⬜ The screens have never been *used*. Create the administrator, add a product, post a transfer, raise an invoice, take a payment, save a PDF, take a backup | you, best at a keyboard |
| 6 | **Build the installer** and test it on a clean machine | ⬜ `installer/venvo-pos.iss` has still never been run | me |

**Found by the first run:** the data directory is
`%APPDATA%\lk.venvoglobal\VenvoPOS\`, not `%APPDATA%\VenvoPOS\` or
`%LOCALAPPDATA%\VenvoPOS` as five places in the documentation claimed. All
five are corrected. That mattered: the installer's uninstall message was
telling the user the wrong folder to protect.

Steps 4 to 6 are an afternoon.

What such a handover is **not**: cloud, multi-device, or Android. Those are
the C1–C8 plan above, and they are weeks rather than hours. Saying so now is
cheaper than saying it the day after the handover.

---

## 9. What the first run settled, and what it did not

**Settled.** The application compiles, starts, opens its window, creates its
data directory and seeds its database. Through eight phases this was the one
unverified assumption underneath everything, and it held.

**Not settled, and still worth an hour at a keyboard.** The screens have been
*rendered* by a test, not *used* by a person. Three things in particular only
a human clicking can confirm:

| | What to check | Why it is not covered by a test |
|---|---|---|
| `printing` | Save an invoice as PDF from the invoice register | The package is a dependency that **nothing calls** — PDFs are written to the exports folder and never sent to a printer. This is a known gap, not a suspected one |
| `url_launcher` | "Open folder" on Backup & Restore, and after a report export | A plugin call into the shell; a test cannot tell whether Explorer actually opened |
| `file_picker` | "Restore from a file…" on Backup & Restore | Opens a native dialog |

None of them can lose data if they fail — they are convenience calls around
work that has already been committed — but all three would be visible to
whoever is handed this tomorrow.

---

## 10. Revision: online-only, and what has been built

Added 14 November 2026, after the business confirmed **"our target online pos
system, no need offline pos"** and asked for the move to begin.

### What that answer removes

It is the single most consequential answer in this document, and it removes
most of the risk §5 and §7 identified:

| Dropped | Why it is no longer needed |
|---|---|
| **C1 — UUID primary keys across all 40 tables** | The collision it solved only happens when two devices create rows while offline. With one server owning every write, `autoIncrement` is correct. §5.1 called this "the single largest and riskiest change in the whole upgrade"; it is now not needed at all |
| **C4 — the sync engine** | Change log, pull-by-cursor, push queue, idempotent writes, the per-kind conflict policies of §5.4. §7 called this "the correctness heart of the upgrade". There is nothing to reconcile when there is one copy of the data |
| **C5 — sync UX** | No pending queue, no failed-sync queue, no conflict resolution screens |
| **Per-device document numbers** | §5.2 chose `SINV-A-2026-00042` to stop two offline devices issuing the same number. The server now allocates numbers in its own transaction, so `SequenceService` works unchanged and invoice numbers keep the format the business already uses. **This reverses the decision recorded in §0** — and in the better direction, since printed numbers stay as they are |

### The cost of that answer, stated plainly

**No internet means no billing.** Not degraded billing — none. A till cannot
raise an invoice, take a payment or look up stock while the connection is
down. For a wholesale business this is a real operational risk and it was
raised before the decision was taken; the business confirmed online-only
anyway, which is its call to make. If it later proves unworkable, the way back
is a read-through cache for lookups plus a local queue for sales, and that is
C1 and C4 again — the expensive work this answer avoids.

### The architecture as built

The audit rejected option A ("thin client plus REST backend") because it meant
re-implementing the business rules server-side and discarding 673 tests. What
has been built is option A's *shape* with option B's *logic reuse*, which the
audit did not consider and which is better than either:

```
packages/venvo_core/     pure Dart, no Flutter: 40 tables, 19 domain model
                         files, 30 services and repositories, every business
                         rule. Shared by the server and both clients.
server/                  shelf API. Opens the SQLite database, runs the
                         venvo_core services verbatim, authenticates.
lib/                     Flutter client: 52 presentation files, widgets,
                         theme, router, providers.
```

The extraction was the thing that made this possible, and it was only possible
because the domain and data layers had **no Flutter imports at all** — checked
before anything was moved.

### Built and verified

| | |
|---|---|
| `packages/venvo_core` extracted | 73 files, 485 imports rewritten, **673 tests still green**, analyze clean |
| Schema v3: `user_sessions` | Additive migration with its own test, including that its indexes exist |
| Authentication | Opaque bearer tokens, SHA-256 at rest, hard expiry and idle timeout, revocation |
| Role enforcement, server-side | The existing `actor.require(permission)` checks inside the services, unchanged |
| User and role administration | List, create, set roles, enable/disable, reset password, unlock |
| Deployment | Dockerfile, compose with Caddy for automatic TLS, healthcheck. **Written, not yet deployed** |
| Server tests | 24, over real HTTP against a real database |

**A regression worth recording.** Regenerating the drift code inside the new
package silently removed **all 106 foreign keys** from the schema. drift_dev
cannot resolve `references(Users, #id)` against the newer analyzer a standalone
package resolves, and it reports that as a warning while generating the column
without its constraint. The Flutter SDK had been pinning the analyzer for eight
phases, which is why it had never happened. One test caught it — an insert of a
product with a category id that does not exist, which SQLite accepted. The
analyzer is now pinned in `packages/venvo_core/pubspec.yaml` and a test counts
the foreign keys SQLite is actually enforcing.

### What remains, in order

| | Work | Size |
|---|---|---|
| 1 | **Business endpoints.** Done: master data, **stock** (movements, ledger, documents, counts), **invoices**, **payments and cheques**, and the **financial journal reads**. The invariants are proved through the API: double-entry stock nets to zero, the journal never holds an unbalanced batch, a cheque reaches the accounts only on clearance, and cancelling a bill does not un-ship goods. Also done: **returns, inspection and credit notes** — the two-leg route through in-transit, the accepted/damaged/scrapped split, and credit worth only the goods that still exist. Also done: **expenses, the petty cash float, payroll and advances**, then **the 18 reports, the dashboard, the journal listing, settings and the audit trail**. Remaining: **backup and restore only**, which needs a design decision rather than an endpoint — `BackupService` works in terms of files on the machine running it, and on a server a backup belongs in object storage on a schedule, not downloaded by a till | Effectively done |
| 2 | **Switch the client data layer to HTTP.** The layer this needs is now **built and proven** — see §10.1. What remains is flipping the provider declarations, adding a server-address setting, and reworking `app_boot_test.dart`. It cannot be done until step 1 is finished; §10.2 says why | Small once step 1 is done |
| 3 | **Android build and responsive layouts** over the same screens | Real design work; the data tables need rework for narrow widths |
| 4 | **Off-site backups** from the server, nightly, to object storage | Small, and not optional |
| 5 | **Deploy and test** on the real server with real devices | — |

Steps 1 and 2 are days of focused work. Nothing here is a day's work, and
saying otherwise was the thing §0 refused to do.

### 10.1 The client layer, and why the screens do not change

The problem that made this look expensive: every list screen watches a
`StreamProvider` fed by a repository's `watchProducts(filter)`, and those are
**Drift query streams** — they re-run themselves whenever their tables are
written to. That is why no screen in the offline build contains a "refresh"
call: saving a form refreshed the table behind it for free. HTTP has nothing
watching any tables.

Rather than convert 25 `StreamProvider`s into `FutureProvider`s and add
invalidation at every call site, the API client reproduces the contract:

* `RevisionBus` holds a revision number per topic (products, shops, stock, …).
* `ApiClient.watch(topics, fetch)` returns a stream that yields `fetch()` now
  and again whenever one of those topics changes.
* Every write declares what it touched — `bumps: {ApiTopic.products}` — and
  bumps those topics on success.

So `ProductApi.watchProducts(filter)` has the same signature and the same
behaviour as `ProductRepository.watchProducts(filter)`, and the provider
bodies are the only thing that changes. The `actor` argument is kept in every
signature and ignored: the server derives the acting user from the bearer
token, which a client cannot forge — a property the local build could not have,
because there the caller *was* the authority.

Two details that are easy to get wrong and are now pinned by tests:

* **A failed fetch is delivered as a stream error, not by closing the stream.**
  Closing it would leave a screen stuck on a failure until its provider was
  rebuilt; this way a dropped connection shows the error and the next refresh
  recovers.
* **Failures keep their type across the wire.** `FailureCodec` rebuilds the
  server's `BusinessRuleFailure`, `ValidationFailure` or `PermissionFailure` as
  the same class, with its `rule`, `field` or `permission` intact, so the
  screens' existing error handling keeps working.

Ten end-to-end tests drive the real client against a real server in one
process, which is the only thing that proves the two halves agree.

### 10.2 Why the switch has to happen all at once

It is tempting to move the client module by module as each one's endpoints
land. **That would be a mistake, and a dangerous one.**

The client still opens its own local SQLite database, and the server has a
different one. A half-migrated client would read products over HTTP from the
server's database and stock from its own local file — two sources of truth for
the same business, diverging from the first write. A product created on the
server would be invisible to the local stock screen, and a transfer posted
locally would never reach the server's ledger.

So the order is fixed: **every module's endpoints first, then the client flips
in one step**, together with the server-address setting and the removal of the
client's local database. Until that step the Windows build keeps working
exactly as it does today, offline and complete, which is also what keeps a
working product in hand throughout.
