# Magic Pie M1 阶段验收（2026-09-15）

> 本文保留 M1 历史结论，不代表当前版本。2026-09-16 M2 实笔流畅与实时压感已获用户确认，保存/撤销重做和电脑文件往返已通过；当前证据与未验收边界见 [NATIVE-INTEGRATION-VERIFICATION.md](NATIVE-INTEGRATION-VERIFICATION.md) 和 [PLAN-M2.md](PLAN-M2.md)。

## 结论

黑白显示适配测试包已安装、正常启动、实笔写入并保存重开。用户实笔反馈为“可以写，但是反应很慢”。**低延迟目标未达标，不能称为原厂级流畅书写版本。** 本轮未接入厂商 EPD/手写通道，M2 尚未实施；自动同步及电脑应用实际编辑也未做端到端验收。

## 构建身份

- 上游基线：Butterfly v2.5.5，`d4d3634894f7e79577e5e34866be0b010c3cfe8c`。
- 集成分支：`magicpie-monochrome`。应用代码来自 `f39360eb91c1d92f9fee6561d0a7b31461fcd5cb`，本次构建流程修复提交为 `c11b2a815`。
- 安装包：`.magicpie-output/Butterfly-MagicPie-2.5.5-armv7-jni-fix.apk`。
- SHA256：`FF2F754BCA58C6C5C0EC32EA4F6C0A7DBE3196DD72167901904D0420E6638FBC`。
- 独立包名：`dev.linwood.butterfly.magicpie`；ARMv7 / legacy native packaging；版本 2.5.5。
- 本地 debug key 回退签名，仅测试用途；未创建正式 release。原版安装未替换、未卸载。

## 已执行验证

| 项目 | 结果与证据 |
| --- | --- |
| 集成测试 | `flutter test --no-pub`：100/100 通过，见本地 `full-tests.log` |
| 静态分析 | `flutter analyze --no-pub`：No issues found，见 `analyze.log` |
| 格式/差异 | 修改的 Dart 文件格式检查通过；diff check 使用 `cr-at-eol` 识别上游 CRLF |
| 修复后构建 | `tools/magicpie/build.ps1 -SkipPubGet` 成功，见 `jni-fix-build.log` |
| 插件注册 | 构建前注册源码缺失；修复后自动生成，包含 JNI 两个插件；`apkanalyzer dex packages --defined-only` 确认 APK 含注册类与 JNI 类 |
| 安装/冷启动 | Magicpie M1，Android 8.1/API 27，`px30_eink_magicpie`；install Success；两次启动返回 ok，日志 App started，进程持续存在 |
| 首页与工具栏 | 黑白主题；笔工具调色板隐藏，线宽控件保留；见 `jni-fix-start.png`、`fixture-import.png` |
| 浅纸彩色 fixture | 原红/蓝笔显示黑色，半透明笔为灰色，青色形状显示黑色；红 PNG 保持原图内容，不进行整屏滤色 |
| 实笔输入 | 用户实际书写成功；保存数据中有变化的 pressure 值，但没有进行压力精度/延迟定量测试 |
| 保存与重开 | 点击保存生成 Documents 下的 `.bfly`；force-stop 后经文件 Intent 重开，合成图案和新写笔迹仍在；见 `fixture-reopen.png` |
| 文件非破坏性 | 拉回已保存 fixture；逐项比较两页原有元素 property 均相同（包含颜色/透明度）；PNG SHA256 与原 fixture 相同 |

日志、截图、测试文件仅在忽略目录 `.magicpie-output`，不提交个人测试笔迹或 APK 到 Git。

## 启动崩溃及修复

首个安装包 `A442D59D…` 启动在 `libdartjni.so!FindClassUnchecked` 空指针崩溃，不能使用。Flutter 3.44.9 的 `build --no-pub` 也会跳过平台注册文件生成；在缺少 `GeneratedPluginRegistrant.java` 且使用 `-SkipPubGet` 的工作区，构建仍成功，但 JNI 静态初始化从未发生。APK mapping 没有注册类，而 JNI 类本身被 keep，并非 R8 混淆导致。

修复只移除 build 的 `--no-pub`，保留正常 Flutter 平台准备步骤，并增加注册文件及 JNI 注册项校验。修复 APK 的 dex 已有注册类，真机两次启动不再出现同类崩溃。未替换第三方二进制、未更改 JNI 源码、未添加无依据的 keep 规则。

## 未通过或未验证

- **用户确认明显书写延迟，低延迟体验未通过。** 截图、ADB 模拟输入不能证明实际墨水屏延迟或刷新质量。
- 原厂快速手写、局部刷新、残影控制、抬笔合成：M2 未实现。
- 自动同步、并发编辑冲突、Windows 桌面实际打开编辑：未实测；本轮仅验证 `.bfly` 数据兼容，不等于同步验收。
- 真机撤销/重做、深纸页面、PNG/SVG/PDF 导出全流程：未完成；相关渲染/导出自动测试通过不替代真机验收。
- 测试中 USB 多次离线，尚未确认根因；不能据此断言 spacedesk 拦截。
- 构建仍有上游 NDK 版本声明不一致、字体与 deprecated API 警告；构建成功不代表未来 SDK 升级无风险。
- GitHub CI 未运行；本地已执行上述验证，最终文档提交使用 `[skip ci]`，不将其描述为 CI 通过。

下一阶段应先验证原厂手写接口是否能被普通应用调用、是否与 Flutter 画布正确同步，再制定 M2 实施与量化验收。不得在未经额外授权时刷机、root 或更换系统组件。
