# Upward Management Core

面向"向上管理"场景的结构化决策引擎，使用 [MoonBit](https://www.moonbitlang.com/) 实现。

> 2026 MoonBit 黑客松参赛项目 · 九月赛

## 是什么

**Upward Management Core** 不是聊天机器人，而是一个可复用的核心推理库：把"向上管理教练"的推理流程（情境清洗 → 证据分级 → 场景路由 → 假设空间 → 防偏见护栏 → 案例检索 → 结构化输出）引擎化为确定性、可测试、无幻觉的 MoonBit 模块。自然语言理解留在外层，核心判断逻辑沉淀为可复用能力。

## 模块

| 模块 | 能力 |
|------|------|
| `ogsm` | OGS-M 情境清洗：目标/差距/情境/下一步 四元组 + 事实分离 + fight/flight 漂移检测 |
| `evidence` | 证据分级（高/中/低）+ 事实/推断/假设三分离 + 置信度计算（规划中） |
| `scenario` | 场景路由：15 类情境枚举 + 路由规则（规划中） |
| `guardrail` | 防偏见护栏：转述失真/漂亮话矛盾/过度共情检测（规划中） |
| `hypothesis` | 2-4 假设空间生成 + 验证动作（规划中） |
| `case` | 案例卡片检索（规划中） |
| `output` | 12 段结构化输出模板（规划中） |

## 快速开始

```bash
moon run main   # OGS-M 清洗 Demo
moon test       # 单元测试
```

## 素材来源

推理规则来源于自研的 upward-management-coach AI Skill（21 个 references + 案例库），本项目将其确定性规则引擎化。
