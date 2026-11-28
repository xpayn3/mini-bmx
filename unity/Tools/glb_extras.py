"""Write each bike glb's root-node "extras" (steer axis, wheel radii, wheelbase, the suspension linkage...) as a flat
text file next to the copied model, because Unity's glTF importer drops extras. One line per number list:
    steerAxis=-0.457,0.889,0
    suspension.rear.G1=0.0984,0.39709
Run from the repo root: python unity/Tools/glb_extras.py
"""
import json, struct, os

SRC = 'godot/assets'
DST = 'unity/Assets/Runout/Art/Models/Bikes'


def glb_json(p):
    b = open(p, 'rb').read()
    n = struct.unpack('<I', b[12:16])[0]
    return json.loads(b[20:20 + n])


def flat(prefix, v, out):
    if isinstance(v, dict):
        for k in v:
            flat(prefix + '.' + k if prefix else k, v[k], out)
    elif isinstance(v, list) and all(isinstance(x, (int, float)) for x in v):
        out.append(prefix + '=' + ','.join(repr(float(x)) for x in v))
    elif isinstance(v, bool):
        out.append(prefix + '=' + ('1' if v else '0'))
    elif isinstance(v, (int, float)):
        out.append(prefix + '=' + repr(float(v)))
    elif isinstance(v, str):
        out.append(prefix + '=' + v)
    # (nested lists of lists: not needed by the drawing yet)


for f in sorted(os.listdir(SRC)):
    if not f.endswith('.glb'):
        continue
    j = glb_json(os.path.join(SRC, f))
    roots = [j['nodes'][i] for i in j['scenes'][0]['nodes']]
    node = next((n for n in roots if n.get('extras')), None) or next((n for n in j['nodes'] if n.get('extras')), None)
    if node is None:
        continue
    out = ['root=' + node['name']]
    flat('', node['extras'], out)
    dst = os.path.join(DST, f[:-4] + '.extras.txt')
    open(dst, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
    print(dst, len(out), 'lines')
