# Municipal Billing Intelligence Platform — Decision Log

*A running record of decisions and their reasoning — especially where alternatives were weighed and rejected. Purpose: stop future sessions relitigating settled questions or reversing good decisions for bad reasons. Add new entries at the end of any session where a decision is made or changed. Never silently overwrite — if a decision changes, record the new position and note what it superseded.*

---

## Scope & product

**MVP boundary = direct municipal billing, defined by the billing relationship (not property type).**
In scope: any account the municipality bills directly — freestanding houses, directly-billed commercial, and sectional title *bulk* accounts. Out of scope: the downstream managing-agent apportionment to individual units.
*Why:* the boundary is defined by data you actually have (a municipal bill), cleanly separates in-scope from deferred, and doesn't exclude sectional title (its bulk account is in scope; only the per-unit split waits). Everything in scope is a municipality error (Type A).
*Rejected:* a property-type boundary (freestanding vs sectional) — messier, excludes body corporates unnecessarily.

**First municipality: City of Johannesburg.**
*Why:* billing crisis most acute post-City-Power-takeover, so value is most demonstrable and the problem most durable.
*Selection principle:* start where billing inaccuracy is *highest*. Cape Town is understood to have very few inaccuracies, so despite the founder being based there it is a poor starting point. **Durban (eThekwini)** was highlighted as a strong secondary candidate on the same basis.
*Superseded:* an earlier "Cape Town first (cleaner product-dev environment), Gauteng second" line of reasoning. Reversed in favour of highest-inaccuracy-first.

**Prepaid electricity — OUT of scope.**
*Why:* token slips lack the readings, period, and line-item breakdown the recalculation engine needs. The necessary inputs do not exist on the customer's side — it is unauditable, not merely error-light.
*Corrected a wrong assumption:* prepaid is NOT "more accurate, fewer errors" — it has its own error classes (debt-recovery skimming especially). It's excluded because the data artifact is too thin, full stop. (Future: a narrower prepaid debt-recovery skimming check.)

**Time-of-use (TOU) electricity — IN scope.**
*Why:* large commercial and large sectional-title bulk accounts (>100 kVA) may be on TOU; excluding it would fail exactly the high-value accounts where rand errors are largest.
*Superseded:* an earlier lean to defer TOU. Reversed after recognising it sits under core target segments. Modelled as `season` + `time_period` dimensions — folds into the same row structure, not a special case.

**Rebates — IN for MVP.**
*Why:* residential is in the target market; the rebate-entitlement check (e.g. a pensioner not receiving a 100% rates rebate) is potentially the most emotionally powerful finding the platform produces.
*Superseded:* Claude initially proposed deferring rebates because the first test bill was commercial. Founder corrected this — first bill ≠ target market. Rebates stayed in.

**Downstream apportionment (managing-agent → unit, error types B and C) — deferred.**
*Why:* needs sub-meter data and apportionment logic; not required to prove the core engine on directly-billed accounts. Schema kept generic via `accounts.issuer_type` and nullable `municipality_id` so it can be added without restructure.

**Meter-number mismatch — partially in, mostly deferred.**
*Why:* the *dynamic* form (meter number changed between consecutive bills) is detectable now via historical consistency. The *static* form (wrong meter from the start) needs reference data only the municipality holds — deferred to a data partnership.

**Check catalogue expanded beyond the original eight.**
Added consumption-spike (Type 2), reading-continuity, interest-on-back-billing, rebate-entitlement. Folded category-mismatch into tariff-misclassification and zero-rated-VAT into the VAT check rather than adding separate checks.
*Why:* having real bills showed the real money is in "estimated *and* unreasonable," cross-bill continuity, and missed rebates — not the original binary checks alone.
*Superseded:* the "MVP = eight Type-1 checks only" framing. The MVP now deliberately includes at least one Type 2 check (consumption-spike).
*Rejected:* base-wide anomaly/fraud detection (needs volume — later), surcharge-legitimacy (no reference to check against — would cry wolf).

**Revenue model — NOT decided; options only.**
Options mapped (MA subscription, body-corporate/trustee subscription, B2C, success fee; free-audit-as-demo go-to-market). Two further options recorded: a **"named tool" (not white-label) sold to incumbents like Venn** — automating their analysts' manual detection (critical unknown: whether Venn already has internal automation); and **B2B2C distribution** to households via estate agents / bond originators / auditors. None chosen.
*Why undecided:* the incentive structure differs sharply by customer and error type; needs real customer-discovery (Sea Glade chairman, Intersect account manager) and unit economics before commitment.

**Competitive landscape — RESEARCHED (closes the earlier "not researched" gap).**
No competitor does independent bill recalculation; the automation layer is unbuilt. Manual consumer (Bill Deponent, Council Solutions, Municipal & Property Solutions); nominally-tech-but-manual consumer (BillVerify; Munichecker is a predictor not an auditor); dead/wrong-category (BillSure, CityRadar); manual enterprise consultancy serving large commercial (Venn — dominant incumbent ~37 yrs/~R500m/~300k accounts; Munifix, SA MAD, Voltwise); manual sectional-title sub-meter layer (Nusco/Motla, "Utilify" ~R79).
*Finding:* the unserved sweet spot is small business, small landlords, and managed sectional-title schemes. The real threat is a manual operator (e.g. Council Solutions) deciding to build — not a direct rival.
*Rejected as durable moats:* "cross-MA insight" and "neutrality positioning" — both stress-tested and found too weak. **Data velocity** (one MA sale routes hundreds of bills/month) is retained as a genuine moat lever.

## Architecture

**Engine = "reconstruct and compare" (recalculate each charge), not "flag only."**
*Why:* recalculating from first principles is the moat and unifies most checks into one operation (recompute, compare). Flagging would be simpler but far less defensible and less powerful.
*Rejected:* a flag-only engine that detects suspicious patterns without recomputing.

**Check logic = pure functions, separated from the API route.**
Each check is a pure function in `lib/checks/` taking data in, returning results out, with no DB/HTTP/side effects. The route handles I/O and passes data in.
*Why:* pure functions are trivially and deterministically testable (no server/DB needed) and make faults locatable. "Fetch in the route, decide in the function."

**Tariff data = parametric (`structure_type` + parameter columns), not stored formulas.**
The engine holds six calculation patterns in code; the table supplies parameters.
*Why:* queryable, comparable across municipalities, populatable by non-engineers, testable, and a licensable dataset. Adding a municipality becomes data entry, not code. Scales to 257 municipalities.
*Rejected:* storing each tariff's formula as an interpreted expression — opaque, unqueryable, hard to populate safely, fails silently (dangerous in a billing product), undermines the data-asset thesis.

**Tariff bands = one row per band, not JSON-per-charge.**
*Why:* queryable (e.g. "all bands over R30/kl"), matches how published schedules are laid out, easier for a non-engineer data team, strengthens the data asset. The "fewer rows" benefit of JSON is irrelevant — the rows *are* the asset. Reversible if ever needed (same information, different shape).
*Commitment created:* the engine must enforce band contiguity (no gaps/overlaps) per service/period.

**Record every check result — pass AND fail — not findings only.**
*Why:* Type 2 pattern detection needs the baseline of passing observations (can't compute "13% estimated" without the denominator; can't model "normal" from exceptions alone). `check_results` is an analytical asset. Display stays lean by querying `WHERE passed = false` — a display decision, not a storage decision. "Store rich, show lean."
*Superseded:* Claude's initial lean toward findings-only (tidier table). Reversed when the founder raised Type 2 / roll-up analysis — the passing rows are exactly the substrate those need.

**Engine is account-centric (operates on bill history); built for single- and multi-bill from the start.**
*Why:* more consecutive bills unlock more checks; a single bill is the degenerate case. Locked checks become the upsell. Building for account-history now is far cheaper than retrofitting it. Each check declares `min_bills_required` + `requires_consecutive`; cross-bill checks must handle gaps gracefully.

**`users.id` references `auth.users(id)` — auth link kept from the start.**
*Why:* identity is the hardest thing to retrofit; everything hangs off the user and RLS policies are written against `auth.uid()`. Building the link now is free; bolting it on later means rewriting the key relationship.
*Accepted cost:* a real auth user must exist before a profile row can be inserted — create test users in the Supabase dashboard when seeding. (Future: a trigger to auto-create the profile row on signup.)

## Schema specifics

**`band_basis` generalises the banding dimension** (consumption / property_value / erf_size / weight / none).
*Why:* banding is not always on consumption — refuse bands on property value, sanitation on erf size. Same banding mechanic, different dimension.

**`check_config` is a separate table from `legal_parameters`.**
*Why:* separation of concerns — `legal_parameters` holds citable law for dispute letters; `check_config` holds engine tuning. Mixing them muddies both.

**`check_config` includes `min_bills_required` and `requires_consecutive`.**
*Why:* checks declare their data needs as data, not code; enables the locked-check upsell and lets the engine run only the checks the available data supports.

**Materiality tolerance stored in `check_config` (`tolerance_amount`, `tolerance_percent`), not hardcoded.**
*Why:* the engine and municipalities round differently, so recalculations rarely match to the cent. A tolerance floor prevents false positives on rounding; storing it allows live tuning without code changes.

**`calculated_amount` and `billed_amount` added to `check_results`.**
*Why:* arithmetic checks store what the engine recalculated vs what was billed (the dispute amount is usually the difference); also gives Type 2 a rich numeric series, not just booleans.

**Dropped `category_ratio` from `tariff_schedules`.**
*Why:* the ratio (e.g. 1:2.5) has no calculation value — it's already baked into the rate-in-the-rand. Metadata only.

**`postal_code` is varchar, VAT stored as a dated `vat_rates` table.**
*Why:* postal codes are identifiers, not numbers. VAT changed 14%→15% (2018) and rates must be dated data, not a hardcoded constant — Check 7 uses the rate in force on the bill's issued date.

## Migrations & tooling

**Squashed incremental migrations into one clean `001_initial_schema.sql`; no `drop` statements in the committed file.**
*Why:* incremental migrations only earn their keep once there's live data to protect — pre-launch they're noise. A single clean baseline is the source of truth; real migrations resume from here. Destructive operations (dropping tables) are done manually in Supabase, kept out of committed files.
*Rejected:* including `drop table if exists ... cascade` in the file — convenient now but a footgun against real data later.

## Legal

> **⚠️ UNRESOLVED CONTRADICTION — TO VERIFY (vital; underpins the back-billing check and dispute-letter citations).** Older project history sourced the back-billing limit and dispute-letter authority to the **Municipal Systems Act**. These documents instead ground them in the **Prescription Act + CoJ Credit Control By-laws** and do not cite the MSA at all. Not reconciled. Confirm which instrument is operative before the back-billing check and its letter wording are finalised; do not treat the Prescription Act / by-law framing as settled until checked.

**Back-billing has no CoJ by-law cap; the operative limit is the Prescription Act (3 years).**
*Why:* CoJ By-law Section 25 *preserves* the Council's recovery right despite its own billing failures — there is no in-by-law time limit. The Prescription Act 68 of 1969 (3-year extinction, running from when the debt is due, interrupted by acknowledgement or legal process) is the real constraint. Back-billing and prescription checks therefore collapse to one operative test.
*This was a finding, not a gap:* the by-law's *silence* is the substantive result.

**Frame back-billing/prescription findings as "may have grounds to dispute, subject to interruption" — not "this is illegal."**
*Why:* whether a debt has prescribed depends on facts the platform can't see (was there an acknowledgement, was legal process served). Overclaiming is inaccurate and risky. Reflected in check severity and message wording.

**Property rates may prescribe differently from service charges — flagged, not resolved.**
*Why:* case law has treated rates differently in places. Encode 3-year prescription for service charges; flag rates as subject to legal nuance until confirmed.

## Process

**Three living documents (project briefing, technical design, decision log) kept in the repo AND in project knowledge; updated as an end-of-session ritual.**
*Why:* a chat is fragile, unsearchable in practice, and non-portable memory. Durable documents in project knowledge bootstrap every future chat with full context and stop knowledge being lost between sessions. The end-of-session "update the docs" ritual prevents decisions accumulating solely in chat history again.

**When consolidating across projects, newer attached documents take precedence over older project history; contradictions are surfaced for human decision, never auto-resolved; older history fills gaps but never overrides.**
*Why:* this project's design work happened partly in the wrong project, whose own history is older. A precedence rule protects current decisions from being overwritten by stale ones.
