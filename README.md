# OLED Alarm Reminder App (Android / Flutter)

Aplicación Android en Flutter para recordatorios tipo alarma de alta confiabilidad, bajo consumo de batería y tema OLED (`#000000`).

## Requerimientos Funcionales
1. **Recordatorios como Alarma**:
   - Nombre personalizado por recordatorio.
   - Activación y desactivación rápida (toggle de 1 toque).
   - Fechas y horarios recurrentes (días de semana, intervalos, fecha específica).
   - Organización por carpetas / categorías.
2. **Pantalla de Disparo (Ringing Screen)**:
   - Se muestra sobre pantalla de bloqueo y enciende la pantalla (`fullScreenIntent`).
   - Opciones para **Apagar** (Dismiss) o **Aplazar** (Snooze) por un tiempo configurable.
3. **Audio y Volumen**:
   - Usa canal de audio de **Alarma** (`USAGE_ALARM` / `STREAM_ALARM`), ignorando modo silencio/no molestar si el sistema lo permite para alarmas.
   - Sonido predeterminado o personalizado por alarma (archivo local o tono del sistema).
4. **Diseño OLED**:
   - Tema negro puro (`#000000`) para ahorro en pantallas AMOLED y mínima fatiga visual.
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
