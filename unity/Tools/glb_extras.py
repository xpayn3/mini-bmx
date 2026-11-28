"""Write each bike glb's root-node "extras" (steer axis, wheel radii, wheelbase, the suspension linkage...) as a flat
text file next to the copied model, because Unity's glTF importer drops extras. One line per number list:
    steerAxis=-0.457,0.889,0
    suspension.rear.G1=0.0984,0.39709
Plus what Godot's BikeRig measures off the meshes at load (rig.* keys, in each part's own mesh space, Godot axes):
    rig.gripL / rig.gripR   middle of the "rubber" surface of the steer mesh, left (z < 0) / right half (BikeRig._grips)
    rig.pedalL / rig.pedalR middle of each half of the crank's "plastic" surface (BikeRig._split_pedals: the pedal pivots)
    rig.pedalTop            the pedals' top above their middle (BikeRig.pedal_top)
    rig.seat                top, rear, front of the frame's "plastic" surface = the saddle (BikeRig._saddle)
Only glbs whose root extras carry a wheelbase (bikes). Run from the repo root: python unity/Tools/glb_extras.py
"""
import json, struct, os

SRC = 'godot/assets'
DST = 'unity/Assets/Runout/Art/Models/Bikes'


def glb(p):
    b = open(p, 'rb').read()
    n = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + n])
    off = 20 + n
    binc = b''
    if off + 8 <= len(b):
        ln = struct.unpack('<I', b[off:off + 4])[0]
        binc = b[off + 8:off + 8 + ln]
    return j, binc


COMP = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def accessor(j, binc, i):
    a = j['accessors'][i]
    bv = j['bufferViews'][a['bufferView']]
    fm, sz = COMP[a['componentType']]
    nc = NC[a['type']]
    stride = bv.get('byteStride') or sz * nc
    base = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    out = []
    for k in range(a['count']):
        o = base + k * stride
        v = struct.unpack('<' + fm * nc, binc[o:o + sz * nc])
        out.append(v if nc > 1 else v[0])
    return out


def prim_tris(j, binc, mesh_name, mat_name):
    """the triangles of node `mesh_name`'s mesh primitives whose material is `mat_name`"""
    node = next((n for n in j['nodes'] if n.get('name') == mesh_name and 'mesh' in n), None)
    if node is None:
        return []
    tris = []
    for pr in j['meshes'][node['mesh']]['primitives']:
        mi = pr.get('material')
        if mi is None or j['materials'][mi].get('name') != mat_name:
            continue
        pos = accessor(j, binc, pr['attributes']['POSITION'])
        idx = accessor(j, binc, pr['indices']) if 'indices' in pr else list(range(len(pos)))
        for t in range(0, len(idx) - 2, 3):
            tris.append((pos[idx[t]], pos[idx[t + 1]], pos[idx[t + 2]]))
    return tris


def grip_cylinder(pts):
    """(inner end, outer end, radius) of the grip's vertices: the axis = their main direction (power iteration on the
    covariance), the ends = the extreme points along it (outer = the one further from the bike's middle plane z = 0)"""
    n = len(pts)
    if n < 8:
        return None
    c = [sum(p[i] for p in pts) / n for i in range(3)]
    C = [[sum((p[a] - c[a]) * (p[b] - c[b]) for p in pts) / n for b in range(3)] for a in range(3)]
    v = [0.0, 0.0, 1.0]
    for _ in range(60):
        w = [sum(C[a][b] * v[b] for b in range(3)) for a in range(3)]
        l = sum(x * x for x in w) ** 0.5 or 1.0
        v = [x / l for x in w]
    ts = [sum((p[i] - c[i]) * v[i] for i in range(3)) for p in pts]
    a = [c[i] + v[i] * min(ts) for i in range(3)]
    b = [c[i] + v[i] * max(ts) for i in range(3)]
    inner, outer = (a, b) if abs(a[2]) < abs(b[2]) else (b, a)
    rad = 0.0
    for p, t in zip(pts, ts):
        d = [p[i] - c[i] - v[i] * t for i in range(3)]
        rad += sum(x * x for x in d) ** 0.5
    return inner, outer, rad / n


def fmt(v):
    return ','.join(repr(float(x)) for x in v)


def sgn(x):
    return 1 if x > 0 else (-1 if x < 0 else 0)


def rig_lines(j, binc):
    out = []
    # grips: every vertex of the steer's rubber, split by side (BikeRig._grips)
    tris = prim_tris(j, binc, 'steer', 'rubber')
    if tris:
        L = [p for t in tris for p in t if p[2] <= 0]
        R = [p for t in tris for p in t if p[2] > 0]
        for nm, s in (('gripL', L), ('gripR', R)):
            if s:
                out.append('rig.%s=%s' % (nm, fmt([sum(p[i] for p in s) / len(s) for i in range(3)])))
                # the grip as a cylinder (any bar: width, sweep, rise): its axis by PCA, the inner / outer end on it, radius
                g = grip_cylinder(s)
                if g:
                    out.append('rig.%sIn=%s' % (nm, fmt(g[0])))
                    out.append('rig.%sOut=%s' % (nm, fmt(g[1])))
                    out.append('rig.%sR=%r' % (nm, g[2]))
    # pedals: the crank's plastic, triangles by the side of their middle (BikeRig._split_pedals)
    tris = prim_tris(j, binc, 'crank', 'plastic')
    if tris:
        top = 0.0
        for nm, side in (('pedalL', -1), ('pedalR', 1)):
            s = [p for t in tris if sgn(sum(q[2] for q in t) / 3) == side for p in t]
            if not s:
                continue
            c = [sum(p[i] for p in s) / len(s) for i in range(3)]
            out.append('rig.%s=%s' % (nm, fmt(c)))
            top = max(top, max(p[1] - c[1] for p in s))
        out.append('rig.pedalTop=%r' % (top if top > 0 else 0.017))
    # saddle: the frame's plastic surface (BikeRig._saddle)
    tris = prim_tris(j, binc, 'frame', 'plastic')
    if tris:
        ps = [p for t in tris for p in t]
        out.append('rig.seat=%s' % fmt([max(p[1] for p in ps), min(p[0] for p in ps), max(p[0] for p in ps)]))
    return out


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
    j, binc = glb(os.path.join(SRC, f))
    roots = [j['nodes'][i] for i in j['scenes'][0]['nodes']]
    node = next((n for n in roots if n.get('extras')), None) or next((n for n in j['nodes'] if n.get('extras')), None)
    if node is None or 'wheelbase' not in node['extras']:
        continue
    out = ['root=' + node['name']]
    flat('', node['extras'], out)
    out += rig_lines(j, binc)
    dst = os.path.join(DST, f[:-4] + '.extras.txt')
    open(dst, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
    print(dst, len(out), 'lines', [l for l in out if l.startswith('rig.')])
