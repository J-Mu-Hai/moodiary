import 'package:flutter/material.dart';
import 'package:moodiary/common/models/isar/expense_record.dart';
import 'package:refreshed/refreshed.dart';

class LedgerState {
  // 当前月份
  Rx<DateTime> currentMonth = DateTime.now().obs;

  // 本月支出记录
  RxList<ExpenseRecord> expenseRecords = <ExpenseRecord>[].obs;

  // 本月总支出（分）
  RxInt totalExpense = 0.obs;

  // 月预算（分）
  RxInt monthlyBudget = 0.obs;
}
