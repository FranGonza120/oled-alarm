# Arquitectura Inicial y Roadmap (Archivo Histórico)

Documento inicial de arquitectura e infraestructura que originalmente estaba en `README.md` durante la Fase 1. Ver también [`docs/SPEC.md`](SPEC.md) para la especificación funcional detallada.

---

## Requerimientos Funcionales Iniciales
1. **Recordatorios como Alarma**:
   - Nombre obligatorio + Nota opcional (visible en pantalla de bloqueo).
   - Activación y desactivación rápida (toggle de 1 toque), indicador de cuenta regresiva y botón para saltar la próxima ocurrencia tanto en la tarjeta de la app como en una **notificación con la próxima alarma a sonar**.
   - **Recurrencia combinada Fecha + Hora**:
     - *Por fecha*: Una vez, días de la semana (Lun-Dom), o cada $N$ días/semanas/meses.
     - *Por hora*: Hora fija única o **recursiva cada $X$ horas/minutos dentro de una ventana activa** (ej. 08:00 a 22:00 o 24h) calculada en grilla fija.
   - **Carpetas colapsables**: Un nivel con color/ícono y **switch maestro con memoria** (al reactivar la carpeta, restaura solo las alarmas que estaban encendidas). Las alarmas sin carpeta se agrupan al final de la lista.
2. **Pantalla de Disparo (Ringing Screen) y Ciclo de No Atendida**:
   - Se muestra sobre pantalla de bloqueo (`fullScreenIntent`) sin solicitar desbloqueo de PIN/patrón.
   - **Ciclo automático global**: Si nadie la apaga, suena durante $X$ min (default 2 min), descansa $Y$ min (default 5 min) y vuelve a sonar hasta $N$ repeticiones configurables en Ajustes. Si se superpone con el siguiente horario programado (de la misma u otra alarma), se reinicia el contador de repeticiones y suena el nuevo turno.
3. **Audio y Volumen**:
   - Canal de **Alarma** (`USAGE_ALARM` / `STREAM_ALARM`), vibración configurable y opción de forzar volumen de alarma específico.
   - Sonido predeterminado, selector de alarmas del sistema Android o archivo de audio local (`.mp3/.ogg/.wav`).
4. **Diseño OLED y Backup**:
   - Tema negro puro (`#000000`) con acento gris minimalista y exportación/importación de backup en JSON local.
5. **Batería y Supervivencia en Segundo Plano (Anti-Killer / Samsung / OEM)**:
   - **Cero polling en segundo plano**: Uso de `AlarmManager.setAlarmClock()` nativo de Android, que registra la alarma a nivel de sistema operativo (despierta el CPU de Doze exactamente a la hora y consume 0% de batería mientras espera).
   - **Foreground Service solo al sonar**: Se levanta un `ForegroundService` (`mediaPlayback`) únicamente cuando la alarma se dispara.
   - **Persistencia ante reinicios (Direct Boot)**: `BroadcastReceiver` (`directBootAware="true"`) para `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `TIME_SET` y `TIMEZONE_CHANGED` leyendo `state.json` desde almacenamiento protegido por dispositivo (`createDeviceProtectedStorageContext()`).
   - **Monitoreo de permisos en tiempo real**: Vigilancia de `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `POST_NOTIFICATIONS` y `isAutoRevokeWhitelisted` (*Manage app if unused*), con alertas sonoras e indicadores visuales si el sistema revierte algún permiso.

## Roadmap Completado
1. **Fase 1**: Setup de Git, estructura base de directorios y documentación de arquitectura.
2. **Fase 2**: Inicialización del proyecto Flutter + Configuración de `AndroidManifest.xml`.
3. **Fase 3**: Motor nativo Android (`setAlarmClock`, audio en canal `STREAM_ALARM`, pantalla sobre bloqueo y reprogramación en boot).
4. **Fase 4**: Persistencia de carpetas/recordatorios, lógica de recurrencia combinada y aplazamiento (snooze).
5. **Fase 5**: UI OLED negra pura en inglés, selector de sonidos, monitoreo de permisos y suite de pruebas unitarias/widgets.
