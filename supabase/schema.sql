-- Trainingsapp: plak dit in Supabase > SQL Editor en klik op Run.
-- Eén tabel voor alle gegevens. Elke gebruiker ziet alleen zijn eigen rijen (Row Level Security).

create table if not exists public.records (
  user_id    uuid    not null default auth.uid() references auth.users on delete cascade,
  tbl        text    not null,
  id         text    not null,
  data       jsonb   not null,
  updated_at bigint  not null,
  deleted    boolean not null default false,
  server_ts  timestamptz not null default clock_timestamp(),
  primary key (user_id, tbl, id)
);

create index if not exists records_user_server_ts on public.records (user_id, server_ts);

-- server_ts bijwerken bij elke wijziging, zodat andere apparaten weten wat nieuw is
create or replace function public.touch_server_ts() returns trigger
language plpgsql as $$
begin
  new.server_ts := clock_timestamp();
  return new;
end $$;

drop trigger if exists records_touch on public.records;
create trigger records_touch before insert or update on public.records
for each row execute function public.touch_server_ts();

alter table public.records enable row level security;

drop policy if exists "eigen rijen lezen" on public.records;
drop policy if exists "eigen rijen toevoegen" on public.records;
drop policy if exists "eigen rijen wijzigen" on public.records;

create policy "eigen rijen lezen" on public.records
  for select using (auth.uid() = user_id);
create policy "eigen rijen toevoegen" on public.records
  for insert with check (auth.uid() = user_id);
create policy "eigen rijen wijzigen" on public.records
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
