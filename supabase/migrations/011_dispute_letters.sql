create table dispute_letters (
    id bigint generated always as identity primary key,
    bill_id bigint references bills(id),
    content text not null,
    status varchar not null,
    created_at timestamptz default now()
);