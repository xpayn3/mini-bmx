using System.Collections.Generic;
using UnityEngine;

namespace Runout.Game
{
    /// The drivetrain drawn as it works on a real bike: chain + rear derailleur, solved every frame by RearDerailleur (a
    /// port of the bike HDA's derailleur / chain solve) for whatever ring and cassette the build has (modular bikes).
    ///   - the derailleur is the SRAM Force eTap AXS model from the HDA (Art/Models/Bikes/rd_sram.glb, tools/
    ///     export_rd_sram.py) as its 6 rigid parts, posed by its own kinematics: B-knuckle set once by B-tension on the
    ///     biggest cog, the slant parallelogram carrying the top pulley into the cog's plane, the cage turning on the
    ///     top pulley's axle to close the chain; it rides on the seatstay (the hanger), so it moves with the suspension
    ///   - the chain: a FIXED number of links (cut big-big + 2, as a mechanic does), laid pin to pin round ring, cog
    ///     and both pulleys, travelling with the cranks; chain growth under compression swings the cage
    ///   - a shift: the mech moves at once (the motor), the chain climbs onto the new cog only as it travels (half a
    ///     turn of the cog): coasting with the cranks still, the shift waits
    ///   - the cage is sprung with a clutch, the runs are strings: bumps make the runs bow and the cage let chain out,
    ///     coasting the top run slaps the chainstay (RearDerailleur.Dynamics, the HDA's "reacting" section)
    /// dh.glb's frozen chain (swingarm) and frozen derailleur (seatstay) are cut out of its meshes.
    public sealed class BikeChain : MonoBehaviour
    {
        const float PITCH = 0.0127f;
        const int MAX_LINKS = 200;
        const float MECH_T = 0.06f;         // s: the AXS motor moving the mech a cog
        const float LOD_NEAR = 4.5f, LOD_FAR = 12f;
        const double RIDE_KG = 92.0;        // rider + bike, for the drive force at the tyre

        public readonly RearDerailleur rd = new RearDerailleur();
        BikeRig rig;
        Transform model, ringNode, axle, seatstay;
        Transform rdRoot, gBody, gTop, gBot, gKnuckle, gCage, pulTop, pulBot;
        Runout.Sim.BikeSim sim;
        int gear = -1, gearChain = -1, gearFrom = -1;
        double zMech, shiftProg = 1.0, lastCrank = double.NaN, spin;
        double _ay0 = double.NaN, _ay1, _ab0, _ab1, _aAcc, _bAcc;
        public int Lod { get; private set; } = -1;
        public int Links => rd.links;
        public string Problem { get; private set; }

        static Mesh _out, _in, _outLo, _inLo, _pulley;
        static Material[] _mats;     // outer plates, pins, inner plates, rollers
        static Material _bandMat;
        readonly Matrix4x4[] _mOut = new Matrix4x4[MAX_LINKS / 2], _mIn = new Matrix4x4[MAX_LINKS / 2];
        readonly Vector3[] _pins = new Vector3[MAX_LINKS];
        readonly List<double> _path = new List<double>();
        readonly List<float> _cum = new List<float>();
        Mesh _band;
        static readonly Matrix4x4 MX = Matrix4x4.Scale(new Vector3(-1f, 1f, 1f));

        /// the drivetrain on the stock frame (dh.glb): cut its frozen chain + derailleur out, mount the rigged one on the
        /// seatstay, cut the chain for this build. rdModel = rd_sram.glb, rdExtras = its kinematics. Null if the frame
        /// has no seatstay / crank / rear wheel.
        public static BikeChain Attach(BikeRig rig, Runout.Sim.BikeSim sim, GameObject rdModel, string rdExtras)
        {
            Transform seat = BikeRig.Find(rig.model, "seatstay");
            if (seat == null || rig.crank_n == null || rig.wheel_r == null || rdModel == null) return null;
            CutChainFromSwing(rig.model);
            CutStaticDerailleur(seat);
            var go = new GameObject("chain");
            go.transform.SetParent(rig.model, false);
            var c = go.AddComponent<BikeChain>();
            c.rig = rig; c.sim = sim; c.model = rig.model; c.ringNode = rig.crank_n; c.axle = rig.wheel_r; c.seatstay = seat;
            c.rd.Load(rdExtras);
            // the mech: its origin (the B-bolt) on the hanger, in the seatstay's frame
            var inst = Instantiate(rdModel, seat, false);
            inst.name = "rear_derailleur";
            DressMech(inst.transform);
            c.rdRoot = inst.transform;
            GodotSpace.SetLocal(c.rdRoot, V3(c.rd.originSeatstay), Quaternion.identity);
            c.gBody = BikeRig.Find(c.rdRoot, "body"); c.gTop = BikeRig.Find(c.rdRoot, "link_top"); c.gBot = BikeRig.Find(c.rdRoot, "link_bot");
            c.gKnuckle = BikeRig.Find(c.rdRoot, "knuckle"); c.gCage = BikeRig.Find(c.rdRoot, "cage");
            c.Build();
            c.Setup();
            return c;
        }

        /// the mechanic: B-tension + chain length for the build (sim.cogs / ring), at rest (seatstay unturned)
        public void Setup()
        {
            double[] cogs = sim.cogs != null && sim.cogs.Count > 0 ? sim.cogs.ToArray() : new double[] { 16 };
            double ring = 34.0 * sim.ring_k;
            Vector3 ss = GodotSpace.LocalPos(seatstay);   // (the seatstay's rest place: the suspension turns it later)
            var axleRest = new RearDerailleur.V(ss.x + GodotSpace.LocalPos(axle).x, ss.y + GodotSpace.LocalPos(axle).y, 0);
            Vector3 bb = GodotSpace.LocalPos(ringNode);
            var bk = new RearDerailleur.V(ss.x + rd.originSeatstay.x, ss.y + rd.originSeatstay.y, 0);
            rd.Setup(cogs, ring, axleRest, new RearDerailleur.V(bb.x, bb.y, 0), bk);
            gear = Mathf.Clamp(sim.gear >= 0 ? (int)sim.gear : cogs.Length / 2, 0, cogs.Length - 1);
            gearChain = gearFrom = gear; shiftProg = 1.0;
            zMech = rd.CogZ(gear, cogs.Length);
            // can this mech run this cassette? (a road / DH mech can't reach a 50T: the gap to the cog goes negative)
            Problem = null;
            for (int i = 0; i < cogs.Length; i++)
            {
                rd.Solve(axleRest, new RearDerailleur.V(bb.x, bb.y, 0), bk, 0, rd.CogZ(i, cogs.Length), RearDerailleur.PitchR(cogs[i]), rd.CogZ(i, cogs.Length));
                double gp = System.Math.Sqrt(Sq(rd.upper.x - axleRest.x) + Sq(rd.upper.y - axleRest.y)) - RearDerailleur.PitchR(cogs[i]) - rd.JockeyR;
                if (!rd.valid || gp < 0.002) { Problem = $"the SRAM AXS mech can't run the {cogs[0]:0}-{cogs[cogs.Length - 1]:0}T cassette (from the {cogs[i]:0}T: needs a long-cage mech)"; break; }
            }
            if (Problem != null) Debug.LogWarning("BikeChain: " + Problem);
        }
        static double Sq(double x) => x * x;

        void LateUpdate()   // (after SimHost / BikeDraw posed the bike this frame)
        {
            if (rig == null || model == null || axle == null || ringNode == null || sim == null) return;
            bool show = axle.gameObject.activeInHierarchy;
            if (rdRoot != null && rdRoot.gameObject.activeSelf != show) rdRoot.gameObject.SetActive(show);
            if (!show) return;
            float dt = Time.deltaTime;
            int n = rd.cogs.Length;
            if (sim.geared && sim.gear >= 0) gear = Mathf.Clamp((int)sim.gear, 0, n - 1);
            // the chain's travel (with the cranks: a freehub, coasting it stands still)
            double crank = rig.crank_angle;
            double dTravel = double.IsNaN(lastCrank) ? 0.0 : (crank - lastCrank) * rd.RingR;
            lastCrank = crank;
            // a shift: the mech goes at once, the chain follows onto the new cog as it travels
            double zTarget = rd.CogZ(gear, n);
            zMech += (zTarget - zMech) * (1.0 - System.Math.Exp(-dt / MECH_T));
            if (gear != gearChain)
            {
                if (shiftProg >= 1.0) { gearFrom = gearChain; shiftProg = 0.0; }
                gearChain = gear;
            }
            if (shiftProg < 1.0)
                shiftProg = System.Math.Min(1.0, shiftProg + System.Math.Abs(dTravel) / (System.Math.PI * RearDerailleur.PitchR(rd.cogs[gearChain])));
            double sp = shiftProg * shiftProg * (3 - 2 * shiftProg);
            double cogR = Lerp(RearDerailleur.PitchR(rd.cogs[gearFrom]), RearDerailleur.PitchR(rd.cogs[gearChain]), sp);
            double zChain = Lerp(rd.CogZ(gearFrom, n), rd.CogZ(gearChain, n), sp);
            // where things are now (Godot model space)
            Vector3 pa = GodotSpace.ToModel(model, axle.position);
            Vector3 pb = GodotSpace.ToModel(model, ringNode.position);
            Vector3 bk = GodotSpace.ToModel(model, seatstay.TransformPoint(GodotSpace.M(V3(rd.originSeatstay))));
            Vector3 s0 = GodotSpace.ToModel(model, seatstay.position), s1 = GodotSpace.ToModel(model, seatstay.TransformPoint(GodotSpace.M(Vector3.right)));
            double seatTurn = System.Math.Atan2(s1.y - s0.y, s1.x - s0.x);
            rd.Solve(new RearDerailleur.V(pa.x, pa.y, 0), new RearDerailleur.V(pb.x, pb.y, 0), new RearDerailleur.V(bk.x, bk.y, 0), seatTurn, zMech, cogR, zChain);
            // how far the camera is: the chain's LOD, and from afar no dynamics (a swept band shows no bow / swing)
            Lod = LodFor();
            // the cage and the runs reacting: the axle's and the BB's vertical acceleration (world), the drive
            Track(dt);
            double driveN = sim.air ? 0.0 : System.Math.Max(0.0, sim.a_pedal) * RIDE_KG;
            if (Lod < 2) rd.Dynamics(dt, _aAcc, _bAcc, driveN, rig.wheel_rr, cogR); else rd.Settle();
            if (!PoseOk()) return;   // (keeps last frame's pose rather than draw a broken one)
            PoseMech(seatTurn);
            // pulleys turn with the chain
            spin += dTravel;
            if (pulTop != null) GodotSpace.SetLocal(pulTop, Vector3.zero, RotZ((float)(rd.senses[2] * spin / rd.JockeyR)));
            if (pulBot != null) GodotSpace.SetLocal(pulBot, BottomPulleyLocal(), RotZ((float)(rd.senses[3] * spin / rd.JockeyR)));
            DrawChain(crank);
        }

        static double Lerp(double a, double b, double t) => a + (b - a) * t;
        static Vector3 V3(RearDerailleur.V v) => new Vector3((float)v.x, (float)v.y, (float)v.z);
        static Quaternion RotZ(float a) => Quaternion.AngleAxis(a * Mathf.Rad2Deg, Vector3.forward);
        Vector3 BottomPulleyLocal() => new Vector3(Mathf.Cos((float)rd.cageRest), Mathf.Sin((float)rd.cageRest), 0f) * (float)rd.cageLen;

        /// vertical accelerations of the rear axle and the BB from their drawn world heights (smoothed: frame jitter)
        void Track(float dt)
        {
            float ay = axle.position.y, by = ringNode.position.y;
            if (double.IsNaN(_ay0) || dt < 1e-4f || !float.IsFinite(ay + by)) { _ay0 = _ay1 = ay; _ab0 = _ab1 = by; return; }
            double h2 = dt * (double)dt;
            double aa = (ay - 2 * _ay1 + _ay0) / h2, ab = (by - 2 * _ab1 + _ab0) / h2;
            if (!RearDerailleur.Finite(aa + ab)) aa = ab = 0;   // (and a respawn's jump is clamped below)
            double k = 1.0 - System.Math.Exp(-dt / 0.02);
            _aAcc += (System.Math.Max(-300, System.Math.Min(300, aa)) - _aAcc) * k;
            _bAcc += (System.Math.Max(-300, System.Math.Min(300, ab)) - _bAcc) * k;
            _ay0 = _ay1; _ay1 = ay; _ab0 = _ab1; _ab1 = by;
        }

        /// the model's three degrees of freedom (the HDA's rderail_pose): body on the B-bolt, both links on their pins,
        /// the knuckle translating, the cage on the top pulley's axle. Seatstay-local (the mech hangs on it).
        void PoseMech(double seatTurn)
        {
            if (gBody == null) return;
            Quaternion rb = RotZ((float)rd.beta);
            Quaternion rl = Quaternion.AngleAxis((float)(rd.phi * Mathf.Rad2Deg), V3(rd.axis).normalized);
            Vector3 disp = V3(rd.Disp(rd.phi));
            GodotSpace.SetLocal(gBody, Vector3.zero, rb);
            if (gTop != null) GodotSpace.SetLocal(gTop, rb * V3(rd.pinTop), rb * rl);
            if (gBot != null) GodotSpace.SetLocal(gBot, rb * V3(rd.pinBot), rb * rl);
            if (gKnuckle != null) GodotSpace.SetLocal(gKnuckle, rb * disp, rb);
            if (gCage != null)
            {
                double cr = rd.cage - rd.cageRest - rd.beta - seatTurn;
                GodotSpace.SetLocal(gCage, rb * (V3(rd.u0) + disp), rb * RotZ((float)cr));
            }
        }

        void DrawChain(double crank)
        {
            double total = rd.Path(_path);
            int np = _path.Count / 3;
            if (np < 4 || !(total > 0) || !RearDerailleur.Finite(total)) { Redraw(); return; }
            _cum.Clear(); _cum.Add(0f);
            for (int i = 1; i < np; i++)
            {
                double dx = _path[i * 3] - _path[i * 3 - 3], dy = _path[i * 3 + 1] - _path[i * 3 - 2], dz = _path[i * 3 + 2] - _path[i * 3 - 1];
                _cum.Add(_cum[i - 1] + (float)System.Math.Sqrt(dx * dx + dy * dy + dz * dz));
            }
            float tot = _cum[np - 1];
            int nl = Mathf.Clamp(rd.links & ~1, 4, MAX_LINKS);
            float step = tot / nl;   // (= the pitch, to the cage solve's precision)
            // the pins: the chain runs the other way round to the path when pedalling forward
            float phase = Fposmod(-(float)(crank * rd.RingR), step * 2f);
            for (int i = 0; i < nl; i++)
            {
                float s = Fposmod(phase + i * step, tot);
                int seg = Lower(_cum, s);
                float u = Mathf.Clamp01((s - _cum[seg - 1]) / Mathf.Max(_cum[seg] - _cum[seg - 1], 1e-6f));
                int a = (seg - 1) * 3, b = seg * 3;
                _pins[i] = new Vector3((float)Lerp(_path[a], _path[b], u), (float)Lerp(_path[a + 1], _path[b + 1], u), (float)Lerp(_path[a + 2], _path[b + 2], u));
            }
            for (int i = 0; i < nl; i++) if (!float.IsFinite(_pins[i].x + _pins[i].y + _pins[i].z)) { Redraw(); return; }
            int want = Lod;
            Matrix4x4 mw = model.localToWorldMatrix;
            var bounds = new Bounds(ringNode.position, Vector3.one * 3f);
            int layer = model.gameObject.layer;
            if (want == 2) { _lastLod = 2; BandMesh(nl); Graphics.RenderMesh(Rp(_bandMat, bounds, layer), _band, 0, mw); return; }
            for (int i = 0; i < nl; i++)
            {
                Vector3 a = _pins[i], b = _pins[(i + 1) % nl];
                Vector3 dir = b - a;
                dir = dir.sqrMagnitude < 1e-10f ? Vector3.right : dir.normalized;
                Vector3 yy = Vector3.Cross(Vector3.forward, dir).normalized;
                var g = Matrix4x4.identity;
                g.SetColumn(0, dir); g.SetColumn(1, yy); g.SetColumn(2, Vector3.Cross(dir, yy));
                g.SetColumn(3, new Vector4((a.x + b.x) * 0.5f, (a.y + b.y) * 0.5f, (a.z + b.z) * 0.5f, 1f));
                Matrix4x4 w = mw * MX * g * MX;   // Godot model space -> Unity model-local (the link meshes are mirrored once)
                if ((i & 1) == 0) _mOut[i / 2] = w; else _mIn[i / 2] = w;
            }
            _half = nl / 2; _lastLod = want; _bounds = bounds; _layer = layer;
            Redraw();
        }

        // the last good chain, drawn again (a frame whose solve failed keeps it instead of drawing nothing / garbage)
        int _half, _lastLod = -1, _layer; Bounds _bounds;
        void Redraw()
        {
            if (_half <= 0 || _lastLod < 0 || _lastLod > 1) return;
            Mesh mo = _lastLod == 0 ? _out : _outLo, mi = _lastLod == 0 ? _in : _inLo;
            for (int sm = 0; sm < 2; sm++)
            {
                Graphics.RenderMeshInstanced(Rp(_mats[sm], _bounds, _layer), mo, sm, _mOut, _half);
                Graphics.RenderMeshInstanced(Rp(_mats[2 + sm], _bounds, _layer), mi, sm, _mIn, _half);
            }
        }

        int LodFor()
        {
            var cam = Camera.main;
            if (cam == null) return 0;
            float d = Vector3.Distance(cam.transform.position, ringNode.position) * Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad) / Mathf.Tan(37.5f * Mathf.Deg2Rad);
            return d < LOD_NEAR ? 0 : d < LOD_FAR ? 1 : 2;
        }

        bool PoseOk()
        {
            bool F(double x) => RearDerailleur.Finite(x);
            return F(rd.cage) && F(rd.phi) && F(rd.beta) && F(rd.upper.x + rd.upper.y + rd.lower.x + rd.lower.y) && F(rd.bowTop + rd.bowLow);
        }

        void Build()
        {
            var lit = Shader.Find("HDRP/Lit");
            if (_out == null)
            {
                _out = LinkMesh(true, false); _in = LinkMesh(false, false);
                _outLo = LinkMesh(true, true); _inLo = LinkMesh(false, true);
                _pulley = PulleyMesh(rd.jockeyTeeth, RearDerailleur.PitchR(rd.jockeyTeeth));
                // (Godot draws the links with culling off: the plates are open-ish, so double sided here too)
                Material M(Color c, string nm)
                {
                    var m = new Material(lit) { name = nm, enableInstancing = true };
                    m.SetColor("_BaseColor", c); m.SetFloat("_Metallic", 0.85f); m.SetFloat("_Smoothness", 0.62f);
                    m.SetFloat("_DoubleSidedEnable", 1f); m.SetFloat("_DoubleSidedNormalMode", 0f);
                    m.SetFloat("_CullMode", 0f); m.SetFloat("_CullModeForward", 0f); m.EnableKeyword("_DOUBLESIDED_ON");
                    UnityEngine.Rendering.HighDefinition.HDMaterial.ValidateMaterial(m);
                    return m;
                }
                _mats = new[] { M(new Color(0.62f, 0.63f, 0.66f), "chain_plate_out"), M(new Color(0.78f, 0.79f, 0.8f), "chain_pin"),
                                M(new Color(0.36f, 0.37f, 0.39f), "chain_plate_in"), M(new Color(0.28f, 0.28f, 0.3f), "chain_roller") };
                _bandMat = M(new Color(0.34f, 0.35f, 0.37f), "chain_band");
            }
            _band = new Mesh { name = "chain_band" };
            _band.MarkDynamic();
            // the two 12T pulleys on the cage (the model's own are 14.5k polygons each: drawn light, as the HDA does)
            if (gCage != null)
            {
                var pm = new Material(lit) { name = "pulley" };
                pm.SetColor("_BaseColor", new Color(0.035f, 0.035f, 0.038f)); pm.SetFloat("_Smoothness", 0.45f);
                pm.SetFloat("_DoubleSidedEnable", 1f); pm.SetFloat("_CullMode", 0f); pm.SetFloat("_CullModeForward", 0f); pm.EnableKeyword("_DOUBLESIDED_ON");
                UnityEngine.Rendering.HighDefinition.HDMaterial.ValidateMaterial(pm);
                Transform P(string nm, Vector3 at)
                {
                    var t = new GameObject(nm).transform;
                    t.SetParent(gCage, false);
                    GodotSpace.SetLocal(t, at, Quaternion.identity);
                    t.gameObject.AddComponent<MeshFilter>().sharedMesh = _pulley;
                    t.gameObject.AddComponent<MeshRenderer>().sharedMaterial = pm;
                    return t;
                }
                pulTop = P("pulley_top", Vector3.zero);
                pulBot = P("pulley_bottom", BottomPulleyLocal());
            }
        }

        static RenderParams Rp(Material m, Bounds b, int layer) => new RenderParams(m)
        { worldBounds = b, layer = layer, shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On, receiveShadows = true };

        static float Fposmod(float a, float b) { float r = a % b; return r < 0f ? r + b : r; }
        static int Lower(List<float> cum, float s)
        {
            int lo = 0, hi = cum.Count;
            while (lo < hi) { int m = (lo + hi) >> 1; if (cum[m] < s) lo = m + 1; else hi = m; }
            return Mathf.Clamp(lo, 1, cum.Count - 1);
        }

        /// the mech's own HDRP materials, by the glb's material names (chrome = the silver body / arms / bolts, black = the
        /// mount and cage plates, plastic = battery and motor housing)
        static void DressMech(Transform root)
        {
            var lit = Shader.Find("HDRP/Lit");
            if (lit == null) return;
            var made = new Dictionary<string, Material>();
            Material Get(string nm)
            {
                if (made.TryGetValue(nm, out var m)) return m;
                m = new Material(lit) { name = "rd_" + nm };
                if (nm.StartsWith("chrome")) { m.SetColor("_BaseColor", new Color(0.80f, 0.80f, 0.82f)); m.SetFloat("_Metallic", 1f); m.SetFloat("_Smoothness", 0.78f); }
                else if (nm.StartsWith("plastic")) { m.SetColor("_BaseColor", new Color(0.03f, 0.03f, 0.032f)); m.SetFloat("_Metallic", 0f); m.SetFloat("_Smoothness", 0.45f); }
                else { m.SetColor("_BaseColor", new Color(0.035f, 0.035f, 0.04f)); m.SetFloat("_Metallic", 0.7f); m.SetFloat("_Smoothness", 0.6f); }
                made[nm] = m;
                return m;
            }
            foreach (var r in root.GetComponentsInChildren<Renderer>(true))
            {
                var mats = r.sharedMaterials;
                for (int i = 0; i < mats.Length; i++) mats[i] = Get(mats[i] != null ? mats[i].name.ToLowerInvariant() : "black");
                r.sharedMaterials = mats;
            }
        }

        // ---- cutting dh.glb's frozen chain / derailleur out of its meshes ----
        static bool CutChainFromSwing(Transform model)
        {
            Transform sw = BikeRig.Find(model, "swing");
            var mf = sw != null ? sw.GetComponent<MeshFilter>() : null;
            var mr = sw != null ? sw.GetComponent<MeshRenderer>() : null;
            if (mf == null || mr == null || mf.sharedMesh == null) return false;
            var mats = mr.sharedMaterials;
            int si = -1;   // (the glb's "chain" material, or a look dressed over it: its name says chain)
            for (int i = 0; i < mats.Length; i++)
                if (mats[i] != null && mats[i].name.ToLowerInvariant().Contains("chain")) si = i;
            Mesh src = mf.sharedMesh;
            if (si < 0 || si >= src.subMeshCount || !src.isReadable) { Debug.LogWarning("BikeChain: the swingarm's chain could not be cut out"); return false; }
            var cm = Instantiate(src);
            cm.name = src.name + "_nochain";
            var keep = new List<int[]>(); var keepMats = new List<Material>();
            for (int i = 0; i < src.subMeshCount; i++)
                if (i != si) { keep.Add(src.GetIndices(i)); keepMats.Add(i < mats.Length ? mats[i] : null); }
            cm.subMeshCount = keep.Count;
            for (int i = 0; i < keep.Count; i++) cm.SetIndices(keep[i], MeshTopology.Triangles, i);
            mf.sharedMesh = cm; mr.sharedMaterials = keepMats.ToArray();
            return true;
        }

        /// the derailleur frozen into the seatstay mesh (dh.glb: the HDA's model at the 10T): every connected part whose
        /// middle is below the axle level (seatstay-local y < -5 mm) and out on the drive side (z > 5 cm). The hanger
        /// (reaching up to the axle) and the axle's own ends stay.
        static void CutStaticDerailleur(Transform seat)
        {
            var mf = seat.GetComponent<MeshFilter>();
            if (mf == null || mf.sharedMesh == null) return;
            Mesh src = mf.sharedMesh;
            if (!src.isReadable) { Debug.LogWarning("BikeChain: the seatstay mesh is not readable: its frozen derailleur stays"); return; }
            var V = src.vertices;
            // weld by position, union-find over the triangles
            var id = new Dictionary<Vector3Int, int>();
            var w = new int[V.Length];
            for (int i = 0; i < V.Length; i++)
            {
                var k = new Vector3Int(Mathf.RoundToInt(V[i].x * 1e5f), Mathf.RoundToInt(V[i].y * 1e5f), Mathf.RoundToInt(V[i].z * 1e5f));
                if (!id.TryGetValue(k, out int j)) { j = id.Count; id[k] = j; }
                w[i] = j;
            }
            var par = new int[id.Count];
            for (int i = 0; i < par.Length; i++) par[i] = i;
            int F(int x) { while (par[x] != x) { par[x] = par[par[x]]; x = par[x]; } return x; }
            var subs = new int[src.subMeshCount][];
            for (int s = 0; s < subs.Length; s++)
            {
                subs[s] = src.GetIndices(s);
                var t = subs[s];
                for (int i = 0; i + 2 < t.Length; i += 3) { int a = F(w[t[i]]); par[F(w[t[i + 1]])] = a; par[F(w[t[i + 2]])] = a; }
            }
            var sum = new Dictionary<int, Vector4>();
            for (int i = 0; i < V.Length; i++)
            {
                int r = F(w[i]);
                Vector3 g = GodotSpace.M(V[i]);
                sum.TryGetValue(r, out Vector4 acc);
                sum[r] = acc + new Vector4(g.x, g.y, g.z, 1f);
            }
            var drop = new HashSet<int>();
            foreach (var kv in sum)
            {
                Vector3 c = new Vector3(kv.Value.x, kv.Value.y, kv.Value.z) / kv.Value.w;
                if (c.y < -0.005f && c.z > 0.05f) drop.Add(kv.Key);
            }
            if (drop.Count == 0) return;
            var cm = Instantiate(src);
            cm.name = src.name + "_noderailleur";
            for (int s = 0; s < subs.Length; s++)
            {
                var keep = new List<int>(subs[s].Length);
                var t = subs[s];
                for (int i = 0; i + 2 < t.Length; i += 3)
                    if (!drop.Contains(F(w[t[i]]))) { keep.Add(t[i]); keep.Add(t[i + 1]); keep.Add(t[i + 2]); }
                cm.SetIndices(keep, MeshTopology.Triangles, s);
            }
            mf.sharedMesh = cm;
        }

        /// a 12T pulley (Godot space: in the xy plane, z across), mirrored once for Unity
        static Mesh PulleyMesh(int teeth, double rPitch)
        {
            var v = new List<Vector3>(); var nr = new List<Vector3>(); var tr = new List<int>();
            int N = teeth * 8;
            float rRoot = (float)rPitch - 0.0028f, rTip = (float)rPitch + 0.0030f, hz = 0.00125f;
            var ol = new Vector2[N];
            for (int k = 0; k < N; k++)
            {
                float a = 2f * Mathf.PI * k / N;
                float tooth = Mathf.Pow(Mathf.Max(0f, Mathf.Cos(a * teeth)), 0.6f);
                float r = Mathf.Lerp(rRoot, rTip, tooth);
                ol[k] = new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * r;
            }
            void Tri(Vector3 a, Vector3 b, Vector3 c, Vector3 n) { int i = v.Count; v.Add(a); v.Add(b); v.Add(c); nr.Add(n); nr.Add(n); nr.Add(n); tr.Add(i); tr.Add(i + 1); tr.Add(i + 2); }
            foreach (float sd in new[] { -1f, 1f })
            {
                var nz = new Vector3(0, 0, sd);
                for (int k = 0; k < N; k++)
                {
                    Vector3 c = new Vector3(0, 0, sd * hz), p = new Vector3(ol[k].x, ol[k].y, sd * hz), q = new Vector3(ol[(k + 1) % N].x, ol[(k + 1) % N].y, sd * hz);
                    if (sd > 0) Tri(c, p, q, nz); else Tri(c, q, p, nz);
                }
            }
            for (int k = 0; k < N; k++)
            {
                Vector2 a = ol[k], b = ol[(k + 1) % N];
                Vector3 n = new Vector3(b.y - a.y, a.x - b.x, 0).normalized;
                Vector3 p0 = new Vector3(a.x, a.y, -hz), p1 = new Vector3(b.x, b.y, -hz), p2 = new Vector3(b.x, b.y, hz), p3 = new Vector3(a.x, a.y, hz);
                Tri(p0, p2, p1, n); Tri(p0, p3, p2, n);
            }
            var m = new Mesh { name = "pulley_12T" };
            var V = new Vector3[v.Count]; var Nn = new Vector3[v.Count];
            for (int i = 0; i < V.Length; i++) { V[i] = GodotSpace.M(v[i]); Nn[i] = GodotSpace.M(nr[i]); }
            for (int i = 0; i < tr.Count; i += 3) { int x = tr[i + 1]; tr[i + 1] = tr[i + 2]; tr[i + 2] = x; }
            m.vertices = V; m.normals = Nn; m.SetTriangles(tr, 0); m.RecalculateBounds();
            return m;
        }

        // ---- meshes (Godot link space: x along the chain, pins at +-PITCH/2, y in the chain's plane, z across) ----
        sealed class MB { public List<Vector3> v = new List<Vector3>(), n = new List<Vector3>(); public List<int>[] t = { new List<int>(), new List<int>() }; }

        static void Tri(MB b, int sub, Vector3 p0, Vector3 p1, Vector3 p2, Vector3 n0, Vector3 n1, Vector3 n2)
        {
            int i = b.v.Count;
            b.v.Add(p0); b.v.Add(p1); b.v.Add(p2); b.n.Add(n0); b.n.Add(n1); b.n.Add(n2);
            b.t[sub].Add(i); b.t[sub].Add(i + 1); b.t[sub].Add(i + 2);
        }

        /// one link: outer = two plates outside + the pins (riveted heads proud); inner = two plates inside + the rollers.
        /// Submesh 0 plates, 1 pins / rollers. Mirrored in x once (Godot model space -> Unity), winding kept front.
        static Mesh LinkMesh(bool outer, bool lo)
        {
            var b = new MB();
            float zc = outer ? 0.0029f : 0.0018f, th = 0.0008f;
            foreach (float sd in new[] { -1f, 1f }) Plate(b, sd * zc, th, outer ? 0.0037f : 0.0039f, outer ? 0.0026f : 0.0030f, lo ? 4 : 14);
            foreach (float e in new[] { -1f, 1f })
            {
                var c = new Vector3(e * PITCH * 0.5f, 0f, 0f);
                if (outer) Cyl(b, c, 0.00185f, -0.0040f, 0.0040f, lo ? 4 : 10);
                else Cyl(b, c, 0.0038f, -0.0013f, 0.0013f, lo ? 5 : 10);
            }
            var m = new Mesh { name = (outer ? "chain_outer" : "chain_inner") + (lo ? "_lo" : "") };
            var V = new Vector3[b.v.Count]; var N = new Vector3[b.v.Count];
            for (int i = 0; i < V.Length; i++) { V[i] = GodotSpace.M(b.v[i]); N[i] = GodotSpace.M(b.n[i]); }
            m.vertices = V; m.normals = N;
            m.subMeshCount = 2;
            for (int s = 0; s < 2; s++)
            {
                var t = b.t[s];
                for (int i = 0; i < t.Count; i += 3) { int x = t[i + 1]; t[i + 1] = t[i + 2]; t[i + 2] = x; }   // (the mirror flips winding)
                m.SetTriangles(t, s);
            }
            m.RecalculateBounds();
            return m;
        }

        /// a figure-eight side plate: lobes of radius R round both pins, a waist of half-height w, thickness th at z
        static void Plate(MB b, float z, float th, float R, float w, int N)
        {
            float L = PITCH * 0.5f + R;
            var outl = new List<Vector2>();
            for (int k = 0; k <= N; k++)
            {
                float x = -L + 2f * L * k / N;
                float d = Mathf.Abs(x) - PITCH * 0.5f;
                float lobe = Mathf.Abs(d) <= R ? Mathf.Sqrt(Mathf.Max(R * R - d * d, 0f)) : 0f;
                float y = Mathf.Abs(x) < PITCH * 0.5f ? Mathf.Max(lobe, w) : lobe;
                outl.Add(new Vector2(x, y));
            }
            for (int k = N - 1; k > 0; k--) outl.Add(new Vector2(outl[k].x, -outl[k].y));
            int m = outl.Count;
            foreach (float sd in new[] { -1f, 1f })
            {
                float zz = z + sd * th * 0.5f;
                var nrm = new Vector3(0, 0, sd);
                for (int k = 0; k < m; k++)
                {
                    Vector2 a = outl[k], c = outl[(k + 1) % m];
                    Vector3 p0 = new Vector3(0, 0, zz), p1 = new Vector3(a.x, a.y, zz), p2 = new Vector3(c.x, c.y, zz);
                    if (sd < 0) Tri(b, 0, p0, p2, p1, nrm, nrm, nrm); else Tri(b, 0, p0, p1, p2, nrm, nrm, nrm);
                }
            }
            for (int k = 0; k < m; k++)
            {
                Vector2 a = outl[k], c = outl[(k + 1) % m];
                Vector2 e = c - a;
                var nrm = new Vector3(e.y, -e.x, 0).normalized;
                Vector3 p0 = new Vector3(a.x, a.y, z - th * 0.5f), p1 = new Vector3(c.x, c.y, z - th * 0.5f);
                Vector3 p2 = new Vector3(c.x, c.y, z + th * 0.5f), p3 = new Vector3(a.x, a.y, z + th * 0.5f);
                Tri(b, 0, p0, p2, p1, nrm, nrm, nrm); Tri(b, 0, p0, p3, p2, nrm, nrm, nrm);
            }
        }

        /// a cylinder along z from z0 to z1 with caps
        static void Cyl(MB b, Vector3 c, float r, float z0, float z1, int N)
        {
            for (int k = 0; k < N; k++)
            {
                float a0 = 2f * Mathf.PI * k / N, a1 = 2f * Mathf.PI * (k + 1) / N;
                Vector3 d0 = new Vector3(Mathf.Cos(a0), Mathf.Sin(a0), 0), d1 = new Vector3(Mathf.Cos(a1), Mathf.Sin(a1), 0);
                Vector3 q0 = c + d0 * r, q1 = c + d1 * r;
                Vector3 Z0 = new Vector3(0, 0, z0), Z1 = new Vector3(0, 0, z1);
                Tri(b, 1, q0 + Z0, q1 + Z1, q1 + Z0, d0, d1, d1);
                Tri(b, 1, q0 + Z0, q0 + Z1, q1 + Z1, d0, d0, d1);
                foreach (float sd in new[] { -1f, 1f })
                {
                    var Z = new Vector3(0, 0, sd > 0 ? z1 : z0);
                    var nz = new Vector3(0, 0, sd);
                    if (sd < 0) Tri(b, 1, c + Z, q1 + Z, q0 + Z, nz, nz, nz); else Tri(b, 1, c + Z, q0 + Z, q1 + Z, nz, nz, nz);
                }
            }
        }

        readonly List<Vector3> _bv = new List<Vector3>(), _bn = new List<Vector3>();
        readonly List<int> _bt = new List<int>();
        /// the far chain: a flat box section (7 x 7.5 mm) swept through the pins (Godot model space, mirrored once)
        void BandMesh(int n)
        {
            _bv.Clear(); _bn.Clear(); _bt.Clear();
            const float hw = 0.0036f, hh = 0.0036f;
            for (int i = 0; i < n; i++)
            {
                Vector3 a = _pins[i], b = _pins[(i + 1) % n];
                Vector3 dir = b - a;
                if (dir.sqrMagnitude < 1e-10f) continue;
                dir.Normalize();
                Vector3 yy = Vector3.Cross(Vector3.forward, dir).normalized, zz = Vector3.forward;
                Vector3[] c = { yy * hh + zz * hw, -yy * hh + zz * hw, -yy * hh - zz * hw, yy * hh - zz * hw };
                (int i0, int i1, Vector3 nr)[] faces = { (0, 3, yy), (1, 0, zz), (2, 1, -yy), (3, 2, -zz) };
                foreach (var f in faces)
                {
                    Vector3 p0 = a + c[f.i0], p1 = a + c[f.i1], p2 = b + c[f.i1], p3 = b + c[f.i0];
                    int s = _bv.Count;
                    foreach (var p in new[] { p0, p1, p2, p3 }) { _bv.Add(GodotSpace.M(p)); _bn.Add(GodotSpace.M(f.nr)); }
                    // (mirrored: winding reversed)
                    _bt.Add(s); _bt.Add(s + 2); _bt.Add(s + 1); _bt.Add(s); _bt.Add(s + 3); _bt.Add(s + 2);
                }
            }
            _band.Clear();
            _band.SetVertices(_bv); _band.SetNormals(_bn); _band.SetTriangles(_bt, 0);
            _band.RecalculateBounds();
        }
    }
}
