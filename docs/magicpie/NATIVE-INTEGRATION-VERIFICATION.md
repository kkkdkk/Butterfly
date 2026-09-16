# Butterfly 原生快写集成实验

日期：2026-09-16。状态：已实机确认 SurfaceView 旧空白帧覆盖快写，改为光栅化画布快照交接并等待新版验收；流畅与压力外观尚未同时通过。常规构建仍默认关闭。

## 范围

- `tools/magicpie/build.ps1 -SkipPubGet -NativeInkExperiment` 才编入开启标记；常规构建关闭。
- Android 控制器与独立实现的 JNI 桥仅存在于 magicpie flavor；设备型号和 API 27 再次守卫，其他环境回退 Flutter。
- 只加载设备公开的 `handwriting_jni`。不分发厂商库，不发送 ENABLE/DISABLE 广播，不改 EPD 模式、SELinux 或权限。
- 保留 `setBrush(4,0,true)` 已验证配置。实时原生预览按固定宽度处理；暂不宣称实时压力外观可用。
- Flutter 仍独占笔画数据、pressure、ElementsCreated、撤销和 `.bfly`；原生回调只做压力范围统计，不注入文档。

## 交接与安全

- Flutter viewport 的逻辑 Rect 与 DPR 转成绝对屏幕 Rect，用于原生初始化；PixelCopy 使用 Flutter SurfaceView 局部物理 Rect，避免截到空白 decor。
- 保留 Flutter 活动前景。最终 renderer 创建后等待 endOfFrame，再捕获完整笔迹作为新的原生背景。
- 存在活动笔画或未提交完成的笔画时不交接；Android 落笔期间跳过 present，新的落笔撞上 PixelCopy 时停止本轮原生预览，保留 Flutter 输入。
- 失焦、暂停、销毁、不支持的输入及工具/页面/坐标变化停止或重建；迟到异步结果不得恢复已销毁的会话。
- 当前固定笔刷与最终 Flutter 笔宽/压力轮廓可能不同。双显、闪断、残影及连续两笔的真机外观仍待验证。

## 已完成软件验证

- 全量 `flutter test --no-pub`：111 项通过。
- `flutter analyze --no-pub`：无问题。
- 压力回归：0.5 / 0.75 / 0.2 三个输入压力经 PenHandler 提交、`.bfly` 保存和重开后逐点保持，元素 ID 保持；存在压力变化时最终 renderer 不模拟压力。
- 桥接测试覆盖：DPR/Rect 协议、不可用库回退、无效 Rect、迟到 prepare、frame 后交接、dispose 取消交接、新笔未完成时禁止清除。
- 全量测试后补充串行化平台 present 请求，相关 9 项测试再次通过。
- 首轮真机启动无崩溃，但默认笔映射被空值条件误挡；已改为检查 `activeTool` 分类。开启 `magicpieNativeInk=true` 跑默认配置的 viewport 启动测试及压力/桥接测试，9 项通过。需要安装该修正版复核实际 start。
- 第二轮 release 真机返回 prepared=false；R8 mapping 确认 `FlutterView` 被改名为 `j6.s`，原先按类名字符串查找失效。改为 `instanceof FlutterView`，保持混淆安全；这不是 JNI 加载或硬件失败证据。
- JNI 静态审查仍不能证明 `setup(bitmap)` 会主动呈现最终位图。当前版本须实测抬笔后是否立即出现最终压力轮廓；若依赖后续点击/重绘才出现，单独 A/B `renderRect`，不同时改变 clear 与其他刷新变量。

## 待真机验收

1. 冷启动、进入浅色测试画布，日志确认原生预览启动，无崩溃。
2. 实笔轻—重—轻：比对 Android（含 history）、Flutter、提交点压力范围；不记录坐标。
3. 用户分别判断书写中和抬笔后粗细、延迟、闪动；两者分开记录，不把固定宽度快写算压力完成。
4. 一笔撤销/重做、保存重开、连续两笔、旋转/缩放/切页/后台恢复。
5. 实际电脑 `.bfly` 往返与导出继续依 PLAN-M2；真实云同步仍需用户服务参数。

## 最新装机记录

- 源码：`acbb8aa84`（R8 查找修复，接在 `879a3d5ae` 实验实现后）。
- APK：`app/build/app/outputs/flutter-apk/app-armeabi-v7a-magicpie-release.apk`。
- SHA256：`60A5E865BE3A65665181291CB9745D4FAFD405539BDED3FC8EFD94A66BC02BEF`。
- 覆盖安装 `dev.linwood.butterfly.magicpie` 成功；原版包与探针均保留。
- 新建浅色空白画布，选择默认笔；01:09:43.954 Android `Native fixed-width preview started`，01:09:43.955 Flutter `MagicpieInk prepared=true`（PID 26974）。
- 实际 Flutter SurfaceView 捕获、JNI init/setup/brush/start 已运行成功。启动 crash buffer 为空；不等于连续笔画、压力外观或保存后文档显示通过。
- 已请用户在该画布画轻—重—轻长线，抬笔后不点其他控件，分别核对快写与最终压感轮廓；等待反馈。

## 用户反馈与第二轮修正

- 用户实笔：“流畅了，但没有粗细变化”；多笔后出现全屏刷新。低延迟初步通过，压力外观与刷新频率未通过。
- 当前日志确认压力并非全被抹掉：Flutter 与提交点存在约 0.03–1.0 的变化；部分短笔只有两个提交点，不能宣称采样与外观均完整。
- 01:12:18 原生因 stylus cancel 停止，随后多笔事件集中到达；InputDispatcher 记录约 15,000 ms 输入处理延迟。未捕获主线程阻塞栈，不能把并行渲染竞争写成已证实唯一根因。
- 代码证实 `addUnbaked` 的同步 viewport 通知提前清空 `_submittedElements`，导致之后真实 renderer-created hook 看不到待完成笔迹。仅在 native 模式让完成权归属后置 hook，不改普通模式和嵌入流程。
- 第二轮：原生会话期间不绘制 Flutter 活动前景、不逐点 refresh；保留输入点、压力、提交、最终 renderer。抬笔先 stop 保留 native 资源，随后成帧捕获和 `setup → brush → start → renderRect`，去除交接 clear。
- 脏区来自最终 PenRenderer.expandedRect，转换为画布局部坐标、留笔缘余量、合并并裁剪后按 DPR 传给 Android。无新脏区时不因 viewport/cache 变化重复整幅呈现；新笔期间跳过的脏区留给下一次完成交接。
- 新增默认映射/前景抑制/提交压力和脏区回归，开启实验标记的 11 项测试通过。该变化的真实压力轮廓、全刷次数和连续书写仍待安装复验。
- 新增真实 ElementsCreated/追踪 PenHandler 回归：在 renderer 已插入后只回调一次，压力 [0.2,0.8] 保持，只调用一次 native present，一次 undo 移除整笔。普通与开启实验标记均通过。
- 全量 `flutter test --no-pub`：114 项通过。
- 第二轮 APK SHA256：`303B863DA057B7A45B9438A11E27F3C390460FADE41A30F5FA630EC881D2E530`，已覆盖安装。设备曾自动息屏，唤醒后新建浅色空白画布。
- 01:28:41.817 Android `Native fixed-width preview started`，01:28:41.818 Flutter `prepared=true`（PID 27575），crash buffer 为空。
- 已请用户再次轻—重—轻和连续约十笔，对照最终压力外观、流畅度与整屏闪烁频率；尚未将本轮局部呈现的视觉效果判为通过。

## 第二轮实笔失败与恢复排查

- `8f75e518a` 实机 PID 27575：01:31:29.052 普通 stylus DOWN 时 initialized=1、started=1、capturePending=0；01:31:44.508 收到 stylus cancel 并停止原生。
- 同时 InputDispatcher 记录约 15.5 秒输入处理延迟并丢弃过期事件。尚未捕获阻塞栈，不能认定是旋转、压力算法或渲染竞争造成。
- 01:31:44.839 下一次 DOWN 撞上捕获，01:31:44.845 prepared=false；此后原生未重新启动。后续普通 Flutter 笔画压力有变化，事件延迟约 0–17 ms，但用户感到显示迟缓。
- 用户反馈“还是没有粗细变化”，随后“粗细变化了，但是不流畅，感觉就是原来软件的笔”，与回退日志一致。本轮没有成功的原生 UP→renderer committed→local rect presented 真机证据，不能将局部交接或压力外观判为通过。
- 现场当前 SurfaceOrientation=1，但用户未确认发生横竖屏变化；不将旋转当成既定根因。
- 新增实验原生会话期间的主线程心跳检测：连续至少 2 秒未响应时，每次卡顿记录一次本进程线程栈；另记录 dispatch 的原生审计/Flutter 分发耗时、输入到达延迟、prepare 几何与窗口焦点。不记录笔画坐标，不使用 root，不改系统配置。这是诊断手段，不是首笔卡顿修复。
- 修正独立的恢复缺陷：prepare/present 失败不再永久缓存成功配置。失败只标记待重试，下一次画布 stylus UP 后重新评估；没有定时无限重试，落笔中不 prepare。请求编号与配置双重校验忽略旧回调，新 prepare 成功清除待重试标志。该修改不等于首次卡顿或压力外观通过。
- 恢复回归与桥接测试在 `magicpieNativeInk=true` 下 12/12 通过；相关 viewport 与测试文件静态分析无问题。覆盖失败后抬笔恢复、落笔中配置变化不启动、旧失败回调隔离、成功启动清除并发误标。
- 诊断 APK SHA256：`8DA45F21B57FE2936C858322BA4DAE036A8464AB3DB5675AC40FC5511C52BDFF`。覆盖安装成功，新 PID 29151，启动 crash buffer 为空。
- 01:50:15.471 准备 `Rect(0,100–1404,1777)`，原生 API rotation=0；01:50:15.700 native started，01:50:15.701 Flutter prepared=true。新建浅色画布并选择默认笔后，请用户两次轻—重—轻，中间抬笔等约 20 秒，不操作工具或旋转；本轮实笔结果待回收。
- 常规全量 `flutter test --no-pub`：117 项通过；其中 3 项 viewport 实验条件测试另以上述开启标记的 12 项运行实测，不能只用常规模式跳过的结果作为实验验收。

## 早间连续实笔：显示落后一笔

- 用户反馈“画下一笔，上一笔才会出现，粗细对的”。这是视觉交接失败，不是压感与流畅同时验收通过。
- 重新连接后保留日志，当前进程 PID 6304（已非夜间 PID）。08:04:48.604 原生启动；08:04:50–08:05:09 连续七笔均为 initialized=1、started=1，收到普通 UP，无 cancel 或本轮主线程卡顿记录。
- 七笔的 UP→renderer committed→Presented local rect 均按序出现；首笔 08:04:51.203 UP，51.250 renderer committed，51.573 local rect；末笔 08:05:09.291 UP，09.306 renderer committed，09.513 local rect。提交和局部调用约在抬笔后 0.2–0.4 秒内完成，不能据此证明物理屏幕已显示本笔。
- 原生有效压力样本这次也正常，例如一笔 native/Android 最大压力均 0.9380，Flutter 提交最大 0.93797。无需先改压力归一化。
- 静态审查确认新 renderer 已进入 visibleUnbakedElements，ViewPainter 监听 cameraViewport 并重画；没有发现此链路漏 repaint。Flutter endOfFrame 仅保证 UI post-frame，不等待 raster/SurfaceView 最新 buffer，立即 PixelCopy 有复制旧帧的可能，但尚未证实为真机唯一原因。
- 增加临时只读像素对照：首次交接前统计 dirtyRect 的暗像素数量和 hash；完成交接约 100 ms 后再次 PixelCopy 同一区域，只比较、不 setup/start/renderRect；输入或会话变化即丢弃。此对照不是新增刷新，也不是生产修复。
- 原始日志保存在忽略目录 `.magicpie-output/m2-research/magicpie-handoff-log-20260916-0825.txt`，不提交用户笔记或厂商代码。

## 已确认旧缓冲区交接与针对性修正

- 临时诊断 APK SHA256 `186E5AFA2C68A0B673B71E918F9C051B0357B4E1F2A79B0024FA700C86065647` 安装成功，PID 7399，启动无 crash。它没有改变原来的呈现策略。
- 08:33:57.319，operation=26 的首次 PixelCopy dirty 区域为 `darkPixels=0,hash=e4f33a81`；08:33:57.542 同一操作的只读第二次 PixelCopy 为 `darkPixels=4119,hash=3db53c1c`。回调通过无新笔/无新会话的守卫。这是首次交接复制旧空白 buffer 的直接证据，不只是时序猜测。之前 operation=17/18 也出现首次 darkPixels=0，但后续新笔打断了对照，不能单独用于稳定帧比较。
- 用户进一步描述：落笔能看到快写笔迹，随后马上消失；稍后像普通渲染一样只显示一部分，下一笔落下前一笔才完整出现。与抬笔过早 stop、旧空白/不完整截图覆盖快写的路径一致。
- 证据日志保存在忽略目录 `.magicpie-output/m2-research/magicpie-stale-frame-proof-20260916.txt`。临时像素扫描在主线程运行，本轮延迟不能代表无诊断版本。
- 修正方案：抬笔不再 stop；保持快写预览直到 Flutter 已绘制画布经 RepaintBoundary.toImage 完成光栅化并生成 PNG。present 传递该图像和原来的局部脏区，Android 解码尺寸校验后才 stop→setup→brush→start→renderRect。present 不再使用 SurfaceView PixelCopy，保留首次 prepare 的背景捕获；移除临时二次截图/像素扫描。
- 新画面准备期间若开始下一笔或有更新的待提交脏区，不允许旧快照覆盖新笔。压感数据、存档格式和固定原生笔刷配置保持不变。本修正需要新的软件回归和真机验收，不能将根因确认等同于体验通过。
- 同时修正 postFrameCallbacks 发起交接时的帧调度：显式 scheduleFrame 再等待 endOfFrame，防止等到下一次输入才出帧；旧 capture 异常不得 dispose 新会话，当前图片捕获或平台呈现失败则显式 dispose 后回退 Flutter。
- 修复 APK 已覆盖安装：SHA256 `8030EE74BBE16E68ED088649CD679717A32835D41AC9C65A14362F328326B999`，PID 7955，启动 crash buffer 为空。08:48:50.793 原生 start，08:48:50.794 prepared=true。已打开新的浅色测试画布并选择默认笔，请用户单笔轻—重—轻、抬笔停 5 秒，验收是否仍消失/需要下一笔触发；尚未收到本轮结论。
- 新版软件验收：全量 `flutter analyze --no-pub` 无问题，常规 `flutter test --no-pub` 124/124 通过；开启实验标记的 bridge/viewport/真实 ElementsCreated 提交三文件 20/20 通过。真实 RepaintBoundary.toImage PNG 解码检出本轮新画黑线，覆盖捕获期间新笔/处置、迟到异常不伤新会话、present 失败释放原生、post-frame 主动调度下一帧；原提交压力/一次撤销等断言保持通过。这仍不替代物理墨水屏的连续书写验收。

## 光栅化交接仍失败与三模式对照计划

- `f961227c3` 已用 `RepaintBoundary.toImage()` PNG 代替 present 阶段的 SurfaceView PixelCopy，软件回归通过；用户实笔仍反馈原生快写笔迹随后消失，而独立 probe 保持稳定。因此“首次 PixelCopy 取到旧空白 buffer”是已经证实并修正的问题，但不是当前消失现象的充分解释，也不能继续写成唯一根因。
- 静态审查确认 native active 只抑制活动 Pen foreground 和逐点 foreground refresh；最终 `PenRenderer` 仍会进入 `cameraViewport.visibleUnbakedElements`，`ViewPainter` 仍绘制完整纸面与已提交笔迹。Flutter 没有暂停或隐藏 SurfaceView。代码可以证明 Flutter paint/raster 链仍工作，但不能单凭框架日志断言 SurfaceView buffer 的实际提交时刻、damage 范围或墨水屏的物理刷新行为。
- 独立 probe 不是当前 handoff 的等价验证：它在启动时一次 `init/setup/start`，书写期间不执行每笔 `stop/setup/start/renderRect`；Java 侧未逐笔更新或替换 setup Bitmap，native 是否写回该 Bitmap 尚未验证，也没有每笔 document/renderer 提交。probe 的 UP 会更新顶部状态文本，所以不能称整个窗口绝对静止；只能确认其 ink Canvas 没有 Butterfly 的画布提交链和 native 重启链。

诊断代码仅在编译标记 `magicpieNativeInkDiagnostics=true` 时启用。诊断启动参数 `magicpieInkDiagnostic` 必须显式解析为以下白名单之一，并记录请求值与最终生效值；普通构建保持原布尔协议和关闭状态。诊断构建若缺少或收到未知值，应明确拒绝启动诊断会话，避免静默落入某个模式污染对照。

1. `record-only`：完成与其他模式相同的初始 native prepare/setup/start。仅当 native 已就绪、单支普通 stylus、无按键且 DOWN 位于合格画布区域时，由 Activity 从 DOWN 开始接管，并一致吞掉该手势直到 UP/CANCEL；记录 Android/native 完整事件与 history，不把该手势送入 Flutter，不创建文档元素，不 capture/present，也不在每笔结束时重启 native。若 DOWN 已吞掉，中途出现异常也不能把孤立 MOVE/UP 转发给 Flutter。
2. `commit-only`：不吞手势，保持正常 Flutter pointer、toolbar、PenHandler、ElementsCreated 与最终 renderer 提交流程；保留连续 native preview，但 Dart 不执行最终 capture/present，Android 不执行每笔 `stop/setup/start/renderRect`。该模式实际增加的是“Flutter gesture + UI 状态 + document commit”整组变量，不是只增加 document commit；首次落笔的 toolbar 刷新/动画也是已知混杂因素。
3. `handoff`：运行当前完整链路，即正常 Flutter 提交、最终帧 PNG 捕获，以及 Android `stop → setup(PNG) → brush → start → renderRect`。它用于和 `commit-only` 比较交接重启的增量影响，不再用来重复证明 PNG 单元测试。

三个模式使用相同的 instrumentation：logcat 只记录诊断模式与会话代号、native ready/start/stop/setup/renderRect、Android DOWN/MOVE/UP/CANCEL/history 统计、手势是否 consumed/forwarded、Flutter 收到的事件计数、document submit、renderer committed、capture 开始/结束、present 开始/结束及失败原因，不逐点输出坐标。为核对三模式实际收到的同一输入，Java 将完整原始事件的坐标、pressure、history 与 time 写入应用 external files 下的 `ink-diagnostics`；仅使用空白测试画布上的受控诊断笔画，不记录真实笔记、不上传、不作为回放输入。本轮不修改采样算法，也不实现事件回放。不适用的阶段必须明确记录为 `N/A`，不能用缺少日志冒充成功。各模式采用同一画布、方向、笔、等待时间与操作脚本；每轮重启应用并确认 effective mode，避免沿用上一轮 native/document 状态。

人眼验收分别记录书写中、抬笔瞬间、抬笔后约 0.5/2/5 秒和下一次落笔前后的外观，并保留连续视频或现场观察说明。Android/Flutter 截图只能反映应用合成面，通常不能证明 native handwriting overlay 当时是否存在、消失或位于其上方，因此截图不得作为 native overlay 成败的单独证据。

### 可证伪判据

- `record-only` 也消失：否定“在 Butterfly Activity 中只要不走 Flutter 手势/提交和 handoff，连续 native session 就必然稳定”。先核对 record-only 是否真的全程吞掉、是否发生 CANCEL/失焦/输入排除或其他 native stop；不能直接归因 Flutter document commit。
- `record-only` 稳定、`commit-only` 消失：问题被收窄到 Flutter 手势、pointer/toolbar/UI 帧和 document/renderer commit 这一组增量变量。它不证明 document commit 单独导致，也不证明每个 Flutter frame 都物理刷新了 ink 区。
- `record-only` 与 `commit-only` 都稳定、`handoff` 消失：较强指向每笔 native handoff 增量，即 PNG setup、stop/start、renderRect 或它们与仍活动的 Flutter Surface 之间的竞争；仍需下一轮单变量实验区分具体调用。
- 三者都稳定：本轮没有复现，不能宣称修复。诊断日志、手势吞噬或额外时序可能改变竞态，应重复相同脚本后再判断。
- 三者都失败或结果不一致：先按 CANCEL、窗口焦点、native 生命周期、事件数量/history 和模式是否生效分层，不用一次肉眼结果选择根因。

### 设计风险与审查清单

- `prepare` 仅在 diagnostics 编译标记开启时返回 `{ready, diagnosticMode}`；Dart 端不得继续用强类型 `invokeMethod<bool>` 解析该分支。普通构建仍须保持原 `bool` 返回，诊断逻辑不得由启动 extra 单独开启。
- `record-only` 只阻断合格画布内的 stylus gesture，不冻结 Flutter engine、toolbar、定时器、动画、autosave 或 SurfaceView，也不证明没有其他 Flutter frame。其稳定结果只能作为“无本笔 Flutter 输入/提交”的基线。
- 只有 native 已成功 ready/start 后才能吞 DOWN；未就绪、越界、按键、多指和非 stylus 输入继续走安全回退。已吞掉的手势必须吞到 UP/CANCEL，并在 CANCEL、失焦、暂停和销毁时留下明确终止原因。
- 当前集成在 CANCEL 时会停止 native，而 probe 只计数 CANCEL；若 record-only 发生 CANCEL，两者已经不是连续 session 等价条件，该轮不能用于稳定性结论。
- `commit-only` 必须明确禁止 Dart capture/present 和 Android handoff，同时保留最终 Flutter renderer；否则它会退化成 handoff 或只测到活动 native overlay。禁用 handoff 后遗留的 dirty/presentQueued 状态也不能跨模式或跨会话污染结果。
- 所有模式应先确认相同初始背景与 native brush 配置。原始输入文件只保留本次受控测试笔画，不包含真实笔记、文档内容或凭据；logcat 仍不得逐点记录坐标。文件写入与高频统计不得在主线程形成会改变输入时序的重活路径，测试结束后按诊断留存策略处理该目录。
- diagnostics 会改变分支、日志量和时序，属于诊断而非生产修复。任何单一模式结果都只支持上述层级归因，不得越级写成 SurfaceView、Flutter、JNI 或墨水屏驱动的既定根因。

### 诊断构建与切换

```powershell
.\tools\magicpie\build.ps1 -SkipPubGet -NativeInkExperiment -NativeInkDiagnostics
C:\adb\adb.exe -s YTCP0100000222000668 shell am force-stop dev.linwood.butterfly.magicpie
C:\adb\adb.exe -s YTCP0100000222000668 shell am start -n dev.linwood.butterfly.magicpie/dev.linwood.butterfly.MainActivity --es magicpieInkDiagnostic record-only
```

同一 APK 分别用 `record-only`、`commit-only`、`handoff` 启动；每次先 force-stop，只在空白测试画布上操作。未加诊断编译标记的构建不会因 intent extra 启用诊断。模式 A 的笔画不会进入 Butterfly 文档，也不用于保存/撤销验收；输入副本仅为诊断记录。确认 Android `Prepare diagnosticMode=...` 与 Flutter `diagnosticMode=...`、`prepared=true` 一致后才能开始实笔。

诊断构建若未指定有效 extra，则 prepare 失败且不启动 native，不能把普通 fallback 当成对照。Recorder 构造不启动线程或写文件：主线程只复制含 history 的 MotionEvent，抬笔后后台展开并写入，finally 回收事件副本，线程空闲 10 秒退出。每笔最多 4096 个事件/8192 个 pointer samples，超限明确记 truncated/dropped，不允许按完整采样验收。

第一轮脚本：画一条短线，抬笔等 5 秒；在旁边再画第二条，等 5 秒；最后连续画 3 笔。记录每个阶段是否消失以及下一笔是否改变上一笔，避免一开始长时间连续写掩盖单笔时序。

### 2026-09-16 诊断版部署记录（尚待实笔结果）

- 常规 `flutter test --no-pub` 通过（129 个测试项；诊断专用项在常规开关关闭时不执行模式断言）；`flutter analyze --no-pub` 无问题。三个相关文件在 `magicpieNativeInk=true` + `magicpieNativeInkDiagnostics=true` 下 25 个测试项通过，包含两种无交接模式不调用 capture/present、handoff 保持捕获、commit-only 仍提交文档并可撤销。
- 诊断 release APK 构建成功并覆盖安装到 fork 包，SHA256 `AF43542ED4AA85124FF3FAFCD65EE44ADE08B566FE22A4DB69E134D120F52556`。未改原版应用；旧 APK 留在忽略目录 `.magicpie-output/m2-research/handoff-before-diagnostics-8030EE74.apk`。
- 已用 `--es magicpieInkDiagnostic record-only --es route /new` 启动，PID `10260`。设备此前休眠，已通过 KEYCODE_WAKEUP 唤醒；打开新白色文档、选择笔。10:03:41.880 Android effective mode 为 record-only，10:03:42.209 native started，10:03:42.210 Dart mode=recordOnly，10:03:42.211 prepared=true。当前进程 crash buffer 为空。
- 已请求用户按单笔停 5 秒、第二笔、连续 3 笔脚本测试。此记录只证明诊断版部署且模式就绪，不证明笔迹保留成功；截至此记录仍待用户观察和实际输入统计，后续两组尚未执行。

### 模式 A 实笔结果与模式 B 准备

- 用户反馈模式 A「粗细无变化，其余正常」。固定粗细符合该原生笔刷配置；这是本轮笔迹保持/流畅观察通过，不代表压感显示或文档保存通过。
- PID 10260 在 10:05:33–10:05:43 记录 4 笔，全部 eligible=1、nativeReady=1、diagnosticConsumed=1、forwarded=0，均正常 UP，无截断。采样数分别 575/546/230/193，总计 1544；history 分别 555/528/221/185。压力最小值最低约 0.0264，最大值达到 1，说明输入压力可变，但固定笔刷未呈现粗细。
- 该区间无 Flutter document submit/renderer commit/present；没有以截图替代用户对 native overlay 的观察。模式 A 的稳定将问题范围缩小，但尚不能单独认定 Flutter 重绘或原生交接哪一个是根因。
- 原始受控测试输入保存在忽略目录 `.magicpie-output/m2-research/diagnostics-record-only/`，进程日志为 `.magicpie-output/m2-research/magicpie-record-only-20260916.log`。不提交原始笔画到 Git。
- 已使用同一个 APK force-stop 后切换 `commit-only`，新白色画布、相同方向与笔刷，PID 10740；10:07:29.270 Android 确认 effective mode=commit-only。模式 B 加入正常 Flutter 输入/UI/文档链，仍禁用 capture/present；待用户按相同脚本实笔观察。

### 模式 B 第一轮：用户视觉正常，但对照条件未成立

- 用户反馈「正常。延迟无重现」。保留该视觉观察，不将其等同于 native-active 文档提交通过。
- PID 10740 第一笔 10:08:49.311 DOWN 时 native ready/eligible，但约 14 秒后 10:09:03.309 收到 CANCEL，native 被停止；记录仅 3 个事件（DOWN/MOVE/CANCEL）、187 samples。系统 InputDispatcher 同时报告 MOVE 处理耗时约 13.6 秒并丢弃 stale event。当前日志未出现 main-thread watchdog stall，不能仅据输入积压断言主线程阻塞或某个渲染调用耗时。
- 后续 5 笔 DOWN 的 nativeReady=false，输入到达滞后约 9827/4533/4046/3711/2668 ms；分别记录 294/125/73/84/168 samples，却只提交 9/4/3/3/6 个文档点。这些是取消后的回退与积压释放，不是模式 B 所需的完整原生连续会话。
- 该轮没有 native-active renderer committed / diagnostic skip capture 日志，故不能据此排除 Flutter 输入链问题或归因 handoff。原生预览与应用文档处理是不同通道，肉眼流畅与文档输入积压可能同时存在。
- 10:09:04.270 native 重新 started，Dart 随后确认 commitOnly/ready。暂不切换模式 C、不改代码，先请求一条短线后停 5 秒，以核对 DOWN→UP→renderer commit 全程原生状态。
- 受控记录与 app 日志保存在忽略目录 `diagnostics-commit-only/`、`magicpie-commit-only-20260916.log`；InputDispatcher 证据为 `magicpie-commit-input-dispatcher-20260916.log`（均位于 `.magicpie-output/m2-research/`）。

### 模式 B 重试：连续原生会话有效，随后出现压感重绘

- 用户反馈没有实时书写延迟，但过几秒会重绘并给线条加上粗细。该观察不同于第一轮取消后的回退，已有有效 native-active 提交日志对应。
- PID 10740，10:13:42–10:14:01 的 stroke 7–13 全部 nativeReady/eligible=true、forwarded=true、正常 UP、truncated=false；没有新的 CANCEL/stop/prepare，DOWN 均 started=1、capturePending=0。
- 每笔均有 `native=true`、`document submit`、`renderer committed` 和 `diagnostic skip capture/present: commitOnly`，证明没有执行 PNG capture 或 Android native handoff。7 笔 Android 采样数 292/284/175/377/808/199/565，共 2700；文档点数 103/48/55/112/227/50/135，历史点未完整进入 Flutter 的问题仍独立存在。
- 从 Android UP stats 到 renderer committed 分别约 40/36/151/40/48/61/47 ms。不能把用户观察的数秒后压感变化解释为文档数秒后才完成，也不能把 renderer committed 当作物理墨水屏已刷新。后续屏幕呈现/刷新时序仍待验证。
- 此轮支持：保持 native 连续书写且禁用显式 handoff，Flutter 文档/最终压感笔迹仍可工作，用户未观察到笔迹消失。暂不能宣布所有 Flutter frame 都安全，也不能忽略先前输入取消问题。下一步用相同 APK 的 handoff 模式确认增加交接链是否复现消失。
- 证据在忽略目录 `.magicpie-output/m2-research/diagnostics-commit-clean/` 和 `magicpie-commit-only-clean-20260916.log`；无代码修改、无新 APK。
- 已 force-stop 后用 `handoff` + `/new` 启动第三组，PID 11093；10:16:52.617 Android mode=handoff，10:16:52.800 native started，10:16:52.804 Dart prepared=true，当前进程 crash buffer 为空。已选相同默认笔，待用户短线停 5 秒的物理观察；尚无第三组结果。

### 模式 C 第一轮：未消失，但没有完成实际 handoff

- 用户反馈「没有消失」。PID 11093 第一笔 10:17:41.323 DOWN 后至 10:17:56.554 CANCEL，约 15 秒输入积压再次出现。随后旧输入以数秒滞后批量送达，期间多次 prepare 被落笔打断；不可将该轮当作完整稳态 handoff 验收。
- 应用日志出现 renderer committed 与 handoff endOfFrame，但没有 captureReady/toImage/PNG/Android Presented/completed 成功日志。仅选择 handoff 模式不证明走完交接。
- 检查取消链发现确定的状态缺口：`_handlePointerCancel` 原本只从 CurrentIndex 移除触点，不通知 PenHandler；被取消笔画仍留在 `elements`，导致 `hasPendingInk` 为真，阻断后续 `presentAfterFrame` 的 ready 条件。该缺口是“可能让交接永远不执行”的独立代码问题，不等于已经定因物理消失或输入积压。
- 新增回归测试先在默认空 cancel hook 下失败（预期剩余 pointer `[3]`，实际 `[1,3]`），修正后通过。最小修正：Handler 增加 cancel 回调、viewport 转发；PenHandler 仅丢弃对应未完成 pointer 的元素/采样/位置并取消形状检测临时状态，不提交被取消笔画，不清空已提交笔画。测试覆盖其他 live pointer 和 submitted stroke 保留、后续实际 present 恢复。
- 修正后的诊断开关相关三文件 26 个测试项通过；普通测试 130 个测试项通过（诊断专用项仍按编译开关执行），analyze 无问题。尚未据此声明物理墨水屏故障修复。
- 旧诊断 APK 已保留为 `.magicpie-output/m2-research/diagnostic-before-cancel-AF43542E.apk`。模式 C 输入与日志位于同目录 `diagnostics-handoff/` 与 `magicpie-handoff-20260916.log`，不提交原始测试笔画。
- 取消状态修正 APK 构建、覆盖安装成功，SHA256 `FBADCB3593A07D88DF81C9A704A9D31DAEAE9176899A245B335D4F276AEAB98E`。以 handoff + `/new` 启动 PID 11757，选择默认笔；10:29:31.582 确认 Android effective mode=handoff，当前进程 crash buffer 为空。此次仍为诊断版，等待实笔验证真实 handoff，不声明原有消失/输入积压已修复。

### 模式 C 后续：第一条消失，后续交接完成

- 用户明确「第一条消失了」，并观察到粗细变化。未重启应用；ADB offline 经 reconnect offline 恢复后读取同一 PID 11757。
- 第一笔 10:30:37.656 DOWN，10:30:53.191 CANCEL；3 个事件、183 samples，无 document submit。系统 InputDispatcher 报告 MOVE 处理约 15533.9 ms 并丢弃 stale events；取消时 native preview 停止。不能把这条消失归因于尚未执行的 PNG handoff；输入积压的底层原因仍未确定。
- 第 2–4 笔 native ready、正常 UP，文档点数 89/208/204，均完成实际 Presented；completedMs 为 2054/1939/1956，toImage 为 637/478/519 ms，PNG 编码为 1193/1201/1198 ms，decode 为 92/93/95 ms。整幅截图编码有明确秒级成本，但软件交接完成不等于物理屏幕呈现。
- 首笔取消是混杂因素，本轮不支持直接宣称 handoff 导致消失。下一步优先调查首笔输入积压，独立跟踪压感重绘延迟，不强行提交 CANCEL 的不完整笔画。
- 证据保存在忽略目录 `.magicpie-output/m2-research/magicpie-after-cancel-20260916.log` 和 `diagnostics-after-cancel/`，不提交原始输入到 Git。

### 输入缓冲单变量探针与候选修正

- 探针 APK SHA256 `8C89C2D599609748626E2774DFED209EFD54518E43A7CC28B399F75712D960F9`：两组 InkView 均消费完整触摸，仅 `unbufferedInput=true` 调用与 FlutterView 相同的 requestUnbufferedDispatch。不含 Flutter 或每笔 bitmap 交接。
- false 组 PID 12131：10:39:29/10:39:50 两笔均 UP，cancel=0，累计 history=421。用户确认未消失。
- true 组 PID 12258：10:41:00.529 首笔 DOWN，10:41:16.040 CANCEL，累计 down=1/move=1/up=0/cancel=1/history=180；InputDispatcher 报告 MOVE outstanding 15519.9 ms 并丢弃 stale events。随后四笔正常 UP。用户也确认未消失：探针 CANCEL 不停止 native，与主程序不同，故视觉保留不等于输入交付正常。
- 单变量实验在没有 Flutter 引擎的探针复现首笔积压/取消，支持针对该固件跳过 unbuffered 请求；尚需主程序重复首笔验收。日志在忽略目录 `magicpie-unbuffered-probe-20260916.log`。
- 候选修正：仅 native controller 存在、DEVICE=px30_eink_magicpie、API27 时，在同一 FlutterView 上以 OnTouchListener 转发笔/橡皮擦起始的完整手势到公开 AndroidTouchProcessor(renderer,false)，绕过 FlutterView 的 requestUnbufferedDispatch。手指起始手势仍走原路径，多指混入不切换处理器，UP/CANCEL 结束归属；不改固件、不反射私有字段、不强行提交取消笔画。false tracker 与当前 SDK FlutterView 一致。此修正不解决 history 点遗漏或 PNG 编码延迟。

### buffered stylus 主程序第一轮：输入取消未复现，显示仍失败

- 候选 APK SHA256 `90795993F3ED1721510D8F9CDE1160114E089B7D4AC7675C84478100F3F96DC7` 构建/安装成功。PID12497 确认 buffered stylus compatibility enabled，handoff ready。该兼容层也覆盖 native 未启动时的笔输入，正式验收需包含该场景。
- 10:47:56 与 10:48:31 两笔均 nativeReady、正常 UP、cancel=0；样本184/222，而文档只有7/8点，历史点遗漏在 buffered 模式下尤其明显。首笔15秒积压本轮没有复现，不等于已完成长期验收。
- 两笔均完成交接，completedMs=2367/1908。用户报告第一笔无延迟但马上消失留空心轮廓，第二笔有延迟且同样消失，第一笔随后重新出现。保留该物理观察，不能用 Presented=true 宣称成功。
- 随后系统截图显示两条实心线，与物理观察不同；只能确认软件截图中存在笔迹，不能证明物理EBC层呈现正确。下一轮保持同一APK和输入修正，仅切换 commit-only，隔离每笔capture/stop/setup/start/renderRect增量。
- 证据位于忽略目录 `magicpie-buffered-handoff-20260916.log`、`diagnostics-buffered-handoff/`、`magicpie-buffered-handoff.png`。本轮未改业务代码。

### buffered commit-only 稳定观察与历史采样修正

- PID12717，用户确认前两笔实时无延迟、不消失，但停笔后出现带粗细的二次绘制。9笔均正常UP、无CANCEL、native ready，且全部跳过capture/present；日志保存在忽略目录 `magicpie-buffered-commit-20260916.log`。这一对照支持停止使用每笔交接，但不把具体stop/setup/renderRect单独认作根因。
- 第一笔 Android737 samples/history714，Flutter文档仅22点；第二笔132 samples/history125，文档仅6点。后续快速短笔甚至只有2–4点。固定原生预览与随后Flutter压力笔迹是两层绘制，不能称为实时压感完成。
- 普通模式改为连续native会话，Dart默认跳过capture/present，Android非显式handoff诊断拒绝present。回归覆盖普通模式连续三笔不capture/present、提交文档/撤销不受影响；handoff保留为诊断测试路径。
- buffered stylus输入补丁新增历史MOVE样本重放，按原始时间、pointer属性、坐标/压力/axes传给Flutter AndroidTouchProcessor，最后只转发一次当前事件。CANCEL不补交旧样本，合成事件finally回收。仅已接管的stylus/eraser手势使用，不重复调用native审计/诊断记录器，也不重新打开unbuffered请求。
- 普通常规Flutter测试131项通过，相关诊断测试23+4项通过，analyze无问题。新增独立设备Instrumentation覆盖MOVE/UP/CANCEL及双pointer、压力/axes/metadata，待真机执行；不得以构建成功代替采样与实体书写验收。
- 后续设备执行：独立probe及测试APK安装成功，`am instrument -w dev.linwood.butterfly.magicpie.probe.test/dev.linwood.butterfly.BufferedStylusInputTest` 返回 `BufferedStylusInput: 3 tests passed`。这是Android事件展开单元回归，不是实体笔迹验证。
- 主程序诊断APK构建/覆盖安装成功，SHA256 `9453BFCC8D92359A99AC5FA435BB8B340D25821153E221EBF1DB5B2706695B07`。PID13378，使用commit-only新画布继续对照，待实体笔写入与实际文档点数核验；原厂/原版包未更改。新增测试包仅用于回归。
- 该版实笔反馈「流畅不消失，停笔后出现粗细」。PID13378记录17次UP、cancel=0；前两笔Android527/493 samples对应Flutter525/491 MOVE（加DOWN/UP与总样本吻合），文档511/480点；文档仍应用既有同坐标去重，不能把该差值都称作事件遗漏。最长一笔提交1621点，压力仍变化。历史样本确已送到Flutter，不再是此前每笔只有个位数/几十点；此轮支持采样修正及连续native路径，仍未通过实时压感外观。
- 原生固定宽度预览与停笔后Flutter压力渲染仍为两层。本次不再以采样修正宣称实时粗细已解决，未盲改setBrush参数。证据在忽略目录 `magicpie-history-verified-20260916.log`。后续需独立验证原生压力笔刷能力，并补保存/重开/跨端验收；软件处理存在数百毫秒积压，不能仅据肉眼流畅宣称整条输入链低延迟。

### 原生逐采样笔宽调查与独立探针

- 当前设备libhandwriting_jni的Thumb反汇编：setBrush对应0x79cc写brush标志+8、width+12、color+16及bool+20；bool不等于压感或enable开关。输入循环0x8822同步回调Java，返回后0x8834检查brush标志，0x884a绘制当前点，0x9b38–0x9b46用当前width设置笔宽。由此可做同步回调内更新width的实验，而不是跨线程定时更新。
- render_rect在0x7788将brush标志+8清零。诊断handoff原顺序setBrush/start/renderRect因此会关闭后续直接笔刷；这支持下一笔变慢的具体解释，但仍不足以单独解释所有物理残影。普通路径已禁用该交接，不重新启用未经复验的handoff。
- 新独立探针 `nativePressure=true`：仅valid DOWN/MOVE同步按归一化pressure映射2–14px并调用既有setBrush，UP不把宽度降为0；不post主线程、不逐点renderRect、不复制厂商绘制代码。该线性映射只是能力验证，不是最终Butterfly笔刷算法。
- 探针同时保留未验收的bitmapPressure实验，但nativePressure优先且当前未启用bitmap路径。当前probe APK SHA256 `A28806D11FB98A5C3B3D6A78A4EF95D79FC68956D18FC0B5162A91E50DC49ACD`，已构建安装并启动nativePressure模式。Butterfly主程序未替换；等待笔未抬起时的粗细、流畅与停笔保留观察。

### 同步原生压感通过探针观察，接入主程序待验证

- 探针休眠/暂停后会cleanup且不自动重启；用户初次反馈无墨时，日志显示started=false。后续手动启动后PID16046收到两笔正常UP、nativeEvents累计2172、cancel=0，用户明确反馈粗细「当场变化」。不能把前面的未启动状态记作压感算法失败。
- 主程序采用同样的valid DOWN/MOVE同步2–14px映射，保留UP末段宽度。listener绑定本次sessionInk实例，避免用另一个新会话的全局引用更新旧回调；不新增主线程post、不使用每笔位图交接。普通文档压力与历史采样链不变。
- 仅诊断handoff路径补正renderRect后恢复setBrush的顺序，普通路径仍禁handoff，未宣称由此解决所有旧残影。实时预览与Flutter最终笔刷外形仍未统一，笔宽设置/缩放匹配和停笔重绘仍是验收项。
- 27项相关诊断回归通过，主程序release构建/安装成功，APK SHA256 `AC672368D33470DE40E0E93A01C0D90F2FAEEF8900D2BDC1285EC65BB95A8286`。PID16793、commit-only新画布，待用户真实书写确认；原版包未改。探针现场日志保留在忽略目录 `magicpie-native-pressure-probe-20260916.log`。
- 随后用户明确确认「现在没有问题了。很流畅，并且粗细都实时显示了」。记录为该版本本轮实体书写通过，不外推为保存、缩放、跨端同步均已完成。用户要求继续上述验收并及时push。
