create table properties (
    id bigint generated always as identity primary key,
    address_line_1 varchar not null,
    address_line_2 varchar,
    suburb varchar not null,
    city varchar not null,
    postal_code varchar not null,
    property_type varchar not null,
    created_at timestamptz default now()
);