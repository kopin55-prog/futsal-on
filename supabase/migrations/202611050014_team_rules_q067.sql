-- 스프린트 01 화면 동작 세부의 서버 규칙 (Q-067, 2026-11-05 "추천안대로")
--
-- 4번  정기 운동일 자정 넘김 허용 (예: 22:00~00:30). 시작 = 종료만 불가.
-- 5번  한 사람 소속 팀 최대 10개(만든 팀 포함), 팀 최대 인원 100명. 서버에서도 검사.
-- 7번  팀 해체: 팀장만, 확인 입력은 이름 정리 규칙 적용 후 앞뒤 공백·영문 대소문자 무시 비교.
-- 8번  해체 시 대기 신청 자동 거절(알림은 202611050029 에서 연결). 해체된 팀의 초대 코드·식별코드 입력은 team_dissolved.
-- 10번 신청자는 대기 중 신청을 취소할 수 있다. 본인 대기 신청 목록(팀 이름·식별코드·로고) 함수.
-- (9번 초대 코드는 발급자와 무관하게 유효: 이미 그렇게 동작. 17번 사진 로고 팀도 로고 글자 자동 변경: 트리거가 이미 사진과 무관.)

-- ---------------------------------------------------------------------------
-- 4번: 자정 넘김 허용
-- ---------------------------------------------------------------------------
alter table public.teams drop constraint teams_regular_end_after_start;
alter table public.teams add constraint teams_regular_end_not_start
  check (regular_end_time is null or regular_end_time <> regular_start_time);

-- ---------------------------------------------------------------------------
-- 5번: 인원 상한
-- ---------------------------------------------------------------------------
create function private.active_team_count(p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int
    from public.team_members m
    join public.teams t on t.id = m.team_id
   where m.user_id = p_user_id and m.status = 'active' and t.dissolved_at is null
$$;

create function private.check_join_limits(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if private.active_team_count(p_user_id) >= 10 then
    raise exception 'team_limit_reached' using errcode = 'P0001';
  end if;
  if private.team_search_row_count(p_team_id) >= 100 then
    raise exception 'team_full' using errcode = 'P0001';
  end if;
end;
$$;

-- 가입 신청 공통: 이미 소속 → already_member, 대기 신청 있음 → request_already_pending (10번 안내 문구용),
-- 인원 상한은 신청 때도 미리 알려준다.
create or replace function private.insert_join_request(
  p_uid uuid,
  p_team_id uuid,
  p_via public.join_via,
  p_invite_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if exists (
    select 1 from public.team_members m
     where m.team_id = p_team_id and m.user_id = p_uid and m.status = 'active'
  ) then
    raise exception 'already_member' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.join_requests r
     where r.team_id = p_team_id and r.user_id = p_uid and r.status = 'pending'
  ) then
    raise exception 'request_already_pending' using errcode = 'P0001';
  end if;
  perform private.check_join_limits(p_team_id, p_uid);
  begin
    insert into public.join_requests (team_id, user_id, via, invite_id)
    values (p_team_id, p_uid, p_via, p_invite_id)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'request_already_pending' using errcode = 'P0001';
  end;
  return v_id;
end;
$$;

-- 승인 때 다시 확인한다 (신청 뒤 다른 팀에 들어갔거나 팀이 찼을 수 있음).
create or replace function public.decide_join_request(p_request_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_req public.join_requests;
begin
  select r.* into v_req from public.join_requests r where r.id = p_request_id;
  if v_req.id is null or not private.is_team_staff(v_req.team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  -- 같은 팀의 승인·해체·역할 변경을 한 줄로 세운다 (인원 상한 검사가 엇갈리지 않게).
  perform 1 from public.teams t where t.id = v_req.team_id for update;
  select r.* into v_req from public.join_requests r where r.id = p_request_id for update;
  if v_req.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = 'P0001';
  end if;
  if p_approve is null then
    raise exception 'invalid_decision' using errcode = 'P0001';
  end if;

  if p_approve and not exists (
    select 1 from public.team_members m
     where m.team_id = v_req.team_id and m.user_id = v_req.user_id and m.status = 'active'
  ) then
    perform private.check_join_limits(v_req.team_id, v_req.user_id);
    insert into public.team_members (team_id, user_id, role, status)
    values (v_req.team_id, v_req.user_id, 'member', 'active');
  end if;

  update public.join_requests
     set status = case when p_approve then 'approved'::public.join_request_status
                       else 'rejected'::public.join_request_status end,
         decided_by = v_uid,
         decided_at = now()
   where id = v_req.id;
  -- (알림은 202611050029 에서 연결) join_request_decided 알림 (9장)
end;
$$;

-- ---------------------------------------------------------------------------
-- 8번: 해체된 팀의 코드 입력
-- ---------------------------------------------------------------------------
-- 지문이 해체된 팀의 초대 코드와 일치하는지. 유효한 코드를 가진 사람만 닿으므로 코드 존재 여부가 새지 않는다.
create function private.is_dissolved_team_invite(p_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.team_invites i
      join public.teams t on t.id = i.team_id
     where p_code is not null
       and char_length(p_code) between 16 and 128
       and i.token_hash = private.invite_token_hash(btrim(p_code))
       and t.dissolved_at is not null
  )
$$;

create or replace function public.get_invite_team(p_code text)
returns table (team_name text, team_code text, logo_text text, logo_image_path text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_invite public.team_invites;
begin
  v_invite := private.find_valid_invite(p_code);
  if v_invite.id is null then
    if private.is_dissolved_team_invite(p_code) then
      raise exception 'team_dissolved' using errcode = 'P0001';
    end if;
    raise exception 'invite_invalid' using errcode = 'P0001';
  end if;
  return query
    select t.name, t.team_code, t.logo_text, t.logo_image_path
      from public.teams t
     where t.id = v_invite.team_id;
end;
$$;

create or replace function public.request_join_by_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_invite public.team_invites;
begin
  v_invite := private.find_valid_invite(p_code);
  if v_invite.id is null then
    if private.is_dissolved_team_invite(p_code) then
      raise exception 'team_dissolved' using errcode = 'P0001';
    end if;
    raise exception 'invite_invalid' using errcode = 'P0001';
  end if;
  return private.insert_join_request(v_uid, v_invite.team_id, 'invite', v_invite.id);
end;
$$;

create or replace function public.find_team_by_code(p_team_code text)
returns table (
  team_code text,
  name text,
  logo_text text,
  logo_image_path text,
  regular_weekday smallint,
  regular_start_time time,
  regular_end_time time,
  venue_name text,
  member_count int,
  is_recruiting boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_code text := upper(btrim(coalesce(p_team_code, '')));
begin
  if exists (select 1 from public.teams t where t.team_code = v_code and t.dissolved_at is not null) then
    raise exception 'team_dissolved' using errcode = 'P0001';
  end if;
  return query
    select t.team_code, t.name, t.logo_text, t.logo_image_path,
           t.regular_weekday, t.regular_start_time, t.regular_end_time, t.venue_name,
           private.team_search_row_count(t.id), t.is_recruiting
      from public.teams t
     where t.dissolved_at is null
       and t.team_code = v_code;
end;
$$;

create or replace function public.request_join(p_team_code text, p_via public.join_via)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team public.teams;
begin
  if p_via is null or p_via not in ('search', 'code') then
    raise exception 'invalid_join_via' using errcode = 'P0001';
  end if;
  select t.* into v_team
    from public.teams t
   where t.team_code = upper(btrim(coalesce(p_team_code, '')));
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = 'P0001';
  end if;
  if v_team.dissolved_at is not null then
    raise exception 'team_dissolved' using errcode = 'P0001';
  end if;
  if not v_team.is_recruiting then
    raise exception 'team_not_recruiting' using errcode = 'P0001';
  end if;
  return private.insert_join_request(v_uid, v_team.id, p_via, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- 10번: 신청 취소, 본인 대기 신청 목록
-- ---------------------------------------------------------------------------
create function public.cancel_join_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_req public.join_requests;
begin
  select r.* into v_req from public.join_requests r where r.id = p_request_id for update;
  if v_req.id is null or v_req.user_id <> v_uid then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = 'P0001';
  end if;
  update public.join_requests
     set status = 'cancelled', decided_at = now()
   where id = v_req.id;
end;
$$;

-- 신청자는 아직 팀원이 아니라 teams 를 읽지 못하므로, 팀 찾기 결과와 같은 범위(이름·식별코드·로고)만 준다.
create function public.list_my_pending_join_requests()
returns table (
  request_id uuid,
  created_at timestamptz,
  team_code text,
  team_name text,
  logo_text text,
  logo_image_path text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
begin
  return query
    select r.id, r.created_at, t.team_code, t.name, t.logo_text, t.logo_image_path
      from public.join_requests r
      join public.teams t on t.id = r.team_id
     where r.user_id = v_uid
       and r.status = 'pending'
       and t.dissolved_at is null
     order by r.created_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7번·8번: 팀 해체 (3-8)
-- ---------------------------------------------------------------------------
-- 확인 입력 비교: 이름 정리 규칙(보이지 않는 문자 삭제·앞뒤 공백·연속 공백) 적용 후 영문 대소문자 무시.
create function private.dissolve_confirmation_matches(p_team_name text, p_input text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_input is not null
     and lower(private.normalize_single_line_name(p_input)) = lower(private.normalize_single_line_name(p_team_name))
$$;

create function public.dissolve_team(p_team_id uuid, p_confirm_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_name text;
begin
  perform private.lock_team_as_owner(p_team_id);
  select t.name into v_name from public.teams t where t.id = p_team_id;
  if not private.dissolve_confirmation_matches(v_name, p_confirm_name) then
    raise exception 'dissolve_confirmation_mismatch' using errcode = 'P0001';
  end if;

  update public.teams set dissolved_at = now() where id = p_team_id;

  update public.team_members
     set status = 'dissolved', ended_at = now()
   where team_id = p_team_id and status = 'active';

  -- 실력 등급·그룹·라이벌은 팀 전체 삭제 (Q-015)
  delete from public.skill_ratings where team_id = p_team_id;
  delete from public.pairing_rules where team_id = p_team_id;

  -- 대기 신청 자동 거절 (Q-067 8번). 처리한 관리자는 없음.
  update public.join_requests
     set status = 'rejected', decided_at = now(), decided_by = null
   where team_id = p_team_id and status = 'pending';

  -- 초대 코드 무효화
  update public.team_invites set revoked_at = now()
   where team_id = p_team_id and revoked_at is null;

  -- (알림은 202611050029 에서 연결) 팀원 전원 team_dissolved 알림, 대기 신청자 "팀이 해체되었어요" 알림 (Q-067 8번)
  -- TODO(일정 단계): 다가오는 일정 취소, 남은 최근 10경기 상세 삭제 (3-8, Q-061 4번)
  -- TODO(로고 사진 단계): 로고 사진 파일 삭제 (3-8)
end;
$$;

-- teams_before_write 는 dissolved_at 을 막지 않지만 칸 단위 권한으로 앱은 못 쓴다 (S-03). 해체 되돌리기 방지:
create function private.teams_keep_dissolved()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.dissolved_at is not null then
    new.dissolved_at := old.dissolved_at;
  end if;
  return new;
end;
$$;

create trigger teams_keep_dissolved
before update on public.teams
for each row execute function private.teams_keep_dissolved();

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.cancel_join_request(uuid),
  public.list_my_pending_join_requests(),
  public.dissolve_team(uuid, text)
from public, anon;
grant execute on function
  public.cancel_join_request(uuid),
  public.list_my_pending_join_requests(),
  public.dissolve_team(uuid, text)
to authenticated;
