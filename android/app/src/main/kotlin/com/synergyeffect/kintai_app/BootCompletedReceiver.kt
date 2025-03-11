package com.synergyeffect.kintai_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONArray

/// デバイス再起動後にジオフェンスを再登録する BroadcastReceiver
/// Android ではデバイス再起動でジオフェンスがクリアされるため、
/// SharedPreferences から再登録する。
class BootCompletedReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootCompletedReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        Log.i(TAG, "Boot completed or package replaced — re-registering geofences")
        reRegisterGeofences(context)
    }

    private fun reRegisterGeofences(context: Context) {
        val availability = GoogleApiAvailability.getInstance()
        if (availability.isGooglePlayServicesAvailable(context) != ConnectionResult.SUCCESS) {
            Log.w(TAG, "Google Play Services not available, skipping geofence re-registration")
            return
        }

        val prefs = context.getSharedPreferences(
            KintaiGeofenceService.PREFS_NAME, Context.MODE_PRIVATE
        )
        val json = prefs.getString(KintaiGeofenceService.ACTIVE_GEOFENCES_KEY, null)

        if (json.isNullOrEmpty()) {
            Log.i(TAG, "No persisted geofences to re-register")
            return
        }

        val geofenceList = mutableListOf<Geofence>()

        try {
            val jsonArray = JSONArray(json)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                geofenceList.add(
                    Geofence.Builder()
                        .setRequestId(obj.getString("id"))
                        .setCircularRegion(
                            obj.getDouble("lat"),
                            obj.getDouble("lng"),
                            obj.getDouble("radius").toFloat()
                        )
                        .setExpirationDuration(Geofence.NEVER_EXPIRE)
                        .setTransitionTypes(
                            Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT
                        )
                        .build()
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing persisted geofences", e)
            return
        }

        if (geofenceList.isEmpty()) {
            Log.i(TAG, "No geofences to re-register")
            return
        }

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofences(geofenceList)
            .build()

        val pendingIntent = KintaiGeofenceService.getGeofencePendingIntent(context)
        val geofencingClient = LocationServices.getGeofencingClient(context)

        try {
            geofencingClient.addGeofences(request, pendingIntent)
                .addOnSuccessListener {
                    Log.i(TAG, "Re-registered ${geofenceList.size} geofences after boot")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Failed to re-register geofences after boot", e)
                }
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing location permission for boot geofence re-registration", e)
        }
    }
}
