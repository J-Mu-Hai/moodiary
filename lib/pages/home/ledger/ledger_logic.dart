import 'package:flutter/material.dart';
import 'package:moodiary/common/models/isar/expense_record.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:refreshed/refreshed.dart';
import 'package:uuid/uuid.dart';

import 'ledger_state.dart';

class LedgerLogic extends GetxController {
  final LedgerState state = LedgerState();

  @override
  void onReady() {
    state.monthlyBudget.value =
        PrefUtil.getValue<int>('monthlyBudget') ?? 0;
    loadExpenses();
    super.onReady();
  }

  /// 加载当前月份的支出数据
  Future<void> loadExpenses() async {
    final year = state.currentMonth.value.year;
    final month = state.currentMonth.value.month;
    final records = await IsarUtil.getExpensesByMonth(year, month);
    state.expenseRecords.value = records;
    state.totalExpense.value =
        records.fold<int>(0, (sum, r) => sum + r.amount);
  }

  /// 切换到上个月
  void previousMonth() {
    final current = state.currentMonth.value;
    state.currentMonth.value = DateTime(current.year, current.month - 1);
    loadExpenses();
  }

  /// 切换到下个月
  void nextMonth() {
    final current = state.currentMonth.value;
    state.currentMonth.value = DateTime(current.year, current.month + 1);
    loadExpenses();
  }

  /// 设置月预算（单位：元，内部转为分存储）
  Future<void> setBudget(double yuan) async {
    final fen = (yuan * 100).round();
    state.monthlyBudget.value = fen;
    await PrefUtil.setValue<int>('monthlyBudget', fen);
    update();
  }

  /// 添加一笔支出（单位：元，内部转为分存储）
  Future<void> addExpense({
    required double amount,
    required String category,
    String note = '',
  }) async {
    final record = ExpenseRecord()
      ..id = const Uuid().v7()
      ..amount = (amount * 100).round()
      ..category = category
      ..note = note
      ..time = DateTime.now()
      ..show = true;
    await IsarUtil.insertExpenseRecord(record);
    await loadExpenses();
  }

  /// 删除支出记录
  Future<void> deleteExpense(int isarId) async {
    await IsarUtil.deleteExpenseRecord(isarId);
    await loadExpenses();
  }

  /// 获取剩余预算（分）
  int get remainingBudget =>
      state.monthlyBudget.value - state.totalExpense.value;

  /// 预算使用百分比
  double get usagePercent => state.monthlyBudget.value > 0
      ? state.totalExpense.value / state.monthlyBudget.value
      : 0.0;
}
