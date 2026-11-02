import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'alarm_api.dart';
import 'models.dart';
import 'storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
    ),
  );
  runApp(const OledAlarmApp());
}

class OledAlarmApp extends StatelessWidget {
  const OledAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OLED Alarm',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        cardColor: const Color(0xFF0A0A0A),
        dividerColor: const Color(0xFF222222),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00B0FF),
          surface: Colors.black,
          error: Color(0xFFFF5252),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF0D0D0D),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Color(0xFF262626)),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  AppState _state = AppState();
  Map<String, dynamic>? _ringing;
  Map<String, bool> _perms = {};
  Timer? _ticker;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AlarmApi.setEventHandler((_) => _refreshAll());
    _refreshAll();
    // Refresh countdown strings once every 20s only while UI is open
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    }
  }

  Future<void> _refreshAll() async {
    final loaded = await Storage.load();
    final ringing = await AlarmApi.getRingingAlarm();
    final perms = await AlarmApi.getPermissionStatus();
    if (!mounted) return;
    setState(() {
      _state = loaded;
      _ringing = ringing;
      _perms = perms;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() {});
    await Storage.saveAndSync(_state);
    final ringing = await AlarmApi.getRingingAlarm();
    if (mounted) setState(() => _ringing = ringing);
  }

  void _skipNextOccurrence(Reminder r, Map<String, Folder> folderMap) {
    final now = DateTime.now();
    final next = r.nextEffectiveTrigger(now, folderMap);
    if (next == null) return;
    r.snoozedUntilMs = null;
    r.skipUntilMs = next.millisecondsSinceEpoch;
    _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_ringing != null) {
      return RingingScreen(
        alarm: _ringing!,
        onDismiss: () async {
          await AlarmApi.dismissRinging();
          await _refreshAll();
        },
        onSnooze: () async {
          await AlarmApi.snoozeRinging();
          await _refreshAll();
        },
      );
    }

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final now = DateTime.now();
    final folderMap = {for (final f in _state.folders) f.id: f};
    final ungrouped =
        _state.reminders
            .where((r) => r.folderId == null || !folderMap.containsKey(r.folderId))
            .toList();

    final missingPerms =
        _perms.entries.where((e) => e.value == false).map((e) => e.key).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'OLED Alarm',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Nueva carpeta',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _openFolderDialog(),
          ),
          IconButton(
            tooltip: 'Blindaje Batería / Samsung',
            icon: Icon(
              Icons.shield_outlined,
              color:
                  missingPerms.isEmpty
                      ? const Color(0xFF00E676)
                      : Colors.amberAccent,
            ),
            onPressed: () => _openBatteryShieldSheet(),
          ),
          IconButton(
            tooltip: 'Ajustes y Backup',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettingsSheet(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          if (missingPerms.isNotEmpty)
            _buildPermissionBanner(missingPerms.length),
          if (_state.folders.isEmpty && _state.reminders.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(
                child: Text(
                  'Sin alarmas.\nTocá + para crear un recordatorio o carpeta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 15),
                ),
              ),
            ),
          for (final folder in _state.folders)
            _buildFolderSection(folder, folderMap, now),
          if (ungrouped.isNotEmpty) ...[
            if (_state.folders.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(6, 16, 6, 6),
                child: Text(
                  'SIN CARPETA',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            for (final rem in ungrouped)
              _buildReminderCard(rem, folderMap, now),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00E676),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_alarm),
        label: const Text(
          'Nueva Alarma',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () => _openReminderEditor(),
      ),
    );
  }

  Widget _buildPermissionBanner(int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141000),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent),
        title: Text(
          'Faltan $count permisos críticos anti-batería',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: const Text(
          'Tocá acá para evitar que Android / Samsung cierre tus alarmas.',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        onTap: _openBatteryShieldSheet,
      ),
    );
  }

  static const _folderIcons = <int, IconData>{
    0xe2c7: Icons.folder,
    0xe943: Icons.work_outline,
    0xf0565: Icons.medication_outlined,
    0xe28d: Icons.fitness_center,
    0xe319: Icons.home_outlined,
    0xe5fd: Icons.star_outline,
  };

  static IconData _iconFor(int code) => _folderIcons[code] ?? Icons.folder;

  Widget _buildFolderSection(
    Folder folder,
    Map<String, Folder> folderMap,
    DateTime now,
  ) {
    final items =
        _state.reminders.where((r) => r.folderId == folder.id).toList();
    final activeCount = items.where((r) => r.isEnabled).length;
    final folderColor = Color(folder.color);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              folder.isEnabled
                  ? folderColor.withValues(alpha: 0.45)
                  : const Color(0xFF222222),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              folder.isExpanded = !folder.isExpanded;
              _save();
            },
            onLongPress: () => _openFolderDialog(existing: folder),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _iconFor(folder.icon),
                    color: folder.isEnabled ? folderColor : Colors.white38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                folder.isEnabled ? Colors.white : Colors.white54,
                          ),
                        ),
                        Text(
                          '$activeCount/${items.length} activas · mantené presionado para editar',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: folder.isEnabled,
                    activeThumbColor: folderColor,
                    onChanged: (v) {
                      // Master folder switch preserves individual r.isEnabled memory
                      folder.isEnabled = v;
                      _save();
                    },
                  ),
                  Icon(
                    folder.isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          if (folder.isExpanded)
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Carpeta vacía',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  children: [
                    for (final r in items)
                      _buildReminderCard(r, folderMap, now),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(
    Reminder r,
    Map<String, Folder> folderMap,
    DateTime now,
  ) {
    final folder = r.folderId != null ? folderMap[r.folderId] : null;
    final folderPaused = folder != null && !folder.isEnabled;
    final nextDt = r.nextEffectiveTrigger(now, folderMap);
    final isActive = r.isEnabled && !folderPaused && nextDt != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF070707),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isActive ? const Color(0xFF282828) : const Color(0xFF161616),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openReminderEditor(existing: r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color:
                                isActive ? Colors.white : Colors.white54,
                          ),
                        ),
                        if (r.note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              r.note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Switch(
                    value: r.isEnabled,
                    activeThumbColor: const Color(0xFF00E676),
                    onChanged: (v) {
                      r.isEnabled = v;
                      if (!v) {
                        r.snoozedUntilMs = null;
                        r.skipUntilMs = null;
                      } else if (r.dateRule == DateRuleType.once) {
                        final target = r.nextGridTrigger(now, ignoreSkip: true);
                        if (target == null) {
                          r.anchorDate = fmtDate(now);
                        }
                      }
                      _save();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                r.scheduleSummary(),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color:
                        isActive
                            ? const Color(0xFF00E676)
                            : Colors.white38,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      folderPaused && r.isEnabled
                          ? 'Carpeta desactivada (en memoria)'
                          : (nextDt != null
                              ? '${fmtCountdown(nextDt, now)} (${fmtDate(nextDt)} ${fmtMin(nextDt.hour * 60 + nextDt.minute)})'
                              : 'Desactivada'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            isActive
                                ? const Color(0xFF00E676)
                                : Colors.white38,
                      ),
                    ),
                  ),
                  if (isActive)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.amberAccent,
                      ),
                      icon: const Icon(Icons.skip_next, size: 16),
                      label: const Text(
                        'Saltar proxima alarma',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () => _skipNextOccurrence(r, folderMap),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFolderDialog({Folder? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    int selectedColor = existing?.color ?? 0xFF00E676;
    int selectedIcon = existing?.icon ?? Icons.folder.codePoint;

    const palette = [
      0xFF00E676,
      0xFF00B0FF,
      0xFFFFAB00,
      0xFFFF5252,
      0xFFE040FB,
      0xFF1DE9B6,
    ];
    final icons = _folderIcons.keys.toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Nueva Carpeta' : 'Editar Carpeta',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de carpeta',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final c in palette)
                        GestureDetector(
                          onTap: () => setDialogState(() => selectedColor = c),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: Color(c),
                            child:
                                selectedColor == c
                                    ? const Icon(
                                      Icons.check,
                                      color: Colors.black,
                                      size: 18,
                                    )
                                    : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final ic in icons)
                        IconButton(
                          icon: Icon(
                            _iconFor(ic),
                            color:
                                selectedIcon == ic
                                    ? Color(selectedColor)
                                    : Colors.white54,
                          ),
                          onPressed:
                              () => setDialogState(() => selectedIcon = ic),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                if (existing != null)
                  TextButton(
                    onPressed: () {
                      _state.folders.removeWhere((f) => f.id == existing.id);
                      for (final r in _state.reminders) {
                        if (r.folderId == existing.id) r.folderId = null;
                      }
                      Navigator.pop(ctx);
                      _save();
                    },
                    child: const Text(
                      'Eliminar',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final txt = nameCtrl.text.trim();
                    if (txt.isEmpty) return;
                    if (existing == null) {
                      _state.folders.add(
                        Folder(
                          id: 'f_${DateTime.now().millisecondsSinceEpoch}',
                          name: txt,
                          color: selectedColor,
                          icon: selectedIcon,
                        ),
                      );
                    } else {
                      existing.name = txt;
                      existing.color = selectedColor;
                      existing.icon = selectedIcon;
                    }
                    Navigator.pop(ctx);
                    _save();
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openReminderEditor({Reminder? existing}) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ReminderEditorScreen(
              existing: existing,
              folders: _state.folders,
            ),
      ),
    );
    if (result == 'delete' && existing != null) {
      _state.reminders.removeWhere((r) => r.id == existing.id);
      await _save();
    } else if (result == 'saved') {
      await _save();
    }
  }

  Future<void> _openBatteryShieldSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0A0A0A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> trigger(String kind) async {
              await AlarmApi.requestPermission(kind);
              await Future<void>.delayed(const Duration(milliseconds: 600));
              final updated = await AlarmApi.getPermissionStatus();
              if (mounted) {
                setState(() => _perms = updated);
                setSheet(() {});
              }
            }

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Blindaje Anti-Batería & Samsung',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'La app usa AlarmManager.setAlarmClock() (0% consumo en espera). Activá estos permisos para que Samsung/Android jamás bloquee el disparo:',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  _permTile(
                    title: 'Ignorar optimización de batería (Doze)',
                    ok: _perms['battery'] ?? false,
                    onTap: () => trigger('battery'),
                  ),
                  _permTile(
                    title: 'Alarmas exactas (USE_EXACT_ALARM)',
                    ok: _perms['exactAlarm'] ?? false,
                    onTap: () => trigger('exactAlarm'),
                  ),
                  _permTile(
                    title: 'Notificaciones y próxima alarma',
                    ok: _perms['notifications'] ?? false,
                    onTap: () => trigger('notifications'),
                  ),
                  _permTile(
                    title: 'Mostrar sobre pantalla de bloqueo (Full Screen)',
                    ok: _perms['fullScreen'] ?? false,
                    onTap: () => trigger('fullScreen'),
                  ),
                  const Divider(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.phone_android,
                      color: Colors.lightBlueAccent,
                    ),
                    title: const Text(
                      'Samsung One UI: Batería -> "No restringido"',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Tocá para abrir Info de la App -> Batería -> Elegí "No restringido" y quitá de "Suspensión profunda".',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => trigger('appDetails'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    await _refreshAll();
  }

  Widget _permTile({
    required String title,
    required bool ok,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle : Icons.error_outline,
        color: ok ? const Color(0xFF00E676) : Colors.amberAccent,
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing:
          ok
              ? const Text(
                'Activo',
                style: TextStyle(color: Color(0xFF00E676), fontSize: 12),
              )
              : FilledButton.tonal(
                onPressed: onTap,
                child: const Text('Activar'),
              ),
    );
  }

  Future<void> _openSettingsSheet() async {
    final s = _state.settings;
    int ringMins = s.ringDurationMinutes;
    int pauseMins = s.autoSnoozeMinutes;
    int retries = s.maxAutoRetries;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0A0A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ajustes Globales (Alarmas no atendidas)',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _numberRow(
                    label: 'Duración sonando (minutos)',
                    value: ringMins,
                    min: 1,
                    max: 30,
                    onChanged: (v) => setSheet(() => ringMins = v),
                  ),
                  _numberRow(
                    label: 'Espera antes de reintentar (minutos)',
                    value: pauseMins,
                    min: 1,
                    max: 60,
                    onChanged: (v) => setSheet(() => pauseMins = v),
                  ),
                  _numberRow(
                    label: 'Cantidad de repeticiones (N ciclos)',
                    value: retries,
                    min: 0,
                    max: 20,
                    onChanged: (v) => setSheet(() => retries = v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        s.ringDurationMinutes = ringMins;
                        s.autoSnoozeMinutes = pauseMins;
                        s.maxAutoRetries = retries;
                        Navigator.pop(ctx);
                        _save();
                      },
                      child: const Text('Guardar Ajustes'),
                    ),
                  ),
                  const Divider(height: 28),
                  const Text(
                    'Backup Local (JSON)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy),
                          label: const Text('Copiar JSON'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _state.toJsonString()),
                            );
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Backup JSON copiado al portapapeles',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.restore),
                          label: const Text('Importar JSON'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openImportJsonDialog();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _numberRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text(
          '$value',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  Future<void> _openImportJsonDialog() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Importar Backup JSON'),
            content: TextField(
              controller: ctrl,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Pegá acá el contenido JSON exportado...',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    final parsed = AppState.fromJson(
                      jsonDecode(ctrl.text) as Map<String, dynamic>,
                    );
                    _state = parsed;
                    Navigator.pop(ctx);
                    _save();
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('JSON inválido')),
                    );
                  }
                },
                child: const Text('Restaurar'),
              ),
            ],
          ),
    );
  }
}

class ReminderEditorScreen extends StatefulWidget {
  final Reminder? existing;
  final List<Folder> folders;

  const ReminderEditorScreen({
    super.key,
    required this.existing,
    required this.folders,
  });

  @override
  State<ReminderEditorScreen> createState() => _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends State<ReminderEditorScreen> {
  late Reminder _draft;
  late TextEditingController _nameCtrl;
  late TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    if (widget.existing != null) {
      _draft = Reminder.fromJson(widget.existing!.toJson());
    } else {
      final curMin = (now.hour * 60 + now.minute + 5) % 1440;
      _draft = Reminder(
        id: 'r_${now.millisecondsSinceEpoch}',
        name: '',
        anchorDate: fmtDate(now),
        startMinute: curMin,
      );
    }
    _nameCtrl = TextEditingController(text: _draft.name);
    _noteCtrl = TextEditingController(text: _draft.note);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final initMin = isStart ? _draft.startMinute : _draft.endMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initMin ~/ 60, minute: initMin % 60),
    );
    if (picked == null) return;
    setState(() {
      final total = picked.hour * 60 + picked.minute;
      if (isStart) {
        _draft.startMinute = total;
        if (_draft.endMinute < _draft.startMinute) {
          _draft.endMinute = _draft.startMinute;
        }
      } else {
        _draft.endMinute = total;
      }
    });
  }

  Future<void> _pickDate() async {
    final parts = _draft.anchorDate.split('-').map(int.parse).toList();
    final initDate = DateTime(parts[0], parts[1], parts[2]);
    final picked = await showDatePicker(
      context: context,
      initialDate: initDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _draft.anchorDate = fmtDate(picked));
    }
  }

  void _commitSave() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poné un nombre para la alarma')),
      );
      return;
    }
    _draft.name = name;
    _draft.note = _noteCtrl.text.trim();
    _draft.isEnabled = true;
    _draft.skipUntilMs = null;
    _draft.snoozedUntilMs = null;

    if (widget.existing != null) {
      final target = widget.existing!;
      final json = _draft.toJson();
      final updated = Reminder.fromJson(json);
      target.folderId = updated.folderId;
      target.name = updated.name;
      target.note = updated.note;
      target.isEnabled = updated.isEnabled;
      target.skipUntilMs = null;
      target.snoozedUntilMs = null;
      target.snoozeMinutes = updated.snoozeMinutes;
      target.dateRule = updated.dateRule;
      target.anchorDate = updated.anchorDate;
      target.weekdays = updated.weekdays;
      target.everyN = updated.everyN;
      target.everyUnit = updated.everyUnit;
      target.timeRule = updated.timeRule;
      target.startMinute = updated.startMinute;
      target.endMinute = updated.endMinute;
      target.intervalMinutes = updated.intervalMinutes;
      target.soundUri = updated.soundUri;
      target.soundName = updated.soundName;
      target.vibrate = updated.vibrate;
      target.customVolume = updated.customVolume;
    } else {
      // Append to caller's list via Storage or pass back
    }
    Navigator.pop(context, 'saved');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Nueva Alarma' : 'Editar Alarma',
        ),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => Navigator.pop(context, 'delete'),
            ),
          TextButton(
            onPressed: _saveWithAddSupport,
            child: const Text(
              'GUARDAR',
              style: TextStyle(
                color: Color(0xFF00E676),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre del recordatorio *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Nota opcional (se muestra al sonar)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            initialValue: _draft.folderId,
            decoration: const InputDecoration(
              labelText: 'Carpeta',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Sin carpeta (al final de la lista)'),
              ),
              for (final f in widget.folders)
                DropdownMenuItem<String?>(
                  value: f.id,
                  child: Text(f.name),
                ),
            ],
            onChanged: (v) => setState(() => _draft.folderId = v),
          ),
          const SizedBox(height: 20),
          const Text(
            'REGLA DE FECHA',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E676),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<DateRuleType>(
            segments: const [
              ButtonSegment(
                value: DateRuleType.once,
                label: Text('Una vez'),
              ),
              ButtonSegment(
                value: DateRuleType.weekdays,
                label: Text('Días sem.'),
              ),
              ButtonSegment(
                value: DateRuleType.everyN,
                label: Text('Cada N...'),
              ),
            ],
            selected: {_draft.dateRule},
            onSelectionChanged:
                (s) => setState(() => _draft.dateRule = s.first),
          ),
          const SizedBox(height: 12),
          if (_draft.dateRule == DateRuleType.once ||
              _draft.dateRule == DateRuleType.everyN)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _draft.dateRule == DateRuleType.once
                    ? 'Fecha de disparo'
                    : 'Fecha de inicio',
              ),
              trailing: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_draft.anchorDate),
                onPressed: _pickDate,
              ),
            ),
          if (_draft.dateRule == DateRuleType.weekdays)
            Wrap(
              spacing: 6,
              children: [
                for (int d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(
                      const ['', 'L', 'M', 'X', 'J', 'V', 'S', 'D'][d],
                    ),
                    selected: _draft.weekdays.contains(d),
                    onSelected: (sel) {
                      setState(() {
                        final list = [..._draft.weekdays];
                        if (sel) {
                          list.add(d);
                        } else if (list.length > 1) {
                          list.remove(d);
                        }
                        _draft.weekdays = list;
                      });
                    },
                  ),
              ],
            ),
          if (_draft.dateRule == DateRuleType.everyN)
            Row(
              children: [
                const Text('Repetir cada: '),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed:
                      _draft.everyN > 1
                          ? () => setState(() => _draft.everyN--)
                          : null,
                ),
                Text(
                  '${_draft.everyN}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _draft.everyN++),
                ),
                const SizedBox(width: 8),
                DropdownButton<IntervalUnit>(
                  value: _draft.everyUnit,
                  items: const [
                    DropdownMenuItem(
                      value: IntervalUnit.days,
                      child: Text('Días'),
                    ),
                    DropdownMenuItem(
                      value: IntervalUnit.weeks,
                      child: Text('Semanas'),
                    ),
                    DropdownMenuItem(
                      value: IntervalUnit.months,
                      child: Text('Meses'),
                    ),
                  ],
                  onChanged:
                      (v) =>
                          v != null
                              ? setState(() => _draft.everyUnit = v)
                              : null,
                ),
              ],
            ),
          const Divider(height: 28),
          const Text(
            'REGLA DE HORA (FIJA O RECURSIVA POR HORA)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E676),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<TimeRuleType>(
            segments: const [
              ButtonSegment(
                value: TimeRuleType.fixed,
                label: Text('Hora fija'),
              ),
              ButtonSegment(
                value: TimeRuleType.hourly,
                label: Text('Recursiva por hora'),
              ),
            ],
            selected: {_draft.timeRule},
            onSelectionChanged:
                (s) => setState(() => _draft.timeRule = s.first),
          ),
          const SizedBox(height: 12),
          if (_draft.timeRule == TimeRuleType.fixed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hora de alarma'),
              trailing: FilledButton.tonal(
                onPressed: () => _pickTime(true),
                child: Text(
                  fmtMin(_draft.startMinute),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Ventana activa:'),
                TextButton(
                  onPressed:
                      () => setState(() {
                        _draft.startMinute = 0;
                        _draft.endMinute = 1439;
                      }),
                  child: const Text('Todo el día (24h)'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(true),
                    child: Text('Inicio: ${fmtMin(_draft.startMinute)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(false),
                    child: Text('Fin: ${fmtMin(_draft.endMinute)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Intervalo en grilla fija:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final mins in [15, 30, 45, 60, 120, 180, 240, 360])
                  ChoiceChip(
                    label: Text(
                      mins < 60
                          ? '${mins}m'
                          : (mins % 60 == 0
                              ? '${mins ~/ 60}h'
                              : '${mins ~/ 60}h ${mins % 60}m'),
                    ),
                    selected: _draft.intervalMinutes == mins,
                    onSelected:
                        (_) => setState(() => _draft.intervalMinutes = mins),
                  ),
              ],
            ),
          ],
          const Divider(height: 28),
          const Text(
            'APLAZAMIENTO Y SONIDO (CANAL ALARMA)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E676),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tiempo del botón "Aplazar"'),
            trailing: DropdownButton<int>(
              value: _draft.snoozeMinutes,
              items: [
                for (final m in [5, 10, 15, 20, 30, 45, 60])
                  DropdownMenuItem(value: m, child: Text('$m min')),
              ],
              onChanged:
                  (v) =>
                      v != null ? setState(() => _draft.snoozeMinutes = v) : null,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sonido de alarma'),
            subtitle: Text(
              _draft.soundName,
              style: const TextStyle(color: Color(0xFF00E676)),
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.music_note),
              onSelected: (choice) async {
                if (choice == 'default') {
                  setState(() {
                    _draft.soundUri = '';
                    _draft.soundName = 'Predeterminado';
                  });
                } else if (choice == 'system') {
                  final picked = await AlarmApi.pickSystemAlarmTone(
                    _draft.soundUri,
                  );
                  if (picked != null) {
                    setState(() {
                      _draft.soundUri = picked['uri'] ?? '';
                      _draft.soundName = picked['name'] ?? 'Tono del sistema';
                    });
                  }
                } else if (choice == 'file') {
                  final picked = await AlarmApi.pickAudioFile();
                  if (picked != null) {
                    setState(() {
                      _draft.soundUri = picked['uri'] ?? '';
                      _draft.soundName = picked['name'] ?? 'Archivo local';
                    });
                  }
                }
              },
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(
                      value: 'default',
                      child: Text('Predeterminado del sistema'),
                    ),
                    PopupMenuItem(
                      value: 'system',
                      child: Text('Elegir alarma del sistema...'),
                    ),
                    PopupMenuItem(
                      value: 'file',
                      child: Text('Elegir archivo de audio (.mp3/.ogg)...'),
                    ),
                  ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibración'),
            value: _draft.vibrate,
            onChanged: (v) => setState(() => _draft.vibrate = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Forzar volumen de alarma específico'),
            subtitle: Text(
              _draft.customVolume == null
                  ? 'Usa el volumen de alarma actual del sistema'
                  : 'Forzado al ${_draft.customVolume}%',
            ),
            value: _draft.customVolume != null,
            onChanged:
                (v) => setState(() => _draft.customVolume = v ? 85 : null),
          ),
          if (_draft.customVolume != null)
            Slider(
              value: _draft.customVolume!.toDouble(),
              min: 10,
              max: 100,
              divisions: 18,
              label: '${_draft.customVolume}%',
              onChanged:
                  (v) => setState(() => _draft.customVolume = v.round()),
            ),
        ],
      ),
    );
  }

  Future<void> _saveWithAddSupport() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poné un nombre para la alarma')),
      );
      return;
    }
    if (widget.existing == null) {
      _draft.name = name;
      _draft.note = _noteCtrl.text.trim();
      final state = await Storage.load();
      state.reminders.add(_draft);
      await Storage.saveAndSync(state);
      if (mounted) Navigator.pop(context, 'saved');
    } else {
      _commitSave();
    }
  }
}

class RingingScreen extends StatelessWidget {
  final Map<String, dynamic> alarm;
  final VoidCallback onDismiss;
  final VoidCallback onSnooze;

  const RingingScreen({
    super.key,
    required this.alarm,
    required this.onDismiss,
    required this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final name = (alarm['name'] as String?) ?? 'Alarma';
    final note = (alarm['note'] as String?) ?? '';
    final snoozeMins = (alarm['snoozeMinutes'] as int?) ?? 10;
    final retry = (alarm['retryCount'] as int?) ?? 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  const SizedBox(height: 24),
                  const Icon(
                    Icons.alarm_on,
                    size: 56,
                    color: Color(0xFF00E676),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  if (retry > 0)
                    Text(
                      'Reintento automático #$retry',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
              Column(
                children: [
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      note,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 68,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Colors.amberAccent,
                          width: 2,
                        ),
                        foregroundColor: Colors.amberAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.snooze, size: 28),
                      label: Text(
                        'APLAZAR (+$snoozeMins MIN)',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: onSnooze,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 76,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.alarm_off, size: 30),
                      label: const Text(
                        'APAGAR ALARMA',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      onPressed: onDismiss,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
