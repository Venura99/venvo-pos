# Venvo POS — user guide

For whoever is going to use this every day. It is organised by what you are
trying to do, not by what is on the menu.

If you are looking for *why* something works the way it does, that is in
[`../README.md`](../README.md); the rules the program enforces are listed in
[`business-rules.md`](business-rules.md).

---

## Contents

1. [The first day](#1-the-first-day)
2. [How the business is modelled](#2-how-the-business-is-modelled)
3. [Getting your data in](#3-getting-your-data-in)
4. [The daily round](#4-the-daily-round)
5. [Money in](#5-money-in)
6. [Goods coming back](#6-goods-coming-back)
7. [Money out](#7-money-out)
8. [Reports](#8-reports)
9. [Backups](#9-backups)
10. [Who can do what](#10-who-can-do-what)
11. [When something looks wrong](#11-when-something-looks-wrong)

---

## 1. The first day

**Create the administrator.** The first time the program opens there are no
accounts, and it asks you to make one. There is no default password anywhere
in the program, and no way to recover the one you choose — write it down
somewhere safe until you are sure of it.

**Fill in Settings.** Business name, address, phone, tax number. These print
on every invoice, receipt and report, so it is worth doing before you raise
anything.

Also in Settings:

| Setting | What it does |
|---|---|
| Allow negative stock | Off, and it should stay off. See [§11](#11-when-something-looks-wrong). |
| Maximum item discount | The most a cashier may take off one line without a manager. |
| Maximum invoice discount | The same for a whole invoice. |
| Automatic daily backup | Leave it on. See [§9](#9-backups). |
| Backups to keep | How many *automatic* ones to keep. Ones you take by hand are never deleted for you. |

**Take a backup and copy it off this machine.** Before you put a day's real
work in. See [§9](#9-backups).

---

## 2. How the business is modelled

Five ideas. Everything else follows from them, and most confusion comes from
mixing two of them up.

**A location is a place goods sit.** The warehouse, each agent, each shop, and
the damaged store. Agents and shops get their location automatically when you
add them — you never create one by hand.

**Moving goods is not selling them.** Sending 50 chargers to an agent moves
stock. Nobody owes anything for it until you raise an invoice. This is on
purpose: it is how you can see what has gone out but not been charged for.

**An invoice is where money becomes owed.** Three kinds, kept apart:

- **Agent invoice** — you charge an agent for goods you sent them.
- **Shop invoice** — wholesale supply to a shop.
- **Retail sale** — what a shop sold over its own counter.

The third is reported separately from the second everywhere in the program. If
you add a shop's counter sales to the wholesale supply that stocked it, you
count the same goods twice.

**Money is only money when it clears.** A cheque in the drawer is not a
collection. It sits in its own column until you mark it cleared, and only then
does it reduce what somebody owes. If it bounces, the debt comes straight
back.

**Nothing is ever deleted.** A mistake is corrected by a new document that
undoes the old one. Both stay on the record, which is what makes the figures
worth trusting.

---

## 3. Getting your data in

In this order, because each step needs the one before it.

1. **Categories** — Master Data → Categories. Nest them if you like.
2. **Products** — SKU, name, category, cost price, wholesale price, retail
   price. Set a reorder level on anything you want to be warned about.
3. **Agents** — each gets a code and a stock location.
4. **Shops** — assign each to the agent who supplies it.
5. **Employees** — for expenses and salaries. The basic salary you set here is
   the starting point each month.
6. **Opening stock** — Inventory → Opening Stock. Enter what is physically
   there now, with what it cost you. This is the only time you type a cost in
   directly; from then on cost travels with the goods.

**Opening balances.** If an agent or shop already owed you money before you
started using the program, put that figure in the agent's or shop's opening
balance. Do not raise a fake invoice for it.

---

## 4. The daily round

### Sending goods to an agent

Operations → Stock Transfers → New transfer. Warehouse to agent. Both sides
update together: the warehouse goes down, the agent goes up. Prices on the
document print on the delivery note but create no revenue.

### Supplying a shop

Operations → Shop Supply. Agent to shop, the same way.

### Charging for it

Money → Invoices. Posted deliveries that have not been billed are listed at
the top of that screen — that list is the answer to "what have we sent out and
not charged for?". Click **Bill it** and the delivery becomes an invoice.

You can also raise an invoice with no delivery behind it (a charge on its
own), or one that moves the stock at the same time (a retail sale).

### Discounts

Per line or on the whole invoice. Both are recorded with the reason and who
gave them. Over the ceiling in Settings, the program asks for somebody with
permission to approve it, and records who did.

A cashier may discount a line but not a whole invoice — that is deliberate.

### Recording a retail sale

Operations → Retail Sales. Pick the shop, the goods come out of that shop's
stock, and the sale is recorded against the shop but reported separately from
wholesale.

---

## 5. Money in

Money → Payments → Record a payment. Cash, bank transfer, cheque or card.

**Applying it.** A payment can be applied to several invoices, and an invoice
can be settled by several payments. Money you take without pointing it at an
invoice is held as that party's **advance** — it is not income, and it shows
on their account until you use it.

**Cheques.** A cheque starts *awaiting clearance*:

```
received  →  banked  →  cleared
                     ↘  bounced
```

Until it clears it settles nothing. Money → Cheques is the list of what is
outstanding, oldest first. A post-dated cheque cannot be banked before its
date.

If one bounces, record it with the reason and any bank charge. The debt comes
back automatically; you do not adjust anything by hand.

**Seeing what is owed.** Money → Invoices with the *Unpaid only* filter, or
Reports → Outstanding balances for the whole picture. Both count cleared money
and posted credit notes only.

---

## 6. Goods coming back

Operations → Returns → New return. Pick the route first; everything else
follows from it.

| Route | When |
|---|---|
| Customer to shop | A walk-in brings something back. |
| Shop to agent | A shop sends goods back to its agent. |
| Agent to warehouse | An agent sends goods back to you. |
| Shop direct to warehouse | Bypasses the agent. Needs permission, and whoever posts it is recorded as having authorised it. |

**Trace it to the invoice if you can.** It caps the return at what was
actually billed and makes the credit repay the price actually charged,
discounts included.

**What happens when you post it.** The goods leave the returning location
immediately — the shop's stock drops — but they do **not** become your
sellable stock. They wait in transit until somebody inspects them. That is on
purpose: nobody should be able to promise units that have not been looked at.

**Inspecting.** Operations → Returns → Inspect. For each line, split the
quantity three ways:

- **Accept** → goes into the receiving location's stock.
- **Damaged** → goes to the quarantine store. Still credited: the goods came
  back, and the loss is yours.
- **Scrap** → written off. **Not** credited.

The three must add up to what came back. The program will not let you post a
part-inspected return, because a unit left over would sit in transit where no
stock report would find it.

**Credit.** Once inspected, Issue credit — up to what the inspection accepted,
never more. A credit note is applied to invoices exactly like a payment: it
can be spread over several, and withdrawn again if you put it on the wrong
one. Money → Credit Notes shows what credit each party is still holding.

---

## 7. Money out

### Expenses

Money → Expenses → New expense. Category, amount, what it was for, how it was
paid.

Tick **Paid out of the petty cash float** for small cash spending. The float
goes down by one linked entry, so the cash movement is recorded once — never
twice.

### Petty cash

Money → Petty Cash. Record the opening float once, then top it up from the
cash box as needed.

- **Cash in / Cash out** — moving your own cash between the box and the float.
  Not a cost.
- **Adjustment** — what you found when you counted. Short is a small loss,
  over is a small gain.

The float cannot go below what is in it: the program refuses rather than
recording a negative cash box.

### Salaries

Money → Salaries.

**An advance is not a wage.** Giving an employee money early is a loan they
owe back, so it is not a cost yet. Give an advance → it shows as outstanding
against them.

**Three steps, on purpose:**

1. **Compute** — a draft. You can check it and change it. Nothing is owed.
2. **Approve** — the wage becomes a cost and a debt to the employee. This is
   where any advance is recovered, oldest advance first. You can cap the
   recovery to spread a big advance over several months.
3. **Pay** — in full or in parts. The remainder stays owed.

The wage is counted as a cost once, at approval. Paying it settles a debt
rather than creating a second cost.

### The financial ledger

Money → Financial Ledger. Every invoice, payment, cheque, credit note, stock
write-off, expense and salary posts to one double-entry journal. You do not
have to use it, but it is what makes the profit and loss trustworthy: the
trial balance tab proves the books add up, and the journal tab traces any
figure back to the document behind it.

---

## 8. Reports

Reports. Eighteen of them, grouped: Sales, Stock, Money, Finance. Pick one on
the left, set the period, read it.

**Export.** **PDF** for printing or emailing. **CSV** for opening in Excel —
money comes out as a plain number so you can total it.

**Read the notes under each report.** They are not decoration. They say what
is counted and what is not: that collections mean cleared money only, that
retail is kept out of the wholesale figures, that a cancelled document is
listed but not counted. Those notes print with the report, so whoever reads it
on paper gets them too.

---

## 9. Backups

Administration → Backup & Restore.

A backup is one ZIP holding the database and every attachment. Taking one
takes a second.

**Do this.** Keep the automatic daily backup on, and **copy an archive off
this machine regularly**. The backups folder is on the same disk as the
database: a disk failure takes both.

**Restoring.**

1. Click an archive. The program opens it, runs SQLite's own integrity check
   over it, and shows you what is actually inside — how many users, invoices
   and stock rows — read from the archive itself, not from what it claims.
2. Confirm. Your current data is archived first, so a restore can be undone.
3. **Close the program and open it again.** The restore is applied as it
   starts. Nothing changes until you do, and until then you can cancel it.

Restoring is a separate permission from taking a backup: somebody who can
protect the data cannot necessarily overwrite it.

---

## 10. Who can do what

Six roles, each with a documented set of permissions:

| Role | For |
|---|---|
| Administrator | Everything, including users and restores. |
| Manager | Everything operational, plus approving discounts over the ceiling and issuing credit. |
| Store keeper | Goods: transfers, returns, inspections, stock counts. No money. |
| Cashier | Invoices, payments, retail sales. May discount a line, not a whole invoice. |
| Accountant | Money and the whole report set. Does not move stock. |
| Viewer | Reads. Changes nothing. |

Administration → Users & Roles. Every permission check lives in the program's
own logic, not just in whether a button is shown, so a role cannot be worked
around.

**The audit log** (Administration → Audit Log) records every sign-in, failure,
posting, cancellation and permission override, written as part of the
operation itself. It cannot be edited or deleted by anybody, including an
administrator.

---

## 11. When something looks wrong

**"Only N units are available."** Exactly what it says. The program will not
let stock go below zero at a real location, because that figure would then be
a guess. Either the goods are not there, or a movement was not recorded. Find
the missing document rather than switching the rule off.

**A balance looks wrong.** Inventory → Stock Movements shows every movement
for a product with the balance each one left behind. Read down it and you will
find the entry that is wrong. Inventory → Reconciliation lets you record what
you actually counted and post the difference as an adjustment, with a reason.

**An invoice shows as unpaid but you took a cheque.** The cheque has not been
marked cleared. Money → Cheques.

**A figure on a report does not match a screen.** It should not happen — every
report uses the same definitions as the screen it corresponds to, and there
are tests asserting that. If you find one that disagrees, that is a bug worth
reporting, with the report, the period and the screen you compared it against.

**You posted something wrong.** Cancel it; do not try to undo it by hand.
Cancelling writes a compensating document and leaves both on the record. A
return with credit against it cannot be cancelled until the credit note is
withdrawn — the goods and the money stay in step.

**The program will not start after you went back to an older version.** An
older release refuses to open a database written by a newer one rather than
risk misreading it. Restore a backup taken with the older version, or install
the newer one again.
