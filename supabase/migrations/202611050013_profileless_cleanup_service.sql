-- 가입 도중 그만둔 계정 정리 때 카카오 연결 해제를 먼저 시도하기 위한 서버 전용 함수 (data-model.md 2-1, Q-066 3번)
--
-- 흐름 (supabase/functions/account-cleanup, 예약 실행):
--   1) public.list_profileless_accounts(n): 프로필 없이 24시간 지난 계정 ID 목록
--   2) 계정마다 카카오 연결 끊기 시도 (실패해도 계속, Q-066 2번)
--   3) public.delete_profileless_account(uid): 그 사이 프로필이 생기지 않았는지 다시 확인하고 삭제
-- 두 함수는 service_role 만 실행할 수 있다.
--
-- Edge Function 배포 전까지는 기존 예약 작업(cleanup-profileless-accounts, 202611050008)이
-- 연결 해제 없이 지운다. 배포 후 예약 작업을 Edge Function 호출로 바꾸는 마이그레이션을 따로 만든다.

create function private.is_stale_profileless_account(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.users u
     where u.id = p_user_id
       and u.created_at < now() - interval '24 hours'
       and not exists (select 1 from public.profiles p where p.user_id = u.id)
  )
$$;

create function public.list_profileless_accounts(p_limit int)
returns table (user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id
    from auth.users u
   where u.created_at < now() - interval '24 hours'
     and not exists (select 1 from public.profiles p where p.user_id = u.id)
   order by u.created_at
   limit least(greatest(coalesce(p_limit, 100), 1), 1000)
$$;

create function public.delete_profileless_account(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1 from auth.users u where u.id = p_user_id for update;
  if not private.is_stale_profileless_account(p_user_id) then
    return false;
  end if;
  delete from auth.users u where u.id = p_user_id;
  return true;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.is_stale_profileless_account(uuid) from authenticated;
revoke execute on function
  public.list_profileless_accounts(int),
  public.delete_profileless_account(uuid)
from public, anon, authenticated;
grant execute on function
  public.list_profileless_accounts(int),
  public.delete_profileless_account(uuid)
to service_role;
