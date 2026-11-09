-- 배치 미확정 알림 (스프린트 03 / Q-075 15번, Q-076 2번 / data-model.md v4.5 9장 lineup_unconfirmed)
--
-- 경기 시작 시각에 확정된 배치가 없으면 팀장·운영진에게 1회.
--   - "경기 시작 시각에 1회 도는 처리" = 참여율 처리 private.close_out_attendance_vote (202611050027, 일정마다 1회,
--     attendance_closed_out_at 으로 두 번 돌지 않음). 그 끝에 붙인다. 참여율 계산은 그대로.
--   - 예약 작업이 밀려 경기 종료 뒤에 처리되면 보내지 않는다 (확정할 수 없는 시점).
--   - 받는 사람: 처리 시점의 팀장·운영진 (해체된 팀은 없음). 사건 값 '' → 일정마다 한 번.
--   - 확정하지 않아도 출석·투표는 참석자 기준으로 쌓인다 (Q-076 3번, 202611050046).
--   - 푸시 건너뛰기: notifier 가 이 종류는 "경기 시작함" 대신 "경기 종료됨"으로 건너뛴다 (202611050050).

create or replace function private.close_out_attendance_vote(p_match_id uuid)
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

  -- 배치 미확정 알림 (경기 종료 전일 때만)
  if v_match.status = 'scheduled'
     and now() < v_match.ends_at
     and not exists (select 1 from public.lineups l
                      where l.match_id = v_match.id and l.status = 'confirmed') then
    perform private.notify('lineup_unconfirmed', private.team_staff_ids(v_match.team_id), v_match.team_id,
                           'match', v_match.id, '', null,
                           jsonb_build_object('match_at', v_match.starts_at));
  end if;
end;
$$;

revoke execute on function private.close_out_attendance_vote(uuid)
from public, anon, authenticated, service_role;
