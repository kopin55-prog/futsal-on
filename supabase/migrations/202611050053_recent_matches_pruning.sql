-- 최근 10경기 보관 정리 (스프린트 03 7-1·7-2 / data-model.md v4.5 7-5 / Q-058 1번, Q-061 1번)
--
-- private.prune_team_matches(팀, 기준 시각): 팀 하나 정리. 지운 일정 수를 돌려준다.
--   - "10경기" = 종료 시각이 지났고 취소되지 않은 일정, 최근 순(종료 시각 → 시작 시각 → id 내림차순,
--     앱의 지난 경기 목록 PastMatches.recent 와 같은 순서). 배치 미확정·투표 없던 경기도 센다.
--   - 끝난 경기가 10개 미만이면 아무것도 지우지 않는다.
--   - 11번째 이전 경기는 (a) closed_out_at 있음 (b) 투표 회차가 있으면 closed 인 것만 지운다.
--     카운트 반영 전(경기 종료 처리 전, 투표 마감 전)에는 절대 지우지 않는다 → 다음 실행 때 다시 본다.
--   - 취소된 일정은 남은 10경기 중 가장 오래된 경기(10번째)보다 종료 시각이 이전이면 함께 지운다
--     (앱 목록도 그 사이의 취소 일정만 보여 준다).
--   - 다가오는·진행 중 일정은 대상이 아니다 (종료 시각이 기준 시각 이후).
--   - 경기 단위로 일정 줄 하나를 지우면 외래 키(같이 삭제)로 딸린 줄이 한 번에 지워진다:
--     참석 응답, 게스트와 게스트 실력 등급, 배치·팀 블록·배치 명단·변경 이력,
--     투표 회차·대상자·참여 표시·득표·수상자, 출석 기록 (7-2).
--   - 남는 것: 시즌 카운트, 월간 출석 수, 팀 월간 경기 수, 참석 투표 참여율, 알림함(이동 대상이 외래 키가 아님).
--     부상 기록(04)의 return_check_sent_for 비움은 부상 표를 만들 때 외래 키(비움)로 건다.
--   - 일정 줄을 잠그고(SKIP LOCKED) 잠근 뒤에 처리 표시·투표 상태를 다시 확인한다.
--     경기 종료 처리·투표 마감 처리와 동시에 돌아도 반영 전 경기를 지우지 않는다.
--
-- private.prune_old_matches(기준 시각): 끝난 경기가 10개 이상인 모든 팀(해체 팀 포함). 하루 1회 예약 작업.
-- private.close_award_polls: 마감 처리한 회차의 팀마다 바로 정리 (투표 마감 직후, 7-5 실행 시점).
--
-- 함수는 앱 사용자와 service_role 이 실행할 수 없다. 예약 작업(pg_cron)과 다른 서버 함수만 부른다.

-- 팀별 끝난 경기 최근 순 찾기용
create index matches_team_ended on public.matches (team_id, ends_at desc, starts_at desc, id desc);

-- ---------------------------------------------------------------------------
-- 팀 하나 정리
-- ---------------------------------------------------------------------------
create function private.prune_team_matches(p_team_id uuid, p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenth record;
  v_match public.matches;
  v_poll_status public.award_poll_status;
  v_count int := 0;
begin
  -- 남길 10경기 중 가장 오래된 경기 (10번째)
  select m.id, m.ends_at, m.starts_at into v_tenth
    from public.matches m
   where m.team_id = p_team_id
     and m.status = 'scheduled'
     and m.ends_at <= p_now
   order by m.ends_at desc, m.starts_at desc, m.id desc
   offset 9
   limit 1;
  if v_tenth.id is null then
    return 0;
  end if;

  for v_match in
    select m.*
      from public.matches m
     where m.team_id = p_team_id
       and (
         (m.status = 'scheduled'
          and (m.ends_at, m.starts_at, m.id) < (v_tenth.ends_at, v_tenth.starts_at, v_tenth.id))
         or (m.status = 'cancelled' and m.ends_at < v_tenth.ends_at)
       )
     order by m.ends_at, m.id
     for update skip locked
  loop
    -- 잠근 뒤 다시 읽은 값으로 판단
    if v_match.status = 'scheduled' then
      -- (a) 경기 종료 처리(출석·카운트 반영) 전이면 남김
      if v_match.closed_out_at is null then
        continue;
      end if;
      -- (b) 투표가 있었다면 마감 처리(1위·카운트 반영) 전이면 남김
      select p.status into v_poll_status
        from public.award_polls p
       where p.match_id = v_match.id
         for update;
      if found and v_poll_status <> 'closed' then
        continue;
      end if;
    end if;

    delete from public.matches m where m.id = v_match.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 예약 작업: 끝난 경기가 10개 이상인 팀 모두. 지운 일정 수를 돌려준다.
-- p_now 는 테스트에서 시각을 당겨 확인할 때만 넘긴다.
-- ---------------------------------------------------------------------------
create function private.prune_old_matches(p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_count int := 0;
begin
  for v_team_id in
    select m.team_id
      from public.matches m
     where m.status = 'scheduled'
       and m.ends_at <= p_now
     group by m.team_id
    having count(*) >= 10
     order by m.team_id
  loop
    v_count := v_count + private.prune_team_matches(v_team_id, p_now);
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 투표 마감 예약 작업 (202611050048) + 마감 직후 그 팀 정리
-- ---------------------------------------------------------------------------
create or replace function private.close_award_polls(p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_poll record;
  v_teams uuid[] := '{}';
  v_team_id uuid;
  v_count int := 0;
begin
  for v_poll in
    select p.match_id, p.team_id
      from public.award_polls p
     where p.status = 'open'
       and p.closes_at <= p_now
     order by p.closes_at, p.match_id
     limit 500
     for update skip locked
  loop
    perform private.close_award_poll(v_poll.match_id);
    if not v_poll.team_id = any (v_teams) then
      v_teams := v_teams || v_poll.team_id;
    end if;
    v_count := v_count + 1;
  end loop;

  -- 최근 10경기 정리 (7-5: 투표 마감 처리 직후). 같은 처리 안이라 방금 마감한 회차도 closed 로 보인다.
  foreach v_team_id in array v_teams loop
    perform private.prune_team_matches(v_team_id, p_now);
  end loop;
  return v_count;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.prune_team_matches(uuid, timestamptz),
  private.prune_old_matches(timestamptz),
  private.close_award_polls(timestamptz)
from public, anon, authenticated, service_role;

-- 예약 작업: 하루 1회 (한국 시간 04:27)
select cron.unschedule(jobid) from cron.job where jobname = 'prune-old-matches';
select cron.schedule(
  'prune-old-matches',
  '27 19 * * *',
  $$select private.prune_old_matches()$$
);
