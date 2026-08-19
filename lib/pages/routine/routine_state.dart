import 'package:moodiary/services/agent_brain/daily_routine.dart';

/// 行为作息页状态。
class RoutineState {
  /// 日常身份（如「学生」）。
  String defaultIdentity = '';

  /// 时段列表（按开始时间升序）。
  List<RoutineSlot> slots = [];

  /// 手机监督摘要（计划 vs 实际观察）。
  String supervisionText = '';

  /// 当前时刻应处于的文本（身份·做什么）。
  String currentSlotText = '';
}
