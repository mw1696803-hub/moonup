# MoonUp Rete 可复现演示说明

本文件提供一键复现步骤与真实运行输出快照（2026-10-01 在 MoonBit 工具链 `moon 0.1.20260920` 下实测），对应赛事验收标准 03「能够运行」。

## 一键复现

```bash
git clone https://github.com/mw1696803-hub/moonup.git
cd moonup
moon install        # 拉取依赖（仅 MoonBit core，无第三方依赖）
moon test           # 87 个单元测试（含 lib/rete 的 10 个 Rete 网络测试）
moon run main       # 端到端 Demo：跨事实风控 / 工单路由（共享 alpha）/ 库存连锁激活 + 可选组件
moon build --release --target wasm-gc   # 构建浏览器 WASM（docs/moonup.wasm）
```

## 运行要求

- MoonBit 工具链（`moon` 命令），安装见 <https://www.moonbitlang.com/download/>
- 纯 MoonBit core 实现，无任何第三方依赖
- 网页演示需 HTTP 服务打开 `docs/moonup-demo.html`（file:// 无法加载 WASM）

## 真实输出快照

### 1. moon test

```
Total tests: 87, passed: 87, failed: 0.
```

### 2. moon run main（真实 stdout，未删改）

```text
﻿=== MoonUp Rete: MoonBit 产生式规则引擎（Rete 网络）===

[0A] 实时风控：跨事实关联（order × customer × device）
    规则：大额订单 && 新客户 && 设备高风险 → 人工复核
    alpha节点=5 beta节点=6 terminal=2
    触发 5 条: risk_hold, risk_hold, risk_attach, risk_hold, risk_attach
    订单最终状态: status=hold tags=risk_device
    客户标签: high_risk
    ↑ 同一引擎承载跨事实关联；new_customer/大额/高风险分开是三条规则也各自成立

[0B] 工单路由：共享子条件（VIP 条件只编译一次）
    两条规则共享 customer.vip==true，Rete 共享该 alpha 节点
    共享前条件数=2 条规则 → alpha节点=2（VIP 条件 1 个共享节点，未重复编译）
    触发 5 条: vip_senior, vip_senior, vip_sla, vip_senior, vip_sla

[0C] 库存促销：连锁激活（下单→扣库存→补货→再触发）
    触发链: stock_apply, stock_reorder
    触发轨迹（前 3 条）:
      rule=stock_apply facts=[2,1,2] action=product.stock-=order.qty & order.status=fulfilled
      rule=stock_reorder facts=[3] action=product.stock+=100 & action=reorder_triggered
    ↑ 动作修改事实会触发增量传播与连锁激活，fire limit 防止无限循环

[1] Evidence 证据分级（可选组件，与引擎解耦）
  置信度: High | 证据 4 条，整体置信度高；存在高权重证据（书面/资源/结果/重复行为），结论可靠
  缺失信息: SLA 违约认定标准, 审批负责人
  ↑ 任何需要证据分级的决策过程都可复用（风控举证、审核材料、绩效评估等）

[2] Guardrail 决策偏见护栏（可选组件，与引擎解耦）
  是否安全通过: false
    ⚠ 转述放大痛苦：转述可能放大痛苦时刻，回到证据清单
    ⚠ 措辞与行为矛盾：措辞漂亮但行为矛盾，以重复行为为准
    ⚠ 希望扭曲判断：急需认可易过度信任承诺，先验证
    ⚠ 过度共情叙述者：单方叙述+情绪浓，保持中立
  必查项:
    · 什么证据支持这个解读？
    · 什么证据反对它？
    · 什么会改变结论？
    · 有没有更安全的小测试？
    · 用户当前状态能否执行这条建议？
  ↑ 防的是决策偏见本身（转述放大/措辞矛盾/仅凭感觉），不绑定任何业务场景

[3] Case 案例库（可选组件，与引擎解耦）
  命中 2 条内置示例案例（演示数据，机制可接任意领域）
    · c-promotion [口头承诺转为书面条件，按时间线验证兑现]
    · c-multi-leader [多领导冲突先对齐再执行：让领导当面确认优先级排序]
  落盘 round-trip: JSON 2330 字符 → 恢复 6 条
  ↑ 案例沉淀机制（命中计数/反馈闭环）与领域无关，可接任意规则引擎结果
```

## Demo 各段说明

| 段 | 模块 | 演示内容 |
|----|------|----------|
| [0A] | rete | 跨事实风控：order × customer × device 三类事实变量绑定 join，命中后动作修改事实（status=hold + 标签累积） |
| [0B] | rete | 工单路由：两条规则共享 `customer.vip==true` 子条件，Rete 只编译一个 alpha 节点（alpha 数 = 2 而非 3） |
| [0C] | rete | 库存连锁激活：下单→扣库存→低库存补货→补货后不再触发（增量传播 + fire limit + 幂等保护） |
| [1] | evidence | 证据分级（书面/资源/口头/猜测）+ 置信度合成 + 缺失信息清单（可选组件，与引擎解耦，示例数据为演示用） |
| [2] | guardrail | 决策偏见护栏（转述放大/措辞矛盾/仅凭感觉等），不绑定业务场景 |
| [3] | case | 案例库落盘 round-trip + 命中计数/反馈闭环机制（与领域无关，内置案例为演示数据） |

## 验证说明

- 所有输出为本仓库 `main` 分支 `moon run main` 的真实 stdout，未做删改
- 同一规则集 + 同一事实流恒得同一输出（确定性规则引擎，无随机性）
- Rete 网络测试（lib/rete/rete_test.mbt）覆盖：单条件触发 / 跨事实 join / 共享 alpha 节点 / 冲突消解（salience→specificity→recency）/ 动作修改事实连锁激活 / 幂等自触发保护 / retract 清理 / 数字比较边界 / 标签累积
