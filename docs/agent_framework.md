# 智能体框架设计（Moodiary Agent Framework）

> 本文档是 Moodsonder 智能体建设的**活文档**。目标、架构、决策会随迭代演进；
> 每个阶段的实现都对照本文档进行，完成后更新状态标记。

## 1. 愿景与目标

做一个「朋友般智能体」——不只是记录日记的工具，而是一个**主动认识用户、
帮用户规划、监督用户执行**的智能伙伴。

### 1.1 三大核心诉求

| # | 诉求 | 含义 |
|---|------|------|
| 1 | **超乎寻常的主动性** | 主动找用户聊天，逐步建立对用户的认知（不靠用户先开口） |
| 2 | **规划辅助** | 评估任务规划的合理度、每日规划的合理性，主动给出建议 |
| 3 | **执行监督** | 监督任务执行情况，给予及时反馈（而非每晚被动复盘一次） |

### 1.2 扩展能力（用户补充）

- **自主产生任务**：智能体自己规划任务（今天 / 本周 / 长期）并持续追踪
- **感知**：可调用函数查询用户地点、天气、具体日记等
- **干预**：语音提醒、强制弹窗阻断用户沉迷手机
- **行为认知**：还原用户每天的生活逻辑——什么时间段大概在做什么、是否使用手机

### 1.3 设计姿态

用户明确：**细节不确定，采用智能体框架，慢慢寻找细节并优化。**
所以本文档先立骨架，每个模块的细节在迭代中打磨，不一味追求一次性完美。

---

## 2. 关键设计决策（已与用户对齐）

### D1. 主动性：保留触发框架 + 模型生成
- **不**做全自主 agent loop（模型自己决定何时开口）——成本高、不可控。
- **保留**现有 `TriggerEngine`（时间/事件触发）作为行为骨架；
- 触发后由模型**生成内容**，生成时注入用户画像；`gentle` 级触发先由模型判断
  「此刻是否合适开口」，不合适则静默（防过度打扰）。
- 结论：**规则保证不遗漏，模型保证内容质量与分寸。**

### D2. 认知建立：模型定期沉淀画像
- 不依赖即时记忆碎片；由模型**每晚**回顾当天日记 + 交互 + 行为数据，
  总结出「关于用户的新认知」，与旧画像**合并去重**后写回长期记忆。
- 认知随使用持续加深，智能体越来越「认识」用户。

---

## 3. 总体架构（分层）

```
┌─────────────────────────────────────────────────────┐
│  感知层：触发信号 + 数据查询                          │
│  时间 / 屏幕状态 / 日记写入 / 任务变更 / 天气/地点    │
│  屏幕使用会话(UsageSession) / 日记(Isar)             │
└───────────────────────┬─────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────┐
│  记忆层：用户认知（本次建设的地基，❌→✅）            │
│  ① 工作记忆：当前对话上下文(已有)                     │
│  ② 事件记忆：日记/行为记录(已有 UsageSession/Isar)    │
│  ③ 长期认知：用户画像(习惯/偏好/情绪/行为规律)✅      │
│     —— MemoryService 每晚由模型沉淀                    │
└───────────────────────┬─────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────┐
│  决策层：TriggerEngine（保留+增强）                   │
│  到点/事件触发 → 注入画像 → 模型判断(可选) → 生成      │
└───────────────────────┬─────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────┐
│  行动层：AiFunctionSystem（工具/函数）                │
│  查询日记/任务/环境/时间线 · 创建任务 · 语音 · 弹窗    │
└─────────────────────────────────────────────────────┘
```

- **感知层 / 事件记忆 / 工作记忆 / 触发框架 / 函数系统**：已有，本设计做增强。
- **长期认知（画像）**：完全缺失，是阶段 1 的核心新增。

---

## 4. 分层设计

### 4.1 感知层

| 信号 | 现状 | 状态 |
|------|------|------|
| 时间 | 每分轮询 | ✅ |
| 屏幕使用会话（分钟级） | `UsageSession` + 持续监督 | ✅ |
| 按天使用总时长 | `UsageRecord` | ✅ |
| 日记写入 | `BrainService.notifyDiaryWritten` 记录写入时刻 → 30 分钟后触发「信息稳定」信号 | ✅ |
| 任务变更 | 大脑任务库 `AgentTaskStore` 变化即智能体主动性的输入 | ✅ |
| 天气/地点 | `env_snapshot` + `BrainMonitor` 天气变化信号 | ✅ |
| App 使用类别变化 | `BrainMonitor` 每日对比各类别占比（内置类别映射） | ✅ |
| 画像未初始化 | `BrainMonitor` 画像为空且有日记 → 建议沉淀信号 | ✅ |
| 行为时间线（喂给模型） | `get_usage_timeline`（日期+时段过滤，喂给模型还原生活逻辑） | ✅ |

### 4.2 记忆层（核心新增，阶段 1 ✅）

**存储**：`UserMemoryData` → `PrefUtil`（SharedPreferences）JSON blob
（`key=userMemory`）。因 isar_generator 在当前环境不可用，画像体量小
（几十条要点），暂用 PrefUtil 存 JSON；接口稳定后如需类型安全/跨端同步
可平滑迁移 Isar。存储字段：

```yaml
profileVersion: int          # 画像版本号（每次沉淀 +1）
updatedAt: DateTime          # 最后沉淀时间
aspects: List<String>        # 画像要点，每条格式 `[类别] 内容`
#   category ∈ { 生活习惯, 情绪状态, 偏好与习惯, 目标与痛点, 人际关系, 行为规律 }
rawSummaries: List<String>   # 历次沉淀的原始总结（溯源，保留最近 10 条）
```

**服务**：`MemoryService`（`lib/services/memory_service.dart`）

```dart
Future<String> getProfile()          // 拼成画像文本，供对话/触发生成注入
Future<void> consolidate()           // 每晚：回顾当天→模型总结→合并写回
```

- `consolidate()` 输入：当天日记摘要 + 当前画像（阶段 2 起并入屏幕使用规律）
- 输出：模型总结的 `{"add":[...],"remove":[...]}` 增量，宽松解析后合并
  （同类别语义去重，`remove` 优先，超 `maxAspects=40` 裁剪）
- 触发方式：新增触发器 `memory_consolidation`（23:30 后台静默执行）
- 手动验证：实验室页「立即沉淀画像」入口

**注入点**：
- `AssistantLogic.getAi` 的 system prompt 注入画像（让对话「带着记忆」）
- `TriggerEngine.fire` 的 `buildSystemPrompt` 注入画像（让主动行为「带着记忆」）

### 4.3 决策层（TriggerEngine 增强）

现状 `TriggerEngine.fire` 已具备：收集数据 → 拼 prompt → 生成 → 拆句 → 冷却。
增强点：

1. **画像注入**：`buildSystemPrompt` 加入 `MemoryService.getProfile()`
2. **打扰判断**（D1 护栏）：`gentle` 优先级触发，先生成一个短判断
   `shouldIntervene(reason, profile)` → 模型决定开口/静默
3. **触发器可扩展**：现有 `triggers.json` 是声明式，新增触发器只需加配置+prompt

### 4.4 行动层（函数扩展）

**已有函数**（AiFunctionSystem，9 个）：
`getDiaryByDateRange` / `getDiaryByCategory` / `getTodayPlan` / `getTaskAnalysis`
`getCategories` / `getUniversalValues` / `env_snapshot` / `speak` / `get_usage_timeline`

**规划要新增的函数**（草案签名，阶段 3/4）：

```dart
create_task({
  title,                 // 任务名
  deadline,              // 可选截止
  scope,                 // 'today' | 'week' | 'longterm'（今天/本周/长期）
  note,                  // 可选备注
})                        // → 写入「任务管理/每日计划」分类，返回新任务 id

schedule_reminder({
  time,                  // 提醒时刻
  text,                  // 提醒内容
})                        // → 到时语音播报提醒

block_phone({
  durationMinutes,       // 阻断时长
  reason,                // 阻断原因（供弹窗文案）
})                        // → 全屏阻断 overlay（Android，需权限）
```

---

## 5. 迭代路线

```
阶段1  记忆层 + 触发注入画像 ✅
       → 智能体「认识」你了（每晚沉淀画像，主动/对话都带着记忆）
       · UserMemory 模型 · MemoryService · memory_consolidation 触发器 · 注入接线
       · 实验室页「立即沉淀画像」手动入口

阶段2  时间线感知 + 规律沉淀画像 ✅
       → 智能体「读懂」你的生活节奏
       · get_usage_timeline 函数（日期+时段过滤，喂给模型还原生活逻辑）
       · consolidate 融合当天使用时间线 → 沉淀 [行为规律] 类画像
       · 使用时间页右侧「用户画像」面板（自适应：宽屏左右并排，窄屏上下）

阶段3  智能体大脑：触发 → 规划 → 执行 → 反馈闭环 ✅
       → 智能体「主动」认识你、帮你规划、监督执行
       · AgentBrain 决策（brain_plan.txt，宽容 JSON 任务输出）
       · AgentTaskStore / AgentRuleStore（PrefUtil JSON）
       · BrainMonitor 4 类代码监督信号（天气/日记稳定/使用类别/画像未初始化）
       · AgentExecutor 5 类执行器（tts · start_chat · ask_user · block_screen · update_profile）
       · BrainService 分钟轮询分发 · 全屏阻断页（App 内倒计时）
       · 助手对话 waitingUser 反馈 hook（用户回应关闭任务）
       · 实验室页：信号手动触发 / 任务库可视化 / 用户规则输入

阶段4  语音提醒增强 + 系统级悬浮窗阻断
       → 智能体更强的「干预」
       · schedule_reminder 到点语音 · block_phone 原生 overlay（需悬浮窗权限）
       · create_task/schedule_reminder 函数接入对话 · 周/长期任务追踪
       · 大脑 tool-calling 升级（当前仅决策，不自主查数据）
```

每阶段独立可验证、独立产生价值；细节（画像字段、判断阈值、触发时机）在
各阶段内迭代打磨。

---

## 6. 现有资产盘点（复用清单）

| 资产 | 位置 | 复用方式 |
|------|------|----------|
| 触发引擎 | `lib/services/ai_triggers.dart` | 保留，增强注入画像 |
| 触发调度 | `lib/services/ai_trigger_service.dart` | 保留 |
| 函数系统 | `lib/services/ai_functions.dart` | 扩展 switch case |
| 对话主脑 | `lib/pages/assistant/assistant_logic.dart` | 注入画像点 |
| prompt 管理 | `lib/services/ai_prompt_manager.dart` | 加载 prompts/*.txt |
| 屏幕使用数据 | `lib/services/screen_time_service.dart` + `UsageSession/Record` | 阶段 2 读取 |
| 任务规划 | `lib/services/task_advisor.dart` + `task_guide_service.dart` | 阶段 3 复用 |
| 时间注入 | `assistant_logic._timeMessage()` | 已有 |
| 拆句/呼吸感 | `reply_chunker.dart` / `typing_pacer.dart` | 已有 |
| 日记模型 | Isar `Diary` | 画像沉淀读取 |

---

## 7. 风险与待确认

1. **强制弹窗阻断**：Android 全屏 overlay 需「悬浮窗」权限（SYSTEM_ALERT_WINDOW），
   且 Android 高版本对 overlay 限制严格；用户体验/误伤风险需谨慎设计。
   *待确认：是否先用「通知+语音提醒」作为阶段 4 的首版，弹窗作为进阶。*
2. **主动打扰的平衡**：`gentle` 判断护栏的阈值需要实测调优，避免智能体变成骚扰。
3. **token 成本**：每晚画像沉淀 + 触发生成会消耗额外 token，需关注 Provider 配额。
4. **画像隐私**：用户画像含敏感认知（情绪、痛点），存储在本机 Isar + WebDAV 同步，
   需延续现有加密/不落源码的原则。
5. **行为数据准确性**：UsageStats 在部分 ROM 上有延迟/权限限制，时间线可能不完整，
   需在 prompt 中提示模型「数据可能不完整，不确定时不要臆断」。
6. **函数调用仍是文本协议 `[[CALL:]]`**：稳定但非原生 tool calling。
   *待确认：是否后续演进为原生工具调用，本文档暂按现状设计。*

---

## 8. 里程碑记录

| 日期 | 事项 | 状态 |
|------|------|------|
| 2026-08-14 | 框架设计定稿（本文档）；决策 D1/D2 对齐 | ✅ |
| 2026-08-14 | 阶段 1 记忆层：`MemoryService`+prompt+`memory_consolidation` 触发器+对话/触发注入+实验室手动入口 | ✅ |
| 2026-08-14 | 阶段 1 构建验证（Android/Windows） | ✅ |
| 2026-08-14 | 阶段 2：`get_usage_timeline` 函数 + consolidate 融合行为规律 + 使用时间页画像面板 | ✅ |
| 2026-08-14 | 阶段 2 构建验证（Android/Windows） | ✅ |
| 2026-08-14 | 阶段 3：智能体大脑闭环（AgentBrain/Monitor/Executor/Task/BlockScreen/规则） | ✅ |
| 2026-08-14 | 阶段 3 构建验证（Android/Windows）+ 修复 userMemory allowList bug | ✅ |
| 2026-08-14 | 修复大脑 AI 401：seed 同步注入 key + AiProviderManager 空 current 回退默认 | ✅ |
| 2026-08-14 | 端到端闭环首验（Android）：画像未初始化信号 → 大脑生成任务 ✅ | ✅ |
| 2026-08-14 | 用户手机交互验证（任务库可视化 / tts / 阻断页 / 规则→定时 / ask_user 闭环） | 🔜 进行中 |
| 2026-08-14 | 阶段3 迭代2：手动触发体验（quiet 网络 + 手动强制出任务）+ 大脑 IO 监督面板 + 画像字段（基础认知/梦想与理想/行为逻辑）+ 日记 AI 读取闭环（侧表/analyze_diaries/长短期计划） | ✅ |
| 2026-08-14 | 迭代2 构建验证（Android/Windows）+ 修复 analyze_diaries 未入 validActions 导致任务被丢弃 | ✅ |
| 2026-08-15 | 阶段3 迭代3：任务执行可靠性（信号后立即派发 + scheduled 空时刻放行 + 执行结果 toast + 实验室类型标签/执行记录 + 任务详情弹窗）+ 工具函数（`moodiary/agent` 原生通道回前台/屏幕常亮 · 强制锁屏 canPop:false/常亮/无逃生门 · open_diary 定位打开指定日记） | ✅ |
| 2026-08-16 | 迭代3 收尾：**系统级全屏悬浮窗强制锁屏**（SYSTEM_ALERT_WINDOW，TYPE_APPLICATION_OVERLAY 覆盖所有应用 + 拦截 Home 手势，Dart 倒计时驱动，一次授权后长期可用；阶段4 block_phone 提前实现）+ 迭代3 任务详情弹窗；Android/Windows 构建已同步 | ✅ 真机验证：系统级悬浮窗覆盖全屏、Home 手势被拦截 |
| 2026-08-16 | 阶段3 迭代4（思考框架）：**决策前思考清单**（价值/打扰预算/结果导向/时机/自检）+ **规划参考框架**（打扰分级/完成标志/拆步/依赖/贴合画像）+ **执行后反思学习回路**（BrainReflect：有用户反应的任务终态后 20min 节流复盘沉淀画像）+ **发起会话耳机语音**（`hasBluetoothHeadset` AudioManager 免权限检测，有蓝牙耳机先 TTS 播报开场白再切对话页，无耳机直接切）| 🔜 构建验证 |
| 2026-08-16 | 修复「发起会话 13 次未收到」：根因 = 助手页 fenix 注册后 `_execStartChat` 走静默注入分支（跳过 TTS/回前台/切页）；重构为**每次完整送达**（TTS→回前台→切页→注入，已在此页才直接注入）+ **防连发守卫**（已有等待回应的会话则跳过重复发起） | ✅ 真机验证：消息抵达用户；重复 start_chat 被守卫拦截 |
| 2026-08-16 | 修复并发派发竞态：多个信号连发 `runDueNow`（不经 `_busy` 守卫）导致两次派发取到同一批任务、防连发守卫竞态漏判；加 `_dispatching` **串行派发锁**（`_dispatchDueTasks` 包装 + `_dispatchDueTasksLocked` 原体） | ✅ 已装真机：Android 构建验证 |
