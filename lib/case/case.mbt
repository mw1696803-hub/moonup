///|
/// Case 案例卡片检索模块。
///
/// 对应向上管理教练素材 references/18-case-library-ingestion.md：
/// - 案例以精简卡片存储（场景标签/权力/动作/风险/来源/迁移原则/脚本/失效条件），不存长文；
/// - 检索按场景标签匹配，返回最相似案例 + 迁移原则 + 不匹配点；
/// - 案例是模式参考，不是权威：使用前需校准用户情境差异。
///
/// 内置示例案例基于通用职场模式（标签体系来自素材），生产环境应从脱敏案例库导入。

/// 案例卡片
pub struct CaseCard {
  id : String
  scenario_tags : Array[String] // scenario: vague-request / promotion / multi-leader ...
  power : String                // direct-boss / skip-level / HR ...
  move : String                 // ask / clarify / negotiate / align ...
  risk : String                 // low / medium / high
  source : String               // generalized-pattern / anonymized-case ...
  principle : String            // 迁移原则
  script_safe : String          // 安全脚本（一条）
  failure_condition : String    // 失效条件
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

/// 创建案例库（内置 5 个通用模式案例）
pub fn CaseLibrary::new() -> CaseLibrary {
  {
    version: "case-v1",
    cases: builtin_cases(),
  }
}

/// 内置通用模式案例（生产环境应从脱敏案例库导入替换）
fn builtin_cases() -> Array[CaseCard] {
  let cases : Array[CaseCard] = []
  cases.push({
    id: "c-vague-request",
    scenario_tags: ["vague-request", "clarify"],
    power: "direct-boss",
    move: "clarify",
    risk: "low",
    source: "generalized-pattern",
    principle: "标准未定义前不承诺产出：先澄清验收标准再开工",
    script_safe: "我先把验收标准和交付物清单列出来，您确认后我再开工",
    failure_condition: "对方已明确标准时，重复澄清会显得不配合",
  })
  cases.push({
    id: "c-promotion",
    scenario_tags: ["promotion", "rosy-talk"],
    power: "direct-boss",
    move: "document",
    risk: "medium",
    source: "generalized-pattern",
    principle: "口头承诺转为书面条件，按时间线验证兑现",
    script_safe: "麻烦把评估标准和时间线书面发我，我对照着准备",
    failure_condition: "组织无晋升机制时，书面确认也难兑现，需考虑其他路径",
  })
  cases.push({
    id: "c-multi-leader",
    scenario_tags: ["multi-leader", "conflict"],
    power: "skip-level",
    move: "align",
    risk: "high",
    source: "generalized-pattern",
    principle: "多领导冲突先对齐再执行：让领导当面确认优先级排序",
    script_safe: "两位的优先级冲突时，我先拉个三方会确认排序，再动手",
    failure_condition: "领导之间本就不和时，避免让自己成为传话筒",
  })
  cases.push({
    id: "c-blame-risk",
    scenario_tags: ["blame-risk", "responsibility"],
    power: "project-owner",
    move: "document",
    risk: "high",
    source: "generalized-pattern",
    principle: "接任务先锁定决策记录与责任边界，避免事后背锅",
    script_safe: "我确认下：这个决定由谁拍板，失败责任如何界定？",
    failure_condition: "事实已发生的责任，事后无法通过话术转移",
  })
  cases.push({
    id: "c-extra-work",
    scenario_tags: ["extra-work", "no-schedule"],
    power: "direct-boss",
    move: "negotiate",
    risk: "medium",
    source: "generalized-pattern",
    principle: "加活必须重排期：用优先级和资源说话，不默默接下",
    script_safe: "加这个任务的话，原排期的哪个可以顺延？",
    failure_condition: "紧急救火场景下谈优先级，可能显得不配合",
  })
  cases
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
