-- 배치를 만든 뒤 인원 변화 자동 반영 (스프린트 03 1-6 / Q-075 3번 = S3-03 추천안)
--
-- 경기 시작 전, 그 일정에 배치(작성 중·확정 모두)가 있을 때:
--   (1) 참석자가 팀 탈퇴·내보내기    → 배치에서 자동으로 빠짐 (cleanup_departed_member)
--       회원 탈퇴                      → 명단 줄이 계정 삭제 연쇄로 같이 지워짐 (5-3)
--   (2) 대기 1번이 자동 참석          → 교체 블록에 자동으로 들어감 (attendance_responses 트리거)
--   (3) 운영진이 게스트 추가          → 교체 블록에 자동으로 들어감 (match_guests 트리거)
--   (4) 게스트 삭제                  → 명단 줄이 외래 키로 같이 지워짐 (202611050037)
-- 자동 변화에는 배치 변경 알림을 보내지 않고, 버전·변경 이력도 남기지 않는다 (운영진의 수정이 아님).
-- "교체 블록에 N명" 경고는 운영진이 배치 화면을 열 때 앱이 센다.
-- (1)~(3)은 배치의 updated_at 을 바꿔, 그 전에 불러온 화면의 저장은 lineup_conflict 로 다시 불러오게 한다.
-- 경기 시작 뒤에는 (1)만 생길 수 있고 배치에는 남는다 (출석·투표 대상에서 빼는 것은 4단계, Q-061 6번).

-- ---------------------------------------------------------------------------
-- 교체 블록에 넣기 (시작 전 일정의 배치가 있고 아직 명단에 없을 때만)
-- ---------------------------------------------------------------------------
create function private.add_to_lineup_bench(p_match_id uuid, p_user_id uuid, p_guest_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lineup_id uuid;
begin
  select l.id into v_lineup_id
    from public.lineups l
    join public.matches m on m.id = l.match_id
   where l.match_id = p_match_id
     and m.status = 'scheduled'
     and m.starts_at > now();
  if v_lineup_id is null then
    return;
  end if;

  insert into public.lineup_slots (lineup_id, squad_id, user_id, guest_id, as_goalkeeper)
  values (v_lineup_id, null, p_user_id, p_guest_id, false)
  on conflict do nothing;
  if found then
    update public.lineups l set updated_at = clock_timestamp() where l.id = v_lineup_id;
  end if;
end;
$$;

-- (2) 대기 → 참석 자동 전환
create function private.attendance_promoted_to_lineup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.add_to_lineup_bench(new.match_id, new.user_id, null);
  return null;
end;
$$;

create trigger attendance_promoted_to_lineup
after update of state on public.attendance_responses
for each row
when (old.state = 'waitlisted' and new.state = 'attending')
execute function private.attendance_promoted_to_lineup();

-- (3) 게스트 추가
create function private.guest_added_to_lineup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.add_to_lineup_bench(new.match_id, null, new.id);
  return null;
end;
$$;

create trigger guest_added_to_lineup
after insert on public.match_guests
for each row execute function private.guest_added_to_lineup();

-- ---------------------------------------------------------------------------
-- (1) 팀 탈퇴·내보내기 공통 정리 (202611050025 + 시작 전 배치에서 빼기)
-- ---------------------------------------------------------------------------
create or replace function private.cleanup_departed_member(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.skill_ratings s
   where s.team_id = p_team_id and s.user_id = p_user_id;

  delete from public.pairing_rule_members m
   using public.pairing_rules r
   where r.id = m.rule_id and r.team_id = p_team_id and m.user_id = p_user_id;

  -- 시작 전 일정의 배치에서 빼기 (Q-075 3번). 시작한 경기의 배치에는 남는다.
  with removed as (
    delete from public.lineup_slots s
     using public.lineups l, public.matches m
     where s.lineup_id = l.id and l.match_id = m.id
       and m.team_id = p_team_id and m.starts_at > now()
       and s.user_id = p_user_id
    returning s.lineup_id
  )
  update public.lineups l
     set updated_at = clock_timestamp()
   where l.id in (select r.lineup_id from removed r);

  -- 시작 전 일정 응답 삭제, 참석이었으면 대기 1번 자동 참석 (3-8, Q-038, Q-071 5번)
  -- → 자동 참석한 사람은 위 트리거로 교체 블록에 들어간다
  perform private.remove_upcoming_responses(p_user_id, p_team_id);
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.add_to_lineup_bench(uuid, uuid, uuid),
  private.attendance_promoted_to_lineup(),
  private.guest_added_to_lineup(),
  private.cleanup_departed_member(uuid, uuid)
from authenticated, service_role;
