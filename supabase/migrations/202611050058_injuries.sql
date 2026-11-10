-- 부상 기록·부상 변경 이력 표 (스프린트 04 1-1 / data-model.md v4.5 8-2 injuries, 8-3 injury_events, 2-5, 7-5, 11장 14번, S-07)
--
-- injuries
--   - 한 사람당 진행 중(active) 부상 1건: 부분 고유 조건.
--   - 메모: 11장 14번 (앞뒤 공백·줄바꿈·제어 문자 없음, 코드 포인트 160(20자 × 8) 이하). 저장 전 앞뒤 공백을 지우고
--     비면 없음(null) — 자기소개(profiles.bio)와 같은 규칙. 보이는 글자 20자는 앱이 센다.
--   - status 와 recovered_at 은 함께 움직인다 (recovered 이면 회복 시각 있음, active 이면 없음).
--   - 사람 칸은 회원 탈퇴 시 같이 삭제 (2-5). return_check_sent_for 는 일정 삭제(최근 10경기 정리 포함) 시 비움 (7-5).
--   - 팀과 무관한 사람 기준 기록이라 팀 칸이 없다. 팀 탈퇴·내보내기·해체에도 그대로 남는다 (3-8, Q-058 6번).
-- injury_events
--   - 부상 줄 삭제 시 같이 삭제. weeks_added 는 연장(extended) 줄에만 있다.
--
-- 읽기 (1차)
--   - 본인: 자기 부상 전부(진행 중·지난 것), 자기 이력.
--   - 지금 같은 팀(해체 안 됨)에 함께 소속된 사람: 진행 중인 부상만(메모 포함), 그리고 주인의 부상 동의가 유효할 때만
--     (S-07). 동의 기록은 본인만 읽으므로 확인은 SECURITY DEFINER 확인 함수(private.has_valid_injury_consent)로 한다.
--   - 이력은 본인만. 다른 팀·비로그인은 0건.
-- 쓰기: 앱 직접 쓰기 없음. 등록·연장·회복·동의 철회 삭제는 서버 함수로만 (1-2, 1-3).
-- Realtime 게시에는 등록하지 않는다.

create type public.injury_status as enum ('active', 'recovered');
create type public.injury_event_kind as enum ('reported', 'extended', 'recovered');
create type public.injury_event_via as enum ('self', 'return_vote', 'return_check');

-- ---------------------------------------------------------------------------
-- 8-2. 부상 기록
-- ---------------------------------------------------------------------------
create table public.injuries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  -- 등록일 (한국 날짜)
  started_on date not null,
  -- 예상 복귀일. "남은 W"는 화면에서 계산 (저장 안 함)
  expected_return_on date not null,
  -- 20자 이내(보이는 글자, 앱이 셈), 한 줄
  memo text
    constraint injuries_memo_valid check (memo is null or private.is_valid_single_line_text(memo, 20)),
  status public.injury_status not null default 'active',
  recovered_at timestamptz,
  -- 복귀 확인 알림을 보낸 마지막 일정. 일정 삭제 시 비움 (7-5)
  return_check_sent_for uuid references public.matches (id) on delete set null,
  constraint injuries_return_after_start check (expected_return_on >= started_on),
  constraint injuries_recovered_at_matches_status check (
    (status = 'recovered') = (recovered_at is not null)
  )
);

create index injuries_user_idx on public.injuries (user_id);
create index injuries_return_check_sent_for_idx on public.injuries (return_check_sent_for)
  where return_check_sent_for is not null;
-- 한 사람당 진행 중 부상은 1건
create unique index injuries_one_active_per_user on public.injuries (user_id) where status = 'active';

-- 저장 전 정리: 메모 앞뒤 공백 제거, 빈 값은 없음. id·user_id·started_on 은 바꾸지 못한다.
create function private.injuries_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.memo is not null then
    new.memo := nullif(private.normalize_input(new.memo), '');
  end if;
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.user_id := old.user_id;
    new.started_on := old.started_on;
  end if;
  return new;
end;
$$;

create trigger injuries_before_write
before insert or update on public.injuries
for each row execute function private.injuries_before_write();

-- ---------------------------------------------------------------------------
-- 8-3. 부상 변경 이력
-- ---------------------------------------------------------------------------
create table public.injury_events (
  id uuid primary key default gen_random_uuid(),
  injury_id uuid not null references public.injuries (id) on delete cascade,
  kind public.injury_event_kind not null,
  -- 연장한 주 수 (연장 줄에만)
  weeks_added int
    constraint injury_events_weeks_positive check (weeks_added is null or weeks_added > 0),
  via public.injury_event_via not null,
  at timestamptz not null default now(),
  constraint injury_events_weeks_only_extended check ((kind = 'extended') = (weeks_added is not null))
);

create index injury_events_injury_idx on public.injury_events (injury_id);

-- ---------------------------------------------------------------------------
-- S-07 확인 함수: p_user_id 에게 유효한(철회 안 된) 부상 동의가 있는가.
-- 권한 규칙 전용. API 에 노출되지 않는 private 스키마에만 둔다.
-- ---------------------------------------------------------------------------
create function private.has_valid_injury_consent(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.user_consents c
     where c.user_id = p_user_id
       and c.consent_type = 'injury_info'
       and c.withdrawn_at is null
  )
$$;

-- ---------------------------------------------------------------------------
-- 권한
-- ---------------------------------------------------------------------------
revoke all on table public.injuries, public.injury_events from anon, authenticated, public;

alter table public.injuries enable row level security;
alter table public.injury_events enable row level security;

grant select on table public.injuries, public.injury_events to authenticated;

-- 본인: 전부
create policy injuries_select_self on public.injuries
  for select to authenticated
  using (user_id = (select auth.uid()));

-- 지금 같은 팀 팀원: 진행 중인 것만 + 주인의 부상 동의가 유효할 때만 (8-2, S-07)
create policy injuries_select_teammate on public.injuries
  for select to authenticated
  using (
    status = 'active'
    and private.is_active_teammate(user_id)
    and private.has_valid_injury_consent(user_id)
  );

-- 이력: 본인 부상의 이력만
create policy injury_events_select_self on public.injury_events
  for select to authenticated
  using (
    exists (
      select 1 from public.injuries i
       where i.id = injury_id
         and i.user_id = (select auth.uid())
    )
  );

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.injuries_before_write() from authenticated;
grant execute on function private.has_valid_injury_consent(uuid) to authenticated;
