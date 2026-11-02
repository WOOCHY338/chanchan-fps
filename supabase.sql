-- 찬찬배틀 경쟁전: run this once in Supabase → SQL Editor → New query → Run.
-- Accounts are Supabase Auth users (nickname + password); rank lives in `profiles`;
-- `ranked_rooms` is the matchmaking board (hosts list their P2P room code there).

-- ── profiles: one row per account ──
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  nickname text unique not null check (char_length(nickname) between 1 and 12),
  division int not null default 0,     -- 0 = 스톤 1 … 15 = 챌린저 2 (챔피언 = top 5 at 챌린저 2)
  points int not null default 0,       -- 0..99, 100 promotes (keeps counting at 챌린저 2 for the leaderboard)
  wins int not null default 0,
  losses int not null default 0,
  last_result_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select using (true);
-- no insert/update policies: rows are created by the trigger and changed only by report_result()

-- create the profile when an account signs up (nickname comes from the sign-up metadata)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nickname) values (new.id, new.raw_user_meta_data->>'nickname');
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- match result: win ≈ +30 (25..35), loss ≈ -25 (20..30), 100 points per division step.
-- At most one result per 60 s so it can't be spammed.
create or replace function public.report_result(win boolean) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
  delta int;
begin
  select * into p from public.profiles where id = auth.uid() for update;
  if not found then raise exception 'no profile'; end if;
  if p.last_result_at is not null and now() - p.last_result_at < interval '60 seconds' then return p; end if;
  delta := case when win then 25 + floor(random() * 11)::int else -(20 + floor(random() * 11)::int) end;
  p.points := p.points + delta;
  if win then p.wins := p.wins + 1; else p.losses := p.losses + 1; end if;
  while p.points >= 100 and p.division < 15 loop
    p.points := p.points - 100; p.division := p.division + 1;
  end loop;
  while p.points < 0 loop
    if p.division > 0 then p.division := p.division - 1; p.points := p.points + 100;
    else p.points := 0; end if;
  end loop;
  update public.profiles set points = p.points, division = p.division, wins = p.wins, losses = p.losses,
    last_result_at = now() where id = p.id;
  return p;
end $$;
grant execute on function public.report_result(boolean) to authenticated;

-- ── ranked_rooms: open ranked lobbies (the host's P2P room code + the host's division) ──
create table if not exists public.ranked_rooms (
  code text primary key,
  host_id uuid not null references auth.users on delete cascade,
  host_division int not null,
  players int not null default 1,
  max_players int not null default 10,
  status text not null default 'open',       -- open | playing
  updated_at timestamptz not null default now()
);
alter table public.ranked_rooms enable row level security;
drop policy if exists "rooms readable" on public.ranked_rooms;
create policy "rooms readable" on public.ranked_rooms for select to authenticated using (true);
drop policy if exists "host inserts" on public.ranked_rooms;
create policy "host inserts" on public.ranked_rooms for insert to authenticated with check (host_id = auth.uid());
drop policy if exists "host updates" on public.ranked_rooms;
create policy "host updates" on public.ranked_rooms for update to authenticated using (host_id = auth.uid());
drop policy if exists "host deletes" on public.ranked_rooms;
create policy "host deletes" on public.ranked_rooms for delete to authenticated using (host_id = auth.uid());
