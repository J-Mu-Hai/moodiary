import 'package:moodiary/common/values/keyboard_state.dart';
import 'package:refreshed/refreshed.dart';

class AssistantState {
  late RxList messages; // List<AIMessage>

  late RxString currentProviderId;
  late RxString currentModel;
  late RxBool diaryAccessEnabled; // AI 是否可读取日记

  late KeyboardState keyboardState;

  AssistantState() {
    messages = <dynamic>[].obs;
    currentProviderId = ''.obs;
    currentModel = ''.obs;
    diaryAccessEnabled = false.obs;
    keyboardState = KeyboardState.closed;
  }
}
