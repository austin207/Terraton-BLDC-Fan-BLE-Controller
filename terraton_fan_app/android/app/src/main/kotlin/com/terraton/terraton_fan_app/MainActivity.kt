package com.terraton.terraton_fan_app

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.terraton/bg_service")
            .setMethodCallHandler { call, result ->
                val label = call.argument<String>("label") ?: "Fan running"
                when (call.method) {
                    "start", "update" -> { startBg(label); result.success(null) }
                    "stop" -> {
                        startService(Intent(this, TerraBgService::class.java).apply {
                            action = TerraBgService.ACTION_STOP
                        })
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startBg(label: String) {
        val intent = Intent(this, TerraBgService::class.java).apply {
            putExtra(TerraBgService.EXTRA_LABEL, label)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
