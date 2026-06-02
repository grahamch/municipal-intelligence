create table accounts (
    id bigint generated always as identity primary key,
    property_id bigint references properties(id),
    municipality_id bigint references municipalities(id),
    issuer_type varchar not null,
    holder_type varchar not null,
    holder_name varchar not null,
    account_number varchar not null,
    tariff_type varchar,
    created_at timestamptz default now()
);