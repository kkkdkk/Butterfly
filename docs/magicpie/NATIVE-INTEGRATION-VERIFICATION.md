# Butterfly 原生快写集成实验

日期：2026-09-16。状态：实验构建已安装、实际原生 start 成功，等待真机书写/压力/文档交接验收。常规构建仍默认关闭。

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
