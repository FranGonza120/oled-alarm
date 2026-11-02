# OLED Alarm Reminder App (Android / Flutter)

Aplicación Android en Flutter para recordatorios tipo alarma de alta confiabilidad, bajo consumo de batería y tema OLED (`#000000`).

## Requerimientos Funcionales (Ver detalle completo en [`docs/SPEC.md`](docs/SPEC.md))
1. **Recordatorios como Alarma**:
   - Nombre obligatorio + Nota opcional (visible en pantalla de bloqueo).
   - Activación y desactivación rápida (toggle de 1 toque) y opción de **"Saltar próxima vez"** + indicador `"Suena en Xh Ym"`.
   - **Recurrencia combinada Fecha + Hora**:
     - *Por fecha*: Una vez, días de la semana (Lun-Dom), o cada $N$ días/semanas/meses.
     - *Por hora*: Hora fija única o **recursiva cada $X$ horas/minutos dentro de una ventana activa** (ej. 08:00 a 22:00 o 24h) calculada en grilla fija.
   - **Carpetas colapsables**: Un nivel con color/ícono y **switch maestro con memoria** (al reactivar la carpeta, restaura solo las alarmas que estaban encendidas). Las alarmas sin carpeta se agrupan al final de la lista.
2. **Pantalla de Disparo (Ringing Screen) y Ciclo de No Atendida**:
   - Se muestra sobre pantalla de bloqueo (`fullScreenIntent`) con 2 botones grandes: **Apagar** y **Aplazar** (usa el tiempo preconfigurado de esa alarma).
   - **Ciclo automático global**: Si nadie la apaga, suena durante $X$ min (default 2 min), descansa $Y$ min (default 5 min) y vuelve a sonar hasta $N$ repeticiones configurables en Ajustes. Si se superpone con el siguiente horario programado (de la misma u otra alarma), se reinicia el contador de repeticiones y suena el nuevo turno.
3. **Audio y Volumen**:
   - Canal de **Alarma** (`USAGE_ALARM` / `STREAM_ALARM`), vibración configurable y opción de forzar volumen de alarma específico.
   - Sonido predeterminado, selector de alarmas del sistema Android o archivo de audio local (`.mp3/.ogg/.wav`).
4. **Diseño OLED y Backup**:
   - Tema negro puro (`#000000`) y exportación/importación de backup en JSON local.
5. **Batería y Supervivencia en Segundo Plano (Anti-Killer / Samsung / OEM)**:
   - **Cero polling en segundo plano**: No mantener servicios corriendo 24/7. Usar `AlarmManager.setAlarmClock()` nativo de Android, que registra la alarma a nivel de sistema operativo (muestra ícono de alarma en barra de estado, despierta el CPU de Doze exactamente a la hora y consume 0% de batería mientras espera).
   - **Foreground Service solo al sonar**: Se levanta un `ForegroundService` (`specialUse` / `mediaPlayback`) únicamente cuando la alarma se dispara.
   - **Persistencia ante reinicios**: `BroadcastReceiver` para `BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `TIME_SET` y `TIMEZONE_CHANGED` que reprograma las alarmas activas.
   - **Permisos críticos y exención OEM**:
     - `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM`
     - `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (exención directa de Doze/ahorro de batería)
     - `USE_FULL_SCREEN_INTENT` y `POST_NOTIFICATIONS`
     - `WAKE_LOCK` y `RECEIVE_BOOT_COMPLETED`
     - Guía en app / intents directos para desactivar "Poner apps en suspensión profunda" de Samsung (Device Care / Freecess).

## Arquitectura e Infraestructura (Minimalista / Ponytail)
Sin sobre-ingeniería (sin Clean Architecture de 30 carpetas ni BLoC complejos):
- **Persistencia**: `sqflite` (SQLite nativo en Android) o `shared_preferences` con JSON en una sola tabla/archivo para carpetas y recordatorios.
- **Motor de Alarmas**: Canal nativo Kotlin (`MethodChannel`) directo contra `AlarmManager.setAlarmClock()` + `BroadcastReceiver` + `Ringtone`/`MediaPlayer` en `USAGE_ALARM`, o plugin `alarm` configurado sobre `AlarmClock`. El canal nativo propio en Kotlin (~150 líneas) garantiza control total sobre `setAlarmClock`, WakeLocks y reinicios sin depender de abstracciones de terceros que fallan en Samsung.
- **Estructura del proyecto**:
  ```text
  reminder_app/
  ├── android/          # Manifiesto con permisos, AlarmReceiver y AlarmService nativo
  ├── assets/sounds/    # Sonidos predeterminados
  ├── docs/             # Documentación técnica y decisiones
  └── lib/
      ├── main.dart     # Entrada y tema OLED (#000000)
      ├── models.dart   # Modelos Folder y Reminder (serialización simple)
      ├── storage.dart  # Persistencia local SQLite / JSON
      ├── alarm_api.dart# Puente MethodChannel con AlarmManager nativo
      └── screens/      # Home (carpetas/toggles), Editor, RingScreen (apagar/aplazar)
  ```

## Roadmap de Desarrollo
1. **Fase 1 (Actual)**: Setup de Git, estructura base de directorios y documentación de arquitectura.
2. **Fase 2**: Inicialización del proyecto Flutter + Configuración de `AndroidManifest.xml` (permisos de alarma exacta, batería, boot, full screen).
3. **Fase 3**: Motor nativo Android (`setAlarmClock`, audio en canal `STREAM_ALARM`, pantalla sobre bloqueo y reprogramación en boot).
4. **Fase 4**: Persistencia de carpetas/recordatorios, lógica de recurrencia y aplazamiento (snooze).
5. **Fase 5**: UI OLED negra pura, selector de sonidos y asistente de permisos contra ahorro de batería (Samsung/Xiaomi).
