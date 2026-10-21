///|
/// 从 JSON 文本加载规则集（规则即数据：规则集可从配置文件注入，无需改代码）。
///
/// 格式约定：
///   {
///     "rules": [
///       {
///         "id": "risk_hold",
///         "label": "跨事实风控",
///         "condition": "order.amount>100000 && customer.is_new==true && order.customer_id==customer.id",
///         "action": "action=manual_review & order.status=hold",
///         "priority": 10,
///         "note": "跨事实强制人工"
///       }
///     ]
///   }
///
/// 字段说明：
///   - id / label / condition / action 为必填字符串（id 与 condition 不可为空）；
///   - priority 为可选整数（缺省 0），note 为可选字符串（缺省 ""）；
///   - condition 使用与 ReteRule::new 相同的条件 DSL（AND/OR/NOT/跨事实引用）。
///
/// 错误处理：返回 Err 并带定位信息（第 N 条规则 + 原因），不静默跳过。
pub fn parse_rules_json(json_str : String) -> Result[Array[ReteRule], String] {
  let parsed = @json.parse(json_str) catch {
    (_ : @json.ParseError) => return Err("JSON 解析失败：不是合法 JSON")
  }
  guard parsed is Object(root) else {
    return Err("JSON 根节点必须是对象 {\"rules\": [...]}")
  }
  let rules_json = root.get("rules")
  guard rules_json is Some(Array(rules)) else {
    return Err("缺少 rules 数组字段")
  }
  let out : Array[ReteRule] = []
  let mut i = 0
  while i < rules.length() {
    let item = rules[i]
    guard item is Object(obj) else {
      return Err("第 " + (i + 1).to_string() + " 条规则必须是对象")
    }
    let r = match rule_from_obj(obj, i) {
      Ok(r) => r
      Err(e) => return Err(e)
    }
    out.push(r)
    i = i + 1
  }
  Ok(out)
}

/// 单条规则对象 → ReteRule（含必填/非空校验）
fn rule_from_obj(obj : Map[String, Json], idx : Int) -> Result[ReteRule, String] {
  let n = idx + 1
  let id = match obj.get("id") {
    Some(String(s)) => s
    Some(_) => return Err("第 " + n.to_string() + " 条规则的 id 必须是字符串")
    None => return Err("第 " + n.to_string() + " 条规则缺少 id")
  }
  if id.trim() == "" {
    return Err("第 " + n.to_string() + " 条规则的 id 不能为空")
  }
  let label = match obj.get("label") {
    Some(String(s)) => s
    _ => ""
  }
  let condition = match obj.get("condition") {
    Some(String(s)) => s
    Some(_) => return Err("第 " + n.to_string() + " 条规则的 condition 必须是字符串")
    None => return Err("第 " + n.to_string() + " 条规则缺少 condition")
  }
  if condition.trim() == "" {
    return Err("第 " + n.to_string() + " 条规则的 condition 不能为空")
  }
  let action = match obj.get("action") {
    Some(String(s)) => s
    Some(_) => return Err("第 " + n.to_string() + " 条规则的 action 必须是字符串")
    None => return Err("第 " + n.to_string() + " 条规则缺少 action")
  }
  let priority = match obj.get("priority") {
    Some(Number(v, ..)) => v.to_int()
    Some(_) => return Err("第 " + n.to_string() + " 条规则的 priority 必须是整数")
    None => 0
  }
  let note = match obj.get("note") {
    Some(String(s)) => s
    _ => ""
  }
  Ok(ReteRule::new(id, label, condition, action, priority, note))
}
