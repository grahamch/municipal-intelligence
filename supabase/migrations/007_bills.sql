create table bills (
    id bigint generated always as identity primary key,
    account_id bigint references accounts(id),
    period_start date not null,
    period_end date not null,
    issued_date date not null,
    total_amount numeric not null,
    document_url varchar,
    created_at timestamptz default now()
)