# Magicpie M1 墨水屏书写：问题与解决手册

更新：2026-09-16。用途：以后在**这块设备**上开发书写功能时，先按现象定位，再复用已经验证的最小实现；不必重跑全部失败实验。

适用基线：Magicpie M1，`DEVICE=px30_eink_magicpie`，Android 8.1/API 27，PX30、ARMv7；本项目使用 Flutter 3.44.9。设备固件、Flutter embedding 或系统库更换后，必须重新验证，不能把以下结论推广到所有墨水屏。

## 1. 从这里开始

当前通过的路线是：**连续原生快写会话 + 同步逐采样调整笔宽 + Android buffered 笔输入及 history 展开 + Flutter 独立保存文档**。

- 原生系统库负责屏幕上的低延迟预览；Flutter 负责笔迹模型、压力、历史、保存和跨端编辑。
- 正常原生模式不逐笔 `capture → stop → setup → start → renderRect`。这条旧交接路径仅保留作显式 `handoff` 诊断，不能当作推荐实现复制。
- 用户已确认“很流畅，并且粗细都实时显示了”；保存、撤销/重做、电脑编辑后回平板重开也已验证。此结论不等于延迟已定量达标、所有生命周期或长期残影已通过。
- 跨项目优先复用设备/JNI 边界、输入兼容和实机验证方法；Flutter 专有的 foreground、renderer、replay 保存修复需要结合新项目架构处理。

版本定位：`634daef9e` 是连续快写、输入兼容和实时压感检查点；`a7604a939` 是撤销/重做保存修复；`de918be91` 记录真机与电脑往返验收。历史逐轮证据见 [NATIVE-INTEGRATION-VERIFICATION.md](NATIVE-INTEGRATION-VERIFICATION.md)，不是按文件顶部的早期实验状态判断当前方案。

## 2. 按症状快速定位

| 现象 | 先检查什么 | 已验证的处理方式/边界 |
| --- | --- | --- |
| ADB 无设备，或连接但不能操作 | `adb devices -l`；USB直连；屏幕电源状态；是否连接到目标设备 | USB重新连接与应用休眠分开查。用户曾怀疑 spacedesk 拦截，但本手册没有受控实验将其确认为所有断连的根因；不要直接重刷或改系统权限。 |
| APK构建成功，打开即崩溃 | `GeneratedPluginRegistrant`、JNI插件注册、crash buffer | Flutter 3.44.9 的 build 不加 `--no-pub`；构建脚本保留平台生成步骤，检查 JNI 注册，再冷启动验收。 |
| `prepared=false`，默认笔也不启动 | 编译开关、诊断参数、工具分类、设备/API守卫、FlutterView查找 | 默认笔看 `activeTool`，不要被空映射误挡；release中用 `instanceof FlutterView`，不能依赖会被R8混淆的类名字符串。 |
| 探针没墨，但之前能写 | `started`、前后台状态、是否按 Start | 探针暂停会清理且不会自动恢复；先按 **Start native ink**。不能把 `started=false` 当压感算法失败。 |
| 首笔约15秒后取消，之后退回慢笔 | `InputDispatcher` stale events、DOWN→CANCEL、`requestUnbufferedDispatch` | 本固件单变量探针复现；目标设备的stylus/eraser手势改走buffered转发，保留Flutter标准事件转换。 |
| 原生写得完整，保存后点很少/曲线不对 | Android当前事件+history、Flutter MOVE数、最终文档点数 | 显式展开history，最后只发送一次当前事件；不能只看native回调数。 |
| 落笔有墨，随后消失/空心，下一笔才补全上一笔 | 是否仍在每笔capture/present；是否输入取消；快照新旧 | 有旧空白PixelCopy直接证据，但改PNG交接仍失败；最终采用连续native会话，正常模式跳过逐笔交接。 |
| 流畅但等宽，停笔几秒后才变粗细 | 原生笔刷是否固定宽度；压力是否已进入文档 | 压力数据不等于实时压力外观。valid DOWN/MOVE同步native回调内更新 `setBrush`；不是等Flutter最终重绘。 |
| 调用renderRect后下一笔画不出/变慢 | 诊断路径的brush状态和调用顺序 | 该设备库的render_rect会清brush标志；诊断交接后恢复setBrush。不能据此重新启用已失败的逐笔交接。 |
| CANCEL后后续笔异常/一直待提交 | 活动pointer、笔画缓存、pending状态、清理异常 | 只丢取消的未提交笔；保留已提交及其他pointer。view用try/finally清理输入状态，不把半笔强行提交。 |
| 撤销视觉生效但文件没变/重开又回来了 | replay是否标脏；save的saved早退；自动保存配置 | undo/redo后标unsaved并触发既有autosave；force只跳过普通saved，不越过absoluteRead。 |
| 多笔频繁全刷/二次绘制 | Flutter活动前景、逐点refresh、bake、逐笔位图交接 | 原生期间抑制重复活动前景和逐点刷新，保留数据提交；没有验证出适用于所有场景的全刷阈值，不能禁掉全部必要刷新。 |

## 3. 已证实原因与不能混淆的结论

### 3.1 首笔输入积压：避免在本固件请求unbuffered

独立探针不包含Flutter引擎和文档交接，两组都消费画布触摸，只改变 `requestUnbufferedDispatch`：

- false组：两笔正常UP，CANCEL=0，累计history=421。
- true组：第一笔DOWN后约15.5秒CANCEL，`MOVE outstanding 15519.9 ms`，丢弃stale事件；后续笔可正常。
- true组屏幕线条仍保留，因为探针CANCEL不停止native。因此“探针看起来流畅”不等于Android事件完整。

修复入口：[MainActivity.java](../../app/android/app/src/main/java/dev/linwood/butterfly/MainActivity.java) 的 `onCreate`。

仅controller存在、API27、DEVICE匹配时，在同一个FlutterView上接管由stylus/eraser发起的完整DOWN→UP/CANCEL手势，调用 `AndroidTouchProcessor(renderer, false)`；不要再进入FlutterView的unbuffered请求。同一手势归属固定，多指混入不临时切换；手指起始手势仍走原路。坐标保持view-local，不做第二次偏移。

注意：当前输入守卫只按DEVICE，controller还接受MODEL回退。移植到改名设备前应显式审查这一差异，不要无条件启用兼容层。

### 3.2 Buffered输入必须展开history

修复前一笔Android 737个样本、history714，文档只有22点；另一笔132样本只有6点。仅恢复普通MOVE转发不够。

[BufferedStylusInput.java](../../app/android/app/src/main/java/dev/linwood/butterfly/BufferedStylusInput.java) 的 `dispatch`：

1. 对MOVE和UP按原历史时间顺序生成MOVE，保留每个pointer的properties、coords、pressure、axes及事件metadata。
2. 每个合成事件使用 `finally` recycle；最后只转发一次原事件。
3. CANCEL不重放历史来“补交”笔迹；不重复native审计，也不重新打开unbuffered。

修复后实笔Android527样本，对应Flutter525 MOVE加DOWN/UP；文档511点仍可能由既有同坐标去重减少，不能要求文档点数与原始事件数机械相等。独立设备Instrumentation 3项通过，入口见第6节。

### 3.3 笔迹消失：旧buffer是一个原因，但不是全部

直接证据：operation26首次PixelCopy脏区 `darkPixels=0`；无新笔/新会话时约223ms后二次只读截图 `darkPixels=4119`。`endOfFrame`不保证SurfaceView已经提供最新raster buffer。

后来改为 `RepaintBoundary.toImage` 光栅PNG交接，并加新笔/会话代号守卫，**用户仍反馈消失**。因此不能只记成“等一帧/换PNG就解决了”。系统截图有实心线，也不能否认物理墨水屏上的空心/消失反馈。

控制输入积压后，同一APK的handoff组仍消失，commit-only组连续9笔无CANCEL、无消失。采用的稳定路径：

- Dart `NativeInkSession.presentAfterFrame` 在normal/commit-only不capture/present。
- Android `present` 在非显式handoff诊断下拒绝逐笔交接。
- 保持原生会话连续；不把UP当作每笔stop/destroy/setup的理由。
- 原生只替代活动预览，Flutter提交和最终renderer仍存在，文档数据不能省掉。

涉及文件：[helpers/native_ink.dart](../../app/lib/helpers/native_ink.dart)、[views/native_ink.dart](../../app/lib/views/native_ink.dart)、[MagicpieNativeInkController.java](../../app/android/app/src/magicpie/java/dev/linwood/butterfly/magicpie/MagicpieNativeInkController.java)。

这里隔离的是一整组capture/重启/呈现行为；不能声称所有物理消失都已精确归因到其中单个JNI调用。

### 3.4 实时压感：在native画当前点之前改笔宽

固定 `setBrush(4,0,true)` 能快写但等宽，Flutter稍后按真实pressure重绘，造成“停笔后才加粗”。真实pressure早已存在，继续修改归一化不解决实时预览。

对本设备系统库的互操作调查确认：native输入线程同步回调Java，回调返回后才用当前brush width绘制本采样。探针验证后，主程序 `onNativeEvent(sessionInk,event)` 采用：

```text
valid且pressure有限，action为DOWN/MOVE：
  width = round(2 + 12 * clamp(pressure, 0, 1))
  sessionInk.setBrush(width, 0, true)
UP不把宽度清零。
```

- 直接在同步回调执行，不post到主线程，不逐点renderRect，不重启会话。
- listener捕获本次 `sessionInk`，不使用可能已指向新会话的全局引用。
- 2–14是设备像素的已验证预览映射，不等于Butterfly最终笔刷算法；strokeWidth、thinning、zoom匹配尚未完整实现/验收。
- `setBrush`的bool不能按名字猜成压力开关。曾移除brush调用后探针无法书写，恢复后正常。
- 此设备库 `render_rect` 会清brush标志，诊断路径在renderRect后恢复brush；库换版必须重查，不能把反汇编地址当稳定ABI。

用户先在探针确认粗细“当场变化”，再在主程序确认流畅、实时粗细；两次验收不能用日志或单元测试替代。

### 3.5 Flutter提交、取消和恢复

- [pen.dart](../../app/lib/handlers/pen.dart)：活动点回写与按帧合并修复普通预览，但单独这一层曾被用户确认仍慢，不能代替原生快写。
- native模式不重复绘制活动foreground、不逐MOVE刷新；保留输入、压力、ElementsCreated。最终renderer插入后才清submitted，避免早到的viewport更新吃掉完成回调。
- `onPointerCancel`只清对应活动pointer；[view.dart](../../app/lib/views/view.dart) 的取消清理用try/finally。CANCEL不是UP，不能为了让文件有笔迹而强制提交。
- [NativeInkViewport](../../app/lib/views/native_ink.dart) prepare/present失败后标记待重试，在安全的后续UP重新评估；旧请求/旧配置的回调不能覆盖新会话。不要缓存一次失败后永久禁用，也不要落笔中无限重启。

### 3.6 撤销/重做后的保存

`replay_bloc`的undo/redo不走普通DocumentEvent保存路径；原先视觉状态变了但SaveState仍为saved，force保存也被早退。真机文件哈希不变，新增回归复现后修复：

- [document_bloc.dart](../../app/lib/bloc/document_bloc.dart)：覆写 `undo/redo`，历史可用才执行；`_markReplayChanged` 标unsaved，`keepRead:true`，按已有配置触发autosave。
- [current_index.dart](../../app/lib/cubits/current_index.dart)：锁外/锁内两处saved早退都尊重force，但absoluteRead仍阻止原地保存。显式新location的Save As保持原语义。
- 只读标志本来编码在SaveState中，其他普通编辑可能改变它；这里不是对所有只读语义的重新设计。
- 默认延迟autosave期间显示Save delayed可以正常；验收必须等保存完成再检查实际文件。

真机96笔→Undo保存95笔→Redo保存96笔，全部元素及10,106压力采样一致；force-stop重开仍一致。电脑端原94笔→新增1笔→导出95笔，数字规范化后原94元素完全一致。

`.bfly`是归档文件：本版本页面在 `BFLY/pages/*.json`，元素在 `page.layers[].content`，**不是page.content**。跨Dart/Web比较JSON时要规范化数字表示（如5.0与5），不要只比ZIP字节或序列化文本；还要比点、压力、属性和资产内容。文件传递通过不等于WebDAV同步通过。

## 4. 源码与回归入口

| 组件 | 路径（仓库根目录相对路径） |
| --- | --- |
| JNI互操作声明，无厂商实现 | `app/android/app/src/magicpie/java/com/yitoa/rk/handwriting3/HandWritingNative.java`、`HandWritingEvent.java` |
| native会话/pressure/诊断 | `app/android/app/src/magicpie/java/dev/linwood/butterfly/magicpie/MagicpieNativeInkController.java` |
| 输入buffered接管/history | `app/android/app/src/main/java/dev/linwood/butterfly/MainActivity.java`、`BufferedStylusInput.java` |
| Flutter桥接及viewport恢复 | `app/lib/helpers/native_ink.dart`、`app/lib/views/native_ink.dart` |
| 活动笔、提交、取消 | `app/lib/handlers/pen.dart`、`app/lib/views/view.dart` |
| 保存与历史 | `app/lib/bloc/document_bloc.dart`、`app/lib/cubits/current_index.dart` |
| 黑白显示与原色数据隔离 | `app/lib/helpers/eink.dart`、`app/test/eink/render_compatibility_test.dart` |
| 原生独立探针 | `tools/magicpie/native_probe/`，先读其README；不提供笔记存档 |
| 历史样本设备回归 | `tools/magicpie/native_probe/src/androidTest/java/dev/linwood/butterfly/BufferedStylusInputTest.java` |
| 桥接、恢复、取消/提交、保存回归 | `app/test/eink/native_ink_test.dart`、`native_ink_viewport_test.dart`；`app/test/handlers/native_pen_commit_test.dart`；`app/test/bloc/undo_save_state_test.dart` |

## 5. 最短排查流程与诊断模式

1. **固定基线**：记录源码commit、APK SHA256、设备/API、启动模式；确认屏幕唤醒、默认笔选中、日志native ready。先复现一笔，不同时改压力、刷新和输入。
2. **分层数事件**：Android DOWN/MOVE/UP/CANCEL+history → Flutter MOVE → ElementsCreated点数/pressure → 文件保存结果。native callback不是第二份文档输入源。
3. **分开验收外观**：落笔即时显示、笔未抬起时粗细变化、UP后5秒不消失、下一笔不触发上一笔补全。肉眼/用户反馈决定物理显示是否通过。
4. **隔离交接**：仅当确需重新研究时比较以下三模式，先解决输入CANCEL混杂因素，再判断交接。
5. **持久化与恢复**：一次Undo整笔、Redo、保存、冷启动、电脑打开编辑/导出/平板重开；再补切页、缩放、旋转、休眠恢复和长时间残影。

| 显式诊断模式 | 做什么 | 不能据此宣称什么 |
| --- | --- | --- |
| `record-only` | native快写，合格笔手势不送Flutter，仅记录 | 不创建笔记，不能验收保存；不可拿个人笔记测试后期待自动保存。 |
| `commit-only` | native连续预览+Flutter输入/提交，无逐笔capture/present | 这才是当前已通过的诊断对照路线；仍不是全场景产品认证。 |
| `handoff` | 完整逐笔光栅快照与native重启/呈现 | 保留失败路径作研究，不是默认推荐。 |

诊断编译开关与启动extra缺一不可；未知或缺失模式会拒绝诊断启动。诊断记录器可能把原始坐标/pressure写进应用 `externalFiles/ink-diagnostics`，只用合成测试，不提交用户笔迹。常规日志只保留汇总、计数与范围。

## 6. 可复制的命令（手动执行，不自动更改设备）

PowerShell，仓库根目录 `D:\code\works\butterfly-magicpie`；`C:\adb\adb.exe` 是本机工具位置。先 `devices -l`，多设备时所有命令指定目标 `-s`。

```powershell
& C:\adb\adb.exe devices -l
& C:\adb\adb.exe shell getprop ro.product.device
& C:\adb\adb.exe shell getprop ro.build.version.sdk
& C:\adb\adb.exe shell dumpsys power | Select-String 'mWakefulness|Display Power'
& C:\adb\adb.exe logcat -d -b crash -t 100
& C:\adb\adb.exe logcat -d -t 3000 | Select-String 'MagicpieInk|MagicpieNativeInk|MagicpieNativeProbe|InputDispatcher'
```

构建当前诊断路线，安装仍由开发者单独确认目标后执行（详见 [BUILD.md](BUILD.md)）：

```powershell
& .\tools\magicpie\build.ps1 -SkipPubGet -NativeInkExperiment -NativeInkDiagnostics
Get-FileHash .\app\build\app\outputs\flutter-apk\app-armeabi-v7a-magicpie-release.apk
```

`-SkipPubGet`只跳过前置独立pub get，不等于给build加 `--no-pub`。省略NativeInkExperiment会关闭native功能；只传NativeInkExperiment、不传Diagnostics时使用normal连续会话，仍需按该实际产物验证。

**确认测试文件已保存之后**冷启动。以下 `/local/` 文件名是占位示例，要换成真实的受控测试文件；不要在重开验收时用 `/new`：

```powershell
& C:\adb\adb.exe shell am force-stop dev.linwood.butterfly.magicpie
& C:\adb\adb.exe shell am start -n dev.linwood.butterfly.magicpie/dev.linwood.butterfly.MainActivity --es magicpieInkDiagnostic commit-only --es route /local/controlled-test.bfly
```

探针同期退出主程序以免两个native使用者冲突，使用其独立包，启动后必须手动按Start：

```powershell
& C:\adb\adb.exe shell am start -n dev.linwood.butterfly.magicpie.probe/.MainActivity --ez unbufferedInput false --ez nativePressure true
```

测unbuffered A/B时每组先保存主程序数据、退出主程序并force-stop探针，使用同一APK和相同画法，仅改变 `unbufferedInput`；不是同时更改nativePressure和多项设置。

Flutter回归在 `app` 目录执行；这些test/analyze可以使用 `--no-pub`：

```powershell
$env:PUB_CACHE = 'D:\code\works\butterfly-magicpie-toolchain\pub-cache'
& D:\code\works\butterfly-magicpie-toolchain\flutter\bin\flutter.bat test --no-pub
& D:\code\works\butterfly-magicpie-toolchain\flutter\bin\flutter.bat analyze --no-pub
& D:\code\works\butterfly-magicpie-toolchain\flutter\bin\flutter.bat test --no-pub --dart-define=magicpieNativeInk=true --dart-define=magicpieNativeInkDiagnostics=true test/eink/native_ink_test.dart test/eink/native_ink_viewport_test.dart test/handlers/native_pen_commit_test.dart
```

以下设备回归要求独立probe和androidTest APK都已构建安装；普通probe的build脚本不等于已安装测试APK：

```powershell
& C:\adb\adb.exe shell am instrument -w dev.linwood.butterfly.magicpie.probe.test/dev.linwood.butterfly.BufferedStylusInputTest
```

## 7. 复用边界与未解决项

- 不root、不刷机、不改SELinux/节点权限；不依赖原厂系统UID/签名。现场固件SELinux为Permissive，不能外推到Enforcing固件。
- 运行时使用设备公开 `libhandwriting_jni.so`，JNI入口包名/签名需精确匹配；不得把厂商.so、APK或反编译业务实现提交进Git/新APK。
- 探针曾发送HANDWRITING_DISABLE广播被SecurityException拒绝；不能把广播当清理保证。产品路径依靠已验证的stop/destroy，不发送ENABLE/DISABLE广播。
- 保护原版 `dev.linwood.butterfly` 和原厂 `com.mp.evernote`；fork独立包 `dev.linwood.butterfly.magicpie`。
- 2–14px实时预览与最终笔宽、thinning、zoom尚未完全匹配；完整旋转/休眠恢复、长时间残影/全刷策略、全部导出格式仍待验收。
- 电脑文件往返已通过，真实WebDAV/Nextcloud服务未配置，不能写成自动同步成功。
- 当前APK为测试签名/实验功能，不能因Gradle叫release就当正式发行。最后保存修复构建SHA256：`F656508823C2880B5143B144203B01EC0A96535C02E8876D3D76001CE2DE8CBC`。
- 原始证据在本机忽略目录 `.magicpie-output/m2-research/` 与 `acceptance-20260916/`，不是Git可复现资产；可长期复用的是源码、合成回归和本手册。不要把私有笔迹用作新仓库fixture。

后续开发先读本手册，再查 [PLAN-M2.md](PLAN-M2.md) 的剩余验收。不要回到早期“每笔重启+截图覆盖”的方案，也不要拿安装成功、单元测试通过或系统截图替代实体笔验证。
