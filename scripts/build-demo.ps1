param([string]$FlutterSdk='',[switch]$Offline)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'flutter-toolchain.ps1')
$flutterExe=Resolve-ProjectFlutter -ProjectRoot $projectRoot -FlutterSdk $FlutterSdk
$previousCache=$env:PUB_CACHE
$env:PUB_CACHE=Join-Path $projectRoot '.cache/pub'
$web=Join-Path $projectRoot 'runtime/demo-web-s13'
Push-Location (Join-Path $projectRoot 'apps/assignment')
try {
    $argsPub=@('pub','get');if ($Offline) {$argsPub+='--offline'}
    & $flutterExe @argsPub
    Assert-FlutterExit 'flutter pub get'
    & $flutterExe build web --no-pub --dart-define=API_URL= --no-web-resources-cdn --output $web
    Assert-FlutterExit 'same-origin web build'
    $stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    & (Join-Path $projectRoot '.venv/Scripts/python.exe') (Join-Path $PSScriptRoot 'package-demo.py') --web $web --output (Join-Path $projectRoot "runtime/artifacts/assignment-demo-s13-$stamp")
    if ($LASTEXITCODE -ne 0) {throw 'Packaging failed.'}
}
finally {Pop-Location;$env:PUB_CACHE=$previousCache}
