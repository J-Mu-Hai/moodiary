/// 句子终结符（含单个换行作为软边界），供分块与拆句共用
const String kSentenceEnds = '。！？.!?…\n';

/// 输出拆分器 — 把 AI 的长回复拆成有节奏的片段
enum SplitStyle { natural, asWhole }

class OutputSplitter {
  /// 自然拆分：短句合并，保证每条至少有一定信息量
  static List<String> split(String text, {SplitStyle style = SplitStyle.natural}) {
    if (text.isEmpty) return [];
    switch (style) {
      case SplitStyle.natural:
        return _splitNatural(text);
      case SplitStyle.asWhole:
        return [text];
    }
  }

  /// 自然拆分策略：
  /// 1. 先按段落拆分
  /// 2. 段落内按句子拆
  /// 3. 太短的句子和上一句合并
  static List<String> _splitNatural(String text) {
    // 先按双换行拆段落
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) return [text];

    final result = <String>[];
    for (final para in paragraphs) {
      final chunks = _splitParagraph(para);
      result.addAll(chunks);
    }

    return result;
  }

  /// 把一个段落拆成合适的片段
  static List<String> _splitParagraph(String text) {
    if (text.length <= 60) return [text]; // 短段落不拆

    // 按句子边界拆
    final raw = _splitBySentence(text);
    if (raw.length <= 2) return [text]; // 只有 1-2 句也不拆

    // 合并短句，保证每个片段至少有 30 个字或 2 个句子
    final merged = <String>[];
    String current = '';
    for (final s in raw) {
      if (current.isEmpty) {
        current = s;
      } else if (current.length + s.length < 30 || _countSentences(current) < 2) {
        current += s; // 合并到上一句
      } else {
        merged.add(current);
        current = s;
      }
    }
    if (current.isNotEmpty) merged.add(current);

    return merged;
  }

  /// 按句号/问号/感叹号/换行拆分
  static List<String> _splitBySentence(String text) {
    final sentences = <String>[];
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if (kSentenceEnds.contains(text[i])) {
        final sentence = buffer.toString().trim();
        if (sentence.isNotEmpty) {
          sentences.add(sentence);
        }
        buffer.clear();
      }
    }
    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      sentences.add(remaining);
    }
    return sentences;
  }

  /// 统计句子数量（粗略）
  static int _countSentences(String text) {
    return kSentenceEnds.split('').fold(0, (count, c) => count + c.allMatches(text).length) + 1;
  }
}
