import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:moodiary/common/values/fixed_categories.dart';
import 'package:moodiary/components/base/button.dart';
import 'package:moodiary/components/loading/loading.dart';
import 'package:moodiary/components/tile/setting_tile.dart';
import 'package:moodiary/main.dart';
import 'package:refreshed/refreshed.dart';

import 'category_manager_logic.dart';

class CategoryManagerPage extends StatelessWidget {
  const CategoryManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = Bind.find<CategoryManagerLogic>();
    final state = Bind.find<CategoryManagerLogic>().state;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingFunctionCategoryManage),
        leading: const PageBackButton(),
      ),
      body: Obx(() {
        return !state.isFetching.value
            ? ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: state.categoryList.length,
                onReorder: logic.reorderCategory,
                itemBuilder: (context, index) {
                  final category = state.categoryList[index];
                  final isFixed = FixedCategories.isFixed(category.categoryName);

                  return AdaptiveListTile(
                    key: ValueKey(category.id),
                    title: Row(
                      children: [
                        if (isFixed)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: colorScheme.outline,
                            ),
                          ),
                        Text(category.categoryName),
                      ],
                    ),
                    subtitle: Text(
                      isFixed ? '固定分类' : category.id,
                      style: const TextStyle(fontSize: 8),
                    ),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 固定分类不能编辑
                        if (!isFixed)
                          IconButton(
                            onPressed: () async {
                              final res = await showTextInputDialog(
                                  context: context,
                                  title: l10n.categoryManageEdit,
                                  textFields: [
                                    DialogTextField(
                                      hintText: l10n.categoryManageName,
                                      initialText: category.categoryName,
                                    )
                                  ]);
                              if (res != null) {
                                logic.editCategory(category.id,
                                    text: res.first);
                              }
                            },
                            icon: const Icon(Icons.edit_rounded),
                          ),
                        // 固定分类不能删除
                        if (!isFixed)
                          IconButton(
                            onPressed: () {
                              logic.deleteCategory(category.id);
                            },
                            icon: const Icon(Icons.delete_forever_rounded),
                            color: colorScheme.error,
                          ),
                      ],
                    ),
                  );
                },
              )
            : const Center(
                child: Processing(),
              );
      }),
      floatingActionButton: Obx(() {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: !state.isFetching.value
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    final res = await showTextInputDialog(
                        context: context,
                        title: l10n.categoryManageAdd,
                        textFields: [
                          DialogTextField(
                            hintText: l10n.categoryManageName,
                          )
                        ]);
                    if (res != null) {
                      logic.addCategory(text: res.first);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text(l10n.categoryManageAdd),
                )
              : const SizedBox.shrink(),
        );
      }),
    );
  }
}
