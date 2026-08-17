import 'dart:convert';

import 'package:moodiary/common/models/isar/diary.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/memory_service.dart';
import 'package:moodiary/utils/environment_sensor.dart';

import 'agent_brain.dart';
import 'agent_task.dart';
import 'diary_ai_read.dart';

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

  static const String _kWeather = 'brainLastWeather';
  static const String _kDiaryTs = 'brainLastDiaryTs';
  static const String _kUsage = 'brainLastUsageProfile';

  /// 记录一次日记写入（编辑页保存成功时调用）。
  static Future<void> recordDiaryWritten() async {
    await PrefUtil.setValue<int>(
        _kDiaryTs, DateTime.now().millisecondsSinceEpoch);
  }

  /// 周期性检查所有信号（BrainService 每分钟调用）。
  Future<void> checkSignals() async {
    await _checkWeather();
    await _checkDiaryStable();
    await _checkUsageCategory();
    await _checkProfile();
    await _checkLongterm();
    await _checkTaskStall();
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
    ],
    '短视频': [
      'douyin', 'aweme', 'kuaishou', '快手', '抖音', '西瓜视频', 'bilibili', 'bili',
    ],
    '游戏': [
      'game', 'tmgp', 'miHoYo', 'honkai', 'genshin', '原神', '崩坏', '王者',
      '和平精英',
    ],
    '阅读': [
      '微信读书', 'wechat_reader', 'kindle', '番茄', 'novel', '小说', '起点', '阅读',
    ],
    '工具': [
      'alipay', '支付宝', 'taobao', '淘宝', '京东', 'jd', 'weather', '地图',
      '相机', 'camera', 'settings', '设置', 'browser', '浏览器', '应用商店',
    ],
    '学习': [
      '学习', '知乎', 'zhihu', '词典', '英语', 'edu', '学堂', '百度',
    ],
    '音乐': [
      'music', 'netease', '网易云', 'qq音乐', '酷狗', 'kugou', 'spotify',
      'audiobook',
    ],
  };

  static String classifyApp(String packageName, String appName) {
    final text = '${packageName.toLowerCase()} $appName'.toLowerCase();
    for (final entry in _categoryRules.entries) {
      if (entry.value.any(text.contains)) return entry.key;
    }
    return '其他';
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
