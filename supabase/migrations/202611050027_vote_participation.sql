-- 참석 투표 참여율 (스프린트 02 2-4 / data-model.md 7-7 / Q-062, Q-064 2번, Q-071 14번)
--
-- 표 monthly_vote_participation: (팀, 사람, 월)마다 한 줄, 대상·응답 횟수 2개만 저장 (퍼센트는 보여줄 때 계산).
-- - 앱(anon·authenticated)은 읽기·쓰기 모두 불가. 1차 "내 기록" 함수는 스프린트 04 (7-2).
-- - 팀을 떠나도 남는다. 회원 탈퇴 시 같이 삭제. 숫자는 0 이상, 응답 ≤ 대상.
--
-- 처리 close_out_attendance_votes (예약 작업, 매분):
--   경기 시작 시각이 지났고 취소되지 않았고 아직 처리 안 한(attendance_closed_out_at 없음) 일정마다 1회.
--   - 대상: 경기 시작 시각에 그 팀 팀원이었고 그 소속을 마감 전에 시작한 사람 (팀장·운영진 포함, Q-064 2번).
--     소속 줄(team_members)의 joined_at < 마감 이고, 시작 시각에 끝나지 않았던(ended_at 없음 또는 시작 뒤) 줄.
--     → 마감 전 탈퇴, 마감 뒤·시작 전 탈퇴, 마감 뒤 가입은 대상 아님. 시작 뒤 탈퇴는 대상 (Q-071 14번).
--   - 응답: 그중 마감 전에 참석/불참(대기 포함)을 눌렀거나, 마감 시각에 부상 중 (부상 판단은 private.is_injured_at
--     한 곳, 부상 표가 생기는 스프린트 04 에서 채움. 지금은 항상 아니오).
--     응답 줄은 마감 뒤에 새로 생기지 않지만 기준을 분명히 하려고 responded_at < 마감 도 확인한다.
--   - 월: 경기 시작일의 1일 (한국 시간).
--   - 시작 전에 취소된 일정은 처음부터 세지 않으므로 되돌림이 없다 (Q-064 1번, Q-071 14번 → 2-5 불필요).
--   - 일정 줄을 잠그고(SKIP LOCKED) 처리 완료 표시를 같은 트랜잭션에서 남겨 두 번 세지 않는다.
--   - 앱 사용자와 service_role 은 실행할 수 없다. 예약 작업(pg_cron)만 부른다.

create table public.monthly_vote_participation (
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  month date not null
    constraint monthly_vote_participation_month_first check (extract(day from month) = 1),
  attendance_vote_eligible int not null default 0
    constraint monthly_vote_participation_eligible_nonneg check (attendance_vote_eligible >= 0),
  attendance_vote_responded int not null default 0
    constraint monthly_vote_participation_responded_nonneg check (attendance_vote_responded >= 0),
  constraint monthly_vote_participation_responded_le_eligible
    check (attendance_vote_responded <= attendance_vote_eligible),
  primary key (team_id, user_id, month)
);

create index monthly_vote_participation_user on public.monthly_vote_participation (user_id);

-- 앱은 읽기·쓰기 불가 (규칙이 없는 표 = 아무도 못 읽음, 11장 1번·18번)
revoke all on table public.monthly_vote_participation from anon, authenticated, public;
alter table public.monthly_vote_participation enable row level security;

-- ---------------------------------------------------------------------------
-- 그 시각에 부상 중인가 (참여율 응답 판단의 한 곳). 부상 표(8-2)는 스프린트 04.
-- 04 에서 injuries 를 보도록 이 함수만 바꾼다.
-- ---------------------------------------------------------------------------
create function private.is_injured_at(p_user_id uuid, p_at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

-- ---------------------------------------------------------------------------
-- 일정 하나 처리 (부르는 쪽이 일정 줄을 잠근 상태)
-- ---------------------------------------------------------------------------
create function private.close_out_attendance_vote(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match public.matches;
  v_month date;
begin
  select m.* into v_match from public.matches m where m.id = p_match_id;
  v_month := date_trunc('month', v_match.starts_at at time zone 'Asia/Seoul')::date;

  insert into public.monthly_vote_participation as p
    (team_id, user_id, month, attendance_vote_eligible, attendance_vote_responded)
  select v_match.team_id, e.user_id, v_month, 1,
         case when exists (
                select 1 from public.attendance_responses r
                 where r.match_id = v_match.id
                   and r.user_id = e.user_id
                   and r.responded_at < v_match.rsvp_deadline_at
              )
              or private.is_injured_at(e.user_id, v_match.rsvp_deadline_at)
              then 1 else 0 end
    from (
      select distinct tm.user_id
        from public.team_members tm
       where tm.team_id = v_match.team_id
         and tm.joined_at < v_match.rsvp_deadline_at
         and (tm.ended_at is null or tm.ended_at > v_match.starts_at)
    ) e
  on conflict (team_id, user_id, month) do update
    set attendance_vote_eligible = p.attendance_vote_eligible + excluded.attendance_vote_eligible,
        attendance_vote_responded = p.attendance_vote_responded + excluded.attendance_vote_responded;

  update public.matches set attendance_closed_out_at = now() where id = v_match.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 예약 작업: 시작 시각이 지난 일정 모두. 처리한 일정 수를 돌려준다.
-- p_now 는 테스트에서 시각을 당겨 확인할 때만 넘긴다 (예약 작업은 지금 시각).
-- ---------------------------------------------------------------------------
create function private.close_out_attendance_votes(p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match_id uuid;
  v_count int := 0;
begin
  for v_match_id in
    select m.id
      from public.matches m
     where m.status = 'scheduled'
       and m.starts_at <= p_now
       and m.attendance_closed_out_at is null
     order by m.starts_at, m.id
     limit 500
     for update skip locked
  loop
    perform private.close_out_attendance_vote(v_match_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create index matches_attendance_close_out_pending on public.matches (starts_at)
  where status = 'scheduled' and attendance_closed_out_at is null;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.is_injured_at(uuid, timestamptz),
  private.close_out_attendance_vote(uuid),
  private.close_out_attendance_votes(timestamptz)
from public, anon, authenticated, service_role;

-- 예약 작업: 매분 (경기 시작 시각 직후 처리)
select cron.unschedule(jobid) from cron.job where jobname = 'close-out-attendance-votes';
select cron.schedule(
  'close-out-attendance-votes',
  '* * * * *',
  $$select private.close_out_attendance_votes()$$
);
