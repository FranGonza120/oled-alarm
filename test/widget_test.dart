import 'package:flutter_test/flutter_test.dart';
import 'package:reminder_app/models.dart';

void main() {
  test('fixed grid hourly recurrence and skipNext', () {
    final r = Reminder(
      id: '1',
      name: 'Agua',
      dateRule: DateRuleType.weekdays,
      anchorDate: '2026-11-01',
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      timeRule: TimeRuleType.hourly,
      startMinute: 480, // 08:00
      endMinute: 840, // 14:00
      intervalMinutes: 120, // 2h -> 08:00, 10:00, 12:00, 14:00
    );

    final after09 = DateTime(2026, 11, 2, 9, 15);
    final t1 = r.nextEffectiveTrigger(after09, {});
    expect(t1, DateTime(2026, 11, 2, 10, 0));

    // Skip 10:00 -> next should be 12:00 on fixed grid
    r.skipUntilMs = t1!.millisecondsSinceEpoch;
    final t2 = r.nextEffectiveTrigger(after09, {});
    expect(t2, DateTime(2026, 11, 2, 12, 0));

    // Folder disabled preserves individual r.isEnabled but pauses effective trigger
    final f = Folder(id: 'f1', name: 'Salud', isEnabled: false);
    r.folderId = 'f1';
    expect(r.nextEffectiveTrigger(after09, {'f1': f}), isNull);
    f.isEnabled = true;
    expect(r.nextEffectiveTrigger(after09, {'f1': f}), DateTime(2026, 11, 2, 12, 0));
  });
}
