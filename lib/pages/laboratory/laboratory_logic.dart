import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/agent_brain/agent_brain.dart';
import 'package:moodiary/services/agent_brain/agent_executor.dart';
import 'package:moodiary/services/agent_brain/agent_rule.dart';
import 'package:moodiary/services/agent_brain/agent_task.dart';
import 'package:moodiary/services/agent_brain/behavior_observations.dart';
import 'package:moodiary/services/memory_service.dart';
import 'package:moodiary/utils/aes_util.dart';
import 'package:moodiary/utils/environment_sensor.dart';
import 'package:moodiary/utils/file_util.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:moodiary/utils/tts_speaker.dart';
import 'package:refreshed/refreshed.dart';
import 'package:share_plus/share_plus.dart';

class LaboratoryLogic extends GetxController {
  // ─── AI Provider 管理 ─────────────────────────────────

  /// 获取所有 AI Provider 配置
  List<AIProviderConfig> getProviders() {
    final json = PrefUtil.getValue<String>('aiProviders');
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => AIProviderConfig.fromJson(e)).toList();
  }

  /// 保存 AI Provider 配置列表
  Future<void> _saveProviders(List<AIProviderConfig> providers) async {
    final json = jsonEncode(providers.map((p) => p.toJson()).toList());
    await PrefUtil.setValue<String>('aiProviders', json);
    update();
  }

  /// 添加 Provider
  Future<void> addProvider(AIProviderConfig config) async {
    final providers = getProviders();
    // 自动生成唯一 ID
    config.id = 'provider_${DateTime.now().millisecondsSinceEpoch}';
    providers.add(config);
    await _saveProviders(providers);
  }

  /// 更新 Provider
  Future<void> updateProvider(String id, AIProviderConfig config) async {
    final providers = getProviders();
    final index = providers.indexWhere((p) => p.id == id);
    if (index != -1) {
      providers[index] = config;
      await _saveProviders(providers);
    }
  }

  /// 删除 Provider
  Future<void> deleteProvider(String id) async {
    final providers = getProviders();
    providers.removeWhere((p) => p.id == id);
    await _saveProviders(providers);
    // 如果删除的是当前选中的，重置
    if (PrefUtil.getValue<String>('aiCurrentProviderId') == id) {
      await PrefUtil.setValue<String>('aiCurrentProviderId', '');
    }
  }

  // ─── 兼容旧的腾讯云密钥 ───────────────────────────────

  Future<void> setTencentID({required String id, required String key}) async {
    await PrefUtil.setValue<String>('tencentId', id);
    await PrefUtil.setValue<String>('tencentKey', key);
    // 同时也创建一个 TencentProvider
    final providers = getProviders();
    final existing = providers.indexWhere((p) => p.id == 'tencent');
    final config = AIProviderConfig(
      id: 'tencent',
      displayName: '腾讯混元',
      baseUrl: 'https://hunyuan.tencentcloudapi.com',
      model: 'hunyuan-lite',
      apiKey: '$id:$key',
    );
    if (existing != -1) {
      providers[existing] = config;
    } else {
      providers.add(config);
    }
    await _saveProviders(providers);
    update();
  }

  Future<void> setQweatherKey({required String key}) async {
    await PrefUtil.setValue<String>('qweatherKey', key);
    update();
  }

  Future<void> setTiandituKey({required String key}) async {
    await PrefUtil.setValue<String>('tiandituKey', key);
    update();
  }

  Future<void> exportErrorLog() async {
    if ((await File(FileUtil.getErrorLogPath()).readAsString()).isNotEmpty) {
      final result = await Share.shareXFiles([XFile(FileUtil.getErrorLogPath())]);
      if (result.status == ShareResultStatus.success) {
        await File(FileUtil.getErrorLogPath()).writeAsString('');
        NoticeUtil.showToast('日志导出成功，已删除本地日志');
      }
    } else {
      NoticeUtil.showToast('暂无日志');
    }
  }

  Future<bool> aesTest() async {
    final key = await AesUtil.deriveKey(salt: 'salt', userKey: 'password');
    final encrypted = await AesUtil.encrypt(key: key, data: 'Hello World');
    final decrypted = await AesUtil.decrypt(key: key, encryptedData: encrypted);
    return decrypted == 'Hello World';
  }

  // ─── 用户画像沉淀（阶段 1 记忆层演示） ────────────────

  /// 立即执行一次画像沉淀（不等 23:30 定时），返回沉淀摘要
  Future<String> consolidateMemory() async {
    NoticeUtil.showToast('正在沉淀用户画像…');
    try {
      final summary = await MemoryService.consolidate();
      NoticeUtil.showToast('沉淀完成');
      return summary;
    } catch (e) {
      NoticeUtil.showToast('沉淀失败: $e');
      return '沉淀失败: $e';
    }
  }

  // ─── 环境感知 + 语音播报（演示） ─────────────────────

  /// 获取环境快照 → 生成播报句 → 豆包 TTS 合成并播放
  Future<void> environmentBroadcast() async {
    NoticeUtil.showToast('正在获取环境…');
    try {
      final snap = await EnvironmentSensor.getSnapshot();
      if (snap == null) {
        NoticeUtil.showToast('环境获取失败：请检查网络或 key 配置');
        return;
      }
      final p = snap['province'].toString();
      final c = snap['city'].toString();
      final d = snap['district'].toString();
      final city = '$p${(c.isNotEmpty && !p.contains(c) ? c : '')}$d';
      final weather = snap['weather'].toString();
      final temp = snap['temp'].toString();
      final sentence = weather.isNotEmpty
          ? '你现在在$city，天气$weather，$temp 摄氏度。'
          : '你现在在$city。';
      NoticeUtil.showToast('正在合成语音…');
      final ok = await TtsSpeaker.speak(sentence);
      NoticeUtil.showToast(
          ok ? '播放完成' : '语音播放失败: ${TtsSpeaker.lastError}');
    } catch (e) {
      NoticeUtil.showToast('环境播报失败：$e');
    }
  }

  // ─── 智能体大脑（阶段 3：触发→规划→执行→反馈闭环） ─────────

  /// 加载进行中的任务（pending / running / waitingUser），供实验室可视化。
  Future<List<AgentTask>> loadActiveTasks() async {
    final pending = await AgentTaskStore.query(status: 'pending');
    final running = await AgentTaskStore.query(status: 'running');
    final waiting = await AgentTaskStore.query(status: 'waitingUser');
    return [...pending, ...running, ...waiting];
  }

  /// 今日「基础任务」：统一作息与复盘等确定性日常例行（带 params.basicTask
  /// 标记），任意状态都展示，让当天的基础任务规划在实验室里统一可见。
  Future<List<AgentTask>> loadBasicTasksToday() async {
    final all = await AgentTaskStore.load();
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    return all.where((t) {
      final c = t.createdAt;
      if ('${c.year}-${c.month}-${c.day}' != today) return false;
      return t.params['basicTask'] == true;
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// 观察者积累的行为观察（时间段→在做什么→效果），新→旧。
  Future<List<BehaviorObservation>> loadBehaviorObservations() =>
      BehaviorObservationStore.recent(limit: 40);

  /// 常做行为模板文本（时间段→App→次数），供评估观察者效果。
  Future<String> behaviorTemplateText() =>
      BehaviorObservationStore.topBehaviorsText(DateTime.now(), top: 4);

  /// 手动触发一类信号（force 跳过冷却），返回大脑决策结果。
  Future<String> triggerBrainSignal(String type) async {
    final signals = <String, BrainSignal>{
      'weather_changed': BrainSignal(
        type: 'weather_changed',
        summary: '【手动测试】模拟地点/天气变化信号。',
        data: {'manual': true},
      ),
      'diary_stable': BrainSignal(
        type: 'diary_stable',
        summary: '【手动测试】模拟日记信息变化稳定信号（近 3 天未读日记会被分析）。',
        data: {'manual': true},
      ),
      'usage_category_changed': BrainSignal(
        type: 'usage_category_changed',
        summary: '【手动测试】模拟手机 App 使用类别变化信号。',
        data: {'manual': true},
      ),
      'profile_uninitialized': BrainSignal(
        type: 'profile_uninitialized',
        summary: '【手动测试】模拟用户画像未初始化信号。',
        data: {'manual': true},
      ),
      'profile_incomplete': BrainSignal(
        type: 'profile_incomplete',
        summary: '【手动测试】模拟画像缺基础认知信号（还不知道姓名/年龄/身份）。',
        data: {'manual': true},
      ),
      'longterm_overdue': BrainSignal(
        type: 'longterm_overdue',
        summary: '【手动测试】模拟长期计划到期回访信号。',
        data: {'manual': true},
      ),
      'task_stall': BrainSignal(
        type: 'task_stall',
        summary: '【手动测试】模拟用户任务板块停滞信号（有任务多日未更新）。',
        data: {'manual': true, 'titles': ['（示例任务）'], 'stallDays': 3},
      ),
      'diary_written': BrainSignal(
        type: 'diary_written',
        summary: '【手动测试】模拟用户刚写完一篇日记《测试日记》：今天天气不错，出去走了走。',
        data: {'manual': true, 'title': '测试日记', 'snippet': '今天天气不错，出去走了走'},
      ),
      'app_switched': BrainSignal(
        type: 'app_switched',
        summary: '【手动测试】模拟用户切换到 抖音（类别：短视频，专注属性：distract）。',
        data: {
          'manual': true,
          'package': 'com.ss.android.ugc.aweme',
          'appName': '抖音',
          'category': '短视频',
          'focusClass': 'distract',
        },
      ),
      'morning_check_in': BrainSignal(
        type: 'morning_check_in',
        summary: '【手动测试】模拟早晨主动问候信号（用户今天第一次开始用手机）。',
        data: {'manual': true},
      ),
      'noon_check_in': BrainSignal(
        type: 'noon_check_in',
        summary: '【手动测试】模拟中午 12-14 点定时主动询问信号。',
        data: {'manual': true},
      ),
      'evening_check_in': BrainSignal(
        type: 'evening_check_in',
        summary: '【手动测试】模拟傍晚 18-19 点定时主动询问信号。',
        data: {'manual': true},
      ),
      'tomorrow_check_in': BrainSignal(
        type: 'tomorrow_check_in',
        summary: '【手动测试】模拟晚上 20-21 点询问明天计划信号。',
        data: {'manual': true},
      ),
    };
    final signal = signals[type];
    if (signal == null) return '未知信号类型: $type';
    return await AgentBrain.handleSignal(signal, force: true);
  }

  /// 最近一次大脑决策的输入/输出（脑 IO 监督面板读取）。
  Future<Map<String, dynamic>?> getLastBrainDecision() async {
    final s = PrefUtil.getValue<String>('brainLastDecision');
    if (s == null || s.isEmpty) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 按日期回溯的智能体输入/输出日志（新→旧，供实验室按日期分组展示）。
  ///
  /// 记录每条大脑决策（kind=decision：信号 → 生成的计划）与每次反馈判定
  /// （kind=feedback：用户反馈 → 大脑判定 done/wait），开发阶段观察
  /// 「智能体每天有什么输入、产出了什么输出」。
  Future<List<Map<String, dynamic>>> getBrainDecisionLog() async {
    final s = PrefUtil.getValue<String>('brainDecisionLog');
    if (s == null || s.isEmpty) return [];
    try {
      return (jsonDecode(s) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 添加一条用户规则并送入大脑分析，返回大脑生成的规划结果。
  Future<String> addRule(String rule) async {
    await AgentRuleStore.add(rule);
    return await AgentBrain.handleSignal(
      BrainSignal(
        type: 'user_rule',
        summary: '用户新增自定义规则：$rule',
        data: {'rule': rule},
      ),
      force: true,
    );
  }

  Future<void> removeRule(String rule) async {
    await AgentRuleStore.remove(rule);
  }

  Future<List<String>> loadRules() => AgentRuleStore.load();

  /// 手动执行一次夜间归位（实验室验证用，不经大脑决策，直接跑归位执行器）。
  Future<String> runNightlyReview() async {
    final task = AgentTask(
      title: '夜间归位：梳理今天',
      kind: 'scheduled',
      action: 'nightly_review',
      scheduledAt: DateTime.now(),
      priority: 2,
    );
    await AgentTaskStore.add(task);
    return await executeTask(task);
  }

  /// 手动执行一个任务（实验室直接跑执行器，不等到点轮询）。
  Future<String> executeTask(AgentTask task) async {
    task.status = 'running';
    await AgentTaskStore.update(task);
    await AgentExecutor.execute(task);
    return '已执行';
  }

  /// 取消一个任务。
  Future<void> cancelTask(AgentTask task) async {
    task.status = 'cancelled';
    task.feedback = [...task.feedback, '[实验室] 用户取消'];
    await AgentTaskStore.update(task);
  }
}
