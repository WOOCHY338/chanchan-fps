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

-- ── 나만의 스킨 (A-K · 저격총, 100 찬크레딧) ── stored as skin 'custom'; the design itself stays on the player's device
create or replace function public.buy_item(item text) returns json
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
  price int := case item when 'karambit' then 50 when 'custom' then 100 else null end;
  k text := case item when 'custom' then 'custom' else 'knife_' || item end;
begin
  p := public._my_profile();
  if price is null then raise exception '없는 상품이에요'; end if;
  if p.super or exists (select 1 from public.skins_owned where user_id = p.id and skin = k) then
    raise exception '이미 갖고 있어요';
  end if;
  if p.credits < price then raise exception '찬크레딧이 부족해요'; end if;
  update public.profiles set credits = credits - price where id = p.id;
  insert into public.skins_owned (user_id, skin) values (p.id, k);
  return json_build_object('item', item, 'credits', p.credits - price);
end $$;
grant execute on function public.buy_item(text) to authenticated;

-- ── 나만의 스킨 디자인을 계정에 저장 (본인만 읽기 가능) ──
create table if not exists public.custom_skins (
  user_id uuid not null references auth.users on delete cascade,
  gun text not null check (gun in ('rifle', 'sniper')),
  design jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, gun)
);
alter table public.custom_skins enable row level security;
drop policy if exists "own custom skins readable" on public.custom_skins;
create policy "own custom skins readable" on public.custom_skins for select to authenticated using (user_id = auth.uid());

create or replace function public.save_custom_skin(gun text, design jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  p := public._my_profile();
  if not p.super and not exists (select 1 from public.skins_owned where user_id = p.id and skin = 'custom') then
    raise exception '나만의 스킨을 먼저 사야 해요';
  end if;
  if gun not in ('rifle', 'sniper') then raise exception '이 총에는 못 넣어요'; end if;
  if length(design::text) > 1000000 then raise exception '그림이 너무 커요'; end if;
  insert into public.custom_skins (user_id, gun, design, updated_at) values (p.id, save_custom_skin.gun, save_custom_skin.design, now())
    on conflict (user_id, gun) do update set design = excluded.design, updated_at = now();
end $$;
grant execute on function public.save_custom_skin(text, jsonb) to authenticated;

-- 나만의 스킨: 디자인 + 저장 슬롯 2개까지 한 행에 저장하므로 크기 제한 4MB
create or replace function public.save_custom_skin(gun text, design jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  p := public._my_profile();
  if not p.super and not exists (select 1 from public.skins_owned where user_id = p.id and skin = 'custom') then
    raise exception '나만의 스킨을 먼저 사야 해요';
  end if;
  if gun not in ('rifle', 'sniper') then raise exception '이 총에는 못 넣어요'; end if;
  if length(design::text) > 4000000 then raise exception '그림이 너무 커요'; end if;
  insert into public.custom_skins (user_id, gun, design, updated_at) values (p.id, save_custom_skin.gun, save_custom_skin.design, now())
    on conflict (user_id, gun) do update set design = excluded.design, updated_at = now();
end $$;

-- ── 주인 계정 전용 찬크레딧 지급 (게임 상점 화면에서) ──
-- 계정 id로 고정: 닉네임을 따라 해도 못 씀. 다른 사람이 부르면 서버에서 거절.
create or replace function public.owner_give_credits(nick text, amount int) returns json
language plpgsql security definer set search_path = public as $$
declare
  r public.profiles;
begin
  if auth.uid() is distinct from 'b6cb9762-1599-48c7-a940-a074c5e0bf89'::uuid then raise exception '권한이 없어요'; end if;
  if amount is null or amount < 1 or amount > 1000000 then raise exception '1 ~ 1,000,000 사이로 넣어 주세요'; end if;
  update public.profiles set credits = credits + amount where nickname = nick returning * into r;
  if r.id is null then raise exception '그 아이디의 계정이 없어요'; end if;
  return json_build_object('nickname', r.nickname, 'credits', r.credits);
end $$;
revoke execute on function public.owner_give_credits(text, int) from public, anon;
grant execute on function public.owner_give_credits(text, int) to authenticated;
notify pgrst, 'reload schema';

-- ── 노이펙트 카람빗 상자: 50 찬크레딧, A-K 상자와 같은 확률. 카람빗 스킨은 'k_<스킨>'으로 저장 (하나라도 있으면 카람빗 보유) ──
create or replace function public.open_knife_case() returns json
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
  r double precision := random() * 100;
  s text;
begin
  p := public._my_profile();
  if p.credits < 50 then raise exception '찬크레딧이 부족해요'; end if;
  s := case
    when r < 0.3 then 'bluegem'
    when r < 3 then 'redgem'
    when r < 15 then 'greengreen'
    when r < 43.333 then 'orange'
    when r < 71.667 then 'navy'
    else 'pink' end;
  update public.profiles set credits = credits - 50 where id = p.id;
  insert into public.skins_owned (user_id, skin) values (p.id, 'k_' || s);
  return json_build_object('skin', 'k_' || s, 'credits', p.credits - 50);
end $$;
revoke execute on function public.open_knife_case() from public, anon;
grant execute on function public.open_knife_case() to authenticated;
notify pgrst, 'reload schema';
