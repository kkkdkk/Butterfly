# Magicpie 原生手写探针验证

更新：2026-09-16。结论：批准 P10 默认关闭的有界接入实验；不批准默认启用，产品验收尚未完成。

## 真机与构建

- Magicpie M1，Android 8.1 / API 27。
- 独立包名 `dev.linwood.butterfly.magicpie.probe`，普通应用 UID。
- 探针 APK 无权限声明、无厂商 `.so`；运行时加载设备公开的 `libhandwriting_jni.so`。
- 当前设备 SELinux 为 Permissive；日志中的 EBC 访问记录带 `permissive=1`。此结果不代表 Enforcing 系统也能访问；测试没有修改 SELinux 或节点权限。

## 实笔结果与修正

1. Flutter 修复版 `73c37e04d` 已安装，用户反馈“仍然很慢”。这不能单独确定全部延迟的根因。
2. 原生探针 `6bf42f430` 调用 `init → setup → setBrush(4, 0, true) → start`，用户确认“写出来了，很流畅”。
3. `887918a50` 去掉 brush 调用后，用户反馈不能写。静态调用名称不足以推翻实机结果。
4. `be464f52e` 已恢复上述调用、重新构建并覆盖安装探针；用户实笔确认“可以，没有问题”。

恢复版 APK SHA256：

`21752478FCA963142A552DFDB8C51E46FCE1563F6EABC672344A1B39770EE473`

此前日志中同时出现 native 回调和 Android stylus 事件，但尚未逐笔验证完整 down/move/up；不能据此宣称 Flutter 输入完整性已通过。探针当前不向 Butterfly 提交文档数据，也不保存测试笔迹。

## 后续检查（2026-09-16）

- 保持已验证的 brush 调用，新增 Android down/move/up/cancel/history 计数；仅抬笔/取消时汇总日志，删除 native 高频坐标日志及 UI 更新。
- 计数版 APK SHA256：`C8604CA3D66747F16FE4BC3AD9D1B4CB487315F6D5603B851528A9B37F2330EF`，已安装。
- 00:30:41–00:32:19 完成 20 次停止、销毁、初始化和启动；日志均为 `Stopped; native result=false` 后接 `Native ink started`。stop 的 false 是停止后的状态，未按调用失败解读。
- 退到桌面再返回后可启动；force-stop 后新 PID 25564 再次启动成功。当前 crash buffer 为空。上述证明调用恢复成功；幽灵墨迹、真实笔事件恢复仍须实笔核对。
- Android sysfs `disabled_report_event` 读回为 I/O error，未把它当作状态已恢复的证据，未写该节点。
- Flutter 主分支 `flutter test --no-pub`：103/103 通过；`flutter analyze --no-pub`：无问题。
- 用户“写完了”后，00:37:40–00:37:43 日志确认实际 4 笔：累计 down=4、move=16、up=4、cancel=0、history=457、nativeEvents=702，started=true。每笔均有 down/move/up；history 表明 MOVE 含批量采样，nativeEvents 不能直接视为笔数。
- 这只证明 Android 事件链完整，尚不证明 Flutter Listener、文档点数与压力完整；后续接入保留 Flutter 原有输入和前景验证。
- 用户新增反馈：探针压感外观消失。当前探针笔刷固定宽度为 4；尚未分层记录压力数值，不能声称压力数据丢失或实时压感已支持。
- Probe 的 HANDWRITING_DISABLE 广播被系统拒绝（SecurityException），不能作为清理成功证据。产品实验使用已经测过的 stop/destroy，不依赖此广播，也不发送 ENABLE 广播。

## 进入产品集成前仍需完成

- 恢复版实笔复验；确认笔刷配置在重新初始化后仍有效。
- start/stop、暂停恢复、重复生命周期、进程退出后的显示与输入恢复。
- 对照每笔 Android down/move/up 与 native 回调，检查采样、坐标、笔压和取消事件。
- 验证原生显示与最终 Flutter 笔迹交接、连续两笔及一次撤销整笔。
- 保持未验证的刷新模式与其他 JNI 库关闭，逐项验证后再启用。
