# Municipal Billing Intelligence Platform — Technical Design

*Architecture and engineering reference. Pairs with `SCHEMA.md` (the data model) and `PROJECT_BRIEFING.md` (the business). Update at the end of any session where an architectural decision changes.*

---

## Tech stack

- **Framework:** Next.js (TypeScript, App Router)
- **UI:** React, Tailwind CSS
- **Database:** Supabase (PostgreSQL) — also provides Auth and Storage
- **Editor:** Cursor, connected to WSL2 (Ubuntu) on Windows 11
- **Testing:** Jest (with ts-jest) for unit tests; Playwright planned for end-to-end
- **Future:** Python for tariff/bill scraping; Vercel for deployment; an OCR engine (AWS Textract / Google Document AI / other — not yet chosen) for bill ingestion; a transactional email provider for dispute letters; **payment processing** (PayFast and/or Stripe); **inbound email parsing** (to let users forward bills in); **real-time features** beyond basic Supabase subscriptions.

Local environment: WSL2 Ubuntu, Node via nvm, Python via pyenv, Supabase CLI via Homebrew, Git/GitHub configured.

## Core architecture — "reconstruct and compare"

The engine independently recalculates every charge on a bill from first principles (the bill's own consumption/valuation inputs plus authoritative tariff parameters), then compares the recalculated figure to what was billed. A discrepancy beyond a materiality tolerance is a finding.

This unifies most checks: tariff misclassification, block-tariff arithmetic, and rates verification are the *same operation* — recompute the charge, compare to billed. The engine is one recalculation machine running against different tariff structures, not a pile of unrelated checks.

### Separation of concerns — the load-bearing principle

- **Check logic** lives in pure functions, one per check, in `lib/checks/`. A check function takes data in (billing lines, bill metadata) and returns results out. It knows nothing about HTTP or the database.
- **I/O** (fetching from Supabase, receiving requests, sending responses) lives in the API route / orchestrator. The route fetches data, hands it to the pure check functions, and writes their results back.

A **pure function** depends only on its inputs and has no side effects (no DB calls, no clock, no network inside it). Two consequences:
1. It is trivially testable — call it with made-up data, assert the output, no database or server required. Tests are fast and deterministic.
2. Faults are locatable — a wrong result must be in the arithmetic, because nothing else is in the function.

**Therefore check functions receive all data as arguments.** The fetch happens in the route; the fetched data is passed to the pure function. "Fetch in the route, decide in the function" is the whole architecture in one line.

### Server vs browser (Next.js)

The language (TypeScript) runs in both places, so the *file's role* tells you where code runs, not the language:
- `app/api/.../route.ts` → **server** (hidden from the browser; holds secrets and logic). The browser's only doorway to server logic.
- `*.tsx` **with** `"use client"` → **browser** (visible, tamperable; interactive UI only, no secrets).
- `*.tsx` **without** `"use client"` → **server component** (renders HTML server-side, like classic server rendering).
- `lib/` files → run wherever they're imported; check functions imported by `route.ts` run server-side.

Rule: secrets and engine logic on the server (so they're hidden and untamperable); instant interactions in the browser (to remove network latency from interactions that don't need the server). The check logic must always be server-side. Server code calling server logic calls the function directly — it never makes an HTTP request to itself.

## The six calculation patterns

Every South African municipal charge is one of six patterns. The engine holds the six formulas in code; `tariff_schedules.structure_type` names the pattern; the other columns supply the parameters. Adding a municipality is adding parameter rows, not code.

| structure_type | Formula | Example |
|---|---|---|
| `flat` | rate × consumption | Commercial electricity energy |
| `block` | consumption split across bands, each band at its own rate, summed | Residential water, prepaid electricity |
| `fixed` | flat amount per period | Service charge, capacity charge |
| `stepped_fixed` | flat amount by which band an attribute falls in | Refuse by property value, sanitation by erf size |
| `valuation` | (valuation − exclusion) × rate ÷ divisor × period | Property rates |
| `demand` | rate × measured demand (kVA / kVArh) | Large-user electricity demand |

Banding is not always on consumption: `band_basis` can be `consumption`, `property_value`, `erf_size`, `weight`, or `none`. Electricity adds two further dimensions: `season` (summer/winter/all) and `time_period` (peak/standard/off_peak/all, for TOU). Each band is **one row** (queryable, matches published schedules); the engine must handle band contiguity (no gaps/overlaps) when summing.

## The check catalogue

Each check is registered in the `check_config` table (tolerance, severity, `min_bills_required`, `requires_consecutive`, legal citation) so the engine is configurable without code changes. Checks declare what data they need; the orchestrator runs whichever checks the available data supports, and presents the rest as locked ("upload N more consecutive bills to unlock").

**Type 1 — rule-based (work from day one):**

| Check | What it verifies | Bills needed | Notes |
|---|---|---|---|
| estimated_read | Flags lines where read_type is estimated | 1 | Smarter when paired with consumption-spike (estimated *and* unreasonable) |
| block_tariff_arithmetic | Recalculates tiered charges vs billed | 1 | Populates calculated_amount / billed_amount |
| tariff_misclassification | Rate applied matches account category | 1 | Folds in "wrong category" cases |
| backbilling | Charges for periods outside the recoverable window | 1 | Operative test = 3-yr prescription |
| prescription | Recovery of debts older than 3 years | 1 | Shares legal basis with backbilling |
| fixed_charge_duplication | Same fixed charge appearing >once per period | 1 | Tariff schedule says which charges are once-per-period |
| vat_miscalculation | VAT at correct rate on correct base | 1 | Folds in zero-rated cases; flag conservatively (legal risk) |
| rebate_entitlement | Owner qualifies for a rebate not being applied | 1 | Flagship; reads user attributes + rebates table |
| meter_mismatch | Meter number consistency | varies | Dynamic form (number changed between bills) detectable now; static form deferred (needs municipality partnership) |

**Type 2 — pattern-based (need history / volume):**

| Check | What it detects | Bills needed | Notes |
|---|---|---|---|
| consumption_spike | Consumption anomalous vs the account's own history | 3 (consecutive) | In MVP despite being Type 2 — the headline "huge estimated bill" catcher |
| reading_continuity | Each bill's opening reading = prior bill's closing reading | 2 (consecutive) | Pure arithmetic across bills; catches gaps/resets |
| interest_on_backbilling | Interest charged from original due date on a back-billed amount | 2 | By-law silent → disputable; downstream of backbilling |

Deferred / future: base-wide anomaly & fraud-signature detection (needs volume), surcharge legitimacy (no reference to check against — would cry wolf), prepaid debt-recovery skimming.

### Recording results — store rich, show lean

The engine records a `check_results` row for **every line checked, pass and fail** — not findings only. Rationale: Type 2 pattern detection needs the baseline of passing observations (you cannot compute "13% estimated this month" without the denominator; you cannot model "normal" from exceptions alone). The dashboard simply queries `WHERE passed = false` to show only problems — a display decision, not a storage decision. `check_results` is itself an analytical asset, like the tariff data. Volume is by design — hence the FK indexes; old detail may be rolled up later.

### Materiality tolerance

Every recalculation check needs a tolerance floor (absolute rand and/or percentage) so rounding differences between the engine and the municipality don't trigger false positives. Stored in `check_config` (`tolerance_amount`, `tolerance_percent`), not hardcoded — so sensitivity can be tuned live.

## OCR — the ingestion problem

The single biggest day-one engineering problem: each of 257 municipalities has a different bill layout, so the OCR layer must learn many document structures. `municipalities.billing_format` selects the parsing rules per municipality.

**Universal fields every bill must yield:** account number; property address; meter number(s); service period (from/to); bill issued date; per line item (description, unit, quantity, rate, amount); actual-vs-estimated read flag; previous balance carried forward; tariff category / account-type code.

**Per-check input notes (beyond the bill itself):**
- block_tariff_arithmetic, fixed_charge_duplication — none beyond bill + tariff DB
- backbilling, prescription — line-item dates; sometimes a statement of account to date arrears components
- estimated_read, consumption_spike, reading_continuity — prior bills (uploaded on onboarding; platform maintains history thereafter)
- tariff_misclassification — property type (onboarding dropdown; optionally erf number → commercial deeds API such as Lightstone/Propinfo/Windeed at ~R5–15/lookup)
- vat_miscalculation — none beyond bill; codify VAT rules once (legal risk — flag conservatively)
- rebate_entitlement — owner attributes (age, income band, disability, primary-property flag) collected on onboarding

## Testing approach

- Jest + ts-jest. Test files sit beside the code as `*.test.ts`.
- Because checks are pure, tests call them directly with fabricated data and assert outputs — no server, no DB. The full suite runs in well under a second.
- Tests must be **independent** (no shared mutable state between tests; each builds its own data) so they pass in any order and in isolation.
- Use a **test factory** (e.g. `makeBillingLine(overrides: Partial<BillingLine>)`) returning a sensible default object merged with `...overrides`, so each test specifies only the field under test. Avoids 19-field duplication and survives schema additions in one place.

## Shared types (`lib/types.ts`)

The contract the whole engine is built on:
- **`BillingLine`** — what checks *read*. Mirrors the `billing_lines` table. Nullable DB columns typed `?: T | null`. Dates and `created_at` are `string` (Supabase returns ISO strings, not Date objects). Includes `id` (it's a saved row being read).
- **`CheckResult`** — what checks *produce*. Mirrors `check_results` minus DB-generated fields. Fields typed `T | null` (present but possibly null) — *not* optional — so the engine must set every field deliberately. `severity` is a union `"info" | "warning" | "error"`. Omits `id` and `created_at` (the database generates them on insert).

The asymmetry (id on `BillingLine`, not on `CheckResult`) is correct: id exists when reading a saved row, not when producing a new one.

## Current build state

- **Database:** 14-table baseline schema live in Supabase, version-controlled as a single clean `001_initial_schema.sql` (incremental migrations squashed — appropriate pre-launch with no data to protect; real migrations resume from here). Fully documented in `SCHEMA.md`. `calculated_amount` / `billed_amount` added to `check_results`.
- **Engine:** First check (`estimatedRead`) written as a pure function in `lib/checks/`, importing shared types from `lib/types.ts`, with three independent Jest tests passing (estimated → fail, actual → pass, null read_type → skipped). Uses a `makeBillingLine` test factory.
- **Not built yet:** the orchestrator (loops an account's bills, runs qualifying checks, writes results); the remaining checks; populated `tariff_schedules`, `rebates`, `legal_parameters`, `check_config`; the API route wiring; OCR ingestion; auth + RLS policies; UI; deployment.
- **No RLS policies yet** — RLS is enabled on the project but no policies are written, so tables reject normal authenticated users until policies exist. Fine for admin/seed work now; required before real users log in. A trigger to auto-create a `users` profile row on signup is also a future addition.

## Immediate next step

Decide between (A) wiring `estimatedRead` through an API route orchestrator end-to-end (fetch lines from Supabase → run check → write results), proving the full data flow once; or (B) building the next check function first (reading-continuity or block-tariff arithmetic) to grow engine breadth. Leaning A — prove the full stack once before replicating the pattern.
