/// MoonUp Rete — MoonBit 产生式规则引擎（CLI Demo）
///
/// 主叙事：Rete 网络 + 工作内存 + 跨事实关联 + 连锁激活。
/// [0] 三个不同领域的跨事实场景，共用同一个 @rete 核心；
/// [1]-[3] 可选决策组件（evidence / guardrail / case）以通用口径展示。
fn main {
  println("=== MoonUp Rete: MoonBit 产生式规则引擎（Rete 网络）===")

  // ---------------------------------------------------------------
  // [0] 场景 A：实时风控 —— 跨三类事实关联（order × customer × device）
  // ---------------------------------------------------------------
  println("\n[0A] 实时风控：跨事实关联（order × customer × device）")
  println("    规则：大额订单 && 新客户 && 设备高风险 → 人工复核")
  let rk_rules : Array[@rete.ReteRule] = [
    @rete.ReteRule::new(
      "risk_hold",
      "跨事实风控",
      "order.amount>100000 && customer.is_new==true && device.risk==high && order.customer_id==customer.id",
      "action=manual_review & order.status=hold",
      10,
      "订单金额、客户属性、设备风险三类事实关联才触发",
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
  println("    alpha节点=" + rk_eng.alpha_count().to_string() + " beta节点=" +
    rk_eng.beta_count().to_string() + " terminal=" + rk_eng.terminal_count().to_string())
  let rk_r = rk_eng.fire_all(rk_wm)
  println("    触发 " + rk_r.fired.length().to_string() + " 条: " + join(rk_r.fired))
  let orders = rk_r.facts.filter(fn(f) { f.kind == "order" })
  if orders.length() > 0 {
    let of = orders[orders.length() - 1]
    println("    订单最终状态: status=" + of.get("status") + " tags=" + of.get("tags"))
  }
  let customers = rk_r.facts.filter(fn(f) { f.kind == "customer" })
  if customers.length() > 0 {
    println("    客户标签: " + customers[0].get("tags"))
  }
  println("    ↑ 同一引擎承载跨事实关联；new_customer/大额/高风险分开是三条规则也各自成立")

  // ---------------------------------------------------------------
  // [0] 场景 B：工单路由 —— 共享子条件（VIP 条件 alpha 节点复用）
  // ---------------------------------------------------------------
  println("\n[0B] 工单路由：共享子条件（VIP 条件只编译一次）")
  println("    两条规则共享 customer.vip==true，Rete 共享该 alpha 节点")
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
      "共享 VIP 条件，仅动作不同",
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
  println("    共享前条件数=2 条规则 → alpha节点=" + tick_eng.alpha_count().to_string() +
    "（VIP 条件 1 个共享节点，未重复编译）")
  let t_r = tick_eng.fire_all(wm2)
  println("    触发 " + t_r.fired.length().to_string() + " 条: " + join(t_r.fired))
  let t_final = wm2.get(2)
  match t_final {
    Some(f) => println("    工单: route=" + f.get("route") + " sla=" + f.get("sla"))
    None => ()
  }

  // ---------------------------------------------------------------
  // [0] 场景 C：库存促销 —— 动作修改事实 → 连锁激活（含 fire limit）
  // ---------------------------------------------------------------
  println("\n[0C] 库存促销：连锁激活（下单→扣库存→补货→再触发）")
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
  println("    触发链: " + join(inv_r.fired))
  let p_final = inv_wm.get(1)
  match p_final {
    Some(f) => println("    库存最终值: " + f.get("stock") + "（5-2 后触底 <10 → 补货 +100）")
    None => ()
  }
  println("    触发轨迹（前 3 条）:")
  let mut n = 0
  while n < inv_r.trace.length() && n < 3 {
    println("      " + inv_r.trace[n])
    n = n + 1
  }
  println("    ↑ 动作修改事实会触发增量传播与连锁激活，fire limit 防止无限循环")

  // ---------------------------------------------------------------
  // [1] 可选决策组件：Evidence 证据分级（通用口径）
  // ---------------------------------------------------------------
  println("\n[1] Evidence 证据分级（可选组件，与引擎解耦）")
  let ev = @evidence.EvidenceEngine::new()
  let items = [
    @evidence.EvidenceItem::new(@evidence.WrittenCommitment, "合同载明 48 小时响应 SLA"),
    @evidence.EvidenceItem::new(@evidence.ResourceAllocation, "已分配专属支持团队"),
    @evidence.EvidenceItem::new(@evidence.SingleOralPromise, "电话中口头承诺当天下班前修复"),
    @evidence.EvidenceItem::new(@evidence.UserGuess, "用户猜测是系统故障"),
  ]
  let ea = ev.assess(items, ["SLA 违约认定标准", "审批负责人"])
  println("  置信度: " + ea.confidence.to_string() + " | " + ea.summary)
  println("  缺失信息: " + join(ea.missing))
  println("  ↑ 任何需要证据分级的决策过程都可复用（风控举证、审核材料、绩效评估等）")

  // ---------------------------------------------------------------
  // [2] 可选决策组件：Guardrail 决策偏见护栏（通用口径）
  // ---------------------------------------------------------------
  println("\n[2] Guardrail 决策偏见护栏（可选组件，与引擎解耦）")
  let gr = @guardrail.GuardrailEngine::new()
  let gs = @guardrail.GuardrailSignals::make(true, true, true, false, false, true, false, false, false)
  let ga = gr.check(gs)
  println("  是否安全通过: " + ga.safe.to_string())
  for g in ga.triggered {
    println("    ⚠ " + g.label() + "：" + note_of(g))
  }
  println("  必查项:")
  for c in ga.required_check {
    println("    · " + c)
  }
  println("  ↑ 防的是决策偏见本身（转述放大/措辞矛盾/仅凭感觉），不绑定任何业务场景")

  // ---------------------------------------------------------------
  // [3] 可选决策组件：Case 案例库（通用口径）
  // ---------------------------------------------------------------
  println("\n[3] Case 案例库（可选组件，与引擎解耦）")
  let cl = @case.CaseLibrary::new()
  let cr = cl.search(["promotion", "multi-leader"])
  println("  命中 " + cr.total.to_string() + " 条内置示例案例（演示数据，机制可接任意领域）")
  for m in cr.matches {
    println("    · " + m.card.id + " [" + m.card.principle + "]")
  }
  let gl = @case.CaseLibrary::new()
  let _ = gl.add_card(@case.CaseCard::make(
    "c-demo-extra",
    ["general", "risk"],
    "general",
    "document",
    "high",
    "anonymized-case",
    "通用决策案例：先核实再行动",
    "先确认事实依据，再推进决策",
    "对方已给出书面承诺时仍需验证执行条件",
  ))
  let json_str = gl.save_json()
  match @case.CaseLibrary::load_json(json_str) {
    Ok(lib2) => println("  落盘 round-trip: JSON " + json_str.length().to_string() + " 字符 → 恢复 " +
      lib2.export_cards().length().to_string() + " 条")
    Err(e) => println("  落盘失败: " + e)
  }
  println("  ↑ 案例沉淀机制（命中计数/反馈闭环）与领域无关，可接任意规则引擎结果")
}

fn note_of(g : @guardrail.GuardrailType) -> String {
  match g {
    RetellingOverrepresentsPain => "转述可能放大痛苦时刻，回到证据清单"
    WordingBehaviorContradiction => "措辞漂亮但行为矛盾，以重复行为为准"
    CultureChangesMeaning => "注意组织文化对语义的影响"
    OverEmpathyWithNarrator => "单方叙述+情绪浓，保持中立"
    TranscriptMissesContext => "转写丢失语气与权力动态，降级结论"
    FeelingIsRiskSignal => "感觉≠证据，补充事实"
    DepletionDistorts => "疲惫时先休息再判断"
    HopeDistorts => "急需认可易过度信任承诺，先验证"
  }
}

fn join(arr : Array[String]) -> String {
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
