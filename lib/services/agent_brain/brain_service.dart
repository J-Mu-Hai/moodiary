import 'dart:async';

import 'agent_executor.dart';
import 'agent_monitor.dart';
import 'agent_task.dart';

/// 大脑服务 — 智能体的「心跳」：每分钟轮询到点任务分发执行 + 检查代码监督信号。
///
/// 单例，在 main.dart 与 AiTriggerService 并列挂载。App 打开期间轮询可靠；
/// 后台被系统杀掉后无法唤醒（Android 12+ 限制，与现有 UsageMonitorService 相同）。
class BrainService {
  static final BrainService _instance = BrainService._();
  factory BrainService() => _instance;
  BrainService._();

  final BrainMonitor _monitor = BrainMonitor();
  Timer? _timer;
  bool _initialized = false;
  bool _busy = false;

  Future<void> init() async {
    if (_initialized) return;
    _startTimer();
    _initialized = true;
    print('[BrainService] 已初始化（分钟级轮询）');
    // 启动后立即检查一次（画像未初始化等信号不必等第一个 tick）
    unawaited(_tick());
  }

  /// 用户写完日记时调用（编辑页保存成功处接线）。
  Future<void> notifyDiaryWritten() async {
    await BrainMonitor.recordDiaryWritten();
    print('[BrainService] 日记写入已记录');
  }

  /// 立即执行一次到点任务分发（实验室手动触发用）。
  Future<void> runDueNow() async {
    await _dispatchDueTasks();
  }

  /// 立即检查一次全部信号（实验室手动触发用，绕过冷却可传 force 由大脑处理）。
  Future<void> checkSignalsNow() async {
    await _monitor.checkSignals();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      await _dispatchDueTasks();
      await _watchdogRunning();
      await _monitor.checkSignals();
    } catch (e) {
      print('[BrainService] tick error: $e');
    } finally {
      _busy = false;
    }
  }

  /// 找出到点任务并分发执行。
  Future<void> _dispatchDueTasks() async {
    final pending = await AgentTaskStore.query(status: 'pending');
    final now = DateTime.now();
    final due = pending.where((t) {
      if (t.kind == 'immediate') return true;
      if (t.kind == 'scheduled') {
        return t.scheduledAt != null && !t.scheduledAt!.isAfter(now);
      }
      return false; // longterm 不自动执行，等大脑/用户处理
    }).toList();
    if (due.isEmpty) return;

    for (final task in due) {
      task.status = 'running';
      await AgentTaskStore.update(task);
      try {
        await AgentExecutor.execute(task);
        // 执行器已写终态。若仍为 running 且非阻断页，兜底置 done。
        final after = await AgentTaskStore.byId(task.id);
        if (after != null &&
            after.status == 'running' &&
            after.action != 'block_screen') {
          after.status = 'done';
          after.feedback = [...after.feedback, '[执行] 完成'];
          await AgentTaskStore.update(after);
        }
      } catch (e) {
        // 执行失败：重排 5 分钟后重试，超过 3 次取消
        final retries =
            task.feedback.where((f) => f.contains('执行失败')).length;
        if (retries >= 2) {
          task.status = 'cancelled';
          task.feedback = [...task.feedback, '[执行] 多次失败，已取消'];
          await AgentTaskStore.update(task);
        } else {
          task.status = 'pending';
          task.scheduledAt = DateTime.now().add(const Duration(minutes: 5));
          task.feedback = [
            ...task.feedback,
            '[执行] 执行失败，5 分钟后重试: $e',
          ];
          await AgentTaskStore.update(task);
        }
      }
    }
  }

  /// 看门狗：running 任务超过 24h 强制完成（防阻断页异常未写回导致卡死）。
  Future<void> _watchdogRunning() async {
    final running = await AgentTaskStore.query(status: 'running');
    final now = DateTime.now();
    for (final t in running) {
      if (now.difference(t.updatedAt).inHours >= 24) {
        t.status = 'done';
        t.feedback = [...t.feedback, '[执行] 超时兜底完成'];
        await AgentTaskStore.update(t);
      }
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
