///|
/// Case 案例卡片检索模块。
///
/// 对应向上管理教练素材 references/18-case-library-ingestion.md：
/// - 案例以精简卡片存储（场景标签/权力/动作/风险/来源/迁移原则/脚本/失效条件），不存长文；
/// - 检索按场景标签匹配，返回最相似案例 + 迁移原则 + 不匹配点；
/// - 案例是模式参考，不是权威：使用前需校准用户情境差异。
///
/// 生长口子（v2）——吸收《复杂问题分析与沉淀协议 v1.3》与《世界建模 KB 调用协议 V1.1》：
/// - save_json / load_json：案例库整体序列化为 JSON 字符串，落盘由宿主执行（MoonBit core 无文件 IO）；
/// - record_feedback：反馈闭环（正向 → verified，负向 → superseded），单次经验不自动变规律；
/// - supersede：修正处理（不做平均化，后续修正优先，保留修正记录而非覆盖）；
/// - status 三态：tentative（待验证）/ verified（已验证）/ superseded（已失效）；
/// - 检索跳过 superseded，同分时 verified 优先（沉淀协议的确定性分级落地）；
/// - hit_count：命中计数信号（跨会话累计依赖落盘加载）。

/// 案例卡片
pub struct CaseCard {
  id : String
  scenario_tags : Array[String] // scenario: vague-request / promotion / multi-leader ...
  power : String                // direct-boss / skip-level / HR ...
  action : String               // ask / clarify / negotiate / align ...
  risk : String                 // low / medium / high
  source : String               // generalized-pattern / anonymized-case ...
  principle : String            // 迁移原则
  script_safe : String          // 安全脚本（一条）
  failure_condition : String    // 失效条件
  hit_count : Int               // 命中计数（沉淀信号，初始 0）
  status : String               // tentative / verified / superseded
  revision_note : String        // 修正记录（防失真：修正优先，保留痕迹）
  feedback_verdict : String     // pending / positive / negative
  created_at : String           // 沉淀时间（宿主注入，如 "2026-09-26"）
  updated_at : String           // 最近更新
} derive(ToJson, FromJson)

/// 创建案例卡片（跨包使用；新字段给默认值：tentative / pending / 空记录）
pub fn CaseCard::make(
  id : String,
  scenario_tags : Array[String],
  power : String,
  action : String,
  risk : String,
  source : String,
  principle : String,
  script_safe : String,
  failure_condition : String,
) -> CaseCard {
  {
    id,
    scenario_tags,
    power,
    action,
    risk,
    source,
    principle,
    script_safe,
    failure_condition,
    hit_count: 0,
    status: "tentative",
    revision_note: "",
    feedback_verdict: "pending",
    created_at: "",
    updated_at: "",
  }
}

/// 检索匹配结果
pub struct CaseMatch {
  card : CaseCard
  matched_tags : Array[String]
  score : Int
  mismatch_note : String
}

/// 案例库
pub struct CaseLibrary {
  version : String
  cases : Array[CaseCard]
} derive(ToJson, FromJson)

/// 检索结果
pub struct CaseSearchResult {
  matches : Array[CaseMatch] // 按命中数降序，最多 3 条；verified 优先于 tentative
  total : Int
  note : String
}

/// 单条追加/操作结果
pub struct CaseAddResult {
  added : Bool
  reason : String // 拒绝原因（成功时为空）
}

/// 批量导入结果
pub struct CaseImportResult {
  added : Int
  skipped : Int
  reasons : Array[String]
}

/// 创建案例库（内置 5 个通用模式案例）
pub fn CaseLibrary::new() -> CaseLibrary {
  {
    version: "case-v2",
    cases: builtin_cases(),
  }
}

/// 内置通用模式案例（生产环境应通过 import_cards 从脱敏案例库导入替换）
fn builtin_cases() -> Array[CaseCard] {
  let cases : Array[CaseCard] = []
  cases.push(CaseCard::make(
    "c-vague-request",
    ["vague-request", "clarify"],
    "direct-boss",
    "clarify",
    "low",
    "generalized-pattern",
    "标准未定义前不承诺产出：先澄清验收标准再开工",
    "我先把验收标准和交付物清单列出来，您确认后我再开工",
    "对方已明确标准时，重复澄清会显得不配合",
  ))
  cases.push(CaseCard::make(
    "c-promotion",
    ["promotion", "rosy-talk"],
    "direct-boss",
    "document",
    "medium",
    "generalized-pattern",
    "口头承诺转为书面条件，按时间线验证兑现",
    "麻烦把评估标准和时间线书面发我，我对照着准备",
    "组织无晋升机制时，书面确认也难兑现，需考虑其他路径",
  ))
  cases.push(CaseCard::make(
    "c-multi-leader",
    ["multi-leader", "conflict"],
    "skip-level",
    "align",
    "high",
    "generalized-pattern",
    "多领导冲突先对齐再执行：让领导当面确认优先级排序",
    "两位的优先级冲突时，我先拉个三方会确认排序，再动手",
    "领导之间本就不和时，避免让自己成为传话筒",
  ))
  cases.push(CaseCard::make(
    "c-blame-risk",
    ["blame-risk", "responsibility"],
    "project-owner",
    "document",
    "high",
    "generalized-pattern",
    "接任务先锁定决策记录与责任边界，避免事后背锅",
    "我确认下：这个决定由谁拍板，失败责任如何界定？",
    "事实已发生的责任，事后无法通过话术转移",
  ))
  cases.push(CaseCard::make(
    "c-extra-work",
    ["extra-work", "no-schedule"],
    "direct-boss",
    "negotiate",
    "medium",
    "generalized-pattern",
    "加活必须重排期：用优先级和资源说话，不默默接下",
    "加这个任务的话，原排期的哪个可以顺延？",
    "紧急救火场景下谈优先级，可能显得不配合",
  ))
  cases
}

/// 追加案例：校验必填字段 + id 去重，成功后案例库生长
pub fn CaseLibrary::add_card(self : CaseLibrary, card : CaseCard) -> CaseAddResult {
  if card.id == "" {
    { added: false, reason: "案例 id 不能为空" }
  } else if card.principle == "" || card.script_safe == "" || card.failure_condition == "" {
    { added: false, reason: "字段不完整：principle / script_safe / failure_condition 必填" }
  } else {
    let mut dup = false
    for c in self.cases {
      if c.id == card.id {
        dup = true
      }
    }
    if dup {
      { added: false, reason: "id 已存在：" + card.id }
    } else {
      self.cases.push(card)
      { added: true, reason: "" }
    }
  }
}

/// 批量导入案例：逐条校验，返回成功/跳过统计
pub fn CaseLibrary::import_cards(self : CaseLibrary, cards : Array[CaseCard]) -> CaseImportResult {
  let mut added = 0
  let reasons : Array[String] = []
  for c in cards {
    let r = self.add_card(c)
    if r.added {
      added = added + 1
    } else {
      reasons.push(c.id + ": " + r.reason)
    }
  }
  { added, skipped: cards.length() - added, reasons }
}

/// 导出全部案例（供落盘/持久化/版本管理）
pub fn CaseLibrary::export_cards(self : CaseLibrary) -> Array[CaseCard] {
  let out : Array[CaseCard] = []
  for c in self.cases {
    out.push(c)
  }
  out
}

/// 序列化为 JSON 字符串（落盘数据层；宿主负责写文件）
pub fn CaseLibrary::save_json(self : CaseLibrary) -> String {
  @json.to_json(self).stringify()
}

/// 从 JSON 字符串恢复案例库（宿主读取文件后调用）
/// 解析失败 / 字段缺失 / 类型不匹配 → Err（不 panic，调用方回退到 new()）
pub fn CaseLibrary::load_json(json : String) -> Result[CaseLibrary, String] {
  let parsed = @json.parse(json) catch {
    (_ : @json.ParseError) => return Err("案例库 JSON 解析失败：不是合法 JSON")
  }
  let lib : CaseLibrary = @json.from_json(parsed) catch {
    (_ : @json.JsonDecodeError) => return Err("案例库 JSON 解码失败：字段缺失或类型不匹配（可能是旧版本格式）")
  }
  Ok(lib)
}

/// 反馈闭环：真实调用后用户反馈（正向 → verified；负向 → superseded）
pub fn CaseLibrary::record_feedback(
  self : CaseLibrary,
  card_id : String,
  verdict : String,
  note : String,
) -> CaseAddResult {
  let mut idx = -1
  let mut i = 0
  while i < self.cases.length() {
    if self.cases[i].id == card_id {
      idx = i
    }
    i = i + 1
  }
  if idx < 0 {
    { added: false, reason: "未找到案例：" + card_id }
  } else if verdict != "positive" && verdict != "negative" {
    { added: false, reason: "verdict 必须是 positive 或 negative" }
  } else {
    let card = self.cases[idx]
    let new_status = if verdict == "positive" { "verified" } else { "superseded" }
    let new_revision = if card.revision_note == "" { note } else { card.revision_note + "\n" + note }
    self.cases[idx] = {
      ..card,
      status: new_status,
      feedback_verdict: verdict,
      revision_note: new_revision,
      updated_at: note,
    }
    { added: true, reason: "" }
  }
}

/// 修正处理：案例被更好案例/新事实替代时标记 superseded（保留卡片与修正记录，不删除）
pub fn CaseLibrary::supersede(self : CaseLibrary, card_id : String, reason : String) -> CaseAddResult {
  let mut idx = -1
  let mut i = 0
  while i < self.cases.length() {
    if self.cases[i].id == card_id {
      idx = i
    }
    i = i + 1
  }
  if idx < 0 {
    { added: false, reason: "未找到案例：" + card_id }
  } else {
    let card = self.cases[idx]
    let new_revision = if card.revision_note == "" { reason } else { card.revision_note + "\n" + reason }
    self.cases[idx] = {
      ..card,
      status: "superseded",
      revision_note: new_revision,
      updated_at: reason,
    }
    { added: true, reason: "" }
  }
}

fn arr_contains(arr : Array[String], s : String) -> Bool {
  let mut found = false
  for x in arr {
    if x == s {
      found = true
    }
  }
  found
}

/// 检索：按场景标签匹配，返回最多 3 条 + 不匹配提示
/// 跳过 superseded；同分时 verified 优先（确定性分级落地）
/// 命中卡片 hit_count +1（沉淀信号，跨会话通过落盘累计）
pub fn CaseLibrary::search(self : CaseLibrary, query_tags : Array[String]) -> CaseSearchResult {
  let matches : Array[CaseMatch] = []
  let mut i = 0
  while i < self.cases.length() {
    let card = self.cases[i]
    if card.status != "superseded" {
      let hit : Array[String] = []
      for q in query_tags {
        if arr_contains(card.scenario_tags, q) {
          hit.push(q)
        }
      }
      if hit.length() > 0 {
        // 命中计数 +1（单次经验积累，供机制候选规则使用）
        let updated = { ..card, hit_count: card.hit_count + 1 }
        self.cases[i] = updated
        let mismatch = mismatch_note(query_tags, card)
        matches.push({ card: updated, matched_tags: hit, score: hit.length(), mismatch_note: mismatch })
      }
    }
    i = i + 1
  }

  // 选择排序：score 降序；同分 verified 优先；再同分保持库序
  let n = matches.length()
  let mut i = 0
  while i < n {
    let mut best = i
    let mut j = i + 1
    while j < n {
      if better(matches[j], matches[best]) {
        best = j
      }
      j = j + 1
    }
    if best != i {
      let tmp = matches[i]
      matches[i] = matches[best]
      matches[best] = tmp
    }
    i = i + 1
  }

  let top : Array[CaseMatch] = []
  for m in matches {
    if top.length() < 3 {
      top.push(m)
    }
  }

  {
    matches: top,
    total: matches.length(),
    note: "案例是模式参考而非权威：迁移前请校准权力位置、组织文化与关系温度；superseded 案例不参与匹配",
  }
}

/// 显式记录一次命中（宿主可在检索命中后手动调用；search 已自动累计）
pub fn CaseLibrary::record_hit(self : CaseLibrary, card_id : String) -> CaseAddResult {
  let mut idx = -1
  let mut i = 0
  while i < self.cases.length() {
    if self.cases[i].id == card_id {
      idx = i
    }
    i = i + 1
  }
  if idx < 0 {
    { added: false, reason: "未找到案例：" + card_id }
  } else {
    let card = self.cases[idx]
    self.cases[idx] = { ..card, hit_count: card.hit_count + 1, updated_at: "hit+" }
    { added: true, reason: "" }
  }
}

/// 机制候选（雏形规则）：命中次数达到阈值 且 已验证（feedback positive）→ 候选机制
/// 后续完善：多场景重复反馈（≥2-3 个不同场景）后由人工确认固化
pub fn CaseLibrary::mechanism_candidates(self : CaseLibrary, min_hits : Int) -> Array[CaseCard] {
  let out : Array[CaseCard] = []
  for c in self.cases {
    if c.status == "verified" && c.hit_count >= min_hits {
      out.push(c)
    }
  }
  out
}

/// 压力测试示例案例集（20 条，公开给工具/宿主做落盘演示与压测）
pub fn CaseLibrary::sample_pressure_cases() -> Array[CaseCard] {
  pressure_cases()
}

/// 排序优先级：score 高者优先；同分 verified 优先；否则保持库序
fn better(a : CaseMatch, b : CaseMatch) -> Bool {
  if a.score != b.score {
    a.score > b.score
  } else if a.card.status != b.card.status {
    a.card.status == "verified"
  } else {
    false
  }
}

/// 不匹配点提示：查询里有但案例未命中的标签
fn mismatch_note(query_tags : Array[String], card : CaseCard) -> String {
  let extra : Array[String] = []
  for q in query_tags {
    if !arr_contains(card.scenario_tags, q) {
      extra.push(q)
    }
  }
  if extra.length() > 0 {
    "注意：情境含「" + join(extra) + "」与本案例不完全一致，迁移时需校准"
  } else {
    ""
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

// ===== 压力测试案例集 =====
// 由真实职场场景 + CRM 场景迁移构造（用于压测检索/反馈/修正/落盘链路）

/// 构造压力测试案例库（20 条，覆盖模糊/多头/背锅/画饼/竞品/HR/跨部门等）
fn pressure_cases() -> Array[CaseCard] {
  let cs : Array[CaseCard] = []
  cs.push(CaseCard::make("p-weekly-rosy", ["weekly-rosy", "rosy-talk"], "direct-boss", "document", "medium", "anonymized-case", "周会画饼：把'辛苦不会白费'转成可验证的书面条件", "我记一下：这周的重点验收标准是什么？", "连续三次无兑现后，重复记录会显得质疑"))
  cs.push(CaseCard::make("p-multi-culture", ["multi-leader", "culture"], "skip-level", "align", "high", "anonymized-case", "多头领导 + 文化差异：先对齐规则再谈优先级", "两边的汇报口径我先确认一遍再执行", "文化冲突已公开化时，中立传话也可能被当成站队"))
  cs.push(CaseCard::make("p-blame-actual", ["blame-risk", "retrospective"], "project-owner", "document", "high", "anonymized-case", "背锅已发生：复盘只谈证据链，不谈态度", "我把当时的决策记录和邮件整理一份给您", "复盘会已定性时，补充证据会被视为翻旧账"))
  cs.push(CaseCard::make("p-competitor-intel", ["competitor", "intel"], "external", "observe", "medium", "anonymized-case", "竞品信息收集者：每场活动都来，只为收集情报", "先判断对方提问是否指向内部细节，再决定披露边界", "对方同时是潜在客户时，情报收集也可能转为转化线索"))
  cs.push(CaseCard::make("p-student-buy", ["purchase", "student"], "sales", "qualify", "low", "anonymized-case", "学生低购买力误判：简单剔除会误伤有意向者", "用行为意向（主动提问/深挖细节）补充购买力判断", "预算确实不足时，过早强推会破坏关系"))
  cs.push(CaseCard::make("p-missing-touch", ["missing-data", "inactive"], "sales", "touch", "medium", "anonymized-case", "身份/渠道缺失且不活跃：需要人工触达补信息", "先触达补齐画像再打分，缺失数据不直接打低分", "多次触达无回应时，继续投入是沉没成本"))
  cs.push(CaseCard::make("p-hr-labor", ["hr", "labor-risk"], "hr", "document", "high", "anonymized-case", "劳动风险：先咨询专业意见，不留书面把柄", "我先了解流程，必要时咨询专业意见再回复", "对方已正式启动法律程序时，个人话术不再适用"))
  cs.push(CaseCard::make("p-cross-resource", ["cross-dept", "resource"], "peer", "negotiate", "medium", "anonymized-case", "跨部门资源争夺：用业务影响说话，不空手要资源", "我把这个需求对业务目标的影响量化后，再向对方要排期", "对方部门也在冲刺时，谈判窗口很小"))
  cs.push(CaseCard::make("p-delegated-vague", ["delegation", "vague-request"], "direct-boss", "clarify", "medium", "anonymized-case", "被授权但责任模糊：先锁权责边界再开工", "我确认下：这个权限范围到哪，责任由谁兜底？", "组织已明确授权时，反复确认显得不担责"))
  cs.push(CaseCard::make("p-firefighting", ["firefighting", "extra-work"], "direct-boss", "negotiate", "high", "anonymized-case", "紧急救火加活：先给二选一，不默默接下", "救火任务和原排期冲突，我先明确哪个优先级更高", "火烧眉毛时谈优先级，可能显得不配合"))
  cs.push(CaseCard::make("p-bayes-update", ["bayes", "behavior-intent"], "sales", "observe", "low", "anonymized-case", "贝叶斯更新：每次行为后更新转化概率，不一次定生死", "把每次互动当作一次概率更新，而不是下结论", "行为样本太少时，概率更新噪声很大"))
  cs.push(CaseCard::make("p-question-driven", ["question-driven", "intent"], "sales", "qualify", "medium", "anonymized-case", "主动提问驱动：参与度低但主动提问题，意向可能更高", "把主动提问视为强意向信号，补查其他行为", "提问只是随口询问时，会高估意向"))
  cs.push(CaseCard::make("p-silent-member", ["silent", "inactive"], "community", "touch", "low", "anonymized-case", "长期沉默成员：先区分是观望还是流失", "沉默 + 历史活跃 → 观望；沉默 + 零历史 → 待验证", "沉默成员批量触达会引发退群风险"))
  cs.push(CaseCard::make("p-rosy-promise", ["rosy-talk", "promise"], "direct-boss", "document", "high", "anonymized-case", "漂亮承诺无兑现机制：先要书面条件，再谈信任", "您说的这个机会，我书面列一下前提条件可以吗？", "对方一贯言而无信时，书面条件也只是缓冲"))
  cs.push(CaseCard::make("p-resource-approver", ["resource", "approval"], "finance", "ask", "medium", "anonymized-case", "资源审批人未指明：先问清楚谁拍板再要资源", "这个预算的审批人是谁？我先对齐口径", "审批链复杂时，问错人反而拖延"))
  cs.push(CaseCard::make("p-org-mechanism", ["org-design", "mechanism"], "system", "observe", "medium", "anonymized-case", "冲突源于组织设计：先找缺失机制，不归因个人", "我先看看是机制缺位还是个人问题，再决定动作", "机制确实存在时，归因于机制会错过个人改进"))
  cs.push(CaseCard::make("p-third-option", ["deadlock", "third-option"], "direct-boss", "negotiate", "medium", "anonymized-case", "两难死锁：先造第三选项，不急着二选一", "除了 A 和 B，还有没有 C 的变体？我先想一个", "决策窗口极短时，造选项反而拖延"))
  cs.push(CaseCard::make("p-conflicting-signal", ["conflicting", "signal"], "direct-boss", "clarify", "high", "anonymized-case", "言行矛盾：措辞漂亮但行为相反，先当弱证据", "我观察到上次说的和这次做的有出入，想确认下口径", "矛盾可能来自误解时，直接指出会激化"))
  cs.push(CaseCard::make("p-stakeholder-blind", ["stakeholder", "blind-spot"], "skip-level", "map", "medium", "anonymized-case", "相关方盲区：决策影响多人时，先画相关方地图", "这件事影响谁？我先列个清单再沟通", "相关方太多时，地图会变成拖延借口"))
  cs.push(CaseCard::make("p-success-copy", ["success", "copy"], "peer", "transfer", "low", "anonymized-case", "单次成功不自动变规律：复制前先标适用边界", "这个成功背后的条件是什么？满足才迁移", "他人成功含运气成分时，盲目复制会翻车"))
  cs
}///|
test "压力案例集 20 条全部入库且检索可用" {
  let lib = CaseLibrary::new()
  let r = lib.import_cards(pressure_cases())
  assert_eq(r.added, 20)
  assert_eq(r.skipped, 0)
  assert_eq(lib.export_cards().length(), 25)
}

///|
test "save_json → load_json round-trip：内容一致" {
  let lib = CaseLibrary::new()
  let _ = lib.import_cards(pressure_cases())
  let json = lib.save_json()
  assert_true(json.length() > 100)
  let loaded = CaseLibrary::load_json(json)
  match loaded {
    Ok(lib2) => {
      assert_eq(lib2.export_cards().length(), 25)
      // round-trip 后检索能力保留
      let r = lib2.search(["promotion"])
      assert_true(r.total >= 1)
    }
    Err(_) => panic()
  }
}

///|
test "load_json 损坏 JSON → Err" {
  match CaseLibrary::load_json("{ not json") {
    Err(_) => ()
    Ok(_) => panic()
  }
}

///|
test "load_json 字段缺失 → Err" {
  match CaseLibrary::load_json("{\"version\":\"case-v2\",\"cases\":[{\"id\":\"x\"}]}") {
    Err(_) => ()
    Ok(_) => panic()
  }
}

///|
test "load_json 空数组库合法" {
  match CaseLibrary::load_json("{\"version\":\"case-v2\",\"cases\":[]}") {
    Ok(lib) => assert_eq(lib.export_cards().length(), 0)
    Err(_) => panic()
  }
}

///|
test "feedback positive → status verified" {
  let lib = CaseLibrary::new()
  let r = lib.record_feedback("c-promotion", "positive", "用户按脚本书面确认成功")
  assert_true(r.added)
  for c in lib.export_cards() {
    if c.id == "c-promotion" {
      assert_eq(c.status, "verified")
      assert_eq(c.feedback_verdict, "positive")
      assert_true(c.revision_note.contains("书面确认成功"))
    }
  }
}

///|
test "feedback negative → superseded 且检索跳过" {
  let lib = CaseLibrary::new()
  let r = lib.record_feedback("c-vague-request", "negative", "该模式在当前组织不适用")
  assert_true(r.added)
  let res = lib.search(["vague-request"])
  assert_eq(res.total, 0)
  // 卡片保留（不删除），带修正记录
  for c in lib.export_cards() {
    if c.id == "c-vague-request" {
      assert_eq(c.status, "superseded")
      assert_true(c.revision_note.contains("不适用"))
    }
  }
}

///|
test "supersede 保留卡片 + 修正记录，检索跳过" {
  let lib = CaseLibrary::new()
  let r = lib.supersede("c-extra-work", "新规则替代：先量化影响再谈排期")
  assert_true(r.added)
  let res = lib.search(["extra-work"])
  assert_eq(res.total, 0)
  let mut found = false
  for c in lib.export_cards() {
    if c.id == "c-extra-work" {
      found = true
      assert_eq(c.status, "superseded")
    }
  }
  assert_true(found)
}

///|
test "同分时 verified 优先于 tentative" {
  let lib = CaseLibrary::new()
  let _ = lib.add_card(CaseCard::make("t-same-a", ["alpha"], "direct-boss", "document", "low", "anonymized-case", "p1", "s1", "f1"))
  let _ = lib.add_card(CaseCard::make("t-same-b", ["alpha"], "direct-boss", "document", "low", "anonymized-case", "p2", "s2", "f2"))
  // 把 t-same-a 标记 verified
  let _ = lib.record_feedback("t-same-a", "positive", "验证通过")
  let r = lib.search(["alpha"])
  assert_eq(r.matches[0].card.id, "t-same-a")
  assert_eq(r.matches[0].card.status, "verified")
}

///|
test "record_feedback 未找到案例 → 拒绝" {
  let lib = CaseLibrary::new()
  let r = lib.record_feedback("c-not-exist", "positive", "")
  assert_false(r.added)
  assert_true(r.reason.contains("未找到"))
}

///|
test "record_feedback 非法 verdict → 拒绝" {
  let lib = CaseLibrary::new()
  let r = lib.record_feedback("c-promotion", "maybe", "")
  assert_false(r.added)
}

///|
test "压力检索：多标签命中 top3 且 superseded 不参与" {
  let lib = CaseLibrary::new()
  let _ = lib.import_cards(pressure_cases())
  let _ = lib.supersede("p-rosy-promise", "被 p-weekly-rosy 替代")
  let r = lib.search(["rosy-talk", "document"])
  assert_true(r.total >= 1)
  for m in r.matches {
    assert_true(m.card.status != "superseded")
  }
}

///|
test "压力检索：竞品场景命中" {
  let lib = CaseLibrary::new()
  let _ = lib.import_cards(pressure_cases())
  let r = lib.search(["competitor", "intel"])
  assert_eq(r.matches[0].card.id, "p-competitor-intel")
}

///|
test "压力检索：学生购买力场景命中" {
  let lib = CaseLibrary::new()
  let _ = lib.import_cards(pressure_cases())
  let r = lib.search(["purchase", "student"])
  assert_eq(r.matches[0].card.id, "p-student-buy")
}

///|
test "压力检索：无命中不误报" {
  let lib = CaseLibrary::new()
  let _ = lib.import_cards(pressure_cases())
  let r = lib.search(["quantum", "crypto"])
  assert_eq(r.matches.length(), 0)
  assert_eq(r.total, 0)
}

///|
test "save 含压力库 → 字段完整（含 status/hit_count）" {
  let lib = CaseLibrary::new()
  let _ = lib.import_cards(pressure_cases())
  let json = lib.save_json()
  assert_true(json.contains("status"))
  assert_true(json.contains("hit_count"))
  assert_true(json.contains("revision_note"))
}

///|
test "内置案例库至少 5 条" {
  let lib = CaseLibrary::new()
  assert_true(lib.cases.length() >= 5)
}

///|
test "检索命中：promotion → 返回晋升案例" {
  let r = CaseLibrary::new().search(["promotion"])
  assert_eq(r.total, 1)
  assert_eq(r.matches[0].card.id, "c-promotion")
}

///|
test "多标签检索：两条都命中，同分按库序" {
  let r = CaseLibrary::new().search(["multi-leader", "promotion"])
  assert_true(r.total >= 2)
  assert_true(r.matches.length() >= 2)
  // 同分（score=1）保持库内顺序：c-promotion 在 c-multi-leader 前
  assert_eq(r.matches[0].card.id, "c-promotion")
  assert_true(r.matches[0].score >= r.matches[1].score)
}

///|
test "无命中 → matches 空，total=0" {
  let r = CaseLibrary::new().search(["hr-crisis"])
  assert_eq(r.matches.length(), 0)
  assert_eq(r.total, 0)
}

///|
test "空查询 → 空结果" {
  let r = CaseLibrary::new().search([])
  assert_eq(r.matches.length(), 0)
}

///|
test "最多返回 3 条" {
  let r = CaseLibrary::new().search(["clarify", "promotion", "document", "align", "negotiate", "conflict", "no-schedule", "responsibility", "rosy-talk", "vague-request"])
  assert_true(r.matches.length() <= 3)
}

///|
test "匹配分数=命中标签数" {
  let r = CaseLibrary::new().search(["promotion", "rosy-talk"])
  assert_eq(r.matches[0].score, 2)
  assert_eq(r.matches[0].matched_tags.length(), 2)
}

///|
test "案例字段完整性：principle/script/failure 非空" {
  let lib = CaseLibrary::new()
  for c in lib.cases {
    assert_true(c.principle.length() > 5)
    assert_true(c.script_safe.length() > 5)
    assert_true(c.failure_condition.length() > 5)
  }
}

///|
test "note 提示案例是模式参考" {
  let r = CaseLibrary::new().search(["promotion"])
  assert_true(r.note.contains("模式参考"))
}

///|
test "不匹配点提示生成" {
  let r = CaseLibrary::new().search(["promotion", "multi-leader"])
  // c-promotion 未命中 multi-leader → 应有提示
  for m in r.matches {
    if m.card.id == "c-promotion" {
      assert_true(m.mismatch_note.contains("multi-leader"))
    }
  }
}

///|
test "add_card 追加成功：案例库生长 +1" {
  let lib = CaseLibrary::new()
  let before = lib.cases.length()
  let card = CaseCard::make(
    "c-user-hr-discussion",
    ["hr", "labor-risk"],
    "hr",
    "document",
    "high",
    "anonymized-case",
    "劳动风险场景：先咨询专业意见，不留书面把柄",
    "我先了解一下流程，必要时咨询专业意见再回复",
    "对方已正式启动法律程序时，个人话术不再适用",
  )
  let r = lib.add_card(card)
  assert_true(r.added)
  assert_eq(r.reason, "")
  assert_eq(lib.cases.length(), before + 1)
}

///|
test "add_card 重复 id → 拒绝" {
  let lib = CaseLibrary::new()
  let card = CaseCard::make(
    "c-promotion",
    ["promotion"],
    "direct-boss",
    "document",
    "medium",
    "generalized-pattern",
    "x",
    "y",
    "z",
  )
  let r = lib.add_card(card)
  assert_false(r.added)
  assert_true(r.reason.contains("已存在"))
}

///|
test "add_card 空 id → 拒绝" {
  let lib = CaseLibrary::new()
  let card = CaseCard::make("", ["promotion"], "direct-boss", "document", "medium", "generalized-pattern", "x", "y", "z")
  let r = lib.add_card(card)
  assert_false(r.added)
  assert_true(r.reason.contains("id 不能为空"))
}

///|
test "add_card 字段不完整 → 拒绝" {
  let lib = CaseLibrary::new()
  let card = CaseCard::make("c-incomplete", ["promotion"], "direct-boss", "document", "medium", "generalized-pattern", "", "y", "")
  let r = lib.add_card(card)
  assert_false(r.added)
  assert_true(r.reason.contains("字段不完整"))
}

///|
test "import_cards 批量：2 新增 + 1 重复 → added=2 skipped=1" {
  let lib = CaseLibrary::new()
  let cards = [
    CaseCard::make("c-imp-a", ["promotion"], "direct-boss", "document", "medium", "anonymized-case", "p1", "s1", "f1"),
    CaseCard::make("c-imp-b", ["conflict"], "skip-level", "align", "high", "anonymized-case", "p2", "s2", "f2"),
    CaseCard::make("c-promotion", ["promotion"], "direct-boss", "document", "medium", "generalized-pattern", "p3", "s3", "f3"),
  ]
  let r = lib.import_cards(cards)
  assert_eq(r.added, 2)
  assert_eq(r.skipped, 1)
  assert_eq(r.reasons.length(), 1)
}

///|
test "export_cards 导出全部（含新增）" {
  let lib = CaseLibrary::new()
  let _ = lib.add_card(CaseCard::make("c-export-new", ["promotion"], "direct-boss", "document", "medium", "anonymized-case", "p", "s", "f"))
  let out = lib.export_cards()
  assert_eq(out.length(), 6)
  let mut has_new = false
  for c in out {
    if c.id == "c-export-new" {
      has_new = true
    }
  }
  assert_true(has_new)
}

///|
test "新增案例可被检索命中" {
  let lib = CaseLibrary::new()
  let _ = lib.add_card(CaseCard::make("c-custom-hr", ["hr", "labor-risk"], "hr", "document", "high", "anonymized-case", "先咨询专业意见", "我先了解流程", "法律程序启动后话术失效"))
  let r = lib.search(["hr"])
  assert_true(r.total >= 1)
  assert_eq(r.matches[0].card.id, "c-custom-hr")
}

///|
test "内置案例 hit_count 初始为 0（沉淀信号）" {
  let lib = CaseLibrary::new()
  for c in lib.cases {
    assert_eq(c.hit_count, 0)
  }
}

///|
test "make 构造字段正确" {
  let c = CaseCard::make("c-make", ["a"], "direct-boss", "ask", "low", "generalized-pattern", "principle", "script", "failure")
  assert_eq(c.id, "c-make")
  assert_eq(c.hit_count, 0)
  assert_eq(c.risk, "low")
  assert_eq(c.scenario_tags.length(), 1)
  assert_eq(c.status, "tentative")
  assert_eq(c.feedback_verdict, "pending")
}
///|
test "search 命中后 hit_count 自动累计" {
  let lib = CaseLibrary::new()
  let _ = lib.search(["promotion"])
  for c in lib.export_cards() {
    if c.id == "c-promotion" {
      assert_eq(c.hit_count, 1)
    }
  }
}

///|
test "record_hit 显式累计 + 未找到拒绝" {
  let lib = CaseLibrary::new()
  let r = lib.record_hit("c-promotion")
  assert_true(r.added)
  let r2 = lib.record_hit("c-promotion")
  assert_true(r2.added)
  for c in lib.export_cards() {
    if c.id == "c-promotion" {
      assert_eq(c.hit_count, 2)
    }
  }
  let bad = lib.record_hit("c-nope")
  assert_false(bad.added)
}

///|
test "mechanism_candidates：高频+已验证 → 候选" {
  let lib = CaseLibrary::new()
  let _ = lib.add_card(CaseCard::make("m-hit-v", ["alpha"], "direct-boss", "document", "low", "anonymized-case", "p1", "s1", "f1"))
  let _ = lib.add_card(CaseCard::make("m-hit-t", ["beta"], "direct-boss", "document", "low", "anonymized-case", "p2", "s2", "f2"))
  let _ = lib.add_card(CaseCard::make("m-low-v", ["gamma"], "direct-boss", "document", "low", "anonymized-case", "p3", "s3", "f3"))
  // m-hit-v：3 次命中 + verified
  let _ = lib.record_hit("m-hit-v")
  let _ = lib.record_hit("m-hit-v")
  let _ = lib.record_hit("m-hit-v")
  let _ = lib.record_feedback("m-hit-v", "positive", "验证通过")
  // m-hit-t：3 次命中但 tentative
  let _ = lib.record_hit("m-hit-t")
  let _ = lib.record_hit("m-hit-t")
  let _ = lib.record_hit("m-hit-t")
  // m-low-v：verified 但 0 次命中
  let _ = lib.record_feedback("m-low-v", "positive", "验证通过")
  let cands = lib.mechanism_candidates(2)
  assert_eq(cands.length(), 1)
  assert_eq(cands[0].id, "m-hit-v")
}

///|
test "mechanism_candidates：阈值过滤" {
  let lib = CaseLibrary::new()
  let _ = lib.record_feedback("c-promotion", "positive", "验证")
  let _ = lib.record_hit("c-promotion")
  // 阈值 2 → 无候选（只 1 次命中）
  let cands = lib.mechanism_candidates(2)
  assert_eq(cands.length(), 0)
  // 阈值 0/1 → 有候选
  let cands1 = lib.mechanism_candidates(1)
  assert_eq(cands1.length(), 1)
}

///|
test "sample_pressure_cases 公开 20 条且可导入" {
  let lib = CaseLibrary::new()
  let r = lib.import_cards(CaseLibrary::sample_pressure_cases())
  assert_eq(r.added, 20)
}

// 显式声明 derive 方法提升，消除 implicit_impl_as_method 弃用警告
pub extend CaseLibrary with ToJson::{to_json}
pub extend CaseCard with ToJson::{to_json}
pub extend CaseLibrary with @moonbitlang/core/json.FromJson::{from_json}
pub extend CaseCard with @moonbitlang/core/json.FromJson::{from_json}
