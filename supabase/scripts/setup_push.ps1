# 푸시 발송 준비: Firebase 서비스 계정을 서버 비밀값 FIREBASE_SERVICE_ACCOUNT 로 등록하고 notifier 서버 함수를 배포한다 (개발 프로젝트 전용).
# 실행: futsal-app 폴더에서  powershell -ExecutionPolicy Bypass -File supabase\scripts\setup_push.ps1
# 필요한 것: .env.local 의 SUPABASE_DEV_URL, SUPABASE_ACCESS_TOKEN / .secrets\firebase-service-account.json
#            (CRON_SECRET 과 Vault 의 cron_secret·project_url 은 setup_cron_secret.ps1 로 이미 등록되어 있어야 한다)
# 비밀값은 화면·파일에 남기지 않는다 (한 줄로 만든 값은 임시 파일에만 잠깐 쓰고 바로 삭제).
# 다시 실행하면 같은 값으로 덮어쓰고 다시 배포한다.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

$e = @{}
Get-Content .env.local -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.*)$') { $e[$matches[1]] = $matches[2].Trim() }
}
foreach ($k in 'SUPABASE_DEV_URL', 'SUPABASE_ACCESS_TOKEN') {
  if (-not $e[$k]) { throw ".env.local에 $k 값이 없습니다" }
}
$env:SUPABASE_ACCESS_TOKEN = $e.SUPABASE_ACCESS_TOKEN
$ref = ([uri]$e.SUPABASE_DEV_URL).Host.Split('.')[0]

$saPath = Join-Path $root '.secrets\firebase-service-account.json'
if (-not (Test-Path $saPath)) { throw ".secrets\firebase-service-account.json 파일이 없습니다 (docs/dev-accounts.md 5장 3)" }

# 한 줄 JSON: 파일의 줄바꿈만 없앤다 (JSON 안의 private_key 줄바꿈은 원래 \n 글자라 그대로 남는다).
# ConvertTo-Json 으로 다시 만들지 않는다 (PowerShell 5.1 은 일부 글자를 바꿔 적는다).
$saJson = ([IO.File]::ReadAllText($saPath, [Text.Encoding]::UTF8)).Trim([char]0xFEFF) -replace "[`r`n]", ''
$tmp = $null
try {
  $sa = $saJson | ConvertFrom-Json
  if ($sa.type -ne 'service_account' -or -not $sa.project_id -or -not $sa.client_email -or -not $sa.private_key) {
    throw "서비스 계정 파일 모양이 다릅니다 (Firebase 콘솔 > 서비스 계정 > 새 비공개 키)"
  }
  if ($saJson.Contains("'")) { throw "서비스 계정 값에 작은따옴표가 있어 env 파일로 넘길 수 없습니다" }
  Write-Host "Firebase 프로젝트: $($sa.project_id)"
  $sa = $null

  $tmp = Join-Path $env:TEMP ("futsal-push-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory $tmp | Out-Null

  Write-Host "1/3 서버 비밀값 FIREBASE_SERVICE_ACCOUNT 등록"
  # 작은따옴표로 감싸 env 파일 해석기가 값 안의 따옴표·역슬래시를 바꾸지 않게 한다
  [IO.File]::WriteAllText("$tmp\push.env", "FIREBASE_SERVICE_ACCOUNT='$saJson'`n", (New-Object Text.UTF8Encoding($false)))
  npx --yes supabase secrets set --env-file "$tmp\push.env" --remote=$ref --yes | Out-Null; if ($LASTEXITCODE -ne 0) { throw "비밀값 등록 실패" }
  Remove-Item "$tmp\push.env" -Force

  Write-Host "2/3 등록 값 확인 (값 대신 SHA-256 요약만 비교)"
  $sha = [Security.Cryptography.SHA256]::Create()
  $digest = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($saJson)) | ForEach-Object { $_.ToString('x2') })
  $list = (npx --yes supabase secrets list --remote=$ref) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "비밀값 목록 확인 실패" }
  if ($list -notmatch 'FIREBASE_SERVICE_ACCOUNT') { throw "FIREBASE_SERVICE_ACCOUNT 가 목록에 없습니다" }
  if ($list -notmatch 'CRON_SECRET') { Write-Warning "CRON_SECRET 이 없습니다. setup_cron_secret.ps1 을 먼저 실행하세요" }
  if ($list.ToLower().Contains($digest)) {
    Write-Host "   값 일치"
  } else {
    Write-Warning "목록에서 같은 값 요약을 찾지 못했습니다 (목록 표시 형식이 다를 수 있음). 배포 후 notifier 로그에 'not_configured'가 없는지 확인하세요"
  }
  $digest = $null; $list = $null

  Write-Host "3/3 notifier 서버 함수 배포 (JWT 검사 끔, 함수가 CRON_SECRET으로 직접 검사)"
  npx --yes supabase functions deploy notifier --use-api --no-verify-jwt --remote=$ref --yes | Out-Null; if ($LASTEXITCODE -ne 0) { throw "notifier 배포 실패" }

  Write-Host "완료. 비밀값은 화면에 출력하지 않았습니다. 예약 작업(notifier, 매분)이 보낼 알림이 있을 때 자동으로 부릅니다."
}
finally {
  if ($tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
  $saJson = $null
}
