import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary/common/models/task_guide.dart';
import 'package:moodiary/services/task_guide_service.dart';

void main() {
  group('TaskGuideStage', () {
    test('阶段号与标签映射', () {
      expect(TaskGuideStage.fromNo(1)?.label, '动机洞察');
      expect(TaskGuideStage.fromNo(2)?.label, '目标锚定');
      expect(TaskGuideStage.fromNo(3)?.label, '现状诊断');
      expect(TaskGuideStage.fromNo(4)?.label, '可行性分析');
      expect(TaskGuideStage.fromNo(5)?.label, '最小可执行单位');
      expect(TaskGuideStage.fromNo(6)?.label, '第一周反思');
      expect(TaskGuideStage.fromNo(7)?.label, '21天反思');
    });

    test('输出物章节标题带 ## 前缀', () {
      expect(TaskGuideStage.motivation.sectionTitle, '## 💡 动机卡片');
      expect(TaskGuideStage.unit.sectionTitle, '## 🗓️ 第一周执行卡');
      expect(TaskGuideStage.reflectDay21.sectionTitle, '## 🌱 21天反思报告');
    });

    test('范围外返回 null，完成号是 8', () {
      expect(TaskGuideStage.fromNo(0), isNull);
      expect(TaskGuideStage.fromNo(8), isNull);
      expect(guideStageDone, 8);
    });
  });

  group('TaskGuideService.parseGuideComplete', () {
    test('合法回调', () {
      final raw = '回答内容\n[[CALL:guideComplete|'
          '{"stage":1,"nextStage":2,"section":"## 💡 动机卡片",'
          '"output":"动机：想进大厂","summary":"动机清晰"}]]';
      final c = TaskGuideService.parseGuideComplete(raw);
      expect(c, isNotNull);
      expect(c!.stage, 1);
      expect(c.nextStage, 2);
      expect(c.section, '## 💡 动机卡片');
      expect(c.output, '动机：想进大厂');
      expect(c.summary, '动机清晰');
    });

    test('output 含嵌套 {} 也能解析', () {
      final raw = '[[CALL:guideComplete|'
          '{"stage":2,"nextStage":3,"section":"## 🎯 目标锚定书",'
          '"output":"目标：{省一} 权重 {0.5}","summary":"OK"}]]';
      final c = TaskGuideService.parseGuideComplete(raw);
      expect(c, isNotNull);
      expect(c!.stage, 2);
      expect(c.output, '目标：{省一} 权重 {0.5}');
    });

    test('无回调返回 null', () {
      expect(TaskGuideService.parseGuideComplete('只是普通回答'), isNull);
    });

    test('乱码 JSON 静默返回 null', () {
      final raw = '[[CALL:guideComplete|{"stage":1]]';
      expect(TaskGuideService.parseGuideComplete(raw), isNull);
    });
  });

  group('TaskGuideService.parseActions / stripActionMarkers', () {
    test('解析多个 ACTION 标记', () {
      final content = '要不要加个任务？\n'
          '[[ACTION:addTask|背单词]]\n'
          '[[ACTION:setDeadline|2026-09-01]]';
      final actions = TaskGuideService.parseActions(content);
      expect(actions.length, 2);
      expect(actions[0].op, 'addTask');
      expect(actions[0].payload, '背单词');
      expect(actions[1].op, 'setDeadline');
      expect(actions[1].payload, '2026-09-01');
    });

    test('剥离标记保留正文', () {
      final stripped =
          TaskGuideService.stripActionMarkers('看这个\n[[ACTION:addTask|X]]\n做完');
      expect(stripped, isNot(contains('ACTION')));
      expect(stripped, contains('看这个'));
      expect(stripped, contains('做完'));
    });

    test('guideComplete 不误配为 ACTION', () {
      final raw = '[[CALL:guideComplete|{"stage":1}]]';
      expect(TaskGuideService.parseActions(raw), isEmpty);
    });
  });
}
