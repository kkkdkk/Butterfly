# Magic Pie 实施计划

版本：1.0 · 2026-09-15 · 对应 [PRD](PRD.md)

## 1. 实施规则与集成拓扑

先提交 PRD 和本 Plan，再保留上轮未验证原型为独立 checkpoint。三个 Sol 从同一 checkpoint 分支，各自只修改分配文件；主 agent 负责工具链、总体验证、逐项审查和最终合并。

- 主目录：D:/code/works/butterfly-magicpie。
- 集成分支：magicpie-monochrome（基于 v2.5.5，不强推 develop）。
- worktree：项目内 .worktrees/ui、.worktrees/render、.worktrees/android。
- 分支：magicpie/ui、magicpie/render、magicpie/android。
- Flutter SDK：D:/code/works/butterfly-magicpie-toolchain/flutter。
- 共享工具链由主 agent 初始化；agent 不并行修改 SDK，不操作设备、不推送远端、不修改其他 worktree。
- 每个 agent 自己运行局部验证并提交，返回 commit、文件范围、测试结果、风险。由主 agent git merge --no-ff，并解决冲突，不能让 agent 自行合并到集成分支。
- API 契约：EinkDisplay.enabled 表示设备模式；EinkDisplay.initialize() 检测设备；EinkDisplay.paint(bool display, VoidCallback) 为同步屏显作用域；EinkDisplay.ink(Color) 仅改变作用域内显示颜色。若需扩展背景/前景映射，保留现有签名并通知主 agent。

## 2. P0：基线与文档（主 agent，先于开发）

| ID | 工作项 | 依赖 | 验收 / 输出 |
| --- | --- | --- | --- |
| P0.1 | 检查工作区、目标 GitHub 及当前变更 | 无 | 已有仓库、公开性、develop OID、改动清单 |
| P0.2 | 编写 PRD：范围、边界、数据策略、验收 | P0.1 | docs/magicpie/PRD.md 已提交 |
| P0.3 | 编写细粒度 Plan、所有权、测试矩阵 | P0.2 | 本文已提交 |
| P0.4 | checkpoint 保存原型，不宣称已测试 | P0.3 | 独立 git commit；不混入凭据 |
| P0.5 | 配置 origin=用户仓库，upstream=LinwoodDev/Butterfly，保留旧 remote 名 | P0.1 | fetch 后核对祖先关系；不覆盖默认分支 |
| P0.6 | 忽略 .worktrees 和本地验证输出，建立三 worktree | P0.4 | 三分支 HEAD 一致、路径全部在 D 盘项目内 |

## 3. P1：工具链准备（主 agent，与 P2-P4 并行）

| ID | 工作项 | 依赖 | 验收 / 输出 |
| --- | --- | --- | --- |
| P1.1 | 检查 Flutter 3.44.9 / Dart，恢复中断下载 | P0.3 | flutter --version 成功 |
| P1.2 | 检查 Java、Android SDK/NDK/build tools、Rust | P1.1 | flutter doctor 输出；构建缺项清单 |
| P1.3 | api/app 拉取依赖、按上游流程生成代码/本地化 | P1.1 | pub get、codegen 成功；不无故升级 lockfile |
| P1.4 | 给三个 agent 提供 SDK/缓存环境与可用命令 | P1.3 | 明确通知；agent 在各自 app 目录验证 |

## 4. P2：黑白主题和控件（Sol UI）

所有权：app/lib/theme.dart、app/lib/views/toolbar/color.dart、app/lib/widgets/color_field.dart；必要的同类 UI 文件需先报告；新增 app/test/eink/ui_*_test.dart。不得修改 helper / renderer / Android。

| ID | 工作项 | 依赖 | 验收 / 输出 |
| --- | --- | --- | --- |
| P2.1 | 审查原型主题和 FlexColorScheme 输出 | P0.6 | 列出 primary/secondary/tertiary/error/container 等处理策略 |
| P2.2 | 实现无彩色高对比主题及选择状态 | P2.1 | AC-02；不影响普通设备主题 |
| P2.3 | 隐藏 palette/eyedropper/颜色属性，保留非颜色动作 | P2.1 | AC-03；不写文档颜色 |
| P2.4 | 验证 NumberInput 参数、竖屏布局与空控件行 | P2.3 | 无 overflow / 构造器错误 |
| P2.5 | 审查选择框/控制点所需主题；通知 render owner | P2.2 | 明确责任边界 |
| P2.6 | 添加 enabled/disabled 对照测试、格式与局部分析 | P1.4,P2.4 | 测试命令和退出码 |
| P2.7 | 自审 diff，提交并交接 | P2.6 | commit 与已知限制 |

## 5. P3：屏显、缓存、导出与文件兼容（Sol Render）

所有权：app/lib/helpers/eink.dart、app/lib/renderers/**、app/lib/view_painter.dart、app/lib/cubits/current_index.dart、app/lib/views/view.dart；需要时 app/lib/models/viewport.dart；新增 app/test/eink/render_*_test.dart。不修改 UI owner 文件、main.dart、Android。

| ID | 工作项 | 依赖 | 验收 / 输出 |
| --- | --- | --- | --- |
| P3.1 | 列出预览、屏显、缓存、导出调用链 | P0.6 | 各 ViewPainter 调用分类，确认 unbake 层缓存行为 |
| P3.2 | 完善作用域隔离及颜色映射，保留透明/白色 | P3.1 | 嵌套、异常退出后作用域恢复单测 |
| P3.3 | 覆盖笔、形状、文字前景；明确背景和网格规则 | P3.2 | 不整屏滤色、不修改图/PDF 内容，暗底边界有测试 |
| P3.4 | 保证 ForegroundPainter 和缓存使用同一显示策略 | P3.3 | 预览/烘焙后的像素一致；shouldRepaint 检查 |
| P3.5 | 隔离 PNG/SVG/PDF 导出与所有层级屏显缓存 | P3.4 | 含缓存的 raster/export 回归测试 |
| P3.6 | .bfly 保存/读取保留颜色和导入资产 | P3.3 | round-trip 数据测试；普通设备对照 |
| P3.7 | 格式、相关分析和测试，提交交接 | P1.4,P3.5,P3.6 | commit；明确不透明高亮等限制 |

## 6. P4：设备识别和安装包配置（Sol Android）

所有权：app/android/**（不提交 local.properties、密钥或 build 输出）、app/lib/main.dart；新增 tools/magicpie/build.ps1、app/test/eink/platform_*_test.dart、docs/magicpie/BUILD.md。helper 接口由 Render owner 管理，异常策略通过消息协调。

| ID | 工作项 | 依赖 | 验收 / 输出 |
| --- | --- | --- | --- |
| P4.1 | 检查设备识别通道与启动时序 | P0.6 | 无插件/通道异常安全回退建议及测试 |
| P4.2 | 添加 magicpie flavor 与独立 app ID/可辨识名称 | P4.1 | 不改变 production/nightly 配置 |
| P4.3 | 编写 D 盘本地构建脚本，ARMv7 + legacy packaging | P4.2 | 可参数化 SDK 路径、显式失败退出、无私钥 |
| P4.4 | 记录 Java/SDK/Rust/依赖生成及签名说明 | P4.3 | BUILD.md 可复现命令，测试签名不是正式签名 |
| P4.5 | 局部验证，提交交接 | P1.4,P4.4 | commit 与主 agent 最终构建命令 |

## 7. P5：主 agent 审查与合并

| ID | 工作项 | 依赖 | 验收 / 输出 |
| --- | --- | --- | --- |
| P5.1 | 逐一核对提交范围、PRD 覆盖和测试证据 | P2.7,P3.7,P4.5 | 审查记录；不足则定向退回原 owner |
| P5.2 | 依次 merge Android、Render、UI（必要时调整） | P5.1 | 非快进合并记录，无未处理冲突 |
| P5.3 | 集成后格式检查、分析、相关 tests + 上游关键 tests | P5.2 | AC-01 至 AC-07；区分上游已有问题 |
| P5.4 | 构建 ARMv7 legacy release APK | P5.3 | 成功退出、aapt 包名/SDK/ABI、SHA256 |

## 8. P6：真机与交付（只由主 agent 操作）

| ID | 工作项 | 依赖 | 验收 / 输出 |
| --- | --- | --- | --- |
| P6.1 | 重新确认 ADB 设备身份、安装定制版 | P5.4 | install 成功；不无故卸载原版 |
| P6.2 | 启动、主题和控件截图；检查启动崩溃 | P6.1 | AC-02/03/08 实机证据 |
| P6.3 | 新建测试笔记、画线、撤销重做、保存、重开 | P6.2 | 数据和显示一致；ADB 模拟线不冒充真实笔压测试 |
| P6.4 | 彩色 fixture 与导出验证；普通设备/桌面兼容 | P6.3 | 可自动化部分实测；不可执行部分明确标记 |
| P6.5 | 写验收报告与限制、构建产物说明 | P6.4 | docs/magicpie/VERIFICATION.md |
| P6.6 | 推送集成分支到用户仓库并比对 OID | P6.5 | AC-09；不强推、不发布虚假成功 release |
| P6.7 | 交付 APK/文档/GitHub 分支，告知需用户实笔体验项 | P6.6 | 清晰区分通过、未测和后续 M2 |

## 9. 阻塞与回退

下载/依赖失败先定位具体端点与错误，尝试安全的官方替代；不降级整个项目、不用随机二进制。构建失败记录可复现命令并继续其他独立验证。设备离线可继续测试/构建，但不能声称真机通过。无 root/系统签名时不尝试刷机。合并冲突由主 agent 精确解决；保留 checkpoint 和各 agent 分支，不删除用户目录。现有 develop 不改写，回退可切回上游 APK。

## 10. 执行状态

- [x] P0.1 目标仓库和连接设备已确认。
- [x] P0.2 / P0.3 文档形成；后续提交与实施状态以 Git 和验收报告为准。
- [x] P0.4-P0.6 基线与 worktree（项目内 `.worktrees`）。
- [x] P1 工具链（Flutter、Android SDK、Pub/Gradle 缓存位于 D 盘）。
- [x] P2 / P3 / P4 三个 Sol 工作包已审查、返修并合并。
- [x] P5 合并、100 项测试、静态分析和 ARMv7 构建通过。
- [x] P6.1 / P6.2 安装与冷启动通过；JNI 注册缺失已修复并实机复验。
- [ ] P6.3 / P6.4 部分通过：实笔写入、保存重开、原色属性/PNG 保留已验证；撤销重做、桌面实际编辑及全导出流程未完成。用户实笔反馈明显延迟，低延迟目标未达标。
- [x] P6.5 验收报告已形成，见 [VERIFICATION.md](VERIFICATION.md)。
- [x] P6.6 集成分支已推送至 `kkkdkk/Butterfly`，远端与本地 OID 比对一致；未覆盖 develop。
- [x] P6.7 黑白适配测试包已安装并作阶段交付，限制见验收报告；不能将本轮交付描述为低延迟目标完成。
