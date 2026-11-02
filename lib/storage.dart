import 'dart:convert';
import 'dart:io';
import 'alarm_api.dart';
import 'models.dart';

class Storage {
  static String? _path;

  static Future<File> _file() async {
    _path ??= await AlarmApi.getStateFilePath();
    return File(_path!);
  }

  static Future<AppState> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return AppState();
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return AppState();
      return AppState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppState();
    }
  }

  static Future<void> saveAndSync(AppState state) async {
    final f = await _file();
    await f.writeAsString(state.toJsonString(), flush: true);
    await AlarmApi.syncSchedule();
  }
}
