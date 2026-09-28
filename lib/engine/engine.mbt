///|
/// Engine 通用规则引擎层。
///
/// 定位：MoonBit 生态的确定性规则引擎核心——
/// - 规则即数据：Rule 用字符串 DSL 描述条件与动作，使用者定义自己的规则集；
/// - 事实通用：Fact 为键值映射，不绑定任何业务语义；
/// - 确定性：同一规则集 + 同一事实 → 同一执行结果（无随机、无外部依赖）；
/// - 冲突消解：匹配规则按 priority 降序执行；同字段「覆盖式设置」先到先得（高优先级胜出）。
///
/// 条件 DSL（condition，多条用 && 连接，全部满足才命中）：
///   key==value   等于
///   key!=value   不等于
///   key~=value   包含子串
///
/// 动作 DSL（action）：
///   key=value    覆盖式设置（同字段只采纳最高优先级那条）
///   key+=value   追加式（标签累积，value 追加到已有值，逗号分隔）
///
/// 示例（客户意向分层）：
///   Rule("r1", "高意向", "intent~=高 && region==华东", "tier=高价值", 10, "高意向+华东")
///   Rule("r2", "补标签", "budget>0", "tags+=高潜", 5, "有预算即补标签")
///
/// 领域规则包（evidence 权重映射、guardrail 触发条件、scenario 场景路由等）
/// 均可基于本引擎构建；本仓库其余模块即作为预置规则包的示例。

/// 事实：键值映射（可原地更新）
pub struct Fact {
  map : Map[String, String]
}

/// 创建空事实
pub fn Fact::new() -> Fact {
  { map: Map([]) }
}

/// 设置事实字段（覆盖）
pub fn Fact::set(self : Fact, key : String, value : String) -> Unit {
  self.map[key] = value
}

/// 读取事实字段；缺失返回空串
pub fn Fact::get(self : Fact, key : String) -> String {
  match self.map.get(key) {
    Some(v) => v
    None => ""
  }
}

/// 字段是否存在
pub fn Fact::has(self : Fact, key : String) -> Bool {
  match self.map.get(key) {
    Some(_) => true
    None => false
  }
}

/// 追加标签值（已有值以逗号连接）
pub fn Fact::append(self : Fact, key : String, value : String) -> Unit {
  let old = self.get(key)
  if old == "" {
    self.map[key] = value
  } else {
    self.map[key] = old + "," + value
  }
}

/// 规则：条件 + 动作 + 优先级 + 命中说明
pub struct Rule {
  id : String
  label : String
  condition : String
  action : String
  priority : Int
  note : String
}

/// 创建规则
pub fn Rule::new(
  id : String,
  label : String,
  condition : String,
  action : String,
  priority : Int,
  note : String,
) -> Rule {
  { id, label, condition, action, priority, note }
}

/// 规则引擎：按声明顺序评估，命中的规则按 priority 降序执行
pub struct RuleEngine {
  rules : Array[Rule]
}

/// 创建引擎（注入规则集）
pub fn RuleEngine::new(rules : Array[Rule]) -> RuleEngine {
  { rules }
}

/// 执行结果
pub struct RuleExecution {
  matched : Array[Rule] // 命中的规则（原始声明顺序）
  ordered : Array[Rule] // 冲突消解后的执行顺序（priority 降序）
  facts : Fact          // 执行动作后的事实（原地更新）
  notes : Array[String] // 按执行顺序的命中说明
}

/// 执行：评估条件 → 冲突消解排序 → 依次执行动作
pub fn RuleEngine::execute(self : RuleEngine, input : Fact) -> RuleExecution {
  let matched : Array[Rule] = []
  for r in self.rules {
    if eval_condition(r.condition, input) {
      matched.push(r)
    }
  }
  let ordered = sort_by_priority(matched)
  let seen : Array[String] = []
  let notes : Array[String] = []
  for r in ordered {
    apply_action(r.action, input, seen)
    notes.push(r.note)
  }
  { matched, ordered, facts: input, notes }
}

/// 条件求值：多条 && 连接，全部满足才为真
fn eval_condition(cond : String, f : Fact) -> Bool {
  let mut ok = true
  for p in cond.split("&&") {
    let c = p.trim().to_owned()
    if c != "" && !eval_single(c, f) {
      ok = false
    }
  }
  ok
}

/// 单条件求值：== / != / ~=
fn eval_single(c : String, f : Fact) -> Bool {
  if c.contains("!=") {
    let (key, value) = split_binary(c, "!=")
    return f.get(key) != value
  }
  if c.contains("==") {
    let (key, value) = split_binary(c, "==")
    return f.get(key) == value
  }
  if c.contains("~=") {
    let (key, value) = split_binary(c, "~=")
    return f.get(key).contains(value)
  }
  false // 未知条件 → 不匹配（宁可保守）
}

/// 二元切分（取第一个分隔符前后）
fn split_binary(s : String, sep : String) -> (String, String) {
  let mut left = ""
  let mut right = ""
  let mut first = true
  for p in s.split(sep) {
    if first {
      left = p.trim().to_owned()
    } else {
      right = p.trim().to_owned()
    }
    first = false
  }
  (left, right)
}

/// 冲突消解排序：priority 降序，同优先级保持声明顺序（稳定）
fn sort_by_priority(arr : Array[Rule]) -> Array[Rule] {
  let mut buf : Array[Rule] = []
  for r in arr {
    let mut placed = false
    let next : Array[Rule] = []
    for x in buf {
      if !placed && r.priority > x.priority {
        next.push(r)
        placed = true
      }
      next.push(x)
    }
    if !placed {
      next.push(r)
    }
    buf = next
  }
  buf
}

/// 执行动作：多条 && 连接依次执行；覆盖式设置受 seen 约束（先到先得）
fn apply_action(action : String, f : Fact, seen : Array[String]) -> Unit {
  for p in action.split("&&") {
    let a = p.trim().to_owned()
    if a != "" {
      apply_single(a, f, seen)
    }
  }
}

fn apply_single(a : String, f : Fact, seen : Array[String]) -> Unit {
  if a.contains("+=") {
    // 追加式：总是执行（标签累积）
    let (key, value) = split_binary(a, "+=")
    f.append(key, value)
    return
  }
  if a.contains("=") {
    // 覆盖式：同字段只采纳最高优先级那条
    let (key, value) = split_binary(a, "=")
    if !seen.contains(key) {
      f.set(key, value)
      seen.push(key)
    }
    return
  }
}

///|
test "等于条件命中" {
  let f = Fact::new()
  f.set("tier", "gold")
  let e = RuleEngine::new([Rule::new("r1", "gold", "tier==gold", "flag=1", 1, "gold 命中")])
  let r = e.execute(f)
  assert_eq(r.matched.length(), 1)
  assert_eq(r.facts.get("flag"), "1")
}

///|
test "不等于条件" {
  let f = Fact::new()
  f.set("tier", "silver")
  let e = RuleEngine::new([Rule::new("r1", "not-gold", "tier!=gold", "flag=1", 1, "非 gold")])
  let r = e.execute(f)
  assert_eq(r.matched.length(), 1)
}

///|
test "包含子串条件" {
  let f = Fact::new()
  f.set("intent", "购买意向高")
  let e = RuleEngine::new([Rule::new("r1", "hi", "intent~=高", "level=high", 1, "高意向")])
  let r = e.execute(f)
  assert_eq(r.facts.get("level"), "high")
}

///|
test "多条件 && 需全部满足" {
  let f = Fact::new()
  f.set("intent", "高")
  f.set("region", "华东")
  let e = RuleEngine::new([
    Rule::new("r1", "both", "intent~=高 && region==华东", "tier=A", 1, "双条件"),
    Rule::new("r2", "region-only", "region==华北", "tier=B", 1, "单条件"),
  ])
  let r = e.execute(f)
  assert_eq(r.matched.length(), 1)
  assert_eq(r.facts.get("tier"), "A")
}

///|
test "未知条件不命中（保守）" {
  let f = Fact::new()
  f.set("a", "1")
  let e = RuleEngine::new([Rule::new("r1", "unknown", "a>>1", "flag=1", 1, "未知语法")])
  let r = e.execute(f)
  assert_eq(r.matched.length(), 0)
}

///|
test "追加式标签累积" {
  let f = Fact::new()
  let e = RuleEngine::new([
    Rule::new("r1", "tagA", "a==1", "tags+=VIP", 1, "加 VIP"),
    Rule::new("r2", "tagB", "a==1", "tags+=老客", 1, "加老客"),
  ])
  f.set("a", "1")
  let r = e.execute(f)
  assert_eq(r.facts.get("tags"), "VIP,老客")
}

///|
test "冲突消解：覆盖式设置高优先级胜出" {
  let f = Fact::new()
  f.set("score", "85")
  let e = RuleEngine::new([
    Rule::new("r1", "low", "score==85", "tier=普通", 5, "低优先"),
    Rule::new("r2", "high", "score==85", "tier=高价值", 10, "高优先"),
  ])
  let r = e.execute(f)
  assert_eq(r.matched.length(), 2)
  assert_eq(r.facts.get("tier"), "高价值") // 高优先级先执行，低优先级被 seen 拦截
  assert_eq(r.ordered[0].id, "r2")         // 执行顺序：高优先在前
}

///|
test "缺失字段按空串处理" {
  let f = Fact::new()
  let e = RuleEngine::new([Rule::new("r1", "empty", "name==张三", "flag=1", 1, "name 缺失")])
  let r = e.execute(f)
  assert_eq(r.matched.length(), 0)
  assert_eq(f.get("name"), "")
}
