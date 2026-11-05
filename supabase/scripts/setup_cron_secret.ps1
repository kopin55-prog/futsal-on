# 정리 예약 작업용 비밀값을 만들고 등록한 뒤, 정리 서버 함수 2개를 배포한다 (개발 프로젝트 전용).
# 실행: futsal-app 폴더에서  powershell -ExecutionPolicy Bypass -File supabase\scripts\setup_cron_secret.ps1
# 비밀값은 화면·파일에 남기지 않는다 (임시 파일은 실행 직후 삭제).
# 이미 등록한 뒤 다시 실행하면 Vault 값을 새 값으로 바꾼다.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

$e = @{}
Get-Content .env.local -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.*)$') { $e[$matches[1]] = $matches[2].Trim() }
}
foreach ($k in 'SUPABASE_DEV_URL', 'SUPABASE_DEV_DB_PASSWORD', 'SUPABASE_ACCESS_TOKEN') {
  if (-not $e[$k]) { throw ".env.local에 $k 값이 없습니다" }
}
$env:SUPABASE_ACCESS_TOKEN = $e.SUPABASE_ACCESS_TOKEN
$ref = ([uri]$e.SUPABASE_DEV_URL).Host.Split('.')[0]
$pw = [uri]::EscapeDataString($e.SUPABASE_DEV_DB_PASSWORD)
$dbUrl = "postgresql://postgres.${ref}:$pw@aws-0-ap-northeast-2.pooler.supabase.com:5432/postgres"

# 64자리 무작위 비밀값
$bytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$secret = -join ($bytes | ForEach-Object { $_.ToString('x2') })

$tmp = Join-Path $env:TEMP ("futsal-cron-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
try {
  Write-Host "1/3 서버 함수 비밀값 CRON_SECRET 등록"
  "CRON_SECRET=$secret" | Set-Content -Encoding ascii "$tmp\cron.env"
  npx --yes supabase secrets set --env-file "$tmp\cron.env" --remote=$ref --yes | Out-Null; if ($LASTEXITCODE -ne 0) { throw "비밀값 등록 실패" }
  Remove-Item "$tmp\cron.env" -Force

  Write-Host "2/3 정리 서버 함수 2개 배포 (JWT 검사 끔, 함수가 CRON_SECRET으로 직접 검사)"
  foreach ($f in 'account-cleanup', 'team-logo-cleanup') {
    npx --yes supabase functions deploy $f --use-api --no-verify-jwt --remote=$ref --yes | Out-Null; if ($LASTEXITCODE -ne 0) { throw "$f 배포 실패" }
  }

  Write-Host "3/3 Vault에 cron_secret, project_url 저장"
  $sql = @"
do `$`$
begin
  if exists (select 1 from vault.secrets where name = 'cron_secret') then
    perform vault.update_secret((select id from vault.secrets where name = 'cron_secret'), '$secret');
  else
    perform vault.create_secret('$secret', 'cron_secret');
  end if;
  if not exists (select 1 from vault.secrets where name = 'project_url') then
    perform vault.create_secret('$($e.SUPABASE_DEV_URL)', 'project_url');
  end if;
end
`$`$;
"@
  $sql | Set-Content -Encoding ascii "$tmp\vault.sql"
  npx --yes supabase db query --db-url $dbUrl -f "$tmp\vault.sql" --yes | Out-Null; if ($LASTEXITCODE -ne 0) { throw "Vault 저장 실패" }
  Remove-Item "$tmp\vault.sql" -Force

  Write-Host "완료. 비밀값은 화면에 출력하지 않았습니다."
}
finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  $secret = $null
}
