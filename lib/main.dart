import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/find_locale.dart';
import 'package:intl/intl.dart';
import 'package:moodiary/common/values/default_config.dart';
import 'package:moodiary/common/values/language.dart';
import 'package:moodiary/components/env_badge/badge.dart';
import 'package:moodiary/components/frosted_glass_overlay/frosted_glass_overlay_view.dart';
import 'package:moodiary/components/window_buttons/window_buttons.dart';
import 'package:moodiary/config/env.dart';
import 'package:moodiary/l10n/app_localizations.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/router/app_pages.dart';
import 'package:moodiary/router/app_routes.dart';
import 'package:moodiary/services/ai_trigger_service.dart';
import 'package:moodiary/services/agent_brain/brain_service.dart';
import 'package:moodiary/services/screen_time_service.dart';
import 'package:moodiary/services/sync_keeper_service.dart';
import 'package:moodiary/src/rust/frb_generated.dart';
import 'package:moodiary/utils/file_util.dart';
import 'package:moodiary/utils/log_util.dart';
import 'package:moodiary/utils/media_util.dart';
import 'package:moodiary/utils/theme_util.dart';
import 'package:moodiary/utils/webdav_util.dart';
import 'package:refreshed/refreshed.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'presentation/pref.dart';

late AppLocalizations l10n;
late Locale locale;

Future<void> _initSystem() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ── 临时诊断：启动各步骤耗时（定位启动 CPU 忙转 / ANR）──
  final _sw = Stopwatch()..start();
  void _step(String name) {
    print('[STARTUP] ${_sw.elapsedMilliseconds}ms: $name');
    _sw.reset();
  }

  await RustLib.init();
  _step('RustLib.init');
  await PrefUtil.initPref();
  _step('PrefUtil.initPref');
  // 预填个人默认配置（WebDAV + DeepSeek），仅在对应配置为空时写入
  await DefaultConfig.seed();
  _step('DefaultConfig.seed');
  await IsarUtil.initIsar();
  _step('IsarUtil.initIsar');
  await IsarUtil.ensureFixedCategories();
  _step('ensureFixedCategories');
  // 诊断：打印数据库文件大小
  try {
    final dbDir = Directory(FileUtil.getRealPath('database', ''));
    if (dbDir.existsSync()) {
      final sizes = dbDir
          .listSync()
          .whereType<File>()
          .map((f) =>
              '${f.uri.pathSegments.last}=${(f.statSync().size / 1024 / 1024).toStringAsFixed(1)}MB')
          .join(', ');
      print('[DB] files: $sizes');
    }
  } catch (e) {
    print('[DB] size check error: $e');
  }
  await ThemeUtil().buildTheme();
  _step('ThemeUtil.buildTheme');
  await WebDavUtil().initWebDav();
  _step('WebDavUtil.initWebDav');
  VideoPlayerMediaKit.ensureInitialized(
    android: true,
    iOS: true,
    macOS: true,
    windows: true,
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  await _findLanguage();
  _step('_findLanguage');
  await _platFormOption();
  _step('_platFormOption');
  // 启动 AI 触发器服务
  AiTriggerService().init();
  // 启动智能体大脑服务（任务轮询 + 代码监督信号）
  BrainService().init();
  // 启动屏幕使用时间服务（Android 采集 + 跨端同步）
  ScreenTimeService().init();
  // 跨端轻量同步守护：WebDAV 已配置时自动周期拉/推元数据与日记，
  // 让「打开另一端就能看到最新」不再依赖手动进页面。
  SyncKeeperService().start();
  _step('services init');
}

Future<void> _findLanguage() async {
  Language language = Language.values.firstWhere(
    (e) => e.languageCode == PrefUtil.getValue<String>('language')!,
    orElse: () => Language.system,
  );
  if (language == Language.system) {
    final systemLocale = await findSystemLocale();
    final systemLanguageCode =
        systemLocale.contains('_')
            ? systemLocale.split('_').first
            : systemLocale;
    language = Language.values.firstWhere(
      (e) => e.languageCode == systemLanguageCode,
      orElse: () => Language.english,
    );
  }
  locale = Locale(language.languageCode);
  Intl.defaultLocale = locale.languageCode;
}

Future<void> _platFormOption() async {
  if (Platform.isAndroid) {
    await FlutterDisplayMode.setHighRefreshRate();
    MediaUtil.useAndroidImagePicker();
  }
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    doWhenWindowReady(() {
      appWindow.minSize = const Size(600, 640);
      appWindow.size = const Size(1024, 640);
      appWindow.alignment = Alignment.center;
      appWindow.show();
    });
  }
}

String _getInitialRoute() {
  if (PrefUtil.getValue<bool>('lock')!) return AppRoutes.lockPage;
  if (PrefUtil.getValue<bool>('firstStart')!) return AppRoutes.startPage;
  return AppRoutes.homePage;
}

void main() async {
  await _initSystem();
  // ── 临时诊断：--dart-define=AUTONAV=/screenTime 启动后自动跳转到指定页面 ──
  // 仅用于定位「进入使用时间后主线程忙转」问题；release 构建不传该参数即完全禁用。
  const autoNavRoute = String.fromEnvironment('AUTONAV');
  if (autoNavRoute.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      print('[AUTONAV] navigating to $autoNavRoute');
      Get.toNamed(autoNavRoute);
    });
  }
  FlutterError.onError = (details) {
    LogUtil.printError(
      'Flutter error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    LogUtil.printWTF('Error', error: error, stackTrace: stack);
    return true;
  };
  final themeData = ThemeUtil().getThemeData();
  // ── 临时诊断：帧看门狗（每 2 秒报告一次产帧速率，定位持续动画）──
  final _frameSw = Stopwatch()..start();
  var _frameCount = 0;
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    _frameCount++;
    if (_frameSw.elapsedMilliseconds >= 2000) {
      final secs = _frameSw.elapsedMilliseconds / 1000;
      print('[FRAMES] ${(_frameCount / secs).toStringAsFixed(1)} fps over ${secs.toStringAsFixed(0)}s');
      _frameSw.reset();
      _frameCount = 0;
    }
  });
  runApp(
    GetMaterialApp.router(
      routeInformationParser: GetInformationParser.createInformationParser(
        initialRoute: _getInitialRoute(),
      ),
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
      backButtonDispatcher: GetRootBackButtonDispatcher(),
      builder: (context, child) {
        l10n = AppLocalizations.of(context)!;
        final mediaQuery = MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              PrefUtil.getValue<double>('fontScale')!,
            ),
          ),
          child: FToastBuilder()(context, child!),
        );
        return Stack(
          children: [
            mediaQuery,
            const FrostedGlassOverlayComponent(),
            if (Env.debugMode)
              const Positioned(
                top: -15,
                right: -15,
                child: EnvBadge(envMode: '测试版'),
              ),
            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
              const Positioned(top: 0, left: 0, right: 0, child: MoveTitle()),
          ],
        );
      },
      theme: themeData.$1,
      darkTheme: themeData.$2,
      locale: locale,
      themeMode: ThemeMode.values[PrefUtil.getValue<int>('themeMode')!],
      getPages: AppPages.routes,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

class GetRootBackButtonDispatcher extends BackButtonDispatcher
    with WidgetsBindingObserver {
  GetRootBackButtonDispatcher();

  @override
  void addCallback(ValueGetter<Future<bool>> callback) {
    if (!hasCallbacks) {
      WidgetsBinding.instance.addObserver(this);
    }
    super.addCallback(callback);
  }

  @override
  void removeCallback(ValueGetter<Future<bool>> callback) {
    super.removeCallback(callback);
    if (!hasCallbacks) {
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  Future<bool> didPopRoute() async {
    return (await Get.rawRoute?.navigator?.maybePop()) ??
        invokeCallback(Future.value(false));
  }
}
