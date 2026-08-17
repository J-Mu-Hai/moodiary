# 智能体任务说明书（Agent Task Spec）

> 给开发（你）看的"它该做什么"的验收基线。开发阶段持续更新；
> 每完成一项功能，在对应行标注 ✅/🔜，与 [agent_framework.md](agent_framework.md) 的里程碑对照。

## 一句定位

**温晚照（Sonder）** 是来自异世界不寐市的人生梦境修补师，机缘巧合认识了现世的这位朋友：
TA 写的日记像记忆碎片一样落到她面前。她陪你拼碎片、不删除不覆盖不篡改，让你能接受，然后睡下。
人格定义见 [assets/ai/prompts/sonder_persona.txt](../assets/ai/prompts/sonder_persona.txt)（角色卡·对话版），
注入对话 / 规划 / 复盘三处，保证它是同一个人。

**人格分三层（只让"说话风格"常驻对话，细节按需查）：**
- L1 角色卡 `sonder_persona.txt`：身份一句话 + 说话风格 + 关系速查，每次对话注入（~400 字）；
- L2 完整档案 `character_bible.md`：城市/职业/成长/师父/闺蜜等，**不进对话**，按需由 `get_lore` 取用；
- L3 `get_lore` 函数：模型记不清细节时用 `[[CALL:get_lore|{"topic":"师父"}]]` 查档案（复用 getUniversalValues 的按需检索模式）。

## 能力清单（验收基线）

| 能力 | 说明 | 实现 | 状态 |
|---|---|---|---|
| 陪伴聊天 | 倾听、共情、启发式对话，注入画像与角色卡 | assistant_logic + system_base + sonder_persona | ✅ |
| 记住你 | 沉淀画像，跨天记住习惯/情绪/目标/困境 | MemoryService + memory_consolidate | ✅ |

**画像结构（v2）**：9 大类常驻槽位（基础认知/生活习惯/情绪状态/偏好与习惯/目标与痛点/人际关系/行为规律/梦想与理想/行为逻辑），
每条认知带 `confidence`（0-1，决定智能体说话语气）+ `source`（explicit/diary_analysis/pattern_recognition/interaction/legacy）。
旧数据自动迁移（来源记 `legacy`，置信 0.6）。展示在「使用时间」页按类别分组 + 置信/来源徽标。
| 语音提醒 | 到点 TTS 播报（蓝牙耳机优先私密播报） | TtsSpeaker + AgentExecutor.tts | ✅ |
| 发起会话 | 有耳机先语音开场白再切对话页；无耳机直接切；每次完整送达+防连发 | AgentExecutor.start_chat/ask_user | ✅ 真机验证 |
| 任务规划 | 信号/规则 → 模型决策 → 拆成 immediate/scheduled/longterm 任务 | AgentBrain + brain_plan.txt | ✅ |
| 执行监督 | 任务库可视化、执行记录、失败重试/取消、看门狗 | BrainService + 实验室页 | ✅ |
| 强制锁屏 | 系统级悬浮窗覆盖所有应用+拦截 Home 手势；无权限回退 App 内 | BlockScreenPage + overlay_force_lock | ✅ 真机验证 |
| 日记分析 | 读未读日记 → 沉淀画像 / 建聊天任务 → 标记已读 | AgentExecutor.analyze_diaries | ✅ |
| 主动信号 | 天气/日记稳定/使用类别/画像未初始化/长期计划回访 | BrainMonitor | ✅ |
| 反思学习 | 终态任务复盘 → 提炼画像要点（20min 节流） | BrainReflect + brain_reflect.txt | 🔜 待真机验证 |
| 思考框架 | 决策前思考清单 + 规划参考框架 + 打扰分级 | brain_plan.txt | ✅ |
| IO 观察 | 按日期归档"输入/输出"（开发用） | brainDecisionLog + 实验室页 | ✅ |
| 人格分层 | 角色卡常驻 + 完整档案按需 get_lore 检索 | sonder_persona + character_bible + get_lore | ✅ 待真机验证 |

## 边界（它不做什么）

- 不假装真人、不编造我们共同的过去。
- 不替用户做决定、不居高临下说教、不空洞讨好。
- 不刷存在感：绝大多数信号可以判断"无需行动"；默认 gentle。
- 后台被杀后无法唤醒（Android 12+ 限制，依赖 FGS 保活），App 活着才工作。

## 验证路径（实验室页）

1. 触发任意「模拟」信号 → 任务库出现规划 → 自动派发执行 → toast 反馈。
2. 加规则"每天 23 点提醒我睡觉" → 生成 scheduled 定时任务。
3. 回复助手页 ask_user → 任务 done + 按日期日志出现 `feedback` 记录 + 反思沉淀画像。
4. 「智能体输入/输出记录（按日期）」查看每天决策的上下文与输出。
