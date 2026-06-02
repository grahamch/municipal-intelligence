create table check_results (
    id bigint generated always as identity primary key,
    bill_id bigint references bills(id),
    billing_line_id bigint references billing_lines(id),
    check_type varchar not null,
    passed boolean not null,
    severity varchar not null,
    message varchar not null,
    amount_in_dispute numeric,
    created_at timestamptz default now()
);
