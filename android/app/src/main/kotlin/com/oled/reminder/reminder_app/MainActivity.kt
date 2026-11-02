package com.oled.reminder.reminder_app

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQ_RINGTONE = 3001
        private const val REQ_AUDIO_FILE = 3002
        private const val REQ_POST_NOTIF = 3003
    }

    private var pendingSoundResult: MethodChannel.Result? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableLockscreenWake()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enableLockscreenWake()
        channel?.invokeMethod("onStateChanged", "ringing")
    }

    private fun enableLockscreenWake() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            km.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alarm")
        channel = ch

        AlarmEngine.onStateChangedCallback = { event ->
            ch.invokeMethod("onStateChanged", event)
        }

        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStateFilePath" -> {
                    result.success(AlarmEngine.stateFile(applicationContext).absolutePath)
                }
                "syncSchedule" -> {
                    AlarmEngine.syncSchedule(applicationContext)
                    result.success(null)
                }
                "getRingingAlarm" -> {
                    val active = AlarmEngine.activeAlarmJson
                    if (active == null || AlarmEngine.activeAlarmId == null) {
                        result.success(null)
                    } else {
                        val map = HashMap<String, Any?>()
                        map["id"] = active.optString("id")
                        map["name"] = active.optString("name", "Alarma")
                        map["note"] = active.optString("note", "")
                        map["snoozeMinutes"] = active.optInt("snoozeMinutes", 10)
                        map["retryCount"] = AlarmEngine.activeRetryCount
                        result.success(map)
                    }
                }
                "dismissRinging" -> {
                    AlarmEngine.handleDismiss(applicationContext)
                    result.success(null)
                }
                "snoozeRinging" -> {
                    AlarmEngine.handleManualSnooze(applicationContext)
                    result.success(null)
                }
                "pickSystemAlarmTone" -> {
                    if (pendingSoundResult != null) {
                        result.error("BUSY", "Picker already open", null)
                        return@setMethodCallHandler
                    }
                    pendingSoundResult = result
                    val curUriStr = call.argument<String>("currentUri") ?: ""
                    val existingUri = if (curUriStr.isNotBlank()) {
                        Uri.parse(curUriStr)
                    } else {
                        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    }
                    val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, existingUri)
                    }
                    startActivityForResult(intent, REQ_RINGTONE)
                }
                "pickAudioFile" -> {
                    if (pendingSoundResult != null) {
                        result.error("BUSY", "Picker already open", null)
                        return@setMethodCallHandler
                    }
                    pendingSoundResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "audio/*"
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                    startActivityForResult(intent, REQ_AUDIO_FILE)
                }
                "getPermissionStatus" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                    val batteryIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        pm.isIgnoringBatteryOptimizations(packageName)
                    } else true

                    val exactAlarm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        am.canScheduleExactAlarms()
                    } else true

                    val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                    } else true

                    val fullScreen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        nm.canUseFullScreenIntent()
                    } else true

                    result.success(
                        mapOf(
                            "battery" to batteryIgnored,
                            "exactAlarm" to exactAlarm,
                            "notifications" to notifications,
                            "fullScreen" to fullScreen
                        )
                    )
                }
                "requestPermission" -> {
                    val kind = call.argument<String>("kind") ?: ""
                    when (kind) {
                        "battery" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                try {
                                    val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                        data = Uri.parse("package:$packageName")
                                    }
                                    startActivity(i)
                                } catch (_: Exception) {
                                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                }
                            }
                        }
                        "exactAlarm" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                try {
                                    val i = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                        data = Uri.parse("package:$packageName")
                                    }
                                    startActivity(i)
                                } catch (_: Exception) {
                                }
                            }
                        }
                        "notifications" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_POST_NOTIF)
                            }
                        }
                        "fullScreen" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                                try {
                                    val i = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                        data = Uri.parse("package:$packageName")
                                    }
                                    startActivity(i)
                                } catch (_: Exception) {
                                }
                            }
                        }
                        "appDetails" -> {
                            val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(i)
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val cb = pendingSoundResult ?: return
        pendingSoundResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            cb.success(null)
            return
        }

        when (requestCode) {
            REQ_RINGTONE -> {
                @Suppress("DEPRECATION")
                val uri: Uri? = data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                if (uri == null) {
                    cb.success(mapOf("uri" to "", "name" to "Predeterminado"))
                } else {
                    val rt = RingtoneManager.getRingtone(this, uri)
                    val title = rt?.getTitle(this) ?: "Tono de alarma"
                    cb.success(mapOf("uri" to uri.toString(), "name" to title))
                }
            }
            REQ_AUDIO_FILE -> {
                val uri: Uri? = data.data
                if (uri == null) {
                    cb.success(null)
                } else {
                    try {
                        contentResolver.takePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    } catch (_: Exception) {
                    }
                    var displayName = "Archivo de audio"
                    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIdx >= 0 && cursor.moveToFirst()) {
                            displayName = cursor.getString(nameIdx) ?: displayName
                        }
                    }
                    cb.success(mapOf("uri" to uri.toString(), "name" to displayName))
                }
            }
        }
    }
}
