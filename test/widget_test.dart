import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/main.dart';
import 'package:reminder_app/models.dart';
import 'package:reminder_app/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Motor de Recurrencia Combinado (Fecha + Hora en Grilla Fija)', () {
    test('Once: dispara solo en la fecha configurada y nunca después', () {
      final r = Reminder(
        id: 'once_1',
        name: 'Turno médico',
        dateRule: DateRuleType.once,
        anchorDate: '2026-11-05',
        timeRule: TimeRuleType.fixed,
        startMinute: 9 * 60 + 30, // 09:30
      );

      expect(
        r.nextEffectiveTrigger(DateTime(2026, 11, 1, 10, 0), {}),
        DateTime(2026, 11, 5, 9, 30),
      );
      expect(
        r.nextEffectiveTrigger(DateTime(2026, 11, 5, 9, 31), {}),
        isNull,
      );
    });

    test('Weekdays + Hourly: respeta ventana activa y salta fines de semana', () {
      // 2026-11-06 es Viernes; 2026-11-07 Sábado; 2026-11-09 Lunes
      final r = Reminder(
        id: 'wk_1',
        name: 'Pausa activa',
        dateRule: DateRuleType.weekdays,
        anchorDate: '2026-11-02',
        weekdays: [1, 2, 3, 4, 5], // Lun a Vie
        timeRule: TimeRuleType.hourly,
        startMinute: 9 * 60, // 09:00
        endMinute: 17 * 60, // 17:00
        intervalMinutes: 120, // cada 2h -> 09, 11, 13, 15, 17
      );

      // Viernes 16:00 -> próximo disparo Viernes 17:00
      expect(
        r.nextEffectiveTrigger(DateTime(2026, 11, 6, 16, 0), {}),
        DateTime(2026, 11, 6, 17, 0),
      );

      // Viernes 17:05 (fuera de ventana) -> salta Sáb/Dom y agenda Lunes 09:00
      expect(
        r.nextEffectiveTrigger(DateTime(2026, 11, 6, 17, 5), {}),
        DateTime(2026, 11, 9, 9, 0),
      );
    });

    test('Every N Days / Weeks / Months calcula intervalos exactos', () {
      final every3Days = Reminder(
        id: 'd3',
        name: 'Riego',
        dateRule: DateRuleType.everyN,
        anchorDate: '2026-11-01',
        everyN: 3,
        everyUnit: IntervalUnit.days,
        timeRule: TimeRuleType.fixed,
        startMinute: 8 * 60,
      );
      expect(
        every3Days.nextEffectiveTrigger(DateTime(2026, 11, 1, 9, 0), {}),
        DateTime(2026, 11, 4, 8, 0),
      );

      final every2Weeks = Reminder(
        id: 'w2',
        name: 'Limpieza',
        dateRule: DateRuleType.everyN,
        anchorDate: '2026-11-02', // Lunes
        everyN: 2,
        everyUnit: IntervalUnit.weeks,
        timeRule: TimeRuleType.fixed,
        startMinute: 10 * 60,
      );
      expect(
        every2Weeks.nextEffectiveTrigger(DateTime(2026, 11, 2, 10, 1), {}),
        DateTime(2026, 11, 16, 10, 0),
      );

      final every2Months = Reminder(
        id: 'm2',
        name: 'Filtro',
        dateRule: DateRuleType.everyN,
        anchorDate: '2026-11-15',
        everyN: 2,
        everyUnit: IntervalUnit.months,
        timeRule: TimeRuleType.fixed,
        startMinute: 12 * 60,
      );
      expect(
        every2Months.nextEffectiveTrigger(DateTime(2026, 11, 15, 12, 1), {}),
        DateTime(2027, 1, 15, 12, 0),
      );
    });

    test('Grilla fija se mantiene intacta tras snooze y "Saltar proxima alarma"', () {
      final r = Reminder(
        id: 'grid_1',
        name: 'Agua',
        dateRule: DateRuleType.weekdays,
        anchorDate: '2026-11-02',
        timeRule: TimeRuleType.hourly,
        startMinute: 8 * 60, // 08:00
        endMinute: 14 * 60, // 14:00
        intervalMinutes: 120, // 08:00, 10:00, 12:00, 14:00
      );

      // Si se aplazó a las 10:10, el próximo efectivo es el snooze (10:10),
      // pero la grilla posterior sigue siendo las 12:00 en punto (no 12:10).
      r.snoozedUntilMs = DateTime(2026, 11, 2, 10, 10).millisecondsSinceEpoch;
      expect(
        r.nextEffectiveTrigger(DateTime(2026, 11, 2, 10, 2), {}),
        DateTime(2026, 11, 2, 10, 10),
      );
      expect(
        r.nextEffectiveTrigger(DateTime(2026, 11, 2, 10, 15), {}),
        DateTime(2026, 11, 2, 12, 0),
      );

      // Saltar la alarma de las 12:00 pasa directo a las 14:00
      r.snoozedUntilMs = null;
      r.skipUntilMs = DateTime(2026, 11, 2, 12, 0).millisecondsSinceEpoch;
      expect(
        r.nextEffectiveTrigger(DateTime(2026, 11, 2, 11, 0), {}),
        DateTime(2026, 11, 2, 14, 0),
      );
    });
  });

  group('2. Carpetas con Memoria y Persistencia ante Reinicio / Apagado', () {
    test('Switch maestro de carpeta apaga alarmas pero conserva memoria individual', () {
      final folder = Folder(id: 'f1', name: 'Salud', isEnabled: true);
      final rOn = Reminder(
        id: 'r_on',
        folderId: 'f1',
        name: 'Vitamina',
        isEnabled: true,
        anchorDate: '2026-11-02',
      );
      final rOff = Reminder(
        id: 'r_off',
        folderId: 'f1',
        name: 'Magnesio',
        isEnabled: false,
        anchorDate: '2026-11-02',
      );
      final now = DateTime(2026, 11, 2, 7, 0);

      // Con carpeta activa: solo rOn programa disparo
      expect(rOn.nextEffectiveTrigger(now, {'f1': folder}), isNotNull);
      expect(rOff.nextEffectiveTrigger(now, {'f1': folder}), isNull);

      // Apagar carpeta: ninguna programa disparo, pero rOn.isEnabled sigue true y rOff.isEnabled false
      folder.isEnabled = false;
      expect(rOn.nextEffectiveTrigger(now, {'f1': folder}), isNull);
      expect(rOff.nextEffectiveTrigger(now, {'f1': folder}), isNull);
      expect(rOn.isEnabled, isTrue);
      expect(rOff.isEnabled, isFalse);

      // Volver a encender carpeta: restaura únicamente rOn
      folder.isEnabled = true;
      expect(rOn.nextEffectiveTrigger(now, {'f1': folder}), isNotNull);
      expect(rOff.nextEffectiveTrigger(now, {'f1': folder}), isNull);
    });

    test('Persistencia en disco (state.json) sobrevive apagado/reinicio del dispositivo', () async {
      final tmpDir = await Directory.systemTemp.createTemp('oled_reboot_test');
      final stateFile = File('${tmpDir.path}/state.json');
      int syncScheduleCalls = 0;

      Storage.resetPathForTests();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('alarm'), (call) async {
        if (call.method == 'getStateFilePath') return stateFile.path;
        if (call.method == 'syncSchedule') {
          syncScheduleCalls++;
          return null;
        }
        return null;
      });

      final initial = AppState(
        folders: [
          Folder(id: 'f_work', name: 'Trabajo', isEnabled: false),
        ],
        reminders: [
          Reminder(
            id: 'r1',
            folderId: 'f_work',
            name: 'Daily',
            note: 'Zoom link',
            isEnabled: true,
            anchorDate: '2026-11-02',
            timeRule: TimeRuleType.hourly,
            startMinute: 540,
            endMinute: 1080,
            intervalMinutes: 60,
            customVolume: 90,
          ),
        ],
        settings: AppSettings(
          ringDurationMinutes: 2,
          autoSnoozeMinutes: 5,
          maxAutoRetries: 4,
        ),
      );

      await Storage.saveAndSync(initial);
      expect(syncScheduleCalls, 1);
      expect(await stateFile.exists(), isTrue);

      // Simular reinicio del teléfono: lectura fría desde state.json
      final afterReboot = await Storage.load();
      expect(afterReboot.folders.single.name, 'Trabajo');
      expect(afterReboot.folders.single.isEnabled, isFalse);
      expect(afterReboot.reminders.single.name, 'Daily');
      expect(afterReboot.reminders.single.isEnabled, isTrue); // Memoria preservada
      expect(afterReboot.reminders.single.customVolume, 90);
      expect(afterReboot.settings.maxAutoRetries, 4);

      await tmpDir.delete(recursive: true);
    });

    test('AndroidManifest declara DirectBoot y receivers de BOOT_COMPLETED / QUICKBOOT', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android.permission.RECEIVE_BOOT_COMPLETED'), isTrue);
      expect(manifest.contains('android.permission.USE_EXACT_ALARM'), isTrue);
      expect(manifest.contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'), isTrue);
      expect(manifest.contains('android:directBootAware="true"'), isTrue);
      expect(manifest.contains('android.intent.action.BOOT_COMPLETED'), isTrue);
      expect(manifest.contains('android.intent.action.LOCKED_BOOT_COMPLETED'), isTrue);
      expect(manifest.contains('android.intent.action.QUICKBOOT_POWERON'), isTrue);
      expect(manifest.contains('android.intent.action.TIME_SET'), isTrue);
      expect(manifest.contains('android.intent.action.TIMEZONE_CHANGED'), isTrue);
    });
  });

  group('3. UI OLED, Orden de Carpetas y Pantalla de Disparo (RingingScreen)', () {
    testWidgets('Tema OLED negro puro (#000000), carpetas arriba y sin carpeta al final, botón "Saltar proxima alarma"', (tester) async {
      late Directory tmpDir;
      late File stateFile;
      await tester.runAsync(() async {
        tmpDir = await Directory.systemTemp.createTemp('oled_ui_test');
        stateFile = File('${tmpDir.path}/state.json');

        final seeded = AppState(
          folders: [
            Folder(id: 'f1', name: 'Carpeta Salud', isEnabled: true, isExpanded: true),
          ],
          reminders: [
            Reminder(
              id: 'r_ungrouped',
              folderId: null,
              name: 'Alarma Suelta Final',
              isEnabled: true,
              anchorDate: fmtDate(DateTime.now()),
            ),
            Reminder(
              id: 'r_folder',
              folderId: 'f1',
              name: 'Alarma En Carpeta',
              isEnabled: true,
              anchorDate: fmtDate(DateTime.now()),
            ),
          ],
        );
        await stateFile.writeAsString(jsonEncode(seeded.toJson()));
      });

      Storage.resetPathForTests();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('alarm'), (call) async {
        switch (call.method) {
          case 'getStateFilePath':
            return stateFile.path;
          case 'getRingingAlarm':
            return null;
          case 'getPermissionStatus':
            return {
              'battery': true,
              'exactAlarm': true,
              'notifications': true,
              'fullScreen': true,
              'unusedApps': false,
            };
          case 'syncSchedule':
            return null;
        }
        return null;
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(const OledAlarmApp());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verificar fondo OLED negro puro (#000000)
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor ?? Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor, Colors.black);

      // Verificar que la carpeta se renderiza ANTES (arriba) que las alarmas SIN CARPETA
      final folderPos = tester.getTopLeft(find.text('Carpeta Salud'));
      final ungroupedHeaderPos = tester.getTopLeft(find.text('SIN CARPETA'));
      final ungroupedAlarmPos = tester.getTopLeft(find.text('Alarma Suelta Final'));
      expect(folderPos.dy < ungroupedHeaderPos.dy, isTrue);
      expect(ungroupedHeaderPos.dy < ungroupedAlarmPos.dy, isTrue);

      // Verificar string exacto del botón "Saltar proxima alarma"
      expect(find.text('Saltar proxima alarma'), findsNWidgets(2));

      // Verificar punto indicador en engranaje y en escudo cuando falta algún permiso (unusedApps: false)
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Faltan 1 permisos por activar'), findsOneWidget);
      await tester.tap(find.text('Permisos y Blindaje Anti-Batería'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Desactivar "Administrar aplicación no usada"'), findsOneWidget);
      Navigator.of(tester.element(find.text('Desactivar "Administrar aplicación no usada"'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verificar que crear una alarma nueva desde el editor la agrega a HomeScreen y guarda en disco
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byType(TextField).first,
        'Alarma Creada En Test',
      );
      await tester.tap(find.text('GUARDAR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.widgetWithText(InkWell, 'Alarma Creada En Test'), findsOneWidget);

      await tester.runAsync(() async {
        await tmpDir.delete(recursive: true);
      });
    });

    testWidgets('RingingScreen muestra nombre, nota y botones únicos de Aplazar y Apagar', (tester) async {
      bool dismissed = false;
      bool snoozed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: RingingScreen(
            alarm: const {
              'id': 'r1',
              'name': 'Tomar antibiótico',
              'note': 'Con un vaso lleno de agua',
              'snoozeMinutes': 15,
              'retryCount': 2,
            },
            onDismiss: () => dismissed = true,
            onSnooze: () => snoozed = true,
          ),
        ),
      );

      expect(find.text('Tomar antibiótico'), findsOneWidget);
      expect(find.text('Con un vaso lleno de agua'), findsOneWidget);
      expect(find.text('Aplazar (15m)'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.text('Aplazar (15m)'));
      expect(snoozed, isTrue);

      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });
  });
}
