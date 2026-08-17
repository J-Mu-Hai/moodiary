import 'dart:convert';

import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/screen_time_service.dart';
import 'package:moodiary/utils/notice_util.dart';

import 'behavior_observations.dart';

/// 专注模式状态 — 用户声明「我要学习到晚上 9 点」后进入。
///
/// PrefUtil JSON 侧表（key=focusMode）：{active, startedAt, endAt, goal, taskId}。
class FocusModeState {
  final bool active;
  final DateTime? startedAt;
  final DateTime? endAt;
  final String goal;
  final String? taskId;

  const FocusModeState({
    required this.active,
    this.startedAt,
    this.endAt,
    this.goal = '',
    this.taskId,
  });

  Map<String, dynamic> toJson() => {
        'active': active,
        'startedAt': startedAt?.toIso8601String(),
        'endAt': endAt?.toIso8601String(),
        'goal': goal,
        'taskId': taskId,
      };

  factory FocusModeState.fromJson(Map<String, dynamic> j) => FocusModeState(
        active: j['active'] as bool? ?? false,
        startedAt: DateTime.tryParse(j['startedAt']?.toString() ?? ''),
        endAt: DateTime.tryParse(j['endAt']?.toString() ?? ''),
        goal: j['goal']?.toString() ?? '',
        taskId: j['taskId']?.toString(),
      );
}

class FocusModeStore {
  static const String _prefKey = 'focusMode';
  static const String _overrideKey = 'appFocusOverrides';

  static Future<FocusModeState> load() async {
    final s = PrefUtil.getValue<String>(_prefKey);
    if (s == null || s.isEmpty) return const FocusModeState(active: false);
    try {
      return FocusModeState.fromJson(
          Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {
      return const FocusModeState(active: false);
    }
  }

  static Future<void> _save(FocusModeState st) async {
    await PrefUtil.setValue<String>(_prefKey, jsonEncode(st.toJson()));
  }

  static Future<bool> isActive() async => (await load()).active;

  static Future<void> start({
    required String goal,
    DateTime? endAt,
    String? taskId,
  }) async {
    await _save(FocusModeState(
      active: true,
      startedAt: DateTime.now(),
      endAt: endAt,
      goal: goal,
      taskId: taskId,
    ));
  }

  static Future<void> end() async =>
      await _save(const FocusModeState(active: false));

  /// 同步读取 App 专注分类覆盖表 {关键词: focus|distract|neutral}。
  /// PrefUtil 是同步读取，供 agent_monitor.focusClassOf 直接调用。
  static Map<String, String> syncOverrides() {
    final s = PrefUtil.getValue<String>(_overrideKey);
    if (s == null || s.isEmpty) return {};
    try {
      return (jsonDecode(s) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _setOverride(String keyword, String focusClass) async {
    final map = {...syncOverrides(), keyword: focusClass};
    await PrefUtil.setValue<String>(_overrideKey, jsonEncode(map));
  }
}

/// 专注模式检测器 — 纯正则、零 AI 调用，从用户消息里识别专注开始/结束/App 覆盖。
///
/// 接线点：助手对话 getAi 与大脑 processFeedback（自发声明与回答「你在忙什么」
/// 都能进入专注）。开专注时自动打开「持续监督」，保证后台能检测前台 App。
class FocusModeDetector {
  // 专注意图词 + 启动动词（避免「我在学习」这类闲聊误开专注）
  static final RegExp _focusIntent =
      RegExp(r'(学习|工作|写作文|写作业|背书|背单词|背课文|复习|刷题|做练习|读书|读英语|练字|冥想|写代码)');
  static final RegExp _focusBegin =
      RegExp(r'(我要|我想|打算|决定|准备|开始|开启|进入|今天要|该开始|得开始|要开始|来开始)');
  static final RegExp _endTime =
      RegExp(r'到\s*(晚上|下午|上午|中午|凌晨)?\s*(\d{1,2})\s*点');
  static final RegExp _hourSpan = RegExp(r'(\d+)\s*小时');
  static final RegExp _endIntent =
      RegExp(r'(学完|学习完|做完|结束|不学了|休息|收工|下班|摸鱼结束|退出专注|暂停专注|停止专注|休息一下)');
  static final RegExp _override =
      RegExp(r'把?\s*([一-龥A-Za-z0-9]{2,10})\s*(?:设为|属于|算|归类为|算作)\s*(娱乐|消遣|专注|学习|工具|摸鱼)');

  /// 处理一条用户消息：先识别 App 覆盖设置，再识别专注开始/结束。
  static Future<void> handle(String msg) async {
    try {
      await _handleOverride(msg);
      if (await tryStart(msg)) return;
      await tryEnd(msg);
    } catch (e) {
      print('[FocusMode] 处理失败: $e');
    }
  }

  /// 尝试开启专注：消息含专注意图 + 启动动词。返回是否开启。
  /// 结束时间：到X点 → 今天 X 点（过了则顺延明天）；X小时 → +Xh；都没给 → 2 小时。
  static Future<bool> tryStart(String msg) async {
    if (!_focusIntent.hasMatch(msg) || !_focusBegin.hasMatch(msg)) {
      return false;
    }
    DateTime? endAt;
    final em = _endTime.firstMatch(msg);
    if (em != null) {
      var hour = int.tryParse(em.group(2) ?? '') ?? 0;
      final hint = em.group(1);
      // 「到晚上9点」= 21 点；「下午/上午/中午」保持原样
      if (hint != null && hint.contains('晚')) {
        if (hour + 12 <= 23) hour += 12;
      }
      final now = DateTime.now();
      endAt = DateTime(now.year, now.month, now.day, hour);
      if (!endAt.isAfter(now)) endAt = endAt.add(const Duration(days: 1));
    } else {
      final hm = _hourSpan.firstMatch(msg);
      endAt = DateTime.now().add(Duration(
          hours: int.tryParse(hm?.group(1) ?? '') ?? 2));
    }
    await FocusModeStore.start(goal: msg, endAt: endAt);
    // 专注需要后台持续检测前台 App → 自动打开「持续监督」
    if (!ScreenTimeService().monitoringEnabled) {
      try {
        await ScreenTimeService().setMonitoringEnabled(true);
        if (!await ScreenTimeService().isGranted()) {
          NoticeUtil.showToast('专注已开启，但缺少「使用情况访问」权限，无法监督你的 App 使用');
        }
      } catch (e) {
        print('[FocusMode] 自动开启持续监督失败: $e');
      }
    }
    print('[FocusMode] 专注开始：$msg（到 $endAt）');
    return true;
  }

  /// 尝试结束专注：消息含结束意图且专注当前开启。返回是否结束。
  /// 结束时会记录「专注结束」行为观察。
  static Future<bool> tryEnd(String msg) async {
    if (!_endIntent.hasMatch(msg)) return false;
    final st = await FocusModeStore.load();
    if (!st.active) return false;
    final started = st.startedAt ?? DateTime.now();
    await BehaviorObservationStore.record(
      event: '专注结束',
      activity: st.goal,
      durationMs: DateTime.now().difference(started).inMilliseconds,
      taskId: st.taskId,
      taskTitle: st.goal,
      confidence: 0.7,
    );
    await FocusModeStore.end();
    print('[FocusMode] 专注结束');
    return true;
  }

  /// 识别「把抖音设为娱乐 / 网易云属于专注」类指令 → 写入 App 分类覆盖表。
  static Future<void> _handleOverride(String msg) async {
    final m = _override.firstMatch(msg);
    if (m == null) return;
    final keyword = m.group(1)!.trim();
    final cls = m.group(2)!;
    final focusClass = switch (cls) {
      '娱乐' || '消遣' || '摸鱼' => 'distract',
      '专注' || '学习' || '工具' => 'focus',
      _ => 'neutral',
    };
    if (keyword.isEmpty) return;
    await FocusModeStore._setOverride(keyword, focusClass);
    print('[FocusMode] App 分类覆盖：$keyword → $focusClass');
  }
}
