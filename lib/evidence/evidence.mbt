///|
/// Evidence 证据分级与置信度模块。
///
/// 对应向上管理教练素材 references/07-evidence-confidence.md：
/// 给每条陈述标注来源类型、权重（High/Medium/Low）与分离类型
/// （已知事实/合理推断/未验证假设），再合成整体置信度。
///
/// 核心约定：权重完全由来源类型决定（确定性映射），不做主观打分；
/// 低置信度（只有 Low 来源）强制附带验证动作，防止把"漂亮话"当真。

/// 证据来源类型（对应素材的 High/Medium/Low 三档）
pub(all) enum EvidenceSource {
  WrittenCommitment  // 书面承诺（邮件/任务系统/文档）
  ResourceAllocation // 资源分配（预算/人力/时间）
  OutcomeChange      // 晋升/绩效/薪酬/角色结果
  RepeatedBehavior   // 重复兑现或不兑现行为
  AuthorityMatch     // 权责匹配
  MeetingMinutes     // 会议记录
  RepeatedWording    // 重复措辞模式
  CoworkerFeedback   // 独立同事反馈
  MeetingSummary     // 会议纪要
  TimingPattern      // 一致时间模式
  SingleOralPromise  // 单次口头承诺
  PolishedLanguage   // 漂亮话
  SingleTranscript   // 单次录音转写
  UserGuess          // 用户猜测
  ToneInference      // 语气推断
}

/// 来源 → 权重（3=High，2=Medium，1=Low）
pub fn EvidenceSource::weight(self : EvidenceSource) -> Int {
  match self {
    WrittenCommitment | ResourceAllocation | OutcomeChange | RepeatedBehavior |
    AuthorityMatch | MeetingMinutes => 3
    RepeatedWording | CoworkerFeedback | MeetingSummary | TimingPattern => 2
    _ => 1
  }
}

/// 来源 → 中文标签
pub fn EvidenceSource::label(self : EvidenceSource) -> String {
  match self {
    WrittenCommitment => "书面承诺"
    ResourceAllocation => "资源分配"
    OutcomeChange => "结果变化"
    RepeatedBehavior => "重复行为"
    AuthorityMatch => "权责匹配"
    MeetingMinutes => "会议记录"
    RepeatedWording => "重复措辞"
    CoworkerFeedback => "同事反馈"
    MeetingSummary => "会议纪要"
    TimingPattern => "时间模式"
    SingleOralPromise => "单次口头承诺"
    PolishedLanguage => "漂亮话"
    SingleTranscript => "单次录音转写"
    UserGuess => "用户猜测"
    ToneInference => "语气推断"
  }
}

/// 分离标注：已知事实 / 合理推断 / 未验证假设
pub(all) enum SeparationLabel {
  KnownFact
  ReasonableInference
  UnverifiedHypothesis
}

fn separation_eq(a : SeparationLabel, b : SeparationLabel) -> Bool {
  match (a, b) {
    (KnownFact, KnownFact) => true
    (ReasonableInference, ReasonableInference) => true
    (UnverifiedHypothesis, UnverifiedHypothesis) => true
    _ => false
  }
}

/// 来源 → 分离标注（自动判定）
///
/// - 书面/结果/重复行为 → 已知事实
/// - 模式/语境推断 → 合理推断
/// - 单次/猜测/语气 → 未验证假设
pub fn EvidenceSource::separation(self : EvidenceSource) -> SeparationLabel {
  match self {
    WrittenCommitment | ResourceAllocation | OutcomeChange | RepeatedBehavior |
    AuthorityMatch | MeetingMinutes => KnownFact
    RepeatedWording | CoworkerFeedback | MeetingSummary | TimingPattern => ReasonableInference
    _ => UnverifiedHypothesis
  }
}

/// 单条证据：来源 + 原文 + 分离标注
pub struct EvidenceItem {
  source : EvidenceSource
  quote : String
  separation : SeparationLabel
}

/// 创建证据条目（分离标注由来源自动判定）
pub fn EvidenceItem::new(source : EvidenceSource, quote : String) -> EvidenceItem {
  { source, quote, separation: source.separation() }
}

/// 整体置信度
pub(all) enum Confidence {
  High
  Medium
  Low
}

fn confidence_eq(a : Confidence, b : Confidence) -> Bool {
  match (a, b) {
    (High, High) => true
    (Medium, Medium) => true
    (Low, Low) => true
    _ => false
  }
}

fn Confidence::label(self : Confidence) -> String {
  match self {
    High => "高"
    Medium => "中"
    Low => "低"
  }
}

/// 置信度 → 英文串（Demo 用）
pub fn Confidence::to_string(self : Confidence) -> String {
  match self {
    High => "High"
    Medium => "Medium"
    Low => "Low"
  }
}

/// 证据评估结果
pub struct EvidenceAssessment {
  items : Array[EvidenceItem]
  confidence : Confidence
  missing : Array[String]
  validation : String
  summary : String
}

/// 证据评估引擎
pub struct EvidenceEngine {
  version : String
}

/// 创建评估引擎
pub fn EvidenceEngine::new() -> EvidenceEngine {
  { version: "evidence-v1" }
}

/// 执行评估：逐条标注已在创建时完成，这里做置信度合成 + 验证动作
///
/// 置信度合成规则（素材）：
/// - 存在 ≥1 条高权重证据（书面/资源/结果/重复行为）→ 高置信度
/// - 只有中权重证据（重复措辞/同事反馈/纪要）→ 中置信度
/// - 只有低权重证据（单次口头/漂亮话/猜测）→ 低置信度 + 强制验证动作
pub fn EvidenceEngine::assess(
  _self : EvidenceEngine,
  items : Array[EvidenceItem],
  missing : Array[String],
) -> EvidenceAssessment {
  let (confidence, validation) = synthesize(items)
  let summary = "证据 " + items.length().to_string() + " 条，整体置信度" + confidence.label() + "；" + validation
  { items, confidence, missing, validation, summary }
}

/// 置信度合成 + 验证动作生成
fn synthesize(items : Array[EvidenceItem]) -> (Confidence, String) {
  let mut has_high = false
  let mut has_medium = false
  let mut has_low = false
  for item in items {
    let w = item.source.weight()
    if w == 3 {
      has_high = true
    } else if w == 2 {
      has_medium = true
    } else {
      has_low = true
    }
  }
  if has_high {
    (High, "存在高权重证据（书面/资源/结果/重复行为），结论可靠")
  } else if has_medium {
    (Medium, "证据以中权重来源为主（措辞模式/同事反馈），建议补充书面或结果性证据后再定结论")
  } else if has_low {
    (Low, "证据全部来自低权重来源（单次口头/漂亮话/猜测）：先做验证动作——要求书面确认或观察重复行为，再下结论")
  } else {
    (Low, "证据不足：先收集互动记录（邮件/会议纪要/行为变化），再评估")
  }
}

///|
test "权重映射：书面承诺=3，会议纪要=2，单次口头=1" {
  assert_eq(EvidenceSource::WrittenCommitment.weight(), 3)
  assert_eq(EvidenceSource::MeetingSummary.weight(), 2)
  assert_eq(EvidenceSource::SingleOralPromise.weight(), 1)
  assert_eq(EvidenceSource::ToneInference.weight(), 1)
}

///|
test "分离标注自动判定：书面=事实，重复措辞=推断，单次口头=假设" {
  assert_true(separation_eq(EvidenceSource::WrittenCommitment.separation(), KnownFact))
  assert_true(separation_eq(EvidenceSource::RepeatedBehavior.separation(), KnownFact))
  assert_true(separation_eq(EvidenceSource::RepeatedWording.separation(), ReasonableInference))
  assert_true(separation_eq(EvidenceSource::SingleOralPromise.separation(), UnverifiedHypothesis))
  assert_true(separation_eq(EvidenceSource::UserGuess.separation(), UnverifiedHypothesis))
}

///|
test "置信度合成：存在高权重证据 → 高置信度" {
  let e = EvidenceEngine::new()
  let items = [
    EvidenceItem::new(WrittenCommitment, "邮件确认了新项目范围"),
    EvidenceItem::new(SingleOralPromise, "会上口头说会考虑"),
  ]
  let r = e.assess(items, [])
  assert_true(confidence_eq(r.confidence, High))
}

///|
test "置信度合成：只有中权重证据 → 中置信度" {
  let e = EvidenceEngine::new()
  let items = [
    EvidenceItem::new(RepeatedWording, "连续两周说'再观察'"),
    EvidenceItem::new(CoworkerFeedback, "同事也提到他从不给明确答复"),
  ]
  let r = e.assess(items, [])
  assert_true(confidence_eq(r.confidence, Medium))
}

///|
test "置信度合成：只有低权重证据 → 低置信度且强制验证动作" {
  let e = EvidenceEngine::new()
  let items = [
    EvidenceItem::new(SingleOralPromise, "他说'好好干会考虑你'"),
    EvidenceItem::new(UserGuess, "我感觉他在拖延"),
  ]
  let r = e.assess(items, [])
  assert_true(confidence_eq(r.confidence, Low))
  assert_true(r.validation.contains("验证动作"))
  assert_true(r.summary.contains("低"))
}

///|
test "空证据 → 低置信度并提示先收集" {
  let e = EvidenceEngine::new()
  let r = e.assess([], ["晋升评估标准"])
  assert_true(confidence_eq(r.confidence, Low))
  assert_true(r.validation.contains("先收集"))
  assert_eq(r.missing.length(), 1)
}

///|
test "缺失信息原样保留" {
  let e = EvidenceEngine::new()
  let r = e.assess([EvidenceItem::new(WrittenCommitment, "邮件确认")], ["评估标准", "时间线"])
  assert_eq(r.missing.length(), 2)
  assert_eq(r.missing[0], "评估标准")
  assert_eq(r.missing[1], "时间线")
}

///|
test "summary 包含证据条数与置信度" {
  let e = EvidenceEngine::new()
  let r = e.assess([EvidenceItem::new(RepeatedBehavior, "两次承诺都没兑现")], [])
  assert_true(r.summary.contains("1 条"))
  assert_true(r.summary.contains("高"))
}
