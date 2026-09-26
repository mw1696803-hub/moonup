/// Upward Management Core — 向上管理决策引擎（CLI Demo）
fn main {
  println("=== Upward Management Core Demo ===")

  // --- OGS-M 清洗示例 ---
  println("\n[1] OGS-M 情境清洗")
  let ogsm_engine = @ogsm.OgsmEngine::new()
  let sep = @ogsm.FactSeparation::new()
  sep.feelings.push("很委屈，又要背锅")
  sep.facts.push("老板在会上口头让我负责新项目")
  sep.facts.push("没有给我预算和人员")
  sep.missing_context.push("不知道成功怎么评估")
  let r = ogsm_engine.clean(
    @ogsm.Ogsm::new(
      "把口头承诺转化为可验证条件",
      "新责任出现但授权、资源、评估标准都不清",
      "老板承诺机会但未明确时间线、资源支持与晋升标准",
      "将承诺转化为书面条件清单",
    ),
    sep,
    true,
    true,
  )
  println("  四元组齐全: " + r.valid.to_string())
  println("  事实: " + join(sep.facts))
  println("  感受: " + join(sep.feelings))
  println("  漂移检测: " + r.drift_note)

  // --- Evidence 证据分级示例 ---
  println("\n[2] Evidence 证据分级与置信度")
  let ev = @evidence.EvidenceEngine::new()
  let items = [
    @evidence.EvidenceItem::new(@evidence.WrittenCommitment, "邮件确认了新项目范围"),
    @evidence.EvidenceItem::new(@evidence.ResourceAllocation, "给了预算但没给人力"),
    @evidence.EvidenceItem::new(@evidence.SingleOralPromise, "会上口头说'会考虑晋升'"),
    @evidence.EvidenceItem::new(@evidence.UserGuess, "我感觉他在故意拖延"),
  ]
  let ea = ev.assess(items, ["晋升评估标准", "预算审批人"])
  println("  置信度: " + ea.confidence.to_string())
  println("  " + ea.summary)
  println("  缺失信息: " + join(ea.missing))
  for item in ea.items {
    println("    [" + item.source.label() + " w=" + item.source.weight().to_string() + "] " + item.quote)
  }

  // --- Scenario 场景路由示例 ---
  println("\n[3] Scenario 场景路由")
  let sr = @scenario.ScenarioRouter::new()
  let rt = sr.route(["两个领导要求冲突", "上个月刚说晋升会考虑", "跨部门协作受阻"])
  println("  主场景: " + rt.primary.label())
  for s in rt.secondary {
    println("  次场景: " + s.label())
  }
  println("  命中: " + join(rt.matched))
  println("  提示: " + rt.hint)

  // --- Guardrail 防偏见护栏示例 ---
  println("\n[4] Guardrail 防偏见护栏")
  let gr = @guardrail.GuardrailEngine::new()
  // make(痛苦转述, 措辞漂亮, 行为矛盾, 文化, 疲惫, 高期待, 仅感觉, 仅转写, 有硬证据)
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

  // --- Hypothesis 假设空间示例 ---
  println("\n[5] Hypothesis 假设空间")
  let he = @hypothesis.HypothesisEngine::new()
  let hs = he.build(
    ["口头承诺只是漂亮话，不会兑现", "老板确实想给机会但缺乏机制", "他在用拖延试探我的底线"],
    ["晋升评估标准"],
  )
  println("  假设数: " + hs.hypotheses.length().to_string())
  for h in hs.hypotheses {
    println("    · " + h.statement + " → 验证: " + h.validation_move)
  }
  println("  最值得优先: " + hs.most_worth_prioritizing)
  println("  下一步: " + hs.next_move)

  // --- Case 案例检索示例 ---
  println("\n[6] Case 案例检索")
  let cl = @case.CaseLibrary::new()
  let cr = cl.search(["promotion", "multi-leader"])
  println("  命中 " + cr.total.to_string() + " 条案例")
  for m in cr.matches {
    println("    · " + m.card.id + " [" + m.card.principle + "]")
    if m.mismatch_note != "" {
      println("      " + m.mismatch_note)
    }
  }
  println("  " + cr.note)

  // --- Case 生长口子演示：追加案例 + 检索命中 ---
  let gl = @case.CaseLibrary::new()
  let _ = gl.add_card(@case.CaseCard::make(
    "c-user-demo",
    ["hr", "labor-risk"],
    "hr",
    "document",
    "high",
    "anonymized-case",
    "劳动风险场景：先咨询专业意见，不留书面把柄",
    "我先了解一下流程，必要时咨询专业意见再回复",
    "对方已正式启动法律程序时，个人话术不再适用",
  ))
  println("  生长口子: 内置 5 条 + 追加 1 条 = " + gl.export_cards().length().to_string() + " 条")
  let gr = gl.search(["hr"])
  println("  新增案例可检索命中: " + gr.matches[0].card.id + "（" + gr.matches[0].card.source + "）")

  // --- Case 落盘 + 反馈闭环演示 ---
  let json_str = gl.save_json()
  let restored = @case.CaseLibrary::load_json(json_str)
  match restored {
    Ok(lib2) => println("  落盘 round-trip: JSON " + json_str.length().to_string() + " 字符 → 恢复 " + lib2.export_cards().length().to_string() + " 条")
    Err(e) => println("  落盘失败: " + e)
  }
  let fb = gl.record_feedback("c-user-demo", "positive", "真实调用：按脚本先咨询专业意见，用户接受")
  let status = gl.export_cards().filter(fn(c) { c.id == "c-user-demo" })[0].status
  println("  反馈闭环: " + fb.reason + " → 状态 " + status)
  let bad = @case.CaseLibrary::load_json("{ 不是合法 JSON")
  match bad {
    Err(e) => println("  损坏 JSON 容错: " + e)
    Ok(_) => println("  损坏 JSON 容错: 不应发生")
  }
  println("  沉淀方向: 落盘(宿主写文件) → 命中计数 → 高频案例经 feedback 验证后沉淀为用户机制")

  // --- 机制候选演示（高频 + 已验证）---
  let _ = gl.record_hit("c-user-demo")
  let _ = gl.record_hit("c-user-demo")
  let cands = gl.mechanism_candidates(2)
  let mut cand_info = ""
  if cands.length() > 0 {
    cand_info = " → " + cands[0].id
  }
  println("  机制候选(命中≥2 且已验证): " + cands.length().to_string() + " 条" + cand_info)

  // --- Output 12 段报告示例（MVP 端到端最后一段）---
  println("\n[7] Output 12 段结构化报告")
  let oe = @output.OutputEngine::new()
  let oi = @output.ReportInputs::new()
  oi.set("objective", "把口头承诺转化为可验证条件")
  oi.set("gap", "承诺出现但时间线/资源/评估标准不清")
  oi.set("situation", "老板口头承诺机会，未明确支持与标准")
  oi.set("move", "书面确认评估标准与时间线")
  oi.set("happening", "新项目责任 + 口头晋升承诺")
  oi.set("stuck", "无法判断承诺是否真实")
  oi.set("missing", "晋升评估标准、预算审批人")
  oi.set("hypothesis_a", "漂亮话不会兑现")
  oi.set("hypothesis_b", "确实想给机会但缺机制")
  oi.set("priority", "缺机制")
  oi.set("user_side", "急需认可、怕错过机会")
  oi.set("boss_side", "有资源但未明确分配")
  oi.set("decision_rights", "晋升评估人未指明")
  oi.set("capacity", "可执行书面确认动作")
  oi.set("protect", "避免把口头承诺当结果")
  oi.set("known_facts", "邮件确认范围；给了预算")
  oi.set("unverified", "口头晋升承诺；感觉被拖延")
  oi.set("confidence", "高（有书面与资源证据）")
  oi.set("similar_case", "c-promotion 口头承诺转书面条件")
  oi.set("transfers", "先书面确认标准再行动")
  oi.set("may_not_apply", "组织若无晋升机制则需换路径")
  oi.set("best_next", "发一封确认邮件列评估标准")
  oi.set("why_move", "把模糊承诺变成可验证条件")
  oi.set("not_conclude", "暂不认定承诺一定兑现或一定不兑现")
  oi.set("third_option", "先确认标准，不急着表忠心或对抗")
  oi.set("suggested_move", "本周内完成书面确认并设定复查时间点")
  oi.set("script_safe", "麻烦把评估标准和时间线书面发我，我对照准备")
  oi.set("script_boundary", "如果对方拒绝书面确认，我会把口头内容复述邮件回执")
  oi.set("script_traceable", "邮件正文写明'按今天 1:1 共识，评估标准为…请确认'")
  oi.set("observe_next", "观察两周内是否有书面反馈或资源动作")
  println(oe.render(oi))
  println("  安全边界检查: " + @output.OutputEngine::safety_boundaries().length().to_string() + " 条已内置")

  // --- MVP 端到端：单情境走完全部 7 个模块 ---
  println("\n[8] MVP 端到端管线（单情境全链路）")
  // 情境：口头晋升承诺（画饼）+ 多头领导冲突 + 资源缺失
  // 1. OGS-M 清洗
  let m_ogsm = @ogsm.OgsmEngine::new()
  let m_sep = @ogsm.FactSeparation::new()
  m_sep.facts.push("会上口头承诺晋升，邮件确认了项目范围")
  m_sep.feelings.push("很委屈")
  m_sep.missing_context.push("评估标准")
  let m_clean = m_ogsm.clean(
    @ogsm.Ogsm::new("把晋升口头承诺转为可验证条件", "承诺无评估标准，且两领导优先级冲突", "老板画饼 + 多头领导 + 只给口头支持", "书面确认评估标准并拉齐领导优先级"),
    m_sep,
    true,
    true,
  )
  // 2. Evidence 分级
  let m_ev = @evidence.EvidenceEngine::new()
  let m_items = [
    @evidence.EvidenceItem::new(@evidence.WrittenCommitment, "邮件确认了项目范围"),
    @evidence.EvidenceItem::new(@evidence.SingleOralPromise, "会上口头说会考虑晋升"),
    @evidence.EvidenceItem::new(@evidence.UserGuess, "感觉被拖着"),
  ]
  let m_ea = m_ev.assess(m_items, ["晋升评估标准", "两领导优先级"])
  // 3. Scenario 路由
  let m_sr = @scenario.ScenarioRouter::new()
  let m_rt = m_sr.route(["口头承诺晋升", "两个领导要求冲突"])
  // 4. Guardrail 检查
  let m_gr = @guardrail.GuardrailEngine::new()
  let m_gs = @guardrail.GuardrailSignals::make(true, true, true, false, false, true, false, false, false)
  let m_ga = m_gr.check(m_gs)
  // 5. Hypothesis 空间
  let m_he = @hypothesis.HypothesisEngine::new()
  let m_hs = m_he.build(["漂亮话不会兑现", "想给机会但缺机制"], ["晋升评估标准"])
  // 6. Case 检索
  let m_cl = @case.CaseLibrary::new()
  let m_cr = m_cl.search(["promotion", "multi-leader"])
  // 7. Output 12 段报告
  let m_oe = @output.OutputEngine::new()
  let m_oi = @output.ReportInputs::new()
  m_oi.set("objective", m_clean.ogsm.objective)
  m_oi.set("gap", m_clean.ogsm.gap)
  m_oi.set("situation", m_clean.ogsm.situation)
  m_oi.set("move", m_clean.ogsm.next_action)
  m_oi.set("missing", "晋升评估标准、两领导优先级")
  m_oi.set("hypothesis_a", m_hs.hypotheses[0].statement)
  m_oi.set("hypothesis_b", m_hs.hypotheses[1].statement)
  m_oi.set("priority", m_hs.most_worth_prioritizing)
  m_oi.set("known_facts", "邮件确认范围（高权重）")
  m_oi.set("unverified", "口头晋升承诺；感觉被拖着")
  m_oi.set("confidence", m_ea.confidence.to_string() + "（有书面证据）")
  m_oi.set("similar_case", m_cr.matches[0].card.id + "：" + m_cr.matches[0].card.principle)
  m_oi.set("transfers", "先书面确认标准再行动")
  m_oi.set("may_not_apply", "组织若无晋升机制需换路径")
  m_oi.set("best_next", m_clean.ogsm.next_action)
  m_oi.set("why_move", "把模糊承诺变成可验证条件，拉齐多头领导优先级")
  m_oi.set("not_conclude", "暂不认定承诺一定兑现或一定不兑现")
  m_oi.set("third_option", "先确认标准，不急着表忠心或对抗")
  m_oi.set("suggested_move", "本周书面确认 + 拉三方会定优先级")
  m_oi.set("script_safe", "麻烦把评估标准和时间线书面发我，我对照准备")
  m_oi.set("script_traceable", "邮件写明'按今天共识，评估标准为…请确认'")
  m_oi.set("observe_next", "观察两周内是否有书面反馈或资源动作")
  println("  管线步骤: 清洗(四元组=" + m_clean.valid.to_string() + ") → 证据(置信度=" + m_ea.confidence.to_string() + ") → 路由(" + m_rt.primary.label() + ") → 护栏(" + m_ga.triggered.length().to_string() + "条触发) → 假设(" + m_hs.hypotheses.length().to_string() + "条) → 案例(" + m_cr.total.to_string() + "条) → 报告(12段)")
  println("  --- 12 段报告片段 ---")
  println(m_oe.render(m_oi))
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
      s = s + "; "
    }
    s = s + arr[i]
    i = i + 1
  }
  s
}
