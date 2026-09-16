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
