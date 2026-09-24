///|
/// Guardrail 防偏见护栏模块。
///
/// 对应向上管理教练素材 references/06-bias-guardrails.md：
/// 在分析转述、录音、情绪化叙述或漂亮的老板话术时，
/// 检查 8 类认知/叙述偏差，触发护栏后强制给出 5 项必查（Required Check）。
///
/// 输入：结构化信号（转述含痛苦词/措辞漂亮/行为矛盾/用户疲惫等）；
/// 输出：触发的护栏清单 + 说明 + 必查项 + 是否安全通过。

/// 护栏类型（8 类）
pub(all) enum GuardrailType {
  RetellingOverrepresentsPain // 转述放大痛苦时刻
  WordingBehaviorContradiction // 措辞漂亮但行为矛盾
  CultureChangesMeaning        // 组织文化改变语义
  OverEmpathyWithNarrator      // 过度共情叙述者
  TranscriptMissesContext      // 转写丢失语气/压力/权力动态
  FeelingIsRiskSignal          // "感觉不对"是风险信号而非证据
  DepletionDistorts            // 疲惫扭曲判断
  HopeDistorts                 // 希望扭曲判断
}

fn guardrail_eq(a : GuardrailType, b : GuardrailType) -> Bool {
  match (a, b) {
    (RetellingOverrepresentsPain, RetellingOverrepresentsPain) => true
    (WordingBehaviorContradiction, WordingBehaviorContradiction) => true
    (CultureChangesMeaning, CultureChangesMeaning) => true
    (OverEmpathyWithNarrator, OverEmpathyWithNarrator) => true
    (TranscriptMissesContext, TranscriptMissesContext) => true
    (FeelingIsRiskSignal, FeelingIsRiskSignal) => true
    (DepletionDistorts, DepletionDistorts) => true
    (HopeDistorts, HopeDistorts) => true
    _ => false
  }
}

/// 护栏中文名
pub fn GuardrailType::label(self : GuardrailType) -> String {
  match self {
    RetellingOverrepresentsPain => "转述放大痛苦"
    WordingBehaviorContradiction => "措辞与行为矛盾"
    CultureChangesMeaning => "文化改变语义"
    OverEmpathyWithNarrator => "过度共情叙述者"
    TranscriptMissesContext => "转写缺上下文"
    FeelingIsRiskSignal => "感觉≠证据"
    DepletionDistorts => "疲惫扭曲判断"
    HopeDistorts => "希望扭曲判断"
  }
}

/// 护栏说明（触发时给用户看）
fn GuardrailType::note(self : GuardrailType) -> String {
  match self {
    RetellingOverrepresentsPain => "转述可能放大了痛苦时刻：回到证据清单，别被情绪峰值带偏"
    WordingBehaviorContradiction => "措辞漂亮但行为矛盾：以重复行为为准（书面/资源/结果优先）"
    CultureChangesMeaning => "同一句话在不同组织文化下含义可能不同：补充组织背景再解读"
    OverEmpathyWithNarrator => "叙述来自单方且情绪浓：输出保持中立，不站队"
    TranscriptMissesContext => "转写丢失语气、停顿、表情和权力动态：结论降级，先补上下文"
    FeelingIsRiskSignal => "'感觉不对'是风险信号，不是证据：补充可验证的事实后再判断"
    DepletionDistorts => "疲惫时易过度解读威胁、低估自身需求：先休息，状态恢复后再判断"
    HopeDistorts => "急需认可时易过度信任漂亮承诺：先做验证动作（书面确认/观察重复行为）"
  }
}

/// 输入信号（由上游清洗或调用方填入）
pub struct GuardrailSignals {
  mut retelling_has_pain : Bool  // 转述含痛苦/委屈等情绪词
  mut boss_wording_polished : Bool // 老板措辞漂亮
  mut behavior_contradicts : Bool  // 行为与措辞矛盾
  mut culture_note_present : Bool  // 存在组织文化背景
  mut user_tired : Bool            // 用户疲惫
  mut user_high_hope : Bool        // 用户急需认可/高度期待
  mut feeling_only : Bool          // 只有"感觉不对"类判断
  mut transcript_only : Bool       // 证据仅来自单次转写/录音
  mut has_hard_evidence : Bool     // 存在高权重证据（书面/结果/重复行为）
}

/// 创建信号（默认全 false）
pub fn GuardrailSignals::new() -> GuardrailSignals {
  {
    retelling_has_pain: false,
    boss_wording_polished: false,
    behavior_contradicts: false,
    culture_note_present: false,
    user_tired: false,
    user_high_hope: false,
    feeling_only: false,
    transcript_only: false,
    has_hard_evidence: false,
  }
}

/// 全参数创建信号（跨包使用时推荐）
///
/// 参数顺序：痛苦转述 / 措辞漂亮 / 行为矛盾 / 文化背景 / 疲惫 / 高期待 / 仅感觉 / 仅转写 / 有硬证据
pub fn GuardrailSignals::make(
  retelling_has_pain : Bool,
  boss_wording_polished : Bool,
  behavior_contradicts : Bool,
  culture_note_present : Bool,
  user_tired : Bool,
  user_high_hope : Bool,
  feeling_only : Bool,
  transcript_only : Bool,
  has_hard_evidence : Bool,
) -> GuardrailSignals {
  {
    retelling_has_pain,
    boss_wording_polished,
    behavior_contradicts,
    culture_note_present,
    user_tired,
    user_high_hope,
    feeling_only,
    transcript_only,
    has_hard_evidence,
  }
}

/// 护栏检测结果
pub struct GuardrailResult {
  triggered : Array[GuardrailType]
  notes : Array[String]
  required_check : Array[String]
  safe : Bool
}

/// 防偏见引擎
pub struct GuardrailEngine {
  version : String
}

/// 创建引擎
pub fn GuardrailEngine::new() -> GuardrailEngine {
  { version: "guardrail-v1" }
}

fn arr_push_once(arr : Array[GuardrailType], t : GuardrailType) -> Unit {
  arr.push(t)
}

/// 执行护栏检查：按规则触发 + 生成说明 + 必查项
pub fn GuardrailEngine::check(_self : GuardrailEngine, s : GuardrailSignals) -> GuardrailResult {
  let triggered : Array[GuardrailType] = []

  if s.retelling_has_pain {
    arr_push_once(triggered, RetellingOverrepresentsPain)
  }
  if s.boss_wording_polished && s.behavior_contradicts {
    arr_push_once(triggered, WordingBehaviorContradiction)
  }
  if s.culture_note_present {
    arr_push_once(triggered, CultureChangesMeaning)
  }
  if s.user_tired {
    arr_push_once(triggered, DepletionDistorts)
  }
  if s.user_high_hope && s.boss_wording_polished {
    arr_push_once(triggered, HopeDistorts)
  }
  if s.feeling_only && !s.has_hard_evidence {
    arr_push_once(triggered, FeelingIsRiskSignal)
  }
  if s.transcript_only {
    arr_push_once(triggered, TranscriptMissesContext)
  }
  if s.retelling_has_pain || s.feeling_only {
    arr_push_once(triggered, OverEmpathyWithNarrator)
  }

  let notes : Array[String] = []
  for t in triggered {
    notes.push(t.note())
  }

  let required_check = if triggered.length() > 0 {
    [
      "什么证据支持这个解读？",
      "什么证据反对它？",
      "什么会改变结论？",
      "有没有更安全的小测试？",
      "用户当前状态能否执行这条建议？",
    ]
  } else {
    []
  }

  { triggered, notes, required_check, safe: triggered.length() == 0 }
}

///|
test "无信号 → 全部通过 safe=true" {
  let r = GuardrailEngine::new().check(GuardrailSignals::new())
  assert_true(r.safe)
  assert_eq(r.triggered.length(), 0)
  assert_eq(r.required_check.length(), 0)
}

///|
test "措辞漂亮 + 行为矛盾 → 触发矛盾护栏" {
  let s = GuardrailSignals::new()
  s.boss_wording_polished = true
  s.behavior_contradicts = true
  let r = GuardrailEngine::new().check(s)
  assert_false(r.safe)
  assert_true(contains_type(r.triggered, WordingBehaviorContradiction))
  assert_true(contains_note(r.notes, "重复行为"))
}

///|
test "疲惫 → 触发疲惫护栏" {
  let s = GuardrailSignals::new()
  s.user_tired = true
  let r = GuardrailEngine::new().check(s)
  assert_true(contains_type(r.triggered, DepletionDistorts))
}

///|
test "急需认可 + 措辞漂亮 → 触发希望扭曲" {
  let s = GuardrailSignals::new()
  s.user_high_hope = true
  s.boss_wording_polished = true
  let r = GuardrailEngine::new().check(s)
  assert_true(contains_type(r.triggered, HopeDistorts))
  assert_true(contains_note(r.notes, "验证动作"))
}

///|
test "'感觉不对' 且无硬证据 → 触发感觉≠证据" {
  let s = GuardrailSignals::new()
  s.feeling_only = true
  let r = GuardrailEngine::new().check(s)
  assert_true(contains_type(r.triggered, FeelingIsRiskSignal))
}

///|
test "'感觉不对' 但有硬证据 → 不触发该护栏" {
  let s = GuardrailSignals::new()
  s.feeling_only = true
  s.has_hard_evidence = true
  let r = GuardrailEngine::new().check(s)
  assert_false(contains_type(r.triggered, FeelingIsRiskSignal))
}

///|
test "痛苦转述 → 放大痛苦 + 过度共情两条" {
  let s = GuardrailSignals::new()
  s.retelling_has_pain = true
  let r = GuardrailEngine::new().check(s)
  assert_true(contains_type(r.triggered, RetellingOverrepresentsPain))
  assert_true(contains_type(r.triggered, OverEmpathyWithNarrator))
}

///|
test "仅转写 → 触发上下文缺失护栏" {
  let s = GuardrailSignals::new()
  s.transcript_only = true
  let r = GuardrailEngine::new().check(s)
  assert_true(contains_type(r.triggered, TranscriptMissesContext))
}

///|
test "有组织文化背景 → 触发文化护栏" {
  let s = GuardrailSignals::new()
  s.culture_note_present = true
  let r = GuardrailEngine::new().check(s)
  assert_true(contains_type(r.triggered, CultureChangesMeaning))
}

///|
test "触发时必查项给全 5 问" {
  let s = GuardrailSignals::new()
  s.user_tired = true
  let r = GuardrailEngine::new().check(s)
  assert_eq(r.required_check.length(), 5)
  assert_true(r.required_check[0].contains("支持"))
  assert_true(r.required_check[4].contains("执行"))
}

fn contains_type(arr : Array[GuardrailType], t : GuardrailType) -> Bool {
  let mut found = false
  for x in arr {
    if guardrail_eq(x, t) {
      found = true
    }
  }
  found
}

fn contains_note(arr : Array[String], kw : String) -> Bool {
  let mut found = false
  for x in arr {
    if x.contains(kw) {
      found = true
    }
  }
  found
}

