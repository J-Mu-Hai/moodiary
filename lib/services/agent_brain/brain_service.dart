import 'dart:async';

import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/utils/notice_util.dart';

import 'agent_brain.dart';
import 'agent_executor.dart';
import 'agent_monitor.dart';
import 'agent_task.dart';
import 'brain_reflect.dart';

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
  bool _dispatching = false; // 派发串行锁：防多信号并发 runDueNow 重复派发

  Future<void> init() async {
    if (_initialized) return;
    _startTimer();
    _initialized = true;
    print('[BrainService] 已初始化（分钟级轮询）');
    // 启动后立即检查一次（画像未初始化等信号不必等第一个 tick）
    unawaited(_tick());
  }

  /// 用户写完日记时调用（编辑页保存成功处接线）。
  ///
  /// 事件驱动：日记刚写完立即送入大脑（diary_written 信号），不等 30 分钟
  /// 的 diary_stable 稳定信号，让「日记变动」真正成为大脑的实时输入。
  /// [title]/[snippet] 用于把日记信息带进决策上下文。
  Future<void> notifyDiaryWritten({String? title, String? snippet}) async {
    await BrainMonitor.recordDiaryWritten();
    final t = title?.trim();
    final snip = snippet?.trim();
    final summary = snip == null || snip.isEmpty
        ? '用户刚写完一篇日记${t != null && t.isNotEmpty ? '《$t》' : ''}。'
            '请看一眼今天的记录，判断是否需要关怀，或为今天做点安排。'
        : '用户刚写完一篇日记${t != null && t.isNotEmpty ? '《$t》' : ''}，内容开头：$snip';
    await AgentBrain.handleSignal(BrainSignal(
      type: 'diary_written',
      summary: summary,
      data: {'title': t, 'snippet': snip},
    ));
    print('[BrainService] 日记写入已记录并触发 diary_written 信号');
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
      // 每日例行（确定性，不经大脑决策）：0 点后创建夜间归位任务；
      // 23:30 后创建当日行为建模任务（晚间归位复盘完再重算行为模型）
      await _checkNightlyReview();
      await _checkBehaviorModel();
      await _dispatchDueTasks();
      await _watchdogRunning();
      await _watchdogWaiting();
      await _monitor.checkSignals();
    } catch (e) {
      print('[BrainService] tick error: $e');
    } finally {
      _busy = false;
    }
  }

  /// 每日例行「晚间复盘」的确定性调度（不进大脑决策，可靠不靠 AI 自觉）。
  ///
  /// 每天 23:00 之后第一次 tick（App 存活时）创建一次 nightly_review 任务，
  /// scheduledAt=now 到点立即派发，梳理「今天」并留下复盘；当天没收集到的
  /// 计划空缺也并入复盘（统一作息管理的兜底）。用 PrefUtil 记录跨天防重复；
  /// 当天已存在 pending/running 的复盘任务（如派发失败待重试）也视为已调度。
  Future<void> _checkNightlyReview() async {
    try {
      final now = DateTime.now();
      // 23:00 后进入晚间复盘窗口
      if (now.hour < 23) return;
      final today = '${now.year}-${now.month}-${now.day}';
      final last = PrefUtil.getValue<String>('nightlyReviewLastAt') ?? '';
      if (last == today) return;

      final existing = await AgentTaskStore.query(action: 'nightly_review');
      final todayCreated = existing.any((t) {
        final c = t.createdAt;
        return '${c.year}-${c.month}-${c.day}' == today &&
            (t.status == 'pending' || t.status == 'running');
      });
      if (todayCreated) {
        await PrefUtil.setValue<String>('nightlyReviewLastAt', today);
        return;
      }

      await AgentTaskStore.add(AgentTask(
        title: '晚间复盘：梳理今天',
        kind: 'scheduled',
        action: 'nightly_review',
        params: {'basicTask': true}, // 统一作息的基础任务之一（实验室按此分组）
        scheduledAt: now,
        priority: 2,
      ));
      await PrefUtil.setValue<String>('nightlyReviewLastAt', today);
      print('[BrainService] 已创建晚间复盘任务（$today）');
    } catch (e) {
      print('[BrainService] 晚间复盘调度失败: $e');
    }
  }

  /// 每日例行「行为建模」的确定性调度（不经大脑决策，可靠不靠 AI 自觉）。
  ///
  /// 每天 23:30 之后第一次 tick（App 存活时）创建一次 build_behavior_model
  /// 任务，scheduledAt=now 到点立即派发，用当天为止的行为观察重新归纳用户
  /// 24h 行为作息。用 PrefUtil 记录跨天防重复；当天已存在 pending/running
  /// 的建模任务（如派发失败待重试）也视为已调度。
  Future<void> _checkBehaviorModel() async {
    try {
      final now = DateTime.now();
      // 23:30 后进入行为建模窗口（晚于 23:00 的夜间归位，先复盘再建模）
      if (now.hour < 23 || (now.hour == 23 && now.minute < 30)) return;
      final today = '${now.year}-${now.month}-${now.day}';
      final last = PrefUtil.getValue<String>('behaviorModelLastAt') ?? '';
      if (last == today) return;

      final existing = await AgentTaskStore.query(action: 'build_behavior_model');
      final todayCreated = existing.any((t) {
        final c = t.createdAt;
        return '${c.year}-${c.month}-${c.day}' == today &&
            (t.status == 'pending' || t.status == 'running');
      });
      if (todayCreated) {
        await PrefUtil.setValue<String>('behaviorModelLastAt', today);
        return;
      }

      await AgentTaskStore.add(AgentTask(
        title: '智能体行为建模',
        kind: 'scheduled',
        action: 'build_behavior_model',
        params: {'basicTask': true}, // 智能体基础任务之一（实验室按此分组）
        scheduledAt: now,
        priority: 1,
      ));
      await PrefUtil.setValue<String>('behaviorModelLastAt', today);
      print('[BrainService] 已创建行为建模任务（$today）');
    } catch (e) {
      print('[BrainService] 行为建模调度失败: $e');
    }
  }

  /// 找出到点任务并分发执行。
  Future<void> _dispatchDueTasks() async {
    // 串行锁：runDueNow 不经 _busy 守卫，多信号并发时若不加锁，多个派发会
    // 同时取到同一批 pending 任务，重复执行/防连发守卫出现竞态。
    if (_dispatching) return;
    _dispatching = true;
    try {
      await _dispatchDueTasksLocked();
    } finally {
      _dispatching = false;
    }
  }

  Future<void> _dispatchDueTasksLocked() async {
    final pending = await AgentTaskStore.query(status: 'pending');
    final now = DateTime.now();
    final due = pending.where((t) {
      if (t.kind == 'immediate') return true;
      if (t.kind == 'scheduled') {
        // scheduledAt 为 null 时按到点处理，避免任务永远卡 pending
        return t.scheduledAt == null || !t.scheduledAt!.isAfter(now);
      }
      return false; // longterm 不自动执行，等大脑/用户处理
    }).toList();
    if (due.isEmpty) return;

    for (final task in due) {
      task.status = 'running';
      await AgentTaskStore.update(task);
      try {
        await AgentExecutor.execute(task);
        // 不带自有 UI 的动作（语音/画像沉淀/日记分析）用 toast 让执行可见；
        // start_chat / ask_user / block_screen 自身会跳页/播报，不再重复弹；
        // nightly_review（夜间归位）是安静例行，复盘在用户打开助手页时呈现，不弹。
        if (task.action != 'start_chat' &&
            task.action != 'ask_user' &&
            task.action != 'block_screen' &&
            task.action != 'nightly_review') {
          NoticeUtil.showToast('智能体已执行：「${task.title}」');
        }
        // 执行器已写终态。若仍为 running 且非阻断页，兜底置 done。
        final after = await AgentTaskStore.byId(task.id);
        if (after != null &&
            after.status == 'running' &&
            after.action != 'block_screen') {
          after.status = 'done';
          after.feedback = [...after.feedback, '[执行] 完成'];
          await AgentTaskStore.update(after);
        }
        // 反思学习回路：终态任务复盘一次（有用户反应的任务才会真正反思）
        unawaited(BrainReflect.maybeReflect(after ?? task));
      } catch (e) {
        // 执行失败：重排 5 分钟后重试，超过 3 次取消
        final retries =
            task.feedback.where((f) => f.contains('执行失败')).length;
        if (retries >= 2) {
          task.status = 'cancelled';
          task.feedback = [...task.feedback, '[执行] 多次失败，已取消'];
          await AgentTaskStore.update(task);
          // 取消的任务含失败时间线，值得反思一次
          unawaited(BrainReflect.maybeReflect(task));
          NoticeUtil.showToast('任务「${task.title}」多次失败，已取消');
        } else {
          task.status = 'pending';
          task.scheduledAt = DateTime.now().add(const Duration(minutes: 5));
          task.feedback = [
            ...task.feedback,
            '[执行] 执行失败，5 分钟后重试: $e',
          ];
          await AgentTaskStore.update(task);
          NoticeUtil.showToast('任务「${task.title}」执行失败，5 分钟后重试');
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

  /// 看门狗 2：等待回应的任务长时间无回应 → 交大脑判定收尾（不再静默结束）。
  ///
  /// 「所有任务都需要结果输入大脑，大脑判定结束才可以真正结束」的兜底：
  /// ask_user/start_chat 若用户始终没回应，不能无限挂起，也不能像之前那样被
  /// 静默置 done——把「用户长时间未回应」作为收尾原因送进大脑，由大脑判定
  /// 结束（通常询问已过时 → done，说明原因）还是继续等待。每个任务只判定
  /// 一次（params.staleJudged 标记），避免每分钟轮询重复烧 AI。
  static const Duration waitingUserStaleHours = Duration(hours: 6);

  Future<void> _watchdogWaiting() async {
    final waiting = await AgentTaskStore.query(status: 'waitingUser');
    final now = DateTime.now();
    for (final t in waiting) {
      if (t.params['staleJudged'] == true) continue;
      if (now.difference(t.updatedAt).inHours < waitingUserStaleHours.inHours) {
        continue;
      }
      t.params['staleJudged'] = true;
      await AgentTaskStore.update(t);
      print('[BrainService] 任务「${t.title}」超时未回应，交大脑判定收尾');
      unawaited(AgentBrain.finalizeTask(
        t,
        '用户超过 ${waitingUserStaleHours.inHours} 小时未回应，'
            '询问/会话可能已过时',
        judge: true,
      ));
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
