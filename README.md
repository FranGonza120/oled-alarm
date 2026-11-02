<p align="center">
  <img src="assets/icon/app_icon.jpg" width="140" alt="OLED Alarm Icon" />
</p>

<h1 align="center">OLED Alarm</h1>

<p align="center">
  <strong>Ultra-minimalist, zero-idle-battery Android alarm & recurring reminder app built with Flutter and a native Kotlin <code>AlarmClock</code> engine.</strong>
</p>

---

## Overview

**OLED Alarm** is an Android reminder application designed to behave like a true hardware-level system alarm rather than a standard notification reminder. It features a pure `#000000` AMOLED dark theme with grey accents, collapsible folders with state memory, combined date + hourly fixed-grid recurrence, and aggressive protection against Android Doze and OEM background killers (such as Samsung One UI Deep Sleep).

---

## Key Features

- **True Alarm Behavior (`STREAM_ALARM`)**
  - Plays over the native Android **Alarm audio stream** (`USAGE_ALARM`), bypassing silent/vibrate modes.
  - Choose between the default system alarm, any Android system alarm tone, or a custom local audio file (`.mp3`, `.ogg`, `.wav`).
  - Optional per-alarm **forced alarm volume percentage** (automatically restores your previous system alarm volume after dismissal).
- **Combined Date & Fixed-Grid Hourly Recurrence**
  - **Date Rules**:
    - *Once*: Specific date (`YYYY-MM-DD`).
    - *Weekdays*: Any combination of Monday through Sunday.
    - *Every N*: Every $N$ days, weeks, or months from a start date.
  - **Time Rules**:
    - *Fixed Time*: Rings once at `HH:mm` on matching days.
    - *Hourly Recurring*: Rings every custom `HH:mm` interval (picked via a 24h time picker) within a configurable active window (e.g., `08:00` to `22:00` or `24h`). Calculated on a strict fixed grid from the start time so snoozing never shifts future slots.
- **Collapsible Folders with Memory**
  - Organize alarms into custom-colored/icon folders or leave them ungrouped at the bottom of the list.
  - **Master Folder Toggle with Memory**: Disabling a folder pauses all alarms inside it while remembering which individual alarms were enabled; re-enabling the folder restores only those previously active alarms.
- **Upcoming Alarm Notification & One-Tap Skip**
  - Persistent status bar notification showing the next scheduled alarm with a **"Skip next alarm"** action button to skip the next occurrence without opening the app or disabling the recurrence.
- **Lockscreen Wake (No Keyguard Prompt)**
  - Wakes the screen over the lockscreen (`setShowWhenLocked` / `setTurnScreenOn`) displaying 24h time, date, title, and note without forcing a PIN/pattern unlock screen.
  - Dismiss by **tapping or swiping** the `✕` button, or snooze with a single tap—immediately returning to the lockscreen when locked.
- **Global Unanswered Alarm Cycle**
  - Configurable global cycle: rings for $X$ minutes (default `2m`), pauses for $Y$ minutes (default `5m`), and repeats up to $N$ times (default `3`).
  - Smart collision handling: if an auto-retry overlaps with the next scheduled grid slot (from the same or another alarm), the retry counter resets and the new schedule fires on time.
- **0% Idle Battery & Reboot Survival (Direct Boot)**
  - Zero background polling services. Uses Android's `AlarmManager.setAlarmClock()` so the OS kernel wakes the device at the exact millisecond.
  - Stores state in **Device Protected Storage** (`createDeviceProtectedStorageContext`) and listens to `LOCKED_BOOT_COMPLETED`, `BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `TIME_SET`, and `TIMEZONE_CHANGED`—rescheduling alarms immediately after a reboot even before the phone is unlocked.
- **Real-Time Permission & Auto-Revoke Shield**
  - Monitors critical permissions (`Ignore Battery Optimizations`, `Exact Alarms`, `Notifications`, `Full Screen Intent`, and Android's `"Manage app if unused"` auto-revoke setting).
  - Alerts you immediately with a notification and red indicator dots on the Settings gear and Shield icon if the OS reverts any protection.
- **Local JSON Backup**
  - One-tap export/copy and import/restore of all folders, alarms, and global settings as plain JSON.

---

## Project Structure

Built with zero third-party runtime dependencies (`ponytail ultra` standard):

```text
oled-alarm/
├── android/app/src/main/
│   ├── AndroidManifest.xml                                    # DirectBoot, ExactAlarm, FullScreen permissions
│   └── kotlin/com/oled/reminder/reminder_app/
│       ├── AlarmEngine.kt                                     # Native setAlarmClock scheduler, Audio/ForegroundService, BootReceiver
│       └── MainActivity.kt                                    # MethodChannel bridge, lockscreen wake, system pickers
├── assets/icon/app_icon.jpg                                   # App icon source
├── docs/
│   ├── ARCHITECTURE.md                                        # Initial architecture & roadmap notes
│   └── SPEC.md                                                # Full functional specification & coding standards
├── lib/
│   ├── main.dart                                              # Pure #000000 OLED UI (Home, Editor, RingingScreen, Settings)
│   ├── models.dart                                            # Folder, Reminder, AppSettings & fixed-grid recurrence engine
│   ├── storage.dart                                           # Atomic JSON persistence shared with native Kotlin
│   └── alarm_api.dart                                         # Flutter MethodChannel wrapper
└── test/
    └── widget_test.dart                                       # Unit & widget test suite
```

---

## Build & Install

### Prerequisites
- Flutter SDK (`^3.13.5`)
- Android SDK (API 36 / Java 17)

### Run Tests
```bash
flutter analyze
flutter test
cd android && ./gradlew testDebugUnitTest
```

### Build & Install Release APK via USB
```bash
flutter build apk --release
flutter install --release
```
The compiled release APK is generated at `build/app/outputs/flutter-apk/app-release.apk`.

---

## Documentation
- [Functional Specification & Standards (`docs/SPEC.md`)](docs/SPEC.md)
- [Architecture & Roadmap History (`docs/ARCHITECTURE.md`)](docs/ARCHITECTURE.md)
