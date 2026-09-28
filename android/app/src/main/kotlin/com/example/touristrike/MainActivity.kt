package com.example.touristrike

import android.content.pm.PackageManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import java.security.MessageDigest
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
            if (call.method == "getGooglePlacesDiagnosticContext") {
                val applicationInfo = packageManager.getApplicationInfo(
                    packageName, PackageManager.GET_META_DATA,
                )
                val key = applicationInfo.metaData
                    ?.getString("com.google.android.geo.API_KEY").orEmpty().trim()
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                        PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES,
                )
                val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                    packageInfo.signingInfo?.apkContentsSigners else packageInfo.signatures
                fun digest(algorithm: String, bytes: ByteArray): String =
                    MessageDigest.getInstance(algorithm).digest(bytes)
                        .joinToString("") { "%02x".format(it.toInt() and 0xff) }
                result.success(mapOf(
                    "package_name" to packageName,
                    "native_key_sha256" to if (key.isEmpty()) "" else digest("SHA-256", key.toByteArray()),
                    "signing_sha1" to signatures?.firstOrNull()?.let { digest("SHA-1", it.toByteArray()) },
                    "signing_sha256" to signatures?.firstOrNull()?.let { digest("SHA-256", it.toByteArray()) },
                ))
                return@setMethodCallHandler
            }
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
