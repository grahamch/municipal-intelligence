create table vat_rates (
  id bigint generated always as identity primary key,
  rate decimal(5,4) not null,
  effective_from date not null,
  effective_to date,
  created_at timestamptz default now()
);