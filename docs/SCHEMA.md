# Municipal Billing Intelligence — Database Schema

This document describes every table in the platform's database, why it exists, what each column stores, and how it connects to the rest of the system. It is the single reference for understanding the data model.

---

## Architecture overview

The database has five logical groups:

| Group | Tables | Purpose |
|---|---|---|
| Reference | municipalities, vat_rates, legal_parameters, check_config | Stable configuration the engine reads |
| Core domain | properties, users, user_properties, accounts | Who owns what, and how billing accounts are structured |
| Tariff data | tariff_schedules, rebates | The moat — authoritative rates the engine recalculates against |
| Bills | bills, billing_lines | The actual invoices ingested from municipalities |
| Engine output | check_results, dispute_letters | What the rules engine found, and the letters it generated |

### The six calculation patterns

Every charge on every bill in South Africa is one of six types. The `structure_type` column on `tariff_schedules` names the pattern; the engine contains the formula; the other columns supply the parameters. Adding a new municipality means adding rows of parameters, not writing new code.

| structure_type | What it means | Example |
|---|---|---|
| `flat` | rate × consumption | Commercial electricity energy charge |
| `block` | consumption split across bands, each band at its own rate, summed | Residential water, electricity prepaid |
| `fixed` | a flat amount per period, no consumption involved | Service charge, capacity charge |
| `stepped_fixed` | a flat amount determined by which band an attribute falls in | Refuse by property value, sanitation by erf size |
| `valuation` | (valuation − exclusion) × rate_per_unit ÷ divisor × period | Property rates |
| `demand` | rate × measured demand (kVA or kVArh) | Large-user electricity demand charge |

---

## Reference tables

These tables hold stable configuration. They change rarely (when legislation changes, or when a new municipality is onboarded), and the rules engine reads from them on every check run.

---

### municipalities

Stores the South African municipalities whose tariff structures have been encoded. Every billing account, tariff schedule, rebate, and legal parameter is anchored to a municipality.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| name | varchar | Full official name |
| province | varchar | Province the municipality sits in |
| billing_format | varchar | Short code identifying the bill layout for OCR parsing (e.g. `coct`, `coj`, `nmb`) |
| created_at | timestamptz | Auto-set on insert |

**Why `billing_format` exists:** Different municipalities lay out their bills differently — different column positions, different section headings, different date formats. The OCR pipeline uses this code to select the right parsing rules for a given bill. When you add a new municipality, you define its layout here.

**Example rows:**

```sql
('City of Cape Town',    'Western Cape', 'coct')
('City of Johannesburg', 'Gauteng',      'coj')
('Nelson Mandela Bay',   'Eastern Cape', 'nmb')
```

---

### vat_rates

Stores the national VAT rate history. Because VAT has changed over time (14% until March 2018, 15% from April 2018), and could change again, rates are stored with effective dates rather than hardcoded. Check 7 uses the rate applicable on the bill's `issued_date`.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| rate | decimal(5,4) | The rate as a decimal, e.g. 0.1500 for 15% |
| effective_from | date | First day this rate applies |
| effective_to | date | Last day (null = currently in effect) |
| created_at | timestamptz | Auto-set on insert |

**How the engine uses it:** `SELECT rate FROM vat_rates WHERE effective_from <= issued_date AND (effective_to IS NULL OR effective_to >= issued_date)` — finds the VAT rate that was in force on the day the bill was issued.

**Example rows:**

```sql
(0.1400, '1993-04-07', '2018-03-31')  -- 14% era
(0.1500, '2018-04-01', null)          -- 15% current
```

---

### legal_parameters

Stores legal rules the engine cites in dispute letters. `municipality_id` is null for national rules (like the Prescription Act) and set for municipality-specific rules. Unlike tariff data, these are legal parameters — they change when legislation changes, not when annual budgets are set.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| municipality_id | bigint | FK → municipalities. Null = national rule |
| parameter_key | varchar | Machine-readable key, e.g. `prescription_period_years` |
| value_numeric | numeric | Numeric value where applicable, e.g. 3 |
| value_text | varchar | Text value where applicable, e.g. `no by-law cap` |
| legal_citation | varchar | The statute or by-law being cited |
| notes | text | Context, nuance, or caveats the engine should surface |
| effective_from | date | When this rule came into force |
| effective_to | date | When it ceased (null = still in force) |
| created_at | timestamptz | Auto-set on insert |

**Key parameters to seed:**

| parameter_key | value | citation | notes |
|---|---|---|---|
| prescription_period_years | 3 | Prescription Act 68 of 1969 | Runs from when debt becomes due. Interrupted by acknowledgement of debt or service of legal process. Property rates may be treated differently in some case law. |
| backbilling_cap | null (no cap) | CoJ By-law GN 1857 of 2005, s.25 | By-law explicitly preserves Council's right to recover regardless of its own failure to bill. No in-by-law time limit. Prescription Act is the operative limit. |
| estimated_read_policy | 12 months basis | CoJ Credit Control Policy 2022, cl.9.3 | Policy (not by-law) states estimates are based on 12 preceding months and adjusted as soon as an actual reading is obtained. Useful for dispute letters even though not legally binding. |

> **⚠️ UNRESOLVED CONTRADICTION — TO VERIFY before seeding `backbilling_cap` / `estimated_read_policy` and wiring the back-billing check.** Older project history sourced the back-billing limit and dispute-letter authority to the **Municipal Systems Act**; these documents ground them in the **Prescription Act + CoJ Credit Control By-laws** and do not cite the MSA. Confirm which instrument is operative before these parameters are treated as final.

---

### check_config

Registers every check the engine can run, with its tuning parameters. This table exists so the engine's behaviour can be changed — enabling/disabling checks, adjusting tolerances, changing severity — without touching code. Each row represents one check type.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| check_type | varchar (unique) | Machine key used throughout the engine, e.g. `estimated_read` |
| description | text | Human-readable description of what the check does |
| default_severity | varchar | `info` / `warning` / `error` — how serious a failure is |
| tolerance_amount | numeric | Absolute rand threshold below which discrepancies are ignored (handles rounding) |
| tolerance_percent | decimal(5,4) | Proportional threshold — e.g. 0.005 = ignore if under 0.5% |
| enabled | boolean | Whether the check currently runs. Default true. |
| min_bills_required | integer | How many bills for this account must exist before this check can run. Default 1. |
| requires_consecutive | boolean | Whether those bills must be adjacent in time (no gaps). Default false. |
| legal_parameter_id | bigint | FK → legal_parameters. The legal basis cited if this check fails. |
| created_at | timestamptz | Auto-set on insert |

**Why tolerance columns exist:** The engine recalculates charges from scratch. Municipalities round at different points in their calculations, so the engine's result and the bill's result will sometimes differ by a few cents even when the billing is correct. Without a tolerance floor, the engine cries wolf on every bill. A tolerance of R1.00 means "only flag it if the discrepancy is more than R1."

**Checks to seed:**

| check_type | description | severity | min_bills |
|---|---|---|---|
| estimated_read | Detects billing lines where read_type is estimated | warning | 1 |
| consumption_spike | Flags consumption that is anomalously high relative to this account's history | error | 3 |
| reading_continuity | Checks that each bill's opening reading matches the previous bill's closing reading | error | 2 |
| block_tariff_arithmetic | Recalculates tiered/block charges and compares to what was billed | error | 1 |
| tariff_misclassification | Checks the rate applied matches the account's category in the tariff schedule | error | 1 |
| backbilling | Flags charges for periods outside the legally permissible window | error | 1 |
| fixed_charge_duplication | Detects the same fixed charge appearing more than once in one billing period | error | 1 |
| prescription | Flags any attempt to recover debts older than the prescription period | error | 1 |
| vat_miscalculation | Checks VAT is calculated at the correct rate on the correct base amount | error | 1 |
| rebate_entitlement | Checks whether the account holder qualifies for rebates they are not receiving | warning | 1 |
| interest_on_backbilling | Flags interest charged from original due date on a back-billed amount | warning | 2 |

---

## Core domain tables

These tables model the real-world entities: properties, people, and the billing accounts that connect them to municipalities.

---

### properties

A physical property — a house, a flat, a commercial building — that is being monitored. Properties are the anchor point for everything else. A property has accounts; accounts have bills.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| address_line_1 | varchar (required) | Street address |
| address_line_2 | varchar | Unit number, complex name, etc. Nullable. |
| suburb | varchar (required) | |
| city | varchar (required) | |
| postal_code | varchar (required) | Stored as text — postal codes are identifiers, not numbers |
| property_type | varchar (required) | `freestanding` / `sectional_title` / `commercial` |
| municipal_valuation | numeric | The municipality's assessed value — drives rates calculations |
| valuation_date | date | When the valuation was assessed (printed on the bill) |
| erf_size_m2 | numeric | Stand size in square metres — drives erf-size-banded sanitation charges |
| heritage_site | boolean | Rebate-qualifying flag (20% rates rebate in CoJ) |
| high_density | boolean | Rebate-qualifying flag (5% rates rebate in CoJ) |
| child_headed_household | boolean | Rebate-qualifying flag (100% rates rebate in CoJ) |
| created_at | timestamptz | Auto-set on insert |

**Example:**

```sql
address_line_1:      '12 Milner Avenue'
address_line_2:      'Sea Glade Body Corporate'
suburb:              'Hout Bay'
city:                'Cape Town'
postal_code:         '7806'
property_type:       'sectional_title'
municipal_valuation: 0        -- R0 on the CoCT bill (exempt or zero-valued)
erf_size_m2:         null     -- Body corporate bill doesn't specify unit erf
```

---

### users

Profile data for people who log into the platform. Authentication (passwords, sessions) is handled by Supabase Auth in a separate system table. This table stores only profile and rebate-eligibility data. The `id` column links directly to Supabase Auth's user record.

| Column | Type | Notes |
|---|---|---|
| id | uuid | Primary key. References `auth.users(id)` — set by Supabase Auth on signup |
| email | varchar (required) | |
| full_name | varchar | |
| cellphone | varchar | |
| date_of_birth | date | Determines pensioner age band for rates rebate checks |
| disability_status | boolean | Rebate-qualifying flag |
| household_income_band | varchar | Income bracket — determines which pensioner rebate tier applies |
| social_package_status | varchar | Indigent / extended social package — rebate qualifying |
| created_at | timestamptz | Auto-set on insert |

**Why rebate fields are on the user:** Rates rebates in South Africa are based on who *owns* the property, not the property itself (age, income, disability). To check whether someone is receiving a rebate they're entitled to, the engine needs to know these facts about the person, not just the property.

**Important:** A trigger should eventually auto-create this profile row when a user signs up. Until that's built, new auth users need a matching row inserted manually for the engine to work.

---

### user_properties

A junction table linking users to properties. One user can be linked to many properties (a property investor, a managing agent overseeing a portfolio). One property can have multiple users linked to it (a trustee and an owner on the same body corporate account).

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| user_id | uuid | FK → users |
| property_id | bigint | FK → properties |
| role | varchar (required) | `owner` / `trustee` / `managing_agent` |
| is_primary_property | boolean | Whether this is the user's primary residence — affects which rates rebates apply |
| created_at | timestamptz | Auto-set on insert |

**Why `is_primary_property` is here and not on `properties`:** "Primary" is relative to a person. The same property could be someone's primary residence and someone else's investment property. The flag belongs on the relationship, not the property itself.

---

### accounts

A billing account — the account number on a municipal bill. One property can have multiple accounts (different service providers, or separate water and electricity accounts). The schema is designed to eventually support managing-agent accounts (Layer 2 billing) via `issuer_type` and nullable `municipality_id`.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| property_id | bigint | FK → properties |
| municipality_id | bigint | FK → municipalities. Nullable — will be null for managing-agent accounts in future |
| issuer_type | varchar (required) | `municipality` for all MVP accounts. `managing_agent` reserved for Layer 2. |
| holder_type | varchar (required) | `individual` / `body_corporate` |
| holder_name | varchar (required) | Name as printed on the bill |
| account_number | varchar (required) | The account number on the bill |
| tariff_type | varchar | `residential` / `commercial` / `industrial` etc. Nullable — may not be known at creation time. |
| created_at | timestamptz | Auto-set on insert |

**Example (Sea Glade bulk municipal account):**

```sql
property_id:    1     -- Sea Glade property
municipality_id: 1    -- City of Cape Town
issuer_type:    'municipality'
holder_type:    'body_corporate'
holder_name:    'SEA GLADE BODY CORP'
account_number: '142063617'
tariff_type:    'commercial'
```

---

## Tariff data tables

These two tables are the moat. They encode the authoritative tariff structures for every municipality the engine supports. Anyone building a competing platform would need to replicate years of data entry to match this.

---

### tariff_schedules

Stores tariff rates in a parametric structure where each row represents one band or component of a charge. The `structure_type` column tells the engine which calculation formula to apply; the other columns supply the parameters.

**One row per band.** A three-band water tariff is three rows. This makes the data queryable ("find all bands above R30/kl across all municipalities"), and makes data entry match the format of published tariff schedules.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| municipality_id | bigint | FK → municipalities |
| service_type | varchar | `electricity` / `water` / `sewerage` / `refuse` / `rates` |
| tariff_type | varchar | The customer/property category this rate applies to |
| structure_type | varchar | The calculation pattern — see the six patterns at the top of this document |
| band_basis | varchar | What the band boundaries measure: `consumption` / `property_value` / `erf_size` / `weight` / `none` |
| band_from | numeric | Lower boundary of this band (inclusive) |
| band_to | numeric | Upper boundary of this band (null = no upper limit) |
| rate_per_unit | numeric | The rate applied per unit within this band |
| fixed_amount | numeric | A flat charge amount (used for `fixed` and `stepped_fixed` structure types) |
| value_exclusion | numeric | Amount subtracted before applying the rate (e.g. residential rates R300,000 exclusion) |
| period_basis | varchar | How the charge is divided across time: `monthly` or `daily_pro_rata` |
| season | varchar | `summer` / `winter` / `all` — for electricity tariffs that vary by season |
| time_period | varchar | `peak` / `standard` / `off_peak` / `all` — for time-of-use electricity tariffs |
| vat_applicable | boolean | Whether VAT applies to this charge |
| effective_from | date (required) | First day this rate is in effect |
| effective_to | date | Last day (null = currently in effect) |
| notes | varchar | Free-text notes for unusual structures or conditions |
| created_at | timestamptz | Auto-set on insert |

**Example — CoJ domestic water, 2025/26 (three rows shown of eight):**

```sql
-- Free band
(municipality_id=2, service_type='water', tariff_type='domestic_conventional',
 structure_type='block', band_basis='consumption',
 band_from=0, band_to=6, rate_per_unit=0, fixed_amount=null,
 season='all', time_period='all', vat_applicable=true,
 effective_from='2025-07-01', effective_to=null)

-- Band 2: >6 to 10 kl at R29.84/kl
(municipality_id=2, service_type='water', tariff_type='domestic_conventional',
 structure_type='block', band_basis='consumption',
 band_from=6, band_to=10, rate_per_unit=29.84, fixed_amount=null,
 season='all', time_period='all', vat_applicable=true,
 effective_from='2025-07-01', effective_to=null)

-- Band 8: >50 kl at R89.24/kl
(municipality_id=2, service_type='water', tariff_type='domestic_conventional',
 structure_type='block', band_basis='consumption',
 band_from=50, band_to=null, rate_per_unit=89.24, fixed_amount=null,
 season='all', time_period='all', vat_applicable=true,
 effective_from='2025-07-01', effective_to=null)
```

**Example — CoJ residential rates, 2025/26 (one row, valuation structure):**

```sql
(municipality_id=2, service_type='rates', tariff_type='residential',
 structure_type='valuation', band_basis='none',
 band_from=null, band_to=null,
 rate_per_unit=0.009545,      -- 0.9545 cents in the rand
 fixed_amount=null,
 value_exclusion=300000,       -- first R300k exempt
 period_basis='monthly',
 season='all', time_period='all', vat_applicable=false,
 effective_from='2025-07-01', effective_to=null)
```

**Example — CoJ refuse (residential), 2025/26 (one row of seven value bands):**

```sql
-- Property valued R500,001 to R750,000 pays R246/month
(municipality_id=2, service_type='refuse', tariff_type='residential',
 structure_type='stepped_fixed', band_basis='property_value',
 band_from=500001, band_to=750000,
 rate_per_unit=null, fixed_amount=246,
 season='all', time_period='all', vat_applicable=true,
 effective_from='2025-07-01', effective_to=null)
```

---

### rebates

Stores the rebates a property owner may be entitled to claim against their rates. Rebates reduce or eliminate the rates charge based on who the owner is — their age, income, disability status, or other qualifying conditions. The engine's rebate-entitlement check reads from this table alongside the user's profile to determine whether an expected rebate is missing from the bill.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| municipality_id | bigint | FK → municipalities |
| rebate_type | varchar | `percentage` / `value_cap` / `value_exclusion` |
| rebate_value | numeric | The percentage (as decimal) or the rand cap, depending on rebate_type |
| qualifying_conditions | text | Human-readable description of who qualifies |
| effective_from | date | |
| effective_to | date | Null = currently in effect |
| created_at | timestamptz | Auto-set on insert |

**The three rebate types explained:**

`percentage` — a percentage off the total rates charge. E.g. Heritage sites get 20% off.

`value_cap` — 100% rebate up to a specified property value, then normal rates above it. E.g. pensioners aged 70+ pay zero rates on the first R2 million of property value.

`value_exclusion` — a fixed amount subtracted from the valuation before the rate is applied. The national residential exclusion (first R300,000 exempt) is this type.

**Example rows (CoJ 2025/26):**

```sql
-- National residential exclusion
(municipality_id=2, rebate_type='value_exclusion', rebate_value=300000,
 qualifying_conditions='All residential properties. For owners with multiple properties, only the highest-value property receives the full R300,000 exclusion. Additional properties are capped at R15,000.',
 effective_from='2025-07-01')

-- Pensioners 60-69, income ≤ R13,049/month
(municipality_id=2, rebate_type='value_cap', rebate_value=1500000,
 qualifying_conditions='100% rebate up to R1.5m property value. Owner must be aged 60-69, gross monthly household income ≤ R13,049. Only primary property.',
 effective_from='2025-07-01')

-- Pensioners 70+
(municipality_id=2, rebate_type='value_cap', rebate_value=2000000,
 qualifying_conditions='100% rebate up to R2m property value. Owner must be aged 70 or above. Income not considered. Only primary property.',
 effective_from='2025-07-01')

-- Heritage sites
(municipality_id=2, rebate_type='percentage', rebate_value=0.20,
 qualifying_conditions='20% rates rebate. Property must be registered as a heritage site.',
 effective_from='2025-07-01')
```

---

## Bills tables

These two tables store the actual invoices ingested from municipalities. `bills` is the header (one row per invoice), `billing_lines` are the individual line items on that invoice.

---

### bills

One row per municipal bill. Contains the overall bill metadata — the dates, the account, the total, and where the original document is stored. The billing lines that make up the bill live in `billing_lines`.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| account_id | bigint | FK → accounts |
| period_start | date (required) | Start of the billing period (printed on the bill) |
| period_end | date (required) | End of the billing period |
| issued_date | date (required) | Date the municipality generated and issued the bill. Different from period and from upload date. Used by Checks 4, 6, and 7. |
| total_amount | numeric (required) | The total amount due on the bill |
| document_url | varchar | Link to the original uploaded PDF in Supabase Storage |
| created_at | timestamptz | Auto-set on insert |

**Why issued_date is separate from period dates:** A bill issued on 13 January 2026 might cover the period 26 November 2025 to 30 December 2025. All three dates are different. `issued_date` determines the applicable VAT rate (Check 7), the back-billing window (Check 4), and the prescription calculation (Check 6).

**Example (the CoJ business bill from Lenasia):**

```sql
account_id:   1
period_start: '2025-11-26'   -- electricity reading period start (earliest service period)
period_end:   '2025-12-30'   -- electricity reading period end
issued_date:  '2026-01-13'   -- date printed on the bill
total_amount: 4217085.53
document_url: 'storage/bills/coj-558833914-jan2026.pdf'
```

---

### billing_lines

One row per line item on a bill. A typical municipal bill has five to fifteen lines (electricity consumption, electricity service charge, water consumption, water fixed charge, sewerage, refuse, rates, etc.). Each line is stored separately so the engine can check each charge individually.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| bill_id | bigint | FK → bills |
| description | varchar (required) | The label exactly as it appears on the bill |
| meter_number | varchar | The meter this line relates to. Nullable — fixed charges have no meter. |
| meter_type | varchar | `electricity` / `water` / `gas`. Nullable. |
| unit | varchar | The unit of measurement: `kWh` / `kVArh` / `kVA` / `kl` / `each`. Nullable. |
| multiply_factor | numeric | Meter scaling factor (default 1). Large commercial meters may have a factor of 120 — raw reading difference × factor = actual consumption. |
| previous_reading | numeric | Meter reading at start of period. Nullable (fixed charges have no readings). |
| current_reading | numeric | Meter reading at end of period. Nullable. |
| read_type | varchar | `actual` / `estimated` / `final`. Nullable. The basis of Check 1. |
| consumption | numeric | Current reading minus previous reading, times multiply_factor. The municipality's stated figure — the engine independently recalculates to verify. Nullable. |
| rate | numeric (required) | The rate charged per unit, or the fixed charge amount |
| amount | numeric (required) | The line total as billed |
| vat_applicable | boolean (required) | Whether VAT applies to this line |
| vat_rate | decimal(5,4) | The VAT rate applied on this specific line. Nullable (cross-checked against vat_rates table in Check 7). |
| time_period | varchar | `peak` / `standard` / `off_peak` / `all`. Only populated for TOU (time-of-use) electricity lines. |
| line_period_start | date | Only set when this line covers a different period than the bill's main period. Used to detect back-billing (a charge for a past period added to a current bill). |
| line_period_end | date | As above. |
| created_at | timestamptz | Auto-set on insert |

**Why `multiply_factor` matters:** On the CoJ business bill, the electricity meter showed a raw reading difference of 60,434.640 kWh. On the Cape Town bill, the electricity meter showed a difference of 242.378 with a multiply factor of 120, meaning actual consumption is 242.378 × 120 = 29,085.3 kWh. Without storing and applying this factor, the consumption recalculation is wrong by an order of magnitude on large commercial meters.

**Example rows from the CoJ Lenasia electricity billing lines:**

```sql
-- Energy charge (estimated read)
(bill_id=1, description='Energy charge',
 meter_number='63038520', meter_type='electricity', unit='kWh',
 multiply_factor=1,
 previous_reading=6351443.000, current_reading=6411877.640,
 read_type='estimated', consumption=60434.640,
 rate=2.6141, amount=157982.19,
 vat_applicable=true, vat_rate=0.1500, time_period='all')

-- Reactive energy charge (estimated read, different unit)
(bill_id=1, description='Reactive energy charge',
 meter_number='63038520', meter_type='electricity', unit='kVArh',
 multiply_factor=1,
 previous_reading=2584122.000, current_reading=6925446.960,
 read_type='estimated', consumption=4341324.960,
 rate=0.4243, amount=1834331.46,
 vat_applicable=true, vat_rate=0.1500, time_period='all')

-- Demand charge (kVA, no readings)
(bill_id=1, description='Demand charge',
 meter_number='63038520', meter_type='electricity', unit='kVA',
 multiply_factor=null,
 previous_reading=null, current_reading=null,
 read_type=null, consumption=109.100,
 rate=423.10, amount=46160.21,
 vat_applicable=true, vat_rate=0.1500, time_period='all')

-- Service charge (fixed, no meter, no readings)
(bill_id=1, description='Service charge',
 meter_number=null, meter_type=null, unit=null,
 multiply_factor=null,
 previous_reading=null, current_reading=null,
 read_type=null, consumption=null,
 rate=3541.57, amount=3541.57,
 vat_applicable=true, vat_rate=0.1500, time_period='all')
```

---

## Engine output tables

These tables store what the rules engine produces. They never need to be edited manually — the engine writes to them on every run.

---

### check_results

One row per check run against a bill (or a specific billing line). If the engine runs eleven checks against a bill, eleven rows are written here. The `passed` field says whether the check passed or failed; `amount_in_dispute` is populated when a check can calculate the financial value of the error.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| bill_id | bigint | FK → bills. Every result is anchored to the bill it was run against. |
| billing_line_id | bigint | FK → billing_lines. Nullable — some checks (duplication, prescription) operate at bill level, not line level. |
| check_type | varchar (required) | Matches `check_config.check_type` — the key identifies which check ran |
| passed | boolean (required) | Whether the check passed. False = an error was found. |
| severity | varchar (required) | `info` / `warning` / `error` — copied from `check_config` at run time |
| message | varchar (required) | Human-readable explanation of what was found. This text is used in dispute letters. |
| amount_in_dispute | numeric | The rand value of the potential error. Null if not quantifiable. |
| created_at | timestamptz | When the check was run |

**Example results for the CoJ Lenasia bill:**

```sql
-- Check 1 fires on every electricity line (all are estimated)
(bill_id=1, billing_line_id=1, check_type='estimated_read',
 passed=false, severity='warning',
 message='Estimated read detected on electricity energy charge (meter 63038520). Municipality may owe correction once actual reading is obtained.',
 amount_in_dispute=null)

-- Check 3 fires if block tariff arithmetic is wrong
(bill_id=1, billing_line_id=1, check_type='block_tariff_arithmetic',
 passed=true, severity='error',
 message='Block tariff arithmetic verified. Charged R157,982.19 matches recalculated R157,982.19.',
 amount_in_dispute=null)

-- Check 6 fires if any line is prescribed
(bill_id=1, billing_line_id=null, check_type='prescription',
 passed=true, severity='error',
 message='All charges fall within the 3-year prescription window (Prescription Act 68 of 1969).',
 amount_in_dispute=null)
```

---

### dispute_letters

Stores generated dispute letters. When the engine finds errors with enough combined severity or disputed amount, it generates a pre-written letter the user can send to the municipality. The letter cites the specific checks that failed, the legal basis, and the amount in dispute.

| Column | Type | Notes |
|---|---|---|
| id | bigint | Auto-generated primary key |
| bill_id | bigint | FK → bills |
| content | text (required) | The full text of the generated letter |
| status | varchar (required) | `draft` / `sent` / `resolved` |
| created_at | timestamptz | When the letter was generated |

---

## Key relationships at a glance

```
municipalities
    ├── accounts (municipality_id)
    ├── tariff_schedules (municipality_id)
    ├── rebates (municipality_id)
    └── legal_parameters (municipality_id, nullable = national)

properties
    ├── user_properties (property_id) ──── users (user_id)
    └── accounts (property_id)
              └── bills (account_id)
                    ├── billing_lines (bill_id)
                    ├── check_results (bill_id)
                    │         └── billing_lines (billing_line_id, nullable)
                    └── dispute_letters (bill_id)

check_config
    └── legal_parameters (legal_parameter_id)
```

---

## What is not yet in the schema (deliberately deferred)

**Layer 2 billing (managing-agent invoices):** Individual sectional title owners receive invoices from their managing agent, not directly from the municipality. Auditing these requires comparing the agent's apportionment against the bulk municipal bill. Deferred until Layer 1 (direct municipal bills) is proven. The `issuer_type` and nullable `municipality_id` on `accounts` keep the door open without requiring a rebuild.

**Meter register number:** Large meters have multiple registers (Register 1: kWh, Register 2: kVArh). Currently the meter number alone identifies the meter. When Check 8 (meter mismatch) is built, a register field may be needed.

**Prepaid electricity:** Token-based prepaid meters do not produce statements with the readings and line-item breakdown the engine requires. Out of scope by design — the necessary input data does not exist on the customer's side.

**Account balances and arrears ageing:** Bills show arrears broken into 90/60/30/current bands and interest on arrears. Not needed for the first eight checks; reserved for future checks around interest legitimacy and arrears disputes.

**Triggers:** A database trigger should auto-create a `users` profile row when a new auth user signs up. Not yet built — manually insert profile rows for test users in the interim.
