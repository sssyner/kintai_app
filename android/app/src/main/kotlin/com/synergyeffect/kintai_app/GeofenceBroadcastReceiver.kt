package com.synergyeffect.kintai_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FieldValue
import io.flutter.plugin.common.EventChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// ジオフェンスイベント受信 BroadcastReceiver
/// ENTER = 自動出勤、EXIT = 自動退勤をFirestoreへ直接書き込む。
/// アプリkill時でも動作する。
class GeofenceBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GeofenceBroadcast"
        private const val CHANNEL_ID = "kintai_geofence_channel"

        /// アプリがフォアグラウンドのときにDart UIへイベントを送信するためのsink
        var eventSink: EventChannel.EventSink? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent)
        if (event == null) {
            Log.w(TAG, "GeofencingEvent is null")
            return
        }
        if (event.hasError()) {
            Log.e(TAG, "GeofencingEvent error: ${event.errorCode}")
            return
        }

        val transition = event.geofenceTransition
        val triggeringGeofences = event.triggeringGeofences ?: return

        for (geofence in triggeringGeofences) {
            val locationId = geofence.requestId
            Log.i(TAG, "Geofence transition: type=$transition, locationId=$locationId")

            when (transition) {
                Geofence.GEOFENCE_TRANSITION_ENTER -> {
                    handleEnterEvent(context, locationId)
                    sendEventToDart("enter", locationId)
                }
                Geofence.GEOFENCE_TRANSITION_EXIT -> {
                    handleExitEvent(context, locationId)
                    sendEventToDart("exit", locationId)
                }
            }
        }
    }

    private fun handleEnterEvent(context: Context, locationId: String) {
        val userInfo = KintaiGeofenceService.getUserInfo(context) ?: run {
            Log.w(TAG, "No user info, skipping ENTER event")
            return
        }

        val (companyId, userId) = userInfo
        val today = todayString()
        val db = FirebaseFirestore.getInstance()
        val ref = db.collection("companies").document(companyId).collection("attendances")

        // 重複チェック: 今日の出勤が既にあるか
        ref.whereEqualTo("userId", userId)
            .whereEqualTo("date", today)
            .limit(1)
            .get()
            .addOnSuccessListener { snapshot ->
                if (!snapshot.isEmpty) {
                    Log.i(TAG, "Already clocked in today, skipping ENTER")
                    return@addOnSuccessListener
                }

                // 拠点名を取得
                db.collection("companies").document(companyId)
                    .collection("locations").document(locationId)
                    .get()
                    .addOnSuccessListener { locDoc ->
                        val locationName = locDoc.getString("name") ?: locationId

                        val data = hashMapOf<String, Any?>(
                            "userId" to userId,
                            "locationId" to locationId,
                            "locationName" to locationName,
                            "clockIn" to FieldValue.serverTimestamp(),
                            "clockOut" to null,
                            "date" to today,
                            "type" to "auto_geofence",
                            "memo" to null,
                        )

                        ref.add(data)
                            .addOnSuccessListener {
                                Log.i(TAG, "Auto clock-in successful at $locationName")
                                showNotification(context, "自動出勤", "${locationName}に出勤しました")
                            }
                            .addOnFailureListener { e ->
                                Log.e(TAG, "Failed to clock in", e)
                            }
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "Failed to get location name", e)
                    }
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Firestore query error", e)
            }
    }

    private fun handleExitEvent(context: Context, locationId: String) {
        val userInfo = KintaiGeofenceService.getUserInfo(context) ?: run {
            Log.w(TAG, "No user info, skipping EXIT event")
            return
        }

        val (companyId, userId) = userInfo
        val today = todayString()
        val db = FirebaseFirestore.getInstance()
        val ref = db.collection("companies").document(companyId).collection("attendances")

        // 今日のclockOutがnullの記録を取得
        ref.whereEqualTo("userId", userId)
            .whereEqualTo("date", today)
            .limit(1)
            .get()
            .addOnSuccessListener { snapshot ->
                if (snapshot.isEmpty) {
                    Log.i(TAG, "No clock-in record found for today, skipping EXIT")
                    return@addOnSuccessListener
                }

                val doc = snapshot.documents[0]
                val clockOut = doc.get("clockOut")

                if (clockOut != null) {
                    Log.i(TAG, "Already clocked out today, skipping EXIT")
                    return@addOnSuccessListener
                }

                val locationName = doc.getString("locationName") ?: locationId

                doc.reference.update("clockOut", FieldValue.serverTimestamp())
                    .addOnSuccessListener {
                        Log.i(TAG, "Auto clock-out successful from $locationName")
                        showNotification(context, "自動退勤", "${locationName}から退勤しました")
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "Failed to clock out", e)
                    }
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Firestore query error", e)
            }
    }

    private fun sendEventToDart(eventType: String, locationId: String) {
        val eventData = mapOf(
            "event" to eventType,
            "locationId" to locationId,
            "timestamp" to System.currentTimeMillis() / 1000.0,
        )
        try {
            eventSink?.success(eventData)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to send event to Dart", e)
        }
    }

    private fun showNotification(context: Context, title: String, body: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "自動打刻通知",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "ジオフェンスによる自動出退勤の通知"
            }
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()

        manager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun todayString(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        return sdf.format(Date())
    }
}
