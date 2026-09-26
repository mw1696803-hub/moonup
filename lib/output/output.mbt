///|
/// Output 结构化输出模块（12 段模板）。
///
/// 对应向上管理教练素材 SKILL.md 的 Default Output Shape：
/// 1.OGS-M 清洗 2.认知定位 3.假设空间 4.双面与环境解读 5.用户状态与韧性校准
/// 6.证据与置信度 7.相关案例参考 8.专业动作 9.第三选项 10.建议动作 11.脚本 12.下一步观察。
///
/// 输入用键值对（缺失键输出「待补充」，不编造内容）；
/// 另内置 Safety Boundaries 常量（素材 Safety Boundaries 段），供上层在输出前检查。

/// 报告输入（键 → 内容，键名见 render 注释）
pub struct ReportInputs {
  map : Map[String, String]
}

/// 创建空输入
pub fn ReportInputs::new() -> ReportInputs {
  { map: Map([]) }
}

/// 设置字段
pub fn ReportInputs::set(self : ReportInputs, key : String, value : String) -> Unit {
  self.map[key] = value
}

/// 输出引擎
pub struct OutputEngine {
  version : String
}

/// 创建引擎
pub fn OutputEngine::new() -> OutputEngine {
  { version: "output-v1" }
}

fn get_or(inputs : ReportInputs, key : String) -> String {
  match inputs.map.get(key) {
    Some(v) => v
    None => "（待补充）"
  }
}

/// 生成 12 段结构化报告（Markdown）
pub fn OutputEngine::render(_self : OutputEngine, inputs : ReportInputs) -> String {
  let mut s = "# MoonUp 结构化输出报告\n"
  s = s + "\n## 1. OGS-M 情境清洗\n"
  s = s + "- O（目标）: " + get_or(inputs, "objective") + "\n"
  s = s + "- G（差距）: " + get_or(inputs, "gap") + "\n"
  s = s + "- S（情境）: " + get_or(inputs, "situation") + "\n"
  s = s + "- M（下一步）: " + get_or(inputs, "move") + "\n"

  s = s + "\n## 2. 认知定位\n"
  s = s + "- 发生了什么: " + get_or(inputs, "happening") + "\n"
  s = s + "- 卡在哪: " + get_or(inputs, "stuck") + "\n"
  s = s + "- 缺失信息: " + get_or(inputs, "missing") + "\n"

  s = s + "\n## 3. 假设空间\n"
  s = s + "- A: " + get_or(inputs, "hypothesis_a") + "\n"
  s = s + "- B: " + get_or(inputs, "hypothesis_b") + "\n"
  s = s + "- C: " + get_or(inputs, "hypothesis_c") + "\n"
  s = s + "- 最值得优先: " + get_or(inputs, "priority") + "\n"

  s = s + "\n## 4. 双面与环境解读\n"
  s = s + "- 用户侧: " + get_or(inputs, "user_side") + "\n"
  s = s + "- 老板侧: " + get_or(inputs, "boss_side") + "\n"
  s = s + "- 环境: " + get_or(inputs, "environment") + "\n"
  s = s + "- 相关方: " + get_or(inputs, "stakeholders") + "\n"
  s = s + "- 决策权: " + get_or(inputs, "decision_rights") + "\n"
  s = s + "- 组织机制: " + get_or(inputs, "org_module") + "\n"

  s = s + "\n## 5. 用户状态与韧性校准\n"
  s = s + "- 容量: " + get_or(inputs, "capacity") + "\n"
  s = s + "- 要保护什么: " + get_or(inputs, "protect") + "\n"
  s = s + "- 环境匹配: " + get_or(inputs, "env_fit") + "\n"
  s = s + "- 所处阶段: " + get_or(inputs, "integration_stage") + "\n"
  s = s + "- 长期循环: " + get_or(inputs, "long_term_loop") + "\n"

  s = s + "\n## 6. 证据与置信度\n"
  s = s + "- 已知事实: " + get_or(inputs, "known_facts") + "\n"
  s = s + "- 合理推断: " + get_or(inputs, "inferences") + "\n"
  s = s + "- 未验证假设: " + get_or(inputs, "unverified") + "\n"
  s = s + "- 置信度: " + get_or(inputs, "confidence") + "\n"

  s = s + "\n## 7. 相关案例参考\n"
  s = s + "- 相似案例: " + get_or(inputs, "similar_case") + "\n"
  s = s + "- 可迁移点: " + get_or(inputs, "transfers") + "\n"
  s = s + "- 可能不适用: " + get_or(inputs, "may_not_apply") + "\n"

  s = s + "\n## 8. 专业动作\n"
  s = s + "- 最佳下一步: " + get_or(inputs, "best_next") + "\n"
  s = s + "- 为什么: " + get_or(inputs, "why_move") + "\n"
  s = s + "- 暂不结论: " + get_or(inputs, "not_conclude") + "\n"

  s = s + "\n## 9. 第三选项\n" + get_or(inputs, "third_option") + "\n"
  s = s + "\n## 10. 建议动作\n" + get_or(inputs, "suggested_move") + "\n"

  s = s + "\n## 11. 脚本\n"
  s = s + "- 安全版: " + get_or(inputs, "script_safe") + "\n"
  s = s + "- 边界版: " + get_or(inputs, "script_boundary") + "\n"
  s = s + "- 可追溯版: " + get_or(inputs, "script_traceable") + "\n"

  s = s + "\n## 12. 下一步观察\n" + get_or(inputs, "observe_next") + "\n"
  s
}

/// 安全边界（素材 Safety Boundaries 段）——输出前应检查
pub fn OutputEngine::safety_boundaries() -> Array[String] {
  [
    "不鼓励非法录音、伪造证据、恶意设局、骚扰或报复",
    "涉及法律/HR/劳动纠纷时只给风险提示并建议专业咨询",
    "漂亮话权重不能压过重复行为",
    "直觉是风险信号，不是已证实的事实",
    "多领导分歧时不默认嗓门大的人拥有决策权，先识别决策权/评估权/资源权/背锅风险",
    "老板向下授权时，区分健康分布式判断与模糊责任转移",
    "冲突可能源于组织设计时，先找缺失机制，再归因于老板性格或用户弱点",
  ]
}

///|
test "空输入 → 12 段齐全且缺失标待补充" {
  let r = OutputEngine::new().render(ReportInputs::new())
  assert_true(r.contains("## 1."))
  assert_true(r.contains("## 12."))
  assert_true(r.contains("（待补充）"))
}

///|
test "OGS-M 段正确输出填入内容" {
  let inputs = ReportInputs::new()
  inputs.set("objective", "把口头承诺转为可验证条件")
  inputs.set("move", "书面确认评估标准")
  let r = OutputEngine::new().render(inputs)
  assert_true(r.contains("O（目标）: 把口头承诺转为可验证条件"))
  assert_true(r.contains("M（下一步）: 书面确认评估标准"))
  assert_false(r.contains("M（下一步）: （待补充）"))
}

///|
test "假设段三行 + 优先级" {
  let inputs = ReportInputs::new()
  inputs.set("hypothesis_a", "漂亮话")
  inputs.set("hypothesis_b", "缺机制")
  inputs.set("hypothesis_c", "试探")
  inputs.set("priority", "缺机制")
  let r = OutputEngine::new().render(inputs)
  assert_true(r.contains("- A: 漂亮话"))
  assert_true(r.contains("- C: 试探"))
  assert_true(r.contains("最值得优先: 缺机制"))
}

///|
test "脚本段三段齐全" {
  let inputs = ReportInputs::new()
  inputs.set("script_safe", "安全版话术")
  inputs.set("script_boundary", "边界版话术")
  inputs.set("script_traceable", "可追溯版话术")
  let r = OutputEngine::new().render(inputs)
  assert_true(r.contains("安全版: 安全版话术"))
  assert_true(r.contains("边界版: 边界版话术"))
  assert_true(r.contains("可追溯版: 可追溯版话术"))
}

///|
test "段落顺序 1-12：共 12 个段首标题" {
  let r = OutputEngine::new().render(ReportInputs::new())
  let parts = r.split("## ").to_array()
  // 12 段 → split 得到 13+ 个片段
  assert_true(parts.length() >= 13)
}

///|
test "证据段内容透传" {
  let inputs = ReportInputs::new()
  inputs.set("known_facts", "邮件确认了范围")
  inputs.set("confidence", "高")
  let r = OutputEngine::new().render(inputs)
  assert_true(r.contains("已知事实: 邮件确认了范围"))
  assert_true(r.contains("置信度: 高"))
}

///|
test "缺失单字段 → 仅该字段待补充" {
  let inputs = ReportInputs::new()
  inputs.set("objective", "目标X")
  let r = OutputEngine::new().render(inputs)
  assert_true(r.contains("O（目标）: 目标X"))
  assert_true(r.contains("G（差距）: （待补充）"))
}

///|
test "安全边界 7 条非空" {
  let b = OutputEngine::safety_boundaries()
  assert_eq(b.length(), 7)
  assert_true(b[0].length() > 5)
}

///|
test "安全边界覆盖关键纪律" {
  let b = OutputEngine::safety_boundaries()
  let mut has_recording = false
  for x in b {
    if x.contains("录音") {
      has_recording = true
    }
  }
  assert_true(has_recording)
}
