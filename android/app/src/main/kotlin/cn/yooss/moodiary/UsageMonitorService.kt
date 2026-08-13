package cn.yooss.moodiary

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * 「持续监督」前台服务：只负责两件事——
 *
 * 1. 以前台服务身份把应用进程保活（后台时 Flutter 引擎与主 isolate 持续存活，
 *    Dart 侧每分钟 Timer 轮询 `queryEvents` 写会话）；
 * 2. 展示一条常驻通知，让用户清楚"监督中"这个状态。
 *
 * 采用 [Service] 而非 `foregroundServiceType="dataSync"` 的另一个原因：
 * Android 15（targetSdk 35）对 `dataSync` 型前台服务有每 24 小时 6 小时上限，
 * 监督需要持续运行，因此声明为 `specialUse` 型（个人自用、非 Play 分发）。
 *
 * 已知取舍：用户从最近任务里划掉应用时，Android 12+ 禁止后台再拉起前台服务，
 * 监督会暂停；下次打开应用时 onResume 拉取会补齐这段空档的会话数据。
 */
class UsageMonitorService : Service() {

    companion object {
        const val CHANNEL_ID = "usage_monitor"
        const val NOTIFICATION_ID = 0x5eed

        /** 是否正在运行（Dart 侧经 MethodChannel 读取，用于开关状态） */
        @Volatile
        var running: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, UsageMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, UsageMonitorService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        // START_STICKY：进程被系统回收后尝试重建服务，尽量维持监督
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        createChannel()
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Moodiary 正在监督手机使用")
            .setContentText("持续统计你在哪些时间段用了哪些应用")
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "使用监督",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
    }
}
