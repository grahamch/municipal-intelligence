create table users (
  id uuid references auth.users(id) primary key,
  email varchar not null,
  full_name varchar,
  cellphone varchar,
  created_at timestamptz default now()
);