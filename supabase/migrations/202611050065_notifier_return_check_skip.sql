-- notifier 건너뛰기 재료 추가: 복귀 확인 알림 받는 사람의 부상·참석 응답 상태 (스프린트 04 2단계, lead 결정 2026-11-10
-- "조용한 시간으로 늦게 나갈 복귀 확인 푸시는 그 사이 회복했으면 건너뜀", 202611050052 와 같은 방식)
--
-- public.claim_push_batch 가 injury_return_check 줄에 한해 아래 2칸도 돌려준다 (다른 종류는 null).
--   recipient_injury_active  받는 사람에게 지금 진행 중 부상이 있는가
--   recipient_rsvp_state     받는 사람의 그 일정 참석 응답 (attending/waitlisted/declined, 응답 없으면 null)
-- notifier(logic.ts): injury_return_check 는 푸시 직전에 진행 중 부상이 없으면(recovered), 그 일정에 이미 참석 투표
-- 응답을 했으면(responded) 푸시만 건너뜀. 알림함 줄은 그대로 남는다. 그 밖의 종류는 202611050052 규칙 그대로.
-- 부상 메모·기간 같은 내용은 돌려주지 않는다(예/아니오와 응답 상태만, 13장 12번). 받는 사람 본인의 상태만 본다.
-- 반환 칸이 바뀌어 함수를 다시 만든다 (본문은 202611050052 + 칸 2개). 실행 권한은 service_role 만 그대로.
-- notifier Edge Function 재배포 필요 (setup_push.ps1).

drop function public.claim_push_batch(int);

create function public.claim_push_batch(p_limit int)
returns table (
  outbox_id uuid,
  notification_id uuid,
  kind text,
  title text,
  body text,
  team_id uuid,
  ref_type text,
  ref_id uuid,
  notified_at timestamptz,
  read_at timestamptz,
  -- 대상이 일정일 때만 (없으면 null)
  match_status text,
  match_starts_at timestamptz,
  match_ends_at timestamptz,
  -- 대상 일정의 POM·오늘의 골 투표 (없으면 null)
  award_poll_status text,
  award_poll_closes_at timestamptz,
  -- 대상 일정의 팀 배치 상태 draft/confirmed (배치가 없으면 null)
  lineup_status text,
  -- injury_return_check 만: 받는 사람의 진행 중 부상 여부 / 그 일정 참석 응답 (다른 종류는 null)
  recipient_injury_active boolean,
  recipient_rsvp_state text,
  -- 받는 사람이 지금 그 팀 소속인가 / 그 팀을 마지막으로 떠난 시각 (소속 이력이 없으면 null)
  recipient_active boolean,
  recipient_left_at timestamptz,
  -- 받는 사람의 모든 기기 토큰 (최근 갱신 순)
  tokens text[]
)
language sql
volatile
security definer
set search_path = ''
as $$
  with picked as (
    select o.id
      from public.notification_outbox o
     where o.status = 'pending'
       and o.send_at <= now()
     order by o.send_at, o.id
     limit least(greatest(coalesce(p_limit, 100), 1), 500)
     for update skip locked
  ),
  claimed as (
    update public.notification_outbox o
       set status = 'failed', sent_at = now()
      from picked p
     where o.id = p.id
    returning o.id, o.notification_id, o.user_id
  )
  select c.id,
         n.id,
         n.kind::text,
         n.title,
         n.body,
         n.team_id,
         n.ref_type,
         n.ref_id,
         n.created_at,
         n.read_at,
         m.status::text,
         m.starts_at,
         m.ends_at,
         ap.status::text,
         ap.closes_at,
         l.status::text,
         case when n.kind = 'injury_return_check' then
           exists (select 1 from public.injuries i where i.user_id = c.user_id and i.status = 'active')
         end,
         case when n.kind = 'injury_return_check' and n.ref_type = 'match' then
           (select ar.state::text from public.attendance_responses ar
             where ar.match_id = n.ref_id and ar.user_id = c.user_id)
         end,
         exists (
           select 1 from public.team_members tm
            where tm.team_id = n.team_id and tm.user_id = c.user_id and tm.status = 'active'
         ),
         (select max(tm.ended_at) from public.team_members tm
           where tm.team_id = n.team_id and tm.user_id = c.user_id),
         coalesce(
           (select array_agg(d.token order by d.updated_at desc, d.id)
              from public.device_tokens d
             where d.user_id = c.user_id),
           '{}'::text[]
         )
    from claimed c
    join public.notifications n on n.id = c.notification_id
    left join public.matches m on n.ref_type = 'match' and m.id = n.ref_id
    left join public.award_polls ap on n.ref_type = 'match' and ap.match_id = n.ref_id
    left join public.lineups l on n.ref_type = 'match' and l.match_id = n.ref_id
$$;

revoke execute on function public.claim_push_batch(int) from public, anon, authenticated;
grant execute on function public.claim_push_batch(int) to service_role;
