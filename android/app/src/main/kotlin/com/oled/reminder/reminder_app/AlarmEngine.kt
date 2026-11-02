package com.oled.reminder.reminder_app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

object AlarmEngine {
    const val ACTION_FIRE = "com.oled.reminder.ACTION_FIRE"
    const val ACTION_DISMISS = "com.oled.reminder.ACTION_DISMISS"
    const val ACTION_SNOOZE = "com.oled.reminder.ACTION_SNOOZE"
    const val ACTION_SKIP_NEXT = "com.oled.reminder.ACTION_SKIP_NEXT"

    const val CH_RINGING = "oled_alarm_ringing"
    const val CH_UPCOMING = "oled_alarm_upcoming_v2"
    const val CH_MISSED = "oled_alarm_missed"

    const val NOTIF_RINGING = 1001
    const val NOTIF_UPCOMING = 1002
    const val NOTIF_MISSED_BASE = 2000

    const val REQ_ALARM_CLOCK = 9001
    const val REQ_SKIP_NEXT = 9002
    const val REQ_DISMISS = 9003
    const val REQ_SNOOZE = 9004

    @Volatile
    var activeAlarmId: String? = null
    @Volatile
    var activeRetryCount: Int = 0
    @Volatile
    var activeAlarmJson: JSONObject? = null
    @Volatile
    var onStateChangedCallback: ((String) -> Unit)? = null

    fun deviceSafeCtx(ctx: Context): Context {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            ctx.createDeviceProtectedStorageContext()
        } else {
            ctx
        }
    }

    fun stateFile(ctx: Context): File {
        val primary = File(deviceSafeCtx(ctx).filesDir, "state.json")
        if (!primary.exists()) {
            val legacy = File(ctx.filesDir, "state.json")
            if (legacy.exists()) {
                try {
                    legacy.copyTo(primary, overwrite = true)
                } catch (_: Exception) {
                    return legacy
                }
            }
        }
        return primary
    }

    fun loadState(ctx: Context): JSONObject {
        val f = stateFile(ctx)
        if (!f.exists()) return defaultState()
        return try {
            val txt = f.readText()
            if (txt.isBlank()) defaultState() else JSONObject(txt)
        } catch (_: Exception) {
            defaultState()
        }
    }

    fun saveState(ctx: Context, root: JSONObject) {
        stateFile(ctx).writeText(root.toString(2))
    }

    private fun defaultState(): JSONObject = JSONObject().apply {
        put("folders", JSONArray())
        put("reminders", JSONArray())
        put("settings", JSONObject().apply {
            put("ringDurationMinutes", 2)
            put("autoSnoozeMinutes", 5)
            put("maxAutoRetries", 3)
        })
    }

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val ringCh = NotificationChannel(
            CH_RINGING,
            "Alarma sonando",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Pantalla de alarma activa"
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        val upCh = NotificationChannel(
            CH_UPCOMING,
            "Próxima alarma",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Muestra la próxima alarma y permite saltarla"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }

        val missedCh = NotificationChannel(
            CH_MISSED,
            "Alarmas perdidas",
            NotificationManager.IMPORTANCE_DEFAULT
        )

        nm.createNotificationChannel(ringCh)
        nm.createNotificationChannel(upCh)
        nm.createNotificationChannel(missedCh)
    }

    private fun matchesDay(rem: JSONObject, dayCal: Calendar): Boolean {
        val anchorStr = rem.optString("anchorDate", "")
        val parts = anchorStr.split("-")
        if (parts.size != 3) return true
        val ay = parts[0].toIntOrNull() ?: return true
        val am = (parts[1].toIntOrNull() ?: 1) - 1
        val ad = parts[2].toIntOrNull() ?: 1

        val anchorCal = Calendar.getInstance().apply {
            set(ay, am, ad, 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }

        return when (rem.optString("dateRule", "weekdays")) {
            "once" -> dayCal.get(Calendar.YEAR) == ay &&
                    dayCal.get(Calendar.MONTH) == am &&
                    dayCal.get(Calendar.DAY_OF_MONTH) == ad
            "weekdays" -> {
                val arr = rem.optJSONArray("weekdays") ?: return true
                // Calendar: SUN=1, MON=2..SAT=7 -> ISO: MON=1..SUN=7
                val dow = dayCal.get(Calendar.DAY_OF_WEEK)
                val iso = if (dow == Calendar.SUNDAY) 7 else dow - 1
                for (i in 0 until arr.length()) {
                    if (arr.optInt(i) == iso) return true
                }
                false
            }
            "everyN" -> {
                if (dayCal.timeInMillis < anchorCal.timeInMillis) return false
                val n = rem.optInt("everyN", 1).coerceAtLeast(1)
                val diffDays = ((dayCal.timeInMillis - anchorCal.timeInMillis) / 86_400_000L).toInt()
                when (rem.optString("everyUnit", "days")) {
                    "days" -> diffDays % n == 0
                    "weeks" -> dayCal.get(Calendar.DAY_OF_WEEK) == anchorCal.get(Calendar.DAY_OF_WEEK) &&
                            (diffDays / 7) % n == 0
                    "months" -> {
                        if (dayCal.get(Calendar.DAY_OF_MONTH) != anchorCal.get(Calendar.DAY_OF_MONTH)) return false
                        val diffMonths = (dayCal.get(Calendar.YEAR) - ay) * 12 + (dayCal.get(Calendar.MONTH) - am)
                        diffMonths >= 0 && diffMonths % n == 0
                    }
                    else -> diffDays % n == 0
                }
            }
            else -> true
        }
    }

    private fun daySlots(rem: JSONObject): IntArray {
        val start = rem.optInt("startMinute", 480)
        if (rem.optString("timeRule", "fixed") == "fixed") return intArrayOf(start)
        val end = rem.optInt("endMinute", 1320).coerceAtLeast(start)
        val step = rem.optInt("intervalMinutes", 120).coerceAtLeast(1)
        val list = ArrayList<Int>()
        var m = start
        while (m <= end) {
            list.add(m)
            m += step
        }
        return list.toIntArray()
    }

    fun nextGridTriggerMs(rem: JSONObject, afterMs: Long, ignoreSkip: Boolean = false): Long? {
        val slots = daySlots(rem)
        if (slots.isEmpty()) return null
        val skipUntil = if (rem.isNull("skipUntilMs")) null else rem.optLong("skipUntilMs")
        val baseCal = Calendar.getInstance().apply {
            timeInMillis = afterMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        for (offset in 0..400) {
            val dayCal = (baseCal.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, offset)
            }
            if (!matchesDay(rem, dayCal)) continue
            for (slot in slots) {
                val candCal = (dayCal.clone() as Calendar).apply {
                    set(Calendar.HOUR_OF_DAY, slot / 60)
                    set(Calendar.MINUTE, slot % 60)
                }
                val candMs = candCal.timeInMillis
                if (candMs <= afterMs) continue
                if (!ignoreSkip && skipUntil != null && candMs <= skipUntil) continue
                return candMs
            }
        }
        return null
    }

    data class ScheduledTarget(
        val reminder: JSONObject,
        val triggerMs: Long,
        val isSnooze: Boolean,
        val retryCount: Int
    )

    fun findNextTarget(root: JSONObject, nowMs: Long): ScheduledTarget? {
        val folders = root.optJSONArray("folders") ?: JSONArray()
        val folderEnabled = HashMap<String, Boolean>()
        for (i in 0 until folders.length()) {
            val f = folders.optJSONObject(i) ?: continue
            folderEnabled[f.optString("id")] = f.optBoolean("isEnabled", true)
        }

        val reminders = root.optJSONArray("reminders") ?: JSONArray()
        var best: ScheduledTarget? = null

        for (i in 0 until reminders.length()) {
            val r = reminders.optJSONObject(i) ?: continue
            if (!r.optBoolean("isEnabled", true)) continue
            val fId = if (r.isNull("folderId")) null else r.optString("folderId", "")
            if (!fId.isNullOrEmpty() && folderEnabled[fId] == false) continue

            val gridMs = nextGridTriggerMs(r, nowMs, ignoreSkip = false)
            val snoozeMs = if (r.isNull("snoozedUntilMs")) null else r.optLong("snoozedUntilMs")
            val retry = r.optInt("autoRetryCount", 0)

            val candidate: ScheduledTarget? = if (snoozeMs != null && snoozeMs > nowMs && (gridMs == null || snoozeMs < gridMs)) {
                ScheduledTarget(r, snoozeMs, isSnooze = true, retryCount = retry)
            } else if (gridMs != null) {
                ScheduledTarget(r, gridMs, isSnooze = false, retryCount = 0)
            } else {
                null
            }

            if (candidate != null && (best == null || candidate.triggerMs < best.triggerMs)) {
                best = candidate
            }
        }
        return best
    }

    fun syncSchedule(ctx: Context) {
        ensureChannels(ctx)
        val root = loadState(ctx)
        val nowMs = System.currentTimeMillis()
        val next = findNextTarget(root, nowMs)
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val fireIntent = Intent(ctx, AlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            if (next != null) {
                putExtra("ALARM_ID", next.reminder.optString("id"))
                putExtra("IS_SNOOZE", next.isSnooze)
                putExtra("RETRY_COUNT", next.retryCount)
            }
        }
        val firePi = PendingIntent.getBroadcast(
            ctx,
            REQ_ALARM_CLOCK,
            fireIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (next == null) {
            am.cancel(firePi)
            nm.cancel(NOTIF_UPCOMING)
            return
        }

        val showIntent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val showPi = PendingIntent.getActivity(
            ctx,
            0,
            showIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            val info = AlarmManager.AlarmClockInfo(next.triggerMs, showPi)
            am.setAlarmClock(info, firePi)
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.triggerMs, firePi)
        }

        showUpcomingNotification(ctx, next)
    }

    private fun showUpcomingNotification(ctx: Context, target: ScheduledTarget) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val r = target.reminder
        val id = r.optString("id")
        val name = r.optString("name", "Alarma")
        val fmt = SimpleDateFormat("EEE HH:mm", Locale.getDefault())
        val timeStr = fmt.format(Date(target.triggerMs))

        val openIntent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPi = PendingIntent.getActivity(
            ctx,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val skipIntent = Intent(ctx, AlarmReceiver::class.java).apply {
            action = ACTION_SKIP_NEXT
            putExtra("ALARM_ID", id)
            putExtra("TARGET_MS", target.triggerMs)
        }
        val skipPi = PendingIntent.getBroadcast(
            ctx,
            REQ_SKIP_NEXT,
            skipIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, CH_UPCOMING)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }

        val action = Notification.Action.Builder(
            android.R.drawable.ic_media_next,
            "Saltar proxima alarma",
            skipPi
        ).build()

        val notif = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Próxima: $name")
            .setContentText("Suena: $timeStr")
            .setContentIntent(openPi)
            .setOngoing(true)
            .addAction(action)
            .build()

        nm.notify(NOTIF_UPCOMING, notif)
    }

    fun handleSkipNext(ctx: Context, alarmId: String, targetMs: Long) {
        val root = loadState(ctx)
        val reminders = root.optJSONArray("reminders") ?: return
        val nowMs = System.currentTimeMillis()
        for (i in 0 until reminders.length()) {
            val r = reminders.optJSONObject(i) ?: continue
            if (r.optString("id") == alarmId) {
                r.put("snoozedUntilMs", JSONObject.NULL)
                r.put("autoRetryCount", 0)
                val skipTo = if (targetMs > nowMs) targetMs else (nextGridTriggerMs(r, nowMs, ignoreSkip = false) ?: nowMs)
                r.put("skipUntilMs", skipTo)
                break
            }
        }
        saveState(ctx, root)
        syncSchedule(ctx)
        notifyFlutter("reload")
    }

    fun handleFire(ctx: Context, alarmId: String, isSnooze: Boolean, retryCount: Int) {
        val root = loadState(ctx)
        val reminders = root.optJSONArray("reminders") ?: JSONArray()
        var targetRem: JSONObject? = null
        val nowMs = System.currentTimeMillis()

        for (i in 0 until reminders.length()) {
            val r = reminders.optJSONObject(i) ?: continue
            if (r.optString("id") == alarmId) {
                targetRem = r
                r.put("snoozedUntilMs", JSONObject.NULL)
                // If it's a normal grid trigger (not a snooze retry), reset retry count and disable if 'once' with no future slots today
                if (!isSnooze) {
                    r.put("autoRetryCount", 0)
                    if (r.optString("dateRule") == "once") {
                        val nextGrid = nextGridTriggerMs(r, nowMs + 1000L, ignoreSkip = false)
                        if (nextGrid == null) {
                            r.put("isEnabled", false)
                        }
                    }
                }
                break
            }
        }

        saveState(ctx, root)

        if (targetRem == null) {
            syncSchedule(ctx)
            return
        }

        // Start foreground ringing service (replaces any previous ringing alarm and resets retry counter if new schedule)
        activeAlarmId = alarmId
        activeRetryCount = if (isSnooze) retryCount else 0
        activeAlarmJson = targetRem

        val svcIntent = Intent(ctx, AlarmService::class.java).apply {
            putExtra("ALARM_ID", alarmId)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ctx.startForegroundService(svcIntent)
        } else {
            ctx.startService(svcIntent)
        }

        syncSchedule(ctx)
        notifyFlutter("ringing")
    }

    fun handleDismiss(ctx: Context) {
        val id = activeAlarmId
        stopRingingService(ctx)
        if (id != null) {
            val root = loadState(ctx)
            val reminders = root.optJSONArray("reminders") ?: JSONArray()
            for (i in 0 until reminders.length()) {
                val r = reminders.optJSONObject(i) ?: continue
                if (r.optString("id") == id) {
                    r.put("snoozedUntilMs", JSONObject.NULL)
                    r.put("autoRetryCount", 0)
                    break
                }
            }
            saveState(ctx, root)
        }
        syncSchedule(ctx)
        notifyFlutter("reload")
    }

    fun handleManualSnooze(ctx: Context) {
        val id = activeAlarmId ?: return
        val rem = activeAlarmJson
        val snoozeMins = rem?.optInt("snoozeMinutes", 10)?.coerceAtLeast(1) ?: 10
        stopRingingService(ctx)

        val root = loadState(ctx)
        val reminders = root.optJSONArray("reminders") ?: JSONArray()
        val targetMs = System.currentTimeMillis() + snoozeMins * 60_000L
        for (i in 0 until reminders.length()) {
            val r = reminders.optJSONObject(i) ?: continue
            if (r.optString("id") == id) {
                r.put("snoozedUntilMs", targetMs)
                r.put("autoRetryCount", 0)
                if (r.optString("dateRule") == "once") {
                    r.put("isEnabled", true)
                }
                break
            }
        }
        saveState(ctx, root)
        syncSchedule(ctx)
        notifyFlutter("reload")
    }

    /**
     * Pure state transition when an alarm rings for [ringDurationMinutes] without user interaction.
     * Mutates [root] in-place and returns true if a missed-alarm notification should be shown.
     */
    fun applyAutoTimeoutToState(
        root: JSONObject,
        alarmId: String,
        curRetry: Int,
        nowMs: Long
    ): Boolean {
        val settings = root.optJSONObject("settings") ?: JSONObject()
        val autoSnoozeMins = settings.optInt("autoSnoozeMinutes", 5).coerceAtLeast(1)
        val maxRetries = settings.optInt("maxAutoRetries", 3).coerceAtLeast(0)
        val nextRetryMs = nowMs + autoSnoozeMins * 60_000L

        val nextGridOverall = findNextGridOnlyTarget(root, nowMs)
        val collidesWithNextSchedule = nextGridOverall != null && nextGridOverall.triggerMs <= nextRetryMs

        var missed = false
        val reminders = root.optJSONArray("reminders") ?: JSONArray()
        for (i in 0 until reminders.length()) {
            val r = reminders.optJSONObject(i) ?: continue
            if (r.optString("id") == alarmId) {
                if (collidesWithNextSchedule) {
                    r.put("snoozedUntilMs", JSONObject.NULL)
                    r.put("autoRetryCount", 0)
                } else if (curRetry < maxRetries) {
                    r.put("snoozedUntilMs", nextRetryMs)
                    r.put("autoRetryCount", curRetry + 1)
                    if (r.optString("dateRule") == "once") {
                        r.put("isEnabled", true)
                    }
                } else {
                    r.put("snoozedUntilMs", JSONObject.NULL)
                    r.put("autoRetryCount", 0)
                    missed = true
                }
                break
            }
        }
        return missed
    }

    fun handleAutoTimeout(ctx: Context) {
        val id = activeAlarmId ?: return
        val rem = activeAlarmJson
        val curRetry = activeRetryCount
        stopRingingService(ctx)

        val root = loadState(ctx)
        val missed = applyAutoTimeoutToState(root, id, curRetry, System.currentTimeMillis())
        if (missed) {
            showMissedNotification(ctx, rem?.optString("name", "Alarma") ?: "Alarma")
        }
        saveState(ctx, root)
        syncSchedule(ctx)
        notifyFlutter("reload")
    }

    fun findNextGridOnlyTarget(root: JSONObject, nowMs: Long): ScheduledTarget? {
        val folders = root.optJSONArray("folders") ?: JSONArray()
        val folderEnabled = HashMap<String, Boolean>()
        for (i in 0 until folders.length()) {
            val f = folders.optJSONObject(i) ?: continue
            folderEnabled[f.optString("id")] = f.optBoolean("isEnabled", true)
        }
        val reminders = root.optJSONArray("reminders") ?: JSONArray()
        var best: ScheduledTarget? = null
        for (i in 0 until reminders.length()) {
            val r = reminders.optJSONObject(i) ?: continue
            if (!r.optBoolean("isEnabled", true)) continue
            val fId = if (r.isNull("folderId")) null else r.optString("folderId", "")
            if (!fId.isNullOrEmpty() && folderEnabled[fId] == false) continue
            val gridMs = nextGridTriggerMs(r, nowMs, ignoreSkip = false) ?: continue
            if (best == null || gridMs < best.triggerMs) {
                best = ScheduledTarget(r, gridMs, isSnooze = false, retryCount = 0)
            }
        }
        return best
    }

    private fun showMissedNotification(ctx: Context, name: String) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, CH_MISSED)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        val notif = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Alarma perdida: $name")
            .setContentText("No se atendió tras los reintentos configurados")
            .setAutoCancel(true)
            .build()
        nm.notify(NOTIF_MISSED_BASE + (System.currentTimeMillis() % 500).toInt(), notif)
    }

    private fun stopRingingService(ctx: Context) {
        activeAlarmId = null
        activeAlarmJson = null
        activeRetryCount = 0
        ctx.stopService(Intent(ctx, AlarmService::class.java))
    }

    fun notifyFlutter(event: String) {
        Handler(Looper.getMainLooper()).post {
            onStateChangedCallback?.invoke(event)
        }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                AlarmEngine.syncSchedule(context)
            }
            AlarmEngine.ACTION_FIRE -> {
                val id = intent.getStringExtra("ALARM_ID") ?: return
                val isSnooze = intent.getBooleanExtra("IS_SNOOZE", false)
                val retryCount = intent.getIntExtra("RETRY_COUNT", 0)
                AlarmEngine.handleFire(context, id, isSnooze, retryCount)
            }
            AlarmEngine.ACTION_DISMISS -> {
                AlarmEngine.handleDismiss(context)
            }
            AlarmEngine.ACTION_SNOOZE -> {
                AlarmEngine.handleManualSnooze(context)
            }
            AlarmEngine.ACTION_SKIP_NEXT -> {
                val id = intent.getStringExtra("ALARM_ID") ?: return
                val targetMs = intent.getLongExtra("TARGET_MS", 0L)
                AlarmEngine.handleSkipNext(context, id, targetMs)
            }
        }
    }
}

class AlarmService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var previousAlarmVolume: Int? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeoutRunnable = Runnable {
        AlarmEngine.handleAutoTimeout(applicationContext)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        AlarmEngine.ensureChannels(this)
        stopMediaAndTimeout()

        val rem = AlarmEngine.activeAlarmJson
        val root = AlarmEngine.loadState(this)
        val settings = root.optJSONObject("settings") ?: JSONObject()
        val ringMins = settings.optInt("ringDurationMinutes", 2).coerceAtLeast(1)

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "oled_alarm:ring_wakelock"
        ).apply {
            acquire(ringMins * 60_000L + 10_000L)
        }

        val name = rem?.optString("name", "Alarma") ?: "Alarma"
        val note = rem?.optString("note", "") ?: ""
        val snoozeMins = rem?.optInt("snoozeMinutes", 10) ?: 10

        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("RINGING", true)
        }
        val fullScreenPi = PendingIntent.getActivity(
            this,
            0,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val dismissIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = AlarmEngine.ACTION_DISMISS
        }
        val dismissPi = PendingIntent.getBroadcast(
            this,
            AlarmEngine.REQ_DISMISS,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val snoozeIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = AlarmEngine.ACTION_SNOOZE
        }
        val snoozePi = PendingIntent.getBroadcast(
            this,
            AlarmEngine.REQ_SNOOZE,
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, AlarmEngine.CH_RINGING)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val dismissAction = Notification.Action.Builder(
            android.R.drawable.ic_menu_close_clear_cancel,
            "Apagar",
            dismissPi
        ).build()
        val snoozeAction = Notification.Action.Builder(
            android.R.drawable.ic_popup_reminder,
            "Aplazar (${snoozeMins}m)",
            snoozePi
        ).build()

        val notif = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(name)
            .setContentText(if (note.isNotBlank()) note else "Alarma sonando")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setFullScreenIntent(fullScreenPi, true)
            .addAction(dismissAction)
            .addAction(snoozeAction)
            .build()

        startForeground(AlarmEngine.NOTIF_RINGING, notif)

        try {
            startActivity(fullScreenIntent)
        } catch (_: Exception) {
        }

        startAlarmAudioAndVibration(rem)
        handler.postDelayed(timeoutRunnable, ringMins * 60_000L)

        return START_NOT_STICKY
    }

    private fun startAlarmAudioAndVibration(rem: JSONObject?) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (rem != null && !rem.isNull("customVolume")) {
            val pct = rem.optInt("customVolume", 100).coerceIn(1, 100)
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            previousAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            val targetVol = ((maxVol * pct) / 100.0).toInt().coerceAtLeast(1)
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, targetVol, 0)
        }

        val uriStr = rem?.optString("soundUri", "") ?: ""
        val soundUri: Uri = if (uriStr.isNotBlank()) {
            Uri.parse(uriStr)
        } else {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        }

        try {
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                try {
                    setDataSource(applicationContext, soundUri)
                } catch (_: Exception) {
                    val fallback = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    setDataSource(applicationContext, fallback)
                }
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Exception) {
        }

        val vibrate = rem?.optBoolean("vibrate", true) ?: true
        if (vibrate) {
            @Suppress("DEPRECATION")
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            val pattern = longArrayOf(0, 600, 400, 600, 400)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .build()
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0), attrs)
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        }
    }

    private fun stopMediaAndTimeout() {
        handler.removeCallbacks(timeoutRunnable)
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
        } catch (_: Exception) {
        }
        mediaPlayer = null

        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        vibrator = null

        previousAlarmVolume?.let { prev ->
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, prev, 0)
            } catch (_: Exception) {
            }
            previousAlarmVolume = null
        }

        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    override fun onDestroy() {
        stopMediaAndTimeout()
        super.onDestroy()
    }
}
