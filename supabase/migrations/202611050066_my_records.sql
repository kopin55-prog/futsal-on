-- 내 기록 읽기 함수 (스프린트 04 3-1 / data-model.md v4.6 7-2·7-3·7-7, Q-058, Q-062, Q-064)
--
-- get_my_records()
--   - 본인 것만. 인자를 받지 않으므로 다른 사람·다른 팀을 고를 방법이 없다(R-04).
--   - 팀별·시즌별 한 줄: 출석 횟수·POM 1위 횟수·오늘의 골 1위 횟수(member_season_stats, 7-3)
--     + 참석 투표 대상·응답 횟수(monthly_vote_participation 월 줄을 시즌 = 연도로 합침, 7-7).
--   - 떠난 팀·해체된 팀도 포함(기록 줄이 남아 있는 팀만). 팀 이름·로고 글자·지금 소속 여부·해체 여부를 함께 준다.
--     떠난 팀은 teams 읽기 규칙으로 못 읽으므로 SECURITY DEFINER 로 본인 기록이 있는 팀의 이 칸들만 꺼낸다.
--   - 득표수 없음(award_tallies 를 보지 않는다). 퍼센트는 앱이 계산한다(소수점 없이 반올림, 대상 0회면 "기록 없음").
--   - 프로필 없는 호출자는 거절(Q-010, 다른 함수와 같음).
-- 새 표·칸 없음. 두 기록 표는 그대로 서버만 쓴다.

create function public.get_my_records()
returns table (
  team_id uuid,
  team_name text,
  logo_text text,
  is_member boolean,
  is_dissolved boolean,
  season int,
  attendance_count int,
  pom_count int,
  goal_of_the_day_count int,
  vote_eligible int,
  vote_responded int
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
  with s as (
    select m.team_id, m.season, m.attendance_count, m.pom_count, m.goal_of_the_day_count
      from public.member_season_stats m
     where m.user_id = v_uid
  ),
  v as (
    select p.team_id,
           extract(year from p.month)::int as season,
           sum(p.attendance_vote_eligible)::int as eligible,
           sum(p.attendance_vote_responded)::int as responded
      from public.monthly_vote_participation p
     where p.user_id = v_uid
     group by p.team_id, extract(year from p.month)
  ),
  j as (
    select coalesce(s.team_id, v.team_id) as team_id,
           coalesce(s.season, v.season) as season,
           coalesce(s.attendance_count, 0) as attendance_count,
           coalesce(s.pom_count, 0) as pom_count,
           coalesce(s.goal_of_the_day_count, 0) as goal_of_the_day_count,
           coalesce(v.eligible, 0) as eligible,
           coalesce(v.responded, 0) as responded
      from s
      full join v on v.team_id = s.team_id and v.season = s.season
  )
  select j.team_id,
         t.name,
         t.logo_text,
         exists (
           select 1 from public.team_members tm
            where tm.team_id = j.team_id and tm.user_id = v_uid and tm.status = 'active'
         ),
         t.dissolved_at is not null,
         j.season,
         j.attendance_count,
         j.pom_count,
         j.goal_of_the_day_count,
         j.eligible,
         j.responded
    from j
    join public.teams t on t.id = j.team_id
   order by j.team_id, j.season;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function public.get_my_records() from public, anon;
grant execute on function public.get_my_records() to authenticated;
