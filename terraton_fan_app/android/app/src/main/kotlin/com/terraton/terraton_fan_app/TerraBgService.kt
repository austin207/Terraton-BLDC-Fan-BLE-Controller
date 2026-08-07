package com.terraton.terraton_fan_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class TerraBgService : Service() {

    companion object {
        const val CHANNEL_ID   = "terraton_ble"
        const val NOTIF_ID     = 7001
        const val EXTRA_LABEL  = "label"
        // Epoch millis at which an armed sleep timer is expected to fire.
        // 0 means "no timer" and keeps the plain notification behaviour.
        const val EXTRA_END_AT = "endAt"
        const val ACTION_STOP  = "com.terraton.STOP"
    }

    private val nm by lazy {
        getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    }

    private val handler = Handler(Looper.getMainLooper())
    private var expiryWatch: Runnable? = null

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
            cancelExpiryWatch()
            stopForeground(STOP_FOREGROUND_REMOVE)
            // Also clears a notification left by the nm.notify fallback below,
            // which stopForeground would not touch.
            nm.cancel(NOTIF_ID)
            stopSelf()
            return START_NOT_STICKY
        }
        val label = intent?.getStringExtra(EXTRA_LABEL) ?: "Fan running"
        val endAt = intent?.getLongExtra(EXTRA_END_AT, 0L) ?: 0L
        val notif = buildNotif(label, endAt)
        // Android 12+ throws ForegroundServiceStartNotAllowedException if the
        // service is not already foreground and the app is in the background.
        // The app only ever starts this while visible, so that should not
        // happen — but a crash is a far worse outcome than a countdown shown as
        // an ordinary notification, so fall back rather than take the process
        // down.
        try {
            startForeground(NOTIF_ID, notif)
        } catch (e: Exception) {
            nm.notify(NOTIF_ID, notif)
        }
        scheduleExpiryWatch(endAt)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        cancelExpiryWatch()
        super.onDestroy()
    }

    private fun buildNotif(label: String, endAt: Long): Notification {
        val tapIntent = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val b = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Terraton Fan")
            .setContentText(label)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
        tapIntent?.let { b.setContentIntent(it) }
        // The sleep-timer countdown is rendered and ticked by the system from
        // this timestamp. Nothing on the Dart side has to stay awake to keep it
        // moving, so it survives backgrounding, Doze and engine throttling —
        // which is the whole point, since the app drops the BLE link on pause.
        // setChronometerCountDown is API 24+; on 23 the static label stands in.
        if (endAt > 0L && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            b.setWhen(endAt)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
        }
        return b.build()
    }

    // Without this the chronometer would sit at 0:00 once the timer elapses.
    // The fan switches itself off at expiry and the app re-confirms the real
    // state when it next resumes, so a late fire here costs nothing.
    private fun scheduleExpiryWatch(endAt: Long) {
        cancelExpiryWatch()
        if (endAt <= 0L) return
        val delay = endAt - System.currentTimeMillis()
        if (delay <= 0L) return
        val r = Runnable { nm.notify(NOTIF_ID, buildNotif("Sleep timer finished", 0L)) }
        expiryWatch = r
        handler.postDelayed(r, delay)
    }

    private fun cancelExpiryWatch() {
        expiryWatch?.let { handler.removeCallbacks(it) }
        expiryWatch = null
    }
}
