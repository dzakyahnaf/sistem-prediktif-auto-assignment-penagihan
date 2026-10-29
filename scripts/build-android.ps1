param([string]$FlutterSdk = '', [string]$ApiUrl = 'http://10.0.2.2:8000', [switch]$Offline)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'flutter-toolchain.ps1')
$flutterExe = Resolve-ProjectFlutter -ProjectRoot $projectRoot -FlutterSdk $FlutterSdk
$uri = [Uri]$ApiUrl
if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'API URL harus origin HTTP(S) tanpa credential/query/fragment.' }
if ($uri.Scheme -eq 'http' -and $uri.Host -notin @('10.0.2.2','127.0.0.1','localhost')) { throw 'HTTP APK demo dibatasi ke emulator/loopback. Gunakan HTTPS untuk server lain.' }
$priorCache = $env:PUB_CACHE
$env:PUB_CACHE = Join-Path $projectRoot '.cache/pub'
Push-Location (Join-Path $projectRoot 'apps/assignment')
try {
    $pubArgs = @('pub','get'); if ($Offline) { $pubArgs += '--offline' }
    & $flutterExe @pubArgs
    Assert-FlutterExit 'flutter pub get'
    & $flutterExe build apk --debug --flavor demo --target lib/main.dart "--dart-define=API_URL=$ApiUrl" --no-pub
    Assert-FlutterExit 'flutter build apk demo'
    $artifacts = Join-Path $projectRoot 'runtime/artifacts'
    New-Item -ItemType Directory -Path $artifacts -Force | Out-Null
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $destination = Join-Path $artifacts "assignment-demo-debug-$stamp.apk"
    if (Test-Path -LiteralPath $destination) { throw 'Berkas artefak sudah ada; tidak ditimpa.' }
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-demo-debug.apk' -Destination $destination
    Get-FileHash -LiteralPath $destination -Algorithm SHA256
}
finally { Pop-Location; $env:PUB_CACHE = $priorCache }
