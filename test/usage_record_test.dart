import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary/common/models/isar/usage_record.dart';
import 'package:moodiary/utils/usage_aggregator.dart';

void main() {
  group('UsageRecord toJson/fromJson 往返', () {
    test('字段完整保留', () {
      final record = UsageRecord()
        ..id = 'test-id-1'
        ..date = DateTime(2026, 8, 8)
        ..packageName = 'com.example.wechat'
        ..appName = '微信'
        ..foregroundMs = 1234567
        ..lastModified = DateTime(2026, 8, 8, 12, 30);

      final restored = UsageRecord.fromJson(record.toJson());

      expect(restored.id, 'test-id-1');
      expect(restored.date, DateTime(2026, 8, 8));
      expect(restored.packageName, 'com.example.wechat');
      expect(restored.appName, '微信');
      expect(restored.foregroundMs, 1234567);
      expect(restored.lastModified, DateTime(2026, 8, 8, 12, 30));
    });

    test('yMd 索引与 date 一致', () {
      final record = UsageRecord()..date = DateTime(2026, 8, 8);
      expect(record.yMd, '2026/8/8');
    });

    test('id 默认生成且 isarId 稳定', () {
      final a = UsageRecord();
      final b = UsageRecord();
      expect(a.id, isNot(equals(b.id)));
      expect(a.isarId, fastHash(a.id));
    });
  });

  group('groupUsageByDay 聚合', () {
    final now = DateTime(2026, 8, 8, 10, 0, 0);

    test('同一天同包聚合、按天分组', () {
      final result = groupUsageByDay(
        [
          {'dayKey': '2026/8/8', 'packageName': 'com.a', 'appName': 'A', 'totalMs': 1000},
          {'dayKey': '2026/8/8', 'packageName': 'com.b', 'appName': 'B', 'totalMs': 2000},
          {'dayKey': '2026/8/7', 'packageName': 'com.a', 'appName': 'A', 'totalMs': 3000},
        ],
        now: now,
      );

      expect(result.keys, unorderedEquals(['2026/8/8', '2026/8/7']));
      expect(result['2026/8/8']!.length, 2);
      expect(result['2026/8/7']!.single.foregroundMs, 3000);
    });

    test('totalMs<=0 / 非数字被过滤，字符串数字被解析', () {
      final result = groupUsageByDay(
        [
          {'dayKey': '2026/8/8', 'packageName': 'com.a', 'appName': 'A', 'totalMs': 0},
          {'dayKey': '2026/8/8', 'packageName': 'com.b', 'appName': 'B', 'totalMs': -5},
          {'dayKey': '2026/8/8', 'packageName': 'com.c', 'appName': 'C', 'totalMs': '50'},
          {'dayKey': '2026/8/8', 'packageName': 'com.d', 'appName': 'D', 'totalMs': 'abc'},
          {'dayKey': '2026/8/8', 'packageName': 'com.e', 'appName': 'E'},
        ],
        now: now,
      );

      expect(result['2026/8/8']!.length, 1);
      expect(result['2026/8/8']!.single.packageName, 'com.c');
      expect(result['2026/8/8']!.single.foregroundMs, 50);
    });

    test('非法 dayKey 被过滤', () {
      final result = groupUsageByDay(
        [
          {'dayKey': '', 'packageName': 'com.a', 'appName': 'A', 'totalMs': 100},
          {'dayKey': 'garbage', 'packageName': 'com.b', 'appName': 'B', 'totalMs': 200},
          {'dayKey': '2026/8/8', 'packageName': 'com.c', 'appName': 'C', 'totalMs': 300},
        ],
        now: now,
      );

      expect(result.keys, ['2026/8/8']);
    });

    test('date 取当天零点，lastModified 用 now', () {
      final result = groupUsageByDay(
        [
          {'dayKey': '2026/8/8', 'packageName': 'com.a', 'appName': 'A', 'totalMs': 100},
        ],
        now: now,
      );

      final record = result['2026/8/8']!.single;
      expect(record.date, DateTime(2026, 8, 8));
      expect(record.lastModified, now);
      expect(record.yMd, '2026/8/8');
    });

    test('appName 缺失时兜底为空字符串', () {
      final result = groupUsageByDay(
        [
          {'dayKey': '2026/8/8', 'packageName': 'com.a', 'totalMs': 100},
        ],
        now: now,
      );

      expect(result['2026/8/8']!.single.appName, '');
    });
  });

  group('dayStartFromKey', () {
    test('正常解析', () {
      expect(dayStartFromKey('2026/8/8'), DateTime(2026, 8, 8));
      expect(dayStartFromKey('2026/08/08'), DateTime(2026, 8, 8));
    });

    test('非法输入返回 null', () {
      expect(dayStartFromKey(''), isNull);
      expect(dayStartFromKey('2026/8'), isNull);
      expect(dayStartFromKey('a/b/c'), isNull);
      expect(dayStartFromKey('2026/13/8'), DateTime(2027, 1, 8)); // 月份溢出由 DateTime 修正
    });
  });
}
