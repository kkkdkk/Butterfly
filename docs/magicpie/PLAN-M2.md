# Magic Pie M2 低延迟与跨端闭环实施计划

日期：2026-09-15 · 基线：`magicpie-monochrome` / `87bf17aa1167aed0bfe726ef3f70382df22650b1`

## 1. 执行原则

先修已知 Flutter 实时预览缺陷，再做真机 A/B；厂商原生路径必须通过普通 UID 探针才可进入产品代码。所有 worktree 位于仓库 `.worktrees`，缓存和产物位于 D 盘。主 agent 审查、合并、构建、安装和最终推送。

## 2. P7：事实基线与文档

| ID | 工作项 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P7.1 | 记录 M1 真机延迟反馈及左上测试 fixture 含义 | M1 | VERIFICATION 不误报完成 |
| P7.2 | 对照上游 b04d7257 与 5808263d，确定最小回移范围 | P7.1 | 每行修改可追溯，不回移无关 eraser/refactor |
| P7.3 | 读取原厂包身份、系统库/public libraries、设备节点权限 | P7.1 | 证据保存在 ignored m2-research |
| P7.4 | 完成 PRD-M2 与本 Plan | P7.2,P7.3 | 范围、安全边界、验收完整 |

## 3. P8：Flutter 实时预览修复

| ID | 工作项 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P8.1 | 为第二点后活动 element 更新编写回归测试 | P7.4 | 修复前失败，断言抬笔前 renderer 含全部点 |
| P8.2 | 回写 `elements[pointer] = element.copyWith(points: points)` | P8.1 | 单测通过；提交仍只用 `_elementPoints` 最终数据 |
| P8.3 | 在当前 2.5.5 架构加入 16 ms foreground runner | P8.2 | 高频 schedule 合并；立即 refresh 可取消待处理延迟刷新 |
| P8.4 | Pen move 使用 delayed refresh，down/up/工具切换保持正确顺序 | P8.3 | 不丢首末点，不产生悬空 Future |
| P8.5 | close/reset 时取消 runner；补 dispose 测试 | P8.3 | 无 timer/renderer 泄漏 |
| P8.6 | 相关 handler/bloc/cubit 测试、全量测试和 analyze | P8.5 | 全部通过，diff check 通过 |
| P8.7 | 构建 M2-A APK，安装并实笔 A/B | P8.6 | 用户确认是否仍有明显抬笔延迟 |

## 4. P9：厂商接口独立探针

| ID | 工作项 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P9.1 | 自主实现最小 `HandWritingNative` 接口声明，绝不复制 manager 业务实现 | P7.4 | APK 不含厂商 so/反编译源码 |
| P9.2 | 增加 probe Activity 和清晰状态日志 | P9.1 | 只在 Magic Pie 手动/显式触发 |
| P9.3 | 验证 `System.loadLibrary(handwriting_jni)` | P9.2 | 普通 UID 成功或记录 linker 原因 |
| P9.4 | 空白区域 init/start/stop/destroy 单次测试 | P9.3 | 返回值、logcat、设备触摸和显示正常 |
| P9.5 | 连续 20 次生命周期与 force-stop 恢复测试 | P9.4 | 无幽灵笔迹、设备节点状态恢复 |
| P9.6 | 反射探测 `EinkRefreshUtil` 及安全模式切换/恢复 | P9.4 | 不可用时不崩溃；可用值有实机证据 |
| P9.7 | 写 PROBE-VERIFICATION，决定 Go/No-Go | P9.5,P9.6 | 主 agent 明确批准后才进入 P10 |

## 5. P10：原生快速预览接入（P9 有界实验 Go，产品启用仍需验收）

2026-09-16：4 次完整 Android 实笔序列通过后，批准默认关闭的 `-NativeInkExperiment` 构建实验，不批准默认产品启用。刷新模式探测/视觉恢复剩余检查继续独立进行，不为第一轮接入叠加 A2。

实验顺序：P10.1 控制面与屏幕/Surface 坐标 → P10.4 保留全部 Flutter 输入和前景 → P10.6a 最终 renderer 帧提交后交接 → P10.8a 轻/重压力范围与 `.bfly` 往返 → 实笔结果决定是否进入前景抑制与刷新优化。Android 与 Dart 分工并行，主 agent 合并审查并独占真机。

| ID | 工作项 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P10.1 | 建立 magicpie-only Android controller 与 MethodChannel 控制面 | P9.7 | 普通设备不加载厂商类/库 |
| P10.2 | 定义 `idle → nativeDrawing → awaitingDocument → documentPresented → overlayCleared` 状态机 | P10.1 | 非法转换安全回退并清理 |
| P10.3 | 精确获取 Flutter viewport 屏幕 Rect、DPR 与 transform revision | P10.1 | 竖屏、状态栏、工具栏位置正确 |
| P10.4 | Android 旁路观察 stylus event/history，不消费 Flutter 事件 | P10.2 | Flutter pressure/保存仍完整 |
| P10.5 | 只为安全子集启用 native preview；其他输入回退 | P10.3,P10.4 | 手指、反向笔、按钮、尺子、形状识别不误启用 |
| P10.6 | Dart 活动前景抑制与最终 renderer 交接 | P10.2,P10.4 | 无双显、无清除空档、连续两笔隔离 |
| P10.7 | up/cancel/reset/pause/focus/rotate 全生命周期清理 | P10.6 | 无幽灵墨迹，正常模式恢复 |
| P10.8 | undo/redo/save/reopen 与 pressure 回归 | P10.7 | 一笔一个历史项，往返一致 |
| P10.9 | 残影与定期全刷策略实机调参 | P10.7 | 明确阈值，离开编辑器恢复正常模式 |
| P10.10 | 构建 M2-B APK 与用户实笔 A/B | P10.9 | 明显改善；未改善则禁用 native feature flag |
| P10.11 | 分层记录 Android 历史压力、Flutter 压力、提交点压力范围 | P10.4 | 轻重变化有数值证据，不记录笔迹坐标 |
| P10.12 | 调查原生压感笔刷接口，区分实时与最终压感外观 | P10.11 | 不猜测 ABI 参数；无证据时保留固定宽度限制 |
| P10.13 | 压力归一化、提交和 `.bfly` 保存重开回归 | P10.11 | 逐点压力保持，最终 renderer 仍使用真实压力 |
| P10.14 | 根据流畅但等宽/全刷反馈，原生期间抑制 Flutter 活动前景与频繁 bake | P10.10 | 输入/pressure/ElementsCreated 保留，MOVE 不反复重建预览 |
| P10.15 | 修复 native 模式 onViewportUpdated 提前清空 submitted 的交接顺序 | P10.14 | renderer 插入后一次完成回调；压力和一次 undo 保持 |
| P10.16 | 抬笔 stop 不 destroy；Flutter 成帧后 setup/start/renderRect 只更新已完成笔迹区域 | P10.15 | 无逐笔 clear，DPR/合并/裁剪测试通过，新笔期间不清旧区域 |
| P10.17 | 真机轻重线和连续十笔复验，记录输入延迟、局部矩形及用户闪屏反馈 | P10.16 | 不把压力数值或局部调用返回成功当作视觉通过 |

## 6. P11：跨端、导出与同步闭环

| ID | 工作项 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P11.1 | Web release 构建并实际打开 device-saved fixture | P7.4 | 两页、图像、笔迹可见 |
| P11.2 | 电脑端新增测试笔迹并保存 | P11.1 | 文件可重新下载/落盘 |
| P11.3 | 平板重开电脑保存文件 | P11.2 | 原色、两端新增笔迹及 pressure 不丢 |
| P11.4 | 浅/深纸 PNG、SVG、PDF 导出 | P8.6 | 导出使用原色，不复用黑白缓存 |
| P11.5 | 真机 undo/redo、切页、缩放平移、旋转 smoke | P8.7 | 关键操作无崩溃/显示错位 |
| P11.6 | WebDAV/Nextcloud 无凭据路径、配置入口与错误提示 | P11.1 | 不泄露凭据；未配置时不宣称同步 |
| P11.7 | 用户提供服务参数后做双端真实同步 | P11.6 | 上传、下载、修改、冲突行为有证据；无参数则保持 blocked-not-failed |

## 7. P12：集成与交付

| ID | 工作项 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P12.1 | 主 agent 审查各提交和许可边界 | P8,P9,P10/P9 No-Go,P11 | 无厂商二进制/闭源源码进入 Git |
| P12.2 | 全量 test、analyze、formatter、diff check | P12.1 | 退出码 0 |
| P12.3 | ARMv7 reproducible build 两次并比较 hash | P12.2 | hash 一致或解释非确定来源 |
| P12.4 | 安装、冷启动、日志、保存重开最终验收 | P12.3 | 无 native/JNI 崩溃 |
| P12.5 | 更新 VERIFICATION、PRD/Plan 状态 | P12.4 | 通过/未通过/未验证明确 |
| P12.6 | 推送 `magicpie-monochrome` 并比对远端 OID | P12.5 | 不覆盖 develop、不强推 |
| P12.7 | 交付 APK、hash、源码和用户实笔结论 | P12.6 | 不把未通过延迟或同步写成完成 |

## 8. 当前执行状态

- [x] P7.1-P7.4：事实基线、PRD 和 Plan 已形成。
- [x] P8：73c37e04d 已实现并通过全量 103 项测试、analyze、构建及真机安装；用户反馈仍然很慢，低延迟目标需继续 P9/P10。
- [ ] P9：快写与 Android 4 笔完整事件通过，20 次生命周期调用及重启无崩溃；视觉恢复/刷新模式未全部验收。只批准 P10 有界实验，见 PROBE-VERIFICATION.md。
- [ ] P10：AC672368 主程序用户确认流畅、不消失、粗细实时显示；输入缓冲兼容、history补齐、连续原生会话、同步逐采样笔宽已实机观察。后续 F6565088 APK 真机保存/重开/撤销重做通过，普通测试136项通过。笔宽设置与缩放一致性、全生命周期/长期残影仍未全部验收，不能将所有P10子项勾完。见 NATIVE-INTEGRATION-VERIFICATION.md。
- [ ] P11：Windows Edge 实际打开平板压力笔迹→新增一笔→保存导出→刷新重开→平板冷启动打开的文件往返已通过；原94个元素完全保留。多页彩色图像的电脑UI验收、各导出格式、旋转仍待补齐；真实WebDAV/Nextcloud同步待服务参数，未配置不等于失败。
- [ ] P12：本轮代码审查、136项测试、analyze、格式检查、构建安装、冷启动、保存重开及提交推送通过；两次可重复构建比较和上述剩余验收未完成，非正式发行包。
