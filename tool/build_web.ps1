$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    node tool/configure_web_maps.cjs --check-env
    if ($LASTEXITCODE -ne 0) { throw 'Browser Maps key configuration is invalid.' }
    flutter build web --release
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
    node tool/configure_web_maps.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Browser Maps key injection verification failed.' }
} finally { Pop-Location }
