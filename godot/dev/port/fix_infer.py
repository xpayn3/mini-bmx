"""Gives GDScript locals that took their type from the (now untyped) physics object an explicit type.

The game holds `phys` untyped so it can be the GDScript BikePhysics or the C# BikePhysicsCs; `var f := phys.fwd()`
then can't infer. This reads Godot's --check-only errors and rewrites each such line: an explicit type when the value
is a physics member / method (from dev/port/out/members.json) or a simple expression of one, else plain `=`.
python godot/dev/port/fix_infer.py   (repeat until it reports 0)
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT = r"C:/Users/Luka/Godot/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
m = json.load(open(os.path.join(ROOT, "dev/port/out/members.json")))
GD_T = {"double": "float", "long": "int", "bool": "bool", "string": "String", "V2": "Vector2", "V3": "Vector3"}
MEMBERS = {k: GD_T[v] for k, v in m["members"].items() if v in GD_T}
METHODS = {"fwd": "Vector3", "gear_k": "float", "is_sane": "bool", "shift": "bool"}
FILES = sys.argv[1:] or ["scripts/game/game.gd", "scripts/game/camera_rig.gd", "scripts/game/pad_rumble.gd",
                         "scripts/game/ride_log.gd", "scripts/ui/hud.gd", "dev/main_dev.gd"]


def errors(path):
    out = subprocess.run([GODOT, "--headless", "--path", ROOT, "--check-only", "--script", "res://" + path],
                         capture_output=True, text=True, timeout=300)
    out = out.stdout + out.stderr
    lines = out.splitlines()
    found = []
    for i, l in enumerate(lines):
        mm = re.search(r'Cannot infer the type of "(\w+)" variable', l)
        if mm and i + 1 < len(lines):
            at = re.search(r"\(res://(.+?):(\d+)\)", lines[i + 1])
            if at:
                found.append((at.group(1), int(at.group(2)), mm.group(1)))
    return found


def infer(expr):
    e = expr.strip()
    # a member / method of the physics, or a numeric expression made only of them and numbers
    mm = re.fullmatch(r"\w+\.(\w+)\(.*\)", e)
    if mm and mm.group(1) in METHODS:
        return METHODS[mm.group(1)]
    mm = re.fullmatch(r"-?\w+\.(\w+)", e)
    if mm and mm.group(1) in MEMBERS:
        return MEMBERS[mm.group(1)]
    if re.search(r"\b(absf|maxf|minf|clampf|sin|cos|sqrt|atan2|lerpf|smoothstep|float)\(", e) and "Vector" not in e:
        return "float"
    return None


total = 0
for f in FILES:
    for path, line, var in errors(f):
        p = os.path.join(ROOT, path)
        src = open(p, encoding="utf-8").read().split("\n")
        l = src[line - 1]
        mm = re.match(r"(\s*var\s+" + var + r")\s*:=\s*(.*)$", l)
        if not mm:
            print(f"FIXINFER skip {path}:{line}: {l.strip()}")
            continue
        code, _, com = mm.group(2).partition("  #")
        t = infer(code)
        src[line - 1] = f"{mm.group(1)}: {t} = {mm.group(2)}" if t else f"{mm.group(1)} = {mm.group(2)}"
        open(p, "w", encoding="utf-8", newline="\n").write("\n".join(src))
        total += 1
print(f"FIXINFER fixed {total}")
