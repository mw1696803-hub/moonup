///|
/// Hypothesis 假设空间模块。
///
/// 对应向上管理教练素材 references/07-evidence-confidence.md 的 Hypothesis Check
/// 与 SKILL.md 输出模板第 3 段：
/// - 情境开放时先列 2-4 个可能假设再选解释；
/// - 每个假设给出：什么会使它为真 / 支持证据 / 反对证据 / 缺失信息 / 过早假设风险 / 验证动作；
/// - 若下一步只需验证一条缺失事实，不扩大答案。
///
/// 输入：候选假设陈述 + 缺失信息清单（来自 evidence 模块）；
/// 输出：约束后的假设空间（2-4 条）+ 最值得优先的假设 + 下一步动作。

/// 单个假设
pub struct Hypothesis {
  statement : String
  would_make_true : String
  supporting : Array[String]
  against : Array[String]
  missing : Array[String]
  risk_if_assumed_early : String
  validation_move : String
}

/// 假设空间
pub struct HypothesisSpace {
  hypotheses : Array[Hypothesis]
  most_worth_prioritizing : String
  next_move : String
  truncated : Bool
}

/// 假设引擎
pub struct HypothesisEngine {
  version : String
}

/// 创建引擎
pub fn HypothesisEngine::new() -> HypothesisEngine {
  { version: "hypothesis-v1" }
}

/// 构建假设空间：数量约束（2-4）+ 字段填充 + 优先级 + 下一步
///
/// - candidates < 2 → 补默认假设（转述失真）
/// - candidates > 4 → 截取前 4，并提示
/// - 每条假设共享缺失信息，验证动作从缺失信息派生
pub fn HypothesisEngine::build(
  _self : HypothesisEngine,
  candidates : Array[String],
  missing : Array[String],
) -> HypothesisSpace {
  let chosen : Array[String] = []
  for c in candidates {
    if chosen.length() < 4 {
      chosen.push(c)
    }
  }
  let truncated = candidates.length() > 4
  if chosen.length() < 2 {
    chosen.push("转述可能失真：单方叙述放大了问题或遗漏了关键背景")
  }
  if chosen.length() < 2 {
    chosen.push("事件可能有更简单的解释：先补一条缺失事实再判断")
  }

  let hypotheses : Array[Hypothesis] = []
  for c in chosen {
    hypotheses.push(make_hypothesis(c, missing))
  }

  // 最值得优先：缺失信息最少的假设（验证成本最低），平局取先
  let mut best = 0
  let mut i = 1
  while i < hypotheses.length() {
    if hypotheses[i].missing.length() < hypotheses[best].missing.length() {
      best = i
    }
    i = i + 1
  }
  let most = hypotheses[best].statement

  let next_move = if missing.length() == 1 {
    "下一步只需验证一条缺失事实：「" + missing[0] + "」，不必扩大假设"
  } else if missing.length() > 1 {
    "缺失信息较多：先按验证动作排序，从最省力、风险最低的开始"
  } else {
    "先做一个低成本小测试（一次书面确认或一次观察），再收敛到单一解释"
  }

  { hypotheses, most_worth_prioritizing: most, next_move, truncated }
}

/// 从候选陈述生成完整假设（字段模板填充）
fn make_hypothesis(statement : String, missing : Array[String]) -> Hypothesis {
  let validation = if missing.length() > 0 {
    "先验证缺失信息：「" + missing[0] + "」（书面确认或观察重复行为）"
  } else {
    "做一个低成本小测试（先问一句 / 发一封确认邮件）观察反应"
  }
  {
    statement,
    would_make_true: "若出现书面记录或重复行为佐证，此假设成立",
    supporting: [],
    against: [],
    missing,
    risk_if_assumed_early: "过早按此假设行动：若实际相反，会采取错误动作并消耗信任",
    validation_move: validation,
  }
}

///|
test "1 个候选 → 自动补到 2 条" {
  let r = HypothesisEngine::new().build(["他只是随口一说"], ["评估标准"])
  assert_eq(r.hypotheses.length(), 2)
  assert_true(r.hypotheses[1].statement.contains("转述可能失真"))
}

///|
test "6 个候选 → 截取到 4 条并标记 truncated" {
  let r = HypothesisEngine::new().build(
    ["H1", "H2", "H3", "H4", "H5", "H6"],
    [],
  )
  assert_eq(r.hypotheses.length(), 4)
  assert_true(r.truncated)
}

///|
test "3 个候选 → 原样保留 3 条" {
  let r = HypothesisEngine::new().build(["A", "B", "C"], [])
  assert_eq(r.hypotheses.length(), 3)
  assert_false(r.truncated)
}

///|
test "单条缺失信息 → next_move 提示只需验证一条" {
  let r = HypothesisEngine::new().build(["他在拖延"], ["时间线"])
  assert_true(r.next_move.contains("只需验证"))
  assert_true(r.next_move.contains("时间线"))
}

///|
test "验证动作从缺失信息派生" {
  let r = HypothesisEngine::new().build(["他在拖延"], ["评估标准"])
  assert_true(r.hypotheses[0].validation_move.contains("评估标准"))
}

///|
test "假设陈述保留原文" {
  let r = HypothesisEngine::new().build(["他想让我背锅"], [])
  assert_eq(r.hypotheses[0].statement, "他想让我背锅")
}

///|
test "缺失信息透传到每条假设" {
  let r = HypothesisEngine::new().build(["A", "B"], ["预算审批人"])
  assert_eq(r.hypotheses[0].missing.length(), 1)
  assert_eq(r.hypotheses[1].missing[0], "预算审批人")
}

///|
test "过早假设风险字段非空" {
  let r = HypothesisEngine::new().build(["A"], [])
  assert_true(r.hypotheses[0].risk_if_assumed_early.length() > 10)
  assert_true(r.hypotheses[0].would_make_true.length() > 5)
}

///|
test "最值得优先的假设非空且存在" {
  let r = HypothesisEngine::new().build(["假设X"], ["时间线"])
  assert_eq(r.most_worth_prioritizing, "假设X")
}

///|
test "空候选 + 空缺失 → 补默认假设并给出下一步" {
  let r = HypothesisEngine::new().build([], [])
  assert_eq(r.hypotheses.length(), 2)
  assert_true(r.next_move.contains("小测试"))
}
