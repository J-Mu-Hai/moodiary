import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moodiary/services/agent_brain/agent_task.dart';
import 'package:refreshed/refreshed.dart';

/// App 内全屏阻断页 — 智能体「强制锁屏」能力的第一版实现。
///
/// 无系统悬浮窗权限，只能覆盖本 App 内容：全屏倒计时 + 原因说明，
/// 用户只能等倒计时结束，或点「提前结束」主动退出（退出时向任务写反馈）。
///
/// 参数（Get.arguments）：taskId / title / reason / durationMinutes。
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
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
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
    super.dispose();
  }

  /// 向任务写回反馈并置完成态（幂等，只写一次）。
  Future<void> _writeFeedback(String feedback) async {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    if (_taskId != null) {
      try {
        final task = await AgentTaskStore.byId(_taskId!);
        if (task != null) {
          task.status = 'done';
          task.feedback = [...task.feedback, '[阻断页] $feedback'];
          await AgentTaskStore.update(task);
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme;
    final done = _finished || _remainingSeconds <= 0;

    return PopScope(
      canPop: true,
      // 任何方式退出（系统返回 / 提前结束按钮 / 倒计时结束）都写反馈；
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
                    if (!done)
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
