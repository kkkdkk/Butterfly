# Magicpie 原生手写探针验证

更新：2026-09-16。产品集成结论：待验证，尚未批准 P10。

## 真机与构建

- Magicpie M1，Android 8.1 / API 27。
- 独立包名 `dev.linwood.butterfly.magicpie.probe`，普通应用 UID。
- 探针 APK 无权限声明、无厂商 `.so`；运行时加载设备公开的 `libhandwriting_jni.so`。
- 当前设备 SELinux 为 Permissive；日志中的 EBC 访问记录带 `permissive=1`。此结果不代表 Enforcing 系统也能访问；测试没有修改 SELinux 或节点权限。

## 实笔结果与修正

1. Flutter 修复版 `73c37e04d` 已安装，用户反馈“仍然很慢”。这不能单独确定全部延迟的根因。
2. 原生探针 `6bf42f430` 调用 `init → setup → setBrush(4, 0, true) → start`，用户确认“写出来了，很流畅”。
3. `887918a50` 去掉 brush 调用后，用户反馈不能写。静态调用名称不足以推翻实机结果。
4. `be464f52e` 已恢复上述调用、重新构建并覆盖安装探针；当前界面确认 `Native ink started`。恢复版实笔体验待用户复验。

恢复版 APK SHA256：

`21752478FCA963142A552DFDB8C51E46FCE1563F6EABC672344A1B39770EE473`

此前日志中同时出现 native 回调和 Android stylus 事件，但尚未逐笔验证完整 down/move/up；不能据此宣称 Flutter 输入完整性已通过。探针当前不向 Butterfly 提交文档数据，也不保存测试笔迹。

## 进入产品集成前仍需完成

- 恢复版实笔复验；确认笔刷配置在重新初始化后仍有效。
- start/stop、暂停恢复、重复生命周期、进程退出后的显示与输入恢复。
- 对照每笔 Android down/move/up 与 native 回调，检查采样、坐标、笔压和取消事件。
- 验证原生显示与最终 Flutter 笔迹交接、连续两笔及一次撤销整笔。
- 保持未验证的刷新模式与其他 JNI 库关闭，逐项验证后再启用。
