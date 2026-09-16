# Magicpie 墨水屏开发文档

以后开发这块屏的书写功能，先看 **[问题与解决手册](HANDWRITING-RUNBOOK.md)**：症状速查、已证实原因、可复用架构、源码/测试入口、命令和未验收边界。

- [构建说明](BUILD.md)：工具链、插件注册、签名和APK边界。
- [M2 PRD](PRD-M2.md) 与 [执行计划](PLAN-M2.md)：需求与剩余验收。
- [原生集成逐轮证据](NATIVE-INTEGRATION-VERIFICATION.md)：包括失败实验，当前总结以手册和文末最新验收为准。
- [独立探针验证](PROBE-VERIFICATION.md) 与 [探针README](../../tools/magicpie/native_probe/README.md)：隔离系统快写与Flutter。
- [M1历史验收](VERIFICATION.md)：早期慢笔版本，不代表当前结果。

当前已验证：实体笔流畅且实时粗细；撤销/重做保存与冷启动；电脑编辑后回平板的 `.bfly` 文件往返。未配置真实云同步，不将剩余边界测试标作完成。
