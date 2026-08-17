import 'dart:convert';

import 'package:moodiary/common/models/isar/diary.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/memory_service.dart';
import 'package:moodiary/utils/agent_channel.dart';
import 'package:moodiary/utils/environment_sensor.dart';

import 'agent_brain.dart';
import 'agent_executor.dart';
import 'agent_task.dart';
import 'behavior_observations.dart';
import 'daily_rhythm.dart';
import 'diary_ai_read.dart';
import 'focus_mode.dart';

/// 大脑的代码机械监督 — 周期性检测环境/行为/画像状态变化，把变化送入大脑。
///
/// 构成智能体「主动性」的后半部分（前半是用户输入与任务变化）：
/// 天气变化、日记信息稳定、App 使用类别变化、画像未初始化 → 每次检测到即入脑。
///
/// 检测节流分两层：内存内节流（天气 30 分钟 / 日记 10 分钟 / 类别 60 分钟 /
/// 画像 30 分钟）+ 大脑侧冷却（同类型 6 小时，见 AgentBrain.signalCooldown）。
class BrainMonitor {
  DateTime? _lastWeatherCheck;
  DateTime? _lastDiaryCheck;
  DateTime? _lastUsageCheck;
  DateTime? _lastProfileCheck;
  DateTime? _lastLongtermCheck;
  DateTime? _lastTaskStallCheck;

  // ── 实时输入（会话级） ──
  String? _lastFgPackage; // 上一个/当前前台 App 包名
  DateTime? _lastFgSince; // 当前前台 App 开始时刻（用于写「使用App」观察）
  String? _lastFgAppName;
  String? _lastFgCategory;
  String? _lastFgFocusClass;

  // ── 专注监督（内存态，重启用 focusMode 状态重建） ──
  String? _focusReminderTaskId; // 当前活跃的委婉提醒任务 id
  DateTime? _focusDistractSince; // 连续刷娱乐 App 的开始时刻
  String? _focusDistractPackage;

  static const String _kWeather = 'brainLastWeather';
  static const String _kDiaryTs = 'brainLastDiaryTs';
  static const String _kUsage = 'brainLastUsageProfile';

  /// 定时询问（morning/afternoon/evening）当天是否已触发过的标记
  static const String _kCheckInFired = 'brainCheckInsFired';

  /// 记录一次日记写入（编辑页保存成功时调用）。
  static Future<void> recordDiaryWritten() async {
    await PrefUtil.setValue<int>(
        _kDiaryTs, DateTime.now().millisecondsSinceEpoch);
  }

  /// 周期性检查所有信号（BrainService 每分钟调用）。
  Future<void> checkSignals() async {
    // 实时输入（观察者核心）：前台 App 切换 → app_switched + 使用行为观察
    await _checkAppSwitched();
    // 专注监督：确定性提醒/升级，不依赖大脑生成
    await _checkFocusSupervision();
    // 定时主动沟通：下午 / 傍晚各一次
    await _checkTimedCheckIns();
    await _checkWeather();
    await _checkDiaryStable();
    await _checkUsageCategory();
    await _checkProfile();
    await _checkLongterm();
    await _checkTaskStall();
  }

  // ─── 信号 0：前台 App 切换（实时输入 + 早晨问候） ───────

  Future<void> _checkAppSwitched() async {
    final pkg = await AgentChannel.currentForegroundApp();
    if (pkg == null) return; // 拿不到（非 Android/无权限）→ 不做任何检测
    // 起床时间：当天首次检测到手机有动静就记录（任何时间都记，<5:00 打熬夜标）
    await DailyRhythmStore.recordWake(DateTime.now());
    // 早晨问候：检测到手机有动静（包括用户在本 App 内）就尝试触发，当天一次
    await _checkMorningCheckIn();
    // ''=用户此刻在 moodiary 本身。把上一个真实 App 的会话收尾记入观察，
    // 基线切到 ''（moodiary）；这样冷启动后从 moodiary 切到第一个真实 App
    // 才是真正的「切换」，能触发 app_switched（否则首个 App 只建基线、静默）。
    if (pkg.isEmpty) {
      if (_lastFgPackage != null &&
          _lastFgPackage!.isNotEmpty &&
          _lastFgSince != null) {
        final dur = DateTime.now().difference(_lastFgSince!);
        if (dur.inSeconds >= 15) {
          final prevApp = _lastFgAppName ?? _lastFgPackage!;
          await BehaviorObservationStore.record(
            event: '使用App',
            activity: prevApp,
            category: _lastFgCategory ?? classifyApp(_lastFgPackage!, prevApp),
            focusClass:
                _lastFgFocusClass ?? focusClassOf(_lastFgPackage!, prevApp),
            durationMs: dur.inMilliseconds,
            time: _lastFgSince,
            confidence: 0.7,
          );
        }
      }
      if (_lastFgPackage != '') {
        _lastFgPackage = '';
        _lastFgSince = DateTime.now();
        _lastFgAppName = 'moodiary';
        _lastFgCategory = classifyApp('cn.yooss.moodiary', 'moodiary');
        _lastFgFocusClass = focusClassOf('cn.yooss.moodiary', 'moodiary');
      }
      return;
    }
    if (pkg == _lastFgPackage) return; // 同一个 App，无切换

    // 首次检测（内存冷启动）：只建基线，不触发信号（避免启动即打扰）
    if (_lastFgPackage == null) {
      final appName = await _resolveAppName(pkg);
      _lastFgPackage = pkg;
      _lastFgSince = DateTime.now();
      _lastFgAppName = appName;
      _lastFgCategory = classifyApp(pkg, appName);
      _lastFgFocusClass = focusClassOf(pkg, appName);
      return;
    }

    // 切换发生：把「上一个 app 会话」写入行为观察（时间/类别/专注属性）
    if (_lastFgSince != null) {
      final dur = DateTime.now().difference(_lastFgSince!);
      if (dur.inSeconds >= 15) {
        final prevApp = _lastFgAppName ?? _lastFgPackage!;
        await BehaviorObservationStore.record(
          event: '使用App',
          activity: prevApp,
          category: _lastFgCategory ?? classifyApp(_lastFgPackage!, prevApp),
          focusClass:
              _lastFgFocusClass ?? focusClassOf(_lastFgPackage!, prevApp),
          durationMs: dur.inMilliseconds,
          time: _lastFgSince,
          confidence: 0.7,
        );
      }
    }

    // 解析新前台 App 并送入大脑（真正作为输入，10 分钟冷却不刷屏）
    final appName = await _resolveAppName(pkg);
    final category = classifyApp(pkg, appName);
    final fc = focusClassOf(pkg, appName);
    print('[BrainMonitor] 前台 App 切换: $appName（$category/$fc）');
    await AgentBrain.handleSignal(BrainSignal(
      type: 'app_switched',
      summary: '用户切换到 $appName（类别：$category，专注属性：$fc）。'
          '判断是否贴合用户此刻的安排；若在专注中切到娱乐类，代码会自行委婉提醒，'
          '你只需结合行为观察判断要不要额外关怀。',
      data: {
        'package': pkg,
        'appName': appName,
        'category': category,
        'focusClass': fc,
      },
    ));

    _lastFgPackage = pkg;
    _lastFgSince = DateTime.now();
    _lastFgAppName = appName;
    _lastFgCategory = category;
    _lastFgFocusClass = fc;
  }

  Future<String> _resolveAppName(String pkg) async {
    final label = await AgentChannel.appLabel(pkg);
    return (label == null || label.isEmpty) ? pkg : label;
  }

  // ─── 定时主动沟通（早晨 / 中午 / 傍晚各一次，确定性采集计划） ───────

  /// 早晨：当天首次检测到前台 App 且时间在 12:00 前 → 确定性问上午计划。
  /// 起床时间在 [_checkAppSwitched] 顶部单独记录（任何时间都记）。
  Future<void> _checkMorningCheckIn() async {
    final now = DateTime.now();
    if (now.hour >= 12) return;
    if (await _checkInFiredToday('morning')) return;
    await _firePlanAsk('morning', '早呀！今天上午有什么打算吗？');
    await AgentBrain.handleSignal(BrainSignal(
      type: 'morning_check_in',
      summary: '早上好，用户今天第一次开始用手机（${now.hour} 点）。'
          '上午计划的采集已由代码确定性发起（待办里有带 planPeriod 的 ask_user），'
          '不要重复创建询问计划的 ask_user，只补充关怀/安排或 noop。',
    ));
  }

  /// 中午 12:00-13:59 与傍晚 18:00-18:59 各确定性询问一次计划。
  Future<void> _checkTimedCheckIns() async {
    final now = DateTime.now();
    if (now.hour >= 12 && now.hour < 14) {
      if (await _checkInFiredToday('noon')) return;
      await _firePlanAsk('noon', '中午好！今天中午/下午有什么安排吗？');
      await AgentBrain.handleSignal(BrainSignal(
        type: 'noon_check_in',
        summary: '现在是中午 ${now.hour} 点。中午计划的采集已由代码确定性发起，'
            '不要重复创建询问计划的 ask_user，只补充关怀/安排或 noop。',
      ));
    }
    if (now.hour >= 18 && now.hour < 19) {
      if (await _checkInFiredToday('evening')) return;
      await _firePlanAsk(
          'evening', '晚上好！今晚有什么安排？白天计划完成得怎么样？');
      await AgentBrain.handleSignal(BrainSignal(
        type: 'evening_check_in',
        summary: '现在是傍晚 ${now.hour} 点。晚上计划的采集与白天完成情况询问'
            '已由代码确定性发起，不要重复创建询问计划的 ask_user，只补充关怀或 noop。',
      ));
    }
    // 明天计划：20:00-20:59 确定性询问一次（统一作息的基础任务之一）
    if (now.hour >= 20 && now.hour < 21) {
      if (await _checkInFiredToday('tomorrow')) return;
      await _firePlanAsk(
          'tomorrow', '今天快结束了，明天有什么打算吗？提前说说，我帮你记着。');
      await AgentBrain.handleSignal(BrainSignal(
        type: 'tomorrow_check_in',
        summary: '现在是晚上 ${now.hour} 点。明天计划的采集已由代码确定性发起'
            '（planPeriod:tomorrow），不要重复创建询问计划的 ask_user，只补充关怀或 noop。',
      ));
    }
  }

  /// 确定性发起一次「采集计划」的 ask_user：定时时机必然问到、回答必然落库
  /// （processFeedback 见 params.planPeriod 后写入 DailyRhythmStore）。
  /// params['basicTask']=true 标记这是统一作息的基础任务（询问上午/中午/晚上/
  /// 明天计划），实验室「今日基础任务」据此统一展示。
  Future<void> _firePlanAsk(String period, String question) async {
    try {
      final task = AgentTask(
        title: '询问${DailyRhythmStore.labelOf(period)}计划',
        kind: 'immediate',
        action: 'ask_user',
        params: {
          'planPeriod': period,
          'question': question,
          'text': '${DailyRhythmStore.labelOf(period)}计划采集',
          'basicTask': true,
        },
        priority: 2,
      );
      await AgentTaskStore.add(task);
      await AgentExecutor.execute(task);
    } catch (e) {
      print('[BrainMonitor] 计划采集 ask 失败: $e');
    }
  }

  /// 定时询问当天只触发一次：true=今天已触发过；未触发则标记后返回 false。
  Future<bool> _checkInFiredToday(String kind) async {
    final now = DateTime.now();
    final ymd = '${now.year}-${now.month}-${now.day}';
    final raw = PrefUtil.getValue<String>(_kCheckInFired);
    final map = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        map.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    if (map[kind] == ymd) return true;
    map[kind] = ymd;
    await PrefUtil.setValue<String>(_kCheckInFired, jsonEncode(map));
    return false;
  }

  // ─── 专注监督（确定性：3 分钟规则 → 委婉提醒 → 无回复锁屏） ──

  Future<void> _checkFocusSupervision() async {
    final state = await FocusModeStore.load();
    if (!state.active) {
      _focusReminderTaskId = null;
      _focusDistractSince = null;
      _focusDistractPackage = null;
      return;
    }

    // 到点自动结束专注（记录专注结束观察）
    final endAt = state.endAt;
    if (endAt != null && DateTime.now().isAfter(endAt)) {
      await FocusModeStore.end();
      await BehaviorObservationStore.record(
        event: '专注结束',
        activity: state.goal,
        taskId: state.taskId,
        taskTitle: state.goal,
        confidence: 0.6,
      );
      _focusReminderTaskId = null;
      _focusDistractSince = null;
      _focusDistractPackage = null;
      print('[BrainMonitor] 专注已到点自动结束');
      return;
    }

    final pkg = await AgentChannel.currentForegroundApp();
    if (pkg == null || pkg.isEmpty) return; // 在 moodiary 内/拿不到 → 不监督

    final appName = _lastFgPackage == pkg
        ? (_lastFgAppName ?? pkg)
        : await _resolveAppName(pkg);
    final fc = focusClassOf(pkg, appName);

    if (fc == 'focus' || fc == 'neutral') {
      // 回到专注/中性 App：重置计时，清理残留提醒
      _focusDistractSince = null;
      _focusDistractPackage = null;
      if (_focusReminderTaskId != null) {
        await _resolveFocusReminder(done: true);
        _focusReminderTaskId = null;
      }
      return;
    }

    // distract：统计连续刷时长
    if (_focusDistractPackage != pkg) {
      _focusDistractSince = DateTime.now();
      _focusDistractPackage = pkg;
    }
    final distractFor =
        DateTime.now().difference(_focusDistractSince!).inMinutes;
    if (distractFor < 3) return; // 不足 3 分钟不动

    // 已有活跃提醒：检查是否超时升级（无回复 ≥3 分钟 → 强制锁屏）
    if (_focusReminderTaskId != null) {
      final rt = await AgentTaskStore.byId(_focusReminderTaskId!);
      if (rt != null && rt.status == 'waitingUser') {
        final waited = DateTime.now().difference(rt.updatedAt).inMinutes;
        if (waited >= 3) {
          print('[BrainMonitor] 专注提醒无回复，升级强制锁屏');
          await _createFocusBlockScreen(state);
          await _resolveFocusReminder(done: false);
          _focusReminderTaskId = null;
        }
        return;
      }
      // 提醒已结束（用户回复/取消）→ 重置
      _focusReminderTaskId = null;
      return;
    }

    // 无活跃提醒：创建委婉提醒（确定性，直接派发进对话框对话）
    print(
        '[BrainMonitor] 专注中切到 $appName 已 $distractFor 分钟，创建委婉提醒');
    final reminder = AgentTask(
      title: '专注提醒：回到「${state.goal}」',
      kind: 'immediate',
      action: 'ask_user',
      params: {
        'focusReminder': true,
        'question': '我看到你正刷 $appName 呢，记得你刚才说「${state.goal}」，要不要先回来继续？',
        'text': '专注提醒',
        'focusGoal': state.goal,
      },
      priority: 3,
    );
    await AgentTaskStore.add(reminder);
    _focusReminderTaskId = reminder.id;
    await AgentExecutor.execute(reminder);
  }

  /// 升级：强制锁屏 ≥5 分钟（无回复时的最后手段）。
  Future<void> _createFocusBlockScreen(FocusModeState state) async {
    final goal = state.goal.isNotEmpty ? state.goal : '刚才的安排';
    final task = AgentTask(
      title: '强制锁屏：回到专注',
      kind: 'immediate',
      action: 'block_screen',
      params: {
        'title': '该回专注了',
        'reason': '刚才提醒过，还没看到你回来。先休息 5 分钟，再继续「$goal」吧。',
        'durationMinutes': 5,
        'force': true,
      },
      priority: 3,
    );
    await AgentTaskStore.add(task);
    await AgentExecutor.execute(task);
  }

  /// 收尾残留的专注提醒任务（回到专注 → done；升级锁屏 → cancelled）。
  Future<void> _resolveFocusReminder({required bool done}) async {
    final id = _focusReminderTaskId;
    if (id == null) return;
    final t = await AgentTaskStore.byId(id);
    if (t != null &&
        (t.status == 'waitingUser' ||
            t.status == 'running' ||
            t.status == 'pending')) {
      t.status = done ? 'done' : 'cancelled';
      t.feedback = [
        ...t.feedback,
        done ? '[专注监督] 用户已回到专注，提醒结束' : '[专注监督] 升级强制锁屏，提醒取消',
      ];
      await AgentTaskStore.update(t);
    }
  }

  // ─── 信号 1：地点/天气变化 ─────────────────────────────

  Future<void> _checkWeather() async {
    final now = DateTime.now();
    if (_lastWeatherCheck != null &&
        now.difference(_lastWeatherCheck!).inMinutes < 30) {
      return;
    }
    _lastWeatherCheck = now;
    try {
      final snap = await EnvironmentSensor.getSnapshot();
      if (snap == null) return;
      final city = '${snap['province']}${snap['city']}${snap['district']}';
      final key = '$city|${snap['weather']}|${snap['temp']}';
      final last = PrefUtil.getValue<String>(_kWeather) ?? '';
      if (last.isEmpty) {
        // 首次：只记录基线，不触发（避免启动即打扰）
        await PrefUtil.setValue<String>(_kWeather, key);
        return;
      }
      if (last != key) {
        print('[BrainMonitor] 天气变化 $last → $key');
        final summary = '用户所在位置/天气发生变化：现在是 $key（上次 $last）。';
        await AgentBrain.handleSignal(BrainSignal(
          type: 'weather_changed',
          summary: summary,
          data: {'now': key, 'last': last},
        ));
        await PrefUtil.setValue<String>(_kWeather, key);
      }
    } catch (e) {
      print('[BrainMonitor] weather check error: $e');
    }
  }

  // ─── 信号 2：日记信息变化稳定 ──────────────────────────

  Future<void> _checkDiaryStable() async {
    final now = DateTime.now();
    if (_lastDiaryCheck != null &&
        now.difference(_lastDiaryCheck!).inMinutes < 10) {
      return;
    }
    _lastDiaryCheck = now;
    final ts = PrefUtil.getValue<int>(_kDiaryTs);
    if (ts == null) return; // 从未写过日记
    final written = DateTime.fromMillisecondsSinceEpoch(ts);
    final stableMinutes = now.difference(written).inMinutes;
    if (stableMinutes < 30) return; // 距上次写入不足 30 分钟，不算稳定

    // 今天有日记才算「信息稳定」，避免只凭旧写入信号打扰
    var diaryCount = 0;
    try {
      final dayStart = DateTime(now.year, now.month, now.day);
      final diaries = await IsarUtil.getDiariesByDateRange(
          dayStart, dayStart.add(const Duration(hours: 23, minutes: 59)));
      if (diaries.isEmpty) return;
      diaryCount = diaries.length;
    } catch (_) {
      return;
    }

    // 统计近 3 天未读日记数，让大脑知道还有多少篇等着分析
    var unreadCount = 0;
    try {
      unreadCount = await DiaryAiReadStore.unreadCount();
    } catch (_) {}

    print('[BrainMonitor] 日记信息稳定（距上次写入 $stableMinutes 分钟，'
        '未读 ${unreadCount} 篇）');
    await AgentBrain.handleSignal(BrainSignal(
      type: 'diary_stable',
      summary: '用户刚写过日记（今天共 $diaryCount 篇，近 3 天未读 $unreadCount 篇），'
          '距上次写入已 $stableMinutes 分钟，信息趋于稳定。'
          '若存在未读日记，安排读取分析；并回顾今天的记录判断是否需要关怀或规划。',
      data: {
        'diaryCount': diaryCount,
        'unreadCount': unreadCount,
      },
    ));
  }

  // ─── 信号 3：App 使用类别变化 ──────────────────────────

  Future<void> _checkUsageCategory() async {
    final now = DateTime.now();
    if (_lastUsageCheck != null &&
        now.difference(_lastUsageCheck!).inMinutes < 60) {
      return;
    }
    _lastUsageCheck = now;
    try {
      final today =
          await _categoryDurations(DateTime(now.year, now.month, now.day));
      if (today.isEmpty) return; // 今天还没有使用数据
      final todayYmd = '${now.year}/${now.month}/${now.day}';

      final lastRaw = PrefUtil.getValue<String>(_kUsage);
      if (lastRaw == null || lastRaw.isEmpty) {
        // 首次：建立基线
        await PrefUtil.setValue<String>(
            _kUsage, jsonEncode({'yMd': todayYmd, 'categories': today}));
        return;
      }
      final last = jsonDecode(lastRaw) as Map<String, dynamic>;
      if (last['yMd'] == todayYmd) return; // 同一天不重复对比
      final yesterday =
          (last['categories'] as Map? ?? {}).map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()));

      final changed = _significantChange(yesterday, today);
      if (changed != null) {
        print('[BrainMonitor] 使用类别变化: $changed');
        await AgentBrain.handleSignal(BrainSignal(
          type: 'usage_category_changed',
          summary: changed,
          data: {'today': today, 'yesterday': yesterday},
        ));
      }
      // 无论是否显著变化，都更新基线为今天
      await PrefUtil.setValue<String>(
          _kUsage, jsonEncode({'yMd': todayYmd, 'categories': today}));
    } catch (e) {
      print('[BrainMonitor] usage category check error: $e');
    }
  }

  // ─── 信号 4：画像未初始化 ──────────────────────────────

  Future<void> _checkProfile() async {
    final now = DateTime.now();
    if (_lastProfileCheck != null &&
        now.difference(_lastProfileCheck!).inMinutes < 30) {
      return;
    }
    _lastProfileCheck = now;
    try {
      final data = await MemoryService.load();
      if (data.entries.isNotEmpty) {
        // 画像已初始化但缺最基础的「基础认知」（姓名/年龄/身份）→ 引导第一次沟通
        final hasBasic =
            data.entries.any((e) => e.category == '基础认知');
        if (!hasBasic) {
          print('[BrainMonitor] 画像缺基础认知');
          await AgentBrain.handleSignal(BrainSignal(
            type: 'profile_incomplete',
            summary: '画像已经有一些内容，但还没有最基础的认知：'
                '不知道用户的姓名、年龄、身份（学生/工作）。'
                '请找个合适时机与用户第一次沟通，问清这些。',
          ));
        }
        return;
      }
      // 画像为空：最近 30 天有日记才有沉淀素材，否则不打扰
      final diaries = await IsarUtil.getDiariesByDateRange(
          now.subtract(const Duration(days: 30)), now);
      if (diaries.isEmpty) return;
      print('[BrainMonitor] 画像未初始化');
      await AgentBrain.handleSignal(BrainSignal(
        type: 'profile_uninitialized',
        summary: '用户画像尚未初始化（有日记但还没沉淀过）。'
            '可以建议沉淀一次画像，让智能体开始认识用户。',
      ));
    } catch (e) {
      print('[BrainMonitor] profile check error: $e');
    }
  }

  // ─── 信号 5：长期计划回访 ─────────────────────────────

  Future<void> _checkLongterm() async {
    final now = DateTime.now();
    if (_lastLongtermCheck != null &&
        now.difference(_lastLongtermCheck!).inHours < 24) {
      return;
    }
    _lastLongtermCheck = now;
    try {
      final longterms =
          await AgentTaskStore.query(kind: 'longterm', status: 'pending');
      if (longterms.isEmpty) return;
      // 只回访已创建超过 24 小时的长期计划（避免刚建的立刻打扰）
      final due = longterms
          .where((t) => now.difference(t.createdAt).inHours >= 24)
          .toList();
      if (due.isEmpty) return;
      final titles = due.map((t) => '「${t.title}」').join('、');
      print('[BrainMonitor] 长期计划待回访: $titles');
      await AgentBrain.handleSignal(BrainSignal(
        type: 'longterm_overdue',
        summary: '有 ${due.length} 个长期计划已持续一段时间未完成：$titles。'
            '请 gently 提醒用户进展，或询问是否需要调整计划，督促用户完善。',
        data: {
          'titles': due.map((t) => t.title).toList(),
        },
      ));
    } catch (e) {
      print('[BrainMonitor] longterm check error: $e');
    }
  }

  // ─── 信号 6：用户任务管理板块停滞 ──────────────────────

  /// 用户任务多少天未更新视为停滞（可调）
  static const int taskStallDays = 3;

  Future<void> _checkTaskStall() async {
    final now = DateTime.now();
    if (_lastTaskStallCheck != null &&
        now.difference(_lastTaskStallCheck!).inHours < 24) {
      return;
    }
    _lastTaskStallCheck = now;
    try {
      final pending = await _pendingUserTasks();
      if (pending.isEmpty) return;
      final stalled = pending
          .where((t) => now.difference(t.time).inDays >= taskStallDays)
          .toList();
      if (stalled.isEmpty) return;
      final lines = stalled
          .map((t) => '「${t.title.isEmpty ? '(无标题)' : t.title}」'
              '${now.difference(t.time).inDays}天未动')
          .join('、');
      print('[BrainMonitor] 任务停滞: $lines');
      await AgentBrain.handleSignal(BrainSignal(
        type: 'task_stall',
        summary: '用户任务板块有 ${stalled.length} 个任务已 $taskStallDays 天以上未更新：$lines。'
            '请 gently 提醒进展，或帮用户把任务拆小/调整计划，不要施压。',
        data: {
          'titles': stalled.map((t) => t.title).toList(),
          'stallDays': taskStallDays,
        },
      ));
    } catch (e) {
      print('[BrainMonitor] task stall check error: $e');
    }
  }

  /// 用户「任务管理」分类下未完成（无「完成」标签）的近期任务。
  static Future<List<Diary>> _pendingUserTasks() async {
    try {
      final cats = await IsarUtil.getAllCategoryAsync();
      final taskCat =
          cats.where((c) => c.categoryName == '任务管理').toList();
      if (taskCat.isEmpty) return [];
      final cat = taskCat.first;
      final now = DateTime.now();
      final all = await IsarUtil.getDiariesByDateRange(
          now.subtract(const Duration(days: 30)), now);
      return all
          .where((d) =>
              d.show && d.categoryId == cat.id && !d.tags.contains('完成'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── 应用类别 ─────────────────────────────────────────

  /// 包名/应用名关键词 → 类别。映射不全会归「其他」，随使用迭代补充。
  static const Map<String, List<String>> _categoryRules = {
    '社交': [
      'wechat', 'weixin', 'tencent.mm', 'mobileqq', 'qq', '微博', 'weibo',
      '贴吧', '小红书', 'xiaohongshu', '钉钉', 'dingtalk', '企业微信',
      'telegram', 'whatsapp', 'instagram', 'facebook', 'twitter', 'soul',
      '陌陌', '探探', '脉脉', 'linkedin', '泡泡',
    ],
    '短视频': [
      'douyin', 'aweme', 'kuaishou', '快手', '抖音', '西瓜视频', 'bilibili', 'bili',
      'youtube', '油管', 'reels', 'shorts', '皮皮虾',
    ],
    '游戏': [
      'game', 'tmgp', 'miHoYo', 'honkai', 'genshin', '原神', '崩坏', '王者',
      '和平精英', 'taptap', 'steam', 'league', '部落冲突', '明日方舟', '蛋仔',
      '开心消消乐', '地铁跑酷', '贪吃蛇', '洛克', 'rockking',
    ],
    '阅读': [
      '微信读书', 'wechat_reader', 'kindle', '番茄', 'novel', '小说', '起点', '阅读',
      '晋江', 'lofter', '轻小说',
    ],
    '工具': [
      'alipay', '支付宝', 'taobao', '淘宝', '京东', 'jd', 'weather', '地图',
      '相机', 'camera', 'settings', '设置', 'browser', '浏览器', '应用商店',
      '百度网盘', '夸克', 'wps', 'office', 'word', 'excel', 'notion', '石墨',
      '有道云', '滴答', '番茄钟', 'forest', '美团', '滴滴', '高德',
    ],
    '学习': [
      '学习', '知乎', 'zhihu', '词典', '英语', 'edu', '学堂', '百度',
      '多邻国', 'duolingo', '百词斩', '扇贝', 'anki', 'coursera',
    ],
    '音乐': [
      'music', 'netease', '网易云', 'qq音乐', '酷狗', 'kugou', 'spotify',
      'audiobook', '喜马拉雅', '荔枝', 'podcast', '播客', '小宇宙', '汽水音乐',
    ],
  };

  static String classifyApp(String packageName, String appName) {
    final text = '${packageName.toLowerCase()} $appName'.toLowerCase();
    for (final entry in _categoryRules.entries) {
      if (entry.value.any(text.contains)) return entry.key;
    }
    return '其他';
  }

  /// 娱乐/非娱乐分类轴（专注监督用）。
  ///
  /// 优先级：用户覆盖（对话里「把抖音设为娱乐」，focus_mode.dart 写入
  /// appFocusOverrides）> 规则映射 > 默认 neutral。
  /// 返回 focus（利于专注）/ distract（娱乐，需监督）/ neutral（中性，不误扰）。
  static String focusClassOf(String packageName, String appName) {
    final text = '${packageName.toLowerCase()} $appName'.toLowerCase();
    try {
      final overrides = FocusModeStore.syncOverrides();
      for (final e in overrides.entries) {
        if (text.contains(e.key.toLowerCase())) return e.value;
      }
    } catch (_) {}
    switch (classifyApp(packageName, appName)) {
      case '短视频' || '游戏' || '社交':
        return 'distract';
      case '学习' || '阅读' || '工具':
        return 'focus';
      default:
        return 'neutral';
    }
  }

  static Future<Map<String, int>> _categoryDurations(DateTime day) async {
    final yMd = '${day.year}/${day.month}/${day.day}';
    final sessions = await IsarUtil.getUsageSessionsByDay(yMd);
    final map = <String, int>{};
    for (final s in sessions) {
      final cat = classifyApp(s.packageName, s.appName);
      map[cat] = (map[cat] ?? 0) + s.durationMs;
    }
    return map;
  }

  /// 对比两天的类别占比：任一主要类别相对占比变化 >30% 即视为显著，
  /// 返回自然语言描述；无显著变化返回 null。
  static String? _significantChange(
      Map<String, int> yesterday, Map<String, int> today) {
    Map<String, double> props(Map<String, int> m) {
      final total = m.values.fold<int>(0, (a, b) => a + b);
      if (total == 0) return {};
      return m.map((k, v) => MapEntry(k, v / total));
    }

    final y = props(yesterday);
    final t = props(today);
    final all = {...y.keys, ...t.keys};
    final changes = <String, double>{};
    for (final cat in all) {
      final yv = y[cat] ?? 0.0;
      final tv = t[cat] ?? 0.0;
      if (yv < 0.05 && tv < 0.05) continue; // 边缘类别忽略
      final base = yv < 0.01 ? 0.01 : yv;
      final rel = ((tv - yv).abs() / base).abs();
      if (rel > 0.3) changes[cat] = tv - yv;
    }
    if (changes.isEmpty) return null;
    final parts = changes.entries.map((e) {
      final d = (e.value * 100).round();
      return '${e.key}${d >= 0 ? '+' : ''}$d%';
    }).join('，');
    return '今天手机使用类别构成与昨天差异显著：$parts。'
        '请判断是否需要关心用户的作息或给出建议。';
  }
}
