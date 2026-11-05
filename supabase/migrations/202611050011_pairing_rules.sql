-- 그룹·라이벌 (data-model.md 3-7 pairing_rules, pairing_rule_members)
--
-- - 그룹 = 항상 같은 팀, 라이벌 = 항상 다른 팀. 팀 설정에 저장해두고 켜고 끈다.
-- - 읽기: 관리자만 (Q-017). 쓰기: 관리자, 서버 함수로만 (모순 검사를 건너뛰지 못하게).
-- - 켜진 설정끼리 모순이면 저장 불가: 켜진 그룹을 이어서(간접 포함) 같은 묶음이 된 두 사람이
--   켜진 라이벌 설정에 함께 들어 있으면 거절.
-- - 묶인 사람은 현재 팀원만, 2명 이상. 사람이 빠져 2명 미만이 되면 그 설정은 꺼진다(트리거,
--   팀 탈퇴·내보내기·회원 탈퇴 모두).

create type public.pairing_kind as enum ('group', 'rival');

create table public.pairing_rules (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  kind public.pairing_kind not null,
  is_enabled boolean not null,
  created_by uuid references public.profiles (user_id) on delete set null,
  updated_at timestamptz not null default now()
);

create index pairing_rules_team_idx on public.pairing_rules (team_id);

create table public.pairing_rule_members (
  rule_id uuid not null references public.pairing_rules (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  primary key (rule_id, user_id)
);

create index pairing_rule_members_user_idx on public.pairing_rule_members (user_id);

-- 사람이 빠져 2명 미만이 된 설정은 끈다 (3-7, 2-5).
create function private.pairing_rule_members_after_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.pairing_rules r
     set is_enabled = false,
         updated_at = now()
   where r.id = old.rule_id
     and r.is_enabled
     and (select count(*) from public.pairing_rule_members m where m.rule_id = old.rule_id) < 2;
  return null;
end;
$$;

create trigger pairing_rule_members_after_delete
after delete on public.pairing_rule_members
for each row execute function private.pairing_rule_members_after_delete();

-- 켜진 설정끼리 모순이 없는지 (3-7 저장 규칙).
create function private.pairing_rules_consistent(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive
    group_members as (
      select m.rule_id, m.user_id
        from public.pairing_rules r
        join public.pairing_rule_members m on m.rule_id = r.id
       where r.team_id = p_team_id and r.kind = 'group' and r.is_enabled
    ),
    edges as (
      select a.user_id as u, b.user_id as v
        from group_members a
        join group_members b on b.rule_id = a.rule_id
    ),
    reach (u, v) as (
      select e.u, e.v from edges e
      union
      select r.u, e.v from reach r join edges e on e.u = r.v
    ),
    component as (
      select r.u as user_id, min(r.v::text) as component_id from reach r group by r.u
    )
  select not exists (
    select 1
      from public.pairing_rules r
      join public.pairing_rule_members a on a.rule_id = r.id
      join public.pairing_rule_members b on b.rule_id = r.id and a.user_id < b.user_id
      join component ca on ca.user_id = a.user_id
      join component cb on cb.user_id = b.user_id
     where r.team_id = p_team_id
       and r.kind = 'rival'
       and r.is_enabled
       and ca.component_id = cb.component_id
  )
$$;

-- ---------------------------------------------------------------------------
-- 권한
-- ---------------------------------------------------------------------------
revoke all on table public.pairing_rules, public.pairing_rule_members from anon, authenticated, public;
alter table public.pairing_rules enable row level security;
alter table public.pairing_rule_members enable row level security;
grant select on table public.pairing_rules, public.pairing_rule_members to authenticated;

create policy pairing_rules_select_staff on public.pairing_rules
  for select to authenticated
  using (private.is_team_staff(team_id));

create policy pairing_rule_members_select_staff on public.pairing_rule_members
  for select to authenticated
  using (exists (
    select 1 from public.pairing_rules r
     where r.id = rule_id and private.is_team_staff(r.team_id)
  ));

-- ---------------------------------------------------------------------------
-- 서버 함수
-- ---------------------------------------------------------------------------

-- 설정을 고칠 수 있는 관리자인지 확인하고 팀 줄을 잠근다 (같은 팀 설정 변경을 한 줄로 세워 모순 검사가 엇갈리지 않게).
create function private.lock_team_as_staff(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_team_id is null or not private.is_team_staff(p_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  perform 1 from public.teams t where t.id = p_team_id for update;
end;
$$;

-- 설정 만들기·고치기. p_rule_id 가 null 이면 새로 만든다. 종류는 만든 뒤 바꿀 수 없다.
create function public.save_pairing_rule(
  p_team_id uuid,
  p_rule_id uuid,
  p_kind public.pairing_kind,
  p_user_ids uuid[],
  p_enabled boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_rule public.pairing_rules;
  v_count int;
begin
  perform private.lock_team_as_staff(p_team_id);
  if p_kind is null or p_enabled is null then
    raise exception 'invalid_pairing_rule' using errcode = 'P0001';
  end if;

  -- 2명 이상, 중복 없음, 모두 현재 팀원
  v_count := coalesce(cardinality(p_user_ids), 0);
  if v_count < 2
     or array_position(p_user_ids, null) is not null
     or (select count(distinct x) from unnest(p_user_ids) as x) <> v_count
     or (select count(*) from public.team_members m
          where m.team_id = p_team_id and m.status = 'active' and m.user_id = any (p_user_ids)) <> v_count then
    raise exception 'invalid_pairing_members' using errcode = 'P0001';
  end if;

  if p_rule_id is null then
    insert into public.pairing_rules (team_id, kind, is_enabled, created_by)
    values (p_team_id, p_kind, p_enabled, v_uid)
    returning * into v_rule;
  else
    select r.* into v_rule from public.pairing_rules r where r.id = p_rule_id and r.team_id = p_team_id;
    if v_rule.id is null then
      raise exception 'not_permitted' using errcode = 'P0001';
    end if;
    if v_rule.kind <> p_kind then
      raise exception 'invalid_pairing_rule' using errcode = 'P0001';
    end if;
    -- 사람을 먼저 바꾸고 켬·끔을 정한다 (지우는 동안 2명 미만 트리거가 끈 것을 덮어쓴다).
    delete from public.pairing_rule_members m where m.rule_id = v_rule.id;
    update public.pairing_rules set updated_at = now() where id = v_rule.id;
  end if;

  insert into public.pairing_rule_members (rule_id, user_id)
  select v_rule.id, x from unnest(p_user_ids) as x;

  update public.pairing_rules set is_enabled = p_enabled, updated_at = now() where id = v_rule.id;

  if not private.pairing_rules_consistent(p_team_id) then
    raise exception 'pairing_rule_conflict' using errcode = 'P0001';
  end if;
  return v_rule.id;
end;
$$;

-- 켜기·끄기. 켤 때는 2명 이상인지, 다른 켜진 설정과 모순이 없는지 확인한다.
create function public.set_pairing_rule_enabled(p_rule_id uuid, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team_id uuid;
begin
  select r.team_id into v_team_id from public.pairing_rules r where r.id = p_rule_id;
  perform private.lock_team_as_staff(v_team_id);
  if p_enabled is null then
    raise exception 'invalid_pairing_rule' using errcode = 'P0001';
  end if;
  if p_enabled and (select count(*) from public.pairing_rule_members m where m.rule_id = p_rule_id) < 2 then
    raise exception 'invalid_pairing_members' using errcode = 'P0001';
  end if;
  update public.pairing_rules set is_enabled = p_enabled, updated_at = now() where id = p_rule_id;
  if p_enabled and not private.pairing_rules_consistent(v_team_id) then
    raise exception 'pairing_rule_conflict' using errcode = 'P0001';
  end if;
end;
$$;

create function public.delete_pairing_rule(p_rule_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team_id uuid;
begin
  select r.team_id into v_team_id from public.pairing_rules r where r.id = p_rule_id;
  perform private.lock_team_as_staff(v_team_id);
  delete from public.pairing_rules where id = p_rule_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.save_pairing_rule(uuid, uuid, public.pairing_kind, uuid[], boolean),
  public.set_pairing_rule_enabled(uuid, boolean),
  public.delete_pairing_rule(uuid)
from public, anon;
grant execute on function
  public.save_pairing_rule(uuid, uuid, public.pairing_kind, uuid[], boolean),
  public.set_pairing_rule_enabled(uuid, boolean),
  public.delete_pairing_rule(uuid)
to authenticated;
