---
name: change-exposure-lookup
description: "Given a customer or a part, find open engineering and manufacturing changes and the customer exposure across the CRM, ERP, PLM and MES schemas of the Meridian demo database. Triggers: open changes on part, what's in flight for customer, ECR exposure, MCR exposure, is anything in flight, who received affected product."
---

# Change exposure lookup

Answers the question: *"For this customer or this part, what engineering (ECR) or manufacturing (MCR) changes are in flight, and who has received the affected product?"*

**Database:** the Meridian demo database, `SKILL_DEMO_PLM_20261019` by default. If it isn't found, ask the user which database holds the `CRM`, `ERP`, `PLM` and `MES` schemas.

Before starting, read `references/known-quirks.md`. Every rule there applies.

**Read-only.** Run only SELECT queries; never create, alter, or delete anything. Treat the user's input as a value: double any single quotes before putting it in a string literal, and never paste it into SQL as code.

## Step 1 — Classify the input
- A part number in any format (`MT-48210-A`, `48210A`, `0048210`, `48210`) means **part**.
- A company name means **customer**.
- If you can't tell which it is, **ask the user**.

## Step 2 — Resolve entities

**Customer**
1. Search `CRM.ACCOUNTS` (active accounts only; mention inactive matches) and `ERP.CUSTOMERS`. Score name pairs with `JAROWINKLER_SIMILARITY(UPPER(crm_name), erp_name)`, and use `ILIKE` on the distinctive first word.
2. Confirm with the email domain: CRM `CONTACTS.EMAIL` vs ERP `CUSTOMERS.BILL_TO_EMAIL`.
3. Assign confidence. The thresholds below are illustrative starting points; tune them for real data.
   - **Excluded:** both sides have email domains and they differ, whatever the name score. A domain conflict outranks the name score.
   - **High:** name score ≥ 90, or the email domain matches and the name score is ≥ 80.
   - **Medium:** name score 80–89 and no domain comparison possible (either side has no email).
   - **Low:** the match rests on the email domain alone, or the name score is below 80.
4. Show the candidates as a table with confidence and reasoning, and exclude look-alikes whose domain doesn't match.
5. **Stop and ask the user to confirm the matches before continuing.**

**Part**
1. Normalize: remove `-`, strip leading zeros, take the 5 digits, and prefix `MT-` to get the base part. Look it up in `PLM.PARTS` by `BASE_PART`.
2. Check supersession in both directions (`SUPERSEDED_BY` = this part, and this part's `SUPERSEDED_BY`). Include both the old and the new part from here on.
3. Find the ERP items that normalize to these base parts.

## Step 3 — Trace
customer → `ERP.SALES_ORDERS` → `ERP.ORDER_LINES` (item, lot) → normalized PLM part → `PLM.BOM` children (one level) →
- ECRs via `PLM.ECR_AFFECTED_PARTS`
- MCRs via `MES.MANUFACTURING_CHANGE_REQUESTS.PART_NUMBER` (the part or its components). If `LINKED_ECR` is NULL, relate the MCR to an ECR by part, plant and description, and label that link **inferred**.
- lots via `MES.PRODUCTION_LOTS` → holds via `MES.QUALITY_HOLDS`

Lookback: for a **customer** entry point, use all order history, but report recent exposure (the last 12 months) separately from older shipments. For a **part** entry point, use the last 90 days. In both cases, say which window you used.

For a **part** entry point, run the trace in reverse: part (old and new) → ERP items → order lines → customers (last 90 days unless told otherwise) → resolve each to CRM with confidence as in Step 2. Then confirm all customer matches in a single question, calling out any Low ones.

## Step 4 — Normalize statuses
Join to `PUBLIC.STATUS_MAP` (fall back to this table if it's missing):

| Source | Status | Normalized |
|---|---|---|
| ECR | Draft | Not started |
| ECR | In Review | In progress |
| ECR | Approved | In progress (pending implementation) |
| ECR | Implemented | Done |
| ECR | Cancelled | Excluded |
| MCR | OPEN | In progress |
| MCR | WIP | In progress |
| MCR | CLOSED | Done |
| MCR | REJ | Excluded |

"In flight" means the normalized status starts with "In progress". Drop Excluded rows and any ECR with `DUPLICATE_OF` set (name the surviving ECR instead). List Done changes briefly, for context only.

## Step 5 — Normalize times
Join `MES.PLANTS` and convert MES timestamps with `CONVERT_TIMEZONE(TIMESTAMP_ZONE, 'UTC', ts)`. Plants don't all record in UTC. Show effective dates in UTC and flag any that are in the future.

## Step 6 — Link symptoms (optional)
If the customer has support cases, compare the case `NOTES` and `SUBJECT` with the change descriptions. Read them, or use `AI_SIMILARITY`. Report matches as **"consistent with"**, never "caused by".

## Step 7 — Output (always this shape)

**Summary**: three bullets: what was matched, what is in flight, and who is exposed.

**Matches & assumptions**: a table of each entity resolved, how it was matched, and confidence.

**Open changes**

| ID | Type | Status → normalized | Part / rev | Via | Plant | Effective (UTC) |
|---|---|---|---|---|---|---|

ECRs have no plant; show `—`.

**Exposure**: order lines and units, lots (plant, produced date), and quality holds (active ones first).

**Caveats / verify next**: inferred links, future effective dates, assumed customer matches, and anything unconfirmed.

If nothing is in flight, say **"Nothing in flight"** and list every part and component that was checked. Never invent a finding.
