[CmdletBinding()]
param(
    [string]$AndroidSdk = 'D:\code\works\butterfly-magicpie-toolchain\android-sdk',
    [string]$JavaHome = 'C:\Program Files\Microsoft\jdk-17.0.16.8-hotspot',
    [string]$GradleUserHome = 'D:\code\works\butterfly-magicpie-toolchain\gradle'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
foreach ($required in @($AndroidSdk, $JavaHome, $GradleUserHome)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path does not exist: $required"
    }
}
$gradle = Get-ChildItem -LiteralPath (Join-Path $GradleUserHome 'wrapper\dists\gradle-8.14.5-bin') `
    -Recurse -Filter 'gradle.bat' | Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($gradle)) {
    throw 'Gradle 8.14.5 is not present in the configured Gradle user home'
}

$savedAndroidHome = $env:ANDROID_HOME
$savedAndroidSdkRoot = $env:ANDROID_SDK_ROOT
$savedJavaHome = $env:JAVA_HOME
$savedGradleUserHome = $env:GRADLE_USER_HOME
try {
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    $env:JAVA_HOME = $JavaHome
    $env:GRADLE_USER_HOME = $GradleUserHome
    & $gradle -p $PSScriptRoot --no-daemon assembleDebug
    if ($LASTEXITCODE -ne 0) {
        throw "Native probe build failed with exit code $LASTEXITCODE"
    }
} finally {
    $env:ANDROID_HOME = $savedAndroidHome
    $env:ANDROID_SDK_ROOT = $savedAndroidSdkRoot
    $env:JAVA_HOME = $savedJavaHome
    $env:GRADLE_USER_HOME = $savedGradleUserHome
}

$builtApks = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'build\outputs\apk\debug') `
    -Filter '*.apk')
if ($builtApks.Count -ne 1) {
    throw "Expected exactly one APK, found $($builtApks.Count)"
}
$builtApk = $builtApks[0].FullName
$outputDir = Join-Path $repoRoot '.magicpie-output\native-probe'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$outputApk = Join-Path $outputDir 'magicpie-native-probe-debug.apk'
Copy-Item -LiteralPath $builtApk -Destination $outputApk -Force
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $outputApk
Write-Output "APK: $($hash.Path)"
Write-Output "SHA256: $($hash.Hash)"
