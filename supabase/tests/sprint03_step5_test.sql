-- 스프린트 03 5단계 마이그레이션(202611050052: notifier 재료에 팀 배치 상태) 동작 확인 스크립트.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.

create function pg_temp.check(p_ok boolean, p_label text)
returns void
language plpgsql
as $$
begin
  if p_ok is not true then
    raise exception 'check failed: %', p_label;
  end if;
end;
$$;

create function pg_temp.login(p_uid uuid)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

create temp table t_vars (k text primary key, v text);
grant all on t_vars to authenticated, anon;

create function pg_temp.vid(p_k text)
returns uuid
language sql
as $$
  select v::uuid from t_vars where k = p_k
$$;

create function pg_temp.u(p_n int)
returns uuid
language sql
as $$
  select ('00000000-0000-4000-8000-0000000005b' || p_n::text)::uuid
$$;

-- ---------------------------------------------------------------------------
-- 준비: e1 팀장. 시작했고 끝나지 않은 경기 3개 (모두 배치 없음 → 배치 미확정 알림)
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, created_at, updated_at)
values (pg_temp.u(1), 'authenticated', 'authenticated', 'a5b1@test.invalid', now(), now());

set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
insert into t_vars select 'T', public.create_team('티FC')::text;
reset role;
update public.team_members set joined_at = timestamptz '2020-01-01 00:00+09' where team_id = pg_temp.vid('T');

with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('T'), 'manual', now() - interval '30 minutes', now() + interval '90 minutes', now() - interval '3 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mC', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('T'), 'manual', now() - interval '31 minutes', now() + interval '89 minutes', now() - interval '3 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mD', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('T'), 'manual', now() - interval '32 minutes', now() + interval '88 minutes', now() - interval '3 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mN', id::text from x;

select private.close_out_attendance_votes(now());
select pg_temp.check((select count(*) = 3 from public.notifications
                       where kind = 'lineup_unconfirmed' and user_id = pg_temp.u(1)
                         and ref_id in (pg_temp.vid('mC'), pg_temp.vid('mD'), pg_temp.vid('mN'))), 'unconfirmed notices');

-- 알림이 생긴 뒤(푸시 전) mC 는 확정, mD 는 초안, mN 은 배치 없음
insert into public.lineups (match_id, team_count, players_per_team, status, confirmed_at, confirmed_by)
values (pg_temp.vid('mC'), 2, 1, 'confirmed', now(), pg_temp.u(1));
insert into public.lineups (match_id, team_count, players_per_team)
values (pg_temp.vid('mD'), 2, 1);

-- 조용한 시간이면 13:00 로 미뤄지므로 지금 보내게 당긴다
update public.notification_outbox o set send_at = now()
  from public.notifications n
 where n.id = o.notification_id and n.kind = 'lineup_unconfirmed' and n.user_id = pg_temp.u(1);

-- ---------------------------------------------------------------------------
-- 1. claim_push_batch 가 팀 배치 상태를 돌려준다
-- ---------------------------------------------------------------------------
create temp table t_claimed as select * from public.claim_push_batch(500);
select pg_temp.check((select lineup_status from t_claimed where kind = 'lineup_unconfirmed' and ref_id = pg_temp.vid('mC')) = 'confirmed',
                     'confirmed lineup status');
select pg_temp.check((select lineup_status from t_claimed where kind = 'lineup_unconfirmed' and ref_id = pg_temp.vid('mD')) = 'draft',
                     'draft lineup status');
select pg_temp.check((select count(*) = 1 and bool_and(lineup_status is null and match_ends_at is not null)
                        from t_claimed where kind = 'lineup_unconfirmed' and ref_id = pg_temp.vid('mN')), 'no lineup -> null');
select pg_temp.check((select coalesce(bool_and(lineup_status is null), true) from t_claimed where ref_type is distinct from 'match'), 'non-match rows null');

-- ---------------------------------------------------------------------------
-- 2. 권한·설정 그대로
-- ---------------------------------------------------------------------------
select pg_temp.check(has_function_privilege('service_role', 'public.claim_push_batch(int)', 'execute')
                     and not has_function_privilege('authenticated', 'public.claim_push_batch(int)', 'execute')
                     and not has_function_privilege('anon', 'public.claim_push_batch(int)', 'execute'), 'claim grants');
select pg_temp.check((select p.prosecdef and p.proconfig @> array['search_path=""']
                        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.proname = 'claim_push_batch'), 'definer search_path fixed');

select 'ALL PASSED' as result;
