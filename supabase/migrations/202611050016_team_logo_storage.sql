-- 스프린트 01 4단계: 로고 사진 저장소 (data-model.md 3-1 끝 줄, 13장 S-10, Q-068 1번, Q-067 3번)
--
-- - 비공개 버킷 team-logos. 파일 경로는 "팀ID/무작위UUID.jpg|png" (추측 불가, S-10).
-- - 읽기: 로그인한 사람 누구나 — 단, 지금 어느 (해체 안 된) 팀의 로고로 쓰이는 파일만.
--   그 팀 관리자는 자기 팀 폴더의 파일을 모두 읽을 수 있다(교체·삭제 처리용).
--   → 비팀원이 폴더 목록을 봐도 지금 로고 하나만 보인다 (S-10 "목록 조회는 비팀원에게 열지 않음" 취지).
-- - 올리기: 그 팀 팀장·운영진 (경로 첫 폴더의 팀 ID 로 확인). 덮어쓰기(수정) 정책 없음 → 매번 새 파일.
-- - 지우기: 그 팀 팀장·운영진, 또는 해체된 팀의 해체 당시 팀장·운영진(해체 직후 앱이 파일을 지운다).
--   지금 로고로 쓰이는 파일은 지울 수 없다 (먼저 teams.logo_image_path 를 바꾸거나 비운다).
-- - 형식·크기: JPG·PNG, 10MB 이하 (Q-067 3번). 앱은 정사각형으로 잘라 줄이고 다시 인코딩해 위치 정보를 지운 PNG 를 올린다.
-- - storage.objects 는 SQL 로 직접 지울 수 없다(Supabase 보호 트리거) → 파일 삭제는 앱·서버 함수가 Storage API 로 한다.
--   남은 파일(교체 도중 앱 종료 등)은 team-logo-cleanup 서버 함수가 정리한다 (list_orphan_team_logos).
-- 표·칸 추가 없음 (teams.logo_image_path 기존 칸 사용). 버킷 1개는 Q-068 1번 승인.

-- ---------------------------------------------------------------------------
-- 버킷
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('team-logos', 'team-logos', false, 10485760, array['image/jpeg', 'image/png'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- 경로 규칙: "팀ID/무작위UUIDv4.jpg|png". 맞지 않으면 null.
-- ---------------------------------------------------------------------------
create function private.team_logo_path_team_id(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png)$'
    then split_part(p_name, '/', 1)::uuid
  end
$$;

-- 해체된 팀의 해체 당시 팀장·운영진인지 (해체 직후 로고 파일 삭제용)
create function private.was_staff_of_dissolved_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.team_members m
      join public.teams t on t.id = m.team_id
     where m.team_id = p_team_id
       and m.user_id = (select auth.uid())
       and m.status = 'dissolved'
       and m.role in ('owner', 'manager')
       and t.dissolved_at is not null
  )
$$;

-- 지금 해체 안 된 팀의 로고로 쓰이는 파일인지
create function private.is_current_team_logo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.teams t
     where t.logo_image_path = p_name and t.dissolved_at is null
  )
$$;

create function private.can_upload_team_logo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.is_team_staff(private.team_logo_path_team_id(p_name)), false)
$$;

create function private.can_remove_team_logo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.team_logo_path_team_id(p_name) is not null
     and (private.is_team_staff(private.team_logo_path_team_id(p_name))
          or private.was_staff_of_dissolved_team(private.team_logo_path_team_id(p_name)))
     and not exists (select 1 from public.teams t where t.logo_image_path = p_name)
$$;

create function private.can_read_team_logo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_current_team_logo(p_name)
      or (private.team_logo_path_team_id(p_name) is not null
          and (private.is_team_staff(private.team_logo_path_team_id(p_name))
               or private.was_staff_of_dissolved_team(private.team_logo_path_team_id(p_name))))
$$;

-- ---------------------------------------------------------------------------
-- storage.objects 정책 (team-logos 버킷만)
-- ---------------------------------------------------------------------------
create policy team_logos_select on storage.objects
  for select to authenticated
  using (bucket_id = 'team-logos' and private.can_read_team_logo(name));

create policy team_logos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'team-logos' and private.can_upload_team_logo(name));

create policy team_logos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'team-logos' and private.can_remove_team_logo(name));

-- ---------------------------------------------------------------------------
-- teams.logo_image_path: 자기 팀 폴더의, 실제로 올라간 파일만 가리킬 수 있다.
-- (관리자가 칸 단위 권한으로 직접 쓰므로 트리거로 확인한다.)
-- ---------------------------------------------------------------------------
create unique index teams_logo_image_path_key on public.teams (logo_image_path)
  where logo_image_path is not null;

create function private.teams_check_logo_image()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.logo_image_path is not null
     and (tg_op = 'INSERT' or new.logo_image_path is distinct from old.logo_image_path) then
    if private.team_logo_path_team_id(new.logo_image_path) is distinct from new.id
       or not exists (
         select 1 from storage.objects o
          where o.bucket_id = 'team-logos' and o.name = new.logo_image_path
       ) then
      raise exception 'invalid_logo_image' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger teams_check_logo_image
before insert or update of logo_image_path on public.teams
for each row execute function private.teams_check_logo_image();

-- ---------------------------------------------------------------------------
-- 팀 해체: 로고 사진 칸을 비운다 (3-8). 파일은 앱(해체 당시 관리자)이 바로 지우고,
-- 남으면 team-logo-cleanup 이 지운다. 나머지는 202611050014 와 같다.
-- ---------------------------------------------------------------------------
create or replace function public.dissolve_team(p_team_id uuid, p_confirm_name text)
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

  update public.teams set dissolved_at = now(), logo_image_path = null where id = p_team_id;

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
end;
$$;

-- ---------------------------------------------------------------------------
-- 남은 로고 파일 목록 (team-logo-cleanup 서버 함수 전용, 서비스 키로만 호출)
-- 어느 팀의 지금 로고도 아니고, 올린 지 1시간이 지난 파일 (올리는 도중인 파일은 건드리지 않음).
-- ---------------------------------------------------------------------------
create function public.list_orphan_team_logos(p_limit int default 100)
returns table (name text)
language sql
stable
security definer
set search_path = ''
as $$
  select o.name
    from storage.objects o
   where o.bucket_id = 'team-logos'
     and o.created_at < now() - interval '1 hour'
     and not exists (select 1 from public.teams t where t.logo_image_path = o.name)
   order by o.created_at
   limit least(greatest(coalesce(p_limit, 100), 1), 1000)
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
grant execute on function
  private.team_logo_path_team_id(text),
  private.was_staff_of_dissolved_team(uuid),
  private.is_current_team_logo(text),
  private.can_upload_team_logo(text),
  private.can_remove_team_logo(text),
  private.can_read_team_logo(text)
to authenticated;

revoke execute on function public.dissolve_team(uuid, text) from public, anon;
grant execute on function public.dissolve_team(uuid, text) to authenticated;

revoke execute on function public.list_orphan_team_logos(int) from public, anon, authenticated;
grant execute on function public.list_orphan_team_logos(int) to service_role;
