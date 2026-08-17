import 'dart:convert';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/main.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/agent_brain/agent_task.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:refreshed/refreshed.dart';

import 'laboratory_logic.dart';

class LaboratoryPage extends StatelessWidget {
  const LaboratoryPage({super.key});

  Future<void> _editProvider(
      BuildContext context, LaboratoryLogic logic, AIProviderConfig? existing) async {
    final isNew = existing == null;
    final initialName = existing?.displayName ?? '';
    final initialUrl = existing?.baseUrl ?? '';
    final initialKey = existing?.apiKey ?? '';
    final initialModel = existing?.model ?? '';

    final res = await showTextInputDialog(
      context: context,
      title: isNew ? '添加 AI 服务商' : '编辑 AI 服务商',
      textFields: [
        DialogTextField(
          hintText: '显示名称',
          initialText: initialName,
        ),
        DialogTextField(
          hintText: 'API 地址 (如 https://api.openai.com/v1/chat/completions)',
          initialText: initialUrl,
        ),
        DialogTextField(
          hintText: 'API Key',
          initialText: initialKey,
        ),
        DialogTextField(
          hintText: '模型名 (如 gpt-4, deepseek-chat)',
          initialText: initialModel,
        ),
      ],
      style: AdaptiveStyle.material,
    );
    if (res == null) return;

    final config = AIProviderConfig(
      id: existing?.id ?? '',
      displayName: res[0],
      baseUrl: res[1],
      apiKey: res[2],
      model: res[3],
    );

    if (isNew) {
      await logic.addProvider(config);
    } else {
      await logic.updateProvider(existing.id, config);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logic = Bind.find<LaboratoryLogic>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingLab),
      ),
      body: GetBuilder<LaboratoryLogic>(builder: (_) {
        final providers = logic.getProviders();
        return ListView(
          children: [
            // ── AI 服务商 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('AI 服务商',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _editProvider(context, logic, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加'),
                  ),
                ],
              ),
            ),
            if (providers.isEmpty)
              const ListTile(
                title: Text('暂无配置'),
                subtitle: Text('点击右上角"添加"配置 AI 服务商'),
              ),
            ...providers.map((p) => ListTile(
                  leading: Icon(
                    p.id == 'tencent' ? Icons.cloud : Icons.memory,
                    color: colorScheme.primary,
                  ),
                  title: Text(p.displayName),
                  subtitle: Text('${p.model}\n${p.baseUrl}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _editProvider(context, logic, p),
                      ),
                      if (p.id != 'tencent')
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: colorScheme.error),
                          onPressed: () => logic.deleteProvider(p.id),
                        ),
                    ],
                  ),
                )),
            const Divider(),

            // ── 原有的其他配置 ──
            ListTile(
              title: const Text('和风天气密钥'),
              subtitle: SelectionArea(
                  child: Text(PrefUtil.getValue<String>('qweatherKey') ?? '')),
              trailing: IconButton(
                  onPressed: () async {
                    final res = await showTextInputDialog(
                        context: context,
                        style: AdaptiveStyle.material,
                        title: '和风天气密钥',
                        message: '在和风天气控制台获取密钥',
                        textFields: [
                          DialogTextField(
                            hintText: 'KEY',
                            initialText:
                                PrefUtil.getValue<String>('qweatherKey') ?? '',
                          )
                        ]);
                    if (res != null) {
                      logic.setQweatherKey(key: res[0]);
                    }
                  },
                  icon: const FaIcon(FontAwesomeIcons.wrench)),
            ),
            ListTile(
              title: const Text('天地图密钥'),
              subtitle: SelectionArea(
                  child: Text(PrefUtil.getValue<String>('tiandituKey') ?? '')),
              trailing: IconButton(
                  onPressed: () async {
                    final res = await showTextInputDialog(
                        context: context,
                        textFields: [
                          DialogTextField(
                            hintText: 'KEY',
                            initialText:
                                PrefUtil.getValue<String>('tiandituKey') ?? '',
                          )
                        ],
                        title: '天地图密钥',
                        message: '在天地图控制台获取密钥',
                        style: AdaptiveStyle.material);
                    if (res != null) {
                      logic.setTiandituKey(key: res[0]);
                    }
                  },
                  icon: const FaIcon(FontAwesomeIcons.wrench)),
            ),
            ListTile(
              onTap: () => logic.exportErrorLog(),
              title: const Text('导出日志文件'),
            ),
            ListTile(
              onTap: () async {
                final res = await logic.aesTest();
                if (res) {
                  NoticeUtil.showToast('加密测试通过');
                } else {
                  NoticeUtil.showToast('加密测试失败');
                }
              },
              title: const Text('加密测试'),
            ),
            const Divider(),
            ListTile(
              onTap: () => logic.environmentBroadcast(),
              leading: const Icon(Icons.graphic_eq),
              title: const Text('环境播报'),
              subtitle: const Text('测试环境感知+语音：播报当前所在城市与天气'),
            ),
            ListTile(
              onTap: () async {
                final summary = await logic.consolidateMemory();
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('画像沉淀结果'),
                    content: SelectionArea(
                        child: Text(summary, style: const TextStyle(fontSize: 13))),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('好的'),
                      ),
                    ],
                  ),
                );
              },
              leading: const Icon(Icons.psychology),
              title: const Text('立即沉淀画像'),
              subtitle: const Text('手动执行一次记忆层沉淀：把今天日记的认知写进用户画像'),
            ),
            // 智能体大脑：信号触发 / 任务库 / 用户规则
            const _BrainSection(),
          ],
        );
      }),
    );
  }
}

/// 智能体大脑演示区块：手动触发信号、可视化任务库、添加用户规则。
///
/// 每次操作后重新读取任务库与规则，让「信号 → 规划 → 执行」闭环可直观观察。
class _BrainSection extends StatefulWidget {
  const _BrainSection();

  @override
  State<_BrainSection> createState() => _BrainSectionState();
}

class _BrainSectionState extends State<_BrainSection> {
  final logic = Bind.find<LaboratoryLogic>();
  List<AgentTask> _tasks = [];
  List<AgentTask> _doneTasks = [];
  List<String> _rules = [];
  Map<String, dynamic>? _decision;
  List<Map<String, dynamic>> _decisionLog = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final tasks = await logic.loadActiveTasks();
    final done = await logic.loadDoneTasks();
    final rules = await logic.loadRules();
    final decision = await logic.getLastBrainDecision();
    final decisionLog = await logic.getBrainDecisionLog();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _doneTasks = done;
      _rules = rules;
      _decision = decision;
      _decisionLog = decisionLog;
      _loading = false;
    });
  }

  Future<void> _showResult(String title, String content) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectionArea(
            child: Text(content, style: const TextStyle(fontSize: 13))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  Future<void> _trigger(String type) async {
    final result = await logic.triggerBrainSignal(type);
    await _refresh();
    await _showResult('大脑决策结果', result);
  }

  /// 手动执行一次夜间归位（直接跑归位执行器，验证行为逻辑梳理+复盘）。
  Future<void> _runNightly() async {
    final result = await logic.runNightlyReview();
    await _refresh();
    await _showResult('夜间归位', result);
  }

  Future<void> _addRule() async {
    final res = await showTextInputDialog(
      context: context,
      title: '添加规则',
      message: '用一句话告诉智能体你想让它帮忙的事，大脑会自动分析生成任务规划',
      textFields: const [
        DialogTextField(hintText: '如：每天 23 点提醒我睡觉'),
      ],
      style: AdaptiveStyle.material,
    );
    if (res == null || res[0].trim().isEmpty) return;
    final result = await logic.addRule(res[0].trim());
    await _refresh();
    await _showResult('大脑规划结果', result);
  }

  Future<void> _exec(AgentTask task) async {
    await logic.executeTask(task);
    await _refresh();
  }

  Future<void> _cancel(AgentTask task) async {
    await logic.cancelTask(task);
    await _refresh();
  }

  String _fmtHm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 任务类型的中文标签（immediate=即时 / scheduled=定时 / longterm=长期）。
  String _kindLabel(String kind) => switch (kind) {
        'scheduled' => '定时',
        'longterm' => '长期',
        _ => '即时',
      };

  /// 任务状态的中文标签。
  String _statusLabel(String status) => switch (status) {
        'pending' => '待执行',
        'running' => '执行中',
        'waitingUser' => '等待回应',
        'done' => '已完成',
        'cancelled' => '已取消',
        _ => status,
      };

  String _fmtFull(DateTime t) =>
      '${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 任务详情弹窗：完整展示「什么时间做什么事 + 执行情况」。
  ///
  /// 展示：状态/类型/动作/优先级、创建/定时/最后更新时间、参数（智能体打算
  /// 做什么），以及 feedback 时间线（每次执行、失败重试、大脑判定、用户回应、
  /// 阻断页结束等都会追加记录，即任务的执行与修改历史）。
  Future<void> _showTaskDetail(AgentTask t) async {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme;

    Widget metaRow(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: Text(label,
                    style: textStyle.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(value,
                    style: textStyle.bodySmall
                        ?.copyWith(color: colorScheme.onSurface)),
              ),
            ],
          ),
        );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(t.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_statusLabel(t.status),
                  style: textStyle.labelSmall
                      ?.copyWith(color: colorScheme.onSecondaryContainer)),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                metaRow('类型', _kindLabel(t.kind)),
                metaRow('动作', t.action),
                if (t.priority != 0) metaRow('优先级', '${t.priority}'),
                metaRow('创建', _fmtFull(t.createdAt)),
                if (t.scheduledAt != null)
                  metaRow('定时执行', _fmtFull(t.scheduledAt!)),
                metaRow('最后更新', _fmtFull(t.updatedAt)),
                const Divider(height: 16),
                if (t.params.isNotEmpty) ...[
                  Text('参数（智能体打算做什么）', style: textStyle.titleSmall),
                  const SizedBox(height: 4),
                  SelectableText(
                    jsonEncode(t.params),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const Divider(height: 16),
                ],
                Text('执行记录（${t.feedback.length} 条）',
                    style: textStyle.titleSmall),
                const SizedBox(height: 4),
                if (t.feedback.isEmpty)
                  Text('暂无记录',
                      style: textStyle.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant))
                else
                  ...t.feedback.map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(f,
                          style: const TextStyle(
                              fontSize: 11, fontFamily: 'monospace')),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  String _fmtDecisionTime(Object? iso) {
    final t = DateTime.tryParse(iso?.toString() ?? '');
    if (t == null) return '';
    return '${t.month}/${t.day} ${_fmtHm(t)}';
  }

  /// 按日期分组展示输入/输出日志（新日期在上，组内新记录在上）。
  ///
  /// 每条记录一行：时刻 + 摘要 + 结果徽标，可展开「输入（上下文/反馈）」与
  /// 「输出（决策/任务）」原文。kind=decision 为信号→计划，kind=feedback 为
  /// 用户反馈→大脑判定。
  List<Widget> _buildDateGroups(
      ColorScheme colorScheme, TextTheme textStyle) {
    final groups = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final rec in _decisionLog) {
      final t = DateTime.tryParse(rec['time']?.toString() ?? '');
      if (t == null) continue;
      final key =
          '${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}';
      if (!groups.containsKey(key)) {
        groups[key] = [];
        order.add(key);
      }
      groups[key]!.add(rec);
    }
    return [
      for (final key in order) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text(
            _fmtDateTitle(groups[key]!.first) ?? key,
            style: textStyle.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        ...groups[key]!.map(
          (rec) => _recordTile(rec, colorScheme, textStyle),
        ),
        const Divider(height: 12),
      ],
    ];
  }

  /// 日期标题：8月16日 星期日（带星期）。
  String? _fmtDateTitle(Map<String, dynamic> rec) {
    final t = DateTime.tryParse(rec['time']?.toString() ?? '');
    if (t == null) return null;
    const wd = ['一', '二', '三', '四', '五', '六', '日'];
    return '${t.month}月${t.day}日 星期${wd[t.weekday - 1]}';
  }

  /// 一条输入/输出记录：时刻 + 摘要 + 结果徽标 + 可展开输入/输出。
  Widget _recordTile(Map<String, dynamic> rec, ColorScheme colorScheme,
      TextTheme textStyle) {
    final isFeedback = rec['kind'] == 'feedback';
    final noop = rec['noop'] == true;
    final t = DateTime.tryParse(rec['time']?.toString() ?? '');
    final icon = isFeedback
        ? Icons.chat_bubble_outline
        : (noop ? Icons.info_outline : Icons.assignment_outlined);
    final iconColor = isFeedback
        ? colorScheme.tertiary
        : (noop ? colorScheme.tertiary : colorScheme.primary);
    final badge = isFeedback
        ? '反馈'
        : (noop ? '无需行动' : '生成 ${rec['taskCount'] ?? 0} 个任务');
    final summary = rec['summary']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${t != null ? _fmtHm(t) : ''} · $summary',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle.bodySmall,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge,
                    style: textStyle.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
          _ExpandableText(
              label: '输入（上下文/反馈）',
              text: rec['input']?.toString() ?? ''),
          _ExpandableText(
              label: '输出（决策/任务）',
              text: rec['output']?.toString() ?? ''),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.memory, size: 18),
              const SizedBox(width: 8),
              Text('智能体大脑', style: textStyle.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: '刷新',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '手动触发信号（绕过冷却，观察大脑如何规划）',
            style: textStyle.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.cloud_outlined, size: 16),
                label: const Text('模拟天气变化'),
                onPressed: () => _trigger('weather_changed'),
              ),
              ActionChip(
                avatar: const Icon(Icons.edit_note, size: 16),
                label: const Text('模拟日记稳定'),
                onPressed: () => _trigger('diary_stable'),
              ),
              ActionChip(
                avatar: const Icon(Icons.smartphone, size: 16),
                label: const Text('模拟类别变化'),
                onPressed: () => _trigger('usage_category_changed'),
              ),
              ActionChip(
                avatar: const Icon(Icons.psychology, size: 16),
                label: const Text('模拟画像未初始化'),
                onPressed: () => _trigger('profile_uninitialized'),
              ),
              ActionChip(
                avatar: const Icon(Icons.badge_outlined, size: 16),
                label: const Text('模拟缺基础认知'),
                onPressed: () => _trigger('profile_incomplete'),
              ),
              ActionChip(
                avatar: const Icon(Icons.hourglass_bottom, size: 16),
                label: const Text('模拟长期计划回访'),
                onPressed: () => _trigger('longterm_overdue'),
              ),
              ActionChip(
                avatar: const Icon(Icons.task_alt, size: 16),
                label: const Text('模拟任务停滞'),
                onPressed: () => _trigger('task_stall'),
              ),
              ActionChip(
                avatar: const Icon(Icons.nightlight_round, size: 16),
                label: const Text('立即归位'),
                onPressed: _runNightly,
              ),
            ],
          ),
        ),
        // 大脑输入/输出监督：展示送进大脑的上下文与模型原始返回
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('大脑输入/输出（最近一次决策）', style: textStyle.titleSmall),
        ),
        if (_decision == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('暂无决策记录：触发上方任意信号后，这里会展示送入大脑的完整上下文与模型输出',
                style: TextStyle(fontSize: 12)),
          )
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _decision!['noop'] == true
                            ? Icons.info_outline
                            : Icons.check_circle_outline,
                        size: 16,
                        color: _decision!['noop'] == true
                            ? colorScheme.tertiary
                            : colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${_decision!['signalType']} · '
                          '${_fmtDecisionTime(_decision!['time'])}'
                          '${_decision!['noop'] == true ? ' · 判断无需行动' : ' · 生成 ${_decision!['taskCount']} 个任务'}',
                          style: textStyle.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_decision!['summary']?.toString() ?? '',
                      style: textStyle.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  _ExpandableText(
                      label: '输入（送进大脑的上下文）',
                      text: _decision!['input']?.toString() ?? ''),
                  _ExpandableText(
                      label: '输出（模型原始返回）',
                      text: _decision!['output']?.toString() ?? ''),
                ],
              ),
            ),
          ),
        // 智能体输入/输出记录（按日期分组，开发阶段观察「每天有什么输入/输出」）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('智能体输入/输出记录（按日期）', style: textStyle.titleSmall),
        ),
        if (_decisionLog.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
                '暂无记录：大脑每做一次决策、或处理一次用户反馈，都会按日期归档到这里',
                style: TextStyle(fontSize: 12)),
          )
        else
          ..._buildDateGroups(colorScheme, textStyle),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('任务库（进行中）', style: textStyle.titleSmall),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_tasks.isEmpty)
          const ListTile(
            dense: true,
            title: Text('暂无进行中的任务'),
            subtitle: Text('触发信号或添加规则后，大脑会把规划写到这里'),
          )
        else
          ..._tasks.map((t) => ListTile(
                dense: true,
                onTap: () => _showTaskDetail(t),
                leading: Icon(
                  t.action == 'block_screen'
                      ? Icons.lock_clock
                      : t.action == 'tts'
                          ? Icons.volume_up_outlined
                          : Icons.task_alt,
                  size: 20,
                  color: colorScheme.primary,
                ),
                title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${_kindLabel(t.kind)} · ${t.action} · ${t.status}'
                  '${t.scheduledAt != null ? ' @${_fmtHm(t.scheduledAt!)}' : ''}',
                  style: textStyle.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _exec(t),
                      icon: const Icon(Icons.play_arrow, size: 20),
                      tooltip: '立即执行',
                    ),
                    IconButton(
                      onPressed: () => _cancel(t),
                      icon: Icon(Icons.close, size: 20, color: colorScheme.error),
                      tooltip: '取消',
                    ),
                  ],
                ),
              )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('任务执行记录（最近 10 条）', style: textStyle.titleSmall),
        ),
        if (_doneTasks.isEmpty)
          const ListTile(
            dense: true,
            title: Text('暂无已执行任务'),
            subtitle: Text('任务执行完成或用户回应后，会记录到这里'),
          )
        else
          ..._doneTasks.map((t) => ListTile(
                dense: true,
                onTap: () => _showTaskDetail(t),
                leading: Icon(
                  Icons.done_all,
                  size: 20,
                  color: colorScheme.primary,
                ),
                title:
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  t.feedback.isEmpty
                      ? '${_kindLabel(t.kind)} · ${t.status}'
                      : '${_kindLabel(t.kind)} · ${t.feedback.last}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant),
                ),
                trailing: Text(
                  _fmtHm(t.updatedAt),
                  style: textStyle.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant),
                ),
              )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Text('用户规则', style: textStyle.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: _addRule,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
        ),
        if (_rules.isEmpty)
          const ListTile(
            dense: true,
            title: Text('暂无自定义规则'),
            subtitle: Text('规则会作为大脑上下文的输入，自动转化为任务规划'),
          )
        else
          ..._rules.map((r) => ListTile(
                dense: true,
                leading: const Icon(Icons.rule, size: 20),
                title: Text(r),
                trailing: IconButton(
                  onPressed: () async {
                    await logic.removeRule(r);
                    await _refresh();
                  },
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: colorScheme.error),
                  tooltip: '删除规则',
                ),
              )),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 可展开/折叠的监督文本块（大脑输入/输出用）。
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.label, required this.text});

  final String label;
  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.primary),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  widget.text.isEmpty ? '（空）' : widget.text,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
