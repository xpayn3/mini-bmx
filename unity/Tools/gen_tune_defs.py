"""Regenerate unity/Assets/Runout/Config/TuneDefs.g.cs from godot/scripts/core/tune.gd (run from the repo root)."""
import re

src = open('godot/scripts/core/tune.gd', encoding='utf-8').read()
body = src[src.index('const DEFS := ['):src.index('const PATH :=')]
NUM = r'([0-9.eE+-]+)'
STR = r'"((?:[^"\\]|\\.)*)"'
ROW = re.compile(r'^\["(\w+)",\s*' + STR + r',\s*' + NUM + r',\s*' + NUM + r',\s*' + NUM + r',\s*' + NUM + r',\s*' + STR + r'\s*\],?')
GROUP = re.compile(r'^\["([^"]+)",\s*\[\s*$')


def f(v):
    return v if ('.' in v or 'e' in v or 'E' in v) else v + '.0'


out = ['// GENERATED from godot/scripts/core/tune.gd DEFS by unity/Tools/gen_tune_defs.py. Do not edit by hand.',
       '// Row = group, key, label, default, min, max, step, unit.',
       'namespace Runout.Config', '{', '    public static partial class TuneDefs', '    {',
       '        public static readonly TuneRow[] Rows =', '        {']
group, n = None, 0
for ln in body.split('\n'):
    s = ln.strip()
    g = GROUP.match(s)
    if g:
        group = g.group(1)
        continue
    r = ROW.match(s)
    if r:
        k, lab, d, lo, hi, st, unit = r.groups()
        out.append(f'            new TuneRow("{group}", "{k}", "{lab}", {f(d)}, {f(lo)}, {f(hi)}, {f(st)}, "{unit}"),')
        n += 1
    elif s.startswith('["') and not s.endswith('['):
        print('UNPARSED', s[:110])
out += ['        };', '    }', '}', '']
open('unity/Assets/Runout/Config/TuneDefs.g.cs', 'w', encoding='utf-8').write('\n'.join(out))
print(n, 'rows')
