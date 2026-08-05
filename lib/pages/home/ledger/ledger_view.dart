import 'dart:io';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:moodiary/common/models/isar/expense_record.dart';
import 'package:moodiary/common/values/border.dart';
import 'package:moodiary/common/values/expense_categories.dart';
import 'package:moodiary/components/base/clipper.dart';
import 'package:moodiary/main.dart';
import 'package:refreshed/refreshed.dart';

import 'ledger_logic.dart';

class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = Get.put(LedgerLogic());
    return GetBuilder<LedgerLogic>(builder: (_) {
      final colorScheme = Theme.of(context).colorScheme;
      final textStyle = Theme.of(context).textTheme;
      final size = MediaQuery.sizeOf(context);
      final isWide = size.width >= 600;

    // 格式化金额（分 -> 元）
    String formatAmount(int fen) {
      return (fen / 100).toStringAsFixed(2);
    }

    /// 预算概览卡片
    Widget buildBudgetCard() {
      return Obx(() {
        final budget = logic.state.monthlyBudget.value;
        final spent = logic.state.totalExpense.value;
        final remaining = budget - spent;
        final percent = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
        final isOverBudget = remaining < 0;

        return Card.filled(
          color: colorScheme.surfaceContainerLow,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.ledgerBudgetOverview,
                      style: textStyle.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showBudgetDialog(context, logic),
                      child: Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.ledgerMonthlyBudget,
                            style: textStyle.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            budget > 0
                                ? '\u00A5${formatAmount(budget)}'
                                : l10n.ledgerNotSet,
                            style: textStyle.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.ledgerRemaining,
                            style: textStyle.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            budget > 0
                                ? '${isOverBudget ? '-' : ''}\u00A5${formatAmount(remaining.abs())}'
                                : '\u00A5${formatAmount(spent)}',
                            style: textStyle.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isOverBudget
                                  ? colorScheme.error
                                  : colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (budget > 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: AppBorderRadius.smallBorderRadius,
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        isOverBudget
                            ? colorScheme.error
                            : percent > 0.8
                                ? colorScheme.tertiary
                                : colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.ledgerUsed('${formatAmount(spent)}'),
                        style: textStyle.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${(percent * 100).toStringAsFixed(0)}%',
                        style: textStyle.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      });
    }

    /// 月份选择器
    Widget buildMonthSelector() {
      return Obx(() {
        final current = logic.state.currentMonth.value;
        final monthStr = DateFormat.yMMM(locale.languageCode)
            .format(current);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: logic.previousMonth,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              GestureDetector(
                onTap: () => _showMonthPicker(context, logic),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: AppBorderRadius.mediumBorderRadius,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        monthStr,
                        style: textStyle.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: logic.nextMonth,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        );
      });
    }

    /// 单条支出记录
    Widget buildExpenseItem(ExpenseRecord record, int index) {
      final category = ExpenseCategories.defaults
          .where((c) => c.name == record.category)
          .firstOrNull;

      return Dismissible(
        key: ValueKey(record.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          color: colorScheme.errorContainer,
          child: Icon(Icons.delete_rounded, color: colorScheme.onErrorContainer),
        ),
        onDismissed: (_) => logic.deleteExpense(record.isarId),
        child: Card.outlined(
          color: colorScheme.surfaceContainerLow,
          margin: EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            child: Row(
              children: [
                // 分类图标
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(category?.color ?? 0xFF8D6E63).withAlpha(30),
                    borderRadius: AppBorderRadius.mediumBorderRadius,
                  ),
                  child: Icon(
                    category?.icon ?? Icons.more_horiz_rounded,
                    size: 18,
                    color: Color(category?.color ?? 0xFF8D6E63),
                  ),
                ),
                const SizedBox(width: 12),
                // 分类 + 备注 + 时间
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.category,
                        style: textStyle.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (record.note.isNotEmpty)
                        Text(
                          record.note,
                          style: textStyle.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        DateFormat.Md(locale.languageCode).format(record.time),
                        style: textStyle.labelSmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                // 金额
                Text(
                  '-\u00A5${formatAmount(record.amount)}',
                  style: textStyle.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    /// 支出列表
    Widget buildExpenseList() {
      return Obx(() {
        final records = logic.state.expenseRecords;
        if (records.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 48,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.ledgerNoExpense,
                    style: textStyle.bodyMedium?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: records.length,
          separatorBuilder: (_, __) => const SizedBox(height: 0),
          itemBuilder: (context, index) {
            return buildExpenseItem(records[index], index);
          },
        );
      });
    }

    /// FAB 添加按钮
    Widget buildFab() {
      return Obx(() {
        return Visibility(
          visible: !isWide,
          child: FloatingActionButton(
            onPressed: () => _showAddExpenseSheet(context, logic),
            child: const Icon(Icons.add_rounded),
          ),
        );
      });
    }

    /// 桌面端添加按钮（在侧栏中）
    Widget buildDesktopAddButton() {
      return Visibility(
        visible: isWide,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: IconButton.filled(
            onPressed: () => _showAddExpenseSheet(context, logic),
            icon: const Icon(Icons.add_rounded),
            tooltip: l10n.ledgerAddExpense,
          ),
        ),
      );
    }

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.homeNavigatorLedger,
                      style: textStyle.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  buildDesktopAddButton(),
                ],
              ),
              const SizedBox(height: 8),
              buildBudgetCard(),
              const SizedBox(height: 8),
              buildMonthSelector(),
              const SizedBox(height: 8),
              Expanded(child: buildExpenseList()),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: buildFab(),
        ),
      ],
    );
    });
  }

  /// 显示设置预算对话框
  Future<void> _showBudgetDialog(BuildContext context, LedgerLogic logic) async {
    final currentBudget = logic.state.monthlyBudget.value / 100.0;
    final result = await showTextInputDialog(
      context: context,
      title: l10n.ledgerSetBudget,
      message: l10n.ledgerSetBudgetHint,
      textFields: [
        DialogTextField(
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          initialText: currentBudget > 0 ? currentBudget.toStringAsFixed(2) : '',
          hintText: l10n.ledgerAmountHint,
        ),
      ],
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
    );
    if (result != null && result.isNotEmpty) {
      final amount = double.tryParse(result.first);
      if (amount != null && amount >= 0) {
        await logic.setBudget(amount);
      }
    }
  }

  /// 显示月份选择器
  Future<void> _showMonthPicker(BuildContext context, LedgerLogic logic) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: logic.state.currentMonth.value,
      firstDate: DateTime(2020, 1),
      lastDate: DateTime(now.year + 5, 12),
      initialDatePickerMode: DatePickerMode.year,
      locale: locale,
    );
    if (picked != null) {
      logic.state.currentMonth.value = DateTime(picked.year, picked.month);
      logic.loadExpenses();
    }
  }

  /// 显示添加支出底部弹窗
  Future<void> _showAddExpenseSheet(
      BuildContext context, LedgerLogic logic) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _AddExpenseSheet(logic: logic),
    );
  }

}

/// 添加支出记录的底部弹窗
class _AddExpenseSheet extends StatefulWidget {
  final LedgerLogic logic;

  const _AddExpenseSheet({required this.logic});

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _selectedCategory = '';

  @override
  void initState() {
    super.initState();
    _selectedCategory = ExpenseCategories.defaults.first.name;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 新建分类对话框
  Future<void> _showNewCategoryDialog() async {
    final result = await showTextInputDialog(
      context: context,
      title: '新建支出分类',
      textFields: [
        DialogTextField(hintText: '分类名称'),
      ],
      okLabel: '添加',
      cancelLabel: '取消',
    );
    if (result != null && result.first.isNotEmpty) {
      final name = result.first;
      if (ExpenseCategories.all.any((c) => c.name == name)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('该分类已存在')),
          );
        }
        return;
      }
      await ExpenseCategories.addCustom(
        ExpenseCategory(icon: Icons.category_rounded, name: name, color: 0xFF9C27B0),
      );
      if (context.mounted) {
        setState(() => _selectedCategory = name);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加分类: $name')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖拽指示器
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 标题
            Text(
              l10n.ledgerAddExpense,
              style: textStyle.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            // 金额输入
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[\d.]'),
                ),
              ],
              decoration: InputDecoration(
                labelText: l10n.ledgerAmount,
                hintText: l10n.ledgerAmountHint,
                prefixText: '\u00A5 ',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            // 分类选择
            Text(
              l10n.ledgerCategory,
              style: textStyle.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...ExpenseCategories.all.map((cat) {
                  final isSelected = _selectedCategory == cat.name;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat.name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Color(cat.color).withAlpha(40)
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: AppBorderRadius.mediumBorderRadius,
                        border: isSelected
                            ? Border.all(color: Color(cat.color), width: 1.5)
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(cat.icon, size: 16, color: Color(cat.color)),
                          const SizedBox(width: 4),
                          Text(
                            cat.name,
                            style: textStyle.bodySmall?.copyWith(
                              color: isSelected
                                  ? Color(cat.color)
                                  : colorScheme.onSurface,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                // 新建分类按钮
                GestureDetector(
                  onTap: () => _showNewCategoryDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: AppBorderRadius.mediumBorderRadius,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            size: 16, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '新建',
                          style: textStyle.bodySmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 备注输入
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: l10n.ledgerNote,
                hintText: l10n.ledgerNoteHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            // 确认按钮
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(_amountController.text);
                if (amount == null || amount <= 0) return;
                await widget.logic.addExpense(
                  amount: amount,
                  category: _selectedCategory,
                  note: _noteController.text.trim(),
                );
                HapticFeedback.selectionClick();
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(l10n.ok),
            ),
          ],
        ),
      ),
    );
  }
}
