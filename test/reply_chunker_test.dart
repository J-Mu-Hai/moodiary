import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary/services/reply_chunker.dart';

void main() {
  group('ReplyChunker 句子切分', () {
    test('长句按句子边界切分，短句自动并入', () {
      final chunker = ReplyChunker();

      final emitted = chunker.add('你好。今天天气不错！我们出去玩吧。');

      // "你好。"(3字) 短于 minLen 并入下一句；"我们出去玩吧。"(7字) 留到 finish
      expect(emitted, ['你好。今天天气不错！']);
      expect(chunker.finish(), ['我们出去玩吧。']);
    });

    test('单独一个短句不到 minLen 也最终成泡（微信式）', () {
      final chunker = ReplyChunker();

      expect(chunker.add('嗯。'), isEmpty);
      expect(chunker.finish(), ['嗯。']);
    });

    test('流式逐 chunk 到达时，完整句子即时成泡', () {
      final chunker = ReplyChunker();

      expect(chunker.add('你好。今天天气不错！'), ['你好。今天天气不错！']);
      // 未完成的短句先 hold
      expect(chunker.add('我们出去玩吧。'), isEmpty);
      expect(chunker.finish(), ['我们出去玩吧。']);
    });
  });

  group('ReplyChunker 段落与兜底', () {
    test('\\n\\n 段落硬边界，任何长度都切', () {
      final chunker = ReplyChunker();

      expect(
        chunker.add('第一段内容。\n\n第二段的内容在这里。'),
        ['第一段内容。', '第二段的内容在这里。'],
      );
      expect(chunker.finish(), isEmpty);
    });

    test('超 maxLen 无标点 → 在 maxLen 处强制切', () {
      final chunker = ReplyChunker();

      expect(chunker.add('没' * 70), ['没' * 60]);
      expect(chunker.finish(), ['没' * 10]);
    });

    test('emoji 不被切在代理对中间', () {
      final chunker = ReplyChunker();
      const emoji = '😀';

      expect(chunker.add('a' * 59 + emoji + 'b' * 20), ['a' * 59]);
      expect(chunker.finish(), [emoji + 'b' * 20]);
    });
  });

  group('ReplyChunker CALL 标记处理', () {
    test('CALL 标记从显示文本剔除，保留在 raw', () {
      final chunker = ReplyChunker();

      final emitted = chunker.add('让我查一下 [[CALL:getDiaryByDateRange|{"startDate":"2026-07-01","endDate":"2026-07-07"}]] 好的，我查到了。');

      expect(emitted, ['让我查一下 好的，我查到了。']);
      expect(chunker.raw, contains('[[CALL:getDiaryByDateRange'));
      // 任何显示文本都不含标记
      expect(emitted.join(), isNot(contains('[[')));
      expect(emitted.join(), isNot(contains('CALL:')));
    });

    test('CALL 标记跨多个 chunk 到达也能正确剔除', () {
      final chunker = ReplyChunker();

      expect(chunker.add('让我查一下 [[CALL:getDiary'), isEmpty);
      expect(chunker.add('ByDateRange|{"startDate":"2026-07-01"}'), isEmpty);
      expect(chunker.add(']] 好的，我查到了。'), ['让我查一下 好的，我查到了。']);

      expect(chunker.raw, contains('[[CALL:getDiaryByDateRange|{"startDate":"2026-07-01"}]]'));
      expect(chunker.finish(), isEmpty);
    });

    test('只有 CALL 没有正文 → 无显示气泡，raw 完整', () {
      final chunker = ReplyChunker();

      expect(chunker.add('[[CALL:getTodayPlan|{}]]'), isEmpty);
      expect(chunker.finish(), isEmpty);
      expect(chunker.raw, '[[CALL:getTodayPlan|{}]]');
    });
  });
}
