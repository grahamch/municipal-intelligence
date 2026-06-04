-- ============================================================
-- Municipal Billing Intelligence — Initial Schema (baseline)
-- Single source of truth. Built from scratch, no migrations history.
-- Run once against an empty database.
-- ============================================================
-- Table groups:
--   Reference   : municipalities, vat_rates, legal_parameters, check_config
--   Core domain : properties, users, user_properties, accounts
--   Tariff data : tariff_schedules, rebates          (the moat)
--   Bills       : bills, billing_lines
--   Engine output: check_results, dispute_letters
-- ============================================================


-- ---------- REFERENCE ----------

-- The municipalities whose tariffs we encode.
create table municipalities (
  id              bigint generated always as identity primary key,
  name            varchar not null,
  province        varchar,
  billing_format  varchar,
  created_at      timestamptz default now()
);

-- National VAT rate history. Time-bounded; null effective_to = current.
create table vat_rates (
  id              bigint generated always as identity primary key,
  rate            decimal(5,4) not null,   -- e.g. 0.1500
  effective_from  date not null,
  effective_to    date,
  created_at      timestamptz default now()
);

-- Legal rules the engine cites (prescription, back-billing position, etc).
-- municipality_id null = national rule; set = municipality-specific.
create table legal_parameters (
  id              bigint generated always as identity primary key,
  municipality_id bigint references municipalities(id),
  parameter_key   varchar not null,        -- e.g. 'prescription_period_years'
  value_numeric   numeric,                 -- e.g. 3
  value_text      varchar,                 -- e.g. 'no by-law cap'
  legal_citation  varchar,                 -- e.g. 'Prescription Act 68 of 1969'
  notes           text,
  effective_from  date,
  effective_to    date,
  created_at      timestamptz default now()
);

-- Per-check tuning. Lets the engine be configured without code changes.
create table check_config (
  id                  bigint generated always as identity primary key,
  check_type          varchar not null unique,   -- engine key, e.g. 'estimated_read'
  description         text,
  default_severity    varchar,                   -- info / warning / error
  tolerance_amount    numeric,                   -- absolute rand floor before flagging
  tolerance_percent   decimal(5,4),              -- proportional floor before flagging
  enabled             boolean default true,
  min_bills_required  integer default 1,         -- how many bills before this check can run
  requires_consecutive boolean default false,    -- must those bills be adjacent in time
  legal_parameter_id  bigint references legal_parameters(id),
  created_at          timestamptz default now()
);


-- ---------- CORE DOMAIN ----------

-- Physical properties being monitored.
create table properties (
  id                    bigint generated always as identity primary key,
  address_line_1        varchar not null,
  address_line_2        varchar,
  suburb                varchar not null,
  city                  varchar not null,
  postal_code           varchar not null,
  property_type         varchar not null,        -- freestanding / sectional_title / commercial
  municipal_valuation   numeric,                 -- drives rates calculation
  valuation_date        date,
  erf_size_m2           numeric,                 -- drives erf-size-banded sanitation
  heritage_site         boolean default false,   -- rebate-qualifying flags
  high_density          boolean default false,
  child_headed_household boolean default false,
  created_at            timestamptz default now()
);

-- Profile data, keyed to Supabase Auth. Credentials live in auth.users.
create table users (
  id                    uuid references auth.users(id) primary key,
  email                 varchar not null,
  full_name             varchar,
  cellphone             varchar,
  date_of_birth         date,                    -- rebate eligibility (pensioner age bands)
  disability_status     boolean default false,
  household_income_band varchar,
  social_package_status varchar,
  created_at            timestamptz default now()
);

-- Junction: which users hold which properties, in what role.
create table user_properties (
  id                  bigint generated always as identity primary key,
  user_id             uuid references users(id),
  property_id         bigint references properties(id),
  role                varchar not null,           -- owner / trustee / managing_agent
  is_primary_property boolean default false,      -- drives R300k rates exclusion
  created_at          timestamptz default now()
);

-- A billing account. issuer_type generic for future managing-agent layer;
-- municipality_id nullable for the same reason.
create table accounts (
  id              bigint generated always as identity primary key,
  property_id     bigint references properties(id),
  municipality_id bigint references municipalities(id),
  issuer_type     varchar not null,               -- municipality (managing_agent later)
  holder_type     varchar not null,               -- individual / body_corporate
  holder_name     varchar not null,
  account_number  varchar not null,
  tariff_type     varchar,                         -- residential / commercial / etc
  created_at      timestamptz default now()
);


-- ---------- TARIFF DATA (the moat) ----------

-- One row per tariff band/component. structure_type names the calculation
-- pattern; the other columns are its parameters. band_basis says what the
-- band boundaries measure. season / time_period handle electricity.
create table tariff_schedules (
  id              bigint generated always as identity primary key,
  municipality_id bigint references municipalities(id),
  service_type    varchar not null,    -- electricity / water / sewerage / refuse / rates
  tariff_type     varchar,             -- property/customer category
  structure_type  varchar not null,    -- flat / block / fixed / stepped_fixed / valuation / demand
  band_basis      varchar,             -- consumption / property_value / erf_size / weight / none
  band_from       numeric,
  band_to         numeric,
  rate_per_unit   numeric,
  fixed_amount    numeric,
  value_exclusion numeric,             -- e.g. rates residential R300k exclusion
  period_basis    varchar,             -- monthly / daily_pro_rata
  season          varchar,             -- summer / winter / all
  time_period     varchar,             -- peak / standard / off_peak / all
  vat_applicable  boolean,
  effective_from  date not null,
  effective_to    date,
  notes           varchar,
  created_at      timestamptz default now()
);

-- Rebates that may apply to a charge (chiefly rates). Conditions held as text
-- for now; structured matching can come later.
create table rebates (
  id                   bigint generated always as identity primary key,
  municipality_id      bigint references municipalities(id),
  rebate_type          varchar not null,   -- percentage / value_cap / value_exclusion
  rebate_value         numeric,
  qualifying_conditions text,
  effective_from       date,
  effective_to         date,
  created_at           timestamptz default now()
);


-- ---------- BILLS ----------

-- One monthly bill per account. issued_date = date printed on the bill
-- (distinct from period and from upload time); drives Checks 4, 6, 7.
create table bills (
  id            bigint generated always as identity primary key,
  account_id    bigint references accounts(id),
  period_start  date not null,
  period_end    date not null,
  issued_date   date not null,
  total_amount  numeric not null,
  document_url  varchar,
  created_at    timestamptz default now()
);

-- Individual line items. Reading fields nullable (fixed charges have none).
-- line_period_* only set when a line covers a different period than the bill.
create table billing_lines (
  id                bigint generated always as identity primary key,
  bill_id           bigint references bills(id),
  description       varchar not null,
  meter_number      varchar,
  meter_type        varchar,
  unit              varchar,                 -- kWh / kVArh / kVA / kl / each
  multiply_factor   numeric default 1,       -- large-meter scaling
  previous_reading  numeric,
  current_reading   numeric,
  read_type         varchar,                 -- actual / estimated / final
  consumption       numeric,
  rate              numeric not null,
  amount            numeric not null,
  vat_applicable    boolean not null,
  vat_rate          decimal(5,4),
  time_period       varchar,                 -- peak / standard / off_peak (TOU lines)
  line_period_start date,
  line_period_end   date,
  created_at        timestamptz default now()
);


-- ---------- ENGINE OUTPUT ----------

-- One row per check run against a bill (or a specific line).
create table check_results (
  id                bigint generated always as identity primary key,
  bill_id           bigint references bills(id),
  billing_line_id   bigint references billing_lines(id),
  check_type        varchar not null,
  passed            boolean not null,
  severity          varchar not null,
  message           varchar not null,
  calculated_amount numeric,
  billed_amount     numeric,
  amount_in_dispute numeric,
  created_at        timestamptz default now()
);

-- Generated dispute letters.
create table dispute_letters (
  id          bigint generated always as identity primary key,
  bill_id     bigint references bills(id),
  content     text not null,
  status      varchar not null,              -- draft / sent / resolved
  created_at  timestamptz default now()
);


-- ---------- FOREIGN KEY INDEXES ----------
-- Postgres does not auto-create these. The engine joins/filters on them
-- constantly, so index every FK column.

create index idx_legal_parameters_municipality on legal_parameters(municipality_id);
create index idx_check_config_legal_parameter   on check_config(legal_parameter_id);
create index idx_user_properties_user           on user_properties(user_id);
create index idx_user_properties_property       on user_properties(property_id);
create index idx_accounts_property              on accounts(property_id);
create index idx_accounts_municipality          on accounts(municipality_id);
create index idx_tariff_schedules_municipality  on tariff_schedules(municipality_id);
create index idx_rebates_municipality           on rebates(municipality_id);
create index idx_bills_account                  on bills(account_id);
create index idx_billing_lines_bill             on billing_lines(bill_id);
create index idx_check_results_bill             on check_results(bill_id);
create index idx_check_results_billing_line     on check_results(billing_line_id);
create index idx_dispute_letters_bill           on dispute_letters(bill_id);


-- ---------- SEED DATA ----------

insert into municipalities (name, province, billing_format) values
  ('City of Cape Town',    'Western Cape', 'coct'),
  ('City of Johannesburg', 'Gauteng',      'coj'),
  ('Nelson Mandela Bay',   'Eastern Cape', 'nmb');

insert into vat_rates (rate, effective_from, effective_to) values
  (0.1400, '1993-04-07', '2018-03-31'),
  (0.1500, '2018-04-01', null);