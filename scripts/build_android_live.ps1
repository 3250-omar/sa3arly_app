param(
  [Parameter(Mandatory = $true)]
  [string]$SupabaseUrl,

  [Parameter(Mandatory = $true)]
  [string]$SupabaseAnonKey
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  throw "SupabaseUrl and SupabaseAnonKey are required."
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  if (Test-Path "E:\dev\flutter\bin\flutter.bat") {
    $env:Path = "E:\dev\flutter\bin;$env:Path"
  }
}

if (-not $env:PUB_CACHE -and (Test-Path "E:\dev\pub-cache")) {
  $env:PUB_CACHE = "E:\dev\pub-cache"
}

$appDir = Join-Path $PSScriptRoot "..\app"
Set-Location $appDir

flutter build apk --release `
  --dart-define="SUPABASE_URL=$SupabaseUrl" `
  --dart-define="SUPABASE_ANON_KEY=$SupabaseAnonKey"

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$apkPath = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"
Write-Output "APK built successfully: $apkPath"
