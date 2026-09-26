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
  oi.set("boss_side", "（由输入记录推断，待补充）")
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
