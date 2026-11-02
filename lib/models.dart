import 'dart:convert';

enum DateRuleType { once, weekdays, everyN }

enum IntervalUnit { days, weeks, months }

enum TimeRuleType { fixed, hourly }

class Folder {
  String id;
  String name;
  int color;
  int icon;
  bool isEnabled;
  bool isExpanded;

  Folder({
    required this.id,
    required this.name,
    this.color = 0xFF9E9E9E,
    this.icon = 0xe2c7, // Icons.folder
    this.isEnabled = true,
    this.isExpanded = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'icon': icon,
    'isEnabled': isEnabled,
    'isExpanded': isExpanded,
  };

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
    id: j['id'] as String,
    name: j['name'] as String,
    color: (j['color'] as int?) ?? 0xFF9E9E9E,
    icon: (j['icon'] as int?) ?? 0xe2c7,
    isEnabled: (j['isEnabled'] as bool?) ?? true,
    isExpanded: (j['isExpanded'] as bool?) ?? true,
  );
}

class Reminder {
  String id;
  String? folderId;
  String name;
  String note;
  bool isEnabled;
  int? skipUntilMs; // If set, skip any grid occurrence <= skipUntilMs
  int snoozeMinutes;
  int? snoozedUntilMs; // Manual or auto snooze target

  // Date rule
  DateRuleType dateRule;
  String anchorDate; // YYYY-MM-DD (used for 'once' target or 'everyN' anchor)
  List<int> weekdays; // 1=Mon .. 7=Sun
  int everyN;
  IntervalUnit everyUnit;

  // Time rule
  TimeRuleType timeRule;
  int startMinute; // Minutes from midnight (0..1439), also fixed time
  int endMinute; // End of window (0..1439)
  int intervalMinutes; // Step for hourly recurrence (e.g. 60, 120)

  // Audio & vibration
  String soundUri; // '' = default system alarm
  String soundName;
  bool vibrate;
  int? customVolume; // null = system volume, 1..100 = forced percentage

  Reminder({
    required this.id,
    this.folderId,
    required this.name,
    this.note = '',
    this.isEnabled = true,
    this.skipUntilMs,
    this.snoozeMinutes = 10,
    this.snoozedUntilMs,
    this.dateRule = DateRuleType.weekdays,
    required this.anchorDate,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.everyN = 1,
    this.everyUnit = IntervalUnit.days,
    this.timeRule = TimeRuleType.fixed,
    this.startMinute = 480, // 08:00
    this.endMinute = 1320, // 22:00
    this.intervalMinutes = 120,
    this.soundUri = '',
    this.soundName = 'Predeterminado',
    this.vibrate = true,
    this.customVolume,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'folderId': folderId,
    'name': name,
    'note': note,
    'isEnabled': isEnabled,
    'skipUntilMs': skipUntilMs,
    'snoozeMinutes': snoozeMinutes,
    'snoozedUntilMs': snoozedUntilMs,
    'dateRule': dateRule.name,
    'anchorDate': anchorDate,
    'weekdays': weekdays,
    'everyN': everyN,
    'everyUnit': everyUnit.name,
    'timeRule': timeRule.name,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'intervalMinutes': intervalMinutes,
    'soundUri': soundUri,
    'soundName': soundName,
    'vibrate': vibrate,
    'customVolume': customVolume,
  };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
    id: j['id'] as String,
    folderId: j['folderId'] as String?,
    name: j['name'] as String,
    note: (j['note'] as String?) ?? '',
    isEnabled: (j['isEnabled'] as bool?) ?? true,
    skipUntilMs: j['skipUntilMs'] as int?,
    snoozeMinutes: (j['snoozeMinutes'] as int?) ?? 10,
    snoozedUntilMs: j['snoozedUntilMs'] as int?,
    dateRule: DateRuleType.values.firstWhere(
      (e) => e.name == j['dateRule'],
      orElse: () => DateRuleType.weekdays,
    ),
    anchorDate: (j['anchorDate'] as String?) ?? fmtDate(DateTime.now()),
    weekdays:
        (j['weekdays'] as List?)?.map((e) => e as int).toList() ??
        [1, 2, 3, 4, 5, 6, 7],
    everyN: (j['everyN'] as int?) ?? 1,
    everyUnit: IntervalUnit.values.firstWhere(
      (e) => e.name == j['everyUnit'],
      orElse: () => IntervalUnit.days,
    ),
    timeRule: TimeRuleType.values.firstWhere(
      (e) => e.name == j['timeRule'],
      orElse: () => TimeRuleType.fixed,
    ),
    startMinute: (j['startMinute'] as int?) ?? 480,
    endMinute: (j['endMinute'] as int?) ?? 1320,
    intervalMinutes: (j['intervalMinutes'] as int?) ?? 120,
    soundUri: (j['soundUri'] as String?) ?? '',
    soundName: (j['soundName'] as String?) ?? 'Predeterminado',
    vibrate: (j['vibrate'] as bool?) ?? true,
    customVolume: j['customVolume'] as int?,
  );

  bool matchesDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final parts = anchorDate.split('-').map(int.parse).toList();
    final anchor = DateTime(parts[0], parts[1], parts[2]);

    switch (dateRule) {
      case DateRuleType.once:
        return d.year == anchor.year &&
            d.month == anchor.month &&
            d.day == anchor.day;
      case DateRuleType.weekdays:
        return weekdays.contains(d.weekday);
      case DateRuleType.everyN:
        if (d.isBefore(anchor)) return false;
        final n = everyN < 1 ? 1 : everyN;
        switch (everyUnit) {
          case IntervalUnit.days:
            final diffDays =
                (d.millisecondsSinceEpoch - anchor.millisecondsSinceEpoch) ~/
                86400000;
            return diffDays % n == 0;
          case IntervalUnit.weeks:
            if (d.weekday != anchor.weekday) return false;
            final diffDays =
                (d.millisecondsSinceEpoch - anchor.millisecondsSinceEpoch) ~/
                86400000;
            return (diffDays ~/ 7) % n == 0;
          case IntervalUnit.months:
            if (d.day != anchor.day) return false;
            final diffMonths =
                (d.year - anchor.year) * 12 + (d.month - anchor.month);
            return diffMonths >= 0 && diffMonths % n == 0;
        }
    }
  }

  List<int> daySlots() {
    if (timeRule == TimeRuleType.fixed) return [startMinute];
    final step = intervalMinutes < 1 ? 1 : intervalMinutes;
    final end = endMinute < startMinute ? startMinute : endMinute;
    final out = <int>[];
    for (int m = startMinute; m <= end; m += step) {
      out.add(m);
    }
    return out;
  }

  /// Next scheduled grid occurrence strictly after [after], ignoring skipUntilMs if [ignoreSkip] is true.
  DateTime? nextGridTrigger(DateTime after, {bool ignoreSkip = false}) {
    final slots = daySlots();
    if (slots.isEmpty) return null;
    final baseDay = DateTime(after.year, after.month, after.day);
    // ponytail: 400-day horizon covers >1 year of monthly/everyN intervals; extend if multi-year everyN needed
    for (int offset = 0; offset <= 400; offset++) {
      final day = baseDay.add(Duration(days: offset));
      if (!matchesDay(day)) continue;
      for (final m in slots) {
        final candidate = DateTime(
          day.year,
          day.month,
          day.day,
          m ~/ 60,
          m % 60,
        );
        if (!candidate.isAfter(after)) continue;
        if (!ignoreSkip &&
            skipUntilMs != null &&
            candidate.millisecondsSinceEpoch <= skipUntilMs!) {
          continue;
        }
        return candidate;
      }
    }
    return null;
  }

  /// Effective next trigger considering folder state, active snooze, and skipNext.
  DateTime? nextEffectiveTrigger(
    DateTime now,
    Map<String, Folder> folderMap, {
    bool ignoreSkip = false,
  }) {
    if (!isEnabled) return null;
    if (folderId != null) {
      final f = folderMap[folderId];
      if (f != null && !f.isEnabled) return null;
    }
    final grid = nextGridTrigger(now, ignoreSkip: ignoreSkip);
    if (snoozedUntilMs != null && snoozedUntilMs! > now.millisecondsSinceEpoch) {
      final snoozeDt = DateTime.fromMillisecondsSinceEpoch(snoozedUntilMs!);
      if (grid == null || snoozeDt.isBefore(grid)) return snoozeDt;
    }
    return grid;
  }

  String scheduleSummary() {
    String datePart;
    switch (dateRule) {
      case DateRuleType.once:
        datePart = anchorDate;
      case DateRuleType.weekdays:
        if (weekdays.length == 7) {
          datePart = 'Todos los días';
        } else if (weekdays.length == 5 &&
            !weekdays.contains(6) &&
            !weekdays.contains(7)) {
          datePart = 'Lun a Vie';
        } else {
          const names = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
          final sorted = [...weekdays]..sort();
          datePart = sorted.map((d) => names[d]).join(', ');
        }
      case DateRuleType.everyN:
        final unitLabel = switch (everyUnit) {
          IntervalUnit.days => 'días',
          IntervalUnit.weeks => 'sem',
          IntervalUnit.months => 'meses',
        };
        datePart = 'Cada $everyN $unitLabel';
    }

    if (timeRule == TimeRuleType.fixed) {
      return '$datePart · ${fmtMin(startMinute)}';
    }
    final h = intervalMinutes ~/ 60;
    final m = intervalMinutes % 60;
    final stepStr =
        h > 0 && m > 0 ? '${h}h ${m}m' : (h > 0 ? '${h}h' : '${m}m');
    return '$datePart · Cada $stepStr (${fmtMin(startMinute)}-${fmtMin(endMinute)})';
  }
}

class AppSettings {
  int ringDurationMinutes;
  int autoSnoozeMinutes;
  int maxAutoRetries;

  AppSettings({
    this.ringDurationMinutes = 2,
    this.autoSnoozeMinutes = 5,
    this.maxAutoRetries = 3,
  });

  Map<String, dynamic> toJson() => {
    'ringDurationMinutes': ringDurationMinutes,
    'autoSnoozeMinutes': autoSnoozeMinutes,
    'maxAutoRetries': maxAutoRetries,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    ringDurationMinutes: (j['ringDurationMinutes'] as int?) ?? 2,
    autoSnoozeMinutes: (j['autoSnoozeMinutes'] as int?) ?? 5,
    maxAutoRetries: (j['maxAutoRetries'] as int?) ?? 3,
  );
}

class AppState {
  List<Folder> folders;
  List<Reminder> reminders;
  AppSettings settings;

  AppState({
    List<Folder>? folders,
    List<Reminder>? reminders,
    AppSettings? settings,
  }) : folders = folders ?? [],
       reminders = reminders ?? [],
       settings = settings ?? AppSettings();

  Map<String, dynamic> toJson() => {
    'folders': folders.map((f) => f.toJson()).toList(),
    'reminders': reminders.map((r) => r.toJson()).toList(),
    'settings': settings.toJson(),
  };

  factory AppState.fromJson(Map<String, dynamic> j) => AppState(
    folders:
        (j['folders'] as List?)
            ?.map((e) => Folder.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [],
    reminders:
        (j['reminders'] as List?)
            ?.map((e) => Reminder.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [],
    settings:
        j['settings'] != null
            ? AppSettings.fromJson(
              Map<String, dynamic>.from(j['settings'] as Map),
            )
            : AppSettings(),
  );

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String fmtMin(int min) =>
    '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

String fmtCountdown(DateTime target, DateTime now) {
  final diff = target.difference(now);
  if (diff.isNegative) return 'Ahora';
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final mins = (diff.inMinutes % 60) + (diff.inSeconds % 60 > 0 ? 1 : 0);
  final adjHours = hours + (mins == 60 ? 1 : 0);
  final adjMins = mins % 60;
  if (days > 0) return 'Suena en ${days}d ${adjHours}h';
  if (adjHours > 0) return 'Suena en ${adjHours}h ${adjMins}m';
  return 'Suena en ${adjMins < 1 ? 1 : adjMins}m';
}
