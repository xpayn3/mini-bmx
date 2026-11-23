"""Writes tools/bake_jumps.gd's output into trail_features.gd + TerrainFieldCs.cs (TABLE / KICKER knots, AIR spans).
Run: godot --headless --path godot -s res://tools/bake_jumps.gd | python godot/tools/bake_jumps.py"""
import json, re, sys
line = [l for l in sys.stdin.read().splitlines() if l.startswith("BAKE ")][0]
b = json.loads(line[5:])
def num(x):
    s = repr(round(float(x), 4))
    return s[:-2] if s.endswith(".0") and False else s
def gd_knots(k): return "[" + ", ".join("[" + ", ".join(num(v) for v in kn) + "]" for kn in k) + "]"
def cs_knots(k): return "{ " + ", ".join("new[] { " + ", ".join(num(v) for v in kn) + " }" for kn in k) + " }"
T, K = b["table"], b["kicker"]
lt = T["knots"][-1][0]
ta, ka = T["air"], K["air"]
air = {"table": ta, "kicker": ka, "flow": ka,
       "tableLine": ta + [round(lt + 3.0 + ka[0], 2), round(lt + 3.0 + ka[1], 2)],
       "doubleLine": [8.0, 17.6, round(36.8 + 3.0 + ka[0], 2), round(36.8 + 3.0 + ka[1], 2)]}
root = sys.argv[1] if len(sys.argv) > 1 else "godot"
p = root + "/scripts/world/trail_features.gd"
s = open(p, encoding="utf-8").read()
s = re.sub(r"^const TABLE := .*$", "const TABLE := " + gd_knots(T["knots"]) + "   # baked: tools/bake_jumps.gd", s, flags=re.M)
s = re.sub(r"^const KICKER := .*$", "const KICKER := " + gd_knots(K["knots"]) + "   # baked: tools/bake_jumps.gd", s, flags=re.M)
for k, v in air.items():
    s = re.sub(r'(^const AIR := \{.*?)"%s": \[[^\]]*\]' % k, lambda m: m.group(1) + '"%s": [%s]' % (k, ", ".join(num(x) for x in v)), s, count=1, flags=re.M | re.S)
open(p, "w", encoding="utf-8").write(s)
p = root + "/scripts/world/TerrainFieldCs.cs"
s = open(p, encoding="utf-8").read()
s = re.sub(r"public static readonly double\[\]\[\] TABLE = \{.*?\};.*$", "public static readonly double[][] TABLE = " + cs_knots(T["knots"]) + ";   // baked: tools/bake_jumps.gd", s, count=1, flags=re.M)
s = re.sub(r"public static readonly double\[\]\[\] KICKER = \{.*?\};.*$", "public static readonly double[][] KICKER = " + cs_knots(K["knots"]) + ";   // baked: tools/bake_jumps.gd", s, count=1, flags=re.M)
i = s.index("private static readonly System.Collections.Generic.Dictionary<string, double[]> AIR = new()")
j = s.index("};", i)
blk = s[i:j]
for k, v in air.items():
    blk = re.sub(r'\["%s"\] = new\[\] \{[^}]*\}' % k, '["%s"] = new[] { %s }' % (k, ", ".join(num(x) for x in v)), blk, count=1)
s = s[:i] + blk + s[j:]
open(p, "w", encoding="utf-8").write(s)
for k in ("table", "kicker"): print(k, b[k]["length"], b[k]["desc"])
print("AIR", air)
