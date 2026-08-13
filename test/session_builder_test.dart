import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary/common/models/isar/usage_session.dart';
import 'package:moodiary/utils/session_builder.dart';
import 'package:moodiary/utils/session_merger.dart';

void main() {
  final now = DateTime(2026, 8, 13, 12, 0, 0);

  Map<String, dynamic> ev(int t, int type, String pkg) =>
      {'t': t, 'type': type, 'pkg': pkg};

  int ms(int h, int m) => DateTime(2026, 8, 13, h, m).millisecondsSinceEpoch;

  group('buildSessionsFromEvents', () {
    test('同应用内部 activity 切换（PAUSE→同包 RESUME）不切碎会话', () {
      final events = [
        ev(ms(10, 0), UsageEventType.activityResumed, 'com.weixin'),
        // 微信 A 页面 → B 页面：PAUSE 后紧跟同包 RESUME
        ev(ms(10, 1), UsageEventType.activityPaused, 'com.weixin'),
        ev(ms(10, 1, ), UsageEventType.activityResumed, 'com.weixin'),
        ev(ms(10, 3), UsageEventType.activityPaused, 'com.weixin'),
        ev(ms(10, 3), UsageEventType.activityResumed, 'com.weixin'),
        // 真正切到知乎：这次 PAUSE 应该闭合微信会话
        ev(ms(10, 5), UsageEventType.activityPaused, 'com.weixin'),
        ev(ms(10, 5), UsageEventType.activityResumed, 'com.zhihu'),
      ];
      final r = buildSessionsFromEvents(events, now: now);
      expect(r.closed.length, 1, reason: '微信应只有一段会话');
      expect(r.closed.single.packageName, 'com.weixin');
      expect(r.closed.single.start, DateTime.fromMillisecondsSinceEpoch(ms(10, 0)));
      expect(r.closed.single.end, DateTime.fromMillisecondsSinceEpoch(ms(10, 5)));
      expect(r.open?.packageName, 'com.zhihu');
    });

    test('熄屏是真正的结束，即使之后同包 RESUME 也分段', () {
      final events = [
        ev(ms(10, 0), UsageEventType.activityResumed, 'com.weixin'),
        ev(ms(10, 1), UsageEventType.activityPaused, 'com.weixin'),
        ev(ms(10, 1), UsageEventType.screenNonInteractive, 'com.weixin'),
        ev(ms(10, 9), UsageEventType.screenInteractive, 'com.weixin'),
        ev(ms(10, 9), UsageEventType.activityResumed, 'com.weixin'),
      ];
      final r = buildSessionsFromEvents(events, now: now);
      expect(r.closed.length, 1);
      expect(r.open?.packageName, 'com.weixin');
      expect(r.closed.single.end, DateTime.fromMillisecondsSinceEpoch(ms(10, 1)));
    });

    test('跨应用切换照常闭合前一个会话', () {
      final events = [
        ev(ms(10, 0), UsageEventType.activityResumed, 'com.a'),
        ev(ms(10, 2), UsageEventType.activityPaused, 'com.a'),
        ev(ms(10, 2), UsageEventType.activityResumed, 'com.b'),
        ev(ms(10, 4), UsageEventType.activityPaused, 'com.b'),
      ];
      final r = buildSessionsFromEvents(events, now: now);
      expect(r.closed.length, 2);
      expect(r.closed.map((s) => s.packageName), ['com.a', 'com.b']);
    });
  });

  group('mergeAdjacentSessions', () {
    UsageSession ses(String pkg, DateTime start, DateTime end) => UsageSession()
      ..id = '${start.millisecondsSinceEpoch}_$pkg'
      ..start = start
      ..end = end
      ..packageName = pkg
      ..appName = pkg
      ..lastModified = now;

    test('相邻同应用、间隔小合并；间隔大或中间有别的应用不合并', () {
      final list = [
        ses('com.weixin', DateTime(2026, 8, 13, 10, 0), DateTime(2026, 8, 13, 10, 1)),
        ses('com.weixin', DateTime(2026, 8, 13, 10, 1), DateTime(2026, 8, 13, 10, 2)),
        ses('com.zhihu', DateTime(2026, 8, 13, 10, 2), DateTime(2026, 8, 13, 10, 4)),
        // 同应用但被知乎隔开 → 不合并
        ses('com.weixin', DateTime(2026, 8, 13, 10, 4), DateTime(2026, 8, 13, 10, 5)),
        // 同应用但间隔 10 分钟 → 不合并
        ses('com.weixin', DateTime(2026, 8, 13, 10, 15), DateTime(2026, 8, 13, 10, 20)),
      ];
      final merged = mergeAdjacentSessions(list);
      expect(merged.length, 4, reason: '前两段合并成 1，共 4 段');
      expect(merged.first.packageName, 'com.weixin');
      expect(merged.first.end, DateTime(2026, 8, 13, 10, 2), reason: '合并后 end 取最晚');
    });

    test('进行中的会话不参与合并', () {
      final list = [
        ses('com.weixin', DateTime(2026, 8, 13, 10, 0), DateTime(2026, 8, 13, 10, 1)),
        UsageSession()
          ..id = 'open'
          ..start = DateTime(2026, 8, 13, 10, 1)
          ..end = null
          ..packageName = 'com.weixin'
          ..appName = 'com.weixin'
          ..lastModified = now,
      ];
      final merged = mergeAdjacentSessions(list);
      expect(merged.length, 2, reason: 'open 会话单独保留');
      expect(merged.last.isOpen, true);
    });
  });
}
