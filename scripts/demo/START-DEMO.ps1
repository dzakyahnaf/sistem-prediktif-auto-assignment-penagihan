param([Parameter(Mandatory=$true)][string]$PythonExe,[int]$Port=8080)
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) { throw 'Berikan path absolut interpreter Python venv yang sudah memuat requirements.' }
& $PythonExe (Join-Path $PSScriptRoot 'run-demo.py') --port $Port
if ($LASTEXITCODE -ne 0) { throw 'Demo berhenti dengan error; periksa log terminal.' }
