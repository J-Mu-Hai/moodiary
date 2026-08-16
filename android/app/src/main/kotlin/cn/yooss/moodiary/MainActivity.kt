package cn.yooss.moodiary

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioManager
import android.net.Uri
import android.os.Process
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import com.github.gzuliyujiang.oaid.DeviceID
import com.github.gzuliyujiang.oaid.IGetter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale


class MainActivity : FlutterFragmentActivity() {

    private companion object {
        const val USAGE_CHANNEL = "moodiary/usage"
        const val AGENT_CHANNEL = "moodiary/agent"
    }

    // ---- 系统级强制锁屏悬浮窗状态（TYPE_APPLICATION_OVERLAY） ----
    // 锁屏期间悬浮窗常驻 WindowManager；Dart 侧 BlockScreenPage 驱动倒计时，
    // 每秒 updateForceLock 刷新显示，结束/退出时 hideForceLock 移除。
    private var lockOverlayView: View? = null
    private var lockCountdownView: TextView? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "oaid_channel"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getOAID" -> {
                    getOAID(result)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, USAGE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGranted" -> result.success(isUsageAccessGranted())
                "openSettings" -> {
                    openUsageAccessSettings()
                    result.success(null)
                }
                "getUsage" -> {
                    val days = call.argument<Int>("days") ?: 7
                    // queryUsageStats + getApplicationInfo 较慢，必须放后台线程，
                    // 否则会卡死 Android 主线程触发 ANR（页面"点击就卡死"）。
                    // MethodChannel 结果允许从任意线程回传。
                    Thread {
                        try {
                            val out = getUsage(days)
                            runOnUiThread { result.success(out) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("USAGE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "getEventsSince" -> {
                    // 增量拉取使用事件流（时间线/会话的地基）。
                    // 同样放后台线程，避免 queryEvents 阻塞主线程。
                    val since = call.argument<Long>("since") ?: 0L
                    Thread {
                        try {
                            val out = getEventsSince(since)
                            runOnUiThread { result.success(out) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("USAGE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "getAppLabel" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    Thread {
                        try {
                            val label = getAppLabel(pkg)
                            runOnUiThread { result.success(label) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("USAGE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "startMonitor" -> {
                    UsageMonitorService.start(this)
                    result.success(null)
                }
                "stopMonitor" -> {
                    UsageMonitorService.stop(this)
                    result.success(null)
                }
                "isMonitorRunning" -> {
                    result.success(UsageMonitorService.running)
                }
                else -> result.notImplemented()
            }
        }
        // 智能体工具通道：回前台 / 屏幕常亮（配合 agent_executor 的
        // open_diary 进日记、block_screen 强制锁屏使用）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, AGENT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "bringToFront" -> {
                    bringToFront()
                    result.success(null)
                }
                "setKeepScreenOn" -> {
                    val keep = call.argument<Boolean>("keep") ?: false
                    setKeepScreenOn(keep)
                    result.success(null)
                }
                "hasOverlayPermission" -> {
                    result.success(canDrawOverlays())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(canDrawOverlays())
                }
                "showForceLock" -> {
                    showForceLock(call)
                    result.success(null)
                }
                "updateForceLock" -> {
                    val secondsLeft = call.argument<Int>("secondsLeft") ?: 0
                    updateForceLock(secondsLeft)
                    result.success(null)
                }
                "hideForceLock" -> {
                    hideForceLock()
                    result.success(null)
                }
                "hasBluetoothHeadset" -> {
                    result.success(hasBluetoothHeadset())
                }
                else -> result.notImplemented()
            }
        }
    }

    /** 把 moodiary 自身带回前台（后台定时任务触发时唤起） */
    private fun bringToFront() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_NEW_TASK
                )
            }
            startActivity(intent)
        } catch (e: Exception) {
            // Android 12+ 后台限制等场景可能失败，静默
        }
    }

    /** 设置/复位屏幕常亮（强制锁屏期间保持亮屏） */
    private fun setKeepScreenOn(keep: Boolean) {
        runOnUiThread {
            if (keep) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    /** 是否已授予"显示在其他应用上层"（悬浮窗）权限 */
    private fun canDrawOverlays(): Boolean {
        return try {
            Settings.canDrawOverlays(this)
        } catch (e: Exception) {
            false
        }
    }

    /** 未授权时跳转系统"悬浮窗权限"设置页（一次授权后长期可用） */
    private fun requestOverlayPermission() {
        if (canDrawOverlays()) return
        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (e: Exception) {
            // 部分定制 ROM 无此设置页，忽略
        }
    }

    /**
     * 显示系统级强制锁屏悬浮窗：全屏 TYPE_APPLICATION_OVERLAY，覆盖状态栏/
     * 导航栏/Home 手势区，拦截切换应用；沉浸式全屏 + 保持亮屏。
     * 倒计时显示由 Dart 侧每秒 updateForceLock 驱动。
     */
    private fun showForceLock(call: MethodCall) {
        if (!canDrawOverlays()) return
        if (lockOverlayView != null) return // 已在锁屏中，幂等

        val title = call.argument<String>("title") ?: "强制锁屏"
        val reason = call.argument<String>("reason") ?: ""
        val inflater = LayoutInflater.from(this)
        val view = inflater.inflate(R.layout.overlay_force_lock, null)

        view.findViewById<TextView>(R.id.lock_title).text = title
        if (reason.isNotEmpty()) {
            view.findViewById<TextView>(R.id.lock_reason).apply {
                text = reason
                visibility = View.VISIBLE
            }
        }
        lockCountdownView = view.findViewById(R.id.lock_countdown)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER
        try {
            // API 30+ 沉浸式全屏，隐藏状态栏/导航栏（手势区仍在，但被本视图覆盖拦截）
            params.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        } catch (e: Exception) {
            // 老 API 忽略
        }
        try {
            windowManager.addView(view, params)
            lockOverlayView = view
        } catch (e: Exception) {
            lockOverlayView = null
            lockCountdownView = null
        }
    }

    /** 刷新悬浮窗倒计时文本（Dart 侧每秒调用）；未显示时静默 */
    private fun updateForceLock(secondsLeft: Int) {
        val tv = lockCountdownView ?: return
        val mm = secondsLeft / 60
        val ss = secondsLeft % 60
        tv.text = String.format("%02d:%02d", mm, ss)
    }

    /** 移除强制锁屏悬浮窗（幂等） */
    private fun hideForceLock() {
        val view = lockOverlayView ?: return
        lockOverlayView = null
        lockCountdownView = null
        try {
            windowManager.removeView(view)
        } catch (e: Exception) {
            // 视图已不在（进程被杀/权限被撤），忽略
        }
    }

    /**
     * 是否正通过蓝牙耳机（A2DP/SCO）输出音频。
     *
     * 用于智能体「发起会话」决策：耳机在 → 先语音播报开场白（用户能私密听到）；
     * 无耳机 → 直接切到聊天界面（避免公开场合外放尴尬）。
     * 用 AudioManager 的弃用但免权限的 isBluetoothA2dpOn / isBluetoothScoOn，
     * 避免引入 BLUETOOTH_CONNECT 运行时权限。
     */
    private fun hasBluetoothHeadset(): Boolean {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            @Suppress("DEPRECATION")
            val a2dp = am.isBluetoothA2dpOn
            @Suppress("DEPRECATION")
            val sco = am.isBluetoothScoOn
            a2dp || sco
        } catch (e: Exception) {
            false
        }
    }

    /** 是否已授予"使用情况访问"权限 */
    private fun isUsageAccessGranted(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    /** 跳转到系统"使用情况访问"设置页 */
    private fun openUsageAccessSettings() {
        try {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        } catch (e: Exception) {
            // 部分定制 ROM 无此设置页，忽略
        }
    }

    /**
     * 查询最近 [days] 天（含今天）每个应用的前台使用时长。
     * 返回 List<Map>: { dayKey: "yyyy/M/d", packageName, appName, totalMs }
     * 过去完整天用 INTERVAL_DAILY，今天用 INTERVAL_BEST（累计中的最佳间隔）。
     *
     * 注意：本函数在后台线程调用（见 MethodChannel handler），不得直接
     * 触碰 UI 相关的 Activity 方法。
     */
    private fun getUsage(days: Int): ArrayList<Map<String, Any>> {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = packageManager
        val fmt = SimpleDateFormat("yyyy/M/d", Locale.US)
        val now = System.currentTimeMillis()
        val out = ArrayList<Map<String, Any>>()

        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        // 回到 (days-1) 天前的零点
        cal.add(Calendar.DAY_OF_MONTH, -(days - 1))

        for (d in 0 until days) {
            val dayStart = cal.timeInMillis
            cal.add(Calendar.DAY_OF_MONTH, 1)
            val dayEnd = if (d == days - 1) now else cal.timeInMillis

            val interval =
                if (d == days - 1) UsageStatsManager.INTERVAL_BEST
                else UsageStatsManager.INTERVAL_DAILY
            val stats = usm.queryUsageStats(interval, dayStart, dayEnd)
            val dayKey = fmt.format(dayStart)
            // 按包聚合
            val grouped = HashMap<String, Long>()
            for (s: UsageStats in stats) {
                val t = s.totalTimeInForeground
                if (t <= 0) continue
                grouped[s.packageName] = (grouped[s.packageName] ?: 0L) + t
            }
            for ((pkg, totalMs) in grouped) {
                val label = try {
                    pm.getApplicationInfo(pkg, 0).loadLabel(pm).toString()
                } catch (e: Exception) {
                    pkg
                }
                out.add(
                    mapOf(
                        "dayKey" to dayKey,
                        "packageName" to pkg,
                        "appName" to label,
                        "totalMs" to totalMs
                    )
                )
            }
        }
        return out
    }

    /**
     * 增量拉取 [since]（毫秒）之后的使用事件流。
     *
     * 返回 List<Map>: { t: 事件时刻(ms), pkg: 包名, type: UsageEvents 事件类型 }
     * 只保留与"前台使用"相关的事件：进入/退出前台、熄屏、锁屏。
     * 事件本身按时间升序，Dart 侧据此把事件配对成一段段 UsageSession。
     *
     * queryEvents 适合增量拉取（事件只保留最近一段时间），调用方应把返回
     * 的最大事件时刻存下来作为下次的 [since]，避免重复处理。
     */
    private fun getEventsSince(since: Long): ArrayList<Map<String, Any>> {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val out = ArrayList<Map<String, Any>>()
        val now = System.currentTimeMillis()
        val events = usm.queryEvents(since, now)
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.timeStamp <= since) continue
            val type = e.eventType
            when (type) {
                UsageEvents.Event.ACTIVITY_RESUMED,
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.SCREEN_NON_INTERACTIVE,
                UsageEvents.Event.SCREEN_INTERACTIVE,
                UsageEvents.Event.KEYGUARD_SHOWN,
                UsageEvents.Event.KEYGUARD_HIDDEN -> {
                    out.add(
                        mapOf(
                            "t" to e.timeStamp,
                            "pkg" to e.packageName,
                            "type" to type
                        )
                    )
                }
            }
        }
        return out
    }

    /** 解析单个应用名；解析失败兜底为包名。 */
    private fun getAppLabel(pkg: String): String {
        return try {
            packageManager.getApplicationInfo(pkg, 0).loadLabel(packageManager).toString()
        } catch (e: Exception) {
            pkg
        }
    }

    private fun getOAID(resultCallback: MethodChannel.Result) {
        if (DeviceID.supportedOAID(application)) {
            DeviceID.getOAID(application, HandleGetOAID(resultCallback))
        } else {
            resultCallback.success(null)
        }
    }

}

class HandleGetOAID(private var resultCallback: MethodChannel.Result) : IGetter {
    override fun onOAIDGetComplete(result: String) {
        resultCallback.success(result)
    }

    override fun onOAIDGetError(error: Exception?) {
        resultCallback.success(null)
    }
}