import '../common/models/task_plan.dart';

/// 任务规划文档的解析器与文本变更工具（纯 Dart，可单测）。
///
/// 解析约定：
/// - YAML 前置块：首行 `---` 到下一个 `---` 之间的 `key: value`
/// - 章节：`## ` 标题；按标题关键词识别目标/里程碑/任务/日记/AI 建议
/// - 任务：`- [ ]` / `- [x]`，前导空格数决定嵌套层级（2 空格一层）
/// - 里程碑日期：任务文本里的 `(YYYY-MM-DD)`
/// - 日记引用：`> 📓 ...`；目标/AI 建议：`> ...`
class TaskDocParser {
  /// 解析 markdown 任务文档
  static TaskDoc parse(String markdown) {
    final lines = markdown.split('\n');

    // ---- YAML 前置块 ----
    final yamlValues = <String, String>{};
    var inYaml = false;
    for (final line in lines) {
      if (line.trim() == '---') {
        if (inYaml) break;
        inYaml = true;
        continue;
      }
      if (inYaml) {
        final idx = line.indexOf(':');
        if (idx > 0) {
          final k = line.substring(0, idx).trim();
          final v = line.substring(idx + 1).trim();
          if (k.isNotEmpty && v.isNotEmpty) yamlValues[k] = v;
        }
      }
    }

    // ---- 章节与条目 ----
    final milestones = <TaskItem>[];
    final tasks = <TaskItem>[];
    final diaryRefs = <String>[];
    final aiNotes = <String>[];
    final goalBuf = StringBuffer();
    var section = '';

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      final heading = RegExp(r'^#{1,6}\s+(.+)\s*$').firstMatch(line);
      if (heading != null) {
        section = heading.group(1)!.trim();
        continue;
      }

      // 任务行 - [ ] / - [x]
      final taskMatch =
          RegExp(r'^(\s*)-\s+\[( |x|X)\]\s*(.*)$').firstMatch(line);
      if (taskMatch != null) {
        final level = taskMatch.group(1)!.length ~/ 2;
        final checked = taskMatch.group(2)!.toLowerCase() == 'x';
        final text = taskMatch.group(3)!.trim();
        String? date;
        final dm = RegExp(r'\((\d{4}-\d{2}-\d{2})\)').firstMatch(text);
        if (dm != null) date = dm.group(1);
        final item = TaskItem(
          text: text,
          checked: checked,
          level: level,
          srcLine: i,
          date: date,
        );
        if (section.contains('里程碑')) {
          milestones.add(item);
        } else {
          tasks.add(item);
        }
        continue;
      }

      // 目标引用块
      if (section.contains('目标') && trimmed.startsWith('>')) {
        final content = _stripQuote(trimmed);
        if (content.isNotEmpty) {
          if (goalBuf.isNotEmpty) goalBuf.write('\n');
          goalBuf.write(content);
        }
        continue;
      }
      // 日记引用
      if (section.contains('日记') && trimmed.startsWith('>')) {
        final content =
            _stripQuote(trimmed).replaceFirst(RegExp(r'^📓\s*'), '');
        if (content.isNotEmpty) diaryRefs.add(content);
        continue;
      }
      // AI 建议记录
      if (section.contains('AI 建议') && trimmed.startsWith('>')) {
        final content = _stripQuote(trimmed);
        if (content.isNotEmpty) aiNotes.add(content);
        continue;
      }
    }

    return TaskDoc(
      project: yamlValues['project'] ?? '',
      type: yamlValues['type'] ?? '',
      created: yamlValues['created'] ?? '',
      deadline: yamlValues['deadline'] ?? '',
      aiMode: yamlValues['ai-mode'] ?? '',
      goal: goalBuf.toString().trim(),
      milestones: milestones,
      tasks: tasks,
      diaryRefs: diaryRefs,
      aiNotes: aiNotes,
      raw: markdown,
    );
  }

  /// 按一级标题 `# 页面名` 把文档拆成多页。
  /// 第一个 `# ` 之前的内容（含 YAML）作为"总览"页；
  /// 没有 `# ` 时整篇作为单页，行为与旧版一致。
  static List<TaskPage> parsePages(String markdown) {
    final pages = <TaskPage>[];
    final lines = markdown.split('\n');
    String? currentName;
    final buf = StringBuffer();

    void flush() {
      final raw = buf.toString();
      final trimmed = raw.trim();
      if (trimmed.isEmpty && currentName == null) return;
      pages.add(TaskPage(
        name: currentName ?? '总览',
        raw: raw,
        doc: parse(raw),
      ));
      buf.clear();
    }

    for (final line in lines) {
      final m = RegExp(r'^#\s+(.+)\s*$').firstMatch(line);
      if (m != null) {
        flush();
        currentName = m.group(1)!.trim();
      } else {
        buf.writeln(line);
      }
    }
    flush();

    if (pages.isEmpty) {
      pages.add(TaskPage(name: '总览', raw: markdown, doc: parse(markdown)));
    }
    return pages;
  }

  /// 去掉引用行前缀（`> ` 或 `>`）
  static String _stripQuote(String line) {
    return line.startsWith('> ')
        ? line.substring(2).trim()
        : line.substring(1).trim();
  }

  /// 翻转指定源行（0-based）的任务勾选，返回新 markdown
  static String toggleTask(String markdown, int srcLine) {
    final lines = markdown.split('\n');
    if (srcLine < 0 || srcLine >= lines.length) return markdown;
    final m = RegExp(r'^(\s*-\s+\[)( |x|X)(\]\s*.*)$').firstMatch(lines[srcLine]);
    if (m == null) return markdown;
    final newChecked = m.group(2)!.toLowerCase() == 'x' ? ' ' : 'x';
    lines[srcLine] = '${m.group(1)}$newChecked${m.group(3)}';
    return lines.join('\n');
  }

  /// 在「当前阶段任务」节下插入任务项。
  /// [asSubtask] 为 true 时作为子任务（缩进 2 空格）。
  /// 没有该节时追加到文档末尾并新建节。
  static String insertTask(String markdown, String item,
      {bool asSubtask = false}) {
    final lines = markdown.split('\n');
    var sectionStart = -1;
    var lastTaskLine = -1;
    String? section;
    for (var i = 0; i < lines.length; i++) {
      final h = RegExp(r'^#{1,6}\s+(.+)\s*$').firstMatch(lines[i]);
      if (h != null) {
        section = h.group(1)!.trim();
        if (section.contains('当前阶段')) sectionStart = i;
        continue;
      }
      if (section != null && section.contains('当前阶段')) {
        if (RegExp(r'^\s*-\s+\[[ xX]\]').hasMatch(lines[i])) lastTaskLine = i;
      }
    }

    if (sectionStart < 0) {
      return '${markdown.trimRight()}\n\n## 📝 当前阶段任务\n- [ ] $item\n';
    }
    final newLine = '${asSubtask ? '  ' : ''}- [ ] $item';
    final insertAt = lastTaskLine >= 0 ? lastTaskLine + 1 : sectionStart + 1;
    lines.insert(insertAt, newLine);
    return lines.join('\n');
  }

  /// 在文档末尾追加文本
  static String appendText(String markdown, String text) {
    final t = text.trim();
    return t.isEmpty ? markdown : '${markdown.trimRight()}\n\n$t';
  }

  /// 修改 YAML deadline 行；没有则插入；没有 YAML 则生成最小 YAML
  static String setDeadline(String markdown, String date) {
    final lines = markdown.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (RegExp(r'^deadline:\s*.*$').hasMatch(lines[i])) {
        lines[i] = 'deadline: $date';
        return lines.join('\n');
      }
    }
    if (lines.isNotEmpty && lines[0].trim() == '---') {
      lines.insert(1, 'deadline: $date');
      return lines.join('\n');
    }
    final now = DateTime.now();
    final created = _fmtDate(now);
    return '---\nproject: 新项目\ntype: task-planning\ncreated: $created\n'
        'deadline: $date\nai-mode: active\n---\n\n$markdown';
  }

  /// 追加一条 AI 建议记录到「AI 建议记录」节
  static String addAiNote(String markdown, String text) {
    final note = '> $text';
    final lines = markdown.split('\n');
    var sectionStart = -1;
    String? section;
    for (var i = 0; i < lines.length; i++) {
      final h = RegExp(r'^#{1,6}\s+(.+)\s*$').firstMatch(lines[i]);
      if (h != null) {
        section = h.group(1)!.trim();
        if (section.contains('AI 建议')) sectionStart = i;
        continue;
      }
    }
    if (sectionStart >= 0) {
      lines.insert(sectionStart + 1, note);
      return lines.join('\n');
    }
    return '${markdown.trimRight()}\n\n## 🤖 AI 建议记录\n$note\n';
  }

  /// 新建任务文档的基础模板（含 YAML + 五节）
  static String buildNewDocTemplate({String project = '新项目'}) {
    final now = DateTime.now();
    final today = _fmtDate(now);
    return '---\n'
        'project: $project\n'
        'type: task-planning\n'
        'created: $today\n'
        'deadline: \n'
        'ai-mode: active\n'
        '---\n'
        '\n'
        '## 📌 项目目标\n'
        '> \n'
        '\n'
        '## 🎯 里程碑\n'
        '- [ ] 阶段一 ($today)\n'
        '- [ ] 阶段二 \n'
        '\n'
        '## 📝 当前阶段任务\n'
        '- [ ] \n'
        '\n'
        '## 📓 关联日记\n'
        '> 📓 \n'
        '\n'
        '## 🤖 AI 建议记录\n'
        '> \n';
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
