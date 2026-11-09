-- 기록 표 4개 (스프린트 03 4-1 / data-model.md v4.5 7-1·7-3·7-4·7-6, 승인본 그대로)
--
-- 표
--   attendance_records    경기별 출석 (최근 10경기 범위, 경기 삭제 시 같이 삭제)
--   member_season_stats   (사람, 팀, 시즌) 출석·POM·오늘의 골 1위 횟수 (영구)
--   monthly_attendance    (팀, 사람, 월) 출석 횟수 (영구, 2차 리포트 재료)
--   team_monthly_matches  (팀, 월) 끝난 경기 수 (영구, 2차 리포트 분모)
--
-- 쓰기: 앱 권한 없음. 경기 종료 처리·투표 마감 처리(예약 작업, 202611050046·202611050048)만 쓴다 (11장 18번).
-- 읽기:
--   - 출석 기록, 시즌 카운트: 본인 줄만 (화면 "내 기록" 함수는 스프린트 04).
--   - 월간 출석 수, 팀 월간 경기 수: 1차에는 아무도 직접 못 읽음 (권한 규칙 없음).
-- 숫자는 0 이상. 시즌 = 경기 시작일 연도, 월 = 경기 시작일의 1일 (한국 시간).
-- 회원 탈퇴 시 사람 줄은 같이 삭제 (재계산 없음, Q-038). 팀을 떠나도 줄은 남는다 (3-8).

-- ---------------------------------------------------------------------------
-- 7-1. 출석 기록
-- ---------------------------------------------------------------------------
create table public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  season int not null
    constraint attendance_records_season_range check (season between 2000 and 2999),
  recorded_at timestamptz not null default now(),
  constraint attendance_records_once unique (match_id, user_id)
);

create index attendance_records_user on public.attendance_records (user_id);
create index attendance_records_team on public.attendance_records (team_id);

revoke all on table public.attendance_records from anon, authenticated, public;
alter table public.attendance_records enable row level security;
grant select on table public.attendance_records to authenticated;

create policy attendance_records_select_own on public.attendance_records
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 7-3. 시즌별 출석·수상 카운트
-- ---------------------------------------------------------------------------
create table public.member_season_stats (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  season int not null
    constraint member_season_stats_season_range check (season between 2000 and 2999),
  attendance_count int not null default 0
    constraint member_season_stats_attendance_nonneg check (attendance_count >= 0),
  pom_count int not null default 0
    constraint member_season_stats_pom_nonneg check (pom_count >= 0),
  goal_of_the_day_count int not null default 0
    constraint member_season_stats_goal_nonneg check (goal_of_the_day_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, team_id, season)
);

create index member_season_stats_team on public.member_season_stats (team_id);

revoke all on table public.member_season_stats from anon, authenticated, public;
alter table public.member_season_stats enable row level security;
grant select on table public.member_season_stats to authenticated;

create policy member_season_stats_select_own on public.member_season_stats
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 7-4. 월간 출석 수 (아무도 직접 못 읽음)
-- ---------------------------------------------------------------------------
create table public.monthly_attendance (
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  month date not null
    constraint monthly_attendance_month_first check (extract(day from month) = 1),
  attendance_count int not null default 0
    constraint monthly_attendance_count_nonneg check (attendance_count >= 0),
  primary key (team_id, user_id, month)
);

create index monthly_attendance_user on public.monthly_attendance (user_id);

revoke all on table public.monthly_attendance from anon, authenticated, public;
alter table public.monthly_attendance enable row level security;

-- ---------------------------------------------------------------------------
-- 7-6. 팀별 월간 경기 수 (아무도 직접 못 읽음, 개인 정보 없음)
-- ---------------------------------------------------------------------------
create table public.team_monthly_matches (
  team_id uuid not null references public.teams (id) on delete cascade,
  month date not null
    constraint team_monthly_matches_month_first check (extract(day from month) = 1),
  match_count int not null default 0
    constraint team_monthly_matches_count_nonneg check (match_count >= 0),
  primary key (team_id, month)
);

revoke all on table public.team_monthly_matches from anon, authenticated, public;
alter table public.team_monthly_matches enable row level security;
