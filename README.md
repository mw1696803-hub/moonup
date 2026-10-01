# MoonUp Rete：MoonBit 产生式规则引擎（Rete 网络）

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

## 三个领域示例（同一引擎）

```moonbit
// 实时风控：跨三类事实关联
Rule("risk", "order.amount>100000 && customer.is_new==true && device.risk>0.7", "action=manual_review", 10, "跨事实强制人工")

// 工单路由：多规则共享"客户等级==VIP"子条件（网络共享节点，一次测试）
Rule("r1", "customer.level==VIP && ticket.urgency==high", "route=vip_queue", 8, "VIP紧急优先")
Rule("r2", "customer.level==VIP && ticket.type==refund", "route=refund_queue", 5, "VIP退款专属")

// 库存联动：下单 → 扣库存 → 触发补货 → 连锁激活
Rule("stock", "stock.level<10 && stock.restock==false", "stock.restock=true & action=order_restock", 6, "低于阈值自动补货")
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
| `\|\|` / `!` / 括号嵌套 DSL | 🔜 路线图 | |
| JSON/配置文件加载规则 | 🔜 路线图 | 当前 MoonBit API 注入 |
| 大规模规则集性能基准 | 🔜 路线图 | 定位几十到几百条规则 |

## 模块

| 模块 | 能力 |
|---|---|
| `rete` | Rete 网络编译、工作内存、增量传播、冲突消解、动作执行（本仓库核心） |
| `engine` | 线性匹配模式（规则量小时简单路径，保留） |
| `evidence` / `guardrail` / `hypothesis` / `scenario` / `case` / `ogsm` / `output` | 可选决策组件（建立在引擎之上，按需引入） |

## 快速开始

```bash
moon run main    # 端到端 Demo（跨事实风控 + 工单路由 + 库存联动）
moon test        # 单元测试
moon build --release --target wasm-gc   # WASM 构建
```

## 网页演示

[MoonUp 交互演示页](docs/moonup-demo.html) — 左右分栏展示"规则代码 → 引擎真实输出"，三个领域 tab 共用同一 WASM 核心。

## 验收标准对照（2026 MoonBit 黑客松）

| 验收标准 | 状态 | 证据位置 |
|---|---|---|
| 01 MoonBit 为主要实现语言 | ✅ | 核心逻辑、规则执行与测试全部 MoonBit 实现 |
| 02 仓库公开，连续可追踪提交 | ✅ | 本仓库持续提交，CI 见 GitHub Actions |
| 03 README、可运行示例、必要测试 | ✅ | 本 README；`moon run main`；`moon test` |
| 04 本期实质新增 | ✅ | Rete 网络、工作内存、增量传播、冲突消解均为本期新增 |
| 05 开源合规：许可证与参考来源 | ✅ | MIT；Rete 算法与 Drools 设计思想参考见「原创 / 参考」 |
| 06 AI 可解释 | ✅ | 见「AI 使用说明」 |

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
