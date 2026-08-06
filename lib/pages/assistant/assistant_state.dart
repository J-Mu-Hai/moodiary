import 'package:moodiary/common/values/keyboard_state.dart';
import 'package:refreshed/refreshed.dart';

class AssistantState {
  late RxList messages; // List<AIMessage>

  late RxString currentProviderId;
  late RxString currentModel;
  late RxBool diaryAccessEnabled; // AI 是否可读取日记
  late RxBool isTyping; // AI 是否正在输入（显示"正在输入..."）

  late KeyboardState keyboardState;

  AssistantState() {
    messages = <dynamic>[].obs;
    currentProviderId = ''.obs;
    currentModel = ''.obs;
    diaryAccessEnabled = false.obs;
    isTyping = false.obs;
    keyboardState = KeyboardState.closed;
  }
}
