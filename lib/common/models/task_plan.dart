/// 任务规划文档的数据模型。
///
/// 由 [TaskDocParser] 从 markdown 文本解析而来，供渲染视图、右侧状态栏、
/// AI 顾问共用。

/// 单个任务 / 里程碑条目
class TaskItem {
  TaskItem({
    required this.text,
    required this.checked,
    required this.level,
    required this.srcLine,
    this.date,
  });

  /// 任务文本
  final String text;

  /// 是否完成（- [x]）
  final bool checked;

  /// 嵌套层级（每 2 个空格缩进一层，顶层为 0）
  final int level;

  /// 在原始 markdown 中的行号（0-based），用于勾选翻转
  final int srcLine;

  /// 里程碑日期（从文本 `(YYYY-MM-DD)` 提取），普通任务为 null
  final String? date;
}

/// 一页（一级标题 `# 页面名` 划分的一段内容）
class TaskPage {
  TaskPage({required this.name, required this.raw, required this.doc});

  /// 页面名（`# ` 后的文字）
  final String name;

  /// 该页的原始 markdown（不含页标题行）
  final String raw;

  /// 该页解析出的任务文档（无 YAML 时字段为空）
  final TaskDoc doc;
}

/// 一个任务文档的完整解析结果
class TaskDoc {
  TaskDoc({
    this.project = '',
    this.type = '',
    this.created = '',
    this.deadline = '',
    this.aiMode = '',
    this.goal = '',
    this.milestones = const [],
    this.tasks = const [],
    this.diaryRefs = const [],
    this.aiNotes = const [],
    this.raw = '',
  });

  /// YAML project
  final String project;

  /// YAML type
  final String type;

  /// YAML created
  final String created;

  /// YAML deadline（YYYY-MM-DD，可为空）
  final String deadline;

  /// YAML ai-mode
  final String aiMode;

  /// 📌 项目目标的引用块内容
  final String goal;

  /// 🎯 里程碑
  final List<TaskItem> milestones;

  /// 📝 当前阶段任务
  final List<TaskItem> tasks;

  /// 📓 关联日记引用
  final List<String> diaryRefs;

  /// 🤖 AI 建议记录
  final List<String> aiNotes;

  /// 原始 markdown
  final String raw;

  int get totalTasks => tasks.length;

  int get completedTasks => tasks.where((t) => t.checked).length;

  /// 进度 0.0 ~ 1.0
  double get progress => totalTasks == 0 ? 0 : completedTasks / totalTasks;

  /// 距截止天数（正=剩余，负=已过）；未设置 deadline 返回 null
  int? get daysUntilDeadline {
    final d = DateTime.tryParse(deadline);
    if (d == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(d.year, d.month, d.day).difference(today).inDays;
  }

  /// 滞后天数：最早的未完成且日期已过的里程碑超出今天的天数
  int get overdueDays {
    var maxOverdue = 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final m in milestones) {
      if (m.checked || m.date == null) continue;
      final md = DateTime.tryParse(m.date!);
      if (md == null) continue;
      final diff = today
          .difference(DateTime(md.year, md.month, md.day))
          .inDays;
      if (diff > maxOverdue) maxOverdue = diff;
    }
    return maxOverdue;
  }
}

/// 引导标签按钮对应的 markdown 模板
enum TaskTag {
  goal('📌 目标', '## 📌 项目目标\n> \n'),
  milestone('🎯 里程碑', '## 🎯 里程碑\n- [ ] 阶段一 (YYYY-MM-DD)\n- [ ] 阶段二 (YYYY-MM-DD)\n'),
  task('✅ 任务', '- [ ] \n'),
  deadline('📅 截止', '**截止日期：** YYYY-MM-DD\n'),
  diary('🔗 日记', '> 📓 关联日记：\n> \n'),
  ai('🤖 AI', '@AI '),
  page('📄 翻页', '# 📄 新页面\n');

  const TaskTag(this.label, this.template);

  /// 按钮文字
  final String label;

  /// 点击后插入的 markdown 模板
  final String template;
}

/// AI 建议卡片类型
enum TaskCardType { priority, energy, breakdown, diary, warning }

/// 卡片上的一个操作按钮
class TaskAction {
  TaskAction({required this.label, required this.op, this.payload = ''});

  /// 按钮文字
  final String label;

  /// 操作：addTask | append | setDeadline | addAiNote | ignore
  final String op;

  /// 应用内容（任务文本 / markdown 片段 / 日期）
  final String payload;
}

/// 一条 AI 结构化建议卡片
class TaskCardModel {
  TaskCardModel({
    required this.type,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  final TaskCardType type;
  final String title;
  final String content;
  final List<TaskAction> actions;

  String get typeLabel => switch (type) {
        TaskCardType.priority => '优先级',
        TaskCardType.energy => '能量匹配',
        TaskCardType.breakdown => '任务拆解',
        TaskCardType.diary => '日记关联',
        TaskCardType.warning => '预警',
      };
}
