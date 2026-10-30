-- Run this once in Supabase: SQL Editor -> New query -> paste -> Run

create table if not exists kv (
  key   text primary key,
  value text not null,
  updated_at timestamptz default now()
);

alter table kv enable row level security;

-- Demo-level access: anyone using the site can read, add and change rows.
create policy "kv read"   on kv for select using (true);
create policy "kv insert" on kv for insert with check (true);
create policy "kv update" on kv for update using (true) with check (true);
