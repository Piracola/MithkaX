package x.empty.mithka

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the Flutter/TDLib process alive for the in-app push mode.
 *
 * A foreground service is the Android-sanctioned way to hold a socket while
 * the app is backgrounded; exteraless uses the same mechanism. When the
 * unified-push distributor is missing or FCM is unavailable, this service is
 * also the fallback so a self-hosted setup still receives messages.
 */
class PushKeepAliveService : Service() {
    override fun onCreate() {
        super.onCreate()
        createChannels()
        goForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        goForeground()
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        scheduleRestart()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopForegroundCompat()
        if (PushServiceStore.keepAliveEnabled(this)) {
            scheduleRestart()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun goForeground() {
        val resident = PushServiceStore.resident(this)
        val channelId = if (resident) CHANNEL_VISIBLE else CHANNEL_QUIET
        val notification = buildNotification(channelId, resident)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: Throwable) {
            android.util.Log.w(TAG, "Failed to enter foreground", error)
        }
    }

    private fun buildNotification(channelId: String, resident: Boolean): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_stat_push)
            .setContentTitle(getString(R.string.push_keepalive_title))
            .setContentText(getString(R.string.push_keepalive_text))
            .setShowWhen(false)
            .setOngoing(true)
            .setSilent(!resident)
            .setContentIntent(pendingIntent)
            .setPriority(
                if (resident) NotificationCompat.PRIORITY_LOW
                else NotificationCompat.PRIORITY_MIN,
            )
            .build()
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val visible = NotificationChannel(
            CHANNEL_VISIBLE,
            getString(R.string.push_keepalive_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            setShowBadge(false)
            setSound(null, null)
        }
        val quiet = NotificationChannel(
            CHANNEL_QUIET,
            getString(R.string.push_keepalive_channel_quiet),
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            setShowBadge(false)
            setSound(null, null)
        }
        manager.createNotificationChannels(listOf(visible, quiet))
    }

    private fun scheduleRestart() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, PushKeepAliveService::class.java)
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            PendingIntent.getService(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        try {
            alarmManager.cancel(pendingIntent)
            alarmManager.setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + 10 * 60 * 1000L,
                10 * 60 * 1000L,
                pendingIntent,
            )
        } catch (error: Throwable) {
            android.util.Log.w(TAG, "Failed to schedule keep-alive restart", error)
        }
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {
        }
    }

    companion object {
        private const val TAG = "MithkaPush"
        private const val CHANNEL_VISIBLE = "mithka_push_keepalive"
        private const val CHANNEL_QUIET = "mithka_push_keepalive_quiet"
        private const val NOTIFICATION_ID = 0x4D58

        fun start(context: Context) {
            try {
                ContextCompat.startForegroundService(
                    context.applicationContext,
                    Intent(context.applicationContext, PushKeepAliveService::class.java),
                )
            } catch (error: Throwable) {
                android.util.Log.w(TAG, "Failed to start keep-alive service", error)
            }
        }

        fun stop(context: Context) {
            try {
                context.applicationContext.stopService(
                    Intent(context.applicationContext, PushKeepAliveService::class.java),
                )
            } catch (_: Throwable) {
            }
        }
    }
}
