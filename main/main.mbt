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
