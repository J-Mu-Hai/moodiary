import 'package:cross_file/cross_file.dart';
import 'package:moodiary/common/models/isar/diary.dart';
import 'package:moodiary/common/models/isar/guide_message.dart';
import 'package:moodiary/common/models/task_plan.dart';
import 'package:moodiary/common/values/diary_type.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:refreshed/refreshed.dart';

class EditState {
  // 当前编辑的日记对象
  late Diary currentDiary;

  // 编辑时的原始日记对象
  Diary? originalDiary;

  List<XFile> imageFileList = [];

  List<String> get imagePathList => imageFileList.map((e) => e.path).toList();
  List<XFile> videoFileList = [];

  List<String> get videoPathList => videoFileList.map((e) => e.path).toList();
  List<XFile> audioFileList = [];

  List<String> get audioPathList => audioFileList.map((e) => e.path).toList();

  List<String> audioNameList = [];

  String currentAudioName = '';

  // 分类名称
  String categoryName = '';

  //编辑还是新增
  bool isNew = true;

  int tabIndex = 0;

  bool isProcessing = false;

  // 总字数
  RxInt totalCount = 0.obs;

  // 已写作时长
  Duration duration = Duration.zero;

  RxString durationString = ''.obs;

  // 是否展示保存动画
  bool isSaving = false;

  // 是否完成初始化
  bool isInit = false;

  // 日记的类型
  late DiaryType type;

  // 是否渲染markdown
  RxBool renderMarkdown = false.obs;

  // ---- 任务规划模式（「任务管理」分类）----
  // 是否处于任务规划模式
  RxBool isTaskPlanning = false.obs;

  // 右侧 AI 面板是否折叠
  RxBool taskPanelCollapsed = false.obs;

  // AI 面板宽度占屏比（可拖拽分割线调节，0.3 ~ 0.72）
  RxDouble taskPanelRatio = 0.55.obs;

  // AI 建议卡片流
  RxList<TaskCardModel> taskCards = <TaskCardModel>[].obs;

  // 面板输入
  RxString taskInput = ''.obs;

  // AI 分析中
  RxBool taskAnalyzing = false.obs;

  // 当前翻页所在页索引
  RxInt taskCurrentPage = 0.obs;

  // ---- AI 引导式任务规划对话 ----
  // 当前引导阶段（1..7，8=已完成）
  RxInt guideStage = 1.obs;

  // 引导对话记录（落库）
  RxList<GuideMessage> guideMessages = <GuideMessage>[].obs;

  // AI 回复中
  RxBool guideAnalyzing = false.obs;

  // 阶段6/7 时间触发提示
  RxString guideNotice = ''.obs;

  // initGuide 防重入
  RxBool guideStarted = false.obs;

  // 自动获取天气
  bool get autoWeather => PrefUtil.getValue<bool>('autoWeather')!;

  // 首行缩进
  bool get firstLineIndent =>
      (PrefUtil.getValue<bool>('firstLineIndent')!) && type == DiaryType.text;

  // 自动分类
  bool get autoCategory => PrefUtil.getValue<bool>('autoCategory')!;

  // 展示写作时长
  bool get showWriteTime => PrefUtil.getValue<bool>('showWritingTime')!;

  // 展示字数统计
  bool get showWordCount => PrefUtil.getValue<bool>('showWordCount')!;

  EditState();
}
