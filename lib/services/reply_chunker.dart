import 'output_splitter.dart';

/// 增量分块器 — 把流式收到的 AI 回复切分成不同长短的气泡。
///
/// 规则：
/// - 句子边界（。！？!?…\n）→ 切气泡；从第 [minLen] 字起才找边界，短句自动并入下一条
/// - `\n\n` 段落硬边界 → 任何长度都切（保住 markdown 段落结构）
/// - 超 [maxLen] 仍无标点 → 切在最后一个逗号类字符处，否则 [maxLen] 处（避开 emoji 代理对）
/// - `[[CALL:...]]` 视为不可见区域：不写进显示文本、内部不切分，但完整保留在 [raw]
///
/// 用法：
/// ```dart
/// final chunker = ReplyChunker();
/// for (final chunk in stream) {
///   for (final bubble in chunker.add(chunk)) {
///     // 把 bubble 作为一条消息展示
///   }
/// }
/// for (final bubble in chunker.finish()) { /* flush 尾段 */ }
/// final full = chunker.raw; // 含 CALL 标记，供提取函数调用
/// ```
class ReplyChunker {
  ReplyChunker({this.minLen = 8, this.maxLen = 60});

  /// 少于该长度的文本不单独成气泡，与下一段合并（避免"好""嗯"刷屏）
  final int minLen;

  /// 超过该长度仍无句子边界时强制切分
  final int maxLen;

  final StringBuffer _raw = StringBuffer(); // 完整原文（含 CALL）
  final StringBuffer _display = StringBuffer(); // 可见文本（剔除 CALL）
  final StringBuffer _call = StringBuffer(); // 未闭合 [[CALL: 的跨 chunk 暂存
  bool _inCall = false;

  /// 收到的全部原始文本（含 CALL 标记，供提取函数调用）
  String get raw => _raw.toString();

  /// 喂入一段流式 chunk，返回新切出的气泡文本列表
  List<String> add(String chunk) {
    if (chunk.isEmpty) return const [];
    _raw.write(chunk);
    if (_inCall) return _appendCall(chunk);
    _scan(chunk);
    return _tryEmit();
  }

  /// 流结束，flush 剩余缓冲。返回剩余气泡（可能为空）
  List<String> finish() {
    _inCall = false;
    _call.clear();
    final rest = _display.toString().trim();
    _display.clear();
    return rest.isEmpty ? const [] : [rest];
  }

  /// 扫描普通文本：把 [[CALL:...]] 挡在显示之外
  void _scan(String chunk) {
    var rest = chunk;
    while (true) {
      final open = rest.indexOf('[[');
      if (open == -1) {
        _display.write(rest);
        return;
      }
      _display.write(rest.substring(0, open));
      final tail = rest.substring(open);
      final close = tail.indexOf(']]');
      if (close == -1) {
        _inCall = true;
        _call.write(tail);
        return;
      }
      rest = _collapseSepSpace(tail.substring(close + 2));
    }
  }

  /// CALL 标记跨 chunk 到达时，累积到 _call 直到找到 `]]`
  List<String> _appendCall(String chunk) {
    _call.write(chunk);
    final close = _call.toString().indexOf(']]');
    if (close == -1) return const [];
    final leftover = _collapseSepSpace(_call.toString().substring(close + 2));
    _call.clear();
    _inCall = false;
    if (leftover.isNotEmpty) _scan(leftover);
    return _tryEmit();
  }

  /// CALL 标记移除后，若标记前文本以空格结尾、标记后文本以空格开头，合并为一个空格
  String _collapseSepSpace(String text) {
    if (text.startsWith(' ') && _display.toString().endsWith(' ')) {
      return text.substring(1);
    }
    return text;
  }

  /// 尝试切分当前显示缓冲，循环切到无可切为止
  List<String> _tryEmit() {
    final out = <String>[];
    while (true) {
      final text = _display.toString();
      final cut = _findCut(text);
      if (cut == null) return out;
      final seg = text.substring(0, cut).trim();
      _display.clear();
      _display.write(text.substring(cut).trimLeft());
      if (seg.isNotEmpty) out.add(seg);
    }
  }

  /// 返回切分下标（含边界字符），无合适切点返回 null
  int? _findCut(String text) {
    // 1) 段落硬边界
    final para = text.indexOf('\n\n');
    if (para >= 0 && para < maxLen) return para;
    // 2) 句子软边界：从 minLen 起找终结符 → 短句自动并入后续
    for (var i = minLen; i < text.length && i <= maxLen; i++) {
      if (kSentenceEnds.contains(text[i])) return i + 1;
    }
    // 3) maxLen 兜底：切在最后一个逗号类字符，否则 maxLen 处（避开 emoji 代理对）
    if (text.length > maxLen) {
      final head = text.substring(0, maxLen);
      final comma = head.lastIndexOf(RegExp(r'[，,、；;]'));
      return comma > minLen ? comma + 1 : _safeCut(text, maxLen);
    }
    return null;
  }

  /// 避开 emoji 低代理项，防止切在代理对中间
  int _safeCut(String text, int idx) {
    while (idx > 0 &&
        idx < text.length &&
        text.codeUnitAt(idx) >= 0xDC00 &&
        text.codeUnitAt(idx) <= 0xDFFF) {
      idx--;
    }
    return idx;
  }
}
