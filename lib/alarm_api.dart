import 'package:flutter/services.dart';

class AlarmApi {
  static const _ch = MethodChannel('alarm');

  static void setEventHandler(Future<void> Function(String event) onEvent) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onStateChanged') {
        await onEvent((call.arguments as String?) ?? 'reload');
      }
    });
  }

  static Future<String> getStateFilePath() async =>
      (await _ch.invokeMethod<String>('getStateFilePath'))!;

  static Future<void> syncSchedule() async =>
      await _ch.invokeMethod<void>('syncSchedule');

  static Future<Map<String, dynamic>?> getRingingAlarm() async {
    final res = await _ch.invokeMapMethod<String, dynamic>('getRingingAlarm');
    return res;
  }

  static Future<void> dismissRinging() async =>
      await _ch.invokeMethod<void>('dismissRinging');

  static Future<void> snoozeRinging() async =>
      await _ch.invokeMethod<void>('snoozeRinging');

  static Future<Map<String, String>?> pickSystemAlarmTone(
    String currentUri,
  ) async => await _ch.invokeMapMethod<String, String>('pickSystemAlarmTone', {
    'currentUri': currentUri,
  });

  static Future<Map<String, String>?> pickAudioFile() async =>
      await _ch.invokeMapMethod<String, String>('pickAudioFile');

  static Future<Map<String, bool>> getPermissionStatus() async {
    final res = await _ch.invokeMapMethod<String, bool>('getPermissionStatus');
    return res ?? {};
  }

  static Future<void> requestPermission(String kind) async =>
      await _ch.invokeMethod<void>('requestPermission', {'kind': kind});
}
