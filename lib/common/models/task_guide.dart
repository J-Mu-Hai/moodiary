/// AI 引导式任务规划的阶段模型。
///
/// 阶段 1..7 依次推进，阶段 8 表示引导完成。每个阶段对应一个
/// 输出物章节（写入右侧文档），[sectionTitle] 与 TaskDocParser.upsertSection
/// 配合使用。

/// 引导完成后的阶段号（guide-stage 写入文档 YAML 的取值）
const int guideStageDone = 8;

/// 7 个引导阶段
enum TaskGuideStage {
  motivation(1, '动机洞察', '## 💡 动机卡片'),
  goal(2, '目标锚定', '## 🎯 目标锚定书'),
  diagnosis(3, '现状诊断', '## 🔍 现状诊断报告'),
  feasibility(4, '可行性分析', '## ⚖️ 可行性评估书'),
  unit(5, '最小可执行单位', '## 🗓️ 第一周执行卡'),
  reflectWeek1(6, '第一周反思', '## 📋 第一周反思'),
  reflectDay21(7, '21天反思', '## 🌱 21天反思报告');

  const TaskGuideStage(this.no, this.label, this.sectionTitle);

  /// 阶段号（1..7）
  final int no;

  /// 阶段标签（用于状态栏 chip）
  final String label;

  /// 输出物章节标题（含 `## ` 前缀）
  final String sectionTitle;

  /// 阶段号 → 枚举；范围外返回 null
  static TaskGuideStage? fromNo(int no) {
    for (final s in values) {
      if (s.no == no) return s;
    }
    return null;
  }
}

/// 阶段完成回调的解析结果（来自 AI 吐出的 `[[CALL:guideComplete|{...}]]`）
class GuideComplete {
  GuideComplete({
    required this.stage,
    required this.nextStage,
    required this.section,
    required this.output,
    required this.summary,
  });

  /// 声称完成的阶段号（须等于当前 guideStage 才生效）
  final int stage;

  /// 下一阶段号（stage+1）
  final int nextStage;

  /// 输出物章节标题（如 `## 💡 动机卡片`）
  final String section;

  /// 输出物正文 markdown
  final String output;

  /// 一句话总结（写进 stageComplete 气泡）
  final String summary;

  factory GuideComplete.fromJson(Map<String, dynamic> json) {
    return GuideComplete(
      stage: json['stage'] as int? ?? 0,
      nextStage: json['nextStage'] as int? ?? 0,
      section: json['section'] as String? ?? '',
      output: json['output'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
    );
  }
}
