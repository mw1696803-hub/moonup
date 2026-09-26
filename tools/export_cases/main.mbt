///|
/// 案例库导出工具：构造"内置 + 压力示例 + 反馈闭环后"的案例库，
/// 输出 save_json() 纯 JSON（供宿主落盘 / 展示落盘格式）。
///
/// 用法：moon run tools/export_cases > cases/cases.json
fn main {
  let lib = @case.CaseLibrary::new()
  let _ = lib.import_cards(@case.CaseLibrary::sample_pressure_cases())

  // 模拟团队真实使用后的沉淀状态：
  // 信息收集识别与行为信号规则已验证；缺失信息案例被高频命中；一条旧案例被修正
  let _ = lib.record_feedback("p-competitor-intel", "positive", "团队验证：信息收集型接触识别规则有效，供全员参考")
  let _ = lib.record_feedback("p-surface-bias", "positive", "团队验证：行为信号补充特征判断，命中 2 例")
  let _ = lib.record_hit("p-missing-touch")
  let _ = lib.record_hit("p-missing-touch")
  let _ = lib.record_hit("p-missing-touch")
  let _ = lib.record_hit("p-question-driven")
  let _ = lib.supersede("p-rosy-promise", "被 p-weekly-rosy 覆盖：周会画饼场景更精确")

  println(lib.save_json())
}
