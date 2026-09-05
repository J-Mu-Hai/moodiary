package cn.yooss.moodiary

import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.github.gzuliyujiang.oaid.DeviceID
import com.github.gzuliyujiang.oaid.IGetter
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale


/**
 * 主界面 + 智能体原生能力宿主。
 *
 * 引擎保活：本 Activity 销毁（用户划掉 App）时 Flutter 引擎**不销毁**——Dart
 * 主 isolate 继续存活，BrainService 分钟轮询照常跑（配合 UsageMonitorService
 * 前台服务保活进程），实现「App 不打开也能后台执行任务」。实现要点：
 * - [provideFlutterEngine] 返回进程级缓存引擎（构造器自动注册插件一次）；
 * - [createFlutterFragment] 用 [KeepAliveFragment]（覆写 shouldDestroyEngineWithHost=false）；
 * - 宿主相关 MethodChannel handler 一律经 `applicationContext` + 静态 [currentActivity]
 *   路由，Activity 销毁后系统服务调用照常可用、Activity 专属能力静默降级。
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val USAGE_CHANNEL = "moodiary/usage"
        const val AGENT_CHANNEL = "moodiary/agent"
        const val AGENT_ENGINE_ID = "moodiary_agent_engine"

        /** 当前存活且未销毁的 Activity 实例（onStart 置位 / onDestroy 清空）。
         * 所有需要 Activity 的能力（窗口、跳设置页、回前台）都经它路由，
         * 避免 MethodChannel 闭包捕获已销毁的 Activity。 */
        @Volatile
        var currentActivity: MainActivity? = null
            private set

        /** 进程级单例引擎：只构造一次，Activity 销毁/重建都复用同一引擎（同一 isolate）。 */
        @Synchronized
        fun getOrCreateEngine(context: Context): FlutterEngine {
            FlutterEngineCache.getInstance().get(AGENT_ENGINE_ID)?.let { return it }
            val engine = FlutterEngine(context.applicationContext)
            FlutterEngineCache.getInstance().put(AGENT_ENGINE_ID, engine)
            return engine
        }
    }

    // ---- 系统级强制锁屏悬浮窗状态（TYPE_APPLICATION_OVERLAY） ----
    // 锁屏期间悬浮窗常驻 WindowManager；Dart 侧 BlockScreenPage 驱动倒计时，
    // 每秒 updateForceLock 刷新显示，结束/退出时 hideForceLock 移除。
    private var lockOverlayView: View? = null
    private var lockCountdownView: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 开机自启（AgentBootReceiver fromBoot=true）：拉起引擎后把任务移到后台，
        // 不打扰用户（冷启动画面会短暂闪现，但不会停在桌面）。
        if (intent?.getBooleanExtra("fromBoot", false) == true) {
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    moveTaskToBack(true)
                } catch (_: Exception) {
                }
            }, 1500)
        }
    }

    override fun onStart() {
        super.onStart()
        currentActivity = this
    }

    override fun onDestroy() {
        currentActivity = null
        // Activity 已销毁：悬浮窗随 WindowManager 一并消失，复位字段避免下次复用残留
        lockOverlayView = null
        lockCountdownView = null
        super.onDestroy()
    }

    /** 返回进程级缓存引擎：Activity 重建时复用，Dart isolate 从不停机。 */
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        getOrCreateEngine(context.applicationContext)

    /** 使用 KeepAliveFragment：Activity 销毁时引擎不被 destroy（后台轮询不中断）。 */
    override fun createFlutterFragment(): FlutterFragment {
        val renderMode = getRenderMode()
        val shouldDelay = renderMode == RenderMode.surface
        val backgroundMode = getBackgroundMode()
        val transparencyMode =
            if (backgroundMode == BackgroundMode.opaque) {
                TransparencyMode.opaque
            } else {
                TransparencyMode.transparent
            }
        val builder = FlutterFragment.NewEngineFragmentBuilder(KeepAliveFragment::class.java)
            .dartEntrypoint(getDartEntrypointFunctionName())
            .initialRoute(getInitialRoute())
            .appBundlePath(getAppBundlePath())
            .flutterShellArgs(FlutterShellArgs.fromIntent(intent))
            .handleDeeplinking(shouldHandleDeeplinking())
            .renderMode(renderMode)
            .transparencyMode(transparencyMode)
            .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
            .shouldDelayFirstAndroidViewDraw(shouldDelay)
            .shouldAutomaticallyHandleOnBackPressed(true)
        // 库 URI / 入口参数是 @Nullable（null = 默认根库 / 不传参数）。值为 null 时
        // 直接跳过 builder 调用——builder 字段默认即 null，与引擎 Java 基类把 null
        // 透传进去的语义一致；也绕开 Kotlin 对 @NonNull 参数的严格检查。
        val libraryUri = getDartEntrypointLibraryUri()
        if (libraryUri != null) {
            builder.dartLibraryUri(libraryUri)
        }
        val entrypointArgs = getDartEntrypointArgs()
        if (entrypointArgs != null) {
            builder.dartEntrypointArgs(entrypointArgs)
        }
        return builder.build()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 注意：所有 handler 一律用 applicationContext / currentActivity，**绝不**捕获
        // `this`——Activity 销毁后旧 handler 仍可能短暂被后台调用，捕获 this 会泄漏/
        // 失效；经静态路由则安全。
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
                            Handler(Looper.getMainLooper()).post {
                                result.success(out)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("USAGE_ERROR", e.message, null)
                            }
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
                            Handler(Looper.getMainLooper()).post {
                                result.success(out)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("USAGE_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                "getAppLabel" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    Thread {
                        try {
                            val label = getAppLabel(pkg)
                            Handler(Looper.getMainLooper()).post {
                                result.success(label)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("USAGE_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                "getCurrentForegroundPackage" -> {
                    // 查询当前前台应用包名（智能体实时感知 app_switched 用）。
                    Thread {
                        try {
                            val pkg = getCurrentForegroundPackage()
                            Handler(Looper.getMainLooper()).post {
                                result.success(pkg)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("USAGE_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                "startMonitor" -> {
                    UsageMonitorService.start(applicationContext)
                    result.success(null)
                }
                "stopMonitor" -> {
                    UsageMonitorService.stop(applicationContext)
                    result.success(null)
                }
                "isMonitorRunning" -> {
                    result.success(UsageMonitorService.running)
                }
                else -> result.notImplemented()
            }
        }
        // 智能体工具通道：回前台 / 屏幕常亮 / 悬浮窗锁屏 / 系统通知
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
                "showAgentNotification" -> {
                    val title = call.argument<String>("title") ?: "Moodiary"
                    val text = call.argument<String>("text") ?: ""
                    showAgentNotification(title, text)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** 把 moodiary 自身带回前台（后台定时任务触发时唤起）。Activity 已销毁时静默。 */
    private fun bringToFront() {
        val act = currentActivity ?: return
        try {
            val intent = Intent(act, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_NEW_TASK
                )
            }
            act.startActivity(intent)
        } catch (e: Exception) {
            // Android 12+ 后台限制等场景可能失败，静默
        }
    }

    /** 设置/复位屏幕常亮（强制锁屏期间保持亮屏）。Activity 已销毁时静默。 */
    private fun setKeepScreenOn(keep: Boolean) {
        val act = currentActivity ?: return
        act.runOnUiThread {
            if (keep) {
                act.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                act.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    /** 是否已授予"显示在其他应用上层"（悬浮窗）权限 */
    private fun canDrawOverlays(): Boolean {
        return try {
            Settings.canDrawOverlays(applicationContext)
        } catch (e: Exception) {
            false
        }
    }

    /** 未授权时跳转系统"悬浮窗权限"设置页（一次授权后长期可用）。Activity 已销毁时静默。 */
    private fun requestOverlayPermission() {
        if (canDrawOverlays()) return
        val act = currentActivity ?: return
        try {
            act.startActivity(
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
     * 倒计时显示由 Dart 侧每秒 updateForceLock 驱动。Activity 已销毁时静默。
     */
    private fun showForceLock(call: MethodCall) {
        val act = currentActivity ?: return
        if (!canDrawOverlays()) return
        if (lockOverlayView != null) return // 已在锁屏中，幂等

        val title = call.argument<String>("title") ?: "强制锁屏"
        val reason = call.argument<String>("reason") ?: ""
        val inflater = LayoutInflater.from(act)
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
            act.windowManager.addView(view, params)
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

    /** 移除强制锁屏悬浮窗（幂等）。Activity 销毁时悬浮窗已随 WindowManager 消失。 */
    private fun hideForceLock() {
        val view = lockOverlayView ?: return
        val act = currentActivity
        lockOverlayView = null
        lockCountdownView = null
        if (act == null) return
        try {
            act.windowManager.removeView(view)
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
            val am = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
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
            val appOps = applicationContext.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
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

    /** 跳转到系统"使用情况访问"设置页。Activity 已销毁时静默。 */
    private fun openUsageAccessSettings() {
        val act = currentActivity ?: return
        try {
            act.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        } catch (e: Exception) {
            // 部分定制 ROM 无此设置页，忽略
        }
    }

    /**
     * 查询最近 [days] 天（含今天）每个应用的前台使用时长。
     * 返回 List<Map>: { dayKey: "yyyy/M/d", packageName, appName, totalMs }
     * 过去完整天用 INTERVAL_DAILY，今天用 INTERVAL_BEST（累计中的最佳间隔）。
     */
    private fun getUsage(days: Int): ArrayList<Map<String, Any>> {
        val ctx = applicationContext
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = ctx.packageManager
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
     */
    private fun getEventsSince(since: Long): ArrayList<Map<String, Any>> {
        val ctx = applicationContext
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
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

    /**
     * 查询当前前台应用包名（智能体实时感知 app_switched 用）。
     *
     * 主路径：queryUsageStats(INTERVAL_BEST, now-60s, now) 里 lastTimeUsed 最大、
     * 且落在窗口内的包；过滤掉本 App。兜底：queryEvents 最近一条 ACTIVITY_RESUMED。
     * 返回 null 表示拿不到（未授予使用权限）；返回 "" 表示用户此刻在 moodiary 本身
     * （Dart 视为「在本 App 内」，不算切到别的 App）。
     */
    private fun getCurrentForegroundPackage(): String? {
        val ctx = applicationContext
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val windowStart = now - 60_000
        var best: String? = null
        var bestTime = 0L
        var selfTime = 0L
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, windowStart, now)
        for (s in stats) {
            if (s.packageName == packageName) {
                selfTime = maxOf(selfTime, s.lastTimeUsed)
                continue
            }
            if (s.lastTimeUsed in windowStart..now && s.lastTimeUsed > bestTime) {
                bestTime = s.lastTimeUsed
                best = s.packageName
            }
        }
        if (selfTime > bestTime) return "" // 本 App 最近被使用 → 用户正在 moodiary 内
        if (best != null) return best
        // 兜底：事件流里最近一条 ACTIVITY_RESUMED
        val events = usm.queryEvents(windowStart, now)
        val e = UsageEvents.Event()
        var lastResumed: String? = null
        var lastResumedTime = 0L
        var selfResumedTime = 0L
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType != UsageEvents.Event.ACTIVITY_RESUMED) continue
            if (e.packageName == packageName) {
                selfResumedTime = e.timeStamp
            } else {
                lastResumed = e.packageName
                lastResumedTime = e.timeStamp
            }
        }
        if (selfResumedTime >= lastResumedTime) return ""
        return lastResumed
    }

    /** 解析单个应用名；解析失败兜底为包名。 */
    private fun getAppLabel(pkg: String): String {
        return try {
            applicationContext.packageManager
                .getApplicationInfo(pkg, 0).loadLabel(applicationContext.packageManager)
                .toString()
        } catch (e: Exception) {
            pkg
        }
    }

    /**
     * 发一条系统通知（智能体后台提醒：App 不在前台时把询问/提醒推给用户）。
     * 用 applicationContext 而非 Activity——Activity 销毁后照常可用。
     * 点击通知 → 打开 MainActivity（带入最近任务栈）。
     */
    private fun showAgentNotification(title: String, text: String) {
        val ctx = applicationContext
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // 智能体提醒通道：IMPORTANCE_HIGH 才有头部弹出
            nm.createNotificationChannel(
                NotificationChannel(
                    "agent_alerts",
                    "智能体提醒",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
            if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return
            val contentIntent = PendingIntent.getActivity(
                ctx,
                0,
                Intent(ctx, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                },
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val notification = NotificationCompat.Builder(ctx, "agent_alerts")
                .setSmallIcon(android.R.drawable.stat_notify_chat)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(contentIntent)
                .build()
            nm.notify(System.currentTimeMillis().toInt(), notification)
        } catch (e: Exception) {
            // 通知失败不打扰后台任务
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

/**
 * Activity 销毁时引擎不随之销毁：Dart 主 isolate 常驻后台（配合前台服务保活），
 * 让 BrainService 分钟轮询/监控在 App 被划掉后仍持续执行。
 */
class KeepAliveFragment : FlutterFragment() {
    override fun shouldDestroyEngineWithHost(): Boolean = false
}

class HandleGetOAID(private var resultCallback: MethodChannel.Result) : IGetter {
    override fun onOAIDGetComplete(result: String) {
        resultCallback.success(result)
    }

    override fun onOAIDGetError(error: Exception?) {
        resultCallback.success(null)
    }
}
