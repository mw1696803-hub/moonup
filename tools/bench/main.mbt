fn gen_rules(n : Int) -> Array[@rete.ReteRule] {
  let out = Array::make(n, @rete.ReteRule::new("", "", "false==true", "", 0, ""))
  for i = 0; i < n; i = i + 1 {
    out[i] = @rete.ReteRule::new(
      "r" + i.to_string(),
      "",
      "item" + i.to_string() + ".active==true",
      "item" + i.to_string() + ".tag+=hit",
      i % 10,
      "",
    )
  }
  out
}

fn fill_facts(n_rule : Int, n_fact : Int, engine : @rete.ReteEngine, wm : @rete.WorkingMemory) -> Unit {
  for i = 0; i < n_fact; i = i + 1 {
    let f = @rete.Fact::make("item" + (i % n_rule).to_string())
    f.set("active", "true")
    let _ = engine.insert(wm, f)
  }
}

fn bench(n_rule : Int, n_fact : Int) -> (Int, Int, Int) {
  let rules = gen_rules(n_rule)
  let t0 = @env.now()
  let engine = @rete.ReteEngine::new(rules)
  let t1 = @env.now()
  let wm = @rete.WorkingMemory::new()
  fill_facts(n_rule, n_fact, engine, wm)
  let r = engine.fire_all(wm, limit=6000)
  let t2 = @env.now()
  ((t1 - t0).to_int(), (t2 - t1).to_int(), r.fired.length())
}

fn main {
  println("MoonUp Rete 性能基准（@env.now 毫秒计时，单线程确定性执行，CLI/WASM 同源）")
  println("规则数\t事实数\t网络编译(ms)\tinsert+fire(ms)\t触发数")
  let cases = [(50, 100), (200, 500), (500, 1000), (1000, 2000)]
  for (n_rule, n_fact) in cases {
    let (compile_ms, run_ms, fired) = bench(n_rule, n_fact)
    println(
      n_rule.to_string() + "\t" + n_fact.to_string() + "\t" + compile_ms.to_string() + "\t" +
      run_ms.to_string() + "\t" + fired.to_string()
    )
  }
  println("环境: MoonBit 0.1.20260920（单线程确定性执行）")
}
