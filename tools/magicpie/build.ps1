[CmdletBinding()]
param(
    [string]$FlutterSdk = 'D:\code\works\butterfly-magicpie-toolchain\flutter',
    [string]$AndroidSdk = 'D:\code\works\butterfly-magicpie-toolchain\android-sdk',
    [string]$JavaHome = 'C:\Program Files\Microsoft\jdk-17.0.16.8-hotspot',
    [string]$CacheRoot,
    [ValidateSet('debug', 'release')]
    [string]$BuildMode = 'release',
    [switch]$SkipPubGet,
    [switch]$NativeInkExperiment
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$customCacheRoot = -not [string]::IsNullOrWhiteSpace($CacheRoot)

$flutter = Join-Path $FlutterSdk 'bin\flutter.bat'
$java = Join-Path $JavaHome 'bin\java.exe'
foreach ($required in @($flutter, $java, $AndroidSdk)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path does not exist: $required"
    }
}

$environmentNames = @(
    'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'JAVA_HOME', 'PUB_CACHE',
    'GRADLE_USER_HOME', 'USE_LEGACY_PACKAGING', 'FLUTTER_WINDOWS',
    'FLUTTER_LINUX', 'GRADLE_OPTS', 'PATH'
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$locationPushed = $false
$appDir = Join-Path $repoRoot 'app'
try {
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    $env:JAVA_HOME = $JavaHome
    $env:PUB_CACHE = if ($customCacheRoot) { Join-Path $CacheRoot 'pub' } else { 'D:\code\works\butterfly-magicpie-toolchain\pub-cache' }
    $env:GRADLE_USER_HOME = if ($customCacheRoot) { Join-Path $CacheRoot 'gradle' } else { 'D:\code\works\butterfly-magicpie-toolchain\gradle' }
    $env:USE_LEGACY_PACKAGING = 'true'
    # Disable unused desktop targets for this process so `flutter pub get`
    # does not require Windows Developer Mode to create plugin symlinks.
    $env:FLUTTER_WINDOWS = 'false'
    $env:FLUTTER_LINUX = 'false'
    # Flutter may otherwise prefer Android Studio's bundled JBR over JAVA_HOME.
    # Forward slashes avoid backslash interpretation in the Gradle JVM option.
    $gradleJavaHome = $JavaHome.Replace('\', '/')
    $javaHomeOption = "-Dorg.gradle.java.home=`"$gradleJavaHome`""
    $env:GRADLE_OPTS = (($savedEnvironment['GRADLE_OPTS'], $javaHomeOption) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    $env:PATH = "$(Join-Path $FlutterSdk 'bin');$(Join-Path $JavaHome 'bin');$env:PATH"

    New-Item -ItemType Directory -Force -Path $env:PUB_CACHE, $env:GRADLE_USER_HOME | Out-Null
    Push-Location $appDir
    $locationPushed = $true

    if (-not $SkipPubGet) {
        & $flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }
        & $flutter gen-l10n
        if ($LASTEXITCODE -ne 0) { throw "flutter gen-l10n failed with exit code $LASTEXITCODE" }
    }

    $arguments = @(
        'build', 'apk',
        "--$BuildMode",
        '--flavor', 'magicpie',
        '--dart-define=flavor=magicpie',
        '--target-platform', 'android-arm',
        '--split-per-abi'
    )
    # Flutter 3.44 also skips Android plugin registration with --no-pub.
    if ($NativeInkExperiment) {
        $arguments += '--dart-define=magicpieNativeInk=true'
    }
    # Keep build's normal preparation even when explicit pub get was skipped.
    & $flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed with exit code $LASTEXITCODE" }

    $registrant = Join-Path $appDir 'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'
    if (-not (Test-Path -LiteralPath $registrant)) {
        throw 'Android plugin registrant was not generated; APK must not be distributed.'
    }
    $registration = Get-Content -LiteralPath $registrant -Raw
    foreach ($plugin in @('com.github.dart_lang.jni.JniPlugin', 'com.github.dart_lang.jni_flutter.JniFlutterPlugin')) {
        if (-not $registration.Contains("new $plugin(")) {
            throw "Required Android plugin is not registered: $plugin"
        }
    }
} finally {
    if ($locationPushed) { Pop-Location }
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}

$apk = Join-Path $appDir "build\app\outputs\flutter-apk\app-armeabi-v7a-magicpie-$BuildMode.apk"
if (-not (Test-Path -LiteralPath $apk)) {
    throw "Expected APK was not produced: $apk"
}
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $apk
Write-Output "APK: $($hash.Path)"
Write-Output "SHA256: $($hash.Hash)"
