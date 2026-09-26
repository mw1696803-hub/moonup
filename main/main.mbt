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
