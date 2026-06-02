create table municipalities (
    id bigint generated always as identity primary key,
    name varchar not null,
    province varchar, 
    billing_format varchar,
    created_at timestamptz default now() 
);