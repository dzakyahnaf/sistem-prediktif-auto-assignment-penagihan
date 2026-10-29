param([int]$Port = 8000, [ValidateSet('Auto','PostgreSQL','SQLite')][string]$DatabaseMode = 'Auto')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pythonExe = Join-Path $projectRoot '.venv/Scripts/python.exe'
$localConfig = Join-Path $projectRoot 'runtime/postgres-local.json'
if ($DatabaseMode -eq 'SQLite') {
    Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
    if (-not $env:DATABASE_PATH) { $env:DATABASE_PATH = Join-Path $projectRoot 'runtime/assignment.db' }
}
elseif (-not $env:DATABASE_URL -and ($DatabaseMode -eq 'PostgreSQL' -or (-not $env:DATABASE_PATH -and (Test-Path -LiteralPath $localConfig)))) {
    $databaseConfig = Get-Content -LiteralPath $localConfig -Raw | ConvertFrom-Json
    if ($DatabaseMode -eq 'PostgreSQL' -or $databaseConfig.active_backend -eq 'postgresql') {
        if (-not $env:DATABASE_URL) { $env:DATABASE_URL = $databaseConfig.database_url }
    }
}
if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw 'Virtual environment belum tersedia. Ikuti bagian Setup di README.md.'
}
Push-Location (Join-Path $projectRoot 'backend')
try { & $pythonExe -m uvicorn app.main:app --host 127.0.0.1 --port $Port --no-proxy-headers }
finally { Pop-Location }
