import 'package:moodiary/common/models/isar/category.dart';
import 'package:moodiary/common/values/fixed_categories.dart';
import 'package:moodiary/pages/home/diary/diary_logic.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:refreshed/refreshed.dart';

import 'category_manager_state.dart';

class CategoryManagerLogic extends GetxController {
  final CategoryManagerState state = CategoryManagerState();

  late DiaryLogic diaryLogic = Bind.find<DiaryLogic>();

  @override
  void onReady() async {
    await getCategory();
    super.onReady();
  }

  Future<void> getCategory() async {
    state.isFetching.value = true;
    state.categoryList.value = await IsarUtil.getAllCategoryAsync();
    state.isFetching.value = false;
  }

  Future<void> addCategory({required String text}) async {
    if (text.isNotEmpty) {
      if (await IsarUtil.insertACategory(Category()..categoryName = text)) {
        await getCategory();
        await diaryLogic.updateCategory();
      } else {
        await getCategory();
        await diaryLogic.updateCategory();
        NoticeUtil.showToast('分类已存在，已自动添加后缀');
      }
    } else {
      NoticeUtil.showToast('分类名称不能为空');
    }
  }

  Future<void> editCategory(String categoryId, {required String text}) async {
    if (text.isNotEmpty) {
      await IsarUtil.updateACategory(Category()
        ..id = categoryId
        ..categoryName = text);
      await getCategory();
      await diaryLogic.updateCategory();
    } else {
      NoticeUtil.showToast('分类名称不能为空');
    }
  }

  Future<void> deleteCategory(String id) async {
    // 先找分类名称，判断是否为固定分类
    final category = state.categoryList.firstWhereOrNull((c) => c.id == id);
    if (category != null && FixedCategories.isFixed(category.categoryName)) {
      NoticeUtil.showToast('固定分类不可删除');
      return;
    }
    if (await IsarUtil.deleteACategory(id)) {
      NoticeUtil.showToast('删除成功');
      await getCategory();
      await diaryLogic.updateCategory();
    } else {
      NoticeUtil.showToast('删除失败，当前分类下还有日记');
    }
  }

  /// 拖拽重排分类
  void reorderCategory(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final list = List<Category>.from(state.categoryList);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state.categoryList.value = list;
    // TODO: 保存排序顺序到 SharedPreferences 或 Isar
  }
}
