package com.synergyeffect.kintai_app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/// ネイティブジオフェンスサービス（Android版）
/// GeofencingClient で ENTER/EXIT を検知。イベントは GeofenceBroadcastReceiver で処理。
class KintaiGeofenceService {
    private val channelName = "com.kintai/geofencing"
    private val eventChannelName = "com.kintai/geofencing_events"

    private var context: Context? = null

    fun register(flutterEngine: FlutterEngine, context: Context) {
        this.context = context

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "registerGeofences" -> {
                        val locations = call.arguments as? List<Map<String, Any>>
                        if (locations == null) {
                            result.error("INVALID_ARGS", "Expected list of location maps", null)
                            return@setMethodCallHandler
                        }
                        registerGeofences(locations, result)
                    }
                    "unregisterAll" -> {
                        unregisterAll(result)
                    }
                    "isActive" -> {
                        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        val json = prefs.getString(ACTIVE_GEOFENCES_KEY, null)
                        val active = !json.isNullOrEmpty() && json != "[]"
                        result.success(active)
                    }
                    "setUserInfo" -> {
                        val args = call.arguments as? Map<String, Any>
                        val companyId = args?.get("companyId") as? String
                        val userId = args?.get("userId") as? String
                        if (companyId == null || userId == null) {
                            result.error("INVALID_ARGS", "Expected companyId and userId", null)
                            return@setMethodCallHandler
                        }
                        setUserInfo(context, companyId, userId)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    GeofenceBroadcastReceiver.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    GeofenceBroadcastReceiver.eventSink = null
                }
            })
    }

    private fun registerGeofences(locations: List<Map<String, Any>>, result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Context is null", null)
            return
        }

        val availability = GoogleApiAvailability.getInstance()
        if (availability.isGooglePlayServicesAvailable(ctx) != ConnectionResult.SUCCESS) {
            Log.w(TAG, "Google Play Services not available")
            result.success(false)
            return
        }

        val geofencingClient = LocationServices.getGeofencingClient(ctx)
        val pendingIntent = getGeofencePendingIntent(ctx)

        // 既存をクリアしてから登録
        geofencingClient.removeGeofences(pendingIntent).addOnCompleteListener {
            val geofenceList = locations.mapNotNull { loc ->
                val id = loc["id"] as? String ?: return@mapNotNull null
                val lat = (loc["lat"] as? Number)?.toDouble() ?: return@mapNotNull null
                val lng = (loc["lng"] as? Number)?.toDouble() ?: return@mapNotNull null
                val radius = (loc["radius"] as? Number)?.toFloat() ?: return@mapNotNull null

                Geofence.Builder()
                    .setRequestId(id)
                    .setCircularRegion(lat, lng, radius)
                    .setExpirationDuration(Geofence.NEVER_EXPIRE)
                    .setTransitionTypes(
                        Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT
                    )
                    .build()
            }

            if (geofenceList.isEmpty()) {
                clearPersistedGeofences(ctx)
                result.success(true)
                return@addOnCompleteListener
            }

            val request = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofences(geofenceList)
                .build()

            try {
                geofencingClient.addGeofences(request, pendingIntent)
                    .addOnSuccessListener {
                        Log.i(TAG, "Registered ${geofenceList.size} geofences (ENTER+EXIT)")
                        persistGeofences(ctx, locations)
                        result.success(true)
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "Failed to add geofences", e)
                        result.success(false)
                    }
            } catch (e: SecurityException) {
                Log.e(TAG, "Missing location permission", e)
                result.success(false)
            }
        }
    }

    private fun unregisterAll(result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.success(null)
            return
        }

        val geofencingClient = LocationServices.getGeofencingClient(ctx)
        val pendingIntent = getGeofencePendingIntent(ctx)
        geofencingClient.removeGeofences(pendingIntent).addOnCompleteListener {
            clearPersistedGeofences(ctx)
            Log.i(TAG, "Unregistered all geofences")
            result.success(null)
        }
    }

    companion object {
        private const val TAG = "KintaiGeofenceService"
        const val PREFS_NAME = "kintai_geofence_prefs"
        const val ACTIVE_GEOFENCES_KEY = "active_geofences_json"
        const val USER_INFO_KEY = "geofence_user_info"

        fun getGeofencePendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
            return PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
        }

        fun persistGeofences(context: Context, locations: List<Map<String, Any>>) {
            val jsonArray = JSONArray()
            for (loc in locations) {
                val obj = JSONObject()
                obj.put("id", loc["id"])
                obj.put("lat", loc["lat"])
                obj.put("lng", loc["lng"])
                obj.put("radius", loc["radius"])
                obj.put("name", loc["name"] ?: "")
                jsonArray.put(obj)
            }
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(ACTIVE_GEOFENCES_KEY, jsonArray.toString())
                .apply()
        }

        fun clearPersistedGeofences(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(ACTIVE_GEOFENCES_KEY)
                .apply()
        }

        fun setUserInfo(context: Context, companyId: String, userId: String) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString("companyId", companyId)
                .putString("userId", userId)
                .apply()
            Log.i(TAG, "User info set: companyId=$companyId, userId=$userId")
        }

        fun getUserInfo(context: Context): Pair<String, String>? {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val companyId = prefs.getString("companyId", null) ?: return null
            val userId = prefs.getString("userId", null) ?: return null
            return Pair(companyId, userId)
        }
    }
}
