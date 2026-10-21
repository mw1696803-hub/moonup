import re

p = r'C:\Users\21162\Documents\crm\黑客松\moonup\docs\moonup-demo.html'
s = open(p, encoding='utf-8').read()

# 在 Roadmap 块内删除 JSON 行（带 parse_rules_json 的那行）
lines = s.split('\n')
out = []
in_roadmap = False
for l in lines:
    if 'Roadmap' in l:
        in_roadmap = True
    if in_roadmap and 'parse_rules_json' in l:
        # 跳过这行（Roadmap 里的 JSON 行）
        continue
    if in_roadmap and '多轮非线性传播优化' in l:
        in_roadmap = False
    out.append(l)
s2 = '\n'.join(out)
open(p, 'w', encoding='utf-8', newline='').write(s2)

# 打印校验
for i, l in enumerate(s2.splitlines()):
    if 'Roadmap' in l or 'parse_rules_json' in l or 'JSON 规则集加载' in l or 'JSON / 配置' in l or 'unit tests' in l or 'passed' in l:
        print(i + 1, ':', l.strip()[:100])
