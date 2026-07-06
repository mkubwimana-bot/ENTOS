<#
.SYNOPSIS
  Builds a release SME-OS Android package without pasting Supabase keys each time.

.DESCRIPTION
  Resolves SUPABASE_URL and SUPABASE_ANON_KEY in this order:
    1. Existing environment variables (if already set in your shell)
    2. The git-ignored ".env.local" file next to this script (KEY=VALUE lines)
  Then runs `flutter build apk --release` (default) or `flutter build appbundle`
  with the right --dart-define values.

  Output (APK default):
    build\app\outputs\flutter-apk\app-release.apk

  Output (AppBundle):
    build\app\outputs\bundle\release\app-release.aab

.EXAMPLE
  .\build.ps1
.EXAMPLE
  .\build.ps1 -AppBundle
.EXAMPLE
  .\build.ps1 -BuildName 1.0.1 -BuildNumber 2
.EXAMPLE
  .\build.ps1 -- --split-per-abi
#>

param(
  # Build an App Bundle (.aab) for Google Play instead of an APK.
  [switch]$AppBundle,
  # Optional version name (maps to pubspec version before +).
  [string]$BuildName,
  # Optional build number (maps to pubspec version after +).
  [int]$BuildNumber,
  # Extra flutter build args; use "--" before them if needed.
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$url = $env:SUPABASE_URL
$anonKey = $env:SUPABASE_ANON_KEY

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

$buildArgs = @('build')
if ($AppBundle) {
  $buildArgs += 'appbundle', '--release'
  $outputRelative = 'build\app\outputs\bundle\release\app-release.aab'
} else {
  $buildArgs += 'apk', '--release'
  $outputRelative = 'build\app\outputs\flutter-apk\app-release.apk'
}

if (-not [string]::IsNullOrWhiteSpace($BuildName)) {
  $buildArgs += '--build-name', $BuildName
}
if ($PSBoundParameters.ContainsKey('BuildNumber')) {
  $buildArgs += '--build-number', $BuildNumber.ToString()
}

if ($FlutterArgs) {
  $buildArgs += $FlutterArgs
}

Write-Host "Building SME-OS release ($($buildArgs -join ' '))" -ForegroundColor Cyan
Write-Host "SUPABASE_URL=$url" -ForegroundColor DarkGray

& flutter @buildArgs @dartDefines
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
  exit $exitCode
}

$outputPath = Join-Path $scriptDir $outputRelative
Write-Host ""
Write-Host "Build succeeded." -ForegroundColor Green
Write-Host "Output: $outputPath" -ForegroundColor Green
if (-not $AppBundle) {
  Write-Host "Share this APK via WhatsApp (attach as Document), Drive, or adb install." -ForegroundColor DarkGray
}

exit 0
