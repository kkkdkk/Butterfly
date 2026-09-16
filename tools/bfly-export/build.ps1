[CmdletBinding()]
param(
    [string]$FlutterSdk = 'D:\code\works\butterfly-magicpie-toolchain\flutter',
    [string]$PubCache = 'D:\code\works\butterfly-magicpie-toolchain\pub-cache'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$flutter = Join-Path $FlutterSdk 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) { throw "Flutter not found: $flutter" }
$previous = @{}
foreach ($key in @('PUB_CACHE','FLUTTER_WINDOWS','FLUTTER_LINUX')) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    $env:PUB_CACHE = $PubCache
    $env:FLUTTER_WINDOWS = 'false'
    $env:FLUTTER_LINUX = 'false'
    Push-Location (Join-Path $repo 'app')
    try {
        & $flutter build web --release --target lib/bfly_export_main.dart --no-web-resources-cdn --output build/bfly-export
        if ($LASTEXITCODE -ne 0) { throw "Export worker build failed: $LASTEXITCODE" }
    } finally { Pop-Location }
} finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
Write-Output "Worker: $(Join-Path $repo 'app\build\bfly-export')"
