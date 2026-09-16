# bfly-export：本地 `.bfly → PNG` 命令行

独立于 Butterfly GUI 的只读导出工具，复用项目现有 Flutter 渲染器，包括压感轮廓。支持多文件/文件夹、页面选择、Area 和源文件哈希清单，供后续识别使用。**这是本仓库新增工具，不是官方 Butterfly 2.5.5 内置命令，也不是已发布的独立 exe。**

不修改 Android/native 书写链路，不打开同步连接，不调用 AI。源 `.bfly` 不写入、不删除。

## 准备一次

需要 Node.js 20+、本项目兼容的 Flutter SDK（已验证 3.44.9）、Edge/Chrome 或 Playwright Chromium。当前电脑已完成安装依赖与构建，可直接使用。

在仓库根目录：

```powershell
npm ci --prefix tools/bfly-export
.\tools\bfly-export\build.ps1
```

构建脚本默认使用本机 D 盘工具链；其他电脑指定 `-FlutterSdk 'D:\path\flutter' -PubCache 'D:\path\pub-cache'`。输出 `app/build/bfly-export`，源码改变后重新构建。Linux/macOS 可在 `app` 目录运行：

```sh
flutter build web --release --target lib/bfly_export_main.dart --no-web-resources-cdn --output build/bfly-export
```

默认 Windows 优先使用 Edge，其次 Chrome；若没有可用浏览器，在 `tools/bfly-export` 中运行 `npx playwright install chromium`。其他平台默认使用 Chromium。依赖安装可能联网，实际导出不需要联网。

## 使用

以下 `D:\Notes` 路径是示例，替换为实际文件和新输出目录：

```powershell
# 单文件，所有页面（默认），无需启动 Butterfly 窗口
.\tools\bfly-export\bfly-export.cmd 'D:\Notes\原稿.bfly' --output 'D:\Notes\rendered\run-001'

# 文件夹中的所有 .bfly（不递归），优先逐 Area 导出；无 Area 的页退回整页
.\tools\bfly-export\bfly-export.cmd 'D:\Notes\originals' --output 'D:\Notes\rendered\run-002' --areas

# 按页面名选择，可重复 --page；内部 key 优先于同名显示名称
.\tools\bfly-export\bfly-export.cmd 'D:\Notes\原稿.bfly' --output 'D:\Notes\rendered\run-003' --page 'Page 1' --areas

# 笔记包含打字中文时，指定本地且包含对应字形的字体；手写线条不需要字体
.\tools\bfly-export\bfly-export.cmd 'D:\Notes\原稿.bfly' --output 'D:\Notes\rendered\run-004' --areas --font 'C:\Windows\Fonts\msyh.ttc'

# 非 Windows 或希望显式用 Node
node tools/bfly-export/cli.mjs 'D:\Notes\原稿.bfly' --output 'D:\Notes\rendered\run-005'
```

`--help` 查看全部参数。默认 `--scale 2 --max-dimension 4096 --max-pixels 16777216 --margin 24`；边距仅用于整页，Area 严格按区域边界裁剪。尺寸或像素数超限时等比例缩小，在 manifest 标注 `limited`、`actualScale` 和 warning。可提高上限，但最多边长 8192、33554432 像素。

输出示意：

```text
run-001/
  note-原稿-<SHA256前16位>/
    page-0001.png
    page-0002.png
    manifest.json
```

Area 图片为 `page-0001-area-0001.png`。manifest 记录完整源 SHA256、文件大小、源绝对路径、页/Area 名称和索引、原始画布坐标、输出尺寸、实际比例、warning，以及自选字体的名称/哈希。**共享 manifest 时注意它包含本机文件路径。**

stdout 每个成功源文件一行 JSON（含 manifest 路径）；进度和错误写 stderr。所有输入成功退出 0，有失败退出 1。单个损坏文档失败后继续下个文档；操作超时则结束整个批次，避免复用未完成的渲染任务。

## 完整性和边界

- 原稿只读：先读取快照，导出后再次校验源 SHA256；变化则丢弃本次临时输出。同步中的文件应等保存/下载完成后再处理。
- 先在输出根内建立独占临时子目录，全部 PNG 校验通过后发布；失败只清理该次生成的临时目录。已有输出拒绝覆盖。不同目录的同名同内容文件会得到相同目标名，第二份明确失败；换输出目录处理，不静默覆盖。
- PNG 检查签名、chunk 完整性、CRC、尺寸上限，并在浏览器中真实解码后才写入完成清单。
- 浏览器使用临时独立上下文，只访问 `127.0.0.1` 随机端口的本地构建文件；外部页面资源请求被拦截。原稿通过内存传入，不经网络上传，未连接笔记账号或 WebDAV。
- 字体从用户指定路径只读加载到本次浏览器进程，不复制/提交 Windows 字体。`--font` 替代导出进程里的 Roboto 字体，可能改变打字文本的字宽、换行和粗斜体外观，不保证与原电脑排版逐像素相同。中文输入经本机微软雅黑实图验证；无字体时可能出现缺字 warning 或因外部字体请求被拦截而失败。不要把方框当作成功识别。
- 导出文件中的所有图层，不继承其他 GUI 窗口临时隐藏的图层；该隐藏状态并未保存进 `.bfly`。不包含选框、工具栏或屏幕缓存。
- 当前只导出 PNG，不做 OCR，不生成 Mermaid/draw.io/Excalidraw，不监控文件夹，也不修复同步权限。
- **超大画布目前仅缩放，没有高清分块。** 用于 AI 识字时优先建立 Area；检查 `limited`，不要直接拿缩小到看不清的全景图识别。空白页使用 1024×768 文档单位的有限范围。
- 输入最多 256 MiB、500 页，单次最多 1000 张图；仅供受信任的本地笔记，不是隔离任意恶意文档的安全沙箱。
- 外部/丢失图像资产明确失败。**嵌入 PDF 暂不支持**，应先在 Butterfly 转成图片；当前不接入 PDF WASM 后端。加密文档没有密码入口，先另存为受控的未加密副本。SVG/数学等复用上游能力，尚未完成全部元素类型的实图验收。
- 当前已验收 Windows + Edge 的本地 release worker；其他平台有入口，但不宣称已实机测试。

## 回归测试

只使用生成的合成笔迹，不采集个人笔记。仓库根目录运行：

```powershell
npm test --prefix tools/bfly-export
# 用项目的 Dart/Flutter 工具链生成样本（拒绝覆盖已有文件）
Push-Location app
& 'D:\code\works\butterfly-magicpie-toolchain\flutter\bin\dart.bat' run tool/bfly_export_fixture.dart ../.magicpie-output/bfly-export/fixture.bfly ../.magicpie-output/bfly-export/empty.bfly
Pop-Location
# 返回仓库根目录，先完成上面的 release 构建
node tools/bfly-export/test/smoke.mjs .magicpie-output/bfly-export/fixture.bfly .magicpie-output/bfly-export/empty.bfly
```

`smoke.mjs` 每次在 `.magicpie-output/bfly-export` 新建目录，保留合成 PNG 与 manifest 供复核。覆盖顺序多文件、目录非递归、整页/Area/指定页、负坐标、尺寸预算、拒绝覆盖、无效输入及源哈希；像素检查两条相反压感曲线和 6×6 棋盘格内嵌图片。

中文实图测试：生成器加 `--cjk` 输出另一份合成文件，再用 `--font` 导出，人工确认“中文导出测试：压感、笔记、流程图”可读。Flutter worker 测试位于 `app/test/batch_export`。

### 2026-09-16 验收记录

- Flutter release Web 构建成功；全套 147 项 Flutter 测试、7 项 Node 测试通过，静态分析无问题。
- 9 个真实 CLI 场景通过；Canvas 像素验证压感线分别为 `18 → 84 px` 与 `86 → 20 px`，棋盘图 `36/36` 格符合原图。
- 负坐标 Area 为 1600×840，圆形未裁断；空白页为 2048×1536；远距离元素整页按上限缩放，并在 manifest 明确标记。原始合成文件 SHA256 全程不变。
- 中文字体第一次测试曾导出方框：仅 `FontLoader('Roboto')` 追加中文字体仍会选中内置 Latin Roboto。修复是在 `--font` 模式下，仅替本次浏览器请求过滤 FontManifest 的内置 Roboto，再注册本地字体；不改磁盘构建文件和主应用。微软雅黑再次实图检查中文字形正常。
- 不将合成测试等同于所有个人笔记/元素类型兼容；未运行 AI 识别或连接 WebDAV。

后续识别路线见 [AI-INGEST-PLAN](../../docs/magicpie/AI-INGEST-PLAN.md)。首次建议人工发起一份小文档，把成功导出的 PNG 和 manifest 交给当前任务；识别准确率需要另行验收。
