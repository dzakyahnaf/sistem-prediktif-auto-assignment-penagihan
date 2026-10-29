param([string]$FlutterSdk = '', [switch]$Offline)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'flutter-toolchain.ps1')
$flutterExe = Resolve-ProjectFlutter -ProjectRoot $projectRoot -FlutterSdk $FlutterSdk
$priorPubCache = $env:PUB_CACHE
$env:PUB_CACHE = Join-Path $projectRoot '.cache/pub'
Push-Location (Join-Path $projectRoot 'apps/assignment')
try {
    $pubArgs = @('pub', 'get')
    if ($Offline) { $pubArgs += '--offline' }
    & $flutterExe @pubArgs
    Assert-FlutterExit 'flutter pub get'
    & $flutterExe analyze
    Assert-FlutterExit 'flutter analyze'
    & $flutterExe test
    Assert-FlutterExit 'flutter test'
    & $flutterExe build web --dart-define=API_URL=http://127.0.0.1:8000
    Assert-FlutterExit 'flutter build web'
}
finally { Pop-Location; $env:PUB_CACHE = $priorPubCache }
