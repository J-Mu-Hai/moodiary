package cn.yooss.moodiary

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机自启：设备重启后拉起主界面（隐藏），让引擎 + 前台服务恢复，
 * 智能体后台守护（实时监控 + 到点提醒）不因重启中断。
 *
 * BOOT_COMPLETED 广播属于 Android 12+ 后台启动限制的豁免清单，可安全 startActivity。
 * MainActivity 收到 fromBoot=true 会在首帧后 moveTaskToBack 隐藏，不打扰用户。
 */
class AgentBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        try {
            val launch = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("fromBoot", true)
            }
            context.startActivity(launch)
        } catch (e: Exception) {
            // 极少数 ROM 限制开机启动，静默（用户下次打开 App 时守护恢复）
        }
    }
}
