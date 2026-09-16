import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'batch_export/worker.dart';
import 'cubits/settings.dart';

@JS('bflyExport')
external set _exportFunction(JSFunction value);

@JS('bflyExportReady')
external set _exportReady(JSBoolean value);

@JS('bflyExportError')
external set _exportError(JSString value);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _exportReady = false.toJS;
  try {
    // Never read the normal application's connection or autosave preferences.
    SharedPreferences.setPrefix('bfly-export.', allowList: {});
    final settings = SettingsCubit(await SharedPreferences.getInstance());
    runApp(_ExportHost(settings: settings));
  } catch (error) {
    _exportError = error.toString().toJS;
  }
}

class _ExportHost extends StatefulWidget {
  final SettingsCubit settings;

  const _ExportHost({required this.settings});

  @override
  State<_ExportHost> createState() => _ExportHostState();
}

class _ExportHostState extends State<_ExportHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final worker = BatchExportWorker(context, widget.settings);
      _exportFunction = ((JSAny? request) => Future<JSAny?>(() async {
        final value = request.dartify();
        if (value is! Map) {
          throw const FormatException('Export request must be an object');
        }
        return (await worker.request(Map<String, dynamic>.from(value))).jsify();
      }).toJS).toJS;
      _exportReady = true.toJS;
    });
  }

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(color: Colors.white, child: SizedBox.expand()),
  );
}
