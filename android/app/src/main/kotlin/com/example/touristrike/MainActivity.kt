package com.example.touristrike

import android.content.pm.PackageManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            listOf(
                Triple("tour_updates", "Tour Updates", NotificationManager.IMPORTANCE_DEFAULT),
                Triple("payment_updates", "Payment Updates", NotificationManager.IMPORTANCE_DEFAULT),
                Triple("emergency_alerts", "Emergency Alerts", NotificationManager.IMPORTANCE_HIGH),
            ).forEach { (id, name, importance) ->
                manager.createNotificationChannel(NotificationChannel(id, name, importance).apply {
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                })
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "touristrike/config",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getGoogleMapsApiKey") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val applicationInfo = packageManager.getApplicationInfo(
                packageName,
                PackageManager.GET_META_DATA,
            )
            result.success(
                applicationInfo.metaData
                    ?.getString("com.google.android.geo.API_KEY")
                    .orEmpty(),
            )
        }
    }
}
