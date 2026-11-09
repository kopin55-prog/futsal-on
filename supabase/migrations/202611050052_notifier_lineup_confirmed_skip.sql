-- notifier 건너뛰기 재료 추가: 팀 배치 상태 (스프린트 03 5단계, decisions 2026-11-09 lead 정리
-- "배치 미확정 알림은 푸시 전에 확정됐으면 푸시 건너뜀")
--
-- public.claim_push_batch 가 대상 일정의 팀 배치 상태(lineup_status: draft/confirmed, 배치가 없으면 null)도 돌려준다.
-- notifier(logic.ts): lineup_unconfirmed 는 푸시 직전에 배치가 확정돼 있으면 푸시만 건너뜀(lineup_confirmed).
-- 알림함 줄은 그대로 남는다. 그 밖의 종류는 202611050050 규칙 그대로.
-- 반환 칸이 바뀌어 함수를 다시 만든다 (본문은 202611050050 + 칸 1개). 실행 권한은 service_role 만 그대로.
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
