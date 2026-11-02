package com.oled.reminder.reminder_app

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Calendar

class AlarmEngineTest {

    private fun calMs(year: Int, month1Based: Int, day: Int, hour: Int, min: Int): Long {
        return Calendar.getInstance().apply {
            set(year, month1Based - 1, day, hour, min, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    @Test
    fun rebootRescheduling_loadsStateFileAndFindsEarliestActiveAlarmRespectingFolders() {
        val root = JSONObject().apply {
            put("folders", JSONArray().apply {
                put(JSONObject().apply {
                    put("id", "f_off")
                    put("name", "Trabajo")
                    put("isEnabled", false)
                })
                put(JSONObject().apply {
                    put("id", "f_on")
                    put("name", "Salud")
                    put("isEnabled", true)
                })
            })
            put("reminders", JSONArray().apply {
                // Earlier alarm (09:00), but inside disabled folder -> must be ignored after reboot
                put(JSONObject().apply {
                    put("id", "r_ignored")
                    put("folderId", "f_off")
                    put("name", "Reunión")
                    put("isEnabled", true)
                    put("dateRule", "weekdays")
                    put("anchorDate", "2026-11-02")
                    put("weekdays", JSONArray(listOf(1, 2, 3, 4, 5, 6, 7)))
                    put("timeRule", "fixed")
                    put("startMinute", 540) // 09:00
                })
                // Active alarm in enabled folder -> 10:00, hourly every 2h until 16:00
                put(JSONObject().apply {
                    put("id", "r_active")
                    put("folderId", "f_on")
                    put("name", "Tomar agua")
                    put("isEnabled", true)
                    put("dateRule", "weekdays")
                    put("anchorDate", "2026-11-02")
                    put("weekdays", JSONArray(listOf(1, 2, 3, 4, 5, 6, 7)))
                    put("timeRule", "hourly")
                    put("startMinute", 600) // 10:00
                    put("endMinute", 960)   // 16:00
                    put("intervalMinutes", 120)
                })
            })
            put("settings", JSONObject().apply {
                put("ringDurationMinutes", 2)
                put("autoSnoozeMinutes", 5)
                put("maxAutoRetries", 3)
            })
        }

        // Simulate writing state.json before power off and reading it on BOOT_COMPLETED at 08:30
        val tmp = File.createTempFile("state_reboot_test", ".json")
        tmp.writeText(root.toString(2))
        val reloaded = JSONObject(tmp.readText())
        tmp.delete()

        val bootTimeMs = calMs(2026, 11, 2, 8, 30)
        val next = AlarmEngine.findNextTarget(reloaded, bootTimeMs)
        assertNotNull(next)
        assertEquals("r_active", next!!.reminder.optString("id"))
        assertEquals(calMs(2026, 11, 2, 10, 0), next.triggerMs)
        assertFalse(next.isSnooze)
    }

    @Test
    fun unattendedCycle_retriesNTimeAndStopsWithMissedFlag() {
        val r = JSONObject().apply {
            put("id", "r1")
            put("name", "Pastilla")
            put("isEnabled", true)
            put("dateRule", "weekdays")
            put("anchorDate", "2026-11-02")
            put("weekdays", JSONArray(listOf(1, 2, 3, 4, 5, 6, 7)))
            put("timeRule", "fixed")
            put("startMinute", 480) // 08:00
        }
        val root = JSONObject().apply {
            put("folders", JSONArray())
            put("reminders", JSONArray().put(r))
            put("settings", JSONObject().apply {
                put("ringDurationMinutes", 2)
                put("autoSnoozeMinutes", 5)
                put("maxAutoRetries", 2)
            })
        }

        val t0 = calMs(2026, 11, 2, 8, 2) // 08:00 alarm rang for 2m until 08:02
        // 1st timeout (curRetry = 0 < 2) -> schedules snooze at 08:07, retryCount = 1
        val missed1 = AlarmEngine.applyAutoTimeoutToState(root, "r1", 0, t0)
        assertFalse(missed1)
        assertEquals(1, r.optInt("autoRetryCount"))
        assertEquals(t0 + 5 * 60_000L, r.optLong("snoozedUntilMs"))

        // 2nd timeout (curRetry = 1 < 2) -> schedules snooze, retryCount = 2
        val t1 = t0 + 7 * 60_000L
        val missed2 = AlarmEngine.applyAutoTimeoutToState(root, "r1", 1, t1)
        assertFalse(missed2)
        assertEquals(2, r.optInt("autoRetryCount"))

        // 3rd timeout (curRetry = 2 == maxAutoRetries) -> stops retrying, marks missed, schedules next day's 08:00
        val t2 = t1 + 7 * 60_000L
        val missed3 = AlarmEngine.applyAutoTimeoutToState(root, "r1", 2, t2)
        assertTrue(missed3)
        assertEquals(0, r.optInt("autoRetryCount"))
        assertTrue(r.isNull("snoozedUntilMs"))

        val nextAfterMissed = AlarmEngine.findNextTarget(root, t2)
        assertNotNull(nextAfterMissed)
        assertEquals(calMs(2026, 11, 3, 8, 0), nextAfterMissed!!.triggerMs)
    }

    @Test
    fun unattendedCycle_collisionWithNextScheduledSlotResetsCounterAndFiresNewSlot() {
        val r = JSONObject().apply {
            put("id", "r_hourly")
            put("name", "Estirar")
            put("isEnabled", true)
            put("dateRule", "weekdays")
            put("anchorDate", "2026-11-02")
            put("weekdays", JSONArray(listOf(1, 2, 3, 4, 5, 6, 7)))
            put("timeRule", "hourly")
            put("startMinute", 480) // 08:00
            put("endMinute", 600)   // 10:00
            put("intervalMinutes", 15) // 08:00, 08:15, 08:30...
            put("autoRetryCount", 2)
        }
        val root = JSONObject().apply {
            put("folders", JSONArray())
            put("reminders", JSONArray().put(r))
            put("settings", JSONObject().apply {
                put("ringDurationMinutes", 2)
                put("autoSnoozeMinutes", 5)
                put("maxAutoRetries", 5)
            })
        }

        // Suppose it's 08:12 (after a retry), and auto-snooze of 5m would land at 08:17,
        // which collides with the next scheduled grid slot at 08:15!
        val nowMs = calMs(2026, 11, 2, 8, 12)
        val missed = AlarmEngine.applyAutoTimeoutToState(root, "r_hourly", 2, nowMs)
        assertFalse(missed)
        assertEquals(0, r.optInt("autoRetryCount"))
        assertTrue(r.isNull("snoozedUntilMs"))

        // Next target must be the official 08:15 slot with retryCount = 0
        val next = AlarmEngine.findNextTarget(root, nowMs)
        assertNotNull(next)
        assertEquals(calMs(2026, 11, 2, 8, 15), next!!.triggerMs)
        assertFalse(next.isSnooze)
        assertEquals(0, next.retryCount)
    }
}
