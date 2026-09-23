///|
/// OGS-M 情境清洗模块。
///
/// 对应向上管理教练素材 references/02-ogsm-cleaning.md：
/// 把「抱怨/困惑」等情绪化输入，清洗成可分析的 Objective / Gap / Situation / Move 四元组，
/// 并做事实与推断分离、检测 fight/flight 沟通目标漂移。
///
/// 引擎定位：输入结构化情境（调用方从自然语言清洗后传入），
/// 输出结构化判断（四元组校验、事实分离清单、漂移检测结果），
/// 供 evidence / scenario / hypothesis 等下游模块使用。

/// OGS-M 四元组：目标 / 差距 / 情境 / 下一步
pub struct Ogsm {
  objective : String
  gap : String
  situation : String
  next_action : String
}

/// 创建 OGS-M（未清洗，等待校验与事实分离）
pub fn Ogsm::new(objective : String, gap : String, situation : String, next_action : String) -> Ogsm {
  { objective, gap, situation, next_action }
}

/// 事实分离结果：事实 / 感受 / 假设 / 缺失背景 / 决策约束
pub struct FactSeparation {
  facts : Array[String]
  feelings : Array[String]
  assumptions : Array[String]
  missing_context : Array[String]
  decision_constraints : Array[String]
}

/// 创建空的事实分离容器
pub fn FactSeparation::new() -> FactSeparation {
  { facts: [], feelings: [], assumptions: [], missing_context: [], decision_constraints: [] }
}

/// 沟通目标漂移类型：无漂移 / 战斗漂移 / 逃跑漂移
pub(all) enum Drift {
  Clear
  Fight
  Flight
}

/// 漂移比较（MoonBit enum 无内置 Eq，手动比较）
fn drift_eq(a : Drift, b : Drift) -> Bool {
  match (a, b) {
    (Clear, Clear) => true
    (Fight, Fight) => true
    (Flight, Flight) => true
    _ => false
  }
}

/// 清洗校验结果
pub struct OgsmResult {
  ogsm : Ogsm
  separation : FactSeparation
  drift : Drift
  drift_note : String
  empty_fields : Array[String]
  valid : Bool
}

/// OGS-M 清洗引擎
pub struct OgsmEngine {
  version : String
}

/// 创建清洗引擎
pub fn OgsmEngine::new() -> OgsmEngine {
  { version: "ogsm-v1" }
}

/// 执行清洗：校验四元组非空 + 事实分离 + 漂移检测
///
/// 校验规则（来自素材）：
/// - Objective 缺失 → 无法判断真实沟通目标，必须补齐
/// - Gap 缺失 → 无法定位差距，先问"预期与现实差在哪"
/// - Situation 缺失 → 缺少证据基础，先收集发生了什么
/// - Move 缺失 → 先给验证性动作而非结论
pub fn OgsmEngine::clean(
  _self : OgsmEngine,
  ogsm : Ogsm,
  separation : FactSeparation,
  boss_wording_polished : Bool,
  boss_action_contradicts : Bool,
) -> OgsmResult {
  let empty : Array[String] = []
  if ogsm.objective == "" {
    empty.push("Objective")
  }
  if ogsm.gap == "" {
    empty.push("Gap")
  }
  if ogsm.situation == "" {
    empty.push("Situation")
  }
  if ogsm.next_action == "" {
    empty.push("Move")
  }
  let (drift, note) = detect_drift(ogsm, separation, boss_wording_polished, boss_action_contradicts)
  {
    ogsm,
    separation,
    drift,
    drift_note: note,
    empty_fields: empty,
    valid: empty.length() == 0,
  }
}

/// 漂移检测：
/// - 战斗漂移：目标是「证明老板错了 / 赢下争论 / 让对方认错」→ 建议回到真实沟通目标
/// - 逃跑漂移：目标是「保持沉默 / 接受模糊责任 / 保全颜面但丢失目标」→ 建议回到目标
/// - 漂亮话与行为矛盾（boss_wording_polished && boss_action_contradicts）→ 高权重提示
fn detect_drift(
  ogsm : Ogsm,
  _separation : FactSeparation,
  boss_wording_polished : Bool,
  boss_action_contradicts : Bool,
) -> (Drift, String) {
  let fight_words = ["证明", "赢", "认错", "惩罚", "反驳", "吵架", "争", "让他承认"]
  let flight_words = ["沉默", "算了", "忍着", "别说了", "就这样", "不问了"]
  let mut fight_hit = false
  for w in fight_words {
    if ogsm.objective.contains(w) {
      fight_hit = true
    }
  }
  let mut flight_hit = false
  for w in flight_words {
    if ogsm.objective.contains(w) {
      flight_hit = true
    }
  }
  if fight_hit {
    (Fight, "目标含战斗词（证明/赢/认错）——fight 漂移：先回到真实沟通目标，脚本若不服务目标则重写")
  } else if flight_hit {
    (Flight, "目标含逃跑词（沉默/算了/忍着）——flight 漂移：沉默可能丢失原目标，先确认要保护什么")
  } else if boss_wording_polished && boss_action_contradicts {
    (Clear, "警告：老板措辞漂亮但行为矛盾——措辞是弱证据，以重复行为为准（见 evidence 模块）")
  } else {
    (Clear, "无漂移")
  }
}

///|
test "四元组齐全 → valid，无漂移" {
  let e = OgsmEngine::new()
  let r = e.clean(
    Ogsm::new("把口头承诺转化为可验证条件", "承诺出现了但时间线/资源/标准不清", "老板承诺机会但未明确支持与评估标准", "将承诺转化为书面条件清单"),
    FactSeparation::new(),
    false,
    false,
  )
  assert_true(r.valid)
  assert_eq(r.empty_fields.length(), 0)
  assert_true(drift_eq(r.drift, Drift::Clear))
}

///|
test "Objective 缺失 → 标记空字段，valid=false" {
  let e = OgsmEngine::new()
  let r = e.clean(
    Ogsm::new("", "差距", "情境", "动作"),
    FactSeparation::new(),
    false,
    false,
  )
  assert_false(r.valid)
  assert_eq(r.empty_fields.length(), 1)
  assert_eq(r.empty_fields[0], "Objective")
}

///|
test "战斗漂移检测：目标含'证明老板错了'" {
  let e = OgsmEngine::new()
  let r = e.clean(
    Ogsm::new("证明老板错了", "他说的方案不现实", "他拍板了一个不现实的方案", "反驳他"),
    FactSeparation::new(),
    false,
    false,
  )
  assert_true(drift_eq(r.drift, Drift::Fight))
  assert_true(r.drift_note.contains("fight 漂移"))
}

///|
test "逃跑漂移检测：目标含'算了别问了'" {
  let e = OgsmEngine::new()
  let r = e.clean(
    Ogsm::new("算了，别问了", "责任模糊", "他让我背一个没权没资源的任务", "沉默接受"),
    FactSeparation::new(),
    false,
    false,
  )
  assert_true(drift_eq(r.drift, Drift::Flight))
  assert_true(r.drift_note.contains("flight 漂移"))
}

///|
test "漂亮话与行为矛盾 → 提示弱证据" {
  let e = OgsmEngine::new()
  let r = e.clean(
    Ogsm::new("确认晋升条件", "说好晋升但没有评估标准", "老板口头说会考虑晋升", "确认评估标准"),
    FactSeparation::new(),
    true,
    true,
  )
  assert_true(drift_eq(r.drift, Drift::Clear))
  assert_true(r.drift_note.contains("措辞是弱证据"))
}

///|
test "事实分离：情绪词识别" {
  let sep = FactSeparation::new()
  sep.feelings.push("很委屈")
  sep.facts.push("他发了邮件确认任务")
  sep.assumptions.push("他觉得我在推卸")
  sep.missing_context.push("不清楚评估标准")
  assert_eq(sep.feelings.length(), 1)
  assert_eq(sep.facts.length(), 1)
}
