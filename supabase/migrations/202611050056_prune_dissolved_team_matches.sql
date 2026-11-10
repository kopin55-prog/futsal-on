-- 해체된 팀의 남은 일정 정리 (스프린트 03 7-3 후속 / Q-061 4번, lead 결정 2026-11-10)
--
-- 해체 처리(202611050054)는 종료 시각이 지난 일정만 지운다. 남는 일정:
--   - 해체 때 진행 중이던 경기 → 경기 종료 처리(closed_out_at, 팀 월간 경기 수만 +1) 뒤에 지움
--   - 해체로 취소된 다가오는 일정(그 전에 취소된 것 포함) → 바로 지움
-- 하루 1회 정리(private.prune_old_matches)에서 해체 팀마다 같이 처리한다.
-- 투표 회차가 있으면 closed 일 때만 지운다(해체 팀은 투표가 열리지 않지만 7-5 조건을 그대로 지킴).
-- 팀 월간 경기 수·개인 카운트·월간 숫자는 남는다.

create function private.prune_dissolved_team_matches(p_team_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match public.matches;
  v_poll_status public.award_poll_status;
  v_count int := 0;
begin
  if not exists (select 1 from public.teams t where t.id = p_team_id and t.dissolved_at is not null) then
    return 0;
  end if;

  for v_match in
    select m.*
      from public.matches m
     where m.team_id = p_team_id
       and (m.status = 'cancelled' or m.closed_out_at is not null)
     order by m.ends_at, m.id
     for update skip locked
  loop
    if v_match.status = 'scheduled' then
      if v_match.closed_out_at is null then
        continue;
      end if;
      select p.status into v_poll_status
        from public.award_polls p
       where p.match_id = v_match.id
         for update;
      if found and v_poll_status <> 'closed' then
        continue;
      end if;
    end if;

    delete from public.matches m where m.id = v_match.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- 하루 1회 정리 (202611050053) + 해체 팀
create or replace function private.prune_old_matches(p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_count int := 0;
begin
  for v_team_id in
    select m.team_id
      from public.matches m
     where m.status = 'scheduled'
       and m.ends_at <= p_now
     group by m.team_id
    having count(*) >= 10
     order by m.team_id
  loop
    v_count := v_count + private.prune_team_matches(v_team_id, p_now);
  end loop;

  for v_team_id in
    select t.id
      from public.teams t
     where t.dissolved_at is not null
       and exists (select 1 from public.matches m where m.team_id = t.id)
     order by t.id
  loop
    v_count := v_count + private.prune_dissolved_team_matches(v_team_id);
  end loop;
  return v_count;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.prune_dissolved_team_matches(uuid),
  private.prune_old_matches(timestamptz)
from public, anon, authenticated, service_role;
