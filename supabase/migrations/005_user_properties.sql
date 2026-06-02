create table user_properties (
    id bigint generated always as identity primary key,
    user_id uuid references users(id),
    property_id bigint references properties(id),
    role varchar not null,
    created_at timestamptz default now()
);