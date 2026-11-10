-- 회원 탈퇴 시 배치 변경 이력 안의 사람 ID 정리 (스프린트 03 7-4 / data-model.md v4.5 2-5·5-4)
--
-- lineup_change_logs.before / after 는 기록 칸(jsonb)이라 외래 키가 걸리지 않는다.
-- 탈퇴 함수가 계정을 지우기 전에 같은 처리 안에서 그 사람 ID 를 모든 팀 블록(squads[].user_ids)과
-- 교체 블록(bench.user_ids)에서 뺀다. 이력 줄 자체와 나머지 사람·게스트 ID, 팀 수·팀당 인원·조끼 색은 그대로.
-- 그 밖의 기록(투표 대상자·참여 표시·득표·수상자·출석 기록·시즌 카운트·월간 출석·배치 명단)은
-- 계정 삭제 연쇄(같이 삭제)로 지워지고 다시 계산하지 않는다 (Q-038). 이 사람이 준 표는 득표에 남는다 (12-3).
-- public.delete_account (202611050029) 의 TODO 해소. 실행 권한은 service_role 전용 그대로.

-- ---------------------------------------------------------------------------
-- 배치 요약(private.lineup_snapshot 모양)에서 한 사람 ID 빼기: 팀 블록 squads[].user_ids, 교체 블록 bench.user_ids
-- ---------------------------------------------------------------------------
create function private.strip_user_from_lineup_snapshot(p_snapshot jsonb, p_user_id uuid)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_needle jsonb := to_jsonb(p_user_id::text);
  v jsonb := p_snapshot;
begin
  if jsonb_typeof(v) <> 'object' then
    return v;
  end if;
  if jsonb_typeof(v -> 'squads') = 'array' then
    v := jsonb_set(v, '{squads}', coalesce((
      select jsonb_agg(
               case when jsonb_typeof(q.e -> 'user_ids') = 'array' then
                 jsonb_set(q.e, '{user_ids}', coalesce((
                   select jsonb_agg(u.e order by u.ord)
                     from jsonb_array_elements(q.e -> 'user_ids') with ordinality as u(e, ord)
                    where u.e <> v_needle), '[]'::jsonb))
               else q.e end
               order by q.ord)
        from jsonb_array_elements(v -> 'squads') with ordinality as q(e, ord)), '[]'::jsonb));
  end if;
  if jsonb_typeof(v -> 'bench' -> 'user_ids') = 'array' then
    v := jsonb_set(v, '{bench,user_ids}', coalesce((
      select jsonb_agg(u.e order by u.ord)
        from jsonb_array_elements(v -> 'bench' -> 'user_ids') with ordinality as u(e, ord)
       where u.e <> v_needle), '[]'::jsonb));
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- 한 사람의 ID 를 모든 배치 변경 이력에서 정리. 고친 줄 수를 돌려준다.
-- ---------------------------------------------------------------------------
create function private.remove_user_from_lineup_logs(p_user_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_needle jsonb := to_jsonb(p_user_id::text);
  v_count int;
begin
  update public.lineup_change_logs l
     set before = private.strip_user_from_lineup_snapshot(l.before, p_user_id),
         after = private.strip_user_from_lineup_snapshot(l.after, p_user_id)
   where l.lineup_id in (select s.lineup_id from public.lineup_slots s where s.user_id = p_user_id)
      or jsonb_path_exists(l.before, '$.squads[*].user_ids[*] ? (@ == $u)', jsonb_build_object('u', v_needle))
      or jsonb_path_exists(l.before, '$.bench.user_ids[*] ? (@ == $u)', jsonb_build_object('u', v_needle))
      or jsonb_path_exists(l.after, '$.squads[*].user_ids[*] ? (@ == $u)', jsonb_build_object('u', v_needle))
      or jsonb_path_exists(l.after, '$.bench.user_ids[*] ? (@ == $u)', jsonb_build_object('u', v_needle));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 회원 탈퇴 (202611050029 + 배치 변경 이력 정리). service_role 전용 그대로.
-- ---------------------------------------------------------------------------
create or replace function public.delete_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_blocker text;
  v_name text;
  v_team_id uuid;
begin
  -- 같은 사람의 동시 처리 방지
  perform 1 from auth.users u where u.id = p_user_id for update;
  if not found then
    raise exception 'account_not_found' using errcode = 'P0001';
  end if;

  v_blocker := public.account_deletion_blocker(p_user_id);
  if v_blocker is not null then
    raise exception '%', v_blocker using errcode = 'P0001';
  end if;

  -- 소속 팀(해체 안 된 팀)마다 팀장·운영진에게 이름이 든 탈퇴 알림 (Q-067 12번, Q-071 9번).
  -- Q-044 예외: actor_id 를 비워 탈퇴 뒤에도 이름이 남는다 (Q-072 3번). 30일 뒤 다른 알림과 같이 정리.
  select p.display_name into v_name from public.profiles p where p.user_id = p_user_id;
  if v_name is not null then
    for v_team_id in
      select m.team_id
        from public.team_members m
        join public.teams t on t.id = m.team_id
       where m.user_id = p_user_id and m.status = 'active' and t.dissolved_at is null
       order by m.team_id
    loop
      perform private.notify('member_account_deleted',
                             array_remove(private.team_staff_ids(v_team_id), p_user_id),
                             v_team_id, 'team', v_team_id, p_user_id::text,
                             null, jsonb_build_object('name', v_name));
    end loop;
  end if;

  -- 시작 전 일정의 응답을 먼저 지우고, 참석이었으면 대기 1번 자동 참석 + 알림 (2-5 절차 3, Q-038).
  -- 나머지(시작한 경기 응답 등)는 계정 삭제 연쇄로 지워진다.
  perform private.remove_upcoming_responses(p_user_id, null);

  -- 배치 변경 이력 before/after 안의 이 사람 ID 정리 (2-5, 외래 키가 걸리지 않는 기록 칸)
  perform private.remove_user_from_lineup_logs(p_user_id);

  -- TODO(로고 사진 단계): 본인 소유 저장소 파일 삭제 (1차는 개인 사진 없음)

  -- 계정을 지우면 붙은 로그인 방법(auth.identities)과 profiles 이하 모든 줄이 같이 지워진다.
  -- 이 사람 이름이 든 다른 사람의 알림(actor_id = 이 사람)도 같이 지워진다 (Q-044).
  delete from auth.users u where u.id = p_user_id;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.strip_user_from_lineup_snapshot(jsonb, uuid),
  private.remove_user_from_lineup_logs(uuid)
from public, anon, authenticated, service_role;

revoke execute on function public.delete_account(uuid) from public, anon, authenticated;
grant execute on function public.delete_account(uuid) to service_role;
