# Venvo POS API

The server half of the cloud build. It hosts the business logic from
`packages/venvo_core` over a server-side SQLite database and serves the Windows
and Android clients.

## What makes this not a rewrite

Every business rule in this system — the double-entry stock ledger, the
balanced financial journal, invoice posting, payment allocation, returns and
credit notes — lives in `packages/venvo_core`, which has **no Flutter
dependency**. The server imports those classes and runs them verbatim, inside
the same SQLite transactions the 673 existing tests already prove.

The server adds a transport and authentication. It does not re-implement a
single rule, and it must not start to: a rule that needs changing is changed in
`venvo_core`, where it is tested once and both the server and the clients get
the change.

## Status

| | State |
|---|---|
| Every module served over the API, permissions enforced server-side | ✅ |
| Schema v4 (`cheque_reminders`), with migrations from v1, v2 and v3 | ✅ tested |
| Web app built into the image and served from the same origin | ✅ smoke-tested |
| Android and Windows clients talk only to the server — no local database | ✅ |
| Cheque photos (upload, view, save) and WhatsApp cheque reminders | ✅ 16 server tests |
| Server-side backups (daily on first sign-in, list, prune) | ✅ — restore is a server-side operation, not in the app |
| Deployment: Dockerfile, compose, Caddy, healthcheck | ✅ written; **the image has not been built here** (no Docker on the dev machine) |
| Android release build | ❌ needs the Android NDK and SDK 36 installed on the build machine |

Known gap: an agent can see **all** shops, not only their own. There is no
per-agent scoping of shops yet.

### The client half

`packages/venvo_core/lib/core/api/` holds the client, so the web, Android and
Windows builds share one implementation and the server's own tests can drive
the real client against a real server in one process.

`ApiClient.watch(topics, fetch)` reproduces what Drift query streams did
locally: it yields now, and again whenever a write declares it touched one of
those topics (`bumps: {ApiTopic.products}`).

`AppFailure` subclasses survive the round trip through `FailureCodec`, so a
screen still receives a `BusinessRuleFailure` with its `rule`, or a
`ValidationFailure` with its `field`, exactly as it did when the rule ran
locally.

## Running it locally

```bash
cd server
dart pub get
VENVO_DATA_DIR=/tmp/venvo-dev dart run bin/server.dart
```

On Windows the data directory must exist first, and SQLite comes from the
`winsqlite3.dll` that ships with Windows — see `lib/sqlite_runtime.dart`.

Then create the administrator (no account exists until you do, and none is
seeded with a default password):

```bash
curl -X POST http://127.0.0.1:8080/api/v1/auth/first-run \
  -H 'content-type: application/json' \
  -d '{"fullName":"Your Name","username":"admin","password":"choose-a-strong-one"}'
```

## Configuration

Read from the environment at start-up. A bad value stops the process with a
message naming the variable.

| Variable | Default | Meaning |
|---|---|---|
| `VENVO_DATA_DIR` | **required** | Directory holding the database, attachments, backups and exports. No default on purpose: a server that invented one would serve an empty database and lose what was entered into it |
| `VENVO_PORT` | `8080` | |
| `VENVO_BIND_ADDRESS` | `127.0.0.1` | `any` binds every interface. Only safe behind a TLS-terminating proxy |
| `VENVO_SESSION_TTL_HOURS` | `12` | Hard session lifetime |
| `VENVO_SESSION_IDLE_MINUTES` | `480` | Idle timeout, measured separately from the above |
| `VENVO_LOG_SQL` | `false` | Logs every statement. Diagnostic only — noisy and revealing |
| `VENVO_WEB_DIR` | unset | Directory holding the built web app (`flutter build web`). Set in the image |
| `TZ` | `Asia/Colombo` in the image | Decides what "today" and "N days before the cheque date" mean |
| `WHATSAPP_TOKEN` | unset | WhatsApp Cloud API access token. Unset = reminders off, and the app says so |
| `WHATSAPP_PHONE_NUMBER_ID` | unset | The sending number's id from Meta's WhatsApp Manager |
| `WHATSAPP_TEMPLATE` | `cheque_reminder` | Name of the approved message template |
| `WHATSAPP_TEMPLATE_LANGUAGE` | `en` | Its language code |

### WhatsApp cheque reminders

WhatsApp only lets a business start a conversation with an **approved
template**. Create one in Meta's WhatsApp Manager named `cheque_reminder`,
category *Utility*, with five body variables in this order — party, cheque
number, bank, amount, cheque date. For example:

> Cheque reminder: {{1}} gave cheque no. {{2}} ({{3}}) for {{4}}, dated {{5}}.
> Please arrange to bank it.

The admin numbers and how many days before are set in the app, under
Settings. The server checks every hour (and once at start-up), sends each
cheque's reminder once per number, records every attempt with Meta's reason
if it failed, and gives up on a number after five failures. Settings has a
"Send a test message" button.

**There is no secret to configure.** That is a design choice, not an omission:
sessions are opaque random tokens stored as SHA-256 hashes in the database, so
there is no signing key to rotate, leak into a client build, or commit by
accident. Passwords stay where they already were — PBKDF2-HMAC-SHA256, salted
per user.

## Deploying

The recommendation from the audit, unchanged: one small server, Docker, SQLite
on its disk, Caddy in front for automatic TLS.

```bash
# On the server, with the repository checked out:
cat > server/.env <<'EOF'
VENVO_DOMAIN=pos.venvo.lk
VENVO_TLS_EMAIL=you@venvoglobal.lk
# Optional — cheque reminders stay off until these are set:
WHATSAPP_TOKEN=
WHATSAPP_PHONE_NUMBER_ID=
EOF
chmod 600 server/.env

docker compose -f server/docker-compose.yml --env-file server/.env up -d --build
```

Point the domain's A record at the server **before** starting, because Caddy
proves ownership over HTTP to get its certificate.

Note that `docker-compose.yml` deliberately does not publish the API's port to
the host. The only way in is through Caddy, so the API cannot be reached over
plain HTTP from outside even by mistake.

### Why SQLite on the server rather than a managed Postgres

Not thrift. Every one of the 18 reports is explicit SQLite SQL, and every
service runs inside a SQLite transaction. Keeping the same engine on both sides
is what lets the business logic and the reports move **unchanged** — nothing
re-implemented, nothing re-proven. With one server there is a single writer, so
the usual objection to SQLite under concurrency does not apply: Dart serialises
the writes anyway.

Postgres is the upgrade path if the business outgrows one server, and the Dart
server is the right place to make that switch when it comes. It is the wrong
thing to pay for on day one in porting effort.

### Running costs

A small VPS (2 vCPU, 4 GB) from Hetzner or DigitalOcean, object storage for
off-site backups, and a domain. Check current prices rather than trusting a
figure written here — but this is a single-small-server deployment, which is
the cheapest shape this system can take while still being reachable from
anywhere.

## Backups

The server must take them off the machine. The existing `BackupService`
produces the same archive format the desktop build uses, so an archive from the
server restores into the desktop app and the other way round. A nightly archive
copied to object storage is the plan; **that is not yet wired up**, and a
backup sitting on the same disk as the database is not a backup.

## The API

All paths are under `/api/v1`. Errors carry their type across the wire so a
client can tell a business-rule violation from a validation problem — see
`FailureCodec` in `venvo_core`.

| Status | Meaning |
|---|---|
| 401 | Not signed in, or the session has ended |
| 403 | Signed in, but lacks the permission |
| 404 | No such record |
| 409 | A business rule refused it — the request was well formed and conflicts with the current state |
| 422 | The request itself was wrong; `field` names the input |
| 503 | Database or disk problem; retrying is reasonable |

### Open

| Method | Path | |
|---|---|---|
| `GET` | `/health` | Liveness, for the proxy and monitoring |
| `GET` | `/api/v1/status` | Whether first-run setup is needed; schema and API versions |
| `POST` | `/api/v1/auth/first-run` | Creates the first administrator. Refuses once any user exists |
| `POST` | `/api/v1/auth/login` | Returns a bearer token. Locks the account after five failures |

### Signed in

Reachable while a password change is outstanding, so an account forced to
change its password can actually do so.

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/auth/me` | The current user and their resolved permissions |
| `POST` | `/api/v1/auth/logout` | |
| `POST` | `/api/v1/auth/password` | Changes own password; signs other devices out |
| `GET` | `/api/v1/auth/devices` | Devices this account is signed in on |
| `DELETE` | `/api/v1/auth/devices/<id>` | Signs one of **your own** devices out |

### Administration

Requires `users.manage`, checked inside the repositories rather than at the
route, so it cannot be bypassed by reaching an operation another way.

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/users` | |
| `POST` | `/api/v1/users` | Creates an account that must change its password first |
| `PUT` | `/api/v1/users/<id>/roles` | Takes effect on the target's next request, with no re-login |
| `PATCH` | `/api/v1/users/<id>/status` | Enable or disable. Refuses to disable the last administrator |
| `POST` | `/api/v1/users/<id>/password-reset` | Signs that account's devices out |
| `POST` | `/api/v1/users/<id>/unlock` | Clears a failed-attempt lockout |
| `GET` | `/api/v1/roles` | |
| `GET` | `/api/v1/permissions` | The catalogue, so a client need not hardcode it |

### Master data

Reads require the matching `*.view` permission; writes are checked inside the
repositories against `*.manage`.

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/products` | `search`, `categoryId`, `brand`, `includeInactive`, `includeArchived`, `lowStockOnly`, `sortKey`, `sortAscending` |
| `GET` | `/api/v1/products/brands` | Distinct brands, for a filter dropdown |
| `GET` | `/api/v1/products/<id>/stock` | On-hand quantity per location |
| `POST` | `/api/v1/products` | |
| `PUT` | `/api/v1/products/<id>` | |
| `POST` | `/api/v1/products/<id>/archive` · `/restore` | |
| `POST` | `/api/v1/products/bulk-category` | Moves many products at once; one bad id rejects all of them |
| `GET` | `/api/v1/categories` | `includeArchived` |
| `GET` | `/api/v1/categories/selectable` | Assignable categories only |
| `POST`/`PUT` | `/api/v1/categories[/<id>]` | |
| `POST` | `/api/v1/categories/<id>/archive` · `/restore` | |
| `GET` | `/api/v1/agents` | `search`, `includeInactive`, `includeArchived`, `owingOnly` |
| `GET` | `/api/v1/agents/selectable` | |
| `POST`/`PUT` | `/api/v1/agents[/<id>]` | Creating one also creates its inventory location |
| `POST` | `/api/v1/agents/<id>/archive` · `/restore` | |
| `GET` | `/api/v1/shops` | `search`, `agentId`, `owingOnly`, `overCreditLimitOnly`, `unassignedOnly`, … |
| `GET` | `/api/v1/shops/selectable` | `agentId` |
| `POST`/`PUT` | `/api/v1/shops[/<id>]` | |
| `POST` | `/api/v1/shops/<id>/agent` | Reassigns; `agentId: null` unassigns |
| `POST` | `/api/v1/shops/<id>/archive` · `/restore` | |
| `GET` | `/api/v1/employees` | `search`, `designation`, … |
| `GET` | `/api/v1/employees/selectable` · `/designations` | |
| `POST`/`PUT` | `/api/v1/employees[/<id>]` | |
| `POST` | `/api/v1/employees/<id>/archive` · `/restore` | |
| `GET` | `/api/v1/locations` | `includeVirtual`, `includeInactive` |

### Stock

Reads need `stock.view`; the reconciliation reads need `stock.reconcile`.
Writes are checked inside `StockLedgerService` against the permission for the
document type being posted.

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/stock` | On-hand per product. `search`, `categoryId`, `lowStockOnly`, `hideZeroStock` |
| `GET` | `/api/v1/stock/locations/<id>` | Balances at one location. `search`, `hideZero` |
| `GET` | `/api/v1/stock/ledger` | Ledger rows. `productId`, `locationId`, `from`, `to`, `includeVirtualLocations`, `limit` |
| `GET` | `/api/v1/stock/documents` | `type` **repeats** (`?type=openingStock&type=warehouseToAgent`), `status`, `agentId`, `shopId`, `locationId`, `from`, `to` |
| `GET` | `/api/v1/stock/documents/<id>` | Document with its lines |
| `GET` | `/api/v1/stock/balance` | One balance. `locationId`, `productId` |
| `GET` | `/api/v1/stock/verify` | Replays the ledger and says whether the cached balance agrees |
| `GET` | `/api/v1/stock/unbalanced` | Products whose signed rows do not sum to zero. **Should always be empty** |
| `POST` | `/api/v1/stock/movements` | Posts a movement: signed ledger pair, balance cache and journal entry in one transaction |
| `POST` | `/api/v1/stock/movements/<id>/cancel` | Reverses it. Needs a `reason`. Nothing is edited or deleted |
| `GET`/`POST` | `/api/v1/stock/counts` | List / start a reconciliation count |
| `GET` | `/api/v1/stock/counts/<id>` | The count sheet |
| `PUT` | `/api/v1/stock/counts/<id>/quantities` | `counted` is keyed by product id; **null means "not counted yet"**, which is not a counted zero |
| `POST` | `/api/v1/stock/counts/<id>/post` | Turns each variance into a real adjustment movement |
| `POST` | `/api/v1/stock/counts/<id>/discard` | |
| `GET` | `/api/v1/stock/counts/<id>/variance` | Value of the variance, in minor units |

**The negative-stock guard is enforced server-side**, which is where the
current balance actually is. Overriding it needs both
`stock.negative_override` *and* a written reason; both refusals are tested
through the API.

### Invoices

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/invoices` | `kind` repeats; `status`, `settlement`, `agentId`, `shopId`, `from`, `to`, `unpaidOnly`, `overdueOnly` |
| `GET` | `/api/v1/invoices/totals` | Summary figures for the same filter |
| `GET` | `/api/v1/invoices/unbilled-deliveries` | Goods gone out, not yet billed |
| `GET` | `/api/v1/invoices/<id>` | Invoice with lines and payments |
| `POST` | `/api/v1/invoices` | Invoice, lines, receivable, journal entry and (optionally) the stock movement, in one transaction |
| `POST` | `/api/v1/invoices/from-delivery` | Bills a posted delivery. Prices come from the delivery note |
| `POST` | `/api/v1/invoices/<id>/cancel` | Needs a `reason` |

**Cancelling a bill is not un-shipping**, so whether the goods come back is
the caller's decision: `reverseStockMovement` on the cancel body, defaulting
to **false**. Reversing a delivery that already happened would invent stock
the warehouse does not have, so the quiet default is to leave the goods where
they are and release only the money.

When the flag *is* set, it reverses whatever stock document the invoice is
linked to — **including a delivery posted separately**. The code draws no
distinction between a movement the invoice created and one it merely billed.
That is a real operation (the goods came back *and* the bill was wrong), but
it is not the obvious reading of "cancel this invoice", which is why the
default is false. Both paths are tested, for an invoice that moved its own
stock and for one that billed an existing delivery.

### Payments and cheques

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/payments` | `direction`, `method`, `status`, `agentId`, `shopId`, `from`, `to`, `advancesOnly` |
| `GET` | `/api/v1/payments/totals` | |
| `GET` | `/api/v1/payments/allocatable` | Invoices a collection can be applied to. `agentId` or `shopId` |
| `GET` | `/api/v1/payments/advance-balance` | Money received and not yet applied |
| `POST` | `/api/v1/payments` | Payment with its allocations, in one transaction |
| `POST` | `/api/v1/payments/<id>/allocations` | Apply to invoices |
| `POST` | `/api/v1/payments/<id>/allocations/<invoiceId>/release` | Withdraw one, wholly or partly |
| `POST` | `/api/v1/payments/<id>/cancel` | |
| `GET` | `/api/v1/invoices/<id>/settlement` | **Both** settlement figures — see below |
| `POST` | `/api/v1/invoices/<id>/allocations/release` | Release every allocation on an invoice |
| `GET` | `/api/v1/cheques` · `/cheques/totals` | `status` repeats; `bankableOnly`, `from`, `to` |
| `POST` | `/api/v1/cheques/<id>/deposit` · `/clear` · `/bounce` · `/replacement` | The cheque lifecycle |

**A cheque is not money until it clears.** The journal entry is posted on
clearance, not on the day the cheque was taken — posting it earlier would
overstate the bank and understate what the business is owed. Bouncing reverses
whatever the clearance posted and records the bank's charge.

**`/settlement` returns two different numbers on purpose.** `outstanding`
counts cleared money only: what is still owed. `allocatableRemaining` also
counts payments still pending — a cheque banked but not cleared — so it is
what may still be *applied*. Allocating against `outstanding` while a cheque
is in flight would apply the same debt twice.

### Returns and credit notes

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/returns` | `route` repeats; `status`, `reason`, `agentId`, `shopId`, `pendingInspectionOnly`, `from`, `to` |
| `GET` | `/api/v1/returns/totals` | |
| `GET` | `/api/v1/returns/<id>` | Return with its lines and inspection state |
| `GET` | `/api/v1/invoices/<id>/returnable-lines` | Billed, less what has already come back |
| `POST` | `/api/v1/returns` | Records the goods coming back |
| `POST` | `/api/v1/returns/<id>/inspection` | Accepted / damaged / scrapped per line |
| `POST` | `/api/v1/returns/<id>/cancel` | |
| `POST` | `/api/v1/returns/<id>/credit-note` | `amount` optional: omit it to credit the full creditable value |
| `GET` | `/api/v1/credit-notes` | `status`, `agentId`, `shopId`, `withRemainingOnly`, `from`, `to` |
| `GET` | `/api/v1/credit-notes/available` | Unused credit a party holds. `agentId` or `shopId` |
| `GET` | `/api/v1/credit-notes/<id>` | Note with its applications |
| `POST` | `/api/v1/credit-notes/<id>/apply` | `invoiceId` and `amount` — a note is often spread over several invoices |
| `POST` | `/api/v1/credit-notes/<id>/cancel` | |
| `POST` | `/api/v1/credit-note-applications/<id>/withdraw` | Returns the credit to the note's unused balance |

**A return is a two-leg move.** Goods leave the shop into an in-transit
location and stay there: they are neither the shop's nor the agent's while
they are on a lorry, and **nothing becomes sellable until it has been
inspected**. Inspection splits each line into accepted, damaged and scrapped,
and a split that does not add up to the quantity returned is refused — the
missing unit is the whole danger, stock that left a shop and was never
accounted for anywhere.

**Only accepted and damaged goods are credited**, at the price actually
charged after any proportional share of an invoice-level discount. Scrapped
goods are worth nothing; crediting them would hand money back for goods that
no longer exist in any usable form. A storekeeper may inspect goods but not
decide what money goes back — that needs `credit_note.issue`.

### Expenses and the petty cash float

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/expenses` | `categoryId`, `paymentMethod`, `status`, `pettyCashOnly`, `from`, `to` |
| `GET` | `/api/v1/expenses/totals` · `/daily-totals` | |
| `POST` | `/api/v1/expenses` | |
| `POST` | `/api/v1/expenses/<id>/cancel` | |
| `GET`/`POST` | `/api/v1/expense-categories` | `includeArchived` on the read |
| `POST` | `/api/v1/expense-categories/<id>/archive` | |
| `GET` | `/api/v1/petty-cash` | `kind`, `from`, `to` |
| `GET` | `/api/v1/petty-cash/snapshot` · `/float` | `/float` takes `asOf` |
| `POST` | `/api/v1/petty-cash` | |
| `POST` | `/api/v1/petty-cash/recompute` | Replays the entries; returns rows changed, and **0 is the expected answer** |

An expense marked `fromPettyCash` writes its float entry **inside the
expense's own transaction**, so the two can never disagree about what was
spent. `PettyCashService.appendEntry` — the method that does that — is
deliberately not exposed: a client able to add a float movement with no
expense behind it is the hole the float exists to close.

### Payroll and advances

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/salaries` | `employeeId`, `periodYear`, `periodMonth`, `status`, `unpaidOnly` |
| `GET` | `/api/v1/salaries/totals` · `/periods` | |
| `POST` | `/api/v1/salaries/compute` | Works out the net; **writes nothing** |
| `GET` | `/api/v1/salaries/<id>` | |
| `POST` | `/api/v1/salaries` | |
| `POST` | `/api/v1/salaries/<id>/approve` | Posts the liability. No money moves yet |
| `POST` | `/api/v1/salaries/<id>/pay` | `amount` optional: omit to pay what is outstanding |
| `POST` | `/api/v1/salaries/<id>/cancel` | |
| `GET`/`POST` | `/api/v1/advances` | `employeeId`, `outstandingOnly` on the read |
| `GET` | `/api/v1/employees/<id>/outstanding-advances` | |

**An advance already handed over comes off the payslip**, or the employee is
paid twice. `recoverAdvances` on the draft controls it, `compute` shows the
effect before anything is created, and cancelling an approved salary puts the
advance back rather than quietly writing it off against a salary that no
longer exists.

### Financial journal

Reads only. Postings happen as a consequence of the operation that caused
them; an endpoint that wrote into the journal directly would be a way to put
the accounts out of step with the business.

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/finance/trial-balance` | `from`, `to` |
| `GET` | `/api/v1/finance/balance` | `account` (required), `from`, `to` |
| `GET` | `/api/v1/finance/profit-and-loss` | Needs `reports.financial` |
| `GET` | `/api/v1/finance/unbalanced-batches` | **Should always be empty** — the financial twin of `/stock/unbalanced` |
| `GET` | `/api/v1/finance/entries` | Journal entries. `account`, `sourceKind`, `search`, `from`, `to` |

### Reports, dashboard, settings and audit

| Method | Path | |
|---|---|---|
| `GET` | `/api/v1/reports` | The catalogue, **cut to what the caller may run** |
| `GET` | `/api/v1/reports/<id>` | Runs it. `from`, `to`, `agentId`, `shopId`, `productId`, `categoryId`, `employeeId`, `locationId` |
| `GET` | `/api/v1/dashboard` | Every figure computed from the ledgers on this request |
| `GET` | `/api/v1/settings` | Readable by any signed-in user; also lists which keys are writable |
| `PUT` | `/api/v1/settings` | Needs `settings.manage`. Takes a map, so a form saves as one change |
| `GET` | `/api/v1/audit` | `action`, `search`, `limit`. **Read-only** |

**Report authorization is data-driven.** Every `ReportDefinition` in
`kReports` carries the permission needed to run it, so the catalogue a user is
shown and the reports they may actually run come from one list. There is no
second place to keep in step, and a report cannot be added without saying who
may see it. A cashier is offered a subset and is not shown a profit and loss
statement only to be refused it — and when a report *is* refused, the error
names the permission the definition carries rather than one the route picked.

**Report cells stay typed.** Money crosses as integer minor units with a
`kind` of `money`, not as a formatted string — so the table, the PDF and the
CSV each format from the same value instead of from three different strings.

**Settings use an allow-list, not a key/value door.** `backup.last_auto_at`
and `system.seeded_version` are maintained by the machinery that owns them; a
client able to set the seeded version could convince the seeder it had already
run on a database where it had not. An unknown or read-only key is named in
the error rather than silently ignored — a client that believes it changed a
setting and did not is worse off than one told plainly it cannot. There is a
test that tightening the invoice discount ceiling is enforced on the very next
invoice, so settings are demonstrably not decoration.

**The audit trail has no write endpoint**, and will not get one. Entries are
written as a side effect of the operations being recorded; a trail a client
can add to or edit is not a trail.

### Backup and restore

Not exposed, and it needs a decision rather than an endpoint.
`BackupService` works in terms of `File` objects on the machine running it,
which is why `backup_models.dart` is the one model file with no wire format.
On a server, a backup is an archive on the server's disk that should be copied
to object storage on a schedule — not something a till downloads. The likely
shape is a scheduled job plus a small endpoint to list and trigger, and that
is still to be designed.

**Money is integer minor units on the wire**, never a decimal — `"costPrice":
123457` is Rs 1,234.57. `Money` carries its own `toJson`/`fromJson`, so no
amount is ever rounded in transit, and there is a test that an awkward value
survives the round trip byte for byte. Enums cross as their Dart names
(`"unitOfMeasure": "box"`).

**A bad filter value is refused, not ignored.**
`?includeArchived=perhaps` is a 422 naming the parameter. Falling back to the
default would hand the caller a list that looks right and is not.

## Tests

```bash
cd server && dart test
```

Five files, driven over real HTTP against a real SQLite file — no stubs:

| File | What it covers |
|---|---|
| `api_test.dart` | Sessions and user administration, spoken as raw HTTP |
| `master_data_test.dart` | The six master-data modules, including filters |
| `end_to_end_test.dart` | The **real client** against the real server, in one process |
| `stock_end_to_end_test.dart` | Stock movements, the negative guard, reconciliation counts |
| `billing_end_to_end_test.dart` | Invoices, cancellation, collections, the cheque lifecycle |
| `returns_end_to_end_test.dart` | Returns, inspection, credit notes and their application |
| `operating_end_to_end_test.dart` | Expenses, the petty cash float, payroll and advance recovery |
| `reporting_end_to_end_test.dart` | All 18 reports, the dashboard, settings and the audit trail |
| `wire_format_test.dart` | The encodings, with no server at all |

They aim at the properties that would be expensive to get wrong rather than the
happy path. Among them: that no account exists until one is created; that a
wrong password and an unknown username give byte-identical answers; that five
failures lock the account; that a revoked or disabled session stops working on
the next request; that a role change applies without signing in again; that the
last administrator cannot be disabled; that **the double-entry stock ledger
still nets to zero** when movements are posted across a network; that a
movement larger than the stock on hand is refused *and nothing moves*; that
overriding the negative-stock guard needs both the permission and a written
reason; that cancelling reverses rather than deletes; that a stock count's
"not counted yet" never arrives as a counted zero; that **the journal never
holds an unbalanced batch** after any operation; that **a cheque reaches the
bank account only when it clears**, and bouncing it reverses that; that
`outstanding` and `allocatableRemaining` differ while a cheque is in flight;
that returned goods wait in transit and become sellable only once inspected;
that an inspection which does not account for every returned unit is refused;
that scrapped goods are never credited; that an expense paid from the float
moves both in one transaction; that **an advance already handed over comes off
the payslip**, and goes back on if the salary is cancelled; and that a failure
keeps its type across the wire so the screens can still tell a business rule
from a validation error.
