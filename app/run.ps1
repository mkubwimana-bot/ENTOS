<#
.SYNOPSIS
  Runs the SME-OS Flutter app without having to paste the Supabase keys each time.

.DESCRIPTION
  Resolves SUPABASE_URL and SUPABASE_ANON_KEY in this order:
    1. Existing environment variables (if already set in your shell)
    2. The git-ignored ".env.local" file next to this script (KEY=VALUE lines)
  Then launches `flutter run` with the right --dart-define values.

  Any extra arguments you pass are forwarded straight to `flutter run`, so you
  can still target a device, e.g.:
    .\run.ps1 -Device R5CR200A0NY
    .\run.ps1 -Device chrome

.EXAMPLE
  .\run.ps1
.EXAMPLE
  .\run.ps1 -Device R5CR200A0NY
.EXAMPLE
  .\run.ps1 -- -d chrome
#>

param(
  # Optional device id/name (e.g. R5CR200A0NY or chrome). Prefer this over -d
  # because PowerShell does not reliably forward bare -d to flutter run.
  [string]$Device,
  # Extra flutter run args; use "--" before them if needed, e.g. .\run.ps1 -- -d chrome
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'

# Always operate from the folder this script lives in (the Flutter app root),
# so it works no matter where you invoke it from.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Start from any values already present in the environment.
$url = $env:SUPABASE_URL
$anonKey = $env:SUPABASE_ANON_KEY

# Fill in anything missing from .env.local (KEY=VALUE, '#' lines ignored).
$envFile = Join-Path $scriptDir '.env.local'
if (Test-Path $envFile) {
  foreach ($line in Get-Content $envFile) {
    $trimmed = $line.Trim()
    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
    $eq = $trimmed.IndexOf('=')
    if ($eq -lt 1) { continue }
    $name = $trimmed.Substring(0, $eq).Trim()
    $value = $trimmed.Substring($eq + 1).Trim()
    switch ($name) {
      'SUPABASE_URL' { if ([string]::IsNullOrWhiteSpace($url)) { $url = $value } }
      'SUPABASE_ANON_KEY' { if ([string]::IsNullOrWhiteSpace($anonKey)) { $anonKey = $value } }
    }
  }
}

if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($anonKey) `
    -or $anonKey -eq 'PASTE_YOUR_REAL_ANON_KEY_HERE') {
  Write-Host @"
Missing Supabase configuration.

Create a file named ".env.local" in:
  $scriptDir
with these two lines (use your real anon key, no quotes or angle brackets):

  SUPABASE_URL=https://jurhggehykboqpjfigbt.supabase.co
  SUPABASE_ANON_KEY=<your real anon key>

A template is provided at ".env.local.example" - copy it to ".env.local".
"@ -ForegroundColor Yellow
  exit 1
}

$dartDefines = @(
  "--dart-define=SUPABASE_URL=$url",
  "--dart-define=SUPABASE_ANON_KEY=$anonKey"
)

Write-Host "Launching SME-OS (SUPABASE_URL=$url)" -ForegroundColor Cyan

$runArgs = @()
if (-not [string]::IsNullOrWhiteSpace($Device)) {
  $runArgs += '-d', $Device
}
if ($FlutterArgs) {
  $runArgs += $FlutterArgs
}

& flutter run @dartDefines @runArgs
exit $LASTEXITCODE
