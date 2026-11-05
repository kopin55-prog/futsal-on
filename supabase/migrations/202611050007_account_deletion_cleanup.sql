-- 회원 탈퇴와 가입 도중 그만둔 계정 정리 (data-model.md 2-1, 2-5, 11장 4·5번)
--
-- 회원 탈퇴 흐름 (supabase/functions/account-delete):
--   1) Edge Function 이 호출자 JWT 로 본인을 확인한다 (다른 사람 ID 를 받지 않음).
--   2) public.account_deletion_blocker(uid) 로 막는 이유가 없는지 먼저 본다 (팀장인 팀 등).
--   3) 계정에 붙은 로그인 방법마다 외부 서비스 연결 해제 (카카오 연결 끊기 / 구글·애플 토큰 철회).
--   4) public.delete_account(uid) 가 한 트랜잭션에서 다시 확인하고 auth.users 를 지운다
--      → profiles 와 그 아래 모든 표가 2-5 표대로 같이 삭제·비움.
-- 두 함수는 service_role(서버 함수 실행 환경)만 실행할 수 있다. 앱(authenticated)은 직접 부를 수 없다.

-- 탈퇴를 막는 이유. 없으면 null.
create function public.account_deletion_blocker(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    return 'not_authenticated';
  end if;
  -- 해체 안 된 팀의 현재 팀장이면 위임 또는 해체 후에만 (Q-037)
  if exists (
    select 1
      from public.team_members m
      join public.teams t on t.id = m.team_id
     where m.user_id = p_user_id
       and m.status = 'active'
       and m.role = 'owner'
       and t.dissolved_at is null
  ) then
    return 'owner_must_transfer_or_dissolve';
  end if;
  return null;
end;
$$;

create function public.delete_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_blocker text;
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

  -- TODO(일정 단계): 다가오는 일정의 "참석"이면 대기 1번 자동 참석 + 알림 (Q-038)
  -- TODO(팀 나누기 단계): lineup_change_logs before/after 안의 이 사람 ID 정리 (2-5)
  -- TODO(로고 사진 단계): 본인 소유 저장소 파일 삭제 (1차는 개인 사진 없음)

  -- 계정을 지우면 붙은 로그인 방법(auth.identities)과 profiles 이하 모든 줄이 같이 지워진다.
  delete from auth.users u where u.id = p_user_id;
end;
$$;

-- 프로필 없이 24시간 지난 로그인 계정 정리 (2-1). 예약 작업 전용.
-- TODO(lead 확인): 이런 계정도 카카오·구글 쪽 앱 연결이 남는다. 연결 해제가 필요한지는 12-4 테스트 후 결정.
create function private.cleanup_profileless_accounts()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  with doomed as (
    select u.id
      from auth.users u
     where u.created_at < now() - interval '24 hours'
       and not exists (select 1 from public.profiles p where p.user_id = u.id)
     limit 1000
  )
  delete from auth.users u using doomed d where u.id = d.id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.cleanup_profileless_accounts() from authenticated;
revoke execute on function
  public.account_deletion_blocker(uuid),
  public.delete_account(uuid)
from public, anon, authenticated;
grant execute on function
  public.account_deletion_blocker(uuid),
  public.delete_account(uuid)
to service_role;
