import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary/services/task_doc_parser.dart';

const sampleDoc = '''---
project: 算法竞赛
type: task-planning
created: 2026-08-06
deadline: 2026-09-01
ai-mode: active
---

## 📌 项目目标
> 通过算法竞赛提升能力

## 🎯 里程碑
- [x] 基础算法复习 (2026-07-15)
- [ ] 模拟赛训练 (2026-08-01)

## 📝 当前阶段任务
- [ ] 完成动态规划专题
  - [ ] 看教程视频
  - [x] 做10道例题
- [ ] 刷完 LeetCode 50 题

## 📓 关联日记
> 📓 2026-06-15：我发现了一些事

## 🤖 AI 建议记录
> 2026-08-06：建议降低刷题量
''';

void main() {
  group('TaskDocParser.parse', () {
    test('解析 YAML 与各节', () {
      final doc = TaskDocParser.parse(sampleDoc);

      expect(doc.project, '算法竞赛');
      expect(doc.type, 'task-planning');
      expect(doc.deadline, '2026-09-01');
      expect(doc.aiMode, 'active');
      expect(doc.goal, '通过算法竞赛提升能力');
      expect(doc.milestones.length, 2);
      expect(doc.milestones[0].checked, isTrue);
      expect(doc.milestones[1].date, '2026-08-01');
      expect(doc.tasks.length, 4);
      expect(doc.diaryRefs, ['2026-06-15：我发现了一些事']);
      expect(doc.aiNotes, ['2026-08-06：建议降低刷题量']);
    });

    test('任务嵌套层级与勾选状态', () {
      final doc = TaskDocParser.parse(sampleDoc);

      expect(doc.tasks[0].level, 0);
      expect(doc.tasks[0].checked, isFalse);
      expect(doc.tasks[1].level, 1); // 子任务缩进 2 空格
      expect(doc.tasks[2].level, 1);
      expect(doc.tasks[2].checked, isTrue);
      expect(doc.tasks[3].level, 0);
    });

    test('进度计算', () {
      final doc = TaskDocParser.parse(sampleDoc);
      expect(doc.totalTasks, 4);
      expect(doc.completedTasks, 1);
      expect(doc.progress, closeTo(1 / 4, 0.001));
    });

    test('无 YAML 也能解析', () {
      final doc = TaskDocParser.parse('## 📝 当前阶段任务\n- [ ] 任务A');
      expect(doc.project, '');
      expect(doc.tasks.length, 1);
      expect(doc.tasks[0].text, '任务A');
    });
  });

  group('TaskDocParser.stripYamlFrontmatter', () {
    test('剥离 YAML 块，保留正文', () {
      final stripped = TaskDocParser.stripYamlFrontmatter(sampleDoc);
      expect(stripped, isNot(contains('project:')));
      expect(stripped, isNot(contains('task-planning')));
      expect(stripped, contains('## 📌 项目目标'));
      expect(stripped, contains('- [ ] 完成动态规划专题'));
    });

    test('非 YAML 文档原样返回', () {
      final md = '## 普通\n正文内容';
      expect(TaskDocParser.stripYamlFrontmatter(md), md);
    });
  });

  group('TaskDocParser guide-stage', () {
    test('无 guide-stage 键时字段为空字符串', () {
      final doc = TaskDocParser.parse(sampleDoc);
      expect(doc.guideStage, '');
    });

    test('有 guide-stage 键时解析', () {
      final withStage = sampleDoc.replaceFirst(
        'ai-mode: active',
        'ai-mode: active\nguide-stage: 3',
      );
      final doc = TaskDocParser.parse(withStage);
      expect(doc.guideStage, '3');
    });
  });

  group('TaskDocParser.setYamlValue', () {
    test('替换已有键行', () {
      final out = TaskDocParser.setYamlValue(sampleDoc, 'guide-stage', '2');
      expect(TaskDocParser.parse(out).guideStage, '2');
      expect(out, contains('guide-stage: 2'));
    });

    test('无该键时插入 YAML 首行', () {
      final out = TaskDocParser.setYamlValue(sampleDoc, 'guide-stage', '4');
      expect(TaskDocParser.parse(out).guideStage, '4');
    });

    test('无 YAML 块时生成最小前缀', () {
      final out = TaskDocParser.setYamlValue(
        '## 📝 当前阶段任务\n- [ ] 任务A',
        'guide-stage',
        '1',
      );
      expect(TaskDocParser.parse(out).guideStage, '1');
      expect(out, startsWith('---\n'));
    });
  });

  group('TaskDocParser.upsertSection', () {
    test('节存在时整节替换（含标题自动补 ##）', () {
      final out = TaskDocParser.upsertSection(
        sampleDoc,
        '## 📌 项目目标',
        '> 通过算法竞赛成为省一',
      );
      final doc = TaskDocParser.parse(out);
      expect(doc.goal, '通过算法竞赛成为省一');
      // 目标节后的里程碑节仍保留
      expect(doc.milestones.length, 2);
    });

    test('节不存在时追加到文末', () {
      final out = TaskDocParser.upsertSection(
        sampleDoc,
        '## 💡 动机卡片',
        '> 想进大厂\n> 证明自己',
      );
      expect(out, endsWith('## 💡 动机卡片\n> 想进大厂\n> 证明自己\n'));
    });

    test('多行 body 逐行写入', () {
      final out = TaskDocParser.upsertSection(
        '## A\n旧内容1\n旧内容2\n## B\n保留',
        '## A',
        '新内容',
      );
      expect(out, contains('## A\n新内容\n## B\n保留'));
    });
  });

  group('TaskDocParser 变更操作', () {
    test('toggleTask 翻转指定行', () {
      final out = TaskDocParser.toggleTask(sampleDoc, 16);
      final doc = TaskDocParser.parse(out);
      expect(doc.tasks[0].checked, isTrue); // 第16行是 tasks[0]

      final out2 = TaskDocParser.toggleTask(out, 16);
      expect(TaskDocParser.parse(out2).tasks[0].checked, isFalse);
    });

    test('setDeadline 替换现有行', () {
      final out = TaskDocParser.setDeadline(sampleDoc, '2026-10-01');
      expect(TaskDocParser.parse(out).deadline, '2026-10-01');
    });

    test('setDeadline 无 deadline 行时插入 YAML', () {
      final noDeadline =
          sampleDoc.replaceFirst('deadline: 2026-09-01\n', '');
      final out = TaskDocParser.setDeadline(noDeadline, '2026-10-01');
      expect(TaskDocParser.parse(out).deadline, '2026-10-01');
    });

    test('insertTask 在任务节下插入', () {
      final out = TaskDocParser.insertTask(sampleDoc, '学习线段树');
      final doc = TaskDocParser.parse(out);
      expect(doc.tasks.length, 5);
      expect(doc.tasks.last.text, '学习线段树');
      expect(doc.tasks.last.level, 0);
    });

    test('insertTask 作为子任务缩进', () {
      final out = TaskDocParser.insertTask(sampleDoc, '做5道例题',
          asSubtask: true);
      final doc = TaskDocParser.parse(out);
      expect(doc.tasks.last.text, '做5道例题');
      expect(doc.tasks.last.level, 1);
    });

    test('insertTask 无任务节时新建', () {
      final out = TaskDocParser.insertTask('---\nproject: X\n---\n\n## 别的\n',
          '任务A');
      final doc = TaskDocParser.parse(out);
      expect(doc.tasks.length, 1);
      expect(doc.tasks.first.text, '任务A');
    });

    test('addAiNote 追加到 AI 建议节', () {
      final out = TaskDocParser.addAiNote(sampleDoc, '今天状态不错');
      final doc = TaskDocParser.parse(out);
      expect(doc.aiNotes.first, '今天状态不错');
    });

    test('appendText 追加到末尾', () {
      final out = TaskDocParser.appendText(sampleDoc, '## 额外\n内容');
      expect(out, contains('## 额外'));
    });
  });

  group('TaskDocParser.parsePages', () {
    test('无 # 页面 = 单页总览，行为与旧版一致', () {
      final pages = TaskDocParser.parsePages(sampleDoc);
      expect(pages.length, 1);
      expect(pages.first.name, '总览');
      expect(pages.first.doc.tasks.length, 4);
    });

    test('按 # 一级标题拆页', () {
      final multi = '$sampleDoc\n'
          '# 📄 第二周\n'
          '## 📝 当前阶段任务\n'
          '- [ ] 第二周任务\n';
      final pages = TaskDocParser.parsePages(multi);
      expect(pages.length, 2);
      expect(pages[0].name, '总览');
      expect(pages[0].doc.tasks.length, 4); // 第一页含 YAML 与初始任务
      expect(pages[1].name, '📄 第二周');
      expect(pages[1].doc.tasks.length, 1);
      expect(pages[1].doc.tasks.first.text, '第二周任务');
    });

    test('空页（只有标题）也保留', () {
      final multi = '$sampleDoc\n# 📄 空页\n\n# 📄 又一页\n- [ ] 任务X\n';
      final pages = TaskDocParser.parsePages(multi);
      expect(pages.length, 3);
      expect(pages[1].name, '📄 空页');
      expect(pages[1].doc.tasks, isEmpty);
      expect(pages[2].doc.tasks.length, 1);
    });
  });

  group('TaskDoc 计算', () {
    test('deadline 为空时 daysUntilDeadline 为 null', () {
      final doc = TaskDocParser.parse(sampleDoc.replaceFirst(
          'deadline: 2026-09-01', 'deadline: '));
      expect(doc.daysUntilDeadline, isNull);
    });
  });
}
