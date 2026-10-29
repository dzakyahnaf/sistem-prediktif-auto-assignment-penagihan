function Resolve-ProjectFlutter {
    param([string]$ProjectRoot, [string]$FlutterSdk = '')
    if ($FlutterSdk) {
        $candidate = Join-Path $FlutterSdk 'bin/flutter.bat'
        if (-not (Test-Path -LiteralPath $candidate)) { throw "SDK Flutter tidak ditemukan: $candidate" }
        return $candidate
    }
    $localSdk = Join-Path $ProjectRoot '.tools/flutter/bin/flutter.bat'
    if (Test-Path -LiteralPath $localSdk) { return $localSdk }
    $command = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw 'Flutter belum tersedia. Sediakan SDK di .tools/flutter atau gunakan parameter -FlutterSdk.'
}

function Assert-FlutterExit {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) { throw "$Step gagal (exit $LASTEXITCODE). Langkah berikutnya tidak dijalankan." }
}
