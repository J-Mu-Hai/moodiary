# Moodsonder 项目上下文 — 给「pi」的构建与开发简报

> 本文件是给另一个 AI 助手（pi）接手本项目时读的第一份文档：它是什么、
> 难在哪、怎么编译两端、哪些坑千万别踩。所有信息以 `D:\moodsonder` 仓库为准，
> 于 2026-09-03 整理。

---

## 1. 这是什么项目

**Moodsonder** = 开源日记应用 **Moodiary**（Flutter + Rust 跨平台）的个人深度改造版。
在 Moodiary 的日记/富文本/地图/多媒体基础上，长出了一个**「主动型智能体」**：
不只会记录，还会通过手机观察用户（使用时间、行为作息）、沉淀画像、按时主动
询问/提醒/复盘、执行专注锁屏等。

- 双端：**Android 手机版**（正式包 `cn.yooss.moodiary`）+ **Windows 桌面版**（`moodsonder.exe`）。
- 数据靠 **WebDAV 同步** 打通两端（使用时间、任务、画像、聊天记录、日记）。配置在 `.env.local`。
- 上游 Moodiary 在 GitHub 开源；本仓库是私有 fork，可随时 `git diff` 看相对上游的定制量。

**一句话给 pi**：这是「一人一 AI 的日记陪伴软件」，不是 CRUD 工具——改代码要同时
照顾 Android 后台运行与 Windows 桌面两条路径，且不要破坏「单 isolate + 本地库 +
云同步」的既有平衡。

---

## 2. 技术栈与目录地图

| 层 | 选型 |
|---|---|
| UI/逻辑 | Flutter 3.29.0（`.fvmrc` 锁定，装在 `C:\tools\flutter`），GetX 分支 `refreshed` 路由/状态 |
| 本地库 | Isar `4.0.0-dev.14`（`@collection`，`.isar` 文件） |
| 本地 KV | `PrefUtil` = `SharedPreferencesWithCache`（**带内存缓存，不自动跨 isolate reload**） |
| Rust | `flutter_rust_bridge 2.8`，crate `moodiary_rust`（`rust_builder/`，构建时自动编译，需 Rust 工具链） |
| 云同步 | `webdav_client` 走 WebDAV（`server/` 与腾讯云 WebDAV 桥） |
| AI | 多 Provider：腾讯混元、OpenAI 兼容（DeepSeek 等）；天气/定位/语音等 key 构建期注入 |

关键目录：

```
lib/
  main.dart                   启动时序：RustLib→PrefUtil→DefaultConfig.seed→Isar→主题→WebDAV→三个服务
  common/values/default_config.dart  构建注入的 MOODIARY_* 常量与 seed()
  config/env.dart             APP_MODE (debug/release)
  presentation/isar.dart      IsarUtil（所有集合访问）
  presentation/pref.dart      PrefUtil（KV）
  pages/assistant/            AI 对话页（微信式气泡/打字节奏/补发注入）
  pages/brain/block_screen_page.dart  专注锁屏页
  services/agent_brain/       ★ 智能体大脑全套（见 §3）
  services/screen_time_service.dart   使用时间采集 + 前台服务保活
  services/memory_service.dart        长期画像
  services/ai_*.dart          函数调用/触发器/Provider
  utils/agent_channel.dart    MethodChannel(moodiary/agent) 原生能力封装
  utils/notice_util.dart      FToast（后台不可用时自守卫）
android/app/src/main/kotlin/cn/yooss/moodiary/   ★ 原生：MainActivity 引擎保活、UsageMonitorService、AgentBootReceiver
docs/agent_framework.md       智能体框架「活文档」（目标/架构/迭代状态）
docs/brain_signal_mission.md  大脑信号与使命设计
docs/agent_task_spec.md       任务验收基线
tool/build_android.sh         手机版一键构建（读 .env.local 注入 defines）
tool/build_windows.sh         桌面版一键构建
.env.local                    ★ 敏感配置（已 .gitignore），勿外泄勿删
```

---

## 3. 智能体大脑（本项目的灵魂，改之前先懂它）

全部在 `lib/services/agent_brain/`，分工：

- **AgentTask / AgentTaskStore**（`agent_task.dart`）：任务 = 大脑决策的最小单元。
  字段：`kind`(immediate/scheduled/longterm)、`action`、`status`(pending/running/waitingUser/done/cancelled)、
  `params`、`feedback[]`、`priority`。存 PrefUtil key=`agentTasks`（JSON blob）。`query()` 支持按 status/action 过滤。
- **AgentBrain**（`agent_brain.dart`）：收到**信号**（天气变化/日记稳定/使用分类变化/画像未初始化/用户规则…）→
  决定要不要做、拆成任务写库；`finalizeTask` 收尾（`judge:false` 机械 / `judge:true` AI 判定）；
  `processWaitingUserFeedback` 处理用户对 waitingUser 任务的回应。
- **BrainService**（`brain_service.dart`）：**分钟级 tick 引擎**——每次 tick 捞到期任务交给执行器，
  并负责每日例行种子（约 23:00 晚间复盘 `nightly_review`、23:30 行为建模 `build_behavior_model`）。
- **AgentExecutor**（`agent_executor.dart`）：按 `action` 分发执行，能力有：
  `tts / start_chat / ask_user / block_screen / update_profile / analyze_diaries / open_diary / nightly_review / build_behavior_model`。
  **每个会打扰用户的能力都要先看 `AppUiState.instance.uiAvailable`**（界面是否可用），不可用降级为系统通知（见 §5 坑 1）。
- **agent_monitor.dart**：纯时间窗的每日询问（早 <12h / 中午 12–14h / 傍晚 18–19h / 明天 20–21h），
  配合 `brainCheckInsFired` 天标记；**不在窗口内就错过**（补发靠打开助手页时注入）。
- **BehaviorModelStore / behavior_observations**：把观察聚合成 24h 行为作息，喂给对话上下文。
- **DailyRhythmStore**：今日作息/分时段计划表。

> 每次对话的上下文注入顺序在 `assistant_logic.dart getAi()`：长期画像(MemoryService) →
> 行为作息(BehaviorModelStore) → 角色卡(system prompt) → 日记摘要 → **时间戳**（混元会丢 system 消息，
> 所以时间要内联进最后一条 user 消息）。

---

## 4. 重难点（已经走过的坑，别重蹈）

### 4.1 后台运行：App 不打开也要监控/提醒（本阶段刚做完的核心）
- **问题**：BrainService/ScreenTimeService 的定时器全在 Dart 主 isolate；而 FlutterFragment 默认随
  Activity 销毁 → 引擎没了 → 用户划掉 App 一切定时停 → 必须每天先进一次软件才触发提醒。
- **解法（引擎保活，非后台 isolate）**：
  1. `MainActivity.provideFlutterEngine()` 返回进程级缓存引擎（`new FlutterEngine(applicationContext)` 构造器自动注册插件一次，**禁止**再手动 `GeneratedPluginRegistrant`）；
  2. 自定义 `KeepAliveFragment` 覆写 `shouldDestroyEngineWithHost()=false`，并覆写 `createFlutterFragment()`
     用 `FlutterFragment.NewEngineFragmentBuilder(KeepAliveFragment::class.java)` 复刻基类 new-engine 分支
     （`dartLibraryUri`/`dartEntrypointArgs` 是 `@Nullable`，值空时直接跳过 builder 调用，与基类 null 透传等价）；
  3. `UsageMonitorService`（specialUse 前台服务）**无条件常驻**，`ScreenTimeService.init()` 总先拉起它；
     `onTaskRemoved` 划掉后尽力重拉；
  4. `AgentBootReceiver` 开机自启（BOOT_COMPLETED 豁免后台启动限制），拉起后 `moveTaskToBack` 隐藏。
- **为什么不用 flutter_background_service 的后台 isolate**：`Isar`（`@pragma('vm:isolate-unsendable')` 单例）
  和 `PrefUtil`（内存缓存不自动 reload）都绑主 isolate，后台 isolate 会双写竞争/缓存不一致。引擎保活 =
  所有单例/定时器原样继续跑，零状态层改动。**任何方案都不许引入第二个 Dart isolate。**

### 4.2 UI 可用性判定（后台触发任务怎么触达用户）
- 信号：`WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed` 才允许
  `Get.toNamed`/toast/`bringToFront`/悬浮窗；`detached` = Activity 已销毁但引擎还在。
- `lib/services/app_ui_state.dart` 封装为 `AppUiState.instance.uiAvailable / uiAttached`。
- 降级闭环：执行器无 UI → 发系统通知（`AgentChannel.showAgentNotification`，channel `agent_alerts`，
  IMPORTANCE_HIGH）→ 任务置 `waitingUser` → 用户点开 App → `AssistantLogic._injectPendingAsks()`
  把问题补发进对话 → 用户回复走 `processWaitingUserFeedback` 正常收尾。

### 4.3 原生通道必须活到 Activity 之后
- `MainActivity` 里所有 MethodChannel handler **绝不捕获 `this`**：一律 `applicationContext.getSystemService`
  + 静态 `currentActivity`（`onStart` 置位/`onDestroy` 清空）路由；耗时的 usage 查询放后台线程再
  `Handler(mainLooper).post` 回传；需要 Activity 的能力（悬浮窗/跳设置页/回前台）在 `currentActivity==null` 时静默。

### 4.4 AI 的怪癖
- **腾讯混元忽略 system 角色消息**：时间等关键信息必须内联进 user 消息（`_inlineTimeIntoLastUser`）。
- 长文本要拆句成「微信式」气泡 + 打字节奏（`reply_chunker` + `typing_pacer`），模拟真人。

### 4.5 双端共享数据
- WebDAV 元数据同步（`webdav_util.dart`）：任务/画像/聊天记录/使用时间在两端对等；同步要幂等、
  防锁死（`.timeout(...)` 包裹）、防重复消费（事件游标）。聊天记录持久化在 PrefUtil（`assistantChat`，最近 60 条）。

### 4.6 安全边界
- 敏感配置（WebDAV 账密、各家 AI/天气/地图 key）只存根目录 `.env.local`（已 gitignore），
  由 `tool/*.sh` 读取拼成 `--dart-define=MOODIARY_*` 注入。**任何新 key 走同一套路，绝不硬编码。**

---

## 5. 当前在途工作（git 未提交，接手先看这个）

「后台常驻」改造已实现并在真机验证，改动**尚未 commit**。以下是 9 个文件，别回退它们：

```
M android/app/src/main/AndroidManifest.xml              RECEIVE_BOOT_COMPLETED + AgentBootReceiver 注册
M android/app/src/main/kotlin/.../MainActivity.kt       引擎保活 + 通道加固 + showAgentNotification
M android/app/src/main/kotlin/.../UsageMonitorService.kt onTaskRemoved 重拉 + 通知文案
A android/app/src/main/kotlin/.../AgentBootReceiver.kt  开机自启接收器
A lib/services/app_ui_state.dart                        UI 可用性信号
M lib/pages/assistant/assistant_logic.dart              _injectPendingAsks 补发注入
M lib/services/agent_brain/agent_executor.dart          无 UI 时四类任务降级通知
M lib/services/screen_time_service.dart                 FGS 无条件常驻，开关只控轮询
M lib/utils/agent_channel.dart                          showAgentNotification 封装
M lib/utils/notice_util.dart                            toast 惰性 init + UI 守卫
```

若要继续推进，参考 `docs/agent_framework.md` 的下一批里程碑；若 pi 需要理解这套后台机制，
先读 `MainActivity.kt` 顶部注释 + `agent_executor.dart` 里每个 `AppUiState.instance.uiAvailable` 分支。

---

## 6. 构建与更新（双端）

### 0) 前提与环境
- Flutter 3.29.0：`C:\tools\flutter\bin`（在 git-bash 里 `export PATH="/c/tools/flutter/bin:$PATH"`）。
- Rust 工具链（rust_builder 编译 `moodiary_rust`，首次/改动 Rust 后较慢）。
- **`.env.local` 必须存在**（缺 key 就缺默认配置）；git-bash 下跑。
- Android 构建在装有 Android SDK 的机器上；部署用 adb（`/c/Users/j/AppData/Local/Android/Sdk/platform-tools/adb.exe`）。

### 1) 手机版（每次改完 Dart/Kotlin 都这样更新）
```bash
export PATH="/c/tools/flutter/bin:$PATH"
bash tool/build_android.sh                # release APK → build/app/outputs/flutter-apk/app-release.apk
"/c/Users/j/AppData/Local/Android/Sdk/platform-tools/adb.exe" install -r build/app/outputs/flutter-apk/app-release.apk
```
- **必须 `--release`**：debug 包是 `.debug` 后缀的另一个包，装它覆盖不了正式包 `cn.yooss.moodiary`。
- 手机不在 USB：开「无线调试」→ `adb pair <ip>:<配对端口> <配对码>` → `adb connect <ip>:<adb端口>` 再 install。
- 装机后自查：App 启动无崩溃 → 状态栏有「Moodiary 正在后台守护」常驻通知（FGS 硬性要求，关不得）→
  按 Home/切别的 App 后 `adb shell pidof cn.yooss.moodiary` 进程仍在 → 等一个时间窗收到提醒即闭环。

### 2) 桌面版（Windows）
```bash
export PATH="/c/tools/flutter/bin:$PATH"
bash tool/build_windows.sh                # → build/windows/x64/runner/Release/moodsonder.exe
```
- 桌面快捷方式 `D:\桌面\Moodsonder.lnk` 指向该 exe；更新到新 exe 后直接双击/重启即可（数据在 AppData，不随构建清空）。
- 旧增量手法（`build_moodsonder.bat` / 工作文档里 app.so 拷贝）是早期方案，已不必要——全量 `build windows --release` 即可。
- exe 被占用时先 `taskkill /f /im moodsonder.exe`。
- 若报 `cpp_client_wrapper/*.cc` 缺失：从 Flutter SDK 复制
  `C:/tools/flutter/bin/cache/artifacts/engine/windows-x64/cpp_client_wrapper/*.cc → windows/flutter/ephemeral/cpp_client_wrapper/`。

### 3) 改动代码后的自检
```bash
export PATH="/c/tools/flutter/bin:$PATH"
flutter analyze   # 只看 lib/ 下的**新增**告警；rust_builder/cargokit 的一堆 error 是插件构建工具噪声，与本次改动无关，可忽略
```

---

## 7. 铁律（给 pi 的约束清单）

1. **单 isolate 不可破**：不引入后台 isolate / 不自建第二 entrypoint；`PrefUtil`、`Isar` 只在主 isolate 用。
2. **引擎保活语义不可回退**：别把 `provideFlutterEngine` 改回每 Activity 新建引擎；别删 `KeepAliveFragment`。
3. **凡打扰用户的能力先查 `AppUiState.instance.uiAvailable`**，无 UI 就发通知 + 置 waitingUser，再靠补发注入闭环。
4. **Android 特有逻辑要有 `Platform.isAndroid` 守卫**，Windows 桌面照常（桌面无 FGS/悬浮球概念）。
5. **别提交 `.env.local`**；新敏感项走 `MOODIARY_*` + 构建注入 + `DefaultConfig.seed()`。
6. **改 Isar 模型才需要**跑代码生成；平时 Dart 改动不用。
7. **手机包只认 release**；装错 debug 包会出现「改了没用」，因为那是另一个包名。
8. 智能体行为先读 `docs/agent_framework.md`（活文档，含已实现/待办状态），改动对齐它的里程碑。
9. 同步/会话/任务库都有幂等设计：新增跨端数据结构要沿用「确定性 id + 游标/标记去重」套路。

---

## 8. 一句验收标准（用户原话）

> 「我希望这个软件是可以**实时监控我的桌面**的，不取决于我是否在新的一天中进入过这个软件。」
> 对应验收：**当天从不打开 App**（含重启后），到点仍能收到提醒；打开后对话里有那条询问；使用时间照常统计。
