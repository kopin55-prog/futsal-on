-- 계정·프로필 표 (data-model.md 2-2 profiles, 2-3 profile_play_prefs, 2-4 device_tokens, 8-1 user_consents)
--
-- 사람을 가리키는 칸은 모두 profiles.user_id 를 가리키고, profiles 는 auth.users 를 같이 삭제로 가리킨다 (2-5).
-- "같은 팀 사람" 읽기 규칙은 팀 표가 생긴 뒤(202611050003)에 추가한다.

-- ---------------------------------------------------------------------------
-- 선택 값
-- ---------------------------------------------------------------------------
create type public.play_position as enum ('goalkeeper', 'defender', 'midfielder', 'winger', 'forward');
create type public.consent_type as enum ('terms', 'privacy', 'injury_info');
create type public.device_platform as enum ('android', 'ios');

-- ---------------------------------------------------------------------------
-- 2-2. 프로필
-- ---------------------------------------------------------------------------
create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- 팀에서 쓸 이름: 1~8자(보이는 글자, 앱이 셈), 한 줄, 보이지 않는 문자 없음 (Q-011, Q-012, Q-034, Q-048)
  display_name text not null
    constraint profiles_display_name_valid check (private.is_valid_single_line_name(display_name, 8)),
  -- 한줄 자기소개: 20자 이내, 줄바꿈 불가
  bio text
    constraint profiles_bio_valid check (bio is null or private.is_valid_single_line_text(bio, 20)),
  -- 만 14세 이상 확인 시각 (Q-023). 서버 시계, 수정 불가
  age_14_confirmed_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 저장 전 정리 (앱과 같은 규칙, 11장 14번): 이름은 한 줄 이름 정리, 자기소개는 앞뒤 공백 제거·빈 값은 null.
-- 정리 결과가 검사에 어긋나면 위 check 가 거절한다.
create function private.profiles_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.display_name := private.normalize_single_line_name(new.display_name);
  if new.bio is not null then
    new.bio := nullif(private.normalize_input(new.bio), '');
  end if;
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.user_id := old.user_id;
    new.age_14_confirmed_at := old.age_14_confirmed_at;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_before_write
before insert or update on public.profiles
for each row execute function private.profiles_before_write();

-- ---------------------------------------------------------------------------
-- 2-3. 선호 포지션·전문 골키퍼
-- ---------------------------------------------------------------------------
create function private.positions_are_distinct(p_positions public.play_position[])
returns boolean
language sql immutable strict parallel safe set search_path = ''
as $$ select cardinality(p_positions) = (select count(distinct x) from unnest(p_positions) as x) $$;

create table public.profile_play_prefs (
  user_id uuid primary key references public.profiles (user_id) on delete cascade,
  -- 골키퍼 포함 1~3개, 중복 없음 (Q-035)
  positions public.play_position[] not null
    constraint profile_play_prefs_positions_count check (cardinality(positions) between 1 and 3)
    constraint profile_play_prefs_positions_no_null check (array_position(positions, null) is null)
    constraint profile_play_prefs_positions_unique check (private.positions_are_distinct(positions)),
  is_dedicated_gk boolean not null default false,
  updated_at timestamptz not null default now(),
  -- 전문 골키퍼이면 골키퍼 포함 (Q-019)
  constraint profile_play_prefs_dedicated_gk check (
    not is_dedicated_gk or 'goalkeeper'::public.play_position = any (positions)
  )
);

create function private.profile_play_prefs_before_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.user_id := old.user_id;
  new.updated_at := now();
  return new;
end;
$$;

create trigger profile_play_prefs_before_update
before update on public.profile_play_prefs
for each row execute function private.profile_play_prefs_before_update();

-- ---------------------------------------------------------------------------
-- 8-1. 동의 기록
-- ---------------------------------------------------------------------------
create table public.user_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  consent_type public.consent_type not null,
  consent_version text not null
    constraint user_consents_version_format check (consent_version ~ '^[a-z_]+-[0-9A-Za-z.-]{1,40}$'),
  agreed_at timestamptz not null default now(),
  -- 부상 정보 동의만 철회 가능 (Q-052)
  withdrawn_at timestamptz
    constraint user_consents_withdraw_injury_only check (
      withdrawn_at is null or consent_type = 'injury_info'
    ),
  constraint user_consents_withdrawn_after_agreed check (withdrawn_at is null or withdrawn_at >= agreed_at)
);

create index user_consents_user_idx on public.user_consents (user_id);
-- 유효한(철회 안 된) 부상 동의는 사람당 1줄
create unique index user_consents_one_active_injury
  on public.user_consents (user_id)
  where consent_type = 'injury_info' and withdrawn_at is null;

-- ---------------------------------------------------------------------------
-- 2-4. 기기 알림 주소 (FCM 토큰)
-- ---------------------------------------------------------------------------
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  token text not null unique
    constraint device_tokens_token_format check (char_length(token) between 1 and 4096),
  platform public.device_platform not null,
  updated_at timestamptz not null default now()
);

create index device_tokens_user_idx on public.device_tokens (user_id);

-- ---------------------------------------------------------------------------
-- 권한: 기본 표 권한을 모두 회수하고 필요한 것만 다시 준다 (Supabase 기본은 anon·authenticated 전체 허용)
-- ---------------------------------------------------------------------------
revoke all on table public.profiles, public.profile_play_prefs, public.user_consents, public.device_tokens
  from anon, authenticated, public;

alter table public.profiles enable row level security;
alter table public.profile_play_prefs enable row level security;
alter table public.user_consents enable row level security;
alter table public.device_tokens enable row level security;

-- profiles: 읽기 = 본인 (+ 같은 팀·대기 신청 관리자는 202611050003), 고치기 = 본인, 이름·자기소개만.
-- 만들기는 서버 함수(create_profile)만.
grant select on table public.profiles to authenticated;
grant update (display_name, bio) on table public.profiles to authenticated;

create policy profiles_select_self on public.profiles
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- profile_play_prefs: 읽기 = 본인 (+ 관리자는 202611050003), 고치기 = 본인만 (관리자도 불가).
grant select on table public.profile_play_prefs to authenticated;
grant update (positions, is_dedicated_gk) on table public.profile_play_prefs to authenticated;

create policy profile_play_prefs_select_self on public.profile_play_prefs
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy profile_play_prefs_update_self on public.profile_play_prefs
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- user_consents: 읽기 = 본인만. 쓰기는 서버 함수만.
grant select on table public.user_consents to authenticated;

create policy user_consents_select_self on public.user_consents
  for select to authenticated
  using (user_id = (select auth.uid()));

-- device_tokens: 읽기·삭제(로그아웃) = 본인. 등록은 서버 함수(register_device_token)만.
grant select, delete on table public.device_tokens to authenticated;

create policy device_tokens_select_self on public.device_tokens
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy device_tokens_delete_self on public.device_tokens
  for delete to authenticated
  using (user_id = (select auth.uid()));

revoke execute on all functions in schema private from public, anon;
grant execute on function private.positions_are_distinct(public.play_position[]) to authenticated;
