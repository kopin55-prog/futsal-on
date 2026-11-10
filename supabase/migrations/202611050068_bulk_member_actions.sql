-- 큰 팀 관리: 여러 명 한 번에 처리하는 서버 함수 (Q-079 3번 b·c, decisions.md 2026-11-10 "큰 팀 관리")
--
-- 표·칸은 추가하지 않는다 (data-model v4.7 그대로). 서버 함수만 더한다.
--
-- 1) set_skill_levels(팀, 사람 목록, 등급): 실력 등급 여러 명 한 번에 지정.
--    - 기존 단건 set_skill_level 과 같은 검사: 팀장·운영진만(not_permitted), 등급 필수(invalid_skill_level),
--      대상은 모두 그 팀의 현재 팀원(target_not_member). 하나라도 어긋나면 아무것도 쓰지 않는다(한 번의 처리).
--    - "미정"이면 줄을 지운다(단건과 같음). 같은 사람이 여러 번 들어 있어도 한 번만. 빈 목록이면 아무 일 없음.
--
-- 2) decide_join_requests(팀, 신청 목록, 승인 여부): 가입 신청 여러 개 한 번에 승인·거절.
--    - 팀장·운영진만(not_permitted), 승인 여부 필수(invalid_decision). 단건 decide_join_request 와 같이
--      팀 줄을 먼저 잠가 같은 팀의 승인·해체·역할 변경과 한 줄로 세운다.
--    - 신청 순서(created_at, 같으면 id)대로 하나씩 단건과 같은 처리를 한다:
--      정원(팀 최대 100명, team_full)·사람당 팀 10개(team_limit_reached)에 걸리는 승인은 그 신청만 건너뛰고
--      대기 상태로 둔다 → "승인 가능한 만큼 신청 순서대로 승인, 나머지는 그대로 두고 결과 안내".
--      이미 처리된 신청(승인·거절·취소)과 이 팀 신청이 아닌 것·없는 것은 건너뛴다(already_decided).
--    - 알림은 단건과 같게 사람마다: 신청자에게 join_request_decided, 새로 합류하면 팀원에게 member_joined.
--    - 결과는 신청마다 한 줄 (request_id, result): approved / rejected / already_decided / team_full / team_limit_reached.
--
-- 단건 decide_join_request 는 같은 처리(private.apply_join_decision)를 쓰도록 바꾼다(동작 그대로).

-- ---------------------------------------------------------------------------
-- 신청 하나 처리 (잠금·대기 확인은 부르는 쪽이 한 뒤)
-- ---------------------------------------------------------------------------
create function private.apply_join_decision(p_req public.join_requests, p_approve boolean, p_uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_id uuid;
begin
  if p_approve and not exists (
    select 1 from public.team_members m
     where m.team_id = p_req.team_id and m.user_id = p_req.user_id and m.status = 'active'
  ) then
    perform private.check_join_limits(p_req.team_id, p_req.user_id);
    insert into public.team_members (team_id, user_id, role, status)
    values (p_req.team_id, p_req.user_id, 'member', 'active')
    returning id into v_member_id;
  end if;

  update public.join_requests
     set status = case when p_approve then 'approved'::public.join_request_status
                       else 'rejected'::public.join_request_status end,
         decided_by = p_uid,
         decided_at = now()
   where id = p_req.id;

  -- 신청자에게 승인·거절 (사유 없음)
  perform private.notify('join_request_decided', array[p_req.user_id], p_req.team_id,
                         'join_request', p_req.id, '', null,
                         jsonb_build_object('approved', p_approve));
  -- 새로 합류했으면 본인 뺀 팀원 전체에게 합류 알림 (알림함에만, Q-071 9번, Q-072 4번)
  if v_member_id is not null then
    perform private.notify('member_joined', private.team_member_ids(p_req.team_id), p_req.team_id,
                           'team', p_req.team_id, v_member_id::text, p_req.user_id);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 단건 (동작 그대로, 처리 부분만 공용 함수로)
-- ---------------------------------------------------------------------------
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

  perform private.apply_join_decision(v_req, p_approve, v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- 여러 개 한 번에
-- ---------------------------------------------------------------------------
create function public.decide_join_requests(p_team_id uuid, p_request_ids uuid[], p_approve boolean)
returns table (request_id uuid, result text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_req public.join_requests;
  v_ids uuid[];
begin
  if not private.is_team_staff(p_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  if p_approve is null then
    raise exception 'invalid_decision' using errcode = 'P0001';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_ids
    from unnest(coalesce(p_request_ids, '{}')) x
   where x is not null;
  if cardinality(v_ids) = 0 then
    return;
  end if;

  -- 같은 팀의 승인·해체·역할 변경을 한 줄로 세운다 (단건과 같음).
  perform 1 from public.teams t where t.id = p_team_id for update;

  -- 이 팀의 대기 신청이 아닌 것(이미 처리·취소, 다른 팀, 없음)은 건너뜀
  return query
    select x, 'already_decided'::text
      from unnest(v_ids) x
     where not exists (
       select 1 from public.join_requests r
        where r.id = x and r.team_id = p_team_id and r.status = 'pending'
     );

  -- 신청 순서대로
  for v_req in
    select r.* from public.join_requests r
     where r.id = any (v_ids) and r.team_id = p_team_id and r.status = 'pending'
     order by r.created_at, r.id
     for update
  loop
    begin
      perform private.apply_join_decision(v_req, p_approve, v_uid);
      request_id := v_req.id;
      result := case when p_approve then 'approved' else 'rejected' end;
      return next;
    exception when sqlstate 'P0001' then
      -- 정원·사람당 팀 수에 걸린 승인만 건너뛰고 대기로 둔다 (그 신청의 처리는 되돌려진다)
      if sqlerrm in ('team_full', 'team_limit_reached') then
        request_id := v_req.id;
        result := sqlerrm;
        return next;
      else
        raise;
      end if;
    end;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 실력 등급 여러 명 한 번에
-- ---------------------------------------------------------------------------
create function public.set_skill_levels(p_team_id uuid, p_user_ids uuid[], p_level public.skill_level)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_ids uuid[];
begin
  if not private.is_team_staff(p_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  if p_level is null then
    raise exception 'invalid_skill_level' using errcode = 'P0001';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_ids
    from unnest(coalesce(p_user_ids, '{}')) x;
  if cardinality(v_ids) = 0 then
    return;
  end if;
  -- 모두 그 팀의 현재 팀원이어야 한다 (null 포함 하나라도 아니면 아무것도 쓰지 않음)
  if exists (
    select 1 from unnest(v_ids) x
     where x is null or not exists (
       select 1 from public.team_members m
        where m.team_id = p_team_id and m.user_id = x and m.status = 'active'
     )
  ) then
    raise exception 'target_not_member' using errcode = 'P0001';
  end if;

  if p_level = 'undecided' then
    delete from public.skill_ratings where team_id = p_team_id and user_id = any (v_ids);
    return;
  end if;

  insert into public.skill_ratings (team_id, user_id, level, updated_by, updated_at)
  select p_team_id, x, p_level, v_uid, now() from unnest(v_ids) x
  on conflict (team_id, user_id) do update
    set level = excluded.level,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function public.decide_join_requests(uuid, uuid[], boolean) from public, anon;
grant execute on function public.decide_join_requests(uuid, uuid[], boolean) to authenticated;
revoke execute on function public.set_skill_levels(uuid, uuid[], public.skill_level) from public, anon;
grant execute on function public.set_skill_levels(uuid, uuid[], public.skill_level) to authenticated;
