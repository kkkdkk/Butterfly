# Butterfly 原生快写集成实验

日期：2026-09-16。状态：默认关闭，等待真机书写/压力/文档交接验收。

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
- JNI 静态审查仍不能证明 `setup(bitmap)` 会主动呈现最终位图。当前版本须实测抬笔后是否立即出现最终压力轮廓；若依赖后续点击/重绘才出现，单独 A/B `renderRect`，不同时改变 clear 与其他刷新变量。

## 待真机验收

1. 冷启动、进入浅色测试画布，日志确认原生预览启动，无崩溃。
2. 实笔轻—重—轻：比对 Android（含 history）、Flutter、提交点压力范围；不记录坐标。
3. 用户分别判断书写中和抬笔后粗细、延迟、闪动；两者分开记录，不把固定宽度快写算压力完成。
4. 一笔撤销/重做、保存重开、连续两笔、旋转/缩放/切页/后台恢复。
5. 实际电脑 `.bfly` 往返与导出继续依 PLAN-M2；真实云同步仍需用户服务参数。
