///|
/// Case 案例卡片检索模块。
///
/// 对应向上管理教练素材 references/18-case-library-ingestion.md：
/// - 案例以精简卡片存储（场景标签/权力/动作/风险/来源/迁移原则/脚本/失效条件），不存长文；
/// - 检索按场景标签匹配，返回最相似案例 + 迁移原则 + 不匹配点；
/// - 案例是模式参考，不是权威：使用前需校准用户情境差异。
///
/// 生长口子（v1，规则后续逐步完善）：
/// - add_card / import_cards：运行时追加与批量导入（校验必填字段 + id 去重），案例库可持续生长；
/// - export_cards：导出全部卡片，为落盘/持久化与版本管理铺路；
/// - hit_count：命中计数信号，供后续"高频案例沉淀为用户机制"的规则使用（跨会话持久化待落盘加载后启用）。

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
}

/// 创建案例卡片（跨包使用；hit_count 初始为 0）
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
}

/// 检索结果
pub struct CaseSearchResult {
  matches : Array[CaseMatch] // 按命中数降序，最多 3 条
  total : Int
  note : String
}

/// 单条追加结果
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
    version: "case-v1",
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
pub fn CaseLibrary::search(self : CaseLibrary, query_tags : Array[String]) -> CaseSearchResult {
  let matches : Array[CaseMatch] = []
  for card in self.cases {
    let hit : Array[String] = []
    for q in query_tags {
      if arr_contains(card.scenario_tags, q) {
        hit.push(q)
      }
    }
    if hit.length() > 0 {
      let mismatch = mismatch_note(query_tags, card)
      matches.push({ card, matched_tags: hit, score: hit.length(), mismatch_note: mismatch })
    }
  }

  // 选择排序：score 降序（同分保持库内顺序）
  let n = matches.length()
  let mut i = 0
  while i < n {
    let mut best = i
    let mut j = i + 1
    while j < n {
      if matches[j].score > matches[best].score {
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
    note: "案例是模式参考而非权威：迁移前请校准权力位置、组织文化与关系温度",
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
}
