"""GDScript -> C# translator for the ride physics port (dev tool, not shipped).

python godot/dev/port/gd2cs.py godot/scripts/bike/bike_physics.gd godot/sim/BikeSim.gen.cs [--manual NAME,NAME] [--members out.json]

It keeps every line's meaning: GDScript floats are doubles, Vector2 / Vector3 are 32-bit (sim/Gd.cs V2 / V3 round
like the engine), ints stay ints (int / int stays an integer division), helper calls keep their names (Gd.cs gives
them Godot's exact semantics). Functions listed with --manual are left out (hand-ported in BikeSim.Manual.cs).
The output is checked against GDScript step by step (BMX_PHYS=cmp), so a wrong guess here shows up as a mismatch.
"""
import json
import re
import sys

CS_KEYWORDS = {"base", "lock", "object", "string", "params", "out", "ref", "in", "is", "as", "new", "this", "case",
               "char", "decimal", "default", "delegate", "event", "fixed", "checked", "operator", "internal", "goto",
               "implicit", "explicit", "namespace", "using", "struct", "sizeof", "typeof", "unchecked", "unsafe",
               "virtual", "volatile", "void", "float", "double", "int", "long", "short", "byte", "uint", "ulong",
               "readonly", "sealed", "stackalloc", "switch", "throw", "try", "catch", "finally", "lock", "abstract",
               "const", "continue", "do", "else", "enum", "extern", "false", "for", "foreach", "if", "interface",
               "null", "override", "private", "protected", "public", "return", "static", "true", "while", "class",
               "bool", "break", "event", "var", "dynamic", "record", "init", "value", "get", "set"}
SAFE_CTX = {"value", "get", "set", "var", "dynamic", "record", "init"}   # contextual keywords: fine as names


def cs_name(n):
    if n in CS_KEYWORDS and n not in SAFE_CTX:
        return "@" + n
    return n


# ------------------------------------------------------------------ lexer
TOKEN_RE = re.compile(r"""
    (?P<ws>[ \t]+)
  | (?P<num>(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?|0x[0-9a-fA-F]+)
  | (?P<str>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')
  | (?P<id>[A-Za-z_][A-Za-z_0-9]*)
  | (?P<op>:=|->|\*\*|==|!=|<=|>=|\+=|-=|\*=|/=|%=|&=|\|=|<<|>>|&&|\|\||[-+*/%<>=!&|^~()\[\]{},:.;@])
""", re.X)


class Tok:
    def __init__(self, kind, val):
        self.k = kind
        self.v = val

    def __repr__(self):
        return f"{self.k}:{self.v}"


def lex(s):
    out = []
    i = 0
    while i < len(s):
        m = TOKEN_RE.match(s, i)
        if not m:
            raise SyntaxError(f"lex error at {s[i:i + 30]!r}")
        i = m.end()
        k = m.lastgroup
        if k == "ws":
            continue
        out.append(Tok(k, m.group(k)))
    return out


def split_comment(line):
    """code, comment (outside strings)"""
    q = None
    for i, c in enumerate(line):
        if q:
            if c == "\\":
                continue
            if c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c == "#":
            return line[:i], line[i + 1:]
    return line, None


# ------------------------------------------------------------------ types
D, I, B, S, V2, V3, ANY, VOID = "double", "long", "bool", "string", "V2", "V3", "object", "void"
DICT, LIST = "GdDict", "List<object>"


def is_num(t):
    return t in (D, I, "float")


# ------------------------------------------------------------------ expression AST
class N:
    def __init__(self, kind, **kw):
        self.kind = kind
        self.__dict__.update(kw)


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self, o=0):
        j = self.i + o
        return self.t[j] if j < len(self.t) else Tok("eof", "")

    def next(self):
        t = self.peek()
        self.i += 1
        return t

    def accept(self, v):
        if self.peek().v == v and self.peek().k in ("op", "id"):
            self.i += 1
            return True
        return False

    def expect(self, v):
        t = self.next()
        if t.v != v:
            raise SyntaxError(f"expected {v!r}, got {t.v!r} in {' '.join(x.v for x in self.t)}")
        return t

    def at_end(self):
        return self.i >= len(self.t)

    def expr(self):
        return self.ternary()

    def ternary(self):
        a = self.or_()
        if self.peek().v == "if" and self.peek().k == "id":
            self.next()
            c = self.or_()
            self.expect("else")
            b = self.ternary()
            return N("tern", c=c, a=a, b=b)
        return a

    def or_(self):
        a = self.and_()
        while self.peek().v in ("or", "||"):
            self.next()
            a = N("bin", op="||", a=a, b=self.and_())
        return a

    def and_(self):
        a = self.not_()
        while self.peek().v in ("and", "&&"):
            self.next()
            a = N("bin", op="&&", a=a, b=self.not_())
        return a

    def not_(self):
        if self.peek().v in ("not", "!") and not (self.peek().v == "not" and self.peek(1).v == "in"):
            self.next()
            return N("not", a=self.not_())
        return self.in_()

    def in_(self):
        a = self.cmp()
        while True:
            if self.peek().v == "in" and self.peek().k == "id":
                self.next()
                a = N("in", a=a, b=self.cmp(), neg=False)
            elif self.peek().v == "not" and self.peek(1).v == "in":
                self.next(); self.next()
                a = N("in", a=a, b=self.cmp(), neg=True)
            else:
                return a

    def cmp(self):
        a = self.bor()
        while self.peek().v in ("<", ">", "<=", ">=", "==", "!=") and self.peek().k == "op":
            op = self.next().v
            a = N("bin", op=op, a=a, b=self.bor())
        return a

    def bor(self):
        a = self.bxor()
        while self.peek().v == "|" and self.peek().k == "op":
            self.next()
            a = N("bin", op="|", a=a, b=self.bxor())
        return a

    def bxor(self):
        a = self.band()
        while self.peek().v == "^":
            self.next()
            a = N("bin", op="^", a=a, b=self.band())
        return a

    def band(self):
        a = self.shift()
        while self.peek().v == "&" and self.peek().k == "op":
            self.next()
            a = N("bin", op="&", a=a, b=self.shift())
        return a

    def shift(self):
        a = self.add()
        while self.peek().v in ("<<", ">>"):
            op = self.next().v
            a = N("bin", op=op, a=a, b=self.add())
        return a

    def add(self):
        a = self.mul()
        while self.peek().v in ("+", "-") and self.peek().k == "op":
            op = self.next().v
            a = N("bin", op=op, a=a, b=self.mul())
        return a

    def mul(self):
        a = self.unary()
        while self.peek().v in ("*", "/", "%") and self.peek().k == "op":
            op = self.next().v
            a = N("bin", op=op, a=a, b=self.unary())
        return a

    def unary(self):
        if self.peek().v in ("-", "+", "~") and self.peek().k == "op":
            op = self.next().v
            return N("un", op=op, a=self.unary())
        return self.postfix()

    def postfix(self):
        a = self.atom()
        while True:
            if self.accept("."):
                name = self.next().v
                if self.peek().v == "(":
                    args = self.args("(", ")")
                    a = N("mcall", obj=a, name=name, args=args)
                else:
                    a = N("attr", obj=a, name=name)
            elif self.peek().v == "(" and a.kind == "name":
                args = self.args("(", ")")
                a = N("call", name=a.name, args=args)
            elif self.peek().v == "[":
                self.next()
                idx = self.expr()
                self.expect("]")
                a = N("index", obj=a, idx=idx)
            else:
                return a

    def args(self, o, c):
        self.expect(o)
        out = []
        while self.peek().v != c:
            out.append(self.expr())
            if not self.accept(","):
                break
        self.expect(c)
        return out

    def atom(self):
        t = self.next()
        if t.k == "num":
            return N("num", v=t.v)
        if t.k == "str":
            return N("str", v=t.v)
        if t.v == "(":
            e = self.expr()
            self.expect(")")
            return N("paren", a=e)
        if t.v == "[":
            items = []
            while self.peek().v != "]":
                items.append(self.expr())
                if not self.accept(","):
                    break
            self.expect("]")
            return N("list", items=items)
        if t.v == "{":
            items = []
            while self.peek().v != "}":
                if self.peek().k == "id" and self.peek(1).v == "=":
                    k = N("str", v='"' + self.next().v + '"'); self.next()
                else:
                    k = self.expr(); self.expect(":")
                items.append((k, self.expr()))
                if not self.accept(","):
                    break
            self.expect("}")
            return N("dict", items=items)
        if t.k == "id":
            if t.v == "func":   # lambda: left as a marker (hand-ported)
                raise SyntaxError("lambda")
            return N("name", name=t.v)
        raise SyntaxError(f"unexpected {t.v!r} in {' '.join(x.v for x in self.t)}")


# ------------------------------------------------------------------ emitter
GD_FUNCS = {   # name -> return type (sim/Gd.cs has them with Godot's semantics)
    "sin": D, "cos": D, "tan": D, "atan": D, "atan2": D, "asin": D, "acos": D, "exp": D, "log": D, "tanh": D,
    "pow": D, "sqrt": D, "maxf": D, "minf": D, "clampf": D, "absf": D, "signf": D, "lerpf": D, "move_toward": D,
    "floor": D, "ceil": D, "round": D, "wrapf": D, "smoothstep": D, "rad_to_deg": D, "deg_to_rad": D, "fmod": D,
    "fposmod": D, "maxi": I, "mini": I, "clampi": I, "absi": I, "signi": I, "roundi": I, "floori": I,
    "roundf": D, "floorf": D, "ceilf": D, "ceili": I, "is_same": B,
    "is_nan": B, "is_finite": B, "is_inf": B, "is_zero_approx": B, "is_equal_approx": B, "randf": D,
    "randf_range": D, "str": S,
}


class Ctx:
    def __init__(self, members, funcs, consts):
        self.members = members      # name -> type
        self.funcs = funcs          # name -> (ret, [param types], static)
        self.consts = consts
        self.locals = [{}]

    def push(self):
        self.locals.append({})

    def pop(self):
        self.locals.pop()

    def declare(self, n, t):
        self.locals[-1][n] = t

    def is_local(self, n):
        return any(n in sc for sc in self.locals)

    def lookup(self, n):
        for sc in reversed(self.locals):
            if n in sc:
                return sc[n]
        if n in self.members:
            return self.members[n]
        if n in self.consts:
            return self.consts[n]
        return None


INP_BOOL = {"hop", "sprint", "pad", "ws_air"}
DICT_NUM_KEYS = set()   # filled by the caller if needed


class Em:
    def __init__(self, ctx):
        self.c = ctx

    # returns (code, type)
    def e(self, n, want=None):
        k = n.kind
        if k == "num":
            v = n.v
            if v.startswith("0x"):
                return v, I
            if "." in v or "e" in v or "E" in v:
                if v.endswith("."):
                    v += "0"
                if v.startswith("."):
                    v = "0" + v
                if "." not in v:   # 1e-6 style: C# reads it as double already
                    return v, D
                return v, D
            return v, I
        if k == "str":
            s = n.v
            if s.startswith("'"):
                s = '"' + s[1:-1].replace('"', '\\"') + '"'
            return s, S
        if k == "paren":
            c, t = self.e(n.a, want)
            return f"({c})", t
        if k == "name":
            return self.name(n.name)
        if k == "un":
            c, t = self.e(n.a, want)
            if n.op == "-":
                return f"-{c}", t
            return f"{n.op}{c}", t
        if k == "not":
            c, t = self.e(n.a)
            return f"!{self.truthy(c, t)}", B
        if k == "bin":
            return self.binop(n)
        if k == "tern":
            cc, ct = self.e(n.c)
            a, at = self.e(n.a, want)
            b, bt = self.e(n.b, want)
            t = at
            if at != bt:
                if is_num(at) and is_num(bt):
                    t = D
                    a = self.to_d(a, at); b = self.to_d(b, bt)
                elif at == ANY or at is None:
                    t = bt
                elif bt == ANY or bt is None:
                    t = at
            if want == D and t == I:
                a = self.to_d(a, at); b = self.to_d(b, bt); t = D
            return f"({self.truthy(cc, ct)} ? {a} : {b})", t
        if k == "in":
            a, at = self.e(n.a)
            b, bt = self.e(n.b)
            r = f"Gd.in_({a}, {b})"
            return (f"!{r}" if n.neg else r), B
        if k == "list":
            items = [self.e(x) for x in n.items]
            ts = {t for _, t in items}
            if ts <= {D, I} and ts:
                return "new List<double> { " + ", ".join(self.to_d(c, t) for c, t in items) + " }", "List<double>"
            if ts == {V3}:
                return "new List<V3> { " + ", ".join(c for c, _ in items) + " }", "List<V3>"
            if ts == {V2}:
                return "new List<V2> { " + ", ".join(c for c, _ in items) + " }", "List<V2>"
            if ts == {S}:
                return "new List<string> { " + ", ".join(c for c, _ in items) + " }", "List<string>"
            return "new List<object> { " + ", ".join(c for c, _ in items) + " }", LIST
        if k == "dict":
            parts = []
            for kk, vv in n.items:
                kc, _ = self.e(kk)
                vc, vt = self.e(vv)
                parts.append("{ " + kc + ", " + vc + " }")
            return "new GdDict { " + ", ".join(parts) + " }", DICT
        if k == "index":
            o, ot = self.e(n.obj)
            ic, it = self.e(n.idx)
            if ot == "RideParams":
                return f"{o}.f({ic})", D
            if ot == DICT:
                return f"{o}.get_o({ic}, null)", ANY
            el = {"List<double>": D, "double[]": D, "float[]": D, "List<V3>": V3, "List<string>": S, "List<long>": I,
                  "long[]": I, "V3[]": V3, "List<GdDict>": DICT}.get(ot, ANY)
            ic2 = ic if re.fullmatch(r"\d+", ic) else f"(int)({ic})"
            if ot == "float[]":
                return f"(double){o}[{ic2}]", D
            return f"{o}[{ic2}]", el
        if k == "attr":
            return self.attr(n)
        if k == "call":
            return self.call(n)
        if k == "mcall":
            return self.mcall(n)
        raise SyntaxError(f"node {k}")

    def to_d(self, c, t):
        if t == I:
            if re.fullmatch(r"-?\d+", c):
                return c + ".0"
            return f"(double)({c})"
        return c

    def truthy(self, c, t):
        if t == B:
            return c
        if t in (D, I):
            return f"({c} != 0)"
        if t == S:
            return f"({c} != \"\")"
        if t in (DICT, LIST, "List<double>", "List<GdDict>", "List<string>", "List<V3>"):
            return f"Gd.truthy({c})"
        return f"Gd.to_b({c})"

    def name(self, n):
        if n == "true" or n == "false":
            return n, B
        if n == "null":
            return "null", ANY
        if n in ("NAN", "INF", "PI", "TAU"):
            return n, D
        if n == "self":
            return "this", "BikeSim"
        t = self.c.lookup(n)
        if self.c.is_local(n) and (n in self.c.members or n in self.c.consts):
            return "l_" + n, t
        if t is None:
            if n in self.c.funcs:
                return cs_name(n), "func"
            return cs_name(n), ANY
        return cs_name(n), t

    def binop(self, n):
        op = n.op
        if op in ("&&", "||"):
            a, at = self.e(n.a)
            b, bt = self.e(n.b)
            return f"{self.truthy(a, at)} {op} {self.truthy(b, bt)}", B
        a, at = self.e(n.a)
        b, bt = self.e(n.b)
        if op in ("<", ">", "<=", ">=", "==", "!="):
            if at == S and bt == S:
                return f"{a} {op} {b}", B
            return f"{a} {op} {b}", B
        if op == "%":
            if at == S:   # string formatting
                if n.b.kind == "list":
                    args = ", ".join(self.box(self.e(x)) for x in n.b.items)
                else:
                    args = self.box((b, bt))
                return f"Gd.fmt({a}, {args})", S
            if at == I and bt == I:
                return f"{a} % {b}", I
            return f"Gd.fmod({a}, {b})", D
        # vectors
        if at in (V2, V3) or bt in (V2, V3):
            vt = at if at in (V2, V3) else bt
            return f"{a} {op} {b}", vt
        if at == S or bt == S:
            return f"{a} {op} {b}", S
        if at == I and bt == I:
            return f"{a} {op} {b}", I
        if at == B or bt == B:
            # GDScript allows bool arithmetic only after a cast; treat as number
            a = f"({a} ? 1 : 0)" if at == B else a
            b = f"({b} ? 1 : 0)" if bt == B else b
        return f"{a} {op} {b}", D

    def box(self, ct):
        c, t = ct
        return c

    def attr(self, n):
        obj = n.obj
        name = n.name
        # T.key  (Tune values)
        if obj.kind == "name" and obj.name == "T":
            return f'T.f("{name}")', D
        if obj.kind == "name" and obj.name == "inp":
            if name in INP_BOOL:
                return f'inp.b("{name}")', B
            return f'inp.f("{name}")', D
        if obj.kind == "name" and obj.name in ("Vector2", "Vector3"):
            vt = "V2" if obj.name == "Vector2" else "V3"
            return f"{vt}.{name}", vt
        if obj.kind == "name" and obj.name == "FastNoiseLite":
            return f"Noise2S.{name}", I
        if obj.kind == "name" and obj.name == "Ragdoll":
            return f"Ragdoll_{name}", I
        if obj.kind == "name" and obj.name == "SuspSetup":
            return f"SuspMath.{name}", D
        o, ot = self.e(obj)
        if ot in (V2, V3):
            if name in ("x", "y", "z"):
                return f"{o}.{name}", D
        if ot == DICT:
            return f'{o}.f("{name}")', D
        if ot == "IRideHost":
            t = {"terrain": "IGround", "susp": "ISusp", "ragdoll": ANY, "getup_anim": ANY, "pedal_a0": "List<double>"}.get(name, ANY)
            return f"{o}.{name}", t
        if ot == "ISusp":
            t = {"has_r": B, "has_f": B, "wheels_follow": B, "axis": V3, "F": DICT, "R": DICT}.get(name, ANY)
            return f"{o}.{name}", t
        return f"{o}.{cs_name(name)}", ANY

    def call(self, n):
        name = n.name
        args = n.args
        if name in ("float",):
            c, t = self.e(args[0])
            if t == I:
                return f"(double)({c})", D
            if t in (D,):
                return c, D
            return f"Gd.to_f({c})", D
        if name == "int":
            c, t = self.e(args[0])
            if t == I:
                return c, I
            return f"Gd.to_i({c})", I
        if name == "bool":
            c, t = self.e(args[0])
            if t == B:
                return c, B
            return f"Gd.to_b({c})", B
        if name == "str":
            c, t = self.e(args[0])
            return f"Gd.str({c})", S
        if name == "len":
            c, t = self.e(args[0])
            return f"Gd.len({c})", I
        if name == "PackedFloat64Array":
            return "new double[0]", "double[]"
        if name == "PackedFloat32Array":
            return "new float[0]", "float[]"
        if name in ("Vector2", "Vector3"):
            cs = [self.e(a)[0] for a in args]
            t = "V2" if name == "Vector2" else "V3"
            return f"new {t}({', '.join(cs)})", t
        if name == "print":
            parts = [self.e(a) for a in args]
            return "host.log(" + " + ".join(c if t == S else f"Gd.str({c})" for c, t in parts) + ")", VOID
        if name == "range":
            cs = [self.e(a)[0] for a in args]
            return f"Gd.range({', '.join(cs)})", "IEnumerable<int>"
        if name == "randf":
            return "Gd.randf()", D
        if name in GD_FUNCS:
            want_d = GD_FUNCS[name] == D
            cs = []
            for a in args:
                c, t = self.e(a)
                cs.append(c)
            return f"{name}({', '.join(cs)})", GD_FUNCS[name]
        if name in self.c.funcs:
            ret, ptypes, _st = self.c.funcs[name]
            cs = []
            for i, a in enumerate(args):
                c, t = self.e(a, ptypes[i] if i < len(ptypes) else None)
                if i < len(ptypes) and ptypes[i] == D and t == I:
                    c = self.to_d(c, t)
                cs.append(c)
            return f"{cs_name(name)}({', '.join(cs)})", ret
        cs = [self.e(a)[0] for a in args]
        return f"{name}({', '.join(cs)})", ANY

    def mcall(self, n):
        obj, name, args = n.obj, n.name, n.args
        if obj.kind == "name" and obj.name == "T" and name == "get":
            k, _ = self.e(args[0])
            d, dt = self.e(args[1]) if len(args) > 1 else ("0.0", D)
            return f"T.get({k}, {self.to_d(d, dt)})", D
        if obj.kind == "name" and obj.name == "Tune" and False:
            pass
        if obj.kind == "attr" and obj.obj.kind == "name" and obj.obj.name == "Tune" and obj.name == "v" and name == "get":
            k, _ = self.e(args[0])
            d, dt = self.e(args[1])
            return f"RideParams.global.get({k}, {self.to_d(d, dt)})", D
        if obj.kind == "name" and obj.name == "inp" and name == "get":
            k, _ = self.e(args[0])
            d, dt = self.e(args[1]) if len(args) > 1 else ("0.0", D)
            if dt == B:
                return f"inp.get_b({k}, {d})", B
            return f"inp.get({k}, {self.to_d(d, dt)})", D
        if obj.kind == "name" and obj.name == "Env":
            cs = [self.e(a)[0] for a in args]
            return f"Env.{name}({', '.join(cs)})", S
        if obj.kind == "name" and obj.name == "SuspSetup":
            cs = [self.e(a)[0] for a in args]
            return f"SuspMath.{name}({', '.join(cs)})", D
        if obj.kind == "name" and obj.name in ("Time", "Engine"):
            cs = [self.e(a)[0] for a in args]
            return f"host.{name}({', '.join(cs)})", I
        if obj.kind == "name" and obj.name == "CrashLog":
            cs = [self.e(a)[0] for a in args]
            return f"host.crashlog_{name}({', '.join(cs)})", VOID
        if obj.kind == "name" and name == "new" and obj.name in ("FastNoiseLite", "RandomNumberGenerator", "PackedFloat32Array", "PackedFloat64Array"):
            cls = {"FastNoiseLite": "Noise2S", "RandomNumberGenerator": "Pcg32"}.get(obj.name)
            if cls:
                return f"new {cls}()", cls
        if obj.kind == "name" and obj.name == "BikePhysics":
            cs = [self.e(a)[0] for a in args]
            return f"{name}({', '.join(cs)})", self.c.funcs.get(name, (ANY,))[0]
        o, ot = self.e(obj)
        cs = [self.e(a) for a in args]
        ca = [c for c, _ in cs]
        if ot in (V2, V3):
            rt = {"length": D, "length_squared": D, "dot": D, "normalized": ot, "cross": (D if ot == V2 else V3),
                  "distance_to": D, "limit_length": ot}.get(name, ANY)
            return f"{o}.{name}({', '.join(ca)})", rt
        if ot == DICT:
            if name == "get":
                d, dt = cs[1] if len(cs) > 1 else ("null", ANY)
                if dt == B:
                    return f"{o}.get_b({ca[0]}, {d})", B
                if dt in (D, I):
                    return f"{o}.get_f({ca[0]}, {self.to_d(d, dt)})", D
                if dt == S:
                    return f"{o}.get_s({ca[0]}, {d})", S
                return f"{o}.get_o({ca[0]}, {d})", ANY
            if name == "has":
                return f"{o}.has({ca[0]})", B
            if name == "is_empty":
                return f"({o}.Count == 0)", B
            if name == "keys":
                return f"{o}.keys()", "List<string>"
            if name == "clear":
                return f"{o}.Clear()", VOID
            if name == "erase":
                return f"{o}.Remove({ca[0]})", VOID
        if ot in ("List<double>", "List<object>", "List<string>", "List<V3>", "List<GdDict>", LIST, "double[]", "float[]"):
            m = {"size": ("Count" if ot.startswith("List") else "Length", I), "append": ("Add", VOID), "clear": ("Clear", VOID),
                 "push_back": ("Add", VOID), "pop_front": ("PopFront", ANY), "is_empty": ("IsEmpty", B), "resize": ("Resize", VOID),
                 "has": ("Contains", B)}.get(name)
            if m:
                if m[0] in ("Count", "Length"):
                    return f"{o}.{m[0]}", I
                if m[0] == "PopFront":
                    return f"Gd.pop_front({o})", ANY
                if m[0] == "IsEmpty":
                    return f"({o}.Count == 0)", B
                if m[0] == "Resize":
                    return f"Gd.resize(ref {o}, {ca[0]})", VOID
                return f"{o}.{m[0]}({', '.join(ca)})", m[1]
        if ot == "IGround":
            rt = {"height": D, "deck_height": D, "top_height": D, "mesh_height": D, "surface": I, "jump_mask": D,
                  "colliders_near": "List<GdDict>", "jump": ANY}.get(name, ANY)
            return f"{o}.{name}({', '.join(ca)})", rt
        if ot == "IRideHost":
            rt = {"msg_idle": B, "smash": B, "has_method": B}.get(name, VOID)
            return f"{o}.{name}({', '.join(ca)})", rt
        if ot == "ISusp":
            return f"{o}.{name}({', '.join(ca)})", VOID
        if ot == "Noise2S":
            return f"{o}.{name}({', '.join(ca)})", D
        if ot == "Pcg32":
            return f"{o}.{name}({', '.join(ca)})", D
        if ot == S:
            if name == "begins_with":
                return f"{o}.StartsWith({ca[0]})", B
            if name == "join":
                return f"string.Join({o}, {ca[0]})", S
        return f"{o}.{name}({', '.join(ca)})", ANY


# ------------------------------------------------------------------ type parsing
def gd_type(t):
    t = t.strip()
    return {"float": D, "int": I, "bool": B, "String": S, "Vector2": V2, "Vector3": V3, "Dictionary": DICT,
            "Array": "List<double>", "PackedFloat64Array": "double[]", "PackedFloat32Array": "float[]", "Array[Vector3]": "List<V3>",
            "void": VOID, "Transform3D": "Transform3D", "Basis": "Basis", "FastNoiseLite": "Noise2S",
            "RandomNumberGenerator": "Pcg32", "PackedVector3Array": "List<V3>", "Callable": ANY}.get(t, ANY)


# ------------------------------------------------------------------ statements
def logical_lines(src):
    """join continuation lines (open brackets / trailing backslash); keep (indent, code, comment, lineno)"""
    out = []
    buf = ""
    depth = 0
    start = 0
    indent = 0
    comments = []
    for no, raw in enumerate(src.split("\n"), 1):
        code, com = split_comment(raw.rstrip("\r"))
        if not buf:
            if not code.strip():
                out.append((None, "", com, no))
                continue
            indent = len(code) - len(code.lstrip("\t"))
            start = no
            comments = []
        if com is not None:
            comments.append(com)
        buf += (" " if buf else "") + code.strip()
        for ch in code:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
        if buf.endswith("\\"):
            buf = buf[:-1]
            continue
        if depth > 0:
            continue
        out.append((indent, buf, " / ".join(comments) if comments else None, start))
        buf = ""
        depth = 0
    return out


def split_semis(code):
    """split a line at top-level ';'"""
    parts, depth, q, cur = [], 0, None, ""
    for c in code:
        if q:
            cur += c
            if c == q:
                q = None
            continue
        if c in "\"'":
            q = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == ";" and depth == 0:
            parts.append(cur.strip())
            cur = ""
            continue
        cur += c
    if cur.strip():
        parts.append(cur.strip())
    return parts


def top_colon(code):
    """index of the block colon (top level, not in a dict / slice / type annotation after var)"""
    depth, q = 0, None
    for i, c in enumerate(code):
        if q:
            if c == q:
                q = None
            continue
        if c in "\"'":
            q = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == ":" and depth == 0 and code[i + 1:i + 2] != "=":
            return i
    return -1


class Translator:
    def __init__(self, src, manual):
        self.src = src
        self.manual = set(manual)
        self.lines = logical_lines(src)
        self.members = {}
        self.consts = {}
        self.funcs = {}
        self.member_decls = []   # (name, type, init code, comment)
        self.out = []
        self.errors = []

    # pass 1: members, consts, function signatures
    def scan(self):
        for ind, code, com, no in self.lines:
            if ind != 0 or not code:
                continue
            for part in split_semis(code):
                m = re.match(r"(static\s+)?func\s+(\w+)\s*\((.*)\)\s*(->\s*([\w\[\]]+))?\s*:\s*(.*)$", part)
                if m:
                    params = self.params(m.group(3))
                    ret = gd_type(m.group(5)) if m.group(5) else None
                    self.funcs[m.group(2)] = [ret, [t for _, t, _ in params], bool(m.group(1))]
                    continue
                m = re.match(r"(?:static\s+)?(var|const)\s+(\w+)\s*(:\s*([\w\[\]]+))?\s*(:?=)?\s*(.*)$", part)
                if m:
                    name = m.group(2)
                    t = gd_type(m.group(4)) if m.group(4) else None
                    init = m.group(6).strip() if m.group(5) else ""
                    if t is None or t == ANY and not m.group(4):
                        t = self.guess(init)
                    if m.group(1) == "const":
                        self.consts[name] = t
                    else:
                        self.members[name] = t
                    self.member_decls.append((m.group(1), name, t, init, com, no))
        # fix-ups known from the file
        for n, t in (("cogs", "List<double>"), ("_tapes_seen", "List<GdDict>"), ("_cb_hit", "double[]"),
                     ("_lean_hist", "List<double>"), ("_jp_prev", "List<object>"), ("joint_rock", ANY),
                     ("crash_sim", "ICrashSim"), ("host", "IRideHost"), ("T", "RideParams"), ("sus", "SusSetup"),
                     ("prof", "Dictionary<string, long>"), ("_eb", DICT), ("_eb_n", DICT), ("_risk", DICT), ("_jp_n", DICT),
                     ("_wg_raw", "float[]"), ("_su", "double[]"), ("crash_K", ANY), ("crash_RK", ANY),
                     ("joint_rock", DICT)):
            if n in self.members:
                self.members[n] = t

    def refine(self):
        ctx = Ctx(self.members, self.funcs, self.consts)
        fixed = {"cogs", "_tapes_seen", "_cb_hit", "_lean_hist", "_jp_prev", "joint_rock", "crash_sim", "host", "T", "sus",
                 "prof", "_eb", "_eb_n", "_risk", "_jp_n", "_wg_raw", "_su", "crash_K", "crash_RK"}
        for _ in range(3):
            for kind, name, t, init, com, no in self.member_decls:
                if name in fixed or not init:
                    continue
                table = self.consts if kind == "const" else self.members
                cur = table.get(name)
                if cur in (ANY, LIST, None) or (cur == I and "." in init):
                    try:
                        _, it = self.ex(ctx, init)
                        if it not in (ANY, None, VOID, "func"):
                            table[name] = it
                    except Exception:
                        pass

    def guess(self, init):
        init = init.strip()
        if not init:
            return ANY
        if re.fullmatch(r"-?\d+", init):
            return I
        if re.fullmatch(r"-?(\d+\.\d*|\.\d+|\d+)([eE][+-]?\d+)?", init) or init in ("NAN", "INF", "-INF", "PI", "TAU"):
            return D
        if init in ("true", "false"):
            return B
        if init.startswith('"'):
            return S
        if init.startswith("Vector2"):
            return V2
        if init.startswith("Vector3"):
            return V3
        if init.startswith("{"):
            return DICT
        if init.startswith("["):
            return LIST
        if init.startswith("Env.") and "!=" in init:
            return B
        if init.startswith("Env."):
            return S
        if init.startswith("PackedFloat64Array"):
            return "double[]"
        if init.startswith("PackedFloat32Array"):
            return "float[]"
        if init.startswith("RandomNumberGenerator"):
            return "Pcg32"
        if init.startswith("Transform3D"):
            return "Transform3D"
        if "float(" in init or init.startswith("G ") or "*" in init or "/" in init:
            return D
        return ANY

    def params(self, s):
        out = []
        for p in [x.strip() for x in s.split(",") if x.strip()]:
            m = re.match(r"(\w+)\s*(:\s*([\w\[\]]+))?\s*(:?=\s*(.*))?$", p)
            if not m:
                continue
            t = gd_type(m.group(3)) if m.group(3) else None
            dflt = m.group(5)
            if t is None:
                t = self.guess(dflt) if dflt else ANY
                if t == ANY and m.group(1) == "inp":
                    t = "RideInput"
            if m.group(1) == "inp":
                t = "RideInput"
            if m.group(1) == "terrain" and t in (ANY, None):
                t = "IGround"
            out.append((m.group(1), t, dflt))
        return out

    def ex(self, ctx, code, want=None):
        toks = lex(code)
        p = Parser(toks)
        n = p.expr()
        if not p.at_end():
            raise SyntaxError(f"trailing tokens in {code!r}: {p.peek().v!r}")
        return Em(ctx).e(n, want)

    # pass 2: functions
    def translate(self):
        self.scan()
        self.refine()
        ctx = Ctx(self.members, self.funcs, self.consts)
        o = self.out
        i = 0
        L = self.lines
        while i < len(L):
            ind, code, com, no = L[i]
            if ind != 0 or not code:
                i += 1
                continue
            m = re.match(r"(static\s+)?func\s+(\w+)\s*\((.*)\)\s*(->\s*([\w\[\]]+))?\s*:\s*(.*)$", code)
            if not m:
                i += 1
                continue
            name = m.group(2)
            # body = following lines with indent > 0
            j = i + 1
            body = []
            while j < len(L) and (L[j][0] is None or L[j][0] > 0):
                body.append(L[j])
                j += 1
            # trim trailing blanks
            while body and body[-1][0] is None:
                body.pop()
            if name in self.manual:
                o.append(f"\t\t// {name}: hand-ported (BikeSim.Manual.cs)")
                i = j
                continue
            params = self.params(m.group(3))
            ret = self.funcs[name][0]
            ctx.locals = [{}]
            for pn, pt, _ in params:
                ctx.declare(pn, pt)
            # infer an unannotated return type from the first 'return expr'
            if ret is None:
                ret = VOID
                for bl in body:
                    if bl[1] and bl[1].startswith("return ") :
                        try:
                            _, rt = self.ex(ctx, bl[1][7:])
                            ret = rt
                        except Exception:
                            ret = ANY
                        break
                self.funcs[name][0] = ret
            ps = []
            for pn, pt, dflt in params:
                d = ""
                if dflt is not None:
                    try:
                        dc, dtp = self.ex(ctx, dflt)
                        if pt == D and dtp == I:
                            dc += ".0"
                        d = " = " + dc
                    except Exception as e:
                        d = f" /* {dflt} */"
                ps.append(f"{self.cs_t(pt)} {cs_name(pn)}{d}")
            st = "static " if m.group(1) else ""
            o.append("")
            o.append(f"\t\t{'public' if not name.startswith('_') else 'private'} {st}{self.cs_t(ret)} {cs_name(name)}({', '.join(ps)})")
            o.append("\t\t{")
            if m.group(6).strip():   # one-line func
                body = [(1, m.group(6).strip(), None, no)] + body
            try:
                self.block(ctx, body, 1, ret)
            except Exception as e:
                self.errors.append(f"{name} (line {no}): {e}")
                o.append(f"\t\t\t#error translate {name}: {e}")
            o.append("\t\t}")
            i = j
        return o

    def lname(self, ctx, n):
        return "l_" + n if (n in ctx.members or n in ctx.consts) else cs_name(n)

    def cs_t(self, t):
        if t is None:
            return "object"
        return {"Transform3D": "object", "Basis": "object", "IEnumerable<int>": "IEnumerable<int>"}.get(t, t)

    def block(self, ctx, lines, base, ret):
        """translate lines (indent >= base) into C# at nesting depth base"""
        o = self.out
        k = 0
        ctx.push()
        while k < len(lines):
            ind, code, com, no = lines[k]
            if ind is None:
                if com is not None:
                    o.append("\t" * (base + 2) + "//" + com.rstrip())
                k += 1
                continue
            pad = "\t" * (base + 2)
            if com is not None and not code:
                o.append(pad + "//" + com.rstrip())
            # gather the child block
            j = k + 1
            child = []
            while j < len(lines) and (lines[j][0] is None or lines[j][0] > ind):
                child.append(lines[j])
                j += 1
            while child and child[-1][0] is None:
                child.pop()
            # trailing blank lines that belonged to the parent: keep them out of the child
            self.stmt(ctx, code, com, child, ind, base, ret, lines, k)
            k = j
        ctx.pop()

    def stmt(self, ctx, code, com, child, ind, base, ret, lines, k):
        o = self.out
        pad = "\t" * (base + 2)
        tail = f"   //{com.rstrip()}" if com else ""
        kw = re.match(r"(if|elif|else|for|while)\b", code)
        if kw:
            word = kw.group(1)
            ci = top_colon(code)
            if word == "else":
                head = "else"
                inline = code[ci + 1:].strip()
            else:
                cond = code[len(word):ci].strip()
                inline = code[ci + 1:].strip()
                if word in ("if", "elif"):
                    c, t = self.ex(ctx, cond)
                    head = ("if" if word == "if" else "else if") + f" ({Em(ctx).truthy(c, t)})"
                elif word == "while":
                    c, t = self.ex(ctx, cond)
                    head = f"while ({Em(ctx).truthy(c, t)})"
                else:
                    m = re.match(r"(\w+)(\s*:\s*\w+)?\s+in\s+(.*)$", cond)
                    var, it = m.group(1), m.group(3)
                    head = None
                    rm = re.match(r"range\((.*)\)$", it)
                    if rm:
                        args = [self.ex(ctx, a)[0] for a in split_args(rm.group(1))]
                        v_ = self.lname(ctx, var)
                        if len(args) == 1:
                            head = f"for (long {v_} = 0; {v_} < {args[0]}; {v_}++)"
                        elif len(args) == 2:
                            head = f"for (long {v_} = {args[0]}; {v_} < {args[1]}; {v_}++)"
                        else:
                            head = f"foreach (long {v_} in Gd.range({', '.join(args)}))"
                        vt = I
                    else:
                        c, t = self.ex(ctx, it)
                        if t == I:
                            v_ = self.lname(ctx, var)
                            head = f"for (long {v_} = 0; {v_} < {c}; {v_}++)"
                            vt = I
                        else:
                            el = {"List<double>": D, "List<GdDict>": DICT, "List<string>": S, "List<V3>": V3, "List<V2>": V2,
                                  "double[]": D, "List<object>": ANY}.get(t, ANY)
                            if t == DICT:
                                c += ".Keys"; el = S
                            head = f"foreach (var {self.lname(ctx, var)} in {c})"
                            vt = el
                    ctx.push()
                    ctx.declare(var, vt)
            o.append(pad + head + tail)
            o.append(pad + "{")
            if inline:
                for part in split_semis(inline):
                    self.simple(ctx, part, base + 1, ret, None)
            if child:
                self.block(ctx, child, base + 1, ret)
            o.append(pad + "}")
            if word == "for":
                ctx.pop()
            return
        for idx, part in enumerate(split_semis(code)):
            self.simple(ctx, part, base, ret, com if idx == 0 else None)

    def simple(self, ctx, code, base, ret, com):
        o = self.out
        pad = "\t" * (base + 2)
        tail = f"   //{com.rstrip()}" if com else ""
        if code == "pass":
            o.append(pad + ";" + tail)
            return
        if code in ("break", "continue"):
            o.append(pad + code + ";" + tail)
            return
        if code == "return" or code.startswith("return "):
            e = code[6:].strip()
            if not e:
                o.append(pad + "return;" + tail)
            else:
                c, t = self.ex(ctx, e, ret)
                if ret == D and t == I:
                    c = Em(ctx).to_d(c, t)
                o.append(pad + f"return {c};" + tail)
            return
        m = re.match(r"var\s+(\w+)\s*(:\s*([\w\[\]]+))?\s*(:?=)?\s*(.*)$", code)
        if m:
            name = m.group(1)
            t = gd_type(m.group(3)) if m.group(3) else None
            init = m.group(5).strip() if m.group(4) else ""
            if init:
                c, it = self.ex(ctx, init, t)
                if t is None or (t in (LIST, ANY) and it not in (ANY, None, VOID)):
                    t = it
                elif t == "List<double>" and it == "List<GdDict>":
                    t = it
                elif it == ANY and t not in (ANY, None):
                    c = f"Gd.as_<{self.cs_t(t)}>({c})" if t not in (D, I, B, S) else {D: f"Gd.to_f({c})", I: f"Gd.to_l({c})", B: f"Gd.to_b({c})", S: f"Gd.str({c})"}[t]
                if t == D and it == I:
                    c = Em(ctx).to_d(c, it)
                if t in (ANY, None) and init.startswith("host.terrain"):
                    t = "IGround"
                ctx.declare(name, t)
                ctype = self.cs_t(t) if t not in (ANY, None) else "var"
                if ctype == "object" and it not in (ANY, None):
                    ctype = "var"
                o.append(pad + f"{ctype} {self.lname(ctx, name)} = {c};" + tail)
            else:
                ctx.declare(name, t)
                dv = {D: "0.0", I: "0", B: "false", S: '""', V2: "V2.ZERO", V3: "V3.ZERO"}.get(t, "default")
                o.append(pad + f"{self.cs_t(t)} {self.lname(ctx, name)} = {dv};" + tail)
            return
        # assignment
        m = re.match(r"(.+?)\s*(=|\+=|-=|\*=|/=|%=|\|=|&=)\s*(.+)$", code)
        if m and not re.search(r"[=!<>]=", m.group(1) + m.group(2)) and top_assign(code):
            lhs, op, rhs = m.group(1), m.group(2), m.group(3)
            lc, lt = self.ex(ctx, lhs)
            rc, rt = self.ex(ctx, rhs, lt)
            if lt == D and rt == I:
                rc = Em(ctx).to_d(rc, rt)
            if lt == I and rt == D and op == "=":
                rc = f"(long)({rc})"
            if ".get_o(" in lc and lc.endswith(", null)"):   # a dictionary element
                obj_, key_ = lc[:lc.rindex(".get_o(")], lc[lc.rindex(".get_o(") + 7:-7]
                if op == "=":
                    o.append(pad + f"{obj_}.set({key_}, {rc});" + tail)
                else:
                    o.append(pad + f"{obj_}.set({key_}, {obj_}.get_f({key_}, 0.0) {op[0]} {rc});" + tail)
                return
            if lc.startswith("(double)") and lt == D:   # a float32 array element (PackedFloat32Array)
                o.append(pad + f"{lc[len('(double)'):]} {op} (float)({rc});" + tail)
                return
            # T / dict element assignment
            if re.match(r'T\.f\("', lc):
                o.append(pad + f'T["{lhs.split(".")[1]}"] = {rc};' + tail)
                return
            mm = re.match(r'(.+)\.f\((.+)\)$', lc)
            if mm and lt == D and op in ("=", "+=", "-="):
                # dictionary element: d.f(k) = v  ->  d[k] = v
                if op == "=":
                    o.append(pad + f"{mm.group(1)}[{mm.group(2)}] = {rc};" + tail)
                else:
                    o.append(pad + f"{mm.group(1)}[{mm.group(2)}] = {lc} {op[0]} {rc};" + tail)
                return
            o.append(pad + f"{lc} {op} {rc};" + tail)
            return
        c, t = self.ex(ctx, code)
        o.append(pad + c + ";" + tail)


def top_assign(code):
    depth, q = 0, None
    for i, c in enumerate(code):
        if q:
            if c == q:
                q = None
            continue
        if c in "\"'":
            q = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "=" and depth == 0:
            prev = code[i - 1] if i else ""
            nxt = code[i + 1] if i + 1 < len(code) else ""
            if prev in "=!<>" or nxt == "=":
                continue
            return True
    return False


def split_args(s):
    parts, depth, cur = [], 0, ""
    for c in s:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            parts.append(cur.strip()); cur = ""
            continue
        cur += c
    if cur.strip():
        parts.append(cur.strip())
    return parts


def main():
    src_path, out_path = sys.argv[1], sys.argv[2]
    manual = []
    members_out = None
    a = sys.argv[3:]
    for k, v in zip(a[::2], a[1::2]):
        if k == "--manual":
            manual = [x for x in v.split(",") if x]
        if k == "--members":
            members_out = v
    src = open(src_path, encoding="utf-8").read()
    tr = Translator(src, manual)
    body = tr.translate()
    ctx = Ctx(tr.members, tr.funcs, tr.consts)
    decl = []
    for kind, name, t, init, com, no in tr.member_decls:
        if name in tr.manual:
            continue
        t = tr.members.get(name, tr.consts.get(name, t))
        c = ""
        try:
            if init:
                cc, ct = tr.ex(ctx, init, t)
                if t == D and ct == I:
                    cc = Em(ctx).to_d(cc, ct)
                c = cc
        except Exception as e:
            c = f"default /* {init} : {e} */"
        tail = f"   //{com.rstrip()}" if com else ""
        cst = tr.cs_t(t)
        if name == "_wg_init":
            continue
        if name == "sus":
            c = "new SusSetup()"
        if name in ("crash_K", "crash_RK"):
            c = "null"
        if name == "_wg_raw":
            c = "new float[11]"
        if init.strip() == "[]" and cst.startswith("List<"):
            c = f"new {cst}()"
        if cst == "double[]" and c.startswith("new List<double>"):
            c = "new double[]" + c[len("new List<double>"):]
        if init.strip() == "{}" and cst == "GdDict":
            c = "new GdDict()"
        if kind == "const":
            if t in (D, I, B, S) and init and not init.startswith("["):
                decl.append(f"\t\tpublic const {cst} {cs_name(name)} = {c};{tail}")
            else:
                decl.append(f"\t\tpublic static readonly {cst} {cs_name(name)} = {c};{tail}")
        else:
            if not init:
                c = {D: "0.0", I: "0", B: "false", S: '""', V2: "V2.ZERO", V3: "V3.ZERO"}.get(t, "default")
            decl.append(f"\t\tpublic {cst} {cs_name(name)} = {c};{tail}")
    head = [
        "// GENERATED by godot/dev/port/gd2cs.py from scripts/bike/bike_physics.gd - do not edit by hand:",
        "// change the GDScript (or the translator / BikeSim.Manual.cs) and generate again.",
        "// Engine-free: nothing in godot/sim/ may reference the engine (checked by tools/sim_purity.ps1).",
        "#pragma warning disable CS0162, CS0168, CS0219, CS0414, CS1717",
        "using System;",
        "using System.Collections.Generic;",
        "using static Runout.Sim.Gd;",
        "",
        "namespace Runout.Sim",
        "{",
        "\tpublic partial class BikeSim",
        "\t{",
    ]
    open(out_path, "w", encoding="utf-8", newline="\n").write("\n".join(head + decl + body + ["\t}", "}", ""]))
    if members_out:
        json.dump({"members": {n: t for n, t in tr.members.items() if n not in manual}, "consts": tr.consts,
                   "funcs": {n: f for n, f in tr.funcs.items()}}, open(members_out, "w"), indent=1)
    for e in tr.errors:
        print("GD2CS", e)
    print(f"GD2CS wrote {out_path}: {len(decl)} members, {len(tr.funcs)} functions, {len(tr.errors)} errors")


if __name__ == "__main__":
    main()
