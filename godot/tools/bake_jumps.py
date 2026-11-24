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
T, K, D = b["table"], b["kicker"], b["double"]
lt, ld = T["knots"][-1][0], D["knots"][-1][0]
ta, ka, da = T["air"], K["air"], D["air"]
air = {"table": ta, "kicker": ka, "flow": ka, "double": da,
       "tableLine": ta + [round(lt + 3.0 + ka[0], 2), round(lt + 3.0 + ka[1], 2)],
       "doubleLine": da + [round(ld + 3.0 + ka[0], 2), round(ld + 3.0 + ka[1], 2)]}
TS, KS, DS = b["table_s"], b["kicker_s"], b["double_s"]
lts, lds = TS["knots"][-1][0], DS["knots"][-1][0]
tsa, ksa, dsa = TS["air"], KS["air"], DS["air"]
air_s = {"table": tsa, "kicker": ksa, "flow": ksa, "double": dsa,
       "tableLine": tsa + [round(lts + 3.0 + ksa[0], 2), round(lts + 3.0 + ksa[1], 2)],
       "doubleLine": dsa + [round(lds + 3.0 + ksa[0], 2), round(lds + 3.0 + ksa[1], 2)]}
root = sys.argv[1] if len(sys.argv) > 1 else "godot"
p = root + "/scripts/world/trail_features.gd"
s = open(p, encoding="utf-8").read()
s = re.sub(r"^const TABLE := .*$", "const TABLE := " + gd_knots(T["knots"]) + "   # baked: tools/bake_jumps.gd", s, flags=re.M)
s = re.sub(r"^const KICKER := .*$", "const KICKER := " + gd_knots(K["knots"]) + "   # baked: tools/bake_jumps.gd", s, flags=re.M)
s = re.sub(r"^const DOUBLE := \[.*?\]\](?:   # baked: tools/bake_jumps\.gd)?$", lambda m: "const DOUBLE := " + gd_knots(D["knots"]) + "   # baked: tools/bake_jumps.gd", s, count=1, flags=re.M | re.S)
s = re.sub(r"^const DOUBLE_S := \[.*?\]\](?:   # baked: tools/bake_jumps\.gd)?$", lambda m: "const DOUBLE_S := " + gd_knots(DS["knots"]) + "   # baked: tools/bake_jumps.gd", s, count=1, flags=re.M | re.S)
for k, v in air.items():
    s = re.sub(r'(^const AIR := \{.*?)"%s": \[[^\]]*\]' % k, lambda m: m.group(1) + '"%s": [%s]' % (k, ", ".join(num(x) for x in v)), s, count=1, flags=re.M | re.S)
s = re.sub(r"^const TABLE_S := .*$", "const TABLE_S := " + gd_knots(TS["knots"]) + "   # baked: tools/bake_jumps.gd", s, flags=re.M)
s = re.sub(r"^const KICKER_S := .*$", "const KICKER_S := " + gd_knots(KS["knots"]) + "   # baked: tools/bake_jumps.gd", s, flags=re.M)
for k, v in air_s.items():
    s = re.sub(r'(^const AIR_S := \{.*?)"%s": \[[^\]]*\]' % k, lambda m: m.group(1) + '"%s": [%s]' % (k, ", ".join(num(x) for x in v)), s, count=1, flags=re.M | re.S)
open(p, "w", encoding="utf-8").write(s)
p = root + "/scripts/world/TerrainFieldCs.cs"
s = open(p, encoding="utf-8").read()
s = re.sub(r"public static readonly double\[\]\[\] TABLE = \{.*?\};.*$", "public static readonly double[][] TABLE = " + cs_knots(T["knots"]) + ";   // baked: tools/bake_jumps.gd", s, count=1, flags=re.M)
s = re.sub(r"public static readonly double\[\]\[\] KICKER = \{.*?\};.*$", "public static readonly double[][] KICKER = " + cs_knots(K["knots"]) + ";   // baked: tools/bake_jumps.gd", s, count=1, flags=re.M)
s = re.sub(r"public static readonly double\[\]\[\] DOUBLE = \{.*?\};[^\n]*", lambda m: "public static readonly double[][] DOUBLE = " + cs_knots(D["knots"]) + ";   // baked: tools/bake_jumps.gd", s, count=1, flags=re.S)
s = re.sub(r"public static readonly double\[\]\[\] DOUBLE_S = \{.*?\};[^\n]*", lambda m: "public static readonly double[][] DOUBLE_S = " + cs_knots(DS["knots"]) + ";   // baked: tools/bake_jumps.gd", s, count=1, flags=re.S)
i = s.index("private static readonly System.Collections.Generic.Dictionary<string, double[]> AIR = new()")
j = s.index("};", i)
blk = s[i:j]
for k, v in air.items():
    blk = re.sub(r'\["%s"\] = new\[\] \{[^}]*\}' % k, '["%s"] = new[] { %s }' % (k, ", ".join(num(x) for x in v)), blk, count=1)
s = s[:i] + blk + s[j:]
s = re.sub(r"public static readonly double\[\]\[\] TABLE_S = \{.*?\};.*$", "public static readonly double[][] TABLE_S = " + cs_knots(TS["knots"]) + ";   // baked: tools/bake_jumps.gd", s, count=1, flags=re.M)
s = re.sub(r"public static readonly double\[\]\[\] KICKER_S = \{.*?\};.*$", "public static readonly double[][] KICKER_S = " + cs_knots(KS["knots"]) + ";   // baked: tools/bake_jumps.gd", s, count=1, flags=re.M)
i = s.index("private static readonly System.Collections.Generic.Dictionary<string, double[]> AIR_S = new()")
j = s.index("};", i)
blk = s[i:j]
for k, v in air_s.items():
    blk = re.sub(r'\["%s"\] = new\[\] \{[^}]*\}' % k, '["%s"] = new[] { %s }' % (k, ", ".join(num(x) for x in v)), blk, count=1)
s = s[:i] + blk + s[j:]
open(p, "w", encoding="utf-8").write(s)
print("AIR_S", air_s)
for k in ("table", "kicker", "table_s", "kicker_s", "double", "double_s"): print(k, b[k]["length"], b[k]["desc"])
print("AIR", air)
