-- 투표 마감(= 결과 발표) 예약 작업 (스프린트 03 4-5·4-6 / data-model.md v4.5 6-1·6-5·7-3 / Q-076 1·2번, Q-038)
--
-- private.close_award_polls (매분): 마감 시각이 지난 open 회차마다 1회, 한 처리 안에서
--   (1) 항목별 최다 득표자 1위 줄 (동점은 모두, 0표뿐이면 줄 없음 = "결과 없음")
--       시즌 = 경기 시작일 연도 (한국 시간)
--   (2) 1위마다 시즌 카운트 해당 항목 +1 (팀을 떠난 사람도 +1, 본인 기록)
--       회원 탈퇴한 사람은 득표 줄이 이미 지워져 1위가 될 수 없다 (재계산 없음, Q-038)
--   (3) status = closed
--   (4) award_results_announced 알림: 대상자 중 지금 그 팀 팀원에게 (떠난 사람은 그 팀 화면에 못 들어오므로 제외)
--       조용한 시간 규칙은 일반 알림과 같다 (발표 시각이 00:00~08:00 이면 푸시는 13:00, 알림함은 바로).
--   회차 줄을 배타 잠금(SKIP LOCKED)으로 잡고 같은 처리 안에서 closed 로 바꿔 두 번 세지 않는다.
--   투표 함수는 회차 줄을 공유 잠금으로 잡으므로, 진행 중인 투표가 끝난 뒤에 마감한다.
--   최근 10경기 정리(7-5) 호출은 7단계에서 이 처리 뒤에 붙인다.
--
-- 함수는 앱 사용자와 service_role 이 실행할 수 없다. 예약 작업(pg_cron)만 부른다.

-- ---------------------------------------------------------------------------
-- 회차 하나 마감 (부르는 쪽이 회차 줄을 잠근 상태)
-- ---------------------------------------------------------------------------
create function private.close_award_poll(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_poll public.award_polls;
  v_season int;
  v_recipients uuid[];
begin
  select p.* into v_poll from public.award_polls p where p.match_id = p_match_id;
  if v_poll.match_id is null or v_poll.status <> 'open' then
    return;
  end if;
  select private.match_season(m.starts_at) into v_season from public.matches m where m.id = p_match_id;

  -- (1) 1위 줄 (항목마다 최다 득표, 0표는 제외)
  insert into public.award_winners (match_id, team_id, category, user_id, season)
  select t.match_id, v_poll.team_id, t.category, t.candidate_id, v_season
    from public.award_tallies t
   where t.match_id = p_match_id
     and t.vote_count > 0
     and t.vote_count = (select max(t2.vote_count) from public.award_tallies t2
                          where t2.match_id = t.match_id and t2.category = t.category)
  on conflict do nothing;

  -- (2) 수상 카운트
  insert into public.member_season_stats as s (user_id, team_id, season, pom_count, goal_of_the_day_count, updated_at)
  select w.user_id, v_poll.team_id, v_season,
         count(*) filter (where w.category = 'pom')::int,
         count(*) filter (where w.category = 'goal_of_the_day')::int,
         now()
    from public.award_winners w
   where w.match_id = p_match_id
   group by w.user_id
  on conflict (user_id, team_id, season) do update
    set pom_count = s.pom_count + excluded.pom_count,
        goal_of_the_day_count = s.goal_of_the_day_count + excluded.goal_of_the_day_count,
        updated_at = excluded.updated_at;

  -- (3) 마감
  update public.award_polls set status = 'closed' where match_id = p_match_id;

  -- (4) 결과 발표 알림
  select coalesce(array_agg(a.user_id), '{}') into v_recipients
    from public.award_participants a
    join public.team_members tm
      on tm.team_id = v_poll.team_id and tm.user_id = a.user_id and tm.status = 'active'
   where a.match_id = p_match_id;
  perform private.notify('award_results_announced', v_recipients, v_poll.team_id, 'match', p_match_id, '');
end;
$$;

-- ---------------------------------------------------------------------------
-- 예약 작업: 마감 시각이 지난 open 회차 모두. 처리한 회차 수를 돌려준다.
-- p_now 는 테스트에서 시각을 당겨 확인할 때만 넘긴다.
-- ---------------------------------------------------------------------------
create function private.close_award_polls(p_now timestamptz default now())
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
    select p.match_id
      from public.award_polls p
     where p.status = 'open'
       and p.closes_at <= p_now
     order by p.closes_at, p.match_id
     limit 500
     for update skip locked
  loop
    perform private.close_award_poll(v_match_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.close_award_poll(uuid),
  private.close_award_polls(timestamptz)
from public, anon, authenticated, service_role;

select cron.unschedule(jobid) from cron.job where jobname = 'close-award-polls';
select cron.schedule(
  'close-award-polls',
  '* * * * *',
  $$select private.close_award_polls()$$
);
