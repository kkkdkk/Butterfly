# Magic Pie Android 构建

该构建产出仅面向 Magicpie M1（Android 8.1 / API 27 / `armeabi-v7a`）。`magicpie` flavor 使用独立包名 `dev.linwood.butterfly.magicpie`，安装名称为 `Butterfly for Magic Pie (Unofficial)`，不会替换 production 或 nightly 安装包。

## 环境

- Flutter 3.44.9：`D:\code\works\butterfly-magicpie-toolchain\flutter`
- JDK 17：`C:\Program Files\Microsoft\jdk-17.0.16.8-hotspot`
- Android SDK：`D:\code\works\butterfly-magicpie-toolchain\android-sdk`
- Rust/Cargo：必须已在 `PATH` 中（原生依赖需要时使用）

脚本只为当前进程设置 SDK/JDK 环境变量，不调用 `flutter config`，也不修改全局 SDK 配置。除了 `JAVA_HOME`，脚本还通过进程级 `GRADLE_OPTS=-Dorg.gradle.java.home=...` 指定 Gradle daemon 的 JDK；这是因为 Flutter 可能优先选择 Android Studio 自带的 JBR。Pub 与 Gradle 缓存默认位于 `D:\code\works\butterfly-magicpie-toolchain`；传入 `-CacheRoot` 时改用该目录下的 `pub` 和 `gradle` 子目录。Flutter/Gradle 可能在本地生成未提交的 `app/android/local.properties`。

## 构建

从仓库根目录运行：

```powershell
& .\tools\magicpie\build.ps1
```

路径均可显式覆盖：

```powershell
& .\tools\magicpie\build.ps1 `
  -FlutterSdk 'D:\path\to\flutter' `
  -AndroidSdk 'D:\path\to\Android\Sdk' `
  -JavaHome 'D:\path\to\jdk-17' `
  -CacheRoot 'D:\build-cache\butterfly-magicpie'
```

脚本依次执行 `flutter pub get`、`flutter gen-l10n` 和 ARMv7 APK 构建，并检查每一步退出码、产物路径及 SHA256。脚本仅在当前进程中设置 `FLUTTER_WINDOWS=false` 和 `FLUTTER_LINUX=false`，避免 Android-only 构建为未使用的桌面插件创建符号链接，因此当前配置不要求启用 Windows Developer Mode。Flutter 的项目级或全局 `enable-windows-desktop` / `enable-linux-desktop` 显式配置优先于环境变量；若它们被显式开启，需先移除该覆盖或启用 Windows Developer Mode。所有临时环境变量在成功或失败后都会恢复，且不会改写 Flutter 的全局配置。依赖及生成的本地化代码已经就绪时可传 `-SkipPubGet`，仅跳过前置的独立 pub get 和 gen-l10n；build 本身保留正常依赖与平台生成步骤。构建通过 `USE_LEGACY_PACKAGING=true` 启用 legacy JNI native-library packaging，并使用 `--target-platform android-arm --split-per-abi` 限定 ARMv7 产物。

不要为 build 添加 `--no-pub`：Flutter 3.44.9 同时会跳过 Android 插件注册文件生成。在干净检出且跳过前置 pub get 时，构建仍可能成功，但 APK 缺少 `GeneratedPluginRegistrant`，JNI 未初始化便会在启动时崩溃。脚本构建后检查生成文件包含 `JniPlugin` 和 `JniFlutterPlugin` 注册项；交付验收还需检查 APK dex 中的注册类及真机冷启动。

### 生成真机兼容性测试文档

依赖就绪后，从 `app` 目录执行：

```powershell
& 'D:\code\works\butterfly-magicpie-toolchain\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool/magicpie_fixture.dart ../.magicpie-output/magicpie-color-fixture.bfly
```

这是仅含合成数据的两页文档：浅色纸上红/蓝/半透明笔迹、彩色形状和红色 PNG；深色纸上白色/蓝色笔迹。脚本会验证保存再读，拒绝覆盖已有文件。用于设备导入、黑白屏显和原色导出对照，不包含个人笔记。

预期产物：

```text
app\build\app\outputs\flutter-apk\app-armeabi-v7a-magicpie-release.apk
```

## 签名与发布边界

仓库不包含签名私钥或 `key.properties`。未提供 `app/android/key.properties` 时，现有 Gradle 配置会让 release 构建回退到 Android debug key；这种 APK 仅是安装测试产物，不是正式发布签名。正式分发前必须由发布者在本机配置自己的 release keystore，妥善保管密钥，并重新记录 APK SHA256 和源码 commit。

本脚本不安装 APK、不调用 ADB。设备安装、启动、保存重开和崩溃日志检查由最终验收单独执行；构建成功不能替代真机验收。
