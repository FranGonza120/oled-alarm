# Especificación Completa (Scope): OLED Alarm Reminder App

Documento de alcance y decisiones de diseño cerradas para la aplicación Android en Flutter.

---

## 1. Modelo de Datos y Organización (Carpetas + Recordatorios)

### 1.1 Carpetas (1 solo nivel)
- **Campos**: `id`, `name`, `color`, `icon`, `isEnabled` (switch maestro), `isExpanded` (estado colapsable en UI).
- **Comportamiento del Switch Maestro de Carpeta**:
  - Al apagar una carpeta (`isEnabled = false`), todas las alarmas dentro de ella dejan de sonar/programarse, pero **cada alarma conserva su estado individual (`wasEnabled` / `isEnabled`)**.
  - Al volver a encender la carpeta (`isEnabled = true`), se restauran y reprograman **únicamente** las alarmas que estaban activas antes de apagar la carpeta.
- **Alarmas sin carpeta**: Se muestran en la pantalla principal al final de la lista, debajo de todas las carpetas colapsables.

### 1.2 Recordatorio / Alarma
- **Campos principales**:
  - `id`, `folderId` (nullable = sin carpeta).
  - `name` (obligatorio) y `note` (descripción opcional que se muestra en grande al sonar).
  - `isEnabled` (switch individual de 1 toque).
  - `skipNext` (booleano/timestamp para **"Saltar próxima ocurrencia"** sin desactivar la recurrencia).
  - `snoozeMinutes` (tiempo de aplazamiento manual preconfigurado por alarma, ej. 10 min).

---

## 2. Motor de Recurrencia Combinado (Fecha + Hora)

Cada alarma define **Qué días se activa** (Regla de Fecha) y **A qué horas suena en esos días** (Regla de Hora):

### 2.1 Regla de Fecha (Cuándo aplica)
1. **Una sola vez**: Fecha específica (`YYYY-MM-DD`). Si no tiene más disparos pendientes en el día, pasa a `isEnabled = false` al terminar.
2. **Días de la semana**: Selección de días (`Lun, Mar, Mié, Jue, Vie, Sáb, Dom`).
3. **Intervalo periódico (`Cada N`)**:
   - Cada $N$ días (desde una fecha base).
   - Cada $N$ semanas.
   - Cada $N$ meses (mismo día del mes).

### 2.2 Regla de Hora (Cómo suena dentro de un día válido)
1. **Hora fija única**: Suena una sola vez en el día válido a las `HH:mm`.
2. **Recursiva por intervalo de horas/minutos (con ventana activa)**:
   - **Intervalo**: Cada $X$ horas / minutos (ej. cada 30 min, cada 2 horas).
   - **Ventana activa**: Hora de inicio (`startTime`, ej. `08:00`) a hora de fin (`endTime`, ej. `22:00`), con opción de **24 horas** (`00:00` a `23:59`).
   - **Cálculo en grilla fija**: Los horarios se calculan de forma fija desde `startTime` (`startTime + k * interval` mientras `<= endTime`). Ejemplo: `08:00` cada `2h` dispara siempre a las `08:00, 10:00, 12:00...` independientemente de si una ocurrencia previa se aplazó o se apagó tarde.

---

## 3. Pantalla de Disparo (Ringing), Aplazamiento y Ciclo de No Atendida

### 3.1 Pantalla al Sonar (Sobre Pantalla de Bloqueo)
- Fondo OLED `#000000`, alto contraste.
- Muestra: Hora actual, **Nombre de la alarma**, **Nota opcional** en grande.
- **2 Botones grandes**:
  1. **Apagar (Dismiss)**: Detiene el sonido, limpia reintentos y agenda el próximo turno oficial de la grilla/fecha.
  2. **Aplazar (`+X min`)**: Un único botón grande que aplaza directamente por el tiempo `snoozeMinutes` preconfigurado en esa alarma.

### 3.2 Ciclo Global para Alarmas No Atendidas (Ajustes Generales)
Configuración **global** para toda la aplicación (valores por defecto editables en Ajustes):
- **Duración de sonido (`ringDurationMinutes`)**: Por defecto **2 minutos**.
- **Pausa entre reintentos (`autoSnoozeMinutes`)**: Por defecto **5 minutos** después de que dejó de sonar.
- **Cantidad máxima de repeticiones (`maxAutoRetries`)**: $N$ veces configurables por el usuario.
- **Regla de colisión / superposición**:
  - Si mientras está en ciclo de reintento (o sonando) llega el horario programado del **siguiente turno** (de la misma alarma recursiva o de otra alarma), **se reinicia el contador de repeticiones a 0** y se dispara inmediatamente la alarma del nuevo horario correspondiente.
  - Si se agotan las $N$ repeticiones sin respuesta, se registra notificación de "Alarma perdida" y queda agendado el siguiente turno normal.

---

## 4. Audio y Vibración

Configuración por alarma (con valores por defecto heredados de Ajustes):
- **Canal de audio**: Siempre `USAGE_ALARM` / `STREAM_ALARM` nativo de Android (suena aunque el teléfono esté en modo silencio/vibración).
- **Origen del sonido**:
  1. Tono de alarma predeterminado del sistema.
  2. Selector nativo de tonos/alarmas de Android (`RingtoneManager.TYPE_ALARM`).
  3. Archivo de audio local (`.mp3`, `.ogg`, `.wav`).
- **Volumen**:
  - Opción de respetar el volumen de alarma actual del sistema, **o** forzar un porcentaje de volumen de alarma específico al sonar (restaurando el volumen previo al terminar).
- **Vibración**: Toggle activar/desactivar vibración en patrón de alarma.

---

## 5. Interfaz OLED y Funcionalidades Extra

- **Tema OLED puro**: Fondo `#000000`, tarjetas con bordes sutiles (`#1A1A1A` / `#262626`), sin grises lavados para apagar píxeles en pantallas AMOLED.
- **Pantalla Principal (Home)**:
  - Lista de **Carpetas colapsables** (con su color/ícono, contador de alarmas activas y switch maestro).
  - Al final de las carpetas, sección con las **Alarmas sin carpeta**.
  - Cada tarjeta de alarma muestra: Nombre, resumen de recurrencia/ventana, **tiempo restante ("Suena en Xh Ym")**, switch individual y acción rápida **"Saltar próxima"** (cuando está activa).
- **Backup local**: Exportar e importar toda la base de datos (carpetas, alarmas y ajustes globales) en un archivo `.json` local.

---

## 6. Supervivencia en Segundo Plano y Batería (Anti-Killer / Samsung)

1. **Cero consumo en reposo (`AlarmManager.setAlarmClock`)**:
   - No hay servicios corriendo permanentemente en segundo plano.
   - Se agenda cada disparo exacto con `AlarmManager.setAlarmClock()`, que Android trata como alarma de reloj crítica (despierta el dispositivo de Doze profundo y nunca es diferida por ahorradores de batería estándar).
2. **Foreground Service efímero**:
   - Solo vive durante los ~2 minutos que la alarma está sonando activamente con `WakeLock` parcial y `fullScreenIntent`.
3. **Reprogramación automática**:
   - `BroadcastReceiver` nativo escuchando `BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `MY_PACKAGE_REPLACED`, `TIME_SET` y `TIMEZONE_CHANGED`.
4. **Panel de Blindaje de Batería (Onboarding / Ajustes)**:
   - Verificación y solicitud directa de:
     - `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (excluir de Doze).
     - `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`.
     - `USE_FULL_SCREEN_INTENT` (Android 14+) y `POST_NOTIFICATIONS` (Android 13+).
   - Acceso rápido e instrucciones específicas para Samsung (One UI: sacar de *"Aplicaciones en suspensión profunda"* y poner batería en *"No restringido"*).
