-- 안드로이드 푸시 발송 (스프린트 02 5-2 / data-model.md 2-4 device_tokens, 9-1 notification_outbox)
--
-- 발송 서버 함수 notifier(Edge Function)가 쓰는 서버 전용 함수 2개와 매분 예약 작업.
--   1) public.claim_push_batch(n)
--        send_at 이 지난 pending 대기열 줄을 최대 n개 잡는다 (FOR UPDATE SKIP LOCKED).
--        잡은 줄은 같은 처리 안에서 바로 status=failed, sent_at=잡은 시각으로 바꿔 pending 에서 뺀다.
--        → 예약 작업이 겹쳐 돌거나 함수가 두 번 불려도 같은 줄을 다시 잡지 않는다 (중복 발송 방지).
--        → 발송 도중 함수가 멈추면 그 줄은 failed 로 남는다 (두 번 보내기보다 안 보내는 쪽, 다시 시도 없음).
--        돌려주는 값: 알림함 줄의 문구·이동 대상, 건너뛰기 판단 재료(읽음, 일정 상태·시작 시각, 받는 사람의 팀 소속),
--        받는 사람의 모든 기기 토큰. 건너뛰기 판단은 notifier 의 순수 함수가 한다 (Deno 단위 테스트).
--   2) public.finish_push_batch(results, dead_tokens)
--        줄마다 최종 결과(sent / skipped / failed)와 처리 시각(sent_at = 지금)을 적는다. 건너뜀·실패도 처리 시각을 적는다.
--        FCM 이 "등록되지 않은 토큰"(UNREGISTERED / 404)이라고 한 기기 주소는 지운다 (2-4).
--        알림함 줄(notifications)은 건드리지 않는다 (실패해도 알림함은 그대로).
--   두 함수는 service_role 만 실행할 수 있다 (notifier 안에서 Supabase 가 주는 서버 키로 부른다). 앱·비로그인 불가.
--
-- 예약 작업: 매분, 보낼 줄이 있을 때만 private.call_cron_function('notifier') (스프린트 01 과 같은 x-cron-secret 방식).
--   notifier 가 아직 배포 전이면 pg_net 요청이 404 로 끝날 뿐 다른 예약 작업·표에는 영향이 없다 (pending 줄은 그대로 남음).

-- ---------------------------------------------------------------------------
-- 예약 작업이 부를 수 있는 함수에 notifier 추가 (202611050018 과 같은 본문)
-- ---------------------------------------------------------------------------
create or replace function private.call_cron_function(p_function text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
  v_url text;
begin
  -- 예약 작업이 부를 수 있는 함수만
  if p_function not in ('account-cleanup', 'team-logo-cleanup', 'notifier') then
    raise exception 'unknown_function';
  end if;

  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s
   where s.name = 'cron_secret'
   limit 1;
  select s.decrypted_secret into v_url
    from vault.decrypted_secrets s
   where s.name = 'project_url'
   limit 1;

  v_secret := nullif(btrim(v_secret), '');
  v_url := nullif(rtrim(btrim(v_url), '/'), '');
  if v_secret is null or v_url is null then
    return null;  -- 아직 등록 전: 건너뜀
  end if;

  return net.http_post(
    url := v_url || '/functions/v1/' || p_function,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', v_secret
    ),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function private.call_cron_function(text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1) 보낼 줄 잡기
-- ---------------------------------------------------------------------------
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
$$;

-- ---------------------------------------------------------------------------
-- 2) 결과 적기
--   p_results      [{"id": 대기열 줄 ID, "status": "sent" | "skipped" | "failed"}, ...]
--   p_dead_tokens  FCM 이 등록되지 않았다고 한 토큰 (그 기기 주소를 지운다)
-- 잡아 둔 줄(claim 이 failed 로 바꿔 둔 줄)만 바꾼다. 바꾼 줄 수를 돌려준다.
-- ---------------------------------------------------------------------------
create function public.finish_push_batch(p_results jsonb, p_dead_tokens text[] default '{}')
returns int
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_count int := 0;
begin
  if p_results is not null and jsonb_typeof(p_results) = 'array' then
    update public.notification_outbox o
       set status = r.status::public.notification_send_status,
           sent_at = now()
      from jsonb_to_recordset(p_results) as r(id uuid, status text)
     where o.id = r.id
       and o.status = 'failed'
       and r.status in ('sent', 'skipped', 'failed');
    get diagnostics v_count = row_count;
  end if;

  if p_dead_tokens is not null and cardinality(p_dead_tokens) > 0 then
    delete from public.device_tokens d where d.token = any (p_dead_tokens);
  end if;

  return v_count;
end;
$$;

revoke execute on function
  public.claim_push_batch(int),
  public.finish_push_batch(jsonb, text[])
from public, anon, authenticated;
grant execute on function
  public.claim_push_batch(int),
  public.finish_push_batch(jsonb, text[])
to service_role;

-- ---------------------------------------------------------------------------
-- 예약 작업: 매분. 보낼 줄이 없으면 함수를 부르지 않는다.
-- ---------------------------------------------------------------------------
select cron.unschedule(jobid) from cron.job where jobname = 'notifier';
select cron.schedule(
  'notifier',
  '* * * * *',
  $$select private.call_cron_function('notifier') where exists (select 1 from public.notification_outbox o where o.status = 'pending' and o.send_at <= now())$$
);
