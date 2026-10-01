///|
/// Rete 产生式规则引擎核心（MoonBit）。
///
/// 与 lib/engine（线性匹配模式）互补：本模块面向「多事实工作内存 + 跨事实关联 +
/// 增量传播」的产生式推理场景，算法参考 Rete（Forgy 1974）。
///
/// 核心概念：
/// - WorkingMemory：有状态事实集合（insert / update / retract）
/// - 网络编译：规则条件 → alpha（单条件测试，跨规则共享）/ beta（跨事实 join）/ terminal 节点
/// - 增量传播：事实增删改只沿网络重算受影响分支（left/right activation），不做全量重匹配
/// - 冲突消解：salience（规则优先级）→ specificity（条件数）→ recency（事实新近度）→ rule id
/// - match-select-act 循环：触发动作 → 修改事实 → 连锁激活（fire limit 上限）
///
/// 条件 DSL：
///   多条原子条件用 && 连接（与），多组用 || 连接（或，任一组全部满足即匹配）
///   pattern.field==value     等于（value 为字面量）
///   pattern.field!=value     不等于
///   pattern.field~=value     包含子串
///   pattern.field>n         数字大于（严格整数）
///   pattern.field<n / >= / <=
///   patternA.fieldA==patternB.fieldB   跨事实变量绑定 join
///   !pattern.field==value    否定：工作内存中不存在满足该条件的事实
///   示例：(customer.vip==true && ticket.priority==high) || order.amount>100000
///
/// 语义约定：
///   - || 组之间是"或"，任一组内全部原子条件满足即规则匹配；
///   - OR 必须位于顶层（整条条件 = 若干 OR 组，组可用括号包裹）；
///     不支持 OR 内嵌于 AND 中（如 a && (b || c)）与括号嵌套；
///   - ! 否定扫描工作内存全集（非网络 token），且须与至少一个正条件搭配；
///   - 暂不支持跨事实引用的否定（neg 仅用于字面量/类型条件）。
///
/// 动作 DSL（多条用 & 连接）：
///   pattern.field=value      修改/插入事实字段（触发增量传播）
///   pattern.field+=value     追加标签
///   action=xxx               记录触发结果（进入 trace）
///
/// 示例：
///   ReteRule::new("risk", "大额新客风控",
///     "order.amount>100000 && customer.is_new==true && order.customer_id==customer.id",
///     "action=manual_review", 10, "跨事实强制人工")
///
/// 规则即数据：引擎不绑定任何业务语义。

// ============================== 事实与工作内存 ==============================

/// 事实：带类型标记与全局序号的键值映射
pub struct Fact {
  mut id : Int
  kind : String
  map : Map[String, String]
}

/// 创建事实（id 由 WorkingMemory 分配）
pub fn Fact::make(kind : String) -> Fact {
  { id: 0, kind: kind, map: Map([]) }
}

/// 设置字段
pub fn Fact::set(self : Fact, key : String, value : String) -> Unit {
  self.map[key] = value
}

/// 读取字段；缺失返回空串
pub fn Fact::get(self : Fact, key : String) -> String {
  match self.map.get(key) {
    Some(v) => v
    None => ""
  }
}

/// 追加标签
pub fn Fact::append(self : Fact, key : String, value : String) -> Unit {
  let old = self.get(key)
  if old == "" {
    self.map[key] = value
  } else {
    self.map[key] = old + "," + value
  }
}

/// 工作内存：有状态事实集合
pub struct WorkingMemory {
  facts : Map[Int, Fact]
  mut next_id : Int
}

/// 创建空工作内存
pub fn WorkingMemory::new() -> WorkingMemory {
  { facts: Map([]), next_id: 1 }
}

/// 插入事实（分配 id），返回事实 id
pub fn WorkingMemory::insert(self : WorkingMemory, f : Fact) -> Int {
  let id = self.next_id
  let g = f
  g.id = id
  self.facts[id] = g
  self.next_id = id + 1
  id
}

/// 取事实；不存在返回 None
pub fn WorkingMemory::get(self : WorkingMemory, id : Int) -> Fact? {
  self.facts.get(id)
}

/// 移除事实
pub fn WorkingMemory::retract(self : WorkingMemory, id : Int) -> Unit {
  self.facts.remove(id)
}

/// 当前事实数
pub fn WorkingMemory::size(self : WorkingMemory) -> Int {
  self.facts.length()
}

/// 快照（按 id 升序）
pub fn WorkingMemory::snapshot(self : WorkingMemory) -> Array[Fact] {
  let out : Array[Fact] = []
  let ids : Array[Int] = []
  for (id, _) in self.facts {
    ids.push(id)
  }
  ids.sort()
  for id in ids {
    match self.facts.get(id) {
      Some(f) => out.push(f)
      None => ()
    }
  }
  out
}

// ============================== 规则 ==============================

/// 原子条件（pattern 类型上的单字段测试或跨事实引用）
pub struct Pattern {
  name : String        // 事实类型名，如 order / customer
  field : String       // 字段名
  op : String          // == != ~= > < >= <=
  value : String       // 字面量（引用时为 ""）
  ref_type : String    // 跨事实引用：被引用事实类型（非引用时为 ""）
  ref_field : String   // 跨事实引用：被引用字段名
  neg : Bool           // 否定条件（! 前缀）：工作内存中不存在满足该条件的事实
}

/// 产生式规则
pub struct ReteRule {
  id : String
  label : String
  patterns : Array[Pattern]        // 展平原子条件（网络编译 + specificity 计数）
  groups : Array[Array[Pattern]]   // OR 组：任一组内全部原子条件满足即规则匹配
  action : String
  priority : Int   // salience
  note : String
}

/// 创建规则（解析条件 DSL）
pub fn ReteRule::new(
  id : String,
  label : String,
  condition : String,
  action : String,
  priority : Int,
  note : String,
) -> ReteRule {
  let (groups, flat) = parse_condition(condition)
  {
    id,
    label,
    patterns: flat,
    groups,
    action,
    priority,
    note,
  }
}

/// 条件字符串 → (OR 组数组, 展平原子条件数组)
/// 语义：先按 || 拆组（或），组内按 && 拆（与）；组可用括号包裹，解析时剥离。
/// 限制：OR 必须位于顶层（整条条件 = 若干 OR 组），不支持 OR 内嵌于 AND 中。
fn parse_condition(cond : String) -> (Array[Array[Pattern]], Array[Pattern]) {
  let groups : Array[Array[Pattern]] = []
  let flat : Array[Pattern] = []
  for grp in cond.split("||") {
    let mut gs = grp.trim().to_owned()
    // 剥离包裹整个 OR 组的一对括号：(a==1 && b==2) → a==1 && b==2
    if gs.length() >= 2 && gs[0] == '(' && gs[gs.length() - 1] == ')' {
      gs = gs[1:gs.length() - 1].to_owned()
    }
    let g : Array[Pattern] = []
    for part in gs.split("&&") {
      let mut ps = part.trim().to_owned()
      // 原子级括号剥离（防御性，通常无）
      if ps.length() >= 2 && ps[0] == '(' && ps[ps.length() - 1] == ')' {
        ps = ps[1:ps.length() - 1].to_owned()
      }
      let pp = parse_pattern(ps)
      g.push(pp)
      flat.push(pp)
    }
    groups.push(g)
  }
  (groups, flat)
}

/// 解析单个原子条件：pattern.field op value；支持 ! 前缀（否定）
fn parse_pattern(raw : String) -> Pattern {
  let mut neg = false
  let mut src = raw
  if raw.length() > 0 && raw[0] == '!' {
    neg = true
    src = raw[1:].to_owned()
  }
  let mut name = ""
  let mut rest = src
  let dot = first_index_of(src, '.')
  if dot >= 0 {
    name = src[:dot].to_owned()
    rest = src[dot + 1:].to_owned()
  }
  let ops : Array[String] = [">=", "<=", "==", "!=", "~=", ">", "<"]
  let mut field = ""
  let mut op = ""
  let mut value = ""
  for o in ops {
    let parts = split_exact(rest, o)
    if parts is Some((f, v)) {
      field = f
      op = o
      value = v
      break
    }
  }
  let mut ref_type = ""
  let mut ref_field = ""
  if is_reference(value) {
    let d = first_index_of(value, '.')
    if d >= 0 {
      ref_type = value[:d].to_owned()
      ref_field = value[d + 1:].to_owned()
      value = ""
    }
  }
  { name, field, op, value, ref_type, ref_field, neg }
}

/// 找到字符串中 target 字符的首次位置；不存在返回 -1
fn first_index_of(s : String, target : Char) -> Int {
  let mut i = 0
  for ch in s {
    if ch == target {
      return i
    }
    i = i + 1
  }
  -1
}

/// 按分隔符切分并返回二元组；分隔符出现次数不等于 1 时返回 None
fn split_exact(s : String, sep : String) -> (String, String)? {
  let parts : Array[String] = []
  for p in s.split(sep) {
    parts.push(p.trim().to_owned())
  }
  if parts.length() != 2 {
    return None
  }
  Some((parts[0], parts[1]))
}

/// 判断值是否为跨事实引用（形如 other.field）
fn is_reference(v : String) -> Bool {
  if v == "" {
    return false
  }
  if v == "true" || v == "false" {
    return false
  }
  let mut pure_num = v.length() > 0
  let mut first = true
  for ch in v {
    if ch == '-' && first {
      first = false
      continue
    }
    if !(ch >= '0' && ch <= '9') {
      pure_num = false
      break
    }
    first = false
  }
  if pure_num {
    return false
  }
  first_index_of(v, '.') >= 0
}

// ============================== 网络节点 ==============================

/// 节点引用
enum NodeRef {
  Alpha(Int)
  Beta(Int)
  Terminal(Int)
}

/// alpha 节点：单事实原子条件测试（跨规则共享）
struct AlphaNode {
  pat : Pattern
  mem : Array[Int]          // 通过测试的事实 id
  down : Array[AlphaDown]   // 订阅此节点的 beta（left 或 right 输入）
  down_terms : Array[Int]   // 单条件规则直连的 terminal
}

/// alpha → beta 的下行引用（记录角色）
struct AlphaDown {
  b : Int
  as_left : Bool
}

/// beta 节点：left（alpha/beta 部分匹配）× right（alpha）join
struct BetaNode {
  right : NodeRef
  mem : Array[Token]        // 左侧部分匹配 token（持久化，供右侧事实 join）
  down_betas : Array[Int]
  down_terms : Array[Int]
}

/// 部分匹配 token：一条规则链上的事实组合
struct Token {
  facts : Array[Int]
}

/// terminal 节点：规则完整匹配
struct TerminalNode {
  rule : ReteRule
  agenda : Array[Token]
}

/// 传播消息
enum Msg {
  LeftToken(Token)   // 左侧新 token（部分匹配）
  RightFact(Int)     // 右侧新事实 id
}

/// Rete 引擎（编译后的网络）
pub struct ReteEngine {
  alphas : Array[AlphaNode]
  betas : Array[BetaNode]
  terminals : Array[TerminalNode]
}

// ============================== 网络编译 ==============================

/// 创建引擎并编译网络
pub fn ReteEngine::new(rules : Array[ReteRule]) -> ReteEngine {
  let alphas : Array[AlphaNode] = []
  let betas : Array[BetaNode] = []
  let terminals : Array[TerminalNode] = []

  for r in rules {
    // 先建好 terminal，规则的所有 OR 组链汇聚到同一个 terminal
    terminals.push({ rule: r, agenda: [] })
    let t_idx = terminals.length() - 1
    for g in r.groups {
      // 每组独立建一条 alpha/beta 链（OR 语义下各组互不依赖；
      // alpha 节点仍跨组跨规则共享）
      let alpha_seq : Array[Pattern] = []
      for p in g {
        // 否定条件不建网络节点：terminal 判定时扫描工作内存全集
        // （工作内存中不存在满足条件的事实 → 满足）
        if p.neg {
          continue
        }
        if p.ref_type != "" {
          // 跨事实引用：own 侧 + ref 侧各一个 type-only alpha 参与 join，
          // 完整绑定在 terminal 校验
          alpha_seq.push(type_only(p.name))
          alpha_seq.push(type_only(p.ref_type))
        } else {
          alpha_seq.push(p)
        }
      }
      if alpha_seq.length() == 0 {
        // 全否定组：无网络入口，该组永不触发（neg 语义需配合正条件使用）
        continue
      }
      let alpha_idx : Array[Int] = []
      for p in alpha_seq {
        alpha_idx.push(find_or_create_alpha(alphas, p))
      }
      let n = alpha_seq.length()
      // 串 beta 链（n-1 个 beta）
      let mut pos = 1
      while pos < n {
        let right_ref : NodeRef = NodeRef::Alpha(alpha_idx[pos])
        betas.push({ right: right_ref, mem: [], down_betas: [], down_terms: [] })
        pos = pos + 1
      }
      // 建 downlinks（组链 → 本规则的 terminal）
      link_chain(alphas, betas, alpha_idx, t_idx)
    }
  }

  { alphas, betas, terminals }
}

/// 仅按类型匹配的原子条件（@kind 特殊字段）
fn type_only(t : String) -> Pattern {
  { name: t, field: "@kind", op: "==", value: t, ref_type: "", ref_field: "", neg: false }
}

/// alpha 节点数量（用于验证共享子条件合并）
pub fn ReteEngine::alpha_count(self : ReteEngine) -> Int {
  self.alphas.length()
}

/// beta 节点数量
pub fn ReteEngine::beta_count(self : ReteEngine) -> Int {
  self.betas.length()
}

/// terminal 节点数量
pub fn ReteEngine::terminal_count(self : ReteEngine) -> Int {
  self.terminals.length()
}

/// 为一条规则建立 downlinks（alpha → beta，beta → 下游 beta / terminal）
fn link_chain(
  alphas : Array[AlphaNode],
  betas : Array[BetaNode],
  alpha_idx : Array[Int],
  t_idx : Int,
) -> Unit {
  let n = alpha_idx.length()
  if n == 1 {
    // 单条件规则：alpha 直连 terminal
    alphas[alpha_idx[0]].down_terms.push(t_idx)
    return
  }
  let beta_start = betas.length() - (n - 1)
  // 链首 alpha → beta0（as_left）
  alphas[alpha_idx[0]].down.push({ b: beta_start, as_left: true })
  // 右侧 alpha → beta_{j-1}（as_right）
  let mut j = 1
  while j < n {
    alphas[alpha_idx[j]].down.push({ b: beta_start + j - 1, as_left: false })
    j = j + 1
  }
  // beta 下游：beta_i → beta_{i+1} / terminal
  let mut i = 0
  while i < n - 1 {
    if i == n - 2 {
      betas[beta_start + i].down_terms.push(t_idx)
    } else {
      betas[beta_start + i].down_betas.push(beta_start + i + 1)
    }
    i = i + 1
  }
}

/// 查找 alpha 节点
fn find_alpha(alphas : Array[AlphaNode], p : Pattern) -> Int {
  let mut i = 0
  while i < alphas.length() {
    let a = alphas[i]
    if a.pat.name == p.name && a.pat.field == p.field && a.pat.op == p.op &&
      a.pat.value == p.value {
      return i
    }
    i = i + 1
  }
  -1
}

/// 查找或创建共享 alpha 节点
fn find_or_create_alpha(alphas : Array[AlphaNode], p : Pattern) -> Int {
  let existing = find_alpha(alphas, p)
  if existing >= 0 {
    return existing
  }
  alphas.push({ pat: p, mem: [], down: [], down_terms: [] })
  alphas.length() - 1
}

// ============================== 条件求值 ==============================

/// 单事实条件求值（alpha 测试）
fn alpha_match(pat : Pattern, f : Fact) -> Bool {
  // 类型测试：@kind 特殊字段匹配事实类型标记
  if pat.field == "@kind" && pat.op == "==" {
    return f.kind == pat.value
  }
  // 前置类型检查：事实类型必须与条件 pattern 名一致
  if f.kind != pat.name {
    return false
  }
  let v = f.get(pat.field)
  match pat.op {
    "==" => v == pat.value
    "!=" => v != pat.value && v != ""
    "~=" => v.contains(pat.value)
    ">" => compare_num(v, pat.value, true, false)
    "<" => compare_num(v, pat.value, false, false)
    ">=" => compare_num(v, pat.value, true, true)
    "<=" => compare_num(v, pat.value, false, true)
    _ => false
  }
}

/// 严格整数比较：缺失/非数字不匹配
fn compare_num(l : String, r : String, gt : Bool, eq : Bool) -> Bool {
  let (lv, lok) = parse_int_safe(l)
  let (rv, rok) = parse_int_safe(r)
  if !lok || !rok {
    return false
  }
  if gt {
    if lv > rv {
      return true
    }
    return eq && lv == rv
  } else {
    if lv < rv {
      return true
    }
    return eq && lv == rv
  }
}

/// 严格整数解析（整个字符串必须是可选负号 + 至少一位数字）
fn parse_int_safe(s : String) -> (Int, Bool) {
  let mut n = 0
  let mut neg = false
  let mut started = false
  let mut has_digit = false
  for ch in s {
    if ch == '-' && !started {
      neg = true
      started = true
      continue
    }
    let d = match ch {
      '0' => 0
      '1' => 1
      '2' => 2
      '3' => 3
      '4' => 4
      '5' => 5
      '6' => 6
      '7' => 7
      '8' => 8
      '9' => 9
      _ => -1
    }
    if d >= 0 {
      n = n * 10 + d
      started = true
      has_digit = true
    } else {
      return (0, false)
    }
  }
  if !has_digit {
    return (0, false)
  }
  if neg { (-n, true) } else { (n, true) }
}

// ============================== 增量传播 ==============================

/// 插入事实并沿网络增量传播
pub fn ReteEngine::insert(self : ReteEngine, wm : WorkingMemory, f : Fact) -> Unit {
  let id = wm.insert(f)
  let mut i = 0
  while i < self.alphas.length() {
    if alpha_match(self.alphas[i].pat, f) {
      self.alphas[i].mem.push(id)
      // 单条件规则直连 terminal
      for t in self.alphas[i].down_terms {
        self.terminals[t].agenda.push({ facts: [id] })
      }
      // beta 订阅
      for d in self.alphas[i].down {
        if d.as_left {
          propagate(self, wm, NodeRef::Beta(d.b), Msg::LeftToken({ facts: [id] }))
        } else {
          propagate(self, wm, NodeRef::Beta(d.b), Msg::RightFact(id))
        }
      }
    }
    i = i + 1
  }
}

/// 从网络中移除事实（清理 alpha 内存 / beta token / terminal agenda 中的残留引用）
pub fn ReteEngine::remove(self : ReteEngine, fid : Int) -> Unit {
  let mut i = 0
  while i < self.alphas.length() {
    remove_int(self.alphas[i].mem, fid)
    i = i + 1
  }
  let mut j = 0
  while j < self.betas.length() {
    remove_token(self.betas[j].mem, fid)
    j = j + 1
  }
  let mut k = 0
  while k < self.terminals.length() {
    remove_token(self.terminals[k].agenda, fid)
    k = k + 1
  }
}

/// 从 Int 数组中移除指定值
fn remove_int(arr : Array[Int], v : Int) -> Unit {
  let kept : Array[Int] = []
  for x in arr {
    if x != v {
      kept.push(x)
    }
  }
  arr.clear()
  for x in kept {
    arr.push(x)
  }
}

/// token 是否包含指定事实
fn fact_in_token(tok : Token, fid : Int) -> Bool {
  for x in tok.facts {
    if x == fid {
      return true
    }
  }
  false
}

/// 从 Token 数组中移除包含指定事实的 token
fn remove_token(arr : Array[Token], fid : Int) -> Unit {
  let kept : Array[Token] = []
  for tok in arr {
    if !fact_in_token(tok, fid) {
      kept.push(tok)
    }
  }
  arr.clear()
  for tok in kept {
    arr.push(tok)
  }
}

/// 向节点传播消息
fn propagate(eng : ReteEngine, wm : WorkingMemory, node : NodeRef, msg : Msg) -> Unit {
  match node {
    NodeRef::Alpha(_) => ()
    NodeRef::Beta(b_idx) => propagate_beta(eng, wm, b_idx, msg)
    NodeRef::Terminal(t_idx) => {
      match msg {
        Msg::LeftToken(tok) => eng.terminals[t_idx].agenda.push(tok)
        Msg::RightFact(_) => ()
      }
    }
  }
}

/// beta 节点接收消息（join 并向下游传播）
fn propagate_beta(eng : ReteEngine, wm : WorkingMemory, b_idx : Int, msg : Msg) -> Unit {
  let beta = eng.betas[b_idx]
  let new_tokens : Array[Token] = []
  match msg {
    // 右侧新事实 × 左侧内存全部 token
    Msg::RightFact(fid) => {
      for tok in beta.mem {
        let ft = tok.facts.copy()
        ft.push(fid)
        new_tokens.push({ facts: ft })
      }
    }
    // 左侧新 token：先持久化到内存，再与右侧 alpha 全部事实 join
    Msg::LeftToken(tok) => {
      beta.mem.push(tok)
      let right_alpha = match beta.right {
        NodeRef::Alpha(a) => a
        _ => -1
      }
      if right_alpha >= 0 {
        for fid in eng.alphas[right_alpha].mem {
          let ft = tok.facts.copy()
          ft.push(fid)
          new_tokens.push({ facts: ft })
        }
      }
    }
  }
  for t in new_tokens {
    for db in beta.down_betas {
      propagate(eng, wm, NodeRef::Beta(db), Msg::LeftToken(t))
    }
    for dt in beta.down_terms {
      propagate(eng, wm, NodeRef::Terminal(dt), Msg::LeftToken(t))
    }
  }
}

/// 跨事实引用单条件匹配：token 中 own 类型事实字段 == ref 类型事实字段
/// （pattern 引用条件形如：order.customer_id==customer.id，
///   其中 name/field 为 own 侧，ref_type/ref_field 为被引用侧）
fn cross_ref_match(c : Pattern, tok : Token, wm : WorkingMemory) -> Bool {
  let mut found_own : Fact? = None
  let mut found_ref : Fact? = None
  for fid in tok.facts {
    match wm.get(fid) {
      Some(f) => {
        if f.kind == c.name {
          found_own = Some(f)
        }
        if f.kind == c.ref_type {
          found_ref = Some(f)
        }
      }
      None => ()
    }
  }
  let own = match found_own {
    Some(f) => f
    None => return false
  }
  let ref_ = match found_ref {
    Some(f) => f
    None => return false
  }
  // 按操作符语义比较（数值条件走严格整数比较）
  match c.op {
    "==" => own.get(c.field) == ref_.get(c.ref_field)
    "!=" => own.get(c.field) != ref_.get(c.ref_field)
    "~=" => own.get(c.field).contains(ref_.get(c.ref_field))
    ">" => compare_num(own.get(c.field), ref_.get(c.ref_field), true, false)
    "<" => compare_num(own.get(c.field), ref_.get(c.ref_field), false, false)
    ">=" => compare_num(own.get(c.field), ref_.get(c.ref_field), true, true)
    "<=" => compare_num(own.get(c.field), ref_.get(c.ref_field), false, true)
    _ => false
  }
}

/// 单原子条件匹配（字面量 / 类型 / 跨事实引用），支持 neg 取反。
/// 否定语义：工作内存中不存在满足该原子条件的事实 → 满足。
/// 否定条件不建网络节点，判定时直接扫描工作内存全集（非 token）。
fn atom_match(p : Pattern, tok : Token, wm : WorkingMemory) -> Bool {
  if p.neg {
    let mut found = false
    for (_, f) in wm.facts {
      if f.kind == p.name && alpha_match(p, f) {
        found = true
        break
      }
    }
    return !found
  }
  if p.ref_type != "" {
    return cross_ref_match(p, tok, wm)
  }
  // 正字面量/类型条件：token 中存在满足 alpha_match 的事实
  let mut found = false
  for fid in tok.facts {
    match wm.get(fid) {
      Some(f) => {
        if alpha_match(p, f) {
          found = true
          break
        }
      }
      None => ()
    }
  }
  found
}

/// AND 组匹配：组内全部原子条件满足
fn group_match(g : Array[Pattern], tok : Token, wm : WorkingMemory) -> Bool {
  for p in g {
    if !atom_match(p, tok, wm) {
      return false
    }
  }
  true
}

/// 规则条件整体判定（OR 语义）：任一组成立即满足。
/// 网络层只负责把可能相关的事实组合传播到 terminal，
/// 最终是否命中在此处确定性判定（含 neg、跨事实引用）。
fn rule_condition_holds(rule : ReteRule, tok : Token, wm : WorkingMemory) -> Bool {
  for g in rule.groups {
    if group_match(g, tok, wm) {
      return true
    }
  }
  false
}

// ============================== 冲突消解与执行 ==============================

/// 待触发激活
struct Activation {
  t_idx : Int
  rule : ReteRule
  token : Token
  recency : Int
}

/// 执行结果
pub struct FireResult {
  fired : Array[String]
  trace : Array[String]
  facts : Array[Fact]
}

/// 冲突消解排序（确定性）：
/// salience（priority 大者先）→ specificity（条件数多者先）→ recency（新者先）→ rule id 字典序
fn resolve_conflict(a : Activation, b : Activation) -> Int {
  if a.rule.priority != b.rule.priority {
    return b.rule.priority - a.rule.priority
  }
  if a.rule.patterns.length() != b.rule.patterns.length() {
    return b.rule.patterns.length() - a.rule.patterns.length()
  }
  if a.recency != b.recency {
    return b.recency - a.recency
  }
  if a.rule.id < b.rule.id {
    return -1
  }
  if a.rule.id > b.rule.id {
    return 1
  }
  0
}

/// 收集当前全部激活（agenda 合并 + 确定性排序）
fn collect_activations(eng : ReteEngine, wm : WorkingMemory) -> Array[Activation] {
  let out : Array[Activation] = []
  let mut t = 0
  while t < eng.terminals.length() {
    let term = eng.terminals[t]
    for tok in term.agenda {
      // 规则条件整体判定（OR 组语义，含 neg 与跨事实引用）：
      // 不满足条件的 token 不进入激活
      if !rule_condition_holds(term.rule, tok, wm) {
        continue
      }
      let mut max_rec = 0
      for id in tok.facts {
        if id > max_rec {
          max_rec = id
        }
      }
      out.push({ t_idx: t, rule: term.rule, token: tok, recency: max_rec })
    }
    t = t + 1
  }
  out.sort_by(resolve_conflict)
  out
}

/// 执行 match-select-act 循环
pub fn ReteEngine::fire_all(self : ReteEngine, wm : WorkingMemory, limit? : Int) -> FireResult {
  let max_fire = match limit {
    Some(n) => n
    None => 100
  }
  let fired : Array[String] = []
  let trace : Array[String] = []
  let mut count = 0
  while count < max_fire {
    let acts = collect_activations(self, wm)
    if acts.length() == 0 {
      break
    }
    let act = acts[0]
    fired.push(act.rule.id)
    // 清空该规则 agenda（避免同 token 无限重复触发）
    self.terminals[act.t_idx].agenda.clear()
    // 执行动作：修改事实 → retract + insert → 增量传播 → 新激活
    apply_actions(self, wm, act)
    trace.push(
      "rule=" + act.rule.id + " facts=[" + join_ids(act.token.facts) + "] action=" +
      act.rule.action,
    )
    count = count + 1
  }
  { fired, trace, facts: wm.snapshot() }
}

/// 执行动作：解析 action DSL 并修改事实（多动作原子应用，最后统一重插一次）
/// 幂等保护：字段值未变化（或标签已存在）的动作跳过重插，
/// 避免"事实重插 → 重新激活 → 再执行相同动作"的无限循环。
fn apply_actions(eng : ReteEngine, wm : WorkingMemory, act : Activation) -> Unit {
  let changed_facts : Array[Int] = []
  let changed_objs : Array[Fact] = []
  for part in act.rule.action.split("&") {
    let a = part.trim().to_owned()
    if a == "" {
      continue
    }
    if a.length() >= 7 && a[:7].to_owned() == "action=" {
      continue
    }
    let dot = first_index_of(a, '.')
    if dot < 0 {
      continue
    }
    let target_type = a[:dot].to_owned()
    let rest = a[dot + 1:].to_owned()
    let mut target_field = ""
    let mut op = "="
    let mut value = ""
    // 先试 += 与 -=（避免 = 误切），再试 =
    let add = split_exact(rest, "+=")
    if add is Some((f, v)) {
      op = "+="
      target_field = f
      value = v
    } else {
      let sub = split_exact(rest, "-=")
      if sub is Some((f, v)) {
        op = "-="
        target_field = f
        value = v
      } else {
        let eq = split_exact(rest, "=")
        if eq is Some((f, v)) {
          op = "="
          target_field = f
          value = v
        } else {
          continue
        }
      }
    }
    // 值解析：支持跨事实引用（形如 other.field，从 token 中取）
    let resolved = resolve_value(wm, act.token, value)
    // 独立目标：每个动作按其事实类型在 token 中查找（可修改多个不同类型事实）
    let mut target : Fact? = None
    let mut tid = -1
    for fid in act.token.facts {
      match wm.get(fid) {
        Some(f) => {
          if f.kind == target_type {
            target = Some(f)
            tid = fid
            break
          }
        }
        None => ()
      }
    }
    match target {
      Some(f) => {
        let mut did_change = false
        if op == "+=" {
          // 标签去重：已包含则不追加（幂等）
          let cur = f.get(target_field)
          let mut has = false
          for t in cur.split(",") {
            if t.trim().to_owned() == resolved {
              has = true
            }
          }
          if !has {
            f.append(target_field, resolved)
            did_change = true
          }
        } else if op == "-=" {
          let (cur, cok) = parse_int_safe(f.get(target_field))
          let (subv, sok) = parse_int_safe(resolved)
          if cok && sok {
            let newv = cur - subv
            if newv != cur {
              f.set(target_field, newv.to_string())
              did_change = true
            }
          }
        } else {
          let before = f.get(target_field)
          f.set(target_field, resolved)
          if f.get(target_field) != before {
            did_change = true
          }
        }
        if did_change {
          let mut known = false
          for x in changed_facts {
            if x == tid {
              known = true
            }
          }
          if !known {
            changed_facts.push(tid)
            changed_objs.push(f)
          }
        }
      }
      None => ()
    }
  }
  // 统一重插：每个变化事实清理网络残留 → 撤出工作内存 → 重新插入（增量传播）
  let mut i = 0
  while i < changed_facts.length() {
    let tid = changed_facts[i]
    let f = changed_objs[i]
    eng.remove(tid)
    wm.retract(tid)
    eng.insert(wm, f)
    i = i + 1
  }
}

/// 解析动作值：跨事实引用（形如 other.field）时从 token 中取对应事实字段值；
/// 否则原样返回字面量
fn resolve_value(wm : WorkingMemory, tok : Token, value : String) -> String {
  if !is_reference(value) {
    return value
  }
  let d = first_index_of(value, '.')
  if d < 0 {
    return value
  }
  let ref_type = value[:d].to_owned()
  let ref_field = value[d + 1:].to_owned()
  for fid in tok.facts {
    match wm.get(fid) {
      Some(f) => {
        if f.kind == ref_type {
          return f.get(ref_field)
        }
      }
      None => ()
    }
  }
  ""
}

/// token 事实 id 列表转字符串
fn join_ids(ids : Array[Int]) -> String {
  let mut s = ""
  let mut i = 0
  while i < ids.length() {
    if i > 0 {
      s = s + ","
    }
    s = s + ids[i].to_string()
    i = i + 1
  }
  s
}
