-- 팀 배치 표 4개 (스프린트 03 1-1 / data-model.md v4.4 5-1~5-4, 승인본 그대로)
--
-- 표
--   lineups             경기당 배치 하나 (draft 작성 중 / confirmed 확정)
--   lineup_squads       배치 안의 팀 블록과 조끼 색 (한 배치 안 조끼 색 중복 불가, 5-2)
--   lineup_slots        누가 어느 팀 블록에 있는지 (squad_id 가 비면 교체 블록, 5-3)
--   lineup_change_logs  확정 후 수정 이력 (바뀌기 전·후 사람 ID 만, 관리자만 읽음, 5-4)
--
-- 읽기 (Q-017, sprint-03 1-1)
--   - 관리자(팀장·운영진)는 항상.
--   - 팀원은 확정된 배치만. 작성 중 배치는 배치 줄·팀 블록·명단 모두 0건.
--   - 변경 이력은 관리자만. 다른 팀·비로그인·해체된 팀은 0건 (공용 확인 함수가 해체된 팀을 거짓으로 본다).
-- 쓰기
--   - 앱에 insert/update/delete 권한을 주지 않는다. 저장·확정·확정 후 수정은 서버 함수(202611050038)로만.
--     (5-1 은 작성 중 배치의 관리자 직접 쓰기를 허용하지만, 명단 자격·시점 검사를 한 곳에 두려고 서버 함수로 모았다.)
-- 그 밖
--   - 실력 등급·점수·합계 칸은 없다 (3-4, Q-075 5번).
--   - lineup_slots.as_goalkeeper 는 승인본 칸이라 만들지만 서버 함수는 항상 false 로 저장한다.
--     GK 표시를 하지 않고(Q-075 6번), 이 칸이 참이면 팀원이 전문 골키퍼 여부(관리자만, Q-017)를 알 수 있기 때문.
--   - 기본 키는 무작위 uuid (11장 11번). 사람 칸은 탈퇴 시 같이 삭제 또는 비움 (11장 13번).
--   - 일정을 지우면 배치와 딸린 줄이 같이 지워진다 (7-2). 게스트를 지우면 그 게스트 명단 줄도 같이 지워진다.
--   - Realtime 미등록 (화면 단계에서 판단).

create type public.lineup_status as enum ('draft', 'confirmed');
create type public.bib_color as enum (
  'red', 'orange', 'yellow', 'green', 'blue', 'navy', 'purple', 'pink', 'black', 'white', 'no_bib'
);

-- 배치 경고 종류 (필수 조건을 못 지켰을 때, 관리자 화면용, 사람 이름·등급 없음)
--   dedicated_gk_over_teams  전문 골키퍼가 팀보다 많아 한 팀에 2명 이상
--   group_split              그룹을 한 팀에 모두 넣지 못함 (그룹 인원 > 팀당 인원 등)
--   rival_same_team          라이벌을 모두 나누지 못함
-- 교체 N명·N명 모자람은 명단에서 바로 셀 수 있어 저장하지 않는다.
create function private.lineup_warnings_valid(p_warnings text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_warnings is null
      or (cardinality(p_warnings) between 1 and 3
          and p_warnings <@ array['dedicated_gk_over_teams', 'group_split', 'rival_same_team']
          and (select count(distinct w) from unnest(p_warnings) w) = cardinality(p_warnings))
$$;

-- ---------------------------------------------------------------------------
-- 5-1. 팀 배치
-- ---------------------------------------------------------------------------
create table public.lineups (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  -- 팀 수 2~11 (조끼 색 11개, Q-075 7번 (4))
  team_count int not null
    constraint lineups_team_count_range check (team_count between 2 and 11),
  players_per_team int not null
    constraint lineups_players_per_team_range check (players_per_team between 1 and 50),
  status public.lineup_status not null default 'draft',
  warnings text[]
    constraint lineups_warnings_valid check (private.lineup_warnings_valid(warnings)),
  -- 처음 확정 정보. 확정한 사람은 탈퇴 시 비움
  confirmed_at timestamptz,
  confirmed_by uuid references public.profiles (user_id) on delete set null,
  -- 확정 후 고칠 때마다 1씩 증가
  version int not null default 1
    constraint lineups_version_positive check (version >= 1),
  updated_at timestamptz not null default now(),
  constraint lineups_one_per_match unique (match_id),
  constraint lineups_confirmed_consistent check (
    (status = 'confirmed') = (confirmed_at is not null)
    and (status = 'confirmed' or confirmed_by is null)
  ),
  -- 작성 중에는 버전이 오르지 않는다
  constraint lineups_draft_version check (status = 'confirmed' or version = 1)
);

create index lineups_confirmed_by on public.lineups (confirmed_by) where confirmed_by is not null;

-- ---------------------------------------------------------------------------
-- 5-2. 팀 블록
-- ---------------------------------------------------------------------------
create table public.lineup_squads (
  id uuid primary key default gen_random_uuid(),
  lineup_id uuid not null references public.lineups (id) on delete cascade,
  squad_no int not null
    constraint lineup_squads_no_range check (squad_no between 1 and 11),
  bib_color public.bib_color not null,
  constraint lineup_squads_no_once unique (lineup_id, squad_no),
  -- 한 배치 안에서 조끼 색 중복 불가 (5-2)
  constraint lineup_squads_color_once unique (lineup_id, bib_color),
  -- 명단 줄이 같은 배치의 팀 블록만 가리키도록 (복합 외래 키 대상)
  constraint lineup_squads_id_lineup_key unique (id, lineup_id)
);

-- ---------------------------------------------------------------------------
-- 5-3. 배치 명단
-- ---------------------------------------------------------------------------
create table public.lineup_slots (
  id uuid primary key default gen_random_uuid(),
  lineup_id uuid not null references public.lineups (id) on delete cascade,
  -- 비어 있으면 교체 블록
  squad_id uuid,
  -- 팀원. 탈퇴 시 같이 삭제
  user_id uuid references public.profiles (user_id) on delete cascade,
  -- 게스트. 게스트 삭제 시 같이 삭제 (같은 일정의 게스트인지는 서버 함수가 확인)
  guest_id uuid references public.match_guests (id) on delete cascade,
  as_goalkeeper boolean not null default false,
  constraint lineup_slots_squad_fk foreign key (squad_id, lineup_id)
    references public.lineup_squads (id, lineup_id) on delete cascade,
  constraint lineup_slots_one_subject check (num_nonnulls(user_id, guest_id) = 1),
  -- 한 배치에 같은 사람은 한 번만
  constraint lineup_slots_user_once unique (lineup_id, user_id),
  constraint lineup_slots_guest_once unique (lineup_id, guest_id)
);

create index lineup_slots_squad on public.lineup_slots (squad_id) where squad_id is not null;
create index lineup_slots_user on public.lineup_slots (user_id) where user_id is not null;
create index lineup_slots_guest on public.lineup_slots (guest_id) where guest_id is not null;

-- ---------------------------------------------------------------------------
-- 5-4. 배치 변경 이력 (서버만 씀)
-- ---------------------------------------------------------------------------
create table public.lineup_change_logs (
  id uuid primary key default gen_random_uuid(),
  lineup_id uuid not null references public.lineups (id) on delete cascade,
  -- 바뀐 뒤 버전
  version int not null
    constraint lineup_change_logs_version_positive check (version >= 2),
  changed_by uuid references public.profiles (user_id) on delete set null,
  changed_at timestamptz not null default now(),
  -- 팀 블록·명단의 사람 ID 만 (이름·등급 없음). 회원 탈퇴 시 그 사람 ID 정리는 7-4 단계
  before jsonb not null,
  after jsonb not null,
  constraint lineup_change_logs_version_once unique (lineup_id, version)
);

create index lineup_change_logs_changed_by on public.lineup_change_logs (changed_by) where changed_by is not null;

-- ---------------------------------------------------------------------------
-- 권한 규칙 전용 확인 함수 (사람은 auth.uid() 로만 판단)
-- ---------------------------------------------------------------------------

-- 그 일정의 팀 관리자인지 (해체된 팀은 거짓)
create function private.is_match_team_staff(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.matches m
     where m.id = p_match_id
       and private.is_team_staff(m.team_id)
  )
$$;

-- 배치를 읽을 수 있는지: 관리자는 항상, 팀원은 확정된 배치만
create function private.can_read_lineup(p_lineup_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.lineups l
      join public.matches m on m.id = l.match_id
     where l.id = p_lineup_id
       and (private.is_team_staff(m.team_id)
            or (l.status = 'confirmed' and private.is_team_member(m.team_id)))
  )
$$;

-- 배치의 팀 관리자인지 (변경 이력 읽기)
create function private.is_lineup_staff(p_lineup_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.lineups l
      join public.matches m on m.id = l.match_id
     where l.id = p_lineup_id
       and private.is_team_staff(m.team_id)
  )
$$;

-- ---------------------------------------------------------------------------
-- 권한 규칙: 읽기만, 쓰기 권한 없음
-- ---------------------------------------------------------------------------
revoke all on table public.lineups from anon, authenticated, public;
revoke all on table public.lineup_squads from anon, authenticated, public;
revoke all on table public.lineup_slots from anon, authenticated, public;
revoke all on table public.lineup_change_logs from anon, authenticated, public;

alter table public.lineups enable row level security;
alter table public.lineup_squads enable row level security;
alter table public.lineup_slots enable row level security;
alter table public.lineup_change_logs enable row level security;

grant select on table public.lineups to authenticated;
grant select on table public.lineup_squads to authenticated;
grant select on table public.lineup_slots to authenticated;
grant select on table public.lineup_change_logs to authenticated;

create policy lineups_select on public.lineups
  for select to authenticated
  using (private.can_read_lineup(id));

create policy lineup_squads_select on public.lineup_squads
  for select to authenticated
  using (private.can_read_lineup(lineup_id));

create policy lineup_slots_select on public.lineup_slots
  for select to authenticated
  using (private.can_read_lineup(lineup_id));

create policy lineup_change_logs_select_staff on public.lineup_change_logs
  for select to authenticated
  using (private.is_lineup_staff(lineup_id));

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.lineup_warnings_valid(text[]) from authenticated, service_role;
grant execute on function
  private.is_match_team_staff(uuid),
  private.can_read_lineup(uuid),
  private.is_lineup_staff(uuid)
to authenticated;
