param([string]$FlutterSdk = '', [string]$Device = 'emulator-5554', [string]$ApiUrl = 'http://10.0.2.2:8000', [Parameter(Mandatory=$true)][string]$UatConfig, [switch]$NativeFiles)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'flutter-toolchain.ps1')
$flutterExe = Resolve-ProjectFlutter -ProjectRoot $projectRoot -FlutterSdk $FlutterSdk
$config = Get-Content -LiteralPath $UatConfig -Raw | ConvertFrom-Json
if ($config.schema -notmatch '^uat_s(11|13)_[a-f0-9]{12}$') { throw 'Hanya schema UAT native/penerimaan yang disiapkan script proyek.' }
Write-Output 'Pastikan backend aktif memakai URL privat dari UatConfig yang sama. Tes membuat kasus dan transaksi sintetis melalui UI.'
$priorCache = $env:PUB_CACHE
$env:PUB_CACHE = Join-Path $projectRoot '.cache/pub'
Push-Location (Join-Path $projectRoot 'apps/assignment')
try {
    $target = if ($NativeFiles) { 'integration_test/native_files_test.dart' } else { 'integration_test/workflows_test.dart' }
    & $flutterExe test $target -d $Device --flavor demo "--dart-define=API_URL=$ApiUrl" --dart-define=UAT_ISOLATED=true
    Assert-FlutterExit 'Flutter native UAT'
}
finally { Pop-Location; $env:PUB_CACHE = $priorCache }
