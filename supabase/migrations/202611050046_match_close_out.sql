-- 경기 종료 처리 예약 작업 (스프린트 03 4-3·4-6 / data-model.md v4.5 6-1·6-2·7-1·7-3·7-4·7-6 /
-- Q-061 6번, Q-075 13·14번, Q-076 1·3번, 11장 18번)
--
-- private.close_out_matches (매분): 종료 시각이 지났고 취소 안 됐고 closed_out_at 이 빈 일정마다 1회, 한 처리 안에서
--   (1) 대상자 정하기 (게스트 제외, 경기 종료 시각에 그 팀 팀원인 사람만 — Q-061 6번)
--       - 확정 배치가 있으면: 배치 명단(팀 블록 + 교체 블록)의 팀원
--       - 확정 배치가 없으면: 경기 종료 시각에 "참석"인 팀원 (대기·불참·미투표 제외, 작성 중 배치는 무시 — Q-076 3번)
--       "경기 종료 시각에 팀원" = 소속 줄이 종료 시각 이전에 시작했고 종료 시각에 끝나지 않았음
--       (처리가 종료 시각보다 조금 늦게 돌아도 기준은 종료 시각).
--   (2) 대상자마다 출석 기록 1줄 + 시즌 출석 +1(시즌 = 경기 시작일 연도) + 월간 출석 +1(월 = 경기 시작일의 1일, 한국 시간)
--   (3) 팀 월간 경기 수 +1 (대상자가 없어도)
--   (4) 대상자가 2명 이상이고 팀이 해체되지 않았으면 투표 열기 (Q-075 13번 (4), 2명 미만이면 출석만)
--       - opens_at = 경기 종료 시각, closes_at = 경기 종료일(한국 시간) 다음날의 팀 투표 설정 시각 (Q-076 1번)
--       - 대상자 복사(출석 기록과 같은 사람), 대상자 전원 두 항목 0표 줄 (6-4)
--       - award_poll_opened 알림: 대상자에게, 조용한 시간이어도 바로(202611050028 예외), 마감 전 알림은 없음 (Q-075 14번)
--   (5) closed_out_at 기록
--   일정 줄을 잠그고(SKIP LOCKED) 처리 표시를 같은 트랜잭션에서 남겨 두 번 세지 않는다.
--   배치 저장(save_lineup)도 일정 줄을 잠그고 종료 전인지 보므로, 종료 직전 저장과 겹쳐도 저장이 끝난 뒤 처리한다.
--
-- 스프린트 02 기간에 끝난 경기 소급 (sprint-03.md 계획): 이 마이그레이션 시점에 이미 끝나 있던 미처리 경기는
--   팀 월간 경기 수만 +1 하고 처리 표시를 남긴다 (출석·투표 없음). 이후 경기부터 위 처리.
--
-- 함수는 앱 사용자와 service_role 이 실행할 수 없다. 예약 작업(pg_cron)과 팀 해체 처리(서버 안)만 부른다.

-- ---------------------------------------------------------------------------
-- 시즌·월 (경기 시작일, 한국 시간)
-- ---------------------------------------------------------------------------
create function private.match_season(p_starts_at timestamptz)
returns int
language sql
stable
set search_path = ''
as $$
  select extract(year from (p_starts_at at time zone 'Asia/Seoul'))::int
$$;

create function private.match_month(p_starts_at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select date_trunc('month', (p_starts_at at time zone 'Asia/Seoul'))::date
$$;

-- 투표 마감(발표) 시각: 경기 종료일(한국 시간) 다음날의 발표 시각
create function private.award_closes_at(p_ends_at timestamptz, p_announce time)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (((p_ends_at at time zone 'Asia/Seoul')::date + 1) + p_announce) at time zone 'Asia/Seoul'
$$;

-- ---------------------------------------------------------------------------
-- 경기 종료 시각의 출석·투표 대상자 (게스트 제외, 종료 시각에 그 팀 팀원)
-- ---------------------------------------------------------------------------
create function private.match_close_out_user_ids(p_match_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with m as (
    select x.id, x.team_id, x.ends_at from public.matches x where x.id = p_match_id
  ),
  confirmed as (
    select l.id from public.lineups l, m
     where l.match_id = m.id and l.status = 'confirmed'
  ),
  candidates as (
    -- 확정 배치가 있으면 배치 명단의 팀원 (교체 포함)
    select s.user_id
      from public.lineup_slots s
     where s.lineup_id = (select id from confirmed)
       and s.user_id is not null
    union
    -- 확정 배치가 없으면 "참석" 응답 팀원 (작성 중 배치는 무시)
    select r.user_id
      from public.attendance_responses r, m
     where r.match_id = m.id
       and r.state = 'attending'
       and not exists (select 1 from confirmed)
  )
  select coalesce(array_agg(c.user_id order by c.user_id), '{}')
    from candidates c, m
   where exists (
     select 1 from public.team_members tm
      where tm.team_id = m.team_id
        and tm.user_id = c.user_id
        and tm.joined_at <= m.ends_at
        and (tm.ended_at is null or tm.ended_at > m.ends_at)
   )
$$;

-- ---------------------------------------------------------------------------
-- 일정 하나 처리 (부르는 쪽이 일정 줄을 잠근 상태)
--   p_open_poll = false 면 출석만 (팀 해체 처리에서 부를 때, 진행 중 투표는 폐기되므로 열지 않는다)
-- ---------------------------------------------------------------------------
create function private.close_out_match(p_match_id uuid, p_open_poll boolean default true)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match public.matches;
  v_season int;
  v_month date;
  v_users uuid[];
  v_dissolved boolean;
  v_announce time;
begin
  select m.* into v_match from public.matches m where m.id = p_match_id;
  if v_match.id is null or v_match.status <> 'scheduled' or v_match.closed_out_at is not null then
    return;
  end if;

  v_season := private.match_season(v_match.starts_at);
  v_month := private.match_month(v_match.starts_at);
  v_users := private.match_close_out_user_ids(v_match.id);

  -- (2) 출석 기록 + 시즌 출석 + 월간 출석
  insert into public.attendance_records (match_id, team_id, user_id, season, recorded_at)
  select v_match.id, v_match.team_id, u, v_season, now()
    from unnest(v_users) as u
  on conflict (match_id, user_id) do nothing;

  insert into public.member_season_stats as s (user_id, team_id, season, attendance_count, updated_at)
  select u, v_match.team_id, v_season, 1, now()
    from unnest(v_users) as u
  on conflict (user_id, team_id, season) do update
    set attendance_count = s.attendance_count + 1,
        updated_at = excluded.updated_at;

  insert into public.monthly_attendance as a (team_id, user_id, month, attendance_count)
  select v_match.team_id, u, v_month, 1
    from unnest(v_users) as u
  on conflict (team_id, user_id, month) do update
    set attendance_count = a.attendance_count + 1;

  -- (3) 팀 월간 경기 수
  insert into public.team_monthly_matches as t (team_id, month, match_count)
  values (v_match.team_id, v_month, 1)
  on conflict (team_id, month) do update
    set match_count = t.match_count + 1;

  -- (4) 투표 열기
  select t.dissolved_at is not null into v_dissolved from public.teams t where t.id = v_match.team_id;
  if p_open_poll and not v_dissolved and cardinality(v_users) >= 2 then
    select s.award_announce_time into v_announce from public.team_settings s where s.team_id = v_match.team_id;

    insert into public.award_polls (match_id, team_id, opens_at, closes_at, status)
    values (v_match.id, v_match.team_id, v_match.ends_at,
            private.award_closes_at(v_match.ends_at, coalesce(v_announce, time '15:00')), 'open');

    insert into public.award_participants (match_id, user_id)
    select v_match.id, u from unnest(v_users) as u;

    insert into public.award_tallies (match_id, category, candidate_id, vote_count)
    select v_match.id, c, u, 0
      from unnest(v_users) as u
     cross join unnest(enum_range(null::public.award_category)) as c;

    perform private.notify('award_poll_opened', v_users, v_match.team_id, 'match', v_match.id, '');
  end if;

  -- (5) 처리 표시
  update public.matches set closed_out_at = now() where id = v_match.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 예약 작업: 종료 시각이 지난 일정 모두. 처리한 일정 수를 돌려준다.
-- p_now 는 테스트에서 시각을 당겨 확인할 때만 넘긴다 (예약 작업은 지금 시각).
-- ---------------------------------------------------------------------------
create function private.close_out_matches(p_now timestamptz default now())
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
       and m.ends_at <= p_now
       and m.closed_out_at is null
     order by m.ends_at, m.id
     limit 500
     for update skip locked
  loop
    perform private.close_out_match(v_match_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create index matches_close_out_pending on public.matches (ends_at)
  where status = 'scheduled' and closed_out_at is null;

-- ---------------------------------------------------------------------------
-- 스프린트 02 기간에 끝난 경기 소급: 팀 월간 경기 수만 +1 (출석·투표 없음, sprint-03.md 계획)
-- ---------------------------------------------------------------------------
with pending as (
  select m.id, m.team_id, private.match_month(m.starts_at) as month
    from public.matches m
   where m.status = 'scheduled'
     and m.ends_at <= now()
     and m.closed_out_at is null
),
counted as (
  insert into public.team_monthly_matches as t (team_id, month, match_count)
  select p.team_id, p.month, count(*)::int from pending p group by p.team_id, p.month
  on conflict (team_id, month) do update
    set match_count = t.match_count + excluded.match_count
  returning 1
)
update public.matches m
   set closed_out_at = now()
  from pending p
 where m.id = p.id;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.match_season(timestamptz),
  private.match_month(timestamptz),
  private.award_closes_at(timestamptz, time),
  private.match_close_out_user_ids(uuid),
  private.close_out_match(uuid, boolean),
  private.close_out_matches(timestamptz)
from public, anon, authenticated, service_role;

-- 예약 작업: 매분 (경기 종료 시각 직후 처리)
select cron.unschedule(jobid) from cron.job where jobname = 'close-out-matches';
select cron.schedule(
  'close-out-matches',
  '* * * * *',
  $$select private.close_out_matches()$$
);
