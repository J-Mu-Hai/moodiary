import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:moodiary/api/api.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/common/models/isar/diary.dart';
import 'package:moodiary/common/models/isar/guide_message.dart';
import 'package:moodiary/common/models/task_guide.dart';
import 'package:moodiary/common/models/task_plan.dart';
import 'package:moodiary/common/values/diary_type.dart';
import 'package:moodiary/common/values/keyboard_state.dart';
import 'package:moodiary/components/keyboard_listener/keyboard_listener.dart';
import 'package:moodiary/components/quill_embed/audio_embed.dart';
import 'package:moodiary/components/quill_embed/image_embed.dart';
import 'package:moodiary/components/quill_embed/text_indent.dart';
import 'package:moodiary/components/quill_embed/video_embed.dart';
import 'package:moodiary/main.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/router/app_routes.dart';
import 'package:moodiary/services/agent_brain/brain_service.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/services/reply_chunker.dart';
import 'package:moodiary/services/task_advisor.dart';
import 'package:moodiary/services/typing_pacer.dart';
import 'package:moodiary/services/task_doc_parser.dart';
import 'package:moodiary/services/task_guide_service.dart';
import 'package:moodiary/src/rust/api/kmp.dart';
import 'package:moodiary/utils/file_util.dart';
import 'package:moodiary/utils/markdown_util.dart';
import 'package:moodiary/utils/media_util.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:path/path.dart';
import 'package:refreshed/refreshed.dart';
import 'package:uuid/uuid.dart';

import 'edit_state.dart';

class EditLogic extends GetxController {
  final EditState state = EditState();

  //标题
  late final TextEditingController titleTextEditingController =
      TextEditingController();

  //编辑器控制器
  QuillController? quillController;

  // markdown控制器
  TextEditingController? markdownTextEditingController;

  //聚焦对象
  late FocusNode contentFocusNode = FocusNode();
  late FocusNode titleFocusNode = FocusNode();

  /// 任务面板 AI 输入框焦点（🤖AI 标签跳转用）
  late final FocusNode taskInputFocusNode = FocusNode();
  bool _shouldRestoreFocus = false; // 工具栏操作后恢复焦点
  Timer? _timer;

  /// 引导对话会话计数：离开页面时自增，作废进行中的流（照抄 assistant _session 范式）
  int _guideSession = 0;

  late final KeyboardObserver keyboardObserver;

  @override
  void onInit() {
    if (state.showWriteTime) _calculateDuration();
    keyboardObserver = KeyboardObserver(
      onHeightChanged: (_) {},
      onStateChanged: (state) {
        switch (state) {
          case KeyboardState.opening:
            break;
          case KeyboardState.closing:
            break;
          case KeyboardState.closed:
            break;
          case KeyboardState.unknown:
            break;
        }
      },
    );
    keyboardObserver.start();
    super.onInit();
  }

  @override
  void onReady() async {
    await _initEdit();
    quillController?.addListener(_listenCount);
    markdownTextEditingController?.addListener(_listenCount);
    // 工具栏操作后确保编辑器保持焦点
    contentFocusNode.addListener(() {
      _shouldRestoreFocus = contentFocusNode.hasFocus;
    });
    quillController?.addListener(() {
      if (_shouldRestoreFocus && !contentFocusNode.hasFocus) {
        contentFocusNode.requestFocus();
      }
    });
    // 监听文档变化
    quillController?.document.changes.listen((change) {
      final operations = change.change.operations;
      final lastOperation = operations.last;
      // 首行缩进
      if (state.firstLineIndent &&
          lastOperation.key == 'insert' && lastOperation.value == '\n') {
        insertNewLine();
      }
      // # + 空格 → 标题快捷输入（检测光标前的内容）
      if (lastOperation.key == 'insert' && lastOperation.value == ' ') {
        _checkHeadingShortcut();
      }
    });
    super.onReady();
  }

  @override
  void onClose() {
    _guideSession++; // 作废进行中的引导流
    keyboardObserver.stop();
    titleTextEditingController.dispose();
    titleFocusNode.dispose();
    contentFocusNode.dispose();
    quillController?.dispose();
    markdownTextEditingController?.dispose();
    taskInputFocusNode.dispose();
    _timer?.cancel();
    _timer = null;
    super.onClose();
  }

  Future<void> _initEdit() async {
    //如果是新增，更具不同的分类展示不同的操作
    if (Get.arguments.runtimeType == List<Object?>) {
      // 配置日记类型
      state.type = Get.arguments[0] as DiaryType;
      switch (state.type) {
        case DiaryType.text:
        case DiaryType.richText:
          quillController = QuillController.basic();
        case DiaryType.markdown:
          markdownTextEditingController = TextEditingController();
      }
      state.currentDiary = Diary();
      if (state.firstLineIndent) insertNewLine();
      if (state.autoWeather) {
        unawaited(getPositionAndWeather());
      }
      if (state.autoCategory) selectCategory(Get.arguments[1] as String?);
    } else {
      //如果是编辑，将日记对象赋值
      state.isNew = false;
      state.originalDiary = Get.arguments as Diary;
      state.type = DiaryType.values.firstWhere(
        (type) => type.value == state.originalDiary!.type,
      );
      state.currentDiary = state.originalDiary!.clone();
      // 获取分类名称
      if (state.originalDiary!.categoryId != null) {
        state.categoryName =
            IsarUtil.getCategoryName(
              state.originalDiary!.categoryId!,
            )!.categoryName;
      }
      // 初始化标题控制器
      titleTextEditingController.text = state.originalDiary!.title;
      // 待替换的字符串map
      final Map<String, String> replaceMap = {};
      //临时拷贝一份图片数据
      for (final name in state.originalDiary!.imageName) {
        // 生成一个临时文件
        final xFile = XFile(FileUtil.getRealPath('image', name));
        replaceMap[name] = xFile.path;
        state.imageFileList.add(xFile);
      }
      //临时拷贝一份拷贝音频数据到缓存目录
      for (final name in state.originalDiary!.audioName) {
        state.audioNameList.add(name);
        await File(
          FileUtil.getRealPath('audio', name),
        ).copy(FileUtil.getCachePath(name));
      }
      //临时拷贝一份视频数据，别忘记了缩略图
      for (final name in state.originalDiary!.videoName) {
        // 生成一个临时文件
        final videoXFile = XFile(FileUtil.getRealPath('video', name));
        replaceMap[name] = videoXFile.path;
        state.videoFileList.add(videoXFile);
      }
      switch (state.type) {
        case DiaryType.text:
        case DiaryType.richText:
          quillController = QuillController(
            document: Document.fromJson(
              jsonDecode(
                await Kmp.replaceWithKmp(
                  text: state.originalDiary!.content,
                  replacements: replaceMap,
                ),
              ),
            ),
            selection: const TextSelection.collapsed(offset: 0),
          );
        case DiaryType.markdown:
          markdownTextEditingController = TextEditingController(
            text: await Kmp.replaceWithKmp(
              text: state.originalDiary!.content,
              replacements: replaceMap,
            ),
          );
      }
      state.totalCount.value = _toPlainText().length;
    }
    // 任务规划模式：识别「任务管理」分类
    if (_isTaskPlanningCategory()) {
      _enterTaskPlanningMode();
    }
    state.isInit = true;
    update(['body']);
  }

  // ---------- 任务规划模式 ----------

  /// 当前文档是否属于「任务管理」分类
  bool _isTaskPlanningCategory() {
    if (state.categoryName == '任务管理') return true;
    // 新增时若 autoCategory 未开，categoryName 为空，用传入的 categoryId 反查
    if (state.isNew && Get.arguments.runtimeType == List<Object?>) {
      final id = Get.arguments[1] as String?;
      if (id != null) {
        final cat = IsarUtil.getCategoryName(id);
        if (cat?.categoryName == '任务管理') return true;
      }
    }
    return false;
  }

  /// 进入任务规划模式
  void _enterTaskPlanningMode() {
    state.isTaskPlanning.value = true;
    if (state.isNew) {
      // 新建：强制 markdown + 预填 YAML 模板
      state.type = DiaryType.markdown;
      markdownTextEditingController = TextEditingController(
        text: TaskDocParser.buildNewDocTemplate(),
      );
      state.renderMarkdown.value = true;
    } else if (state.type == DiaryType.markdown) {
      // 已有 markdown：渲染为主
      state.renderMarkdown.value = true;
    }
    // 已有 text/richText：保持原编辑（本期不做富文本→markdown 转换）
    // 异步初始化引导对话（读 YAML 阶段 + 加载对话 + 时间触发检查）
    unawaited(initGuide());
  }

  /// 点击引导标签，插入对应 markdown 模板
  void insertMarkdownTemplate(TaskTag tag) {
    if (markdownTextEditingController == null) return;
    if (tag == TaskTag.ai) {
      // 🤖AI 标签：聚焦右侧面板输入框并前缀 @AI
      focusTaskInput();
      return;
    }
    if (tag == TaskTag.page) {
      // 📄 翻页标签：新建一页并切过去
      addTaskPage();
      return;
    }
    if (state.renderMarkdown.value) {
      // 渲染模式：追加到文档末尾
      markdownTextEditingController!.text = TaskDocParser.appendText(
        markdownTextEditingController!.text,
        tag.template,
      );
    } else {
      // 编辑模式：光标处插入（所在行非空先换行）
      _insertTextAtCursor(tag.template);
    }
    update(['task']);
  }

  /// 在 markdown 光标处插入文本（参考 Format 的选区改写范式）
  void _insertTextAtCursor(String text) {
    final controller = markdownTextEditingController!;
    final sel = controller.selection;
    final value = controller.value;

    var insertText = text;
    // 光标所在行非空 → 先换行再插入
    final lineStart = value.text.lastIndexOf('\n', sel.start - 1) + 1;
    final lineEnd = value.text.indexOf('\n', sel.start);
    final lineText = value.text.substring(
      lineStart,
      lineEnd == -1 ? value.text.length : lineEnd,
    );
    if (lineText.trim().isNotEmpty) {
      insertText = '\n$insertText';
    }

    final newText = value.text.replaceRange(sel.start, sel.end, insertText);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + insertText.length),
    );
    contentFocusNode.requestFocus();
  }

  /// 勾选/取消任务复选框（翻转源行）
  void toggleTask(int srcLine) {
    if (markdownTextEditingController == null) return;
    markdownTextEditingController!.text = TaskDocParser.toggleTask(
      markdownTextEditingController!.text,
      srcLine,
    );
    update(['task']);
  }

  /// 应用 AI 卡片的一个操作，修改文档
  void applyTaskAction(TaskCardModel card, TaskAction action) {
    if (markdownTextEditingController == null) return;
    final current = markdownTextEditingController!.text;
    final updated = TaskAdvisor.apply(current, action);
    if (updated != current) {
      markdownTextEditingController!.text = updated;
      NoticeUtil.showToast('AI 已修改');
    }
    state.taskCards.remove(card);
    update(['task']);
  }

  /// 运行一次任务分析，卡片追加到卡片流
  Future<void> runTaskAnalysis(String instruction) async {
    if (markdownTextEditingController == null) return;
    state.taskAnalyzing.value = true;
    update(['task']);
    try {
      final doc = TaskDocParser.parse(markdownTextEditingController!.text);
      final cards = await TaskAdvisor.analyze(doc, instruction);
      state.taskCards.addAll(cards);
    } catch (e) {
      NoticeUtil.showToast('分析失败: $e');
    } finally {
      state.taskAnalyzing.value = false;
      update(['task']);
    }
  }

  /// 聚焦右侧面板 AI 输入框并填入 @AI 前缀
  void focusTaskInput() {
    state.taskPanelCollapsed.value = false;
    state.taskInput.value = '@AI ';
    taskInputFocusNode.requestFocus();
    update(['task']);
  }

  /// 折叠/展开右侧 AI 面板
  void toggleTaskPanel() {
    state.taskPanelCollapsed.value = !state.taskPanelCollapsed.value;
    update(['task']);
  }

  /// 拖拽分割线：调整 AI 面板宽度占屏比（0.3 ~ 0.72）
  void setTaskPanelRatio(double ratio) {
    state.taskPanelRatio.value = ratio.clamp(0.3, 0.72);
    update(['task']);
  }

  /// 忽略（移除）一条 AI 卡片
  void dismissTaskCard(TaskCardModel card) {
    state.taskCards.remove(card);
    update(['task']);
  }

  /// 切换到指定页（翻页）
  void switchTaskPage(int index) {
    if (index < 0) return;
    state.taskCurrentPage.value = index;
    update(['task']);
  }

  /// 新建一页（追加 `# 📄 页面N` 并切到新页）
  void addTaskPage() {
    if (markdownTextEditingController == null) return;
    final pages =
        TaskDocParser.parsePages(markdownTextEditingController!.text);
    final newName = '页面 ${pages.length + 1}';
    markdownTextEditingController!.text = TaskDocParser.appendText(
      markdownTextEditingController!.text,
      '# 📄 $newName\n',
    );
    state.taskCurrentPage.value = pages.length;
    update(['task']);
  }

  // ---------- AI 引导式任务规划对话 ----------

  /// 初始化引导：读 YAML 阶段 → 加载对话 → 时间触发检查 → AI 开场
  Future<void> initGuide() async {
    if (state.guideStarted.value) return;
    state.guideStarted.value = true;
    final controller = markdownTextEditingController;
    if (controller == null) return;

    // 1. 读 YAML guide-stage（无键→1，不写回以保留空文档语义）
    final doc = TaskDocParser.parse(controller.text);
    final saved = int.tryParse(doc.guideStage);
    state.guideStage.value = (saved == null || saved < 1)
        ? 1
        : saved.clamp(1, guideStageDone);

    // 2. 从 Isar 加载对话记录（按 diaryId，跨重启续聊）
    try {
      final savedMsgs = await IsarUtil.getGuideMessages(state.currentDiary.id);
      state.guideMessages.assignAll(savedMsgs);
    } catch (e) {
      print('[Guide Load Error] $e');
    }

    // 3. 阶段 6/7 时间触发检查
    final triggered = _checkGuideTimeTrigger(doc);

    // 4. 开场：空对话 → 当前阶段首问；到反思时间 → 发起反思
    if (triggered) {
      final alreadyAsked = state.guideMessages.any(
        (m) => m.kind == 'systemNotice' && m.stage == state.guideStage.value,
      );
      if (!alreadyAsked) {
        _addGuideMessage(
          role: 'assistant',
          kind: 'systemNotice',
          content: state.guideNotice.value,
          stage: state.guideStage.value,
        );
        await _guideAskOpening(
            stage: state.guideStage.value, reason: 'time');
      }
    } else if (state.guideMessages.isEmpty) {
      await _guideAskOpening(stage: state.guideStage.value);
    }
  }

  /// 阶段 6/7 时间门控：created + 7/21 天 vs 今天，到点写 [state.guideNotice] 并返回 true
  bool _checkGuideTimeTrigger(TaskDoc doc) {
    final stage = state.guideStage.value;
    if (stage != 6 && stage != 7) return false;
    final createdStr = doc.created.isNotEmpty
        ? doc.created
        : _fmtDate(state.currentDiary.time);
    final created = DateTime.tryParse(createdStr);
    if (created == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final createdDay = DateTime(created.year, created.month, created.day);
    final days = today.difference(createdDay).inDays;
    final threshold = stage == 6 ? 7 : 21;
    if (days < threshold) return false;
    state.guideNotice.value = stage == 6
        ? '📋 已到第 7 天，该做第一周反思啦'
        : '🌱 已到第 21 天，该做 21 天复盘啦';
    return true;
  }

  /// 引导对话统一入口：用户输入
  Future<void> submitGuideInput(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      NoticeUtil.showToast('请先在实验室配置 AI 服务商');
      return;
    }
    if (state.guideAnalyzing.value) {
      NoticeUtil.showToast('AI 正在思考，请稍候');
      return;
    }
    _addGuideMessage(role: 'user', content: trimmed);
    state.guideAnalyzing.value = true;
    update(['task']);
    final mySession = _guideSession;
    try {
      final messages = await _buildGuideChatMessages(trimmed);
      final stream = await provider.chat(
        messages: messages,
        modelOverride: provider.config.model,
      );
      await _streamGuide(stream);
    } catch (e) {
      print('[Guide Error] $e');
      if (_guideSession == mySession) {
        _addGuideMessage(
          role: 'assistant',
          kind: 'systemNotice',
          content: '⚠️ 请求失败，请稍后再试。',
          stage: state.guideStage.value,
        );
      }
    } finally {
      if (_guideSession == mySession) {
        state.guideAnalyzing.value = false;
        update(['task']);
      }
    }
  }

  /// AI 主动开场：发起当前阶段第一个问题（或反思时间的问题）
  Future<void> _guideAskOpening({
    required int stage,
    String? reason,
  }) async {
    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      _addGuideMessage(
        role: 'assistant',
        kind: 'systemNotice',
        content: '⚠️ 尚未配置 AI 服务商，请在实验室配置后再开始引导。',
        stage: stage,
      );
      return;
    }
    if (state.guideAnalyzing.value) return;
    state.guideAnalyzing.value = true;
    update(['task']);
    final mySession = _guideSession;
    try {
      final doc = TaskDocParser.parse(markdownTextEditingController!.text);
      final prompt = await TaskGuideService.buildStagePrompt(
        doc: doc,
        stageNo: stage,
        context: reason == 'time' ? '现在到了反思时间，按该阶段框架发起第一个问题。' : null,
      );
      final kicker = reason == 'time'
          ? '现在是第 $stage 阶段（反思）。请用一句话说明到了什么时间，然后提出第一个问题。'
          : '请开始第 $stage 阶段。先用一句话介绍本阶段要做什么，然后提出第一个问题。';
      final messages = [
        AIMessage(role: 'system', content: prompt),
        AIMessage(role: 'user', content: kicker),
      ];
      final stream = await provider.chat(
        messages: messages,
        modelOverride: provider.config.model,
      );
      await _streamGuide(stream);
    } catch (e) {
      print('[Guide Opening Error] $e');
      if (_guideSession == mySession) {
        _addGuideMessage(
          role: 'assistant',
          kind: 'systemNotice',
          content: '⚠️ 开场失败：$e',
          stage: stage,
        );
      }
    } finally {
      if (_guideSession == mySession) {
        state.guideAnalyzing.value = false;
        update(['task']);
      }
    }
  }

  /// 流式接收引导回复 → 逐句气泡落库 → 提取 ACTION / guideComplete
  Future<void> _streamGuide(Stream<String> stream) async {
    final mySession = _guideSession;
    final chunker = ReplyChunker();
    final pacer = TypingPacer();
    var firstBubble = true;
    try {
      await for (final chunk in stream) {
        if (_guideSession != mySession) break;
        if (chunk.isEmpty) continue;
        for (final b in chunker.add(chunk)) {
          // 呼吸感：句子按打字节奏逐个上屏（API 慢时几乎不加延迟）
          await pacer.waitBefore(b.length, isFirst: firstBubble);
          firstBubble = false;
          _addGuideMessage(
              role: 'assistant', content: b, stage: state.guideStage.value);
        }
      }
      if (_guideSession == mySession) {
        for (final b in chunker.finish()) {
          await pacer.waitBefore(b.length, isFirst: firstBubble);
          firstBubble = false;
          _addGuideMessage(
              role: 'assistant', content: b, stage: state.guideStage.value);
        }

        final raw = chunker.raw;
        // 把 ACTION 标记附加到最后一条 AI 气泡（chunker 已从显示文本剥离）
        final actions = TaskGuideService.parseActions(raw);
        if (actions.isNotEmpty &&
            state.guideMessages.isNotEmpty) {
          final last = state.guideMessages.last;
          if (last.role == 'assistant' && last.kind == 'text') {
            final markers = actions
                .map((a) => '[[ACTION:${a.op}|${a.payload}]]')
                .join('\n');
            last.content = '${last.content}\n$markers'.trim();
            await IsarUtil.putGuideMessage(last);
            update(['task']);
          }
        }

        // 阶段完成回调
        final complete = TaskGuideService.parseGuideComplete(raw);
        if (complete != null) {
          await _handleGuideComplete(complete);
        }
      }
    } finally {
      if (_guideSession == mySession) {
        state.guideAnalyzing.value = false;
        update(['task']);
      }
    }
  }

  /// 组装发送给 AI 的消息：system(index 0) + 最近 40 条历史 + 本次用户输入
  Future<List<AIMessage>> _buildGuideChatMessages(String userText) async {
    final doc = TaskDocParser.parse(markdownTextEditingController!.text);
    final prompt = await TaskGuideService.buildStagePrompt(
        doc: doc, stageNo: state.guideStage.value);

    final history = <AIMessage>[];
    final msgs = state.guideMessages;
    final start = msgs.length > 40 ? msgs.length - 40 : 0;
    for (var i = start; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.kind == 'stageComplete' || m.kind == 'systemNotice') continue;
      var content = TaskGuideService.stripActionMarkers(m.content);
      if (content.trim().isEmpty) continue;
      history.add(AIMessage(role: m.role, content: content));
    }
    history.add(AIMessage(role: 'user', content: userText));

    final out = _coalesceGuideMessages(history);
    out.insert(0, AIMessage(role: 'system', content: prompt));
    return out;
  }

  /// 出站消息合并：连续同角色合并（兼容各 API + 省 token）
  List<AIMessage> _coalesceGuideMessages(List<AIMessage> msgs) {
    final out = <AIMessage>[];
    for (final m in msgs) {
      if (out.isNotEmpty && out.last.role == m.role) {
        out[out.length - 1] = AIMessage(
            role: m.role, content: '${out.last.content}\n${m.content}');
      } else {
        out.add(m);
      }
    }
    return out;
  }

  /// 阶段完成：强校验阶段号 → 写输出物章节 → 更新 YAML guide-stage → 下一阶段
  Future<void> _handleGuideComplete(GuideComplete c) async {
    final controller = markdownTextEditingController;
    if (controller == null) return;

    // 强校验：声称的阶段必须等于当前阶段，防 AI 乱吐 CALL
    if (c.stage != state.guideStage.value) {
      NoticeUtil.showToast('阶段校验失败，已忽略本次完成');
      return;
    }
    if (c.nextStage <= c.stage) return;

    // 本阶段回复已结束，先复位 analyzing，下一阶段开场才能通过防重入检查
    state.guideAnalyzing.value = false;

    var md = controller.text;
    if (c.section.isNotEmpty && c.output.isNotEmpty) {
      md = TaskDocParser.upsertSection(md, c.section, c.output);
    }
    final next = c.nextStage.clamp(1, guideStageDone);
    md = TaskDocParser.setYamlValue(md, 'guide-stage', '$next');
    controller.text = md;

    // 阶段完成气泡
    _addGuideMessage(
      role: 'assistant',
      kind: 'stageComplete',
      content: c.summary.isNotEmpty
          ? '✅ 阶段 ${c.stage} 完成：${c.summary}'
          : '✅ 阶段 ${c.stage} 完成',
      extra: jsonEncode({'stage': c.stage, 'section': c.section}),
      stage: c.stage,
    );

    state.guideStage.value = next;

    if (next >= guideStageDone) {
      // 全部完成
      _addGuideMessage(
        role: 'assistant',
        kind: 'text',
        content: '🎉 恭喜！7 个阶段全部完成。计划已沉淀进右侧文档，去执行吧。',
        stage: guideStageDone,
      );
    } else if (next == 6 || next == 7) {
      // 时间门控阶段：写提示，不立即提问，等到了日子再触发
      _addGuideMessage(
        role: 'assistant',
        kind: 'systemNotice',
        content: next == 6
            ? '第一周执行卡已生成。执行一周（约第 7 天）后回来，我们做第一周反思。'
            : '第一周反思完成。继续执行到第 21 天，我们做最终复盘。',
        stage: next,
      );
    } else {
      await _guideAskOpening(stage: next);
    }
    update(['task']);
  }

  /// 气泡按钮回调：把 ACTION 应用到文档
  void applyGuideAction(TaskAction action) {
    if (markdownTextEditingController == null) return;
    final current = markdownTextEditingController!.text;
    final updated = TaskAdvisor.apply(current, action);
    if (updated != current) {
      markdownTextEditingController!.text = updated;
      NoticeUtil.showToast('已应用：${action.label}');
    }
    update(['task']);
  }

  /// 追加一条引导消息（内存 + 落库）
  void _addGuideMessage({
    required String role,
    String kind = 'text',
    required String content,
    String extra = '',
    int? stage,
  }) {
    final m = GuideMessage()
      ..diaryId = state.currentDiary.id
      ..role = role
      ..kind = kind
      ..content = content
      ..extra = extra
      ..stage = stage ?? state.guideStage.value
      ..ts = DateTime.now();
    state.guideMessages.add(m);
    update(['task']); // 逐句气泡即时刷新
    unawaited(IsarUtil.putGuideMessage(m).catchError((e) {
      print('[GuideMessage Save Error] $e');
    }));
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  //计算写作时长
  void _calculateDuration() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      state.duration += const Duration(seconds: 1);
      state.durationString.value = state.duration
          .toString()
          .split('.')[0]
          .padLeft(8, '0');
    });
  }

  String _toPlainText() {
    return state.type == DiaryType.markdown
        ? _markdownToPlainText(markdownTextEditingController!.text)
        : quillController!.document.toPlainText([
          ImageEmbedBuilder(isEdit: true),
          VideoEmbedBuilder(isEdit: true),
          AudioEmbedBuilder(isEdit: true),
          TextIndentEmbedBuilder(isEdit: true),
        ]).trim();
  }

  String _markdownToPlainText(String markdown) {
    if (markdown.isEmpty) return '';

    // 先剥离 YAML 前置块，避免卡片摘要/搜索/字数统计露出元数据
    return MarkdownConverter.convert(
      TaskDocParser.stripYamlFrontmatter(markdown),
    );
  }

  void _listenCount() {
    state.totalCount.value = _toPlainText().length;
  }

  // 插入换行时自动首行缩进
  void insertNewLine() {
    if (quillController == null) return;
    final index = quillController!.selection.baseOffset;
    final length = quillController!.selection.extentOffset - index;
    quillController?.replaceText(
      index,
      length,
      const TextIndentEmbed('2'),
      null,
    );
    quillController?.moveCursorToPosition(index + 1);
  }

  void insertNewImage({required String imagePath}) {
    if (quillController == null) return;
    final imageBlock = ImageBlockEmbed.fromName(imagePath);
    final index = quillController!.selection.baseOffset;
    final length = quillController!.selection.extentOffset - index;
    quillController?.replaceText(index, length, imageBlock, null);
    quillController?.moveCursorToPosition(index + 1);
  }

  void insertNewVideo({required String videoPath}) {
    if (quillController == null) return;
    final videoBlock = VideoBlockEmbed.fromName(videoPath);
    final index = quillController!.selection.baseOffset;
    final length = quillController!.selection.extentOffset - index;
    quillController?.replaceText(index, length, videoBlock, null);
    //插入一个换行
    quillController?.moveCursorToPosition(index + 1);
  }

  Future<void> addNewImage(XFile xFile, {bool isMarkdown = false}) async {
    state.imageFileList.add(xFile);
    if (!isMarkdown) insertNewImage(imagePath: xFile.path);
    update(['Image']);
  }

  // 多张图片

  Future<void> pickMultiPhoto(BuildContext context) async {
    final List<XFile> photoList = await MediaUtil.pickMultiPhoto(10);
    if (photoList.isNotEmpty && context.mounted) {
      Navigator.pop(context);
      for (final photo in photoList) {
        await addNewImage(photo, isMarkdown: false);
      }
      return;
    } else {
      NoticeUtil.showToast(l10n.cancelSelect);
    }
  }

  //单张照片
  Future<void> pickPhoto(
    ImageSource imageSource,
    BuildContext context, {
    bool isMarkdown = false,
  }) async {
    //获取一张图片
    final XFile? photo = await MediaUtil.pickPhoto(imageSource);
    if (photo != null && context.mounted) {
      Navigator.pop<String>(context, photo.path);
      await addNewImage(photo, isMarkdown: isMarkdown);
    } else {
      NoticeUtil.showToast(l10n.cancelSelect);
    }
  }

  //画图照片
  Future<void> pickDraw(Uint8List dataList, BuildContext context) async {
    final path = FileUtil.getCachePath('${const Uuid().v7()}.png');
    Navigator.pop(context, path);
    addNewImage(XFile.fromData(dataList, path: path)..saveTo(path));
  }

  //网络图片
  Future<void> networkImage(BuildContext context) async {
    NoticeUtil.showToast(l10n.imageFetching);
    final imageUrl = await Api.updateImageUrl();
    if (imageUrl == null) {
      NoticeUtil.showToast(l10n.imageFetchError);
      return;
    }
    final imageData = await Api.getImageData(imageUrl.first);
    if (imageData == null) {
      NoticeUtil.showToast(l10n.imageFetchError);
      return;
    }
    final path = FileUtil.getCachePath('${const Uuid().v7()}.png');
    if (context.mounted) Navigator.pop(context, path);
    addNewImage(XFile.fromData(imageData, path: path)..saveTo(path));
  }

  Future<void> addNewVideo(XFile xFile) async {
    //视频list中新增一个
    state.videoFileList.add(xFile);
    insertNewVideo(videoPath: xFile.path);
    update(['Video']);
  }

  //选择视频
  Future<void> pickVideo(ImageSource imageSource, BuildContext context) async {
    // 获取一个视频
    final XFile? video = await MediaUtil.pickVideo(imageSource);
    if (video != null && context.mounted) {
      Navigator.pop(context);
      await addNewVideo(video);
    } else {
      NoticeUtil.showToast(l10n.cancelSelect);
    }
  }

  //预览图片
  // void toPhotoView(List<String> imagePath, int index) {
  //   Get.toNamed(AppRoutes.photoPage, arguments: [imagePath, index]);
  // }

  //预览视频
  // void toVideoView(List<String> videoPath, int index) {
  //   Get.toNamed(AppRoutes.videoPage, arguments: [videoPath, index]);
  // }

  //删除图片
  void deleteImage({required String path}) async {
    // 移除这个图片
    state.imageFileList.removeWhere((file) => file.path == path);
    await FileUtil.deleteFile(path);
    //Get.backLegacy();
    NoticeUtil.showToast('删除成功');
    update(['Image']);
  }

  //长按设置封面
  void setCover(int index) {
    final coverFile = state.imageFileList[index];
    state.imageFileList
      ..removeAt(index)
      ..insert(0, coverFile);
    NoticeUtil.showToast('设置第${index + 1}张图片为封面');
    update(['Image']);
  }

  //获取封面颜色
  Future<int?> getCoverColor() async {
    if (state.imageFileList.isNotEmpty) {
      return await MediaUtil.getColorScheme(
        FileImage(File(state.imageFileList.first.path)),
      );
    } else {
      return null;
    }
  }

  //获取封面比例
  Future<double?> getCoverAspect() async {
    //如果有封面就获取
    if (state.imageFileList.isNotEmpty) {
      return await MediaUtil.getImageAspectRatio(
        FileImage(File(state.imageFileList.first.path)),
      );
    } else {
      return null;
    }
  }

  //保存日记
  Future<void> saveDiary() async {
    state.isSaving = true;
    update(['modal']);
    // 根据文本中的实际内容移除不需要的资源
    final originContent =
        state.type == DiaryType.markdown
            ? markdownTextEditingController!.text.trim()
            : jsonEncode(quillController!.document.toDelta().toJson());
    final needImage = await Kmp.findMatches(
      text: originContent,
      patterns: state.imagePathList,
    );
    final needVideo = await Kmp.findMatches(
      text: originContent,
      patterns: state.videoPathList,
    );
    final needAudio = await Kmp.findMatches(
      text: originContent,
      patterns: state.audioNameList,
    );
    state.imageFileList.removeWhere((file) => !needImage.contains(file.path));
    state.videoFileList.removeWhere((file) => !needVideo.contains(file.path));
    state.audioNameList.removeWhere((name) => !needAudio.contains(name));
    // 保存图片
    final imageNameMap = await MediaUtil.saveImages(
      imageFileList: state.imageFileList,
    );
    // 保存视频
    final videoNameMap = await MediaUtil.saveVideo(
      videoFileList: state.videoFileList,
    );
    //保存录音
    final audioNameMap = await MediaUtil.saveAudio(state.audioNameList);
    final content = await Kmp.replaceWithKmp(
      text: originContent,
      replacements: {...imageNameMap, ...videoNameMap, ...audioNameMap},
    );
    state.currentDiary
      ..title = titleTextEditingController.text
      ..content = content
      ..type = state.type.value
      ..contentText = _toPlainText()
      ..audioName = state.audioNameList
      ..imageName = imageNameMap.values.toList()
      ..videoName = videoNameMap.values.toList()
      ..imageColor = await getCoverColor()
      ..aspect = await getCoverAspect();

    await IsarUtil.updateADiary(
      oldDiary: state.originalDiary,
      newDiary: state.currentDiary,
    );
    // 通知智能体：日记已写入（触发「信息稳定」信号的地基）
    unawaited(BrainService().notifyDiaryWritten());
    state.isNew
        ? Get.back(result: state.currentDiary.categoryId ?? '')
        : Get.back(result: 'changed');
    NoticeUtil.showToast(
      state.isNew ? l10n.editSaveSuccess : l10n.editChangeSuccess,
    );
  }

  DateTime? oldTime;

  /// 是否为空白新文档（无标题且无正文），空白退出不保存
  bool get _isBlankDoc {
    if (!state.isNew) return false; // 编辑已有文档永不视为空白
    final titleBlank = titleTextEditingController.text.trim().isEmpty;
    final contentBlank = state.type == DiaryType.markdown
        ? markdownTextEditingController!.text.trim().isEmpty
        : quillController!.document.toPlainText().trim().isEmpty;
    return titleBlank && contentBlank;
  }

  void handleBack() {
    final DateTime currentTime = DateTime.now();
    if (oldTime != null &&
        currentTime.difference(oldTime!) < const Duration(seconds: 3)) {
      // 第二次返回：自动保存后退出（与右上角对号一致，saveDiary 内部会 Get.back）
      unFocus();
      if (_isBlankDoc) {
        // 空白新文档直接退出，不创建空日记
        Get.back();
      } else {
        saveDiary();
      }
    } else {
      oldTime = currentTime;
      NoticeUtil.showToast(l10n.backAgainToExit);
    }
  }

  Future<void> changeDate() async {
    final nowDateTime = await showDatePicker(
      context: Get.context!,
      initialDate: state.currentDiary.time,
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.day,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
    );
    if (nowDateTime != null) {
      state.currentDiary.time = state.currentDiary.time.copyWith(
        year: nowDateTime.year,
        month: nowDateTime.month,
        day: nowDateTime.day,
      );
      update(['Date']);
    }
  }

  Future<void> changeTime() async {
    final nowTime = await showTimePicker(
      context: Get.context!,
      initialTime: TimeOfDay.fromDateTime(state.currentDiary.time),
    );
    if (nowTime != null) {
      state.currentDiary.time = state.currentDiary.time.copyWith(
        hour: nowTime.hour,
        minute: nowTime.minute,
      );
      update(['Date']);
    }
  }

  void unFocus() {
    titleFocusNode.unfocus();
    contentFocusNode.unfocus();
  }

  //去画画
  void toDrawPage(BuildContext context) {
    unFocus();
    Get.toNamed(AppRoutes.drawPage);
  }

  void changeRate(value) {
    state.currentDiary.mood = value;
    update(['Mood']);
  }

  //获取天气，同时获取定位
  Future<void> getPositionAndWeather() async {
    final key = PrefUtil.getValue<String>('qweatherKey');
    if (key == null) return;

    state.isProcessing = true;
    update(['Weather']);

    // 获取定位
    final position = await Api.updatePosition();
    if (position == null) {
      _handleError(l10n.locationError);
      return;
    }

    state.currentDiary.position = position;

    // 获取天气
    final weather = await Api.updateWeather(
      position: LatLng(double.parse(position[0]), double.parse(position[1])),
    );

    if (weather == null) {
      _handleError(l10n.weatherError);
      return;
    }

    state.currentDiary.weather = weather;
    state.isProcessing = false;
    NoticeUtil.showToast(l10n.weatherSuccess);
    update(['Weather']);
  }

  void _handleError(String message) {
    state.isProcessing = false;
    NoticeUtil.showToast(message);
    update(['Weather']);
  }

  Future<void> pickAudio(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withReadStream: true,
      );

      if (result == null) {
        NoticeUtil.showToast(l10n.cancelSelect);
        return;
      }

      final pickedFile = result.files.single;
      final originalFileName = pickedFile.name;
      final fileExtension = extension(originalFileName);

      final audioName = 'audio-${const Uuid().v7()}$fileExtension';
      final cachePath = FileUtil.getCachePath(audioName);

      await pickedFile.readStream!.pipe(File(cachePath).openWrite());

      if (context.mounted) {
        Navigator.pop(context);
      }

      setAudioName(audioName);
    } catch (e) {
      NoticeUtil.showToast(l10n.audioFileError);
    }
  }

  //获取音频名称
  void setAudioName(String name) {
    if (quillController == null) return;
    state.audioNameList.add(name);
    final audioBlock = AudioBlockEmbed.fromName(name);
    final index = quillController!.selection.baseOffset;
    final length = quillController!.selection.extentOffset - index;
    // 插入音频 Embed
    quillController?.replaceText(index, length, audioBlock, null);
    quillController?.moveCursorToPosition(index + 1);
    update(['Audio']);
  }

  //删除音频
  Future<void> deleteAudio(String path) async {
    // 删除文件
    await FileUtil.deleteFile(path);
    // 删除对应的组件
    state.audioNameList.removeWhere((name) => path.endsWith(name));
    update(['Audio']);
    NoticeUtil.showToast('删除成功');
  }

  //添加一个标签
  void addTag({required String tag}) {
    tag = tag.trim();
    if (tag.isNotEmpty) {
      if (state.currentDiary.tags.contains(tag)) {
        NoticeUtil.showToast(l10n.editAddTagAlreadyExist);
        return;
      }
      state.currentDiary.tags.add(tag);
      update(['Tag']);
    } else {
      NoticeUtil.showToast(l10n.editAddTagCannotEmpty);
    }
  }

  //移除一个标签
  void removeTag(index) {
    state.currentDiary.tags.removeAt(index);
    update(['Tag']);
  }

  /// # + 空格 → 标题快捷输入
  void _checkHeadingShortcut() {
    if (quillController == null) return;
    final index = quillController!.selection.baseOffset;
    if (index < 2) return;
    // 获取光标前的文本
    final plain = quillController!.document.toPlainText();
    if (index > plain.length) return;
    final before = plain.substring(0, index);
    // 查找当前行开头到光标的内容
    final lineStart = before.lastIndexOf('\n');
    final linePrefix = before.substring(lineStart == -1 ? 0 : lineStart + 1);
    // 匹配 # ## ### #### + 空格 的行首模式
    final match = RegExp(r'^(#{1,4}) $').firstMatch(linePrefix);
    if (match == null) return;
    final level = match.group(1)!.length;
    final prefixLen = match.group(0)!.length;
    // 删除 # 文本并设置标题（保留 # 号后的文字）
    final textAfter = linePrefix.substring(prefixLen);
    quillController!.formatText(
      index - prefixLen,
      prefixLen,
      Attribute.fromKeyValue('header', level),
    );
  }

  /// 获取文档标题结构（用于目录弹窗）
  List<MapEntry<int, String>> getDocumentOutline() {
    if (quillController == null) return [];
    final result = <MapEntry<int, String>>[];
    final delta = quillController!.document.toDelta();
    int index = 0;
    for (final op in delta.toJson()) {
      final insert = op['insert'] as String?;
      final attributes = op['attributes'] as Map<String, dynamic>?;
      if (insert == '\n' && attributes != null) {
        final header = attributes['header'];
        if (header is int && header >= 1 && header <= 4) {
          // 找到标题行的文本
          final lines = quillController!.document.toPlainText().split('\n');
          final lineIndex = result.length;
          if (lineIndex < lines.length) {
            result.add(MapEntry(header, lines[lineIndex]));
          }
        }
      }
      if (insert != null) {
        index += insert.length;
      }
    }
    return result;
  }

  /// 滚动到指定位置
  void scrollToOutline(int index) {
    // 简单实现：通过设置 selection 跳转
    quillController?.updateSelection(
      TextSelection.collapsed(offset: index),
      ChangeSource.local,
    );
    contentFocusNode.requestFocus();
  }

  void selectCategory(String? id) {
    state.currentDiary.categoryId = id;
    if (id == null) {
      state.categoryName = '';
    } else {
      final category = IsarUtil.getCategoryName(id);
      if (category != null) {
        state.categoryName = category.categoryName;
      }
    }
    update(['CategoryName']);
  }

  void renderMarkdown() {
    state.renderMarkdown.value = !state.renderMarkdown.value;
  }

  void focusContent() {
    if (!contentFocusNode.hasFocus) contentFocusNode.requestFocus();
  }
}
