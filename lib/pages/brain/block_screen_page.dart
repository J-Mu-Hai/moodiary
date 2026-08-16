import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moodiary/services/agent_brain/agent_task.dart';
import 'package:moodiary/services/agent_brain/brain_reflect.dart';
import 'package:moodiary/utils/agent_channel.dart';
import 'package:refreshed/refreshed.dart';

/// 阻断页 — 智能体「强制锁屏」能力。
///
/// 两级锁屏：
/// - **overlay=true（系统级，强制锁屏首选）**：通过 `moodiary/agent` 原生通道
///   显示 TYPE_APPLICATION_OVERLAY 全屏悬浮窗，覆盖**所有应用**与 Home/切换
///   应用手势区，Home 键手势被拦截，只能等倒计时结束（原生 overlay 由本页
///   Dart 倒计时驱动，每秒 updateForceLock 刷新显示）。
/// - **overlay=false（App 内，回退）**：无悬浮窗权限时只能覆盖本 App 内容；
///   仍是强制锁屏（无「提前结束」、拦截返回、保持亮屏），用户可经 Home 离开。
///
/// force=true（默认）为强制锁屏；force=false 保留「提前结束」按钮，手动测试用。
/// 倒计时归零或用户离开 → _writeFeedback 写回反馈 + 移除悬浮窗（幂等）。
///
/// 参数（Get.arguments）：taskId / title / reason / durationMinutes / force / overlay。
class BlockScreenPage extends StatefulWidget {
  const BlockScreenPage({super.key});

  @override
  State<BlockScreenPage> createState() => _BlockScreenPageState();
}

class _BlockScreenPageState extends State<BlockScreenPage> {
  int _remainingSeconds = 15 * 60;
  String? _taskId;
  String _title = '强制锁屏';
  String _reason = '';
  Timer? _timer;
  bool _finished = false; // 反馈已写回（防重复）
  bool _force = true; // 强制模式：无提前结束、拦截返回、保持亮屏
  bool _overlay = false; // 系统级悬浮窗（覆盖所有应用、拦截 Home 手势）

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is Map) {
      _taskId = args['taskId']?.toString();
      _title = args['title']?.toString() ?? _title;
      _reason = args['reason']?.toString() ?? '';
      final minutes = (args['durationMinutes'] as num?)?.toInt() ?? 15;
      _remainingSeconds = minutes * 60;
      _force = args['force'] as bool? ?? true;
      _overlay = args['overlay'] as bool? ?? false;
    }
    // 强制锁屏期间保持屏幕常亮，倒计时不应被熄屏打断
    unawaited(AgentChannel.setKeepScreenOn(true));
    // 系统级悬浮窗锁屏：原生全屏覆盖所有应用，本页 Dart 倒计时驱动其显示
    if (_force && _overlay) {
      unawaited(AgentChannel.showForceLock(
        title: _title,
        reason: _reason,
        durationMinutes: _remainingSeconds ~/ 60,
      ));
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
        // 同步刷新系统悬浮窗倒计时（原生 overlay 无独立逻辑，纯显示）
        if (_overlay) unawaited(AgentChannel.updateForceLock(_remainingSeconds));
      } else if (!_finished) {
        // 倒计时归零：写反馈 + 展示完成态片刻后自动退出
        _writeFeedback('阻断时间到，已结束');
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted) Get.back();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // 复位屏幕常亮（页面退出后恢复系统默认）
    unawaited(AgentChannel.setKeepScreenOn(false));
    // 兜底移除系统悬浮窗（幂等；倒计时结束/提前退出时 _writeFeedback 已移除）
    if (_overlay) unawaited(AgentChannel.hideForceLock());
    super.dispose();
  }

  /// 向任务写回反馈并置完成态（幂等，只写一次）。
  Future<void> _writeFeedback(String feedback) async {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    // 锁屏结束：立即移除系统级悬浮窗（倒计时归零 / 用户退出都走这里）
    if (_overlay) unawaited(AgentChannel.hideForceLock());
    if (_taskId != null) {
      try {
        final task = await AgentTaskStore.byId(_taskId!);
        if (task != null) {
          task.status = 'done';
          task.feedback = [...task.feedback, '[阻断页] $feedback'];
          await AgentTaskStore.update(task);
          // 反思学习回路：用户是否配合锁屏（等到结束 / 中途离开）值得沉淀
          unawaited(BrainReflect.maybeReflect(task));
        }
      } catch (e) {
        print('[BlockScreen] 反馈写回失败: $e');
      }
    }
  }

  String get _mmss {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 阻断是否已结束（倒计时归零或已写回反馈）。
  bool get _done => _finished || _remainingSeconds <= 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme;
    final done = _done;

    return PopScope(
      // 强制模式下系统返回被拦截（canPop=false）；倒计时结束 _finished 置位
      // → canPop 变 true → 自动退出路径正常 pop。
      canPop: _done || !_force,
      // 任何退出方式（系统返回 / 提前结束按钮 / 倒计时结束）都写反馈；
      // 幂等由 _writeFeedback 的 _finished 保证，不会重复弹路由。
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _writeFeedback('用户提前结束');
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      done ? Icons.check_circle_outline : Icons.lock_clock,
                      size: 72,
                      color: done ? colorScheme.primary : colorScheme.error,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      done ? '阻断完成' : _title,
                      textAlign: TextAlign.center,
                      style: textStyle.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (_reason.isNotEmpty)
                      Text(
                        _reason,
                        textAlign: TextAlign.center,
                        style: textStyle.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 32),
                    Text(
                      done ? '现在可以继续使用' : _mmss,
                      style: (done
                              ? textStyle.titleLarge
                              : textStyle.displayMedium)
                          ?.copyWith(
                        color: done
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (!done) ...[
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _remainingSeconds / (_remainingSeconds + 1),
                          minHeight: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor:
                              AlwaysStoppedAnimation(colorScheme.error),
                        ),
                      ),
                    ],
                    const SizedBox(height: 48),
                    // force=false 时保留「提前结束」按钮（手动测试用）；
                    // 强制锁屏无此按钮，唯一出口是倒计时结束。
                    if (!done && !_force)
                      OutlinedButton(
                        onPressed: () => Get.back(),
                        child: const Text('提前结束'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
