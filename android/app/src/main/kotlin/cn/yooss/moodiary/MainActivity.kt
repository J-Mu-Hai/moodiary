package cn.yooss.moodiary

import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings
import com.github.gzuliyujiang.oaid.DeviceID
import com.github.gzuliyujiang.oaid.IGetter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale


class MainActivity : FlutterFragmentActivity() {

    private companion object {
        const val USAGE_CHANNEL = "moodiary/usage"
    }

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
                else -> result.notImplemented()
            }
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