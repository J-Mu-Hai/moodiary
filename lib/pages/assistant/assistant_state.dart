import 'package:moodiary/common/values/keyboard_state.dart';
import 'package:refreshed/refreshed.dart';

class AssistantState {
  // 对话消息列表（AIMessage 定义在 ai_provider.dart 中）
  late RxList messages; // List<AIMessage>

  // 当前选中的 Provider ID
  late RxString currentProviderId;

  // 当前选中的模型名
  late RxString currentModel;

  late KeyboardState keyboardState;

  AssistantState() {
    messages = <dynamic>[].obs;
    currentProviderId = ''.obs;
    currentModel = ''.obs;
    keyboardState = KeyboardState.closed;
  }
}
