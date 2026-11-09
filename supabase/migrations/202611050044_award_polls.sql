-- POM·오늘의 골 투표 표 5개 (스프린트 03 4-2 / data-model.md v4.5 6-1~6-5, 승인본 그대로)
--
-- 표
--   award_polls            경기당 투표 회차 하나 (open 진행 중 / closed 마감·결과 확정)
--   award_participants     투표할 수 있고 후보가 될 수 있는 사람 (열릴 때 복사해 고정)
--   award_ballot_receipts  누가 어느 항목에 이미 투표했는지만 (누구를 찍었는지 없음)
--   award_tallies          항목별 후보마다 받은 표 수 (누가 찍었는지 없음)
--   award_winners          마감 후 항목별 1위 (공동 1위는 여러 줄, 표가 없으면 줄 없음)
--
-- "누가 누구를 찍었는지"를 잇는 칸·로그·날짜는 어디에도 없다 (6장 핵심, 11장 12번).
--   - 참여 표시와 득표 집계에는 날짜 칸·updated_at 트리거가 없다 (S-17, security 반영).
--   - 득표 집계는 앱에서 누구도 못 읽는다 (팀장 포함, 권한 규칙 없음). Realtime 미등록.
-- 읽기
--   - 회차·대상자: 그 팀 팀원 (후보 목록, 마감 시각).
--   - 참여 표시: 본인 줄만 ("투표 완료" 표시). 관리자도 다른 사람 것은 0건 → 진행 중 투표 수 비공개.
--   - 수상자: 그 팀 팀원 (마감 처리 때만 생기므로 진행 중 결과 노출 없음).
-- 쓰기: 앱 권한 없음. 투표는 서버 함수(202611050047), 열기·마감은 예약 작업(202611050046·202611050048).
-- 삭제: 일정을 지우면 회차가, 회차를 지우면 딸린 줄이 같이 지워진다 (7-2, 팀 해체 시 진행 중 투표 폐기).
--   사람 칸은 회원 탈퇴 시 같이 삭제 (재계산 없음, Q-038).

create type public.award_poll_status as enum ('open', 'closed');
create type public.award_category as enum ('pom', 'goal_of_the_day');

-- ---------------------------------------------------------------------------
-- 6-1. 투표 회차 (경기당 하나)
-- ---------------------------------------------------------------------------
create table public.award_polls (
  match_id uuid primary key references public.matches (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  status public.award_poll_status not null default 'open',
  constraint award_polls_closes_after_open check (closes_at > opens_at)
);

create index award_polls_team on public.award_polls (team_id);
create index award_polls_open_closes on public.award_polls (closes_at) where status = 'open';

-- ---------------------------------------------------------------------------
-- 6-2. 투표 대상자
-- ---------------------------------------------------------------------------
create table public.award_participants (
  match_id uuid not null references public.award_polls (match_id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  primary key (match_id, user_id)
);

create index award_participants_user on public.award_participants (user_id);

-- ---------------------------------------------------------------------------
-- 6-3. 투표 참여 표시 (항목당 한 사람 한 줄, 날짜 칸 없음)
-- ---------------------------------------------------------------------------
create table public.award_ballot_receipts (
  match_id uuid not null references public.award_polls (match_id) on delete cascade,
  category public.award_category not null,
  voter_id uuid not null references public.profiles (user_id) on delete cascade,
  primary key (match_id, category, voter_id)
);

create index award_ballot_receipts_voter on public.award_ballot_receipts (voter_id);

-- ---------------------------------------------------------------------------
-- 6-4. 득표 집계 (마지막 변경 시각 칸 없음)
-- ---------------------------------------------------------------------------
create table public.award_tallies (
  match_id uuid not null references public.award_polls (match_id) on delete cascade,
  category public.award_category not null,
  candidate_id uuid not null references public.profiles (user_id) on delete cascade,
  vote_count int not null default 0
    constraint award_tallies_vote_count_nonneg check (vote_count >= 0),
  primary key (match_id, category, candidate_id)
);

create index award_tallies_candidate on public.award_tallies (candidate_id);

-- ---------------------------------------------------------------------------
-- 6-5. 수상자 (득표수 칸 없음)
-- ---------------------------------------------------------------------------
create table public.award_winners (
  match_id uuid not null references public.award_polls (match_id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  category public.award_category not null,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  season int not null
    constraint award_winners_season_range check (season between 2000 and 2999),
  primary key (match_id, category, user_id)
);

create index award_winners_user on public.award_winners (user_id);
create index award_winners_team on public.award_winners (team_id);

-- ---------------------------------------------------------------------------
-- 권한 규칙 전용 확인 함수 (사람은 auth.uid() 로만 판단)
-- ---------------------------------------------------------------------------
create function private.is_award_poll_team_member(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.award_polls p
     where p.match_id = p_match_id
       and private.is_team_member(p.team_id)
  )
$$;

-- ---------------------------------------------------------------------------
-- 권한 규칙: 읽기만, 쓰기 권한 없음. 득표 집계는 읽기도 없음.
-- ---------------------------------------------------------------------------
revoke all on table public.award_polls from anon, authenticated, public;
revoke all on table public.award_participants from anon, authenticated, public;
revoke all on table public.award_ballot_receipts from anon, authenticated, public;
revoke all on table public.award_tallies from anon, authenticated, public;
revoke all on table public.award_winners from anon, authenticated, public;

alter table public.award_polls enable row level security;
alter table public.award_participants enable row level security;
alter table public.award_ballot_receipts enable row level security;
alter table public.award_tallies enable row level security;
alter table public.award_winners enable row level security;

grant select on table public.award_polls to authenticated;
grant select on table public.award_participants to authenticated;
grant select on table public.award_ballot_receipts to authenticated;
grant select on table public.award_winners to authenticated;

create policy award_polls_select_member on public.award_polls
  for select to authenticated
  using (private.is_team_member(team_id));

create policy award_participants_select_member on public.award_participants
  for select to authenticated
  using (private.is_award_poll_team_member(match_id));

create policy award_ballot_receipts_select_own on public.award_ballot_receipts
  for select to authenticated
  using (voter_id = (select auth.uid()));

create policy award_winners_select_member on public.award_winners
  for select to authenticated
  using (private.is_team_member(team_id));

revoke execute on all functions in schema private from public, anon;
grant execute on function private.is_award_poll_team_member(uuid) to authenticated;
