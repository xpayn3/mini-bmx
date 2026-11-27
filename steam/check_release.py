"""Release gate: fail if a release export of the game carries any developer tool.

Reads the Godot pack embedded in the exe (or a .pck) and lists every file in it; the build fails when one sits in a
dev-only place (res://dev/, the editor addons, tools/) or a dev-only library sits next to the exe.
    python steam/check_release.py build/steam/windows/Runout.exe [--list]
Exit code 0 = clean, 1 = dev files found, 2 = could not read the pack.
"""
import os
import struct
import sys

FORBIDDEN = ("dev/", "tools/", "addons/debug_draw_3d/", "addons/land_lab/", "addons/level_builder/", "docs/")
FORBIDDEN_LIBS = ("libdd3d",)  # Debug Draw 3D (the physics overlay)


def read_pack(path):
    data = open(path, "rb").read()
    if data[:4] == b"GDPC":
        start = 0
    elif data[-4:] == b"GDPC":  # embedded: ... pack ... u64 pack size, "GDPC"
        size = struct.unpack_from("<Q", data, len(data) - 12)[0]
        start = len(data) - 12 - size
        if data[start:start + 4] != b"GDPC":
            raise ValueError("embedded pack header not found")
    else:
        raise ValueError("no Godot pack in " + path)
    o = start + 4
    ver, _maj, _min, _pat, flags = struct.unpack_from("<5I", data, o)
    o += 20
    o += 8  # file base
    if ver >= 3:
        dir_off = struct.unpack_from("<Q", data, o)[0]
        if flags & 2:  # relative file base: the directory offset is relative to the pack start too
            dir_off += start
        o = dir_off
    else:
        o += 16 * 4
        if ver >= 3:
            pass
    if ver < 3:
        o = start + 4 + 20 + 8 + 16 * 4
    count = struct.unpack_from("<I", data, o)[0]
    o += 4
    files = []
    for _ in range(count):
        n = struct.unpack_from("<I", data, o)[0]
        o += 4
        p = data[o:o + n].rstrip(b"\0").decode("utf-8", "replace")
        o += n
        o += 8 + 8 + 16  # offset, size, md5
        if ver >= 2:
            o += 4  # flags
        files.append(p[6:] if p.startswith("res://") else p)
    return files


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    exe = sys.argv[1]
    try:
        files = read_pack(exe)
    except Exception as e:  # noqa: BLE001
        print("RELEASECHECK cannot read the pack:", e)
        return 2
    if "--list" in sys.argv:
        for f in files:
            print(f)
    bad = [f for f in files if f.startswith(FORBIDDEN)]
    folder = os.path.dirname(os.path.abspath(exe))
    bad += [n for n in os.listdir(folder) if n.lower().startswith(FORBIDDEN_LIBS)]
    for f in bad[:60]:
        print("RELEASECHECK dev file:", f)
    print("RELEASECHECK files=%d dev=%d %s" % (len(files), len(bad), "FAIL" if bad else "PASS"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
