/// WASM API 导出：
/// - moonup_demo_engine：线性规则引擎演示（客服分流 + 风控审核，旧 engine 模块）
/// - moonup_rete_demo：Rete 产生式规则引擎演示（跨事实风控 / 工单路由 / 库存连锁）
/// 旧 7 模块决策管线入口（moonup_run）已随向上管理模块移除。
fn join_sep(arr : Array[String]) -> String {
  let mut s = ""
  let mut i = 0
  while i < arr.length() {
    if i > 0 {
      s = s + "；"
    }
    s = s + arr[i]
    i = i + 1
  }
  s
}

/// 通用引擎演示：两个完全不同业务领域共用同一个 @engine 核心
/// 不接受输入，直接跑客服分流 + 风控审核两个例子
#export_name("moonup_demo_engine")
pub fn demo_engine() -> String {
  let mut out = "=== 通用规则引擎演示：客服分流 + 风控审核 ===\n"
  out = out + "（同一 @engine.RuleEngine 核心，只换规则数组，引擎零改动）\n\n"

  // --- 场景 A：客服分流 ---
  out = out + "--- 场景 A：客服分流规则集 ---\n"
  out = out + "规则:\n"
  out = out + "  cs1: intent==退款 && vip==true → route=VIP人工坐席 (priority=10)\n"
  out = out + "  cs2: intent==退款 → route=自助退款流程 (priority=5)\n"
  out = out + "  cs3: vip==true → tags+=VIP (priority=1)\n"
  out = out + "输入事实: intent=退款, vip=true\n"
  let cs_facts = @engine.Fact::new()
  cs_facts.set("intent", "退款")
  cs_facts.set("vip", "true")
  let cs_engine = @engine.RuleEngine::new([
    @engine.Rule::new("cs1", "VIP退款", "intent==退款 && vip==true", "route=VIP人工坐席", 10, "VIP退款转专属坐席"),
    @engine.Rule::new("cs2", "普通退款", "intent==退款", "route=自助退款流程", 5, "普通退款走自助"),
    @engine.Rule::new("cs3", "VIP标签", "vip==true", "tags+=VIP", 1, "所有VIP加标签"),
  ])
  let cs_r = cs_engine.execute(cs_facts)
  out = out + "命中 " + cs_r.matched.length().to_string() + " 条规则\n"
  out = out + "执行说明: " + join_sep(cs_r.notes) + "\n"
  out = out + "输出结果: route=" + cs_r.facts.get("route") + ", tags=" + cs_r.facts.get("tags") + "\n\n"

  // --- 场景 B：风控审核 ---
  out = out + "--- 场景 B：风控审核规则集（同一 engine） ---\n"
  out = out + "规则:\n"
  out = out + "  rk1: amount_tier==large && new_customer==true → action=人工复核 (priority=10)\n"
  out = out + "  rk2: amount_tier==large → action=加强验证 (priority=5)\n"
  out = out + "  rk3: amount_tier==small → action=自动通过 (priority=1)\n"
  out = out + "输入事实: amount=150000, new_customer=true\n"
  let rk_facts = @engine.Fact::new()
  rk_facts.set("amount", "150000")
  rk_facts.set("new_customer", "true")
  let rk_engine = @engine.RuleEngine::new([
    @engine.Rule::new("rk1", "大额新客", "amount>100000 && new_customer==true", "action=人工复核", 10, "大额+新客强制人工"),
    @engine.Rule::new("rk2", "普通大额", "amount>100000", "action=加强验证", 5, "大额加强验证"),
    @engine.Rule::new("rk3", "小额", "amount<1000", "action=自动通过", 1, "小额自动通过"),
  ])
  let rk_r = rk_engine.execute(rk_facts)
  out = out + "命中 " + rk_r.matched.length().to_string() + " 条规则\n"
  out = out + "执行说明: " + join_sep(rk_r.notes) + "\n"
  out = out + "输出结果: action=" + rk_r.facts.get("action") + "\n\n"

  out = out + "↑ 客服分流与风控审核共用 @engine 核心；规则集可替换为任意业务。"
  out
}

/// Rete 产生式规则引擎演示：三个不同领域共用同一个 @rete 核心
/// 不接受输入，直接跑跨事实风控 / 工单路由（共享子条件）/ 库存连锁激活
#export_name("moonup_rete_demo")
pub fn rete_demo() -> String {
  let mut out = "=== MoonUp Rete: MoonBit 产生式规则引擎（Rete 网络）===\n"
  out = out + "同一 @rete 核心：Rete 网络编译 + 工作内存 + 跨事实关联 + 增量传播 + 连锁激活\n\n"

  // --- 场景 A：跨事实风控（order × customer × device） ---
  out = out + "--- 场景 A：跨事实风控（order × customer × device）---\n"
  out = out + "规则: 大额订单 && 新客户 && 设备高风险 → 人工复核\n"
  out = out + "      order.customer_id==customer.id 跨事实绑定 join\n"
  let rk_rules : Array[@rete.ReteRule] = [
    @rete.ReteRule::new(
      "risk_hold",
      "跨事实风控",
      "order.amount>100000 && customer.is_new==true && device.risk==high && order.customer_id==customer.id",
      "action=manual_review & order.status=hold",
      10,
      "三类事实关联才触发",
    ),
    @rete.ReteRule::new(
      "risk_attach",
      "风控标签",
      "order.customer_id==customer.id && device.risk==high",
      "order.tags+=risk_device & customer.tags+=high_risk",
      5,
      "跨事实绑定命中即打标签",
    ),
  ]
  let rk_eng = @rete.ReteEngine::new(rk_rules)
  let rk_wm = @rete.WorkingMemory::new()
  let dev = @rete.Fact::make("device")
  dev.set("risk", "high")
  let cus = @rete.Fact::make("customer")
  cus.set("is_new", "true")
  cus.set("id", "c-1001")
  let ord = @rete.Fact::make("order")
  ord.set("amount", "150000")
  ord.set("customer_id", "c-1001")
  rk_eng.insert(rk_wm, dev)
  rk_eng.insert(rk_wm, cus)
  rk_eng.insert(rk_wm, ord)
  let rk_r = rk_eng.fire_all(rk_wm)
  out = out + "网络: alpha=" + rk_eng.alpha_count().to_string() + " beta=" +
    rk_eng.beta_count().to_string() + " terminal=" + rk_eng.terminal_count().to_string() + "\n"
  out = out + "触发: " + rk_r.fired.length().to_string() + " 条\n"
  let orders = rk_r.facts.filter(fn(f) { f.kind == "order" })
  if orders.length() > 0 {
    let of = orders[orders.length() - 1]
    out = out + "订单: status=" + of.get("status") + " tags=" + of.get("tags") + "\n"
  }
  let customers = rk_r.facts.filter(fn(f) { f.kind == "customer" })
  if customers.length() > 0 {
    out = out + "客户: tags=" + customers[0].get("tags") + "\n"
  }
  out = out + "\n"

  // --- 场景 B：工单路由（共享子条件 alpha 节点复用） ---
  out = out + "--- 场景 B：工单路由（共享子条件）---\n"
  out = out + "两条规则共享 customer.vip==true → 只编译一个 alpha 节点\n"
  let wm2 = @rete.WorkingMemory::new()
  let tick_rules : Array[@rete.ReteRule] = [
    @rete.ReteRule::new(
      "vip_senior",
      "VIP工单进资深坐席",
      "customer.vip==true && ticket.priority==high",
      "ticket.route=senior_agent",
      10,
      "VIP + 高优先级",
    ),
    @rete.ReteRule::new(
      "vip_sla",
      "VIP工单加急",
      "customer.vip==true && ticket.priority==high",
      "ticket.sla=15min",
      8,
      "共享 VIP 条件",
    ),
  ]
  let tick_eng = @rete.ReteEngine::new(tick_rules)
  let vip = @rete.Fact::make("customer")
  vip.set("vip", "true")
  vip.set("id", "c-7")
  let tick = @rete.Fact::make("ticket")
  tick.set("priority", "high")
  tick.set("customer_id", "c-7")
  tick_eng.insert(wm2, vip)
  tick_eng.insert(wm2, tick)
  out = out + "2 条规则 → alpha=" + tick_eng.alpha_count().to_string() +
    "（VIP 条件共享为 1 个节点，未重复编译）\n"
  let t_r = tick_eng.fire_all(wm2)
  out = out + "触发: " + join_names(t_r.fired) + "\n"
  let tickets = t_r.facts.filter(fn(f) { f.kind == "ticket" })
  if tickets.length() > 0 {
    let tf = tickets[tickets.length() - 1]
    out = out + "工单: route=" + tf.get("route") + " sla=" + tf.get("sla") + "\n"
  }
  out = out + "\n"

  // --- 场景 C：库存促销（连锁激活 + fire limit） ---
  out = out + "--- 场景 C：库存促销（连锁激活）---\n"
  out = out + "下单→扣库存→低于阈值补货→（补货后不再触发）\n"
  let inv_rules : Array[@rete.ReteRule] = [
    @rete.ReteRule::new(
      "stock_apply",
      "下单扣库存",
      "order.status==placed && product.stock>=order.qty",
      "product.stock-=order.qty & order.status=fulfilled",
      10,
      "订单成立即扣库存",
    ),
    @rete.ReteRule::new(
      "stock_reorder",
      "低库存补货",
      "product.stock<10",
      "product.stock+=100 & action=reorder_triggered",
      8,
      "低于阈值自动补货",
    ),
  ]
  let inv_eng = @rete.ReteEngine::new(inv_rules)
  let inv_wm = @rete.WorkingMemory::new()
  let prod = @rete.Fact::make("product")
  prod.set("stock", "5")
  let o1 = @rete.Fact::make("order")
  o1.set("status", "placed")
  o1.set("qty", "2")
  inv_eng.insert(inv_wm, prod)
  inv_eng.insert(inv_wm, o1)
  let inv_r = inv_eng.fire_all(inv_wm, limit=50)
  out = out + "触发链: " + join_names(inv_r.fired) + "\n"
  let prods = inv_r.facts.filter(fn(f) { f.kind == "product" })
  if prods.length() > 0 {
    out = out + "库存: " + prods[prods.length() - 1].get("stock") + "（5-2=3 <10 → 补货 +100）\n"
  }
  if inv_r.trace.length() > 0 {
    out = out + "轨迹:\n"
    for t in inv_r.trace {
      out = out + "  " + t + "\n"
    }
  }
  out = out + "\n"

  // --- 场景 D：OR / NOT 复合条件（DSL 增强） ---
  out = out + "--- 场景 D：OR / NOT 复合条件（DSL 增强）---\n"
  out = out + "规则1 (OR) : (customer.level==VIP && ticket.type==refund) || order.amount>100000\n"
  out = out + "规则2 (NOT): order.status==placed && !customer.blacklist==true\n"
  let dl_rules : Array[@rete.ReteRule] = [
    @rete.ReteRule::new(
      "or_rule",
      "VIP退款或大额订单",
      "(customer.level==VIP && ticket.type==refund) || order.amount>100000",
      "action=manual_review",
      10,
      "OR 组语义：任一组满足即触发",
    ),
    @rete.ReteRule::new(
      "not_rule",
      "下单且非黑名单",
      "order.status==placed && !customer.blacklist==true",
      "action=auto_approve",
      8,
      "NOT 语义：工作内存中不存在黑名单客户才触发",
    ),
  ]
  let dl_eng = @rete.ReteEngine::new(dl_rules)
  // OR 组 1 命中：VIP + refund
  let dl_wm1 = @rete.WorkingMemory::new()
  let dl_c = @rete.Fact::make("customer")
  dl_c.set("level", "VIP")
  let dl_t = @rete.Fact::make("ticket")
  dl_t.set("type", "refund")
  dl_eng.insert(dl_wm1, dl_c)
  dl_eng.insert(dl_wm1, dl_t)
  let dl_r1 = dl_eng.fire_all(dl_wm1)
  out = out + "  输入 VIP+退款工单 → 触发: " + join_names(dl_r1.fired) + "\n"
  // OR 组 2 命中：大额订单（无 VIP 客户）
  let dl_wm2 = @rete.WorkingMemory::new()
  let dl_o = @rete.Fact::make("order")
  dl_o.set("amount", "150000")
  dl_eng.insert(dl_wm2, dl_o)
  let dl_r2 = dl_eng.fire_all(dl_wm2)
  out = out + "  输入 15 万订单（无 VIP）→ 触发: " + join_names(dl_r2.fired) + "\n"
  // NOT：无黑名单客户 → 命中
  let dl_wm3 = @rete.WorkingMemory::new()
  let dl_o2 = @rete.Fact::make("order")
  dl_o2.set("status", "placed")
  dl_eng.insert(dl_wm3, dl_o2)
  let dl_r3 = dl_eng.fire_all(dl_wm3)
  out = out + "  输入 placed 订单（无客户）→ 触发: " + join_names(dl_r3.fired) + "\n"
  // NOT：黑名单客户存在 → 不命中
  let dl_wm4 = @rete.WorkingMemory::new()
  let dl_b = @rete.Fact::make("customer")
  dl_b.set("blacklist", "true")
  let dl_o3 = @rete.Fact::make("order")
  dl_o3.set("status", "placed")
  dl_eng.insert(dl_wm4, dl_b)
  dl_eng.insert(dl_wm4, dl_o3)
  let dl_r4 = dl_eng.fire_all(dl_wm4)
  out = out + "  输入 placed 订单 + 黑名单客户 → 触发: " + join_names(dl_r4.fired) + "（NOT 拦截）\n"
  out = out + "\n↑ 同一引擎零修改承载三个领域：规则即数据，引擎与业务语义解耦。"
  out
}

fn join_names(arr : Array[String]) -> String {
  let mut s = ""
  let mut i = 0
  while i < arr.length() {
    if i > 0 {
      s = s + ", "
    }
    s = s + arr[i]
    i = i + 1
  }
  s
}
