package com.terraton.terraton_fan_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder

class TerraBgService : Service() {

    companion object {
        const val CHANNEL_ID  = "terraton_ble"
        const val NOTIF_ID    = 7001
        const val EXTRA_LABEL = "label"
        const val ACTION_STOP = "com.terraton.STOP"
    }

    private val nm by lazy {
        getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Fan Status",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val label = intent?.getStringExtra(EXTRA_LABEL) ?: "Fan running"
        startForeground(NOTIF_ID, buildNotif(label))
        return START_NOT_STICKY
    }

    private fun buildNotif(label: String): Notification {
        val tapIntent = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Terraton Fan")
            .setContentText(label)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .apply { tapIntent?.let { setContentIntent(it) } }
            .build()
    }
}
