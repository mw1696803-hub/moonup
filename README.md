# MoonUp Rete：MoonBit 产生式规则引擎（Rete 网络）

[![CI](https://github.com/mw1696803-hub/moonup/actions/workflows/ci.yml/badge.svg)](https://github.com/mw1696803-hub/moonup/actions/workflows/ci.yml)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-mw1696803--hub%2Fmoonup%400.1.0-blue)](https://mooncakes.io/docs/mw1696803-hub/moonup@0.1.0)

**产生式规则引擎**：维护有状态的工作内存（多事实），规则按条件跨事实匹配，命中后执行动作、修改事实并连锁触发。核心基于 **Rete 算法**（Forgy 1974）——规则编译成共享网络，事实增删改时**增量传播**，不做全量重匹配。同一输入恒得同一输出，触发轨迹完整可审计。

与 mooncakes.io 已有的 `moonrule`（单条 JSON 表达式校验）互补：**moonrule 判断"输入合不合法"，MoonUp 判断"事实流变化时该做什么"**。

2026 MoonBit 黑客松参赛项目 · 十月赛 · MIT 许可证

## 为什么 MoonBit 需要它

成熟生态都有产生式规则引擎：Drools（JVM，ReteOO）、CLIPS（C）、rust-rule-engine（Rust）。MoonBit 目前只有表达式校验类包，缺少"多事实工作内存 + 跨事实匹配 + 增量传播 + 动作执行"这一层。MoonUp 补齐这个生态位，面向实时风控、工单路由、业务联动等事实流频繁变化的场景。

## 核心概念

```
规则集（条件 → 动作）
   │ 编译
   ▼
Rete 网络
  alpha 节点：单条件测试（共享子条件只算一次）
  beta 节点：跨事实变量绑定 join（订单 + 客户 + 设备）
  terminal 节点：规则完整匹配 → 待触发集合
   │
   ▼
工作内存（Working Memory）：insert / update / retract
   │ 增量传播：事实变化只重算受影响分支
   ▼
冲突消解：salience（优先级）+ specificity（条件数）+ recency（新近度）
   ▼
动作执行 → 修改事实 → 连锁激活（match-select-act 循环，fire limit 上限）
```

## 执行语义

本节明确三条核心机制的确定性语义，作为项目边界声明。

### 条件组合

- **AND（`&&`）**：一条规则的同一组内全部原子条件同时满足，规则才匹配。
- **OR（`||`）**：条件按 `||` 拆成若干组，**任一组内全部原子条件满足即匹配**；每组独立编译一条 alpha/beta 链，共享同一 terminal 节点。OR 必须位于顶层（不支持 `a && (b || c)` 内嵌，需表达式树解析，列入路线图）。
- **NOT（`!` 前缀）**：工作内存中**不存在**满足该条件的事实时该条件成立；实现上不建网络节点，terminal 判定时扫描工作内存全集。须与至少一个正条件搭配（单独否定无意义）。
- **跨事实引用（变量绑定 join）**：形如 `order.customer_id==customer.id`——同一事实类型内的字段比较走 alpha 节点；跨类型的字段绑定走 beta 节点，两个事实按绑定值 join。

### 激活管理（Activation）

- **激活何时产生**：事实经增量传播到达 terminal，且整条规则的条件（OR 组 + NOT）整体判定通过，才进入该规则的 agenda。
- **激活如何排序**（冲突消解，确定性）：`salience`（priority 大者先）→ `specificity`（条件数多者先）→ `recency`（token 中最新事实 id 大者先）→ `rule id` 字典序。
- **同 token 只触发一次**：规则触发后清空该 terminal 的 agenda，避免同一事实组合无限重复触发。
- **幂等保护**：动作修改事实后，若字段值未实际变化（或标签已存在），跳过重插，防止"改值→重插→再激活→再执行同一动作"的循环。
- **fire limit**：`fire_all(wm, limit?)` 上限默认 100，作为 match-select-act 循环的硬刹车。

### 事实撤回（Retract）

- `engine.remove(fid)`（即 `wm.retract(id)`）：从 alpha 内存删除该事实引用、从 beta 内存删除所有含该事实的 token、从 terminal agenda 删除所有含该事实的待触发激活。
- **语义边界**：撤回后，依赖该事实的部分匹配与**未执行**激活一并失效；已执行的动作不回滚（Rete 经典语义）。
- 当前实现对三层内存做全表过滤清理（而非指针级联删除），定位几十到几百条规则规模，清理开销与事实数线性相关；指针级联优化列入路线图。

## 条件 DSL

原子条件：`pattern.field==value`（等于）/ `!=`（不等于）/ `~=`（包含）/ `>` `<` `>=` `<=`（严格整数比较）；多条用 `&&` 连接（与）；`||` 连接 OR 组（或，任一组内全部原子条件满足即匹配，组可用括号包裹，必须位于顶层）；`!` 前缀为否定（工作内存中不存在满足该条件的事实才满足，须与至少一个正条件搭配）。跨事实引用形如 `order.customer_id==customer.id`（变量绑定 join）。

```moonbit
// OR：VIP 退款 或 大额订单，任一成立即触发
Rule("or_demo", "(customer.level==VIP && ticket.type==refund) || order.amount>100000",
     "action=manual_review", 10, "OR 组语义")

// NOT：下单且客户不在黑名单才自动放行（黑名单事实存在即拦截）
Rule("not_demo", "order.status==placed && !customer.blacklist==true",
     "action=auto_approve", 8, "否定语义")
```

## 最小示例

```moonbit
// 1. 定义规则：跨事实条件 + 变量绑定 + 动作
let rules = [
  Rule::new("risk_manual", "大额新客风控",
    "order.amount>100000 && customer.is_new==true",
    "action=manual_review",
    10, "大额+新客强制人工"),
  Rule::new("risk_vip", "VIP放行",
    "customer.level==VIP && order.amount<50000",
    "action=auto_pass",
    5, "VIP小额自动通过"),
]

// 2. 构造工作内存，插入事实
let wm = WorkingMemory::new()
wm.insert(Fact::new().set("type","customer").set("is_new","true").set("level","normal"))
wm.insert(Fact::new().set("type","order").set("amount","150000"))

// 3. 增量匹配 + 冲突消解 + 动作执行
let engine = ReteEngine::new(rules)
let result = engine.execute(wm)
// result.fired     → 触发的规则（按 salience/specificity/recency 排序）
// result.trace     → 每条规则的触发轨迹（可审计）
// result.facts     → 动作执行后的工作内存快照
```

## 与 moonrule 的差异

| 维度 | moonrule（已有） | MoonUp Rete（本仓库） |
|---|---|---|
| 回答的问题 | 这份 JSON 合不合法 | 事实流变化时哪些规则触发、顺序、动作 |
| 状态 | 无状态，单条数据求值 | 有状态工作内存，多事实 |
| 匹配 | 单条表达式 → true/false | 跨事实变量绑定 join |
| 增量 | 每次全量求值 | 增量传播，只重算受影响分支 |
| 执行 | 只判断，不改数据 | 动作修改事实 → 连锁激活 |

## 与成熟规则引擎的对比

本项目不追求复刻 Drools / rust-rule-engine 的全部能力，而是在 **MoonBit 生态**内提供一个可嵌入式、确定性、零依赖的 Rete MVP。下表逐项对照，明确边界：

| 能力 | rust-rule-engine (Rust, Grule 系) | Drools (JVM, ReteOO) | MoonUp Rete（本仓库） |
|---|---|---|---|
| 有状态工作内存 | ✅ | ✅ | ✅ |
| 跨事实变量绑定 join | ✅ | ✅ | ✅ |
| 增量传播（事实增删改） | ✅ RETE-UL 索引 | ✅ | ✅（全表过滤清理，未做 O(1) 索引） |
| AND / OR / NOT 条件 | ✅ GRL 表达式 | ✅ | ✅（OR 顶层组、NOT 全集扫描；括号嵌套路线图） |
| 冲突消解 | salience + 优先级 | salience + 复杂度 + 最近性 | salience → specificity → recency → rule id |
| 动作执行 + 连锁激活 | ✅ | ✅ | ✅（match-select-act，fire limit 100） |
| 事实撤回 | ✅ TMS 级联失效、多 justification | ✅ TMS | ✅ 三层内存清理、未执行激活失效；**不做** TMS 多理由归因 |
| 后向链式推理 | ✅ | ✅ | ❌ 明确不做（只做前向数据驱动） |
| 并行 / 分布式执行 | ✅ 多线程、Redis 流式后端 | ✅ Kie Server | ❌ 单线程确定性执行（嵌入式定位） |
| DSL 表达力 | GRL，方法调用、自定义函数 | 完整 Drools 规则语言 | 受限 DSL：原子比较 + 组合 + 赋值/标签；不做表达式求值与方法调用 |
| 嵌入形态 | Rust crate，原生 | JVM 容器 | **MoonBit 原生 + WASM**，浏览器/native 双端可跑 |
| 规模定位 | 100–10,000+ 条规则，生产级 | 企业级 | 几十到几百条规则，嵌入式 MVP |

**一句话定位**：rust-rule-engine / Drools 是生产级重型引擎；MoonUp 是 MoonBit 生态里第一个把"工作内存 + 跨事实 join + 增量传播 + 冲突消解 + 连锁激活"这条主链做完整的可嵌入式 MVP，边界清晰，不与重型引擎正面竞争。

## 五个领域示例（同一引擎）

```moonbit
// 实时风控：跨三类事实关联
Rule("risk", "order.amount>100000 && customer.is_new==true && device.risk>0.7", "action=manual_review", 10, "跨事实强制人工")

// 工单路由：多规则共享"客户等级==VIP"子条件（网络共享节点，一次测试）
Rule("r1", "customer.level==VIP && ticket.urgency==high", "route=vip_queue", 8, "VIP紧急优先")
Rule("r2", "customer.level==VIP && ticket.type==refund", "route=refund_queue", 5, "VIP退款专属")

// 库存联动：下单 → 扣库存 → 触发补货 → 连锁激活
Rule("stock", "stock.level<10 && stock.restock==false", "stock.restock=true & action=order_restock", 6, "低于阈值自动补货")

// 复合条件：OR 组（VIP 退款或大额订单）与 NOT 否定（非黑名单才放行）
Rule("or_demo", "(customer.level==VIP && ticket.type==refund) || order.amount>100000", "action=manual_review", 10, "任一组满足即触发")
Rule("not_demo", "order.status==placed && !customer.blacklist==true", "action=auto_approve", 8, "黑名单存在即拦截")
```

## 当前能力 vs 路线图

| 能力 | 状态 | 说明 |
|---|---|---|
| Rete 网络编译（alpha/beta/terminal） | ✅ | 规则 DSL → 共享网络 |
| 共享子条件（alpha 节点复用） | ✅ | 多条规则共享条件只测一次 |
| 跨事实变量绑定 join | ✅ | 一条规则匹配多条事实 |
| 工作内存 insert/update/retract | ✅ | 事实生命周期管理 |
| 增量传播 | ✅ | 事实变化只重算受影响分支 |
| 冲突消解（salience/specificity/recency） | ✅ | 确定性排序 |
| 动作执行 + 连锁激活 | ✅ | match-select-act，fire limit |
| 触发轨迹记录 | ✅ | 命中规则、顺序、字段变更，可审计 |
| WASM 导出 | ✅ | 浏览器本地运行 |
| 线性匹配模式 | ✅ | 规则量小时简单路径 |
| `\|\|` OR 组（顶层，组可括号包裹） | ✅ | 任一组成立即匹配；每组独立编译网络、共享 terminal |
| `!` 否定条件 | ✅ | 工作内存中不存在满足条件的事实才满足（扫描全集） |
| 括号嵌套（OR 内嵌于 AND，如 `a && (b \|\| c)`） | 🔜 路线图 | 需表达式树解析 |
| JSON/配置文件加载规则 | ✅ | `parse_rules_json`：规则集从 JSON 注入（id/condition/action 校验、带定位错误），引擎与业务解耦 |
| 大规模规则集性能基准 | ✅ | 见「性能基准」节（1000 规则 × 2000 事实实测） |

## 模块

| 模块 | 能力 |
|---|---|
| `rete` | Rete 网络编译、工作内存、增量传播、冲突消解、动作执行、OR/NOT 复合条件 DSL、JSON 规则加载（本仓库核心） |
| `engine` | 线性匹配模式（规则量小时简单路径，保留） |
| `evidence` / `guardrail` / `case` | 可选决策组件（建立在引擎之上、与引擎解耦，按需引入） |

## 快速开始

```bash
moon run main    # 端到端 Demo（跨事实风控 + 工单路由 + 库存联动 + OR/NOT + AI Agent + JSON 加载）
moon test        # 单元测试
moon build --release --target wasm-gc   # WASM 构建
```

规则集从 JSON 注入：

```json
{
  "rules": [
    {
      "id": "risk_hold",
      "condition": "order.amount>100000 && customer.is_new==true",
      "action": "action=manual_review & order.status=hold",
      "priority": 10
    }
  ]
}
```

```moonbit
let rules = parse_rules_json(json_str)  // Result[Array[ReteRule], String]，带定位错误
let engine = ReteEngine::new(rules!)
```

## 作为依赖安装（mooncakes.io）

```bash
moon add mw1696803-hub/moonup
```

然后在 `moon.pkg` 中引入：

```toml
import {
  "mw1696803-hub/moonup/lib/rete",
}
```

即可使用 `ReteEngine` / `WorkingMemory` / `ReteRule` / `FireResult`，把规则引擎嵌入你自己的 MoonBit 项目。

最小可用代码（已在一个全新的独立 MoonBit 项目中实测：`moon add` → `moon run main` 通过）：

```moonbit
let rules : Array[@rete.ReteRule] = [
  @rete.ReteRule::new(
    "risk_hold", "跨事实风控",
    "order.amount>100000 && customer.is_new==true && order.customer_id==customer.id",
    "action=manual_review & order.status=hold",
    10, "大额新客人工复核",
  ),
]
let eng = @rete.ReteEngine::new(rules)
let wm = @rete.WorkingMemory::new()
let cus = @rete.Fact::make("customer")
cus.set("is_new", "true"); cus.set("id", "c-1")
let ord = @rete.Fact::make("order")
ord.set("amount", "150000"); ord.set("customer_id", "c-1")
eng.insert(wm, cus); eng.insert(wm, ord)
let r = eng.fire_all(wm)
// 输出: fired rules: 1 / order.status=hold
```

> 验证记录：2026-10-21 在独立项目 `moonup-consume-test` 中执行 `moon add mw1696803-hub/moonup` 成功下载 `@0.1.0`，按上述代码编译运行，输出 `fired rules: 1` 与 `order.status=hold`，跨事实规则正确触发。包本身就是"轮子"：任何 MoonBit 项目一条命令接入。

## 作为 AI Agent 的决策后端

典型集成：LLM 负责把自然语言归约成结构化事实，引擎负责确定性裁决，trace 回喂给 LLM/用户做审计。

```moonbit
// LLM 已从用户原话抽出结构化字段（生产中这是 JSON → Fact 解析）
let wm = WorkingMemory::new()
wm.insert(Fact::make("customer").set("vip", "true"))
wm.insert(Fact::make("ticket").set("priority", "high").set("type", "refund"))

let engine = ReteEngine::new([
  Rule::new("vip_refund", "VIP退款", "customer.vip==true && ticket.type==refund",
    "ticket.route=senior_agent", 10, ""),
])
let result = engine.fire_all(wm)
// result.fired → ["vip_refund"]
// result.trace → ["rule=vip_refund facts=[1,2] action=ticket.route=senior_agent"]
// 同一字段组合恒得同一结果，且可解释为什么触发——LLM 可能幻觉，规则执行不会。
```

完整可运行示例见 `moon run main` 的 `[0E]` 段。开发历程与设计取舍见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 性能基准

`moon run tools/bench` 可复现（单线程确定性执行，`@env.now` 毫秒计时）：

| 规则数 | 事实数 | 网络编译 (ms) | insert + fire (ms) | 触发数 |
|---|---|---|---|---|
| 50 | 100 | 1 | 16 | 50 |
| 200 | 500 | 1 | 104 | 200 |
| 500 | 1000 | 2 | 758 | 500 |
| 1000 | 2000 | 8 | 4915 | 1000 |

环境：MoonBit `0.1.20260920`，CLI 与 WASM 同源。

观察与定位：
- 网络编译随规则数近似线性（1000 条仅 8ms）；
- insert + fire 随规则数超线性增长（每次插入触发后 terminal 全量重匹配）——这决定了本引擎的目标规模是**几十到几百条规则**、事实流频繁变化的嵌入式场景；
- 1000 条规则 × 2000 事实约 5s，属可运行上限附近，不建议继续堆规模；
- 尚未提供与 Drools / rust-rule-engine 的跨实现对比（本基准为量级参考，非官方跑分）。

## 网页演示

[MoonUp 交互演示页](docs/moonup-demo.html) — 左右分栏展示"规则代码 → 引擎真实输出"，五个领域 tab（跨事实风控 / 共享子条件路由 / 库存连锁 / OR-NOT 复合 / JSON 配置加载）共用同一 WASM 核心。

## 验收标准对照（2026 MoonBit 黑客松）

| 验收标准 | 状态 | 证据位置 |
|---|---|---|
| 01 MoonBit 为主要实现语言 | ✅ | 核心逻辑、规则执行与测试全部 MoonBit 实现 |
| 02 仓库公开，连续可追踪提交 | ✅ | 本仓库持续提交，CI 见 GitHub Actions |
| 03 README、可运行示例、必要测试 | ✅ | 本 README；`moon run main`；`moon test` |
| 04 本期实质新增 | ✅ | Rete 网络、工作内存、增量传播、冲突消解均为本期新增 |
| 05 开源合规：许可证与参考来源 | ✅ | MIT；Rete 算法与 Drools 设计思想参考见「原创 / 参考」 |
| 06 AI 可解释 | ✅ | 见「AI 使用说明」 |
| 07 发布到 mooncakes.io | ✅ | 已发布 `mw1696803-hub/moonup@0.1.0`（[包页](https://mooncakes.io/docs/mw1696803-hub/moonup@0.1.0)），`moon add mw1696803-hub/moonup` 可直接依赖 |

## 原创 / 参考说明

- 全部代码以 MoonBit 从零实现，MIT 许可证；
- 算法参考 Rete 算法（Charles Forgy, 1974/1979，公开学术成果）；
- 架构概念参考 Drools ReteOO（Apache-2.0）、rust-rule-engine（MIT）：节点划分、冲突消解、match-select-act 循环；
- 与 moonrule（Apache-2.0，表达式校验）为互补关系，非重复实现：其管输入合法性，本引擎管产生式推理。

## AI 使用说明

AI 辅助范围：代码脚手架、接口设计辅助、测试用例生成、文档起草。参赛者负责并逐条审查：架构设计、Rete 网络实现、冲突消解策略、技术选型与全部测试验证。

## 构建验证

- 工具链：`moon 0.1.20260920`
- `moon test` → 全部通过
- `moon run main` → 端到端 Demo 正常输出
- `moon build --release --target wasm-gc` → WASM 构建成功
