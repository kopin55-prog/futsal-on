-- 일정·참석 투표·게스트 표 (data-model.md v4.3 4-1 matches, 4-2 attendance_responses, 4-3 match_guests)
-- + 실력 등급에 게스트 칸 (3-4 skill_ratings.guest_id, "user_id·guest_id 중 정확히 하나")
--
-- - 모든 일정 시각은 한국 시간 고정 (Q-027 M-18). 저장은 timestamptz, 계산은 Asia/Seoul.
-- - 읽기: 그 팀 팀원. 쓰기: 서버 함수만 (앱에 insert/update/delete 권한을 주지 않는다).
-- - 게스트 포지션은 관리자만 (Q-017): 팀원용 읽기 권한에서 positions 칸을 뺀다. 관리자용 읽기는
--   게스트 단계(스프린트 02 2단계)의 서버 함수로 준다. 게스트 실력은 skill_ratings(관리자만 읽기)에 둔다.
-- - 일정을 지우면 딸린 참석 응답·게스트·게스트 실력이 같이 지워진다 (최근 10경기 정리 7-5 는 스프린트 03).
-- - (v4.3, Q-072) 미투표 알림 시각 rsvp_reminder_at, 취소 사유 cancel_reason 포함. 미투표 알림 발송은 3단계.
-- - Realtime 등록은 화면 단계에서 판단 (11장 7번: 표 이름 하나씩, 기본 키는 무작위 id 하나).

create type public.match_source as enum ('auto', 'manual');
create type public.match_status as enum ('scheduled', 'cancelled');
create type public.attendance_state as enum ('attending', 'waitlisted', 'declined');

-- ---------------------------------------------------------------------------
-- 4-1. 일정(경기)
-- ---------------------------------------------------------------------------
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  source public.match_source not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  -- 장소 (3-1 과 같은 규칙). 자동 생성은 팀 지정 풋살장 복사, 직접 추가는 선택 입력
  venue_name text
    constraint matches_venue_name_len check (char_length(venue_name) between 1 and 200),
  venue_address text
    constraint matches_venue_address_len check (char_length(venue_address) between 1 and 300),
  venue_lat double precision
    constraint matches_venue_lat_range check (venue_lat between -90 and 90),
  venue_lng double precision
    constraint matches_venue_lng_range check (venue_lng between -180 and 180),
  venue_map_provider public.map_provider,
  venue_map_place_id text
    constraint matches_venue_place_id_len check (char_length(venue_map_place_id) between 1 and 100),
  -- 생성 당시 정원 복사 (비면 정원 없음, M-12)
  capacity int
    constraint matches_capacity_range check (capacity between 1 and 100),
  -- 참석 투표 마감. 자동 생성은 생성 당시 팀 설정, 직접 추가는 일정마다 고름 (Q-072 1번)
  rsvp_deadline_at timestamptz not null,
  -- 미투표 알림 시각 = 마감 - N시간 (Q-072 1번). 비면 알림 없음. 생성 때 이미 지났으면 비움
  rsvp_reminder_at timestamptz,
  status public.match_status not null default 'scheduled',
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles (user_id) on delete set null,
  -- 취소 사유 1~20자, 이름과 같은 글자 정리 (Q-072 5번). 정리·글자 수 검사는 취소 서버 함수가 한다
  cancel_reason text
    constraint matches_cancel_reason_valid check (cancel_reason is null or private.is_valid_single_line_name(cancel_reason, 20)),
  -- 직접 추가한 관리자 (자동 생성은 비움)
  created_by uuid references public.profiles (user_id) on delete set null,
  created_at timestamptz not null default now(),
  -- 경기 종료 처리(7-1) 완료 시각, 참석 투표 참여율 반영(7-7) 완료 시각. 서버만 씀
  closed_out_at timestamptz,
  attendance_closed_out_at timestamptz,

  -- 종료는 시작보다 늦고, 하루를 넘지 않는다 (입력은 날짜 + 시작·종료 시각, 자정 넘김 허용)
  constraint matches_ends_after_start check (ends_at > starts_at and ends_at <= starts_at + interval '24 hours'),
  -- 마감은 시작 이전 (마감이 이미 지난 직접 추가 일정은 마감 = 시작, Q-071 2번)
  constraint matches_deadline_before_start check (rsvp_deadline_at <= starts_at),
  constraint matches_reminder_before_deadline check (rsvp_reminder_at < rsvp_deadline_at),
  constraint matches_cancelled_consistent check (
    (status = 'cancelled') = (cancelled_at is not null)
    and (status = 'cancelled' or (cancelled_by is null and cancel_reason is null))
  ),
  constraint matches_auto_has_no_creator check (source = 'manual' or created_by is null),
  constraint matches_place_id_needs_provider check (venue_map_place_id is null or venue_map_provider is not null),
  constraint matches_lat_lng_pair check ((venue_lat is null) = (venue_lng is null)),
  -- 게스트 표가 같은 팀의 일정만 가리키도록 (복합 외래 키 대상)
  constraint matches_id_team_key unique (id, team_id)
);

-- 같은 팀·같은 시작 시각의 자동 일정은 한 번만 (취소된 것 포함 → 취소된 자동 일정은 다시 생기지 않음)
create unique index matches_auto_once on public.matches (team_id, starts_at) where source = 'auto';
create index matches_team_starts on public.matches (team_id, starts_at);
create index matches_cancelled_by on public.matches (cancelled_by) where cancelled_by is not null;
create index matches_created_by on public.matches (created_by) where created_by is not null;

revoke all on table public.matches from anon, authenticated, public;
alter table public.matches enable row level security;
grant select on table public.matches to authenticated;

create policy matches_select_member on public.matches
  for select to authenticated
  using (private.is_team_member(team_id));

-- 권한 규칙 전용: 그 일정의 팀에 호출자가 지금 소속돼 있는지 (해체된 팀은 거짓)
create function private.is_match_team_member(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.matches m
     where m.id = p_match_id
       and private.is_team_member(m.team_id)
  )
$$;

-- ---------------------------------------------------------------------------
-- 4-2. 참석 투표 (줄이 없으면 "미투표")
-- ---------------------------------------------------------------------------
create table public.attendance_responses (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  state public.attendance_state not null,
  -- 대기 순번 기준 (먼저 누른 순)
  waitlisted_at timestamptz,
  -- 대기에서 참석으로 자동 전환된 시각
  promoted_at timestamptz,
  responded_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_responses_one_per_user unique (match_id, user_id),
  constraint attendance_responses_waitlist_order check (state <> 'waitlisted' or waitlisted_at is not null)
);

create index attendance_responses_user on public.attendance_responses (user_id);

revoke all on table public.attendance_responses from anon, authenticated, public;
alter table public.attendance_responses enable row level security;
grant select on table public.attendance_responses to authenticated;

create policy attendance_responses_select_member on public.attendance_responses
  for select to authenticated
  using (private.is_match_team_member(match_id));

-- ---------------------------------------------------------------------------
-- 4-3. 게스트 (정원과 별도, 매번 새로 입력 M-19)
-- ---------------------------------------------------------------------------
create table public.match_guests (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null,
  team_id uuid not null references public.teams (id) on delete cascade,
  -- 팀에서 쓸 이름과 같은 규칙 (1~8자, Q-034, Q-048). 글자 정리는 서버 함수가 저장 전에 한다
  name text not null
    constraint match_guests_name_valid check (private.is_valid_single_line_name(name, 8)),
  -- 선택, 최대 3개, 중복 없음
  positions public.play_position[]
    constraint match_guests_positions_valid check (
      positions is null
      or (cardinality(positions) between 1 and 3 and private.positions_are_distinct(positions))
    ),
  added_by uuid references public.profiles (user_id) on delete set null,
  created_at timestamptz not null default now(),
  constraint match_guests_match_fk foreign key (match_id, team_id)
    references public.matches (id, team_id) on delete cascade,
  -- 게스트 실력(skill_ratings)이 같은 팀의 게스트만 가리키도록
  constraint match_guests_id_team_key unique (id, team_id)
);

create index match_guests_match on public.match_guests (match_id);
create index match_guests_added_by on public.match_guests (added_by) where added_by is not null;

revoke all on table public.match_guests from anon, authenticated, public;
alter table public.match_guests enable row level security;
-- 팀원 전체가 읽는 칸 (배치 화면용 이름). positions 는 빼서 관리자도 표로는 못 읽는다 (Q-017)
grant select (id, match_id, team_id, name, added_by, created_at) on table public.match_guests to authenticated;

create policy match_guests_select_member on public.match_guests
  for select to authenticated
  using (private.is_team_member(team_id));

-- ---------------------------------------------------------------------------
-- 3-4. 실력 등급: 게스트 칸 (202611050010 의 임시 검사를 "정확히 하나"로 바꾼다)
-- ---------------------------------------------------------------------------
alter table public.skill_ratings add column guest_id uuid;
alter table public.skill_ratings
  add constraint skill_ratings_guest_fk foreign key (guest_id, team_id)
    references public.match_guests (id, team_id) on delete cascade;
alter table public.skill_ratings drop constraint skill_ratings_subject_present;
alter table public.skill_ratings
  add constraint skill_ratings_one_subject check (num_nonnulls(user_id, guest_id) = 1);
create unique index skill_ratings_guest_key on public.skill_ratings (guest_id) where guest_id is not null;

revoke execute on all functions in schema private from public, anon;
grant execute on function private.is_match_team_member(uuid) to authenticated;
