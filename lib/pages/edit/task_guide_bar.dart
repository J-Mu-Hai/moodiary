import 'package:flutter/material.dart';
import 'package:moodiary/common/models/task_plan.dart';

import 'edit_logic.dart';

/// 引导标签按钮栏 — 点击插入对应 markdown 模板
class TaskGuideBar extends StatelessWidget {
  const TaskGuideBar({super.key, required this.logic});

  final EditLogic logic;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tag in TaskTag.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => logic.insertMarkdownTemplate(tag),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    tag.label,
                    style: TextStyle(
                        fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
