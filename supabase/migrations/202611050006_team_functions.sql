-- 팀 만들기·로고 글자·초대 코드·팀 찾기·가입 신청·역할 변경·팀 탈퇴 서버 함수
-- (data-model.md 3-1, 3-3, 3-5, 3-6, 11장 3·4번, 13장 S-03·S-13·S-14)
--
-- 이번 단계에서 만들지 않은 것 (lead 보고):
-- - 팀 해체: 확인 입력 비교 방식 미정(U-28)
-- - 가입 신청 취소: 기능 여부 미정(U-32)
-- - 알림(Q-022 역할 변경·내보내기, 가입 신청 접수·처리): 알림 표(9장)가 생기는 단계에서 추가
-- - 팀 탈퇴·내보내기 때 실력 등급·그룹 소속·다가오는 참석 응답 정리: 해당 표가 생기는 단계에서 추가
-- - 이름 검색·초대 확인·가입 신청 호출 횟수 제한(S-13, S-14 권고): 호출 기록을 둘 표가 승인본에 없음

-- ---------------------------------------------------------------------------
-- 팀 식별코드 생성 (Q-029): 32글자(A~Z 중 O·I 제외 + 2~9) 무작위 6자리. 겹치면 다시 만든다.
-- ---------------------------------------------------------------------------
create function private.new_team_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
  i int;
  attempt int;
begin
  for attempt in 1..20 loop
    v_bytes := extensions.gen_random_bytes(6);
    v_code := '';
    for i in 0..5 loop
      -- 256 은 32 의 배수라 치우침 없음
      v_code := v_code || substr(alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    if not exists (select 1 from public.teams t where t.team_code = v_code) then
      return v_code;
    end if;
  end loop;
  raise exception 'team_code_generation_failed' using errcode = 'P0001';
end;
$$;

-- 초대 코드 지문 (SHA-256, 16진수)
create function private.invite_token_hash(p_code text)
returns text
language sql
immutable
strict
set search_path = ''
as $$ select encode(sha256(convert_to(p_code, 'UTF8')), 'hex') $$;

-- 유효한 초대 코드: 지문 일치 + 만료 전 + 무효화 안 됨 + 팀 해체 안 됨 (3-5)
create function private.find_valid_invite(p_code text)
returns public.team_invites
language sql
stable
security definer
set search_path = ''
as $$
  select i.*
    from public.team_invites i
    join public.teams t on t.id = i.team_id
   where p_code is not null
     and char_length(p_code) between 16 and 128
     and i.token_hash = private.invite_token_hash(btrim(p_code))
     and i.revoked_at is null
     and now() < i.expires_at
     and t.dissolved_at is null
$$;

-- ---------------------------------------------------------------------------
-- 팀 만들기: 팀 이름만으로 생성, 만든 사람이 팀장 (3-1)
-- ---------------------------------------------------------------------------
create function public.create_team(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team_id uuid;
begin
  begin
    insert into public.teams (name, team_code, created_by)
    values (p_name, private.new_team_code(), v_uid)
    returning id into v_team_id;
  exception when check_violation or not_null_violation then
    raise exception 'invalid_team_name' using errcode = 'P0001';
  end;

  insert into public.team_members (team_id, user_id, role, status)
  values (v_team_id, v_uid, 'owner', 'active');

  return v_team_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 로고 글자 변경: 팀장만 (Q-014). 정리 후 1~2자 (Q-013, Q-034, Q-048)
-- ---------------------------------------------------------------------------
create function public.set_team_logo_text(p_team_id uuid, p_logo_text text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_text text;
begin
  if not private.is_team_owner(p_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  v_text := private.normalize_single_line_name(coalesce(p_logo_text, ''));
  if private.grapheme_count(v_text) not between 1 and 2
     or not private.is_valid_single_line_name(v_text, 2) then
    raise exception 'invalid_logo_text' using errcode = 'P0001';
  end if;
  update public.teams set logo_text = v_text where id = p_team_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 초대 코드 발급: 관리자. 이전 코드는 무효화하고 새 코드 1개 (Q-020).
-- 돌려준 원본은 다시 볼 수 없다 (지문만 저장).
-- ---------------------------------------------------------------------------
create function public.issue_team_invite(p_team_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_code text;
begin
  if not private.is_team_staff(p_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  -- 같은 팀의 동시 발급을 한 줄로 세운다.
  perform 1 from public.teams t where t.id = p_team_id for update;

  update public.team_invites
     set revoked_at = now()
   where team_id = p_team_id and revoked_at is null;

  -- 32바이트 무작위 값 → URL 에 안전한 base64 (패딩 없음, 43자)
  v_code := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');

  insert into public.team_invites (team_id, token_hash, created_by)
  values (p_team_id, private.invite_token_hash(v_code), v_uid);

  return v_code;
end;
$$;

-- ---------------------------------------------------------------------------
-- 초대 코드 확인: 유효할 때만 팀 이름·식별코드·로고 (3-1). 실패 이유는 구분하지 않는다.
-- ---------------------------------------------------------------------------
create function public.get_invite_team(p_code text)
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
    raise exception 'invite_invalid' using errcode = 'P0001';
  end if;
  return query
    select t.name, t.team_code, t.logo_text, t.logo_image_path
      from public.teams t
     where t.id = v_invite.team_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 팀 찾기 (3-1, Q-021, Q-029, Q-051, S-14)
-- 모집 꺼진 팀도 포함, 해체된 팀 제외. 주소·좌표·장소 번호·만든 사람·내부 ID 는 주지 않는다.
-- ---------------------------------------------------------------------------
create function private.team_search_row_count(p_team_id uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int from public.team_members m where m.team_id = p_team_id and m.status = 'active'
$$;

-- 이름 검색: 2자 이상, 부분 일치, 최대 20개 (S-14)
create function public.search_teams(p_query text)
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
  v_query text := private.normalize_single_line_name(coalesce(p_query, ''));
  v_pattern text;
begin
  if char_length(v_query) < 2 or char_length(v_query) > 80 then
    raise exception 'invalid_search_query' using errcode = 'P0001';
  end if;
  v_pattern := '%' || replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return query
    select t.team_code, t.name, t.logo_text, t.logo_image_path,
           t.regular_weekday, t.regular_start_time, t.regular_end_time, t.venue_name,
           private.team_search_row_count(t.id), t.is_recruiting
      from public.teams t
     where t.dissolved_at is null
       and t.name ilike v_pattern escape '\'
     order by t.name, t.team_code
     limit 20;
end;
$$;

-- 식별코드 찾기: 소문자도 인식, 정확히 일치할 때만 (Q-051). 틀린 횟수 제한 없음 (M-37).
create function public.find_team_by_code(p_team_code text)
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
begin
  return query
    select t.team_code, t.name, t.logo_text, t.logo_image_path,
           t.regular_weekday, t.regular_start_time, t.regular_end_time, t.venue_name,
           private.team_search_row_count(t.id), t.is_recruiting
      from public.teams t
     where t.dissolved_at is null
       and t.team_code = upper(btrim(coalesce(p_team_code, '')));
end;
$$;

-- ---------------------------------------------------------------------------
-- 가입 신청 (3-6)
-- ---------------------------------------------------------------------------
create function private.insert_join_request(
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

-- 이름 검색·식별코드 경로: 모집 중일 때만 (Q-021, Q-029)
create function public.request_join(p_team_code text, p_via public.join_via)
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
   where t.team_code = upper(btrim(coalesce(p_team_code, '')))
     and t.dissolved_at is null;
  if v_team.id is null then
    raise exception 'team_not_found' using errcode = 'P0001';
  end if;
  if not v_team.is_recruiting then
    raise exception 'team_not_recruiting' using errcode = 'P0001';
  end if;
  return private.insert_join_request(v_uid, v_team.id, p_via, null);
end;
$$;

-- 초대 코드 경로: 신청 시각에 코드가 유효할 때만 (모집 여부 무관, Q-029)
create function public.request_join_by_invite(p_code text)
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
    raise exception 'invite_invalid' using errcode = 'P0001';
  end if;
  return private.insert_join_request(v_uid, v_invite.team_id, 'invite', v_invite.id);
end;
$$;

-- 승인·거절: 관리자. 신청 뒤 코드 재발급·모집 끔이 있어도 대기 신청은 유효 (Q-042, Q-054)
create function public.decide_join_request(p_request_id uuid, p_approve boolean)
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
  if v_req.id is null or not private.is_team_staff(v_req.team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = 'P0001';
  end if;
  if p_approve is null then
    raise exception 'invalid_decision' using errcode = 'P0001';
  end if;

  update public.join_requests
     set status = case when p_approve then 'approved'::public.join_request_status
                       else 'rejected'::public.join_request_status end,
         decided_by = v_uid,
         decided_at = now()
   where id = v_req.id;

  if p_approve and not exists (
    select 1 from public.team_members m
     where m.team_id = v_req.team_id and m.user_id = v_req.user_id and m.status = 'active'
  ) then
    insert into public.team_members (team_id, user_id, role, status)
    values (v_req.team_id, v_req.user_id, 'member', 'active');
  end if;
  -- (알림은 202611050029 에서 연결) join_request_decided 알림 (9장)
end;
$$;

-- ---------------------------------------------------------------------------
-- 역할 변경: 팀장만 (3-3, Q-018). 같은 팀의 역할 변경은 팀 줄 잠금으로 한 줄로 세운다.
-- ---------------------------------------------------------------------------
create function private.lock_team_as_owner(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_team_owner(p_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  perform 1 from public.teams t where t.id = p_team_id for update;
end;
$$;

create function private.active_role(p_team_id uuid, p_user_id uuid)
returns public.team_role
language sql
stable
security definer
set search_path = ''
as $$
  select m.role from public.team_members m
   where m.team_id = p_team_id and m.user_id = p_user_id and m.status = 'active'
$$;

-- 운영진 지정: 팀원 → 운영진, 최대 2명
create function public.appoint_manager(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_role public.team_role;
begin
  perform private.lock_team_as_owner(p_team_id);
  v_role := private.active_role(p_team_id, p_user_id);
  if v_role is null then
    raise exception 'target_not_member' using errcode = 'P0001';
  elsif v_role <> 'member' then
    raise exception 'already_manager' using errcode = 'P0001';
  end if;
  if (select count(*) from public.team_members m
       where m.team_id = p_team_id and m.status = 'active' and m.role = 'manager') >= 2 then
    raise exception 'manager_limit_reached' using errcode = 'P0001';
  end if;
  update public.team_members set role = 'manager'
   where team_id = p_team_id and user_id = p_user_id and status = 'active';
  -- (알림은 202611050029 에서 연결) manager_assigned (Q-022)
end;
$$;

-- 운영진 해제: 운영진 → 팀원
create function public.dismiss_manager(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
begin
  perform private.lock_team_as_owner(p_team_id);
  if private.active_role(p_team_id, p_user_id) is distinct from 'manager' then
    raise exception 'target_not_manager' using errcode = 'P0001';
  end if;
  update public.team_members set role = 'member'
   where team_id = p_team_id and user_id = p_user_id and status = 'active';
  -- (알림은 202611050029 에서 연결) manager_unassigned (Q-022)
end;
$$;

-- 팀장 위임: 운영진 중에서만, 즉시, 기존 팀장은 운영진으로 (3-3)
create function public.transfer_ownership(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
begin
  perform private.lock_team_as_owner(p_team_id);
  if private.active_role(p_team_id, p_user_id) is distinct from 'manager' then
    raise exception 'target_not_manager' using errcode = 'P0001';
  end if;
  update public.team_members set role = 'manager'
   where team_id = p_team_id and user_id = v_uid and status = 'active';
  update public.team_members set role = 'owner'
   where team_id = p_team_id and user_id = p_user_id and status = 'active';
  -- (알림은 202611050029 에서 연결) ownership_received (Q-022)
end;
$$;

-- 내보내기: 팀장만, 운영진도 바로 (Q-018)
create function public.remove_member(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_role public.team_role;
begin
  perform private.lock_team_as_owner(p_team_id);
  if p_user_id = v_uid then
    raise exception 'cannot_target_self' using errcode = 'P0001';
  end if;
  v_role := private.active_role(p_team_id, p_user_id);
  if v_role is null then
    raise exception 'target_not_member' using errcode = 'P0001';
  end if;
  update public.team_members
     set status = 'removed', ended_at = now(), ended_by = v_uid
   where team_id = p_team_id and user_id = p_user_id and status = 'active';
  -- TODO(팀 나누기·일정 단계): 실력 등급·그룹 소속 삭제, 다가오는 참석 응답 정리 (3-8)
  -- (알림은 202611050029 에서 연결) member_removed (Q-022)
end;
$$;

-- 팀 탈퇴: 본인. 팀장은 위임 또는 해체 전에는 불가 (Q-037)
create function public.leave_team(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_role public.team_role;
begin
  perform 1 from public.teams t where t.id = p_team_id for update;
  v_role := private.active_role(p_team_id, v_uid);
  if v_role is null or not private.is_team_member(p_team_id) then
    raise exception 'not_member' using errcode = 'P0001';
  end if;
  if v_role = 'owner' then
    raise exception 'owner_must_transfer_or_dissolve' using errcode = 'P0001';
  end if;
  update public.team_members
     set status = 'left', ended_at = now()
   where team_id = p_team_id and user_id = v_uid and status = 'active';
  -- TODO(팀 나누기·일정 단계): 실력 등급·그룹 소속 삭제, 다가오는 참석 응답 정리 (3-8)
  -- (알림은 202611050029 에서 연결) member_left
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.create_team(text),
  public.set_team_logo_text(uuid, text),
  public.issue_team_invite(uuid),
  public.get_invite_team(text),
  public.search_teams(text),
  public.find_team_by_code(text),
  public.request_join(text, public.join_via),
  public.request_join_by_invite(text),
  public.decide_join_request(uuid, boolean),
  public.appoint_manager(uuid, uuid),
  public.dismiss_manager(uuid, uuid),
  public.transfer_ownership(uuid, uuid),
  public.remove_member(uuid, uuid),
  public.leave_team(uuid)
from public, anon;
grant execute on function
  public.create_team(text),
  public.set_team_logo_text(uuid, text),
  public.issue_team_invite(uuid),
  public.get_invite_team(text),
  public.search_teams(text),
  public.find_team_by_code(text),
  public.request_join(text, public.join_via),
  public.request_join_by_invite(text),
  public.decide_join_request(uuid, boolean),
  public.appoint_manager(uuid, uuid),
  public.dismiss_manager(uuid, uuid),
  public.transfer_ownership(uuid, uuid),
  public.remove_member(uuid, uuid),
  public.leave_team(uuid)
to authenticated;
