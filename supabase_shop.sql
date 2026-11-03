-- 찬찬배틀 상점: 찬크레딧, 노이펙트 상자, A-K 스킨, 퀘스트. Run once after supabase.sql (SQL Editor → Run).
-- Everything that changes credits or skins runs here on the server, so the game can't fake it.

alter table public.profiles
  add column if not exists credits int not null default 0,
  add column if not exists equipped_skin text not null default 'default',
  add column if not exists day date,                                   -- KST day the counters below belong to
  add column if not exists ranked_today int not null default 0,
  add column if not exists ranked_wins_today int not null default 0,
  add column if not exists claimed text[] not null default '{}',       -- rewards already taken today
  add column if not exists play_started_at timestamptz;                -- first time online today

create table if not exists public.skins_owned (
  id bigserial primary key,
  user_id uuid not null references auth.users on delete cascade,
  skin text not null,
  created_at timestamptz not null default now()
);
alter table public.skins_owned enable row level security;
drop policy if exists "own skins readable" on public.skins_owned;
create policy "own skins readable" on public.skins_owned for select to authenticated using (user_id = auth.uid());

-- the profile row for this account, with the daily counters reset at KST midnight
create or replace function public._my_profile() returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
  today date := (now() at time zone 'Asia/Seoul')::date;
begin
  select * into p from public.profiles where id = auth.uid() for update;
  if not found then raise exception 'no profile'; end if;
  if p.day is distinct from today then
    update public.profiles set day = today, ranked_today = 0, ranked_wins_today = 0, claimed = '{}', play_started_at = null
      where id = p.id returning * into p;
  end if;
  return p;
end $$;
revoke execute on function public._my_profile() from public, anon, authenticated;

-- ranked result (same scoring as before) + today's counters for the quests
create or replace function public.report_result(win boolean) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
  delta int;
begin
  p := public._my_profile();
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
  update public.profiles set points = p.points, division = p.division, wins = p.wins, losses = p.losses, last_result_at = now(),
    ranked_today = ranked_today + 1, ranked_wins_today = ranked_wins_today + (case when win then 1 else 0 end)
    where id = p.id returning * into p;
  return p;
end $$;

-- today's status for the shop screen (also starts the 10-minute playtime clock)
create or replace function public.shop_status() returns public.profiles
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  p := public._my_profile();
  if p.play_started_at is null then
    update public.profiles set play_started_at = now() where id = p.id returning * into p;
  end if;
  return p;
end $$;

-- daily rewards, 20 찬크레딧 each, once per KST day:
--   playtime: online 10 minutes today · ranked3: 3 ranked games today · win1: 1 ranked win today
create or replace function public.claim_reward(kind text) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  p := public._my_profile();
  if kind = any(p.claimed) then raise exception '오늘은 이미 받았어요'; end if;
  if kind = 'playtime' then
    if p.play_started_at is null or now() - p.play_started_at < interval '10 minutes' then raise exception '아직 10분이 안 됐어요'; end if;
  elsif kind = 'ranked3' then
    if p.ranked_today < 3 then raise exception '경쟁전 3판을 아직 안 했어요'; end if;
  elsif kind = 'win1' then
    if p.ranked_wins_today < 1 then raise exception '경쟁전에서 아직 못 이겼어요'; end if;
  else
    raise exception 'unknown reward';
  end if;
  update public.profiles set credits = credits + 20, claimed = array_append(claimed, kind) where id = p.id returning * into p;
  return p;
end $$;

-- 노이펙트 상자: 30 찬크레딧. 블루젬 0.3% · 레드젬 2.7% · 그린그린 12% · 일반 3종 85% (28.33% each)
create or replace function public.open_case() returns json
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
  r double precision := random() * 100;
  s text;
begin
  p := public._my_profile();
  if p.credits < 30 then raise exception '찬크레딧이 부족해요'; end if;
  s := case
    when r < 0.3 then 'bluegem'
    when r < 3 then 'redgem'
    when r < 15 then 'greengreen'
    when r < 43.333 then 'orange'
    when r < 71.667 then 'navy'
    else 'pink' end;
  update public.profiles set credits = credits - 30 where id = p.id;
  insert into public.skins_owned (user_id, skin) values (p.id, s);
  return json_build_object('skin', s, 'credits', p.credits - 30);
end $$;

-- equip an A-K skin you own ('default' is always allowed)
create or replace function public.equip_skin(skin text) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  p := public._my_profile();
  if skin <> 'default' and not exists (select 1 from public.skins_owned where user_id = p.id and skins_owned.skin = equip_skin.skin) then
    raise exception '갖고 있지 않은 스킨이에요';
  end if;
  update public.profiles set equipped_skin = skin where id = p.id returning * into p;
  return p;
end $$;

grant execute on function public.report_result(boolean), public.shop_status(), public.claim_reward(text),
  public.open_case(), public.equip_skin(text) to authenticated;

-- 관리자 충전 (SQL Editor에서만): select public.admin_give_credits('닉네임', 100);
create or replace function public.admin_give_credits(nick text, amount int) returns int
language sql security definer set search_path = public as $$
  update public.profiles set credits = credits + amount where nickname = nick returning credits;
$$;
revoke execute on function public.admin_give_credits(text, int) from public, anon, authenticated;

-- ── 카람빗 (확정 상품, 50 찬크레딧) + 슈퍼 계정 ──
-- super = owns every skin/knife, now and later
alter table public.profiles add column if not exists super boolean not null default false;

create or replace function public.buy_item(item text) returns json
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
  price int := case item when 'karambit' then 50 else null end;
begin
  p := public._my_profile();
  if price is null then raise exception '없는 상품이에요'; end if;
  if p.super or exists (select 1 from public.skins_owned where user_id = p.id and skin = 'knife_' || item) then
    raise exception '이미 갖고 있어요';
  end if;
  if p.credits < price then raise exception '찬크레딧이 부족해요'; end if;
  update public.profiles set credits = credits - price where id = p.id;
  insert into public.skins_owned (user_id, skin) values (p.id, 'knife_' || item);
  return json_build_object('item', item, 'credits', p.credits - price);
end $$;
grant execute on function public.buy_item(text) to authenticated;

create or replace function public.equip_skin(skin text) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  p := public._my_profile();
  if skin <> 'default' and not p.super and not exists (select 1 from public.skins_owned where user_id = p.id and skins_owned.skin = equip_skin.skin) then
    raise exception '갖고 있지 않은 스킨이에요';
  end if;
  update public.profiles set equipped_skin = skin where id = p.id returning * into p;
  return p;
end $$;

-- make an account super (SQL Editor): update public.profiles set super = true, credits = greatest(credits, 999999) where nickname = '닉네임';
