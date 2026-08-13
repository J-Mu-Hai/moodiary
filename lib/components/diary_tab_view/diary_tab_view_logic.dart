import 'package:moodiary/pages/home/diary/diary_logic.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:refreshed/refreshed.dart';

import 'diary_tab_view_state.dart';

class DiaryTabViewLogic extends GetxController {
  final DiaryTabViewState state = DiaryTabViewState();

  late final DiaryLogic diaryLogic = Bind.find<DiaryLogic>();

  DiaryTabViewLogic({required String? categoryId}) {
    state.categoryId = categoryId;
  }

  @override
  void onReady() async {
    await _getDiary();
    super.onReady();
  }

  Future<void> _getDiary() async {
    state.isFetching.value = true;
    final sw = Stopwatch()..start();
    try {
      state.diaryList.value =
          await IsarUtil.getDiaryByCategory(state.categoryId, 0, state.initLen);
      print('[DIARY] loaded=${state.diaryList.length} cat=${state.categoryId} in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      print('[DIARY] ERROR cat=${state.categoryId}: $e');
    } finally {
      state.isFetching.value = false;
      print('[DIARY] isFetching=false cat=${state.categoryId}');
    }
  }

  Future<void> updateDiary() async {
    state.isFetching.value = true;
    final sw = Stopwatch()..start();
    try {
      state.diaryList.value =
          await IsarUtil.getDiaryByCategory(state.categoryId, 0, state.initLen);
      print('[DIARY] update loaded=${state.diaryList.length} cat=${state.categoryId} in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      print('[DIARY] update ERROR cat=${state.categoryId}: $e');
    } finally {
      state.isFetching.value = false;
      print('[DIARY] update isFetching=false cat=${state.categoryId}');
    }
  }

  Future<void> paginationDiary() async {
    state.diaryList.value += await IsarUtil.getDiaryByCategory(
        state.categoryId, state.diaryList.length, state.pageLen);
  }
}
