///|
/// Scenario 场景路由模块。
///
/// 对应向上管理教练素材 references/10-scenario-router.md：
/// 在写建议前先选定最接近的场景（16 类），命中多个时给出 top 2，
/// 并按路由规则附加处理提示（多领导先对齐、跨职能组合工具、组织机制先看系统）。
///
/// 输入：情境特征词数组（来自上游清洗或调用方）；
/// 输出：主场景 + 次场景 + 命中特征 + 路由提示。

/// 向上管理情境类型（16 类，含组织机制问题）
pub(all) enum Scenario {
  ReportingUpward          // 向上汇报
  AskingForResources       // 申请资源
  ClarifyingVagueRequirements // 澄清模糊需求
  ExtraWorkNoSchedule      // 加活不加期
  ResponsibilityWithoutAuthority // 有责无权
  MultipleLeadersConflicting // 多头领导冲突
  UnclearDecisionOwner     // 决策人不明/隐形评估者
  CrossFunctionalStakeholder // 跨职能阻力
  BossPromiseRosyTalk      // 老板承诺/画饼
  BlamePrevention          // 防背锅
  PerfPromoSalary          // 绩效/晋升/薪酬
  ConflictDeescalation     // 冲突降级
  EmotionalConsumption     // 情绪消耗
  HrLaborRisk              // HR/劳动风险
  ExitLossReduction        // 离职/止损
  OrganizationMechanism    // 组织机制问题
}

fn scenario_eq(a : Scenario, b : Scenario) -> Bool {
  match (a, b) {
    (ReportingUpward, ReportingUpward) => true
    (AskingForResources, AskingForResources) => true
    (ClarifyingVagueRequirements, ClarifyingVagueRequirements) => true
    (ExtraWorkNoSchedule, ExtraWorkNoSchedule) => true
    (ResponsibilityWithoutAuthority, ResponsibilityWithoutAuthority) => true
    (MultipleLeadersConflicting, MultipleLeadersConflicting) => true
    (UnclearDecisionOwner, UnclearDecisionOwner) => true
    (CrossFunctionalStakeholder, CrossFunctionalStakeholder) => true
    (BossPromiseRosyTalk, BossPromiseRosyTalk) => true
    (BlamePrevention, BlamePrevention) => true
    (PerfPromoSalary, PerfPromoSalary) => true
    (ConflictDeescalation, ConflictDeescalation) => true
    (EmotionalConsumption, EmotionalConsumption) => true
    (HrLaborRisk, HrLaborRisk) => true
    (ExitLossReduction, ExitLossReduction) => true
    (OrganizationMechanism, OrganizationMechanism) => true
    _ => false
  }
}

/// 场景中文名
pub fn Scenario::label(self : Scenario) -> String {
  match self {
    ReportingUpward => "向上汇报"
    AskingForResources => "申请资源"
    ClarifyingVagueRequirements => "澄清模糊需求"
    ExtraWorkNoSchedule => "加活不加期"
    ResponsibilityWithoutAuthority => "有责无权"
    MultipleLeadersConflicting => "多头领导冲突"
    UnclearDecisionOwner => "决策人不明"
    CrossFunctionalStakeholder => "跨职能阻力"
    BossPromiseRosyTalk => "老板承诺/画饼"
    BlamePrevention => "防背锅"
    PerfPromoSalary => "绩效/晋升/薪酬"
    ConflictDeescalation => "冲突降级"
    EmotionalConsumption => "情绪消耗"
    HrLaborRisk => "HR/劳动风险"
    ExitLossReduction => "离职/止损"
    OrganizationMechanism => "组织机制问题"
  }
}

/// 场景路由结果
pub struct RouteResult {
  primary : Scenario
  secondary : Array[Scenario]
  matched : Array[String]
  hint : String
  routable : Bool
}

/// 场景路由器
pub struct ScenarioRouter {
  version : String
}

/// 创建路由器
pub fn ScenarioRouter::new() -> ScenarioRouter {
  { version: "scenario-v1" }
}

/// 所有场景（固定顺序，作为评分索引）
fn all_scenarios() -> Array[Scenario] {
  [
    ReportingUpward,
    AskingForResources,
    ClarifyingVagueRequirements,
    ExtraWorkNoSchedule,
    ResponsibilityWithoutAuthority,
    MultipleLeadersConflicting,
    UnclearDecisionOwner,
    CrossFunctionalStakeholder,
    BossPromiseRosyTalk,
    BlamePrevention,
    PerfPromoSalary,
    ConflictDeescalation,
    EmotionalConsumption,
    HrLaborRisk,
    ExitLossReduction,
    OrganizationMechanism,
  ]
}

/// 场景关键词表
fn scenario_keywords(s : Scenario) -> Array[String] {
  match s {
    ReportingUpward => ["汇报", "周报", "同步进展", "向上同步"]
    AskingForResources => ["要资源", "要预算", "加人", "人力", "经费", "资源不够", "申请资源"]
    ClarifyingVagueRequirements => ["需求不清", "目标模糊", "要求模糊", "说不清", "范围不清", "标准不清"]
    ExtraWorkNoSchedule => ["加活", "额外任务", "排期没变", "临时加活", "不加时间"]
    ResponsibilityWithoutAuthority => ["有责无权", "背锅", "没有授权", "没权", "责任不清"]
    MultipleLeadersConflicting => ["两个领导", "两个老板", "多头", "领导冲突", "汇报线冲突"]
    UnclearDecisionOwner => ["谁拍板", "决策人", "隐形评估", "找不到负责人", "没人拍板"]
    CrossFunctionalStakeholder => ["跨部门", "跨职能", "部门墙", "协作受阻", "其他部门不配合"]
    BossPromiseRosyTalk => ["画饼", "漂亮话", "会考虑", "好好干", "口头承诺"]
    BlamePrevention => ["甩锅", "背黑锅", "推卸责任", "防背锅", "责任推给别人"]
    PerfPromoSalary => ["晋升", "绩效", "加薪", "涨薪", "考核", "评级", "工资"]
    ConflictDeescalation => ["冲突", "吵架", "争执", "对抗", "吵起来"]
    EmotionalConsumption => ["内耗", "心累", "委屈", "焦虑", "情绪消耗", "难受"]
    HrLaborRisk => ["裁员", "仲裁", "辞退", "劳动风险", "合规", "hr"]
    ExitLossReduction => ["离职", "跳槽", "止损", "交接", "准备离开"]
    OrganizationMechanism => ["流程问题", "机制", "激励", "文化", "组织问题", "系统"]
  }
}

/// 路由：扫描特征词 → 统计各场景命中数 → 取 top2 + 规则提示
///
/// 路由规则（素材）：
/// - 多领导 → 提示先对齐再执行
/// - 跨职能受阻 → 提示组合 stakeholder/需求诊断/脚本库
/// - 组织机制 → 提示先看系统再归因
pub fn ScenarioRouter::route(_self : ScenarioRouter, features : Array[String]) -> RouteResult {
  let scenarios = all_scenarios()
  let scores : Array[Int] = []
  let matched_all : Array[Array[String]] = []
  for s in scenarios {
    let kws = scenario_keywords(s)
    let mut cnt = 0
    let hit : Array[String] = []
    for f in features {
      let mut hit_this = false
      for kw in kws {
        if f.contains(kw) {
          hit_this = true
        }
      }
      if hit_this {
        cnt = cnt + 1
        hit.push(f)
      }
    }
    scores.push(cnt)
    matched_all.push(hit)
  }

  // 取最高分（primary）与次高分（secondary），同分按枚举顺序
  let mut best = -1
  let mut second = -1
  let mut i = 0
  while i < scores.length() {
    if best == -1 || scores[i] > scores[best] {
      second = best
      best = i
    } else if second == -1 || scores[i] > scores[second] {
      second = i
    }
    i = i + 1
  }

  if best == -1 || scores[best] <= 0 {
    { primary: ReportingUpward, secondary: [], matched: [], hint: "特征不足：请补充更多情境信息（谁、发生了什么、卡在哪）后再路由", routable: false }
  } else {
    let primary = scenarios[best]
    let secondary = if second != -1 && scores[second] > 0 {
      [scenarios[second]]
    } else {
      []
    }
    { primary, secondary, matched: matched_all[best], hint: build_hint(primary), routable: true }
  }
}

/// 路由提示（按路由规则生成）
fn build_hint(primary : Scenario) -> String {
  match primary {
    MultipleLeadersConflicting => "多领导冲突：先对齐各方期望再执行，避免夹在中间硬扛（参考 stakeholder-map）"
    CrossFunctionalStakeholder => "跨职能受阻：组合 stakeholder-map + 需求诊断 + 脚本库一起用"
    OrganizationMechanism => "问题可能超出个人措辞：先看组织机制（角色/流程/激励）再归因"
    BossPromiseRosyTalk => "画饼场景：把口头承诺转为书面条件清单，先验证再行动（结合 evidence 置信度）"
    ResponsibilityWithoutAuthority => "有责无权：先确认授权/资源/评估标准，再决定接受或协商"
    _ => "已路由到「" + primary.label() + "」场景，按对应脚本模板推进"
  }
}

///|
test "关键词'要预算 加人' → 申请资源" {
  let r = ScenarioRouter::new().route(["下季度要预算", "需要加人"])
  assert_true(r.routable)
  assert_true(scenario_eq(r.primary, AskingForResources))
}

///|
test "'有责无权 背锅' → 有责无权 + 确认授权提示" {
  let r = ScenarioRouter::new().route(["任务有责无权", "又要背锅"])
  assert_true(r.routable)
  assert_true(scenario_eq(r.primary, ResponsibilityWithoutAuthority))
  assert_true(r.hint.contains("确认授权"))
}

///|
test "'画饼 口头承诺' → 老板画饼 + evidence 联动提示" {
  let r = ScenarioRouter::new().route(["老板又在画饼", "口头承诺"])
  assert_true(r.routable)
  assert_true(scenario_eq(r.primary, BossPromiseRosyTalk))
  assert_true(r.hint.contains("书面条件"))
}

///|
test "'两个领导 冲突' → 多头冲突 + 先对齐提示" {
  let r = ScenarioRouter::new().route(["两个领导要求冲突", "汇报线冲突"])
  assert_true(r.routable)
  assert_true(scenario_eq(r.primary, MultipleLeadersConflicting))
  assert_true(r.hint.contains("先对齐"))
}

///|
test "'跨部门 协作受阻' → 跨职能 + 组合工具提示" {
  let r = ScenarioRouter::new().route(["跨部门协作受阻", "部门墙"])
  assert_true(r.routable)
  assert_true(scenario_eq(r.primary, CrossFunctionalStakeholder))
  assert_true(r.hint.contains("stakeholder"))
}

///|
test "多场景命中 → top2（晋升+画饼，同分取先枚举）" {
  let r = ScenarioRouter::new().route(["申请晋升", "他说会考虑"])
  assert_true(r.routable)
  assert_true(scenario_eq(r.primary, BossPromiseRosyTalk))
  assert_eq(r.secondary.length(), 1)
  assert_true(scenario_eq(r.secondary[0], PerfPromoSalary))
}

///|
test "组织机制关键词 → 组织机制 + 先看系统提示" {
  let r = ScenarioRouter::new().route(["流程问题", "激励机制不合理"])
  assert_true(r.routable)
  assert_true(scenario_eq(r.primary, OrganizationMechanism))
  assert_true(r.hint.contains("组织机制"))
}

///|
test "无命中 → routable=false + 补充信息提示" {
  let r = ScenarioRouter::new().route(["今天天气不错"])
  assert_false(r.routable)
  assert_true(r.hint.contains("补充更多"))
}

///|
test "空特征 → routable=false" {
  let r = ScenarioRouter::new().route([])
  assert_false(r.routable)
}

///|
test "命中特征原样返回" {
  let r = ScenarioRouter::new().route(["绩效评估", "加薪申请"])
  assert_eq(r.matched.length(), 2)
}
