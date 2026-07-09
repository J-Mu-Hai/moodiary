import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/main.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:refreshed/refreshed.dart';

import 'laboratory_logic.dart';

class LaboratoryPage extends StatelessWidget {
  const LaboratoryPage({super.key});

  Future<void> _editProvider(
      BuildContext context, LaboratoryLogic logic, AIProviderConfig? existing) async {
    final isNew = existing == null;
    final initialName = existing?.displayName ?? '';
    final initialUrl = existing?.baseUrl ?? '';
    final initialKey = existing?.apiKey ?? '';
    final initialModel = existing?.model ?? '';

    final res = await showTextInputDialog(
      context: context,
      title: isNew ? '添加 AI 服务商' : '编辑 AI 服务商',
      textFields: [
        DialogTextField(
          hintText: '显示名称',
          initialText: initialName,
        ),
        DialogTextField(
          hintText: 'API 地址 (如 https://api.openai.com/v1/chat/completions)',
          initialText: initialUrl,
        ),
        DialogTextField(
          hintText: 'API Key',
          initialText: initialKey,
        ),
        DialogTextField(
          hintText: '模型名 (如 gpt-4, deepseek-chat)',
          initialText: initialModel,
        ),
      ],
      style: AdaptiveStyle.material,
    );
    if (res == null) return;

    final config = AIProviderConfig(
      id: existing?.id ?? '',
      displayName: res[0],
      baseUrl: res[1],
      apiKey: res[2],
      model: res[3],
    );

    if (isNew) {
      await logic.addProvider(config);
    } else {
      await logic.updateProvider(existing!.id, config);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logic = Bind.find<LaboratoryLogic>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingLab),
      ),
      body: GetBuilder<LaboratoryLogic>(builder: (_) {
        final providers = logic.getProviders();
        return ListView(
          children: [
            // ── AI 服务商 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('AI 服务商',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _editProvider(context, logic, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加'),
                  ),
                ],
              ),
            ),
            if (providers.isEmpty)
              const ListTile(
                title: Text('暂无配置'),
                subtitle: Text('点击右上角"添加"配置 AI 服务商'),
              ),
            ...providers.map((p) => ListTile(
                  leading: Icon(
                    p.id == 'tencent' ? Icons.cloud : Icons.memory,
                    color: colorScheme.primary,
                  ),
                  title: Text(p.displayName),
                  subtitle: Text('${p.model}\n${p.baseUrl}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _editProvider(context, logic, p),
                      ),
                      if (p.id != 'tencent')
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: colorScheme.error),
                          onPressed: () => logic.deleteProvider(p.id),
                        ),
                    ],
                  ),
                )),
            const Divider(),

            // ── 原有的其他配置 ──
            ListTile(
              title: const Text('和风天气密钥'),
              subtitle: SelectionArea(
                  child: Text(PrefUtil.getValue<String>('qweatherKey') ?? '')),
              trailing: IconButton(
                  onPressed: () async {
                    final res = await showTextInputDialog(
                        context: context,
                        style: AdaptiveStyle.material,
                        title: '和风天气密钥',
                        message: '在和风天气控制台获取密钥',
                        textFields: [
                          DialogTextField(
                            hintText: 'KEY',
                            initialText:
                                PrefUtil.getValue<String>('qweatherKey') ?? '',
                          )
                        ]);
                    if (res != null) {
                      logic.setQweatherKey(key: res[0]);
                    }
                  },
                  icon: const FaIcon(FontAwesomeIcons.wrench)),
            ),
            ListTile(
              title: const Text('天地图密钥'),
              subtitle: SelectionArea(
                  child: Text(PrefUtil.getValue<String>('tiandituKey') ?? '')),
              trailing: IconButton(
                  onPressed: () async {
                    final res = await showTextInputDialog(
                        context: context,
                        textFields: [
                          DialogTextField(
                            hintText: 'KEY',
                            initialText:
                                PrefUtil.getValue<String>('tiandituKey') ?? '',
                          )
                        ],
                        title: '天地图密钥',
                        message: '在天地图控制台获取密钥',
                        style: AdaptiveStyle.material);
                    if (res != null) {
                      logic.setTiandituKey(key: res[0]);
                    }
                  },
                  icon: const FaIcon(FontAwesomeIcons.wrench)),
            ),
            ListTile(
              onTap: () => logic.exportErrorLog(),
              title: const Text('导出日志文件'),
            ),
            ListTile(
              onTap: () async {
                final res = await logic.aesTest();
                if (res) {
                  NoticeUtil.showToast('加密测试通过');
                } else {
                  NoticeUtil.showToast('加密测试失败');
                }
              },
              title: const Text('加密测试'),
            ),
          ],
        );
      }),
    );
  }
}
