# Municipal Billing Intelligence Platform — Project Briefing

*Business and strategy reference. The durable source of truth for what this venture is and why. Update at the end of any session where a strategic decision changes.*

---

## The problem

South African municipal bills are riddled with errors, and consumers have no practical way to verify them. Billing systems are opaque, tariff structures are complex, and the burden of proof sits with the customer. The City of Johannesburg situation is acute — dysfunction intensified after the City Power takeover (July 2025), with widespread estimated reads, large catch-up "corrections," tariff misclassifications, and back-billing. These are durable, structural problems, not transient glitches.

There is hard evidence the problem is large. eThekwini's own Finance Committee report (Feb 2026) recorded **64,147 estimated water meters out of 588,907 (10.9%)** and **57,024 estimated electricity meters out of 366,607 (15.6%)**. A documented Durban case saw a landlord billed on estimates for over 18 months, then hit with the full retrospective adjustment in one lump sum with no warning — the characteristic financial profile of estimated-read errors: modest monthly, devastating on correction. (This is national evidence that the problem is real and large; it is not CoJ-specific.)

Section 27 of the CoJ by-law makes the Council's records *prima facie evidence* — the onus is on the customer to disprove the bill, not on the Council to prove it. Today the customer has no independent tool to do so.

## The solution

A platform that independently **recalculates every charge on a municipal bill** from first principles — using the consumption or valuation on the bill plus authoritative, encoded tariff data — and compares the recalculated figure to what was billed. Discrepancies beyond a materiality tolerance are flagged as findings, with the rand value quantified and the legal basis cited.

Pipeline: **OCR ingestion** of uploaded bills → structured billing-line data → **rules engine** that recalculates and compares → **check results** → **dispute letters** the customer can send.

Core principle: "reconstruct and compare." The engine re-derives what each charge *should* be and detects divergence — it is not a database of known errors.

## How municipal billing is structured (and where this platform sits)

Understanding the billing chain is essential to understanding scope.

- **Direct municipal billing.** The municipality issues a bill directly to a customer. That customer might be a freestanding house, a directly-billed commercial property, or a **sectional title body corporate's bulk account** (the municipality bills the body corporate as a single customer for the whole scheme's consumption). In every one of these cases, the only party that can have made a billing error is **the municipality itself**.
- **Downstream apportionment (sectional title only).** For a sectional title scheme, after the municipality bills the body corporate in bulk, a **managing agent** splits that bulk bill out to individual unit owners — typically using **sub-meters**. This second stage introduces two further parties who can err: the managing agent (wrong rate, wrong period, double-charged fixed fees) and the on-site staff who read the sub-meters.

A freestanding house has **only** the first stage — one bill, straight from the municipality, no intermediary. A sectional title scheme has **both** stages.

## The three error types (mapped to scope)

- **Type A — Municipality error on a directly-billed account.** Estimated reads, block-tariff arithmetic, tariff misclassification, back-billing, prescription, VAT, fixed-charge duplication, missed rebates. The municipality errs; nobody systematically catches it; the customer pays. **Applies to every directly-billed account** — freestanding houses, directly-billed commercial, and body corporate bulk accounts alike. **This is the entire MVP.**
- **Type B — Managing-agent apportionment error** (sectional title downstream). Wrong rate per kℓ, wrong period, fixed charges applied twice when splitting the bulk bill to units. **Deferred.**
- **Type C — Sub-meter reading error** (sectional title downstream). On-site staff misread or misrecord a unit's sub-meter. **Deferred.**

## MVP scope — defined by billing relationship, not property type

The MVP targets **any account billed directly by the municipality** — defined by the billing relationship, not the kind of building. This deliberately includes:
- Freestanding houses
- Directly-billed commercial properties
- **Sectional title bulk accounts** (the municipality's bill to the body corporate)

It excludes only the **downstream managing-agent apportionment** (the per-unit split), which is the deferred work below.

Why this is the right boundary: it is defined by data you actually have (a municipal bill), it cleanly separates in-scope (the municipal bill, whoever receives it) from deferred (the sub-meter apportionment), and it means a sectional title scheme is *not* excluded — its bulk account is fully in scope; only the per-unit split waits. A body corporate trustee can be served on day one (auditing their bulk municipal bill) with no sub-metering logic built. Everything in scope is **Type A**.

Further MVP constraints:
- **First municipality: City of Johannesburg** — billing crisis most acute, value most demonstrable, problem most durable. *Selection principle: start where billing inaccuracy is highest, so value is most demonstrable.* Cape Town is understood to have very few billing inaccuracies, so despite the founder being based there it is a poor starting point. **Durban (eThekwini)** was also highlighted as a strong candidate on the same basis. This supersedes an earlier "Cape Town first, Gauteng second" line of reasoning from project history.
- **Conventional metered accounts only** — prepaid out of scope.
- Real test bills on hand: Sea Glade (founder's own Cape Town sectional title bulk account, CoCT), CoJ (Lenasia business), Nelson Mandela Bay, CoCT. Each exercises a different part of the engine:
  - **CoJ Lenasia** (commercial; estimated reads, demand charge, ×1 multiplier) — the primary worked example in the schema.
  - **Sea Glade CoCT** (sectional-title bulk; ×120 meter multiplier; electricity billed on a *commercial* tariff for a residential scheme) — both the multiplier and the tariff classification are flagged for verification, **not** confirmed errors.
  - **NMBM** (residential rates) — audited because the rates bill *appeared* very high versus a comparable property (the founder's own). The audit confirmed the rates charge itself was essentially **accurate**; the real discrepancies sat in other line items (a valuation figure differing from the valuation roll, noted as a future back-billing risk, and a water rate that could not be reconciled to a published tariff). A useful test point: the headline "this looks too high" suspicion was wrong, and the engine's value was in the line-item detail.

## Two types of detection (foundational framing)

This distinction shapes the build, the timeline, and the moat.

**Type 1 — Rule-based detection.** Errors that follow a known formula. Code the rule once and it works from day one. More data does not make these smarter — they are right or wrong immediately. An *engineering* problem. Examples: tariff misclassification, block-tariff arithmetic, estimated-read overrun, back-billing beyond the legal limit, prescription violations, VAT miscalculation, fixed-charge duplication, meter-number mismatch.

**Type 2 — Pattern-based detection.** Anomalies only visible once you have enough historical data to know what "normal" looks like for an account, property type, suburb, and season. A *data-science* problem, and where the engine gets smarter with volume. Examples: consumption-anomaly detection, municipality-specific error-pattern recognition, tariff-optimisation forecasting, fraud/theft signature detection.

**The strategic sequencing — the key insight:** build Type 1 to generate value from the first bill; collect clean, structured data passively while doing so; that accumulated data *is* what trains the Type 2 models later. Invest in collecting clean data from day one so the data-science investment in year two has something to work with. *This is the reasoning behind the decision to record every check result, pass and fail* — the passing observations are the baseline that makes Type 2 anomaly detection possible.

The deepest Type 2 moat is **municipality-specific quirk recognition**: each of 257 municipalities has systematic deviations (e.g. applying last year's tariff for the first two months of the financial year) visible only across thousands of accounts at once. A later competitor faces the same multi-year data-accumulation timeline — no shortcut.

## How it works — the account-centric model

The engine operates on an **account's bill history**, not a single bill in isolation. A user uploads one bill or many; more consecutive bills unlock more checks:
- **Single-bill checks** run on one bill (estimated read, block-tariff arithmetic, VAT, fixed-charge duplication, rebate entitlement)
- **Cross-bill checks** need multiple consecutive bills (consumption-spike, reading continuity, interest-on-back-billing)

Locked checks become the upsell ("upload two more consecutive bills to unlock spike detection"). A single-bill upload is the degenerate case — one engine, scaling its output to the data available.

## The moat

Defensibility is the **encoded tariff data** — authoritative tariff schedules for (eventually) all 257 municipalities, kept current each July — plus the **accumulated `check_results` data** powering Type 2 pattern detection. Sourcing and encoding every municipality's published schedules (dense, inconsistently published, not the public "understanding your bill" booklets) is exactly the work no competitor has done. The tariff data is a structured, queryable, potentially licensable dataset; adding a municipality is a data-entry task, not a code change, because the engine holds a fixed set of calculation patterns and the database supplies the parameters. The OCR challenge — 257 different bill layouts — is the single biggest day-one engineering problem and itself a barrier to entry.

**Data velocity** is a further moat lever: a single managing-agent sale routes hundreds of bills per month through the engine, refining the rules engine far faster than consumer acquisition could. Two candidate moats were stress-tested and **rejected as too weak to be durable**: a "cross-MA insight" advantage and a "neutrality positioning" advantage. Recording them here prevents relitigating them.

## Revenue model — OPTIONS UNDER CONSIDERATION, NOT DECIDED

⚠️ **The revenue model is far from decided.** What follows are *options* explored, each with different incentive structures and trade-offs. None is chosen. This is a priority area for dedicated work and real customer validation before commitment.

- **Option — B2B subscription (managing agents).** MA pays; platform reduces homeowner-query staff load or audits bulk accounts. Risk: fixing the MA's own downstream errors is an awkward sales conversation and invites build-it-in-house at scale. Auditing the municipality's errors on the bulk account is a cleaner pitch the MA can present to the body corporate as value-added.
- **Option — B2B/collective subscription (body corporate / trustees).** Trustee sees errors via a free audit, champions it, body corporate votes to subscribe. Pricing logic: municipality errors on the bulk account affect all units equally → flat rate per scheme, possibly banded by unit count. (Per-unit pricing would only make sense for the deferred downstream apportionment errors.)
- **Option — B2C subscription (homeowners / freestanding).** Real, immediate financial pain, but customers don't know the problem exists, so acquisition is costly and the awareness-to-payment journey is long.
- **Option — Success fee.** Take a percentage (≈15%) of amounts recovered. Removes subscription friction. Especially powerful for high-value, low-frequency wins — 15% of a R30,000 prescribed-debt recovery is R4,500 from one case.
- **Option — "named tool" sold to incumbents (e.g. Venn).** Rather than competing with Venn, position the platform as a *named* SaaS tool (not white-label) that firms like Venn subscribe to, automating the manual detection their analysts currently do. Named branding builds client-facing equity but complicates the enterprise sale. **Critical unknown:** whether Venn already has internal automated detection — a conversation with a Venn insider is the highest-value next research step.
- **Option — B2B2C distribution.** Direct-to-household is the only genuinely unserved segment, but consumer acquisition is costly; reaching it economically may run via estate agents, bond originators, or auditors as distribution partners.

**Leading go-to-market mechanic (also an option, not locked):** the **free audit as product demo** — upload your bills, get an answer in ~60 seconds; the product demonstrates value before asking for payment. Works at trustee and individual level and needs little marketing copy.

**Not yet addressed:** final pricing, conversion assumptions, B2B-vs-B2C priority, freemium structure, unit economics, and whether monetisation hangs off subscription, dispute-letter generation, or successful recovery.

### Illustrative market sizing — ASSUMPTION-BASED, NOT VALIDATED

⚠️ **These figures are conservative back-of-envelope estimates built on stacked assumptions. None are validated.** They will be replaced by real data once the first batch of bills runs. Treat as directional only, not as project truth.

- **TAM** ~14M households; **SAM** ~3.5M; **SOM** ~100K–350K.
- **Pure success-fee model** bottoms out around **R1.7M/yr** — used in the original analysis as the argument *against* a success-fee-only model, not as a target.
- **Hybrid subscription** scenarios land in roughly the **R20–88M/yr** range; a **B2B layer** could add ~R24M.

## Error frequency and financial impact (evidence for prioritisation)

- Hard data exists only for estimated reads (eThekwini figures above). Other frequencies are inferred from legal cases and structural reasoning — low/medium confidence until the first ~5,000 real bills replace inference with evidence.
- **Tariff misclassification** — medium frequency but uniquely *persistent*: wrong charge every month until corrected, so recovery value compounds. Municipalities don't fix these easily.
- **Prescription violations** — rare but highest per-case impact: typically years of arrears, R5,000–R50,000+. Highest per-case revenue under a success-fee model.

**Fuller frequency / impact estimates — MOSTLY INFERENCE, LOW/MEDIUM CONFIDENCE.** ⚠️ Only estimated reads is hard data (eThekwini). Every other frequency is inferred from legal cases and structural reasoning; the average-recovery figures are internally inconsistent across the source analysis (e.g. estimated-read impact appears as ~R1,500 in one place and as part of an R3,000→R600/case model elsewhere). Use only to sequence the build, not to forecast revenue.

| Error type | Est. frequency | Avg. impact | Confidence |
|---|---|---|---|
| Estimated reads | ~13% | ~R1,500 | Hard (eThekwini) |
| Tariff misclassification | ~6% | ~R1,200 | Low/medium |
| Block-tariff arithmetic | ~6% | ~R500 | Low/medium |
| Back-billing | ~4% | ~R5,000 | Low/medium |
| Fixed-charge duplication | ~3% | ~R400 | Low |
| VAT | ~2% | ~R300 | Low |
| Prescription | ~1.5% | ~R15,000 | Low |
| Meter mismatch | ~0.7% | ~R6,000 | Low |

## Scope decisions (locked)

- **Prepaid electricity — OUT.** Token slips lack the readings, period, and line-item breakdown the engine needs. (Future possibility: a narrower "prepaid debt-recovery skimming" check.)
- **Time-of-use (TOU) electricity — IN.** Large commercial and large sectional-title bulk accounts (>100 kVA) may be on TOU; excluding it would fail the high-value accounts. Modelled via season + time_period dimensions.
- **Rebates — IN for MVP.** Conditional on owner attributes (age, income, disability). Flagship check.
- **Downstream apportionment (managing-agent → unit owner, Types B and C) — deferred**, schema kept generic via `accounts.issuer_type` and nullable `municipality_id`.
- **Meter-number mismatch — partially in, mostly deferred.** The *dynamic* form (meter number changed between consecutive bills) is detectable now via historical consistency. The *static* form (wrong meter from the start) needs a municipality data partnership and is deferred.
- **The "eight Type-1 checks only" MVP framing is SUPERSEDED.** The catalogue now also includes consumption-spike (Type 2), reading-continuity, interest-on-back-billing, and rebate-entitlement. The MVP therefore deliberately includes at least one Type 2 check.

## Legal foundation

> **⚠️ UNRESOLVED CONTRADICTION — TO VERIFY (vital; underpins the back-billing check and dispute-letter citations).** Older project history sourced the back-billing limit and dispute-letter authority to the **Municipal Systems Act**. These documents instead ground them in the **Prescription Act + CoJ Credit Control By-laws** and do not cite the MSA at all. This has not been reconciled. Confirm which instrument is operative before the back-billing check and its letter wording are finalised — do not treat the Prescription Act / by-law framing as settled until checked.

- **Prescription: 3 years** (Prescription Act 68 of 1969). Runs from when the debt becomes due; interrupted by acknowledgement of debt or service of legal process. The operative limit on back-billing.
- **CoJ Credit Control and Debt Collection By-laws** (General Notice 1857 of 2005, Gauteng Provincial Gazette Extraordinary Vol. 11 No. 213, 23 May 2005):
  - **Silent** on any back-billing time limit. Section 25 *preserves* the Council's recovery right despite its own billing failures — no by-law cap; the Prescription Act is the operative external limit.
  - Section 5 permits estimated billing; **no** obligation to reconcile within any period and **no** cap on the catch-up adjustment.
  - Section 17: arrears bear interest; Section 21(11): interest stops once an Acknowledgement of Debt is signed.
  - **Silent** on whether back-bill interest runs from the original due date or corrected-account date — a material, disputable gap.
  - **Section 27**: Council records are *prima facie evidence* — onus on the customer to rebut. **Strategic significance:** the platform arms the customer to discharge an onus the law places on them.
- **2022 CoJ Credit Control Policy** (cl. 9.3) — distinct from the by-law — says estimates are based on 12 preceding months and adjusted once an actual reading is obtained. Citable in dispute letters though only policy.
- Back-billing and prescription checks collapse to one operative test: the 3-year window. Frame findings as "you may have grounds to dispute, subject to whether the period was interrupted," not "this is illegal."
- Property *rates* may prescribe differently from service charges in case law — flag as nuance.

## Founder context

- Graham Cherrington. Computer science background; relearning modern web development (Java/PHP ~20 years ago). Cape Town. ~10 hours/week.
- Building the platform *while* relearning development — the build is the tutorial. Pauses to teach concepts, then resumes.
- Has direct access to a real body corporate (Sea Glade) and its managing agent (Intersect) — a customer-discovery asset most founders lack.

## Validation — concrete next actions (founder has the access)

Customer-discovery questions to close the revenue-model gaps with real people rather than theory:

**Sea Glade chairman (trustee):** most common homeowner billing complaints and frequency; whether anyone has ever checked the City's bulk-account billing; whether the managing agent provides a bulk-to-unit reconciliation; whether automated monthly checking + dispute-letter generation would be worth paying for and at what price; whether a body corporate can approve a subscription at trustee level or needs an AGM vote; any known managing-agent-side billing errors.

**Intersect account manager:** homeowner billing-query volume per month; whether they systematically check bulk municipal accounts and how; the dispute process and its staff-time cost; whether the body corporate would pay for automated detection + dispute letters, or see it as something they should already provide; whether their Sea Glade contract includes municipal billing accuracy as a deliverable.

**Sea Glade trustees interviewed — findings.** The chairman (Brett) and a trustee (Mark) confirmed neither scrutinises the bulk municipal bill; Intersect loads it to a trustee portal for ~3 signatories to sign off; per-unit calculations are outsourced to Nusco (formerly Motla); historical frustrations were *human meter-reading errors*, not tariff/calculation errors; and Cape Town billing is perceived as reliable, so bulk-account accuracy was never treated as a concern. *Implication: trustee "pain" for Type-A municipal errors is currently low in CoCT — consistent with the CoJ-first selection principle and a caution against assuming trustees will champion the product on bulk-account accuracy alone.*

## Competitive landscape

No competitor performs independent bill *recalculation*; the automation layer simply has not been built. The market splits into:

- **Manual consumer services** — Bill Deponent, Council Solutions, Municipal & Property Solutions. Human-driven, no automation.
- **Nominally tech-enabled consumer** — *BillVerify* claims AI auditing but is effectively manual (≈163 bill uploads in a year, an admin subdomain implying human processing, 100% desktop traffic, no organic search, WhatsApp workflow; its customer PDFs appeared publicly accessible — a responsible-disclosure message was sent). *Munichecker* is a bill *predictor* (input your own readings → estimated bill), not an auditor; freehold only, 5 municipalities, free.
- **Dead / wrong category** — *BillSure* (URL dead), *CityRadar* (civic service-delivery complaints, not billing).
- **Enterprise B2B (manual consultancy)** — *Venn Diagnostics*, the dominant incumbent (~37 years, ~R500m recovered, ~300,000 accounts analysed), large commercial only; *Munifix*, *SA MAD*, *Voltwise* follow the same manual model.
- **Sectional-title sub-meter layer** — *Nusco* (formerly Motla Utilities) does the on-site unit readings and calculations for schemes like Sea Glade and runs a manual bill-audit service ("Utilify", advertised ~R79).

**The unserved sweet spot:** small business, small landlords, and managed sectional-title schemes — too small for Venn, unserved by automation. **The real threat is not a direct rival** but a manual operator with deep domain knowledge (e.g. Council Solutions, 20+ years) deciding to build.

## Open questions (the honest list)

1. **Revenue model** — options mapped but none decided; needs the validation conversations and unit economics.
2. **Competitive landscape** — researched (see section above). Remaining unknown: whether Venn Diagnostics has internal automated detection.
3. **Go-to-market** — free-audit motion is the leading idea, not locked; CoJ focus while founder is in Cape Town is unresolved.
4. **OCR approach** — the single biggest day-one engineering problem (257 bill layouts); tooling not chosen.
5. **Rates prescription nuance** — needs legal confirmation.
