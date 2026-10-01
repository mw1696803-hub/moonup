///|
/// WASM API：将 7 模块决策管线导出为浏览器可调用的单一入口。
///
/// 输入：文本协议（\n 分隔 10 行，多值用 ";;" 分隔）
///   1   objective（O 目标）
///   2   gap（G 差距）
///   3   situation（S 情境）
///   4   move（M 下一步）
///   5   facts（事实，;; 分隔）
///   6   feelings（感受，;; 分隔）
///   7   missing_context（缺失上下文，;; 分隔）
///   8   evidence（证据，格式 kind|描述，;; 分隔；kind ∈ written|resource|oral|guess）
///   9   features（场景路由特征，;; 分隔）
///   10  missing_evidence（缺失信息，;; 分隔）
///
/// 输出：文本报告（12 段结构化报告 + 管线摘要 + 安全边界）
#export_name("moonup_run")
pub fn run(input : String) -> String {
  let lines = split_lines(input)
  let get = fn(i : Int) -> String {
    if i < lines.length() { lines[i] } else { "" }
  }

  // --- 1. OGS-M 清洗 ---
  let ogsm_engine = @ogsm.OgsmEngine::new()
  let sep = @ogsm.FactSeparation::new()
  for f in split_multi(get(4)) {
    sep.facts.push(f)
  }
  for f in split_multi(get(5)) {
    sep.feelings.push(f)
  }
  for f in split_multi(get(6)) {
    sep.missing_context.push(f)
  }
  let clean = ogsm_engine.clean(
    @ogsm.Ogsm::new(get(0), get(1), get(2), get(3)),
    sep,
    true,
    true,
  )

  // --- 2. Evidence 分级与置信度 ---
  let ev_engine = @evidence.EvidenceEngine::new()
  let items : Array[@evidence.EvidenceItem] = []
  for raw in split_multi(get(7)) {
    let mut kind = ""
    let mut quote = ""
    let mut is_kind = true
    for p in raw.split("|") {
      if is_kind {
        kind = p.trim().to_owned()
      } else {
        quote = p.trim().to_owned()
      }
      is_kind = false
    }
    let src = match kind {
      "written" => @evidence.WrittenCommitment
      "resource" => @evidence.ResourceAllocation
      "oral" => @evidence.SingleOralPromise
      "guess" => @evidence.UserGuess
      _ => @evidence.UserGuess
    }
    items.push(@evidence.EvidenceItem::new(src, quote))
  }
  let assessed = ev_engine.assess(items, split_multi(get(9)))

  // --- 3. Scenario 场景路由 ---
  let router = @scenario.ScenarioRouter::new()
  let route = router.route(split_multi(get(8)))

  // --- 4. Guardrail 防偏见检查 ---
  let guard_engine = @guardrail.GuardrailEngine::new()
  // 信号位：痛苦转述 / 措辞漂亮 / 行为矛盾 / 文化 / 疲惫 / 高期待 / 仅感觉 / 仅转写 / 有硬证据
  let signals = @guardrail.GuardrailSignals::make(
    sep.feelings.length() > 0,
    true,
    true,
    false,
    false,
    true,
    false,
    false,
    assessed.items.length() > 0,
  )
  let guard_out = guard_engine.check(signals)

  // --- 5. Hypothesis 假设空间 ---
  let hyp_engine = @hypothesis.HypothesisEngine::new()
  let hyp = hyp_engine.build(
    ["口头承诺只是漂亮话，不会兑现", "老板确实想给机会但缺乏机制", "他在用拖延试探我的底线"],
    assessed.missing,
  )

  // --- 6. Case 案例检索 ---
  let cl = @case.CaseLibrary::new()
  let case_route = cl.search(["promotion", "multi-leader"])

  // --- 7. Output 12 段报告 ---
  let out = @output.OutputEngine::new()
  let oi = @output.ReportInputs::new()
  oi.set("objective", clean.ogsm.objective)
  oi.set("gap", clean.ogsm.gap)
  oi.set("situation", clean.ogsm.situation)
  oi.set("move", clean.ogsm.next_action)
  oi.set("happening", "输入互动记录待细化")
  oi.set("stuck", clean.ogsm.gap)
  oi.set("missing", join_sep(assessed.missing))
  oi.set("hypothesis_a", hyp.hypotheses[0].statement)
  oi.set("hypothesis_b", hyp.hypotheses[1].statement)
  oi.set("priority", hyp.most_worth_prioritizing)
  oi.set("user_side", "（由输入记录推断，待补充）")
  oi.set("counterparty_side", "（由输入记录推断，待补充）")
  oi.set("decision_rights", "（待补充）")
  oi.set("capacity", "可执行书面确认动作")
  oi.set("protect", "避免把口头承诺当结果")
  oi.set("known_facts", join_sep(facts_of(assessed)))
  oi.set("unverified", join_sep(assessed.missing))
  oi.set("confidence", assessed.confidence.to_string())
  oi.set("similar_case", if case_route.matches.length() > 0 {
    case_route.matches[0].card.id + "：" + case_route.matches[0].card.principle
  } else {
    "（无命中案例）"
  })
  oi.set("transfers", "先书面确认标准再行动")
  oi.set("may_not_apply", "组织若无对应机制需换路径")
  oi.set("best_next", clean.ogsm.next_action)
  oi.set("why_move", "把模糊承诺变成可验证条件")
  oi.set("not_conclude", "证据不足时不下结论")
  oi.set("third_option", "先确认标准，不急着表忠心或对抗")
  oi.set("suggested_move", "本周书面确认并设定复查时间点")
  oi.set("script_safe", "麻烦把评估标准和时间线书面发我，我对照准备")
  oi.set("script_boundary", "如果对方拒绝书面确认，我会把口头内容复述邮件回执")
  oi.set("script_traceable", "邮件正文写明按今天共识，评估标准为…请确认")
  oi.set("observe_next", "观察两周内是否有书面反馈或资源动作")

  let report = out.render(oi)

  // --- 管线摘要 ---
  let summary = "管线: 清洗(四元组=" + clean.valid.to_string() + ") → 证据(置信度=" +
    assessed.confidence.to_string() + ") → 路由(" + route.primary.label() + ") → 护栏(" +
    guard_out.triggered.length().to_string() + "条触发) → 假设(" +
    hyp.hypotheses.length().to_string() + "条) → 案例(" + case_route.total.to_string() +
    "条) → 报告(12段)\n缺失信息: " + join_sep(assessed.missing) +
    "\n安全边界: " + @output.OutputEngine::safety_boundaries().length().to_string() + " 条已内置"

  summary + "\n\n" + report
}

/// 按 \n 切分行
fn split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  for p in s.split("\n") {
    out.push(p.to_owned())
  }
  out
}

/// 按 ";;" 切分多值
fn split_multi(s : String) -> Array[String] {
  let out : Array[String] = []
  for p in s.split(";;") {
    let t = p.trim().to_owned()
    if t != "" {
      out.push(t)
    }
  }
  out
}

/// 从证据分级结果提取高权重事实
fn facts_of(ea : @evidence.EvidenceAssessment) -> Array[String] {
  let out : Array[String] = []
  for item in ea.items {
    if item.source.weight() >= 3 {
      out.push(item.quote)
    }
  }
  out
}

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

  out = out + "↑ 客服分流与风控审核共用 @engine 核心；向上管理仅是另一个内置规则包。"
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
