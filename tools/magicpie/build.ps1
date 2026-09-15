[CmdletBinding()]
param(
    [string]$FlutterSdk = 'D:\code\works\butterfly-magicpie-toolchain\flutter',
    [string]$AndroidSdk = 'D:\code\works\butterfly-magicpie-toolchain\android-sdk',
    [string]$JavaHome = 'C:\Program Files\Microsoft\jdk-17.0.16.8-hotspot',
    [string]$CacheRoot,
    [ValidateSet('debug', 'release')]
    [string]$BuildMode = 'release',
    [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$customCacheRoot = -not [string]::IsNullOrWhiteSpace($CacheRoot)

$flutter = Join-Path $FlutterSdk 'bin\flutter.bat'
$dart = Join-Path $FlutterSdk 'bin\dart.bat'
$java = Join-Path $JavaHome 'bin\java.exe'
foreach ($required in @($flutter, $dart, $java, $AndroidSdk)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path does not exist: $required"
    }
}

$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:JAVA_HOME = $JavaHome
$env:PUB_CACHE = if ($customCacheRoot) { Join-Path $CacheRoot 'pub' } else { 'D:\code\works\butterfly-magicpie-toolchain\pub-cache' }
$env:GRADLE_USER_HOME = if ($customCacheRoot) { Join-Path $CacheRoot 'gradle' } else { 'D:\code\works\butterfly-magicpie-toolchain\gradle' }
$env:USE_LEGACY_PACKAGING = 'true'
$env:PATH = "$(Join-Path $FlutterSdk 'bin');$(Join-Path $JavaHome 'bin');$env:PATH"

New-Item -ItemType Directory -Force -Path $env:PUB_CACHE, $env:GRADLE_USER_HOME | Out-Null

$appDir = Join-Path $repoRoot 'app'
Push-Location $appDir
try {
    if (-not $SkipPubGet) {
        # `flutter pub get` also creates Windows desktop plugin symlinks, which
        # requires Developer Mode even though this build only targets Android.
        & $dart pub get
        if ($LASTEXITCODE -ne 0) { throw "dart pub get failed with exit code $LASTEXITCODE" }
        & $flutter gen-l10n
        if ($LASTEXITCODE -ne 0) { throw "flutter gen-l10n failed with exit code $LASTEXITCODE" }
    }

    $arguments = @(
        'build', 'apk',
        "--$BuildMode",
        '--flavor', 'magicpie',
        '--dart-define=flavor=magicpie',
        '--target-platform', 'android-arm',
        '--split-per-abi',
        '--no-pub'
    )
    & $flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

$apk = Join-Path $appDir "build\app\outputs\flutter-apk\app-armeabi-v7a-magicpie-$BuildMode.apk"
if (-not (Test-Path -LiteralPath $apk)) {
    throw "Expected APK was not produced: $apk"
}
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $apk
Write-Output "APK: $($hash.Path)"
Write-Output "SHA256: $($hash.Hash)"
