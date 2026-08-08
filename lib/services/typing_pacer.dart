import 'dart:async';

/// AI 回复的"呼吸感"节奏器 —— 按人类打字节奏把句子逐个放上屏。
///
/// 问题：流式接口的 chunk 到达速度远快于人类阅读/打字，句子会一次性
/// 全部上屏，没有呼吸感。本类把"上屏"和"API 到达"解耦：
/// - 每次把一条气泡加入 UI 前调用 [waitBefore]
/// - 距上次上屏不足本句应有的节奏时，补齐等待；API 本身慢则几乎不加延迟
///
/// 用法（在流式循环里）：
/// ```dart
/// final pacer = TypingPacer();
/// for (final b in chunker.add(chunk)) {
///   await pacer.waitBefore(b.length, isFirst: first);
///   // 把 b 加入 UI
/// }
/// ```
class TypingPacer {
  TypingPacer() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  /// 首句前的"思考"停顿（连接耗时已算在内，这里只补一小段）
  static const Duration firstSentenceDelay = Duration(milliseconds: 400);

  /// 单句基础停顿 + 按字数线性累加，上限约 1s。
  /// 30 字句子 ≈ 540ms，80 字句子 ≈ 940ms。
  static Duration sentenceDelay(int charLen) {
    final ms = (300 + charLen * 8).clamp(300, 1000).toInt();
    return Duration(milliseconds: ms);
  }

  /// 等待到本句该上屏的时刻（从上一次上屏起算）。
  /// API 快 → 补足节奏；API 慢 → 几乎不加延迟。
  Future<void> waitBefore(int charLen, {bool isFirst = false}) async {
    final need = isFirst ? firstSentenceDelay : sentenceDelay(charLen);
    final elapsed = _watch.elapsed;
    if (elapsed < need) {
      await Future.delayed(need - elapsed);
    }
    _watch.reset();
  }
}
