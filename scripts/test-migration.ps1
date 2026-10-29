$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location (Join-Path $root 'backend')
try {
    & (Join-Path $root '.venv/Scripts/python.exe') -c "import unittest,sys; r=unittest.TextTestRunner(verbosity=2,stream=sys.stdout).run(unittest.defaultTestLoader.discover('pgtests')); sys.exit(not r.wasSuccessful())"
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL migration tests failed.' }
}
finally { Pop-Location }
