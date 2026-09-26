# MoonUp：向上管理决策引擎

面向"向上管理"场景的结构化决策引擎，使用 [MoonBit](https://www.moonbitlang.com/) 实现。

> 2026 MoonBit 黑客松参赛项目 · 九月赛

## 是什么

**MoonUp** 不是聊天机器人，而是一个可复用的决策推理库：把"向上管理教练"的推理流程（情境清洗 → 证据分级 → 场景路由 → 防偏见护栏 → 假设空间 → 案例检索 → 结构化输出）引擎化为确定性、可测试、无幻觉的 MoonBit 模块。自然语言理解留在外层，核心判断逻辑沉淀为可复用能力。

**解决什么问题**：把口头承诺当真、被分配权责不清的任务、靠情绪判断老板的真实态度——这些经验依赖个人天赋、无法复制。MoonUp 输入与上级的互动记录，输出证据分级、置信度和下一步动作，让向上沟通从"凭感觉"变成"可验证"。

## 模块（全部完成，63 个单元测试通过）

| 模块 | 能力 |
|------|------|
| `ogsm` | OGS-M 情境清洗：目标/差距/情境/下一步四元组 + 事实分离 + fight/flight 漂移检测 |
| `evidence` | 证据分级（书面/资源/结果=高，措辞/反馈=中，单次口头/猜测=低）+ 事实/推断/假设三分离 + 置信度合成 + 低置信度强制验证动作 |
| `scenario` | 16 类情境场景路由（含组织机制问题）+ top2 命中 + 路由规则提示 |
| `guardrail` | 8 类防偏见护栏（转述放大/措辞矛盾/文化语义/过度共情/疲惫/希望扭曲…）+ 5 项必查 |
| `hypothesis` | 2-4 假设空间生成 + 验证动作 + 最值得优先判定 |
| `case` | 案例卡片标签检索 + 迁移原则 + 不匹配点提示；落盘（save_json/load_json）+ 反馈闭环（feedback）+ 修正处理（supersede）+ 命中计数 → 机制候选 |
| `output` | 12 段结构化报告模板 + Safety Boundaries 7 条安全边界 |

## 快速开始

```bash
moon run main              # 端到端 Demo：7 段分模块演示 + MVP 单情境全链路
moon test                  # 93 个单元测试
moon run tools/export_cases > cases/cases.json   # 导出案例库落盘示例（纯 JSON）
```

## MVP 演示（moon run main）

Demo 覆盖：OGS-M 清洗 → 证据分级与置信度 → 场景路由 → 防偏见检查 → 假设空间 → 案例检索 → 12 段结构化报告，并以一个完整情境（口头晋升承诺 + 多头领导）走完全管线。

## 架构

```
输入（结构化情境/特征）
  → ogsm（清洗四元组 + 事实分离 + 漂移检测）
  → evidence（证据分级 + 置信度）
  → scenario（场景路由）
  → guardrail（防偏见检查）
  → hypothesis（假设空间）
  → case（案例参考）
  → output（12 段报告）
```

## 案例沉淀（case 生长口子）

- **落盘数据层**：`save_json()` / `load_json()` 将案例库整体序列化/反序列化（MoonBit core 无文件 IO，宿主负责真实文件读写；损坏/旧版格式返回 Err 不崩溃）。落盘示例见 [`cases/cases.json`](cases/cases.json)（25 条，含 verified/superseded/hit_count 真实沉淀状态）。
- **反馈闭环**：`record_feedback(card_id, positive|negative)` —— 正反馈 → `verified`，负反馈 → `superseded`（修正优先，不覆盖不删除）。
- **命中计数**：`search` 命中自动 `hit_count +1`，跨会话通过落盘累计。
- **机制候选雏形**：`mechanism_candidates(min_hits)` 返回「命中 ≥ 阈值 且 已验证」的案例，供人工确认固化为适合用户自身的机制；多场景重复反馈（≥2-3 个不同场景）后才升级为规则。

## 素材来源

推理规则来源于自研的 upward-management-coach AI Skill（21 个 references + 案例库），本项目将其确定性规则引擎化为 MoonBit 实现。全部代码原创，采用 MIT 许可证。
