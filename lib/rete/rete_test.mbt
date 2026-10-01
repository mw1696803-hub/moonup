///|
/// Rete 引擎单元测试。

test "single-condition rule fires" {
  let rules = [
    ReteRule::new("r1", "VIP退款", "ticket.type==refund", "action=route_vip", 10, "退款路由"),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let t = Fact::make("ticket")
  t.set("type", "refund")
  engine.insert(wm, t)
  let r = engine.fire_all(wm)
  assert_eq(r.fired.length(), 1)
  assert_eq(r.fired[0], "r1")
}

test "single-condition non-match does not fire" {
  let rules = [
    ReteRule::new("r1", "VIP退款", "ticket.type==refund", "action=route_vip", 10, ""),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let t = Fact::make("ticket")
  t.set("type", "complaint")
  engine.insert(wm, t)
  let r = engine.fire_all(wm)
  assert_eq(r.fired.length(), 0)
}

test "cross-fact join with variable binding" {
  let rules = [
    ReteRule::new(
      "risk",
      "大额新客风控",
      "order.amount>100000 && customer.is_new==true && order.customer_id==customer.id",
      "action=manual_review",
      10,
      "跨事实强制人工",
    ),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let c = Fact::make("customer")
  c.set("id", "1001")
  c.set("is_new", "true")
  engine.insert(wm, c)
  // 未关联订单：金额大但 customer_id 不匹配 → 不触发
  let o1 = Fact::make("order")
  o1.set("amount", "150000")
  o1.set("customer_id", "9999")
  engine.insert(wm, o1)
  let r1 = engine.fire_all(wm)
  assert_eq(r1.fired.length(), 0)
  // 关联订单：customer_id 匹配 → 触发
  let o2 = Fact::make("order")
  o2.set("amount", "150000")
  o2.set("customer_id", "1001")
  engine.insert(wm, o2)
  let r2 = engine.fire_all(wm)
  assert_eq(r2.fired.length(), 1)
  assert_eq(r2.fired[0], "risk")
}

test "shared alpha node: two rules share one condition" {
  let rules = [
    ReteRule::new("r1", "VIP紧急", "customer.level==VIP && ticket.urgency==high", "route=vip_queue", 8, ""),
    ReteRule::new("r2", "VIP退款", "customer.level==VIP && ticket.type==refund", "route=refund_queue", 5, ""),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let c = Fact::make("customer")
  c.set("level", "VIP")
  engine.insert(wm, c)
  let t = Fact::make("ticket")
  t.set("urgency", "high")
  t.set("type", "refund")
  engine.insert(wm, t)
  let r = engine.fire_all(wm)
  // VIP 紧急 + VIP 退款同时命中
  assert_eq(r.fired.length(), 2)
  assert_eq(r.fired[0], "r1")
  assert_eq(r.fired[1], "r2")
  // 网络共享：customer.level==VIP 只应有一个 alpha 节点
  // 3 个条件若共享（level==VIP 复用于两条规则）则 alpha 数 = 3；无共享则 = 4
  assert_eq(engine.alpha_count(), 3)
}

test "conflict resolution: salience then specificity then recency" {
  let rules = [
    ReteRule::new("low", "低优先级", "f.a==1", "action=low", 1, ""),
    ReteRule::new("high", "高优先级", "f.a==1", "action=high", 9, ""),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let f = Fact::make("f")
  f.set("a", "1")
  engine.insert(wm, f)
  let r = engine.fire_all(wm)
  assert_eq(r.fired[0], "high")
  assert_eq(r.fired[1], "low")
}

test "action modifies fact and triggers chained rule" {
  let rules = [
    ReteRule::new(
      "stock_check",
      "库存检查",
      "stock.level<10 && stock.restock==false",
      "stock.restock=true&action=order_restock",
      6,
      "低于阈值自动补货",
    ),
    ReteRule::new(
      "stock_alert",
      "补货后预警",
      "stock.restock==true && stock.level<10",
      "action=alert_manager",
      4,
      "补货后通知",
    ),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let s = Fact::make("stock")
  s.set("level", "5")
  s.set("restock", "false")
  engine.insert(wm, s)
  let r = engine.fire_all(wm)
  // stock_check 先触发（salience 6 > 4），修改 restock=true，随后 stock_alert 连锁触发
  assert_eq(r.fired.length(), 2)
  assert_eq(r.fired[0], "stock_check")
  assert_eq(r.fired[1], "stock_alert")
}

test "idempotent self-activation stops loop" {
  // 动作不改任何字段值（f.a=1 幂等）：引擎只触发一次即停，不依赖 fire limit 兜底
  let rules = [
    ReteRule::new("loop", "自持触发", "f.a==1", "f.a=1", 1, ""),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let f = Fact::make("f")
  f.set("a", "1")
  engine.insert(wm, f)
  let r = engine.fire_all(wm, limit=5)
  assert_eq(r.fired.length(), 1)
}

test "retract removes fact and its tokens" {
  let rules = [
    ReteRule::new("r1", "VIP退款", "customer.level==VIP && ticket.type==refund", "route=vip_queue", 8, ""),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let c = Fact::make("customer")
  c.set("level", "VIP")
  engine.insert(wm, c)
  let t = Fact::make("ticket")
  t.set("type", "refund")
  engine.insert(wm, t)
  let r1 = engine.fire_all(wm)
  assert_eq(r1.fired.length(), 1)
  // 撤回 ticket 后再次 fire：不再触发
  wm.retract(t.id)
  let r2 = engine.fire_all(wm)
  assert_eq(r2.fired.length(), 0)
}

test "number comparison rejects malformed values" {
  let rules = [
    ReteRule::new("r1", "大额", "order.amount>100000", "action=big", 10, ""),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let o1 = Fact::make("order")
  o1.set("amount", "150000")
  engine.insert(wm, o1)
  let r1 = engine.fire_all(wm)
  assert_eq(r1.fired.length(), 1)
  // 非数字不触发
  let o2 = Fact::make("order")
  o2.set("amount", "abc123")
  engine.insert(wm, o2)
  let r2 = engine.fire_all(wm)
  assert_eq(r2.fired.length(), 0)
  // 负数
  let o3 = Fact::make("order")
  o3.set("amount", "-5")
  engine.insert(wm, o3)
  let r3 = engine.fire_all(wm)
  assert_eq(r3.fired.length(), 0)
}

test "append action accumulates tags" {
  let rules = [
    ReteRule::new("r1", "补标签", "f.a==1", "f.a=2&f.tags+=high", 5, ""),
  ]
  let engine = ReteEngine::new(rules)
  let wm = WorkingMemory::new()
  let f = Fact::make("f")
  f.set("a", "1")
  engine.insert(wm, f)
  let r = engine.fire_all(wm)
  assert_eq(r.fired.length(), 1)
  // 动作修改事实后快照应包含 tags
  let snap = r.facts
  assert_eq(snap.length(), 1)
  assert_eq(snap[0].get("tags"), "high")
}

test "OR groups: fires when either group matches" {
  let rules = [
    ReteRule::new(
      "or_rule",
      "VIP退款或大额订单",
      "(customer.level==VIP && ticket.type==refund) || order.amount>100000",
      "action=manual",
      10,
      "OR 组语义",
    ),
  ]
  let engine = ReteEngine::new(rules)
  // 组 1 命中：VIP + refund（组 2 不成立）
  let wm1 = WorkingMemory::new()
  let c = Fact::make("customer")
  c.set("level", "VIP")
  engine.insert(wm1, c)
  let t = Fact::make("ticket")
  t.set("type", "refund")
  engine.insert(wm1, t)
  let r1 = engine.fire_all(wm1)
  assert_eq(r1.fired.length(), 1)
  // 组 2 命中：大额订单（无 VIP 客户）
  let wm2 = WorkingMemory::new()
  let o = Fact::make("order")
  o.set("amount", "150000")
  engine.insert(wm2, o)
  let r2 = engine.fire_all(wm2)
  assert_eq(r2.fired.length(), 1)
  // 两组都不成立：普通 ticket
  let wm3 = WorkingMemory::new()
  let t2 = Fact::make("ticket")
  t2.set("type", "complaint")
  engine.insert(wm3, t2)
  let o2 = Fact::make("order")
  o2.set("amount", "100")
  engine.insert(wm3, o2)
  let r3 = engine.fire_all(wm3)
  assert_eq(r3.fired.length(), 0)
}

test "OR inside AND chain with cross-fact reference" {
  let rules = [
    ReteRule::new(
      "or_ref",
      "大额或高价值客户下单",
      "(order.status==placed && order.amount>100000 && order.customer_id==customer.id) || (order.status==placed && customer.level==VIP && order.customer_id==customer.id)",
      "action=review",
      10,
      "OR 与跨事实引用组合",
    ),
  ]
  let engine = ReteEngine::new(rules)
  // 大额订单命中 OR 组 2
  let wm = WorkingMemory::new()
  let c = Fact::make("customer")
  c.set("id", "9")
  c.set("level", "NORMAL")
  engine.insert(wm, c)
  let o = Fact::make("order")
  o.set("status", "placed")
  o.set("amount", "200000")
  o.set("customer_id", "9")
  engine.insert(wm, o)
  let r = engine.fire_all(wm)
  assert_eq(r.fired.length(), 1)
}

test "NOT: fires when matching fact absent" {
  let rules = [
    ReteRule::new(
      "not_ok",
      "下单且非黑名单",
      "order.status==placed && !customer.blacklist==true",
      "action=auto_approve",
      10,
      "NOT 语义",
    ),
  ]
  let engine = ReteEngine::new(rules)
  // 无 customer 事实：!customer.blacklist==true 满足
  let wm1 = WorkingMemory::new()
  let o1 = Fact::make("order")
  o1.set("status", "placed")
  engine.insert(wm1, o1)
  let r1 = engine.fire_all(wm1)
  assert_eq(r1.fired.length(), 1)
  // 黑名单客户存在：不满足
  let wm2 = WorkingMemory::new()
  let c2 = Fact::make("customer")
  c2.set("blacklist", "true")
  engine.insert(wm2, c2)
  let o2 = Fact::make("order")
  o2.set("status", "placed")
  engine.insert(wm2, o2)
  let r2 = engine.fire_all(wm2)
  assert_eq(r2.fired.length(), 0)
  // 普通客户（非黑名单）：仍满足
  let wm3 = WorkingMemory::new()
  let c3 = Fact::make("customer")
  c3.set("blacklist", "false")
  engine.insert(wm3, c3)
  let o3 = Fact::make("order")
  o3.set("status", "placed")
  engine.insert(wm3, o3)
  let r3 = engine.fire_all(wm3)
  assert_eq(r3.fired.length(), 1)
}

test "NOT combined with AND: urgent ticket from non-VIP customer" {
  let rules = [
    ReteRule::new(
      "not_and",
      "紧急且非VIP",
      "ticket.urgency==high && !customer.vip==true",
      "action=normal_queue",
      10,
      "NOT + AND",
    ),
  ]
  let engine = ReteEngine::new(rules)
  // 非 VIP 客户 + 紧急工单 → 触发
  let wm1 = WorkingMemory::new()
  let c1 = Fact::make("customer")
  c1.set("vip", "false")
  engine.insert(wm1, c1)
  let t1 = Fact::make("ticket")
  t1.set("urgency", "high")
  engine.insert(wm1, t1)
  let r1 = engine.fire_all(wm1)
  assert_eq(r1.fired.length(), 1)
  // VIP 客户 + 紧急工单 → 不触发
  let wm2 = WorkingMemory::new()
  let c2 = Fact::make("customer")
  c2.set("vip", "true")
  engine.insert(wm2, c2)
  let t2 = Fact::make("ticket")
  t2.set("urgency", "high")
  engine.insert(wm2, t2)
  let r2 = engine.fire_all(wm2)
  assert_eq(r2.fired.length(), 0)
}
