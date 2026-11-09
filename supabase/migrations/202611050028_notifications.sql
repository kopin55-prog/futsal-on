-- 알림함·발송 대기열과 알림 만들기 한 곳 (스프린트 02 3-1 / data-model.md v4.3 9장 9-1·9-2)
--
-- 표
--   notifications        앱 안 알림함 한 줄 (받는 사람 본인만 읽기, 본인은 read_at 만 수정)
--   notification_outbox  보낼 푸시와 보낼 시각 (서버만). 실제 발송(notifier)은 5단계
--
-- 알림 만들기는 private.notify 한 곳에서만 한다 (앱·service_role 은 실행 불가).
--   - 알림함 줄은 즉시 만든다 (조용한 시간에도, Q-033).
--   - 대기열 send_at (한국 시간, private.notification_send_at):
--       00:00~08:00 에 생긴 알림 → 그날 13:00 (Q-071 11번, Q-072 2번)
--       08:00 부터 생긴 알림 → 바로
--       예외: 미투표 알림(rsvp_deadline_soon)·POM 투표 오픈(award_poll_opened)은 조용한 시간이어도 바로 (Q-072 1번, notifications.md 예외 1)
--   - 새 팀원 합류(member_joined)는 대기열 줄을 만들지 않는다 = 알림함에만 (Q-071 9번).
--   - 중복 방지: (받는 사람, dedupe_key) 고유. dedupe_key = 종류:관련 대상:사건 값.
--     사건 값에는 사건마다 다른 값을 넣어(예: 승격 시각) 실제로 두 번 일어난 사건은 각각 알림 (lead 정리 L-06).
--   - 문구는 종류별로 private.notification_body 한 곳에서 만든다. 제목은 팀 이름(알림함 항목마다 팀 이름, Q-071 10번).
--     문구에 실력 등급·득표수·부상 메모·초대 코드는 넣지 않는다. 다른 사람 이름은 한 명까지, 그 사람을 actor_id 에 적는다.
--     예외: 회원 탈퇴 알림(member_account_deleted)은 이름을 남기려고 actor_id 를 비운다 (Q-072 3번).
--   - 그 밖에 이름이 든 알림은 actor_id 가 그 사람을 가리켜 그 사람이 회원 탈퇴하면 같이 지워진다 (Q-044).
--   - 문구는 임시 (Q-067 0번, 매니저 말투). 묶음 테스트 때 kopn 승인 후 이 함수만 고친다.
--
-- 읽음 (lead 정리 L-11, Q-071 10번)
--   - 본인은 read_at 만 수정할 수 있다(칸 단위 권한). 값은 서버 시각으로 바꿔 적는다.
--   - 이미 읽은 알림의 read_at 은 바뀌지 않는다. read_at 을 비우는 수정(안 읽음으로 되돌리기)은 거절.
--   - "모두 읽음" 함수 mark_all_notifications_read, 안 읽은 개수 count_unread_notifications.

-- ---------------------------------------------------------------------------
-- 종류
-- ---------------------------------------------------------------------------
create type public.notification_kind as enum (
  'match_created',
  'rsvp_deadline_soon',
  'waitlist_promoted',
  'match_cancelled',
  'lineup_confirmed',
  'lineup_changed',
  'award_poll_opened',
  'award_deadline_soon',
  'join_request_received',
  'join_request_decided',
  'member_left',
  'team_dissolved',
  'injury_return_check',
  'manager_assigned',
  'manager_unassigned',
  'ownership_received',
  'member_removed',
  'member_joined',
  'member_account_deleted',
  'join_request_auto_declined',
  'monthly_report'
);

create type public.notification_send_status as enum ('pending', 'sent', 'skipped', 'failed');

-- ---------------------------------------------------------------------------
-- 9-2. 알림함
-- ---------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  kind public.notification_kind not null,
  -- 관련 팀. 팀 줄은 지워지지 않는다(해체는 표시만)
  team_id uuid references public.teams (id) on delete cascade,
  -- 누르면 이동할 대상. 외래 키 아님 (대상이 없어지면 앱이 이동하지 않는다, Q-041)
  ref_type text
    constraint notifications_ref_type_valid check (ref_type in ('match', 'team', 'join_request')),
  ref_id uuid,
  -- 문구에 이름이 들어간 다른 사람. 그 사람이 회원 탈퇴하면 이 알림도 지워진다 (Q-044)
  actor_id uuid references public.profiles (user_id) on delete cascade,
  title text not null
    constraint notifications_title_len check (char_length(title) between 1 and 100),
  body text not null
    constraint notifications_body_len check (char_length(body) between 1 and 300),
  dedupe_key text not null
    constraint notifications_dedupe_key_len check (char_length(dedupe_key) between 1 and 200),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint notifications_ref_pair check ((ref_type is null) = (ref_id is null)),
  constraint notifications_actor_not_self check (actor_id is null or actor_id <> user_id),
  constraint notifications_once unique (user_id, dedupe_key)
);

create index notifications_user_created on public.notifications (user_id, created_at desc);
create index notifications_user_unread on public.notifications (user_id) where read_at is null;
create index notifications_actor on public.notifications (actor_id) where actor_id is not null;
create index notifications_team on public.notifications (team_id) where team_id is not null;
create index notifications_created on public.notifications (created_at);

-- 본인의 read_at 수정만 허용. 다른 칸은 칸 단위 권한으로 막히지만, 혹시 서버 쪽에서 바꿔도 그대로 둔다.
create function private.notifications_before_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.read_at is not null and new.read_at is null then
    raise exception 'cannot_mark_unread' using errcode = 'P0001';
  end if;
  new.id := old.id;
  new.user_id := old.user_id;
  new.kind := old.kind;
  new.team_id := old.team_id;
  new.ref_type := old.ref_type;
  new.ref_id := old.ref_id;
  new.actor_id := old.actor_id;
  new.title := old.title;
  new.body := old.body;
  new.dedupe_key := old.dedupe_key;
  new.created_at := old.created_at;
  -- 처음 읽을 때 서버 시각으로. 이미 읽은 알림은 처음 읽은 시각 그대로.
  new.read_at := case
    when old.read_at is not null then old.read_at
    when new.read_at is not null then now()
    else null
  end;
  return new;
end;
$$;

create trigger notifications_before_update
before update on public.notifications
for each row execute function private.notifications_before_update();

revoke all on table public.notifications from anon, authenticated, public;
alter table public.notifications enable row level security;
grant select on table public.notifications to authenticated;
grant update (read_at) on table public.notifications to authenticated;

create policy notifications_select_own on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 9-1. 발송 대기열 (서버만)
-- ---------------------------------------------------------------------------
create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  send_at timestamptz not null,
  status public.notification_send_status not null default 'pending',
  -- 발송(또는 건너뜀·실패 처리)한 시각
  sent_at timestamptz,
  constraint notification_outbox_one_per_notification unique (notification_id),
  constraint notification_outbox_sent_consistent check (status = 'pending' or sent_at is not null)
);

create index notification_outbox_pending on public.notification_outbox (send_at) where status = 'pending';
create index notification_outbox_user on public.notification_outbox (user_id);
create index notification_outbox_done on public.notification_outbox (sent_at) where status <> 'pending';

-- 앱은 읽기·쓰기 불가 (규칙이 없는 표 = 아무도 못 읽음)
revoke all on table public.notification_outbox from anon, authenticated, public;
alter table public.notification_outbox enable row level security;

-- ---------------------------------------------------------------------------
-- 보낼 시각 (한국 시간). 00:00~08:00 → 그날 13:00, 그 밖 → 바로. 예외 종류는 언제나 바로.
-- ---------------------------------------------------------------------------
create function private.notification_send_at(p_kind public.notification_kind, p_at timestamptz)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select case
    when p_kind in ('rsvp_deadline_soon', 'award_poll_opened') then p_at
    when (p_at at time zone 'Asia/Seoul')::time < time '08:00' then
      ((p_at at time zone 'Asia/Seoul')::date + time '13:00') at time zone 'Asia/Seoul'
    else p_at
  end
$$;

-- 일정 일시 표시: "11월 12일(수) 10:00" (한국 시간)
create function private.match_time_label(p_starts_at timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select to_char(p_starts_at at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일"')
         || '(' || (array['월', '화', '수', '목', '금', '토', '일'])[extract(isodow from p_starts_at at time zone 'Asia/Seoul')::int] || ') '
         || to_char(p_starts_at at time zone 'Asia/Seoul', 'HH24:MI')
$$;

-- ---------------------------------------------------------------------------
-- 문구 (임시, 매니저 말투, Q-067 0번). 종류별로 여기 한 곳.
--   p_args: name(다른 사람 이름), match_at(일정 시작), reason(취소 사유), approved(가입 승인 여부)
-- ---------------------------------------------------------------------------
create function private.notification_body(p_kind public.notification_kind, p_args jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_name text := p_args ->> 'name';
  v_when text := case when p_args ? 'match_at'
                      then private.match_time_label((p_args ->> 'match_at')::timestamptz) end;
  v_reason text := nullif(p_args ->> 'reason', '');
begin
  return case p_kind
    when 'match_created' then
      v_when || ' 경기가 열렸어요! 이번 주도 뛰어야죠, 참석 투표 부탁드려요.'
    when 'rsvp_deadline_soon' then
      v_when || ' 경기 참석 투표가 곧 마감돼요. 아직 투표 전이시네요, 참석하실 거죠?'
    when 'waitlist_promoted' then
      '자리가 났어요! ' || v_when || ' 경기 대기에서 참석으로 바뀌었어요.'
    when 'match_cancelled' then
      v_when || ' 경기가 취소됐어요.' || coalesce(' 사유: ' || v_reason, '')
    when 'join_request_received' then
      v_name || '님이 가입을 신청했어요. 확인 부탁드려요!'
    when 'join_request_decided' then
      case when (p_args ->> 'approved')::boolean
           then '가입이 승인됐어요! 이제 같이 뛰어요.'
           else '아쉽지만 이번 가입 신청은 승인되지 않았어요.' end
    when 'join_request_auto_declined' then
      '팀이 해체되었어요. 보내주신 가입 신청은 마무리됐어요.'
    when 'member_left' then
      v_name || '님이 팀을 떠났어요.'
    when 'member_account_deleted' then
      v_name || '님이 회원 탈퇴로 팀을 떠났어요.'
    when 'member_joined' then
      v_name || '님이 새로 합류했어요! 반갑게 맞아 주세요.'
    when 'team_dissolved' then
      '팀이 해체됐어요. 그동안 함께 뛰어 주셔서 고마워요.'
    when 'manager_assigned' then
      '운영진이 되셨어요! 팀 운영 잘 부탁드려요.'
    when 'manager_unassigned' then
      '운영진에서 팀원으로 바뀌었어요. 그동안 고생 많으셨어요.'
    when 'ownership_received' then
      '팀장을 넘겨받으셨어요! 이제 팀을 잘 이끌어 주세요.'
    when 'member_removed' then
      '팀에서 내보내졌어요. 그동안 함께 뛰어 주셔서 고마워요.'
    else null
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 알림 만들기 한 곳. 받는 사람마다 알림함 줄 + (합류 알림이 아니면) 대기열 줄.
--   p_recipients  받는 사람들 (null·중복·actor 본인은 빠진다)
--   p_event       사건 값 (dedupe_key 의 마지막 부분). 같은 사건을 다시 부르면 무시된다
--   p_actor_id    문구에 이름이 들어간 다른 사람 (이름은 그 사람 프로필의 팀에서 쓸 이름)
--   p_args        문구 재료 (private.notification_body)
-- 만든 알림함 줄 수를 돌려준다.
-- ---------------------------------------------------------------------------
create function private.notify(
  p_kind public.notification_kind,
  p_recipients uuid[],
  p_team_id uuid,
  p_ref_type text,
  p_ref_id uuid,
  p_event text,
  p_actor_id uuid default null,
  p_args jsonb default '{}'::jsonb
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_body text;
  v_args jsonb := coalesce(p_args, '{}'::jsonb);
  v_dedupe text;
  v_now timestamptz := now();
  v_send_at timestamptz;
  v_count int;
begin
  if p_recipients is null or cardinality(p_recipients) = 0 then
    return 0;
  end if;

  select t.name into v_title from public.teams t where t.id = p_team_id;
  if v_title is null then
    raise exception 'notification_team_missing';
  end if;

  if p_actor_id is not null then
    select v_args || jsonb_build_object('name', p.display_name) into v_args
      from public.profiles p where p.user_id = p_actor_id;
    if not (v_args ? 'name') then
      return 0;  -- 이름을 넣을 사람이 없다 (이미 탈퇴)
    end if;
  end if;

  v_body := private.notification_body(p_kind, v_args);
  if v_body is null then
    raise exception 'notification_text_missing';
  end if;

  v_dedupe := p_kind::text || ':' || coalesce(p_ref_id::text, p_team_id::text) || ':' || coalesce(p_event, '');
  v_send_at := private.notification_send_at(p_kind, v_now);

  with recipients as (
    select distinct r.uid
      from unnest(p_recipients) as r(uid)
      join public.profiles p on p.user_id = r.uid
     where r.uid is distinct from p_actor_id
  ),
  inserted as (
    insert into public.notifications (user_id, kind, team_id, ref_type, ref_id, actor_id, title, body, dedupe_key, created_at)
    select r.uid, p_kind, p_team_id, p_ref_type, p_ref_id, p_actor_id, v_title, v_body, v_dedupe, v_now
      from recipients r
    on conflict (user_id, dedupe_key) do nothing
    returning id, user_id
  ),
  queued as (
    insert into public.notification_outbox (notification_id, user_id, send_at)
    select i.id, i.user_id, v_send_at
      from inserted i
     where p_kind <> 'member_joined'  -- 합류 알림은 알림함에만 (Q-071 9번)
    returning 1
  )
  select count(*)::int into v_count from inserted;

  return v_count;
end;
$$;

-- 팀의 현재 팀장·운영진 (해체된 팀은 없음)
create function private.team_staff_ids(p_team_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(m.user_id), '{}')
    from public.team_members m
    join public.teams t on t.id = m.team_id
   where m.team_id = p_team_id and m.status = 'active' and m.role in ('owner', 'manager')
     and t.dissolved_at is null
$$;

-- 팀의 현재 팀원 전체 (해체된 팀은 없음)
create function private.team_member_ids(p_team_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(m.user_id), '{}')
    from public.team_members m
    join public.teams t on t.id = m.team_id
   where m.team_id = p_team_id and m.status = 'active'
     and t.dissolved_at is null
$$;

-- ---------------------------------------------------------------------------
-- 앱: 모두 읽음, 안 읽은 개수 (본인 알림만, 권한 규칙 그대로 적용)
-- ---------------------------------------------------------------------------
create function public.mark_all_notifications_read()
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_count int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  update public.notifications n
     set read_at = now()
   where n.user_id = v_uid and n.read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create function public.count_unread_notifications()
returns int
language sql
stable
security invoker
set search_path = ''
as $$
  select count(*)::int from public.notifications n
   where n.user_id = (select auth.uid()) and n.read_at is null
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한: 알림 만들기는 서버 안에서만 (앱·service_role 불가)
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.notifications_before_update(),
  private.notification_send_at(public.notification_kind, timestamptz),
  private.match_time_label(timestamptz),
  private.notification_body(public.notification_kind, jsonb),
  private.notify(public.notification_kind, uuid[], uuid, text, uuid, text, uuid, jsonb),
  private.team_staff_ids(uuid),
  private.team_member_ids(uuid)
from public, anon, authenticated, service_role;

revoke execute on function
  public.mark_all_notifications_read(),
  public.count_unread_notifications()
from public, anon;
grant execute on function
  public.mark_all_notifications_read(),
  public.count_unread_notifications()
to authenticated;
