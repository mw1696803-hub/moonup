# MoonUp 设计文档

## 定位

MoonUp 是面向"向上管理"场景的**确定性决策引擎**（MoonBit 核心库）。不做自然语言理解，只做结构化判断：外层应用负责把原始对话/记录清洗为结构化输入，MoonUp 负责把输入转化为可解释、可审计的决策结果。

## 设计原则

1. **确定性**：同一输入必得同一输出；所有判断由规则/映射表驱动，不做概率猜测、不做主观打分。
2. **无幻觉**：缺失信息输出「待补充」，低置信度强制给出验证动作，不编造事实。
3. **可测试**：每个模块配单元测试，规则变更必须先改测试。
4. **可组合**：模块间通过结构化数据传递（情景→证据→路由→护栏→假设→案例→报告），可单独复用。

## 数据流

```
输入（情境特征词 / 证据条目 / 信号）
  │
  ▼
[ogsm]     情境清洗：Objective/Gap/Situation/下一步 四元组 + 事实分离 + fight/flight 漂移检测
  │
  ▼
[evidence] 证据分级：来源→权重（3/2/1）→ 分离标注（事实/推断/假设）→ 置信度合成
  │
  ▼
[scenario] 场景路由：16 类情境关键词匹配 → top2 + 路由规则提示
  │
  ▼
[guardrail] 防偏见：8 类护栏触发检查 → 5 项必查
  │
  ▼
[hypothesis] 假设空间：候选约束为 2-4 条 + 验证动作 + 最值得优先
  │
  ▼
[case]    案例检索：场景标签匹配 → top3 + 迁移原则 + 不匹配点
  │
  ▼
[output]  12 段结构化报告 + Safety Boundaries
```

## 模块规则摘要

### ogsm（lib/ogsm）

- 输入：`Ogsm` 四元组 + `FactSeparation` + 两个布尔信号（措辞漂亮/行为矛盾）
- 四元组任一为空 → 标记空字段并 `valid=false`（不继续下游）
- 漂移检测：目标含战斗词（证明/赢/认错）→ Fight；含逃跑词（沉默/算了）→ Flight；措辞漂亮且行为矛盾 → 弱证据警告

### evidence（lib/evidence）

- 15 类来源 → 权重映射：书面承诺/资源分配/结果变化/重复行为/权责匹配/会议记录 = 3；重复措辞/同事反馈/会议纪要/时间模式 = 2；单次口头/漂亮话/单次转写/猜测/语气 = 1
- 分离标注自动判定：权重 3 类来源 → KnownFact；2 类 → ReasonableInference；1 类 → UnverifiedHypothesis
- 置信度合成：存在权重 3 → High；仅权重 2 → Medium；仅权重 1 → Low + 强制验证动作；空 → Low + 先收集

### scenario（lib/scenario）

- 16 类场景（含组织机制问题），每类关键词表
- 命中计数 → top2（同分按枚举序）
- 路由规则：多领导→先对齐；跨职能→组合工具；组织机制→先看系统；画饼→转书面条件

### guardrail（lib/guardrail）

- 8 类护栏触发规则（见 guardrail.mbt 注释）
- 触发任意护栏 → 输出 5 项 Required Check

### hypothesis（lib/hypothesis）

- 候选 <2 补默认；>4 截取并标记 truncated
- 最值得优先 = 缺失信息最少（验证成本最低）
- 单条缺失 → next_move = "只需验证一条"

### case（lib/case）

- 案例卡片：场景标签/权力/动作/风险/来源/迁移原则/脚本/失效条件 + hit_count 沉淀信号
- 标签匹配检索 → score 降序 top3 + 不匹配点提示；superseded 不参与匹配；同分 verified 优先
- 内置 5 个通用模式案例（生产环境替换为脱敏案例）
- **生长口子（v2）**：
  - `add_card` 追加（校验必填字段 + id 去重）、`import_cards` 批量导入、`export_cards` 导出
  - `save_json` / `load_json`：案例库整体 JSON 序列化/反序列化（落盘数据层，宿主负责文件读写；损坏/旧版格式 → Err 不 panic）
  - `record_feedback`：反馈闭环（positive → verified / negative → superseded）
  - `supersede`：修正处理（保留卡片 + 修正记录，不覆盖不删除）
  - status 三态：tentative / verified / superseded
- **沉淀方向（后续逐步完善）**：落盘加载 → 命中计数跨会话累计 → 高频 + 已验证案例沉淀为"适合用户自身的机制"候选 → 多场景重复反馈（≥2-3 个不同场景）才升级为规则

### output（lib/output）

- 12 段模板（OGS-M/认知/假设/双面解读/状态校准/证据/案例/动作/第三选项/建议/脚本/观察）
- 键值对输入，缺失键 → 「待补充」
- Safety Boundaries 7 条

## 与源素材的映射

| MoonUp 模块 | 源素材（upward-management-coach Skill） |
|---|---|
| ogsm | references/02-ogsm-cleaning.md |
| evidence | references/07-evidence-confidence.md |
| scenario | references/10-scenario-router.md |
| guardrail | references/06-bias-guardrails.md |
| hypothesis | references/07-evidence-confidence.md（Hypothesis Check）+ SKILL.md 输出模板第 3 段 |
| case | references/18-case-library-ingestion.md |
| output | SKILL.md Default Output Shape |

## 测试基线

- 63 个单元测试，`moon test` 全过
- Demo（`moon run main`）：7 段分模块演示 + MVP 单情境全链路
