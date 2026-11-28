using System;
using System.Collections.Generic;
using Runout.Rider;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// The rider on the bike: our pose solver (Runout.Rider.RiderPose, the port of godot/scripts/rider/rider.gd) fed the
    /// same inputs Godot's game.gd gives it every frame, retargeted onto a Unity Humanoid (any Mecanim Humanoid model:
    /// Mixamo, Unity's, a scan). The solver works in the rider's space (Godot axes: +X forward, +Y up, +Z the rider's
    /// right, = the bike's lean space); its humanoid bones are moved onto the model's bones as a change from the T-pose
    /// (delta retargeting: D = pose * rest^-1 per bone, applied to the model's own T-pose), so the model keeps its own
    /// bone axes. The model's limb lengths go into the solver, so hands land on the grips and feet on the pedals.
    public sealed class RiderView : MonoBehaviour
    {
        public Animator character;   // a Humanoid
        public RiderPose pose;
        public readonly PoseInput pi = new PoseInput();

        BikeSim st;
        BikeRig rig;
        RideParams T;
        readonly List<(HumanBodyBones hb, string name, Transform t)> _bones = new List<(HumanBodyBones, string, Transform)>();
        static readonly Quaternion FACE_X = Quaternion.Euler(0f, 90f, 0f);   // a model facing Unity +Z, turned to face the rider's forward (W(+X) = Unity +X)
        float t;
        // game.gd's smoothed pose inputs
        float _yaw_s, _turn_s, _aspin_s, _atilt_s, _blat_s, _awhip_s;

        public void Init(BikeSim sim, BikeRig r, Animator model)
        {
            st = sim; rig = r; T = sim.T; character = model;
            pose = new RiderPose();
            pose.tune = (k, d) => T != null ? T.get(k, d) : d;
            pose.seat = rig.seat;
            pose.pedal_top = rig.pedal_top;
            // the rider fitted to the bike like Godot does (Game: rider.fit from the grips + crank), model space ~ lean space
            Vector3 grip = rig.steer_n != null ? GodotSpace.LocalPos(rig.steer_n) + (rig.grip_l + rig.grip_r) * 0.5f : new Vector3(0.4388f, 0.9646f, 0f);
            float crankY = rig.crank_n != null ? GodotSpace.LocalPos(rig.crank_n).y : 0.297f;
            pose.fit = new Vec3((grip.x - 0.4388) * 0.5, ((grip.y - 0.9646) + (crankY - 0.297)) * 0.5, 0.0);
            CaptureRest();
        }

        /// the model's T-pose (its bind pose, which a Humanoid import keeps when no animator controller plays), in the
        /// "rider frame" seen from Unity, and its limb lengths into the solver
        void CaptureRest()
        {
            _bones.Clear();
            if (character == null || !character.isHuman) { Debug.LogWarning("RiderView: the character is not a Humanoid"); return; }
            Transform root = character.transform;
            // the rest = the avatar's T-pose (the skeleton pose the Humanoid import was configured with), NOT the mesh's
            // file pose: a model's file pose is often an A-pose or relaxed, and taking that as the T-pose twisted the
            // shoulders, wrists, hips. A bone's rest rotation in the root's space = its chain of rest local rotations
            _restLocal.Clear();
            if (character.avatar != null)
                foreach (var sb in character.avatar.humanDescription.skeleton) _restLocal[sb.name] = sb.rotation;
            foreach (HumanBodyBones hb in Enum.GetValues(typeof(HumanBodyBones)))
            {
                if (hb == HumanBodyBones.LastBone) continue;
                Transform bt = character.GetBoneTransform(hb);
                if (bt == null) continue;
                _bones.Add((hb, hb.ToString(), bt));
            }
            // each hand's own axes, from its own skeleton (whatever pose the model was made in): toward the middle finger's
            // knuckle, across the knuckles toward the index (thumb side), the back of the hand = their cross product
            for (int i = 0; i < 2; i++)
            {
                string sd = i == 0 ? "Left" : "Right";
                Transform hb = Bone(sd + "Hand"), mk = Bone(sd + "MiddleProximal"), ix = Bone(sd + "IndexProximal"), lt = Bone(sd + "LittleProximal");
                if (hb == null || mk == null) continue;
                Vector3 fw = mk.localPosition.normalized;
                Vector3 up;
                if (ix != null && lt != null && ix.parent == hb && lt.parent == hb)
                {
                    Vector3 across = ix.localPosition - lt.localPosition;   // (toward the thumb side)
                    up = Vector3.Cross(fw, across).normalized * (i == 0 ? 1f : -1f);
                }
                else up = Quaternion.Inverse(RestInRoot(hb)) * Vector3.up;   // (no finger bones: a T-pose's palms are down)
                _handFwdL[i] = fw;
                _handUpL[i] = (up - fw * Vector3.Dot(up, fw)).normalized;
                _handOk[i] = true;
            }
            // parents before children (so setting a world rotation never disturbs one already set)
            _bones.Sort((a, b) => Depth(a.t).CompareTo(Depth(b.t)));
            float Len(HumanBodyBones a, HumanBodyBones b)
            {
                Transform ta = character.GetBoneTransform(a), tb = character.GetBoneTransform(b);
                return ta != null && tb != null ? Vector3.Distance(ta.position, tb.position) / Mathf.Max(1e-4f, root.lossyScale.y) : 0f;
            }
            float th = Len(HumanBodyBones.LeftUpperLeg, HumanBodyBones.LeftLowerLeg), sh = Len(HumanBodyBones.LeftLowerLeg, HumanBodyBones.LeftFoot);
            float ua = Len(HumanBodyBones.LeftUpperArm, HumanBodyBones.LeftLowerArm), fa = Len(HumanBodyBones.LeftLowerArm, HumanBodyBones.LeftHand);
            if (th > 0.2f) pose.L_THIGH = th;
            if (sh > 0.2f) pose.L_SHIN = sh;
            if (ua > 0.15f) pose.L_UARM = ua;
            if (fa > 0.15f) pose.L_FARM = fa + 0.07;   // (Godot's forearm runs to the middle of the grip: the wrist + half the hand)
            // the torso (pelvis -> the chest joint at the base of the neck) and half the shoulder width, from the model
            float tor = Len(HumanBodyBones.Hips, HumanBodyBones.Neck), shw = Len(HumanBodyBones.LeftUpperArm, HumanBodyBones.RightUpperArm) * 0.5f;
            if (tor > 0.3f) pose.TORSO = tor;
            if (shw > 0.1f) pose.SHOULDERS = shw;
            pose.set_style(new Dictionary<string, double>());   // (after the lengths: they seed the style's torso / shoulders)
            Debug.Log($"RiderView: {character.name} humanoid, {_bones.Count} bones, thigh {th:F3} shin {sh:F3} upper arm {ua:F3} forearm {fa:F3} m");
        }

        static int Depth(Transform t) { int d = 0; while (t.parent != null) { t = t.parent; d++; } return d; }

        readonly Dictionary<string, Quaternion> _restLocal = new Dictionary<string, Quaternion>();
        Quaternion RestLocal(Transform n) => _restLocal.TryGetValue(n.name, out var q) ? q : n.localRotation;
        Quaternion RestInRoot(Transform bt)
        {
            Quaternion r = Quaternion.identity;
            for (Transform n = bt; n != null && n != character.transform; n = n.parent) r = RestLocal(n) * r;
            return r;
        }

        // ---- fingers: WHEN they grip / rest on the lever / squeeze = ours (RiderFingers); HOW = Unity muscles ----
        public readonly RiderFingers fingers = new RiderFingers();
        /// The model's proportions are not the solver's: after the retarget its own arms and legs are bent (two-bone IK,
        /// the hands' / feet's rotation kept) so the contact points are exactly where Godot puts them: the middle
        /// finger's knuckle on the grip where GloveFingers has it (on a circle of GRIP_R round the bar, KNUCKLE_ANG up the
        /// front), the ankles where the solver's feet are
        void ContactIK(Quaternion frame)
        {
            Vector3 ToWorld(Vec3 riderPos) => GodotSpace.W(rig.LeanToWorld(U(riderPos)));
            for (int i = 0; i < 2; i++)
            {
                string sd = i == 0 ? "Left" : "Right";
                Xf hand = i == 0 ? pose.handL : pose.handR;
                Transform ua = Bone(sd + "UpperArm"), la = Bone(sd + "LowerArm"), hb = Bone(sd + "Hand"), mk = Bone(sd + "MiddleProximal");
                if (ua != null && la != null && hb != null && mk != null)
                {
                    double inner = i == 0 ? 1.0 : -1.0;
                    var kn = new Vec3(Math.Cos(RiderFingers.KNUCKLE_ANG + 0.04) * RiderFingers.GRIP_R, Math.Sin(RiderFingers.KNUCKLE_ANG + 0.04) * RiderFingers.GRIP_R, inner * 0.0115);
                    Vector3 knuckle = ToWorld(hand.o + hand.b * kn);
                    Vector3 target = knuckle - (mk.position - hb.position);   // (rigid with the hand: its rotation is kept)
                    TwoBoneIK(ua, la, hb, target, ToWorld(pose.J[i == 0 ? 4 : 7]));   // (bends toward our solver's elbow)
                }
                Transform ul = Bone(sd + "UpperLeg"), ll = Bone(sd + "LowerLeg"), fb = Bone(sd + "Foot");
                if (ul != null && ll != null && fb != null)
                {
                    Xf shoe = i == 0 ? pose.shoeL : pose.shoeR;   // the ankle over the shoe (Rider ANKLE_X / ANKLE_UP)
                    Vec3 ankle = shoe.o + shoe.b.x.normalized() * pose.ANKLE_X + shoe.b.y.normalized() * pose.ANKLE_UP;
                    TwoBoneIK(ul, ll, fb, ToWorld(ankle), ToWorld(pose.J[i == 0 ? 10 : 13]));   // (toward our knee)
                }
            }
        }

        readonly Vector3[] _handFwdL = new Vector3[2], _handUpL = new Vector3[2];
        readonly bool[] _handOk = new bool[2];

        /// each hand turned to hold the grip: its fingers along our hand's +X (across the bar, a little down its front:
        /// Godot's orient_grip), the back of the hand along our +Y. From the model's own hand axes (no conversion of
        /// Godot's hand bone, whose axes are not a Unity Humanoid's)
        void SetHands(Quaternion frame)
        {
            for (int i = 0; i < 2; i++)
            {
                if (!_handOk[i]) continue;
                Transform hb = Bone(i == 0 ? "LeftHand" : "RightHand");
                Xf hand = i == 0 ? pose.handL : pose.handR;
                // the fingers go across the REAL grip (its measured axis: swept / angled bars), back of the hand up
                Vector3 axis = frame * GodotSpace.W(rig.GripAxis(i));
                Vector3 fw = frame * GodotSpace.W(U(hand.b.x));
                fw = (fw - axis * Vector3.Dot(fw, axis)).normalized;
                Vector3 up = frame * GodotSpace.W(U(hand.b.y));
                up = (up - axis * Vector3.Dot(up, axis) - fw * Vector3.Dot(up, fw)).normalized;
                Quaternion want = Quaternion.LookRotation(fw, up);
                Quaternion rest = Quaternion.LookRotation(_handFwdL[i], _handUpL[i]);
                hb.rotation = want * Quaternion.Inverse(rest);
            }
        }

        /// turn a bone so its rest forward / up (the model's T-pose: root +Z / +Y) point along fw / up (world)
        void Face(HumanBodyBones hb, Vector3 fw, Vector3 up)
        {
            Transform t = character.GetBoneTransform(hb);
            if (t == null || fw.sqrMagnitude < 1e-10f || up.sqrMagnitude < 1e-10f) return;
            Quaternion rest = RestInRoot(t);
            Vector3 fl = Quaternion.Inverse(rest) * Vector3.forward, ul = Quaternion.Inverse(rest) * Vector3.up;
            t.rotation = Quaternion.LookRotation(fw, up) * Quaternion.Inverse(Quaternion.LookRotation(fl, ul));
        }

        Transform Bone(string n) => Enum.TryParse(n, out HumanBodyBones hb) ? character.GetBoneTransform(hb) : null;

        /// a -> b -> c reaches `target` (as near as the lengths allow), bending in the plane it already bends in; c keeps its
        /// world rotation
        /// a -> b -> c reaches `target` (as near as the lengths allow) with the middle joint toward `hint` (our solver's
        /// elbow / knee: the plane it bends in); c keeps its world rotation. The model's own bone lengths
        static void TwoBoneIK(Transform a, Transform b, Transform c, Vector3 target, Vector3 hint)
        {
            Quaternion cRot = c.rotation;
            Vector3 pa = a.position;
            float la = (b.position - pa).magnitude, lb = (c.position - b.position).magnitude;
            if (la < 1e-4f || lb < 1e-4f) return;
            Vector3 to = target - pa;
            float lt = Mathf.Clamp(to.magnitude, Mathf.Abs(la - lb) + 1e-3f, la + lb - 1e-3f);
            Vector3 dir = to.sqrMagnitude > 1e-10f ? to.normalized : Vector3.down;
            Vector3 side = (hint - pa) - Vector3.Dot(hint - pa, dir) * dir;   // toward the hint, square to the reach
            if (side.sqrMagnitude < 1e-8f) side = (b.position - pa) - Vector3.Dot(b.position - pa, dir) * dir;
            side = side.sqrMagnitude > 1e-10f ? side.normalized : Vector3.Cross(dir, Vector3.up).normalized;
            float along = (la * la - lb * lb + lt * lt) / (2f * lt);
            float h = Mathf.Sqrt(Mathf.Max(0f, la * la - along * along));
            Vector3 elbow = pa + dir * along + side * h;
            a.rotation = Quaternion.FromToRotation(b.position - pa, elbow - pa) * a.rotation;
            b.rotation = Quaternion.FromToRotation(c.position - b.position, pa + dir * lt - b.position) * b.rotation;
            c.rotation = cRot;
        }

        // ---- Unity's Humanoid muscle space: the skeleton is a real human's. After our pose is on the bones, it is read
        // back as muscles (normalized: -1 .. 1 = each joint's human range), held inside that range, and the fingers are
        // set as muscles from our grip state (RiderFingers: when they wrap the bar, rest on the lever, squeeze) ----
        [Header("Fingers (Humanoid muscles: -1 bent .. 1 straight)")]
        [Tooltip("each finger joint wrapped round the grip (proximal, middle, tip)")] public Vector3 gripCurl = new Vector3(-0.55f, -0.8f, -0.6f);
        [Tooltip("open / relaxed hand")] public Vector3 openCurl = new Vector3(0.1f, 0.05f, 0.05f);
        [Tooltip("index + middle resting on the brake lever")] public Vector3 leverRest = new Vector3(0.15f, -0.1f, -0.25f);
        [Tooltip("... squeezing it")] public Vector3 leverPull = new Vector3(-0.25f, -0.55f, -0.5f);
        [Tooltip("thumb round the grip (1, 2, 3)")] public Vector3 thumbGrip = new Vector3(-0.3f, -0.5f, -0.6f);
        public float thumbSpread = -0.3f;
        [Tooltip("hold every joint inside Unity's human range")] public bool humanLimits = true;

        bool _offscreenSet;
        HumanPoseHandler _hph;
        HumanPose _hp;
        int[,,] _mFinger;   // [hand, finger 0 thumb..4 little, joint 0..2] -> muscle index ("Left Index 2 Stretched")
        int[,] _mSpread;    // [hand, finger] -> "Left Index Spread"

        void InitMuscles()
        {
            if (character == null || character.avatar == null || !character.avatar.isHuman) return;
            _hph = new HumanPoseHandler(character.avatar, character.transform);
            _hp = new HumanPose();
            _mFinger = new int[2, 5, 3];
            _mSpread = new int[2, 5];
            string[] names = HumanTrait.MuscleName;
            int Find(string n) => Array.IndexOf(names, n);
            string[] fn = { "Thumb", "Index", "Middle", "Ring", "Little" };
            for (int h = 0; h < 2; h++)
                for (int f = 0; f < 5; f++)
                {
                    string pre = (h == 0 ? "Left " : "Right ") + fn[f];
                    for (int j = 0; j < 3; j++) _mFinger[h, f, j] = Find($"{pre} {j + 1} Stretched");
                    _mSpread[h, f] = Find($"{pre} Spread");
                }
        }

        void HumanMuscles()
        {
            if (_hph == null) InitMuscles();
            if (_hph == null) return;
            // (the round trip through muscle space may place the body by its own rules: the hips are put back after)
            Transform hips = character.GetBoneTransform(HumanBodyBones.Hips);
            Vector3 hipPos = hips.position; Quaternion hipRot = hips.rotation;
            _hph.GetHumanPose(ref _hp);
            if (humanLimits)
                for (int m = 0; m < _hp.muscles.Length; m++) _hp.muscles[m] = Mathf.Clamp(_hp.muscles[m], -1f, 1f);
            for (int h = 0; h < 2; h++)
            {
                float lev = (float)fingers.on_lever(h), sq = (float)fingers.squeeze(h);
                for (int f = 0; f < 5; f++)
                {
                    float c = (float)fingers.finger_curl(h, f);
                    for (int j = 0; j < 3; j++)
                    {
                        int mi = _mFinger[h, f, j];
                        if (mi < 0) continue;
                        float v = f == 0 ? Mathf.Lerp(openCurl[j], thumbGrip[j], c) : Mathf.Lerp(openCurl[j], gripCurl[j], c);
                        if ((f == 1 || f == 2) && lev > 0f) v = Mathf.Lerp(v, Mathf.Lerp(leverRest[j], leverPull[j], sq), lev);
                        _hp.muscles[mi] = v;
                    }
                    int ms = _mSpread[h, f];
                    if (ms >= 0) _hp.muscles[ms] = f == 0 ? Mathf.Lerp(0f, thumbSpread, (float)fingers.finger_curl(h, 0)) : 0f;
                }
            }
            _hph.SetHumanPose(ref _hp);
            hips.SetPositionAndRotation(hipPos, hipRot);
        }

        /// the model's materials made HDRP Lit (a model made for the built-in pipeline draws black / pink in HDRP),
        /// keeping its colour texture
        public static void HdrpMaterials(GameObject model, Texture albedo)
        {
            var lit = Shader.Find("HDRP/Lit");
            if (lit == null) return;
            foreach (var r in model.GetComponentsInChildren<Renderer>())
            {
                var mats = r.sharedMaterials;
                for (int k = 0; k < mats.Length; k++)
                {
                    var old = mats[k];
                    // (always replaced: an import can give an HDRP Lit material with no colour on it = black)
                    Texture tex = albedo;
                    if (old != null && old.HasProperty("_BaseColorMap") && old.GetTexture("_BaseColorMap") != null) tex = old.GetTexture("_BaseColorMap");
                    else if (old != null && old.HasProperty("_MainTex") && old.mainTexture != null) tex = old.mainTexture;
                    var m = new Material(lit) { name = (old != null ? old.name : "rider") + "_HDRP" };
                    if (tex != null) m.SetTexture("_BaseColorMap", tex);
                    m.SetColor("_BaseColor", Color.white);
                    m.SetFloat("_Smoothness", 0.35f);
                    mats[k] = m;
                }
                r.sharedMaterials = mats;
            }
        }

        static Vec3 V(Vector3 v) => new Vec3(v.x, v.y, v.z);
        static Vector3 U(Vec3 v) => new Vector3((float)v.x, (float)v.y, (float)v.z);
        /// one drawn frame, after the bike is posed (BikeDraw). The inputs are game.gd's (lines ~4280-4415), in order
        public void Draw(float dt, float p_draw, float y_draw, float frame_y, float lean_c, float steer_c, Func<string, float, float, float> mcap)
        {
            if (pose == null || st == null) return;
            t += dt;
            if (st.crash_on) { if (character != null) character.gameObject.SetActive(false); return; }   // (the ragdoll is not ported yet)
            if (character != null && !character.gameObject.activeSelf) { character.gameObject.SetActive(true); pose.reset_pose(); }
            var lt = rig.limb_targets();
            float ek = 1f - Mathf.Exp(-dt * 8f);
            float ak = (float)st.air_k;
            _yaw_s += ((float)st.yaw_rate - _yaw_s) * (1f - Mathf.Exp(-dt * 14f));
            _turn_s += ((1f - ak) * (float)st.yaw_rate * Mathf.Clamp(Mathf.Abs((float)st.v) / 3f, 0.3f, 1f) - _turn_s) * (1f - Mathf.Exp(-dt * 5f));
            _aspin_s += (ak * (float)st.yaw_rate - _aspin_s) * ek;
            float stl = new Vector2((float)st.air_stick.x, (float)st.air_stick.y).magnitude;
            _atilt_s += ((st.air ? (float)st.air_tilt * (float)T.get("stickBodyTilt", 0.6) * Mathf.Clamp(stl * 3f + Mathf.Abs((float)st.edge_s) * 2f, 0f, 1f) * ak : 0f) - _atilt_s) * ek;
            _blat_s += (Mathf.Lerp((float)st.flick, st.air ? (float)st.air_stick.x : 0f, ak) - _blat_s) * ek;
            _awhip_s += ((st.air ? (float)st.air_tw * ak : 0f) - _awhip_s) * (1f - Mathf.Exp(-dt * 16f));
            float pdt = Mathf.Min(dt, 0.05f);

            pi.Clear();
            pi["footL"] = V(lt.footL); pi["footR"] = V(lt.footR);
            pi["handL"] = V(lt.handL); pi["handR"] = V(lt.handR);
            pi["gripX_L"] = V(lt.gripX); pi["gripX_R"] = V(lt.gripX); pi["gripZ"] = V(lt.gripZ);
            pi["dab"] = 0.0; pi["dabSide"] = 0.0; pi["dabNormal"] = null; pi["footOut"] = 0.0; pi["footOutSide"] = 0.0;
            pi["dabLean"] = 0.0; pi["dabLeanVar"] = 0.0; pi["stopStand"] = 0.0; pi["stopSit"] = 0.0;
            pi["v"] = st.v;
            pi["lean"] = (double)(lean_c + (float)st.rock);
            pi["steer"] = (double)steer_c;
            pi["yawRate"] = (double)_yaw_s;
            pi["counter"] = (double)(lean_c - mcap("body_roll", (float)(st.bike_lean - st.counter), pdt));
            pi["rockRoll"] = st.rock;
            pi["frameY"] = (double)frame_y;
            pi["headRoll"] = (double)mcap("head_roll", (float)st.bike_lean * 0.85f, pdt);
            pi["absorb"] = (double)mcap("absorb", Mathf.Clamp((float)st.body_y - y_draw, -(float)T.f("legComp"), (float)T.f("legExt")), pdt);
            pi["pitch"] = (double)p_draw;
            pi["bodyLevel"] = T.f("bodyLevel");
            pi["attackDrop"] = T.f("attackDrop");
            pi["pedal"] = st.pedal;
            pi["sprint"] = st.sprint * st.pedal;
            pi["spinOut"] = st.spin_out_k;
            pi["stamina"] = st.stamina;
            pi["hr"] = 72.0;
            pi["crank"] = st.crank;
            pi["air"] = st.air_k;
            pi["compress"] = Math.Max(0.0, -st.compress);
            pi["extend"] = Math.Max(0.0, st.compress);
            double auto_pre = st.squash > 0.2 ? 0.0 : st.prep * T.f("autoPump") * (1.0 - st.auto_absorb);
            pi["preload"] = Math.Max(st.crouch, auto_pre) * (1.0 - ak);
            pi["popFx"] = st.pop_fx * Math.Min(1.0, st.pop_q) * (st.pro_flight ? 1.0 : 0.35);
            pi["airPull"] = st.air ? st.air_pull : 0.0;
            pi["squash"] = Math.Max(Math.Max(st.squash, st.auto_absorb) * st.prep, st.squash_fx);
            pi["lipK"] = Math.Max(st.prep, (st.pop_wait > 0.0 || st.hop_t > 0.0) ? 1.0 : 0.0);
            pi["landFold"] = st.land_fold * (1.0 - ak);
            pi["landReach"] = st.land_prep * st.land_reach;
            pi["inAir"] = ak > 0.5f ? 1.0 : 0.0;
            pi["brakeF"] = st.brake_f; pi["brakeR"] = st.brake_r;
            pi["hipShift"] = (double)mcap("hip_shift", (float)st.hip_shift, pdt);
            pi["bodyStick"] = (double)mcap("body_stick", (float)st.body_in_s, pdt);
            pi["speedTuck"] = st.speed_tuck;
            pi["relax"] = 0.0; pi["tall"] = 0.0;
            pi["lookYaw"] = 0.0; pi["lookPitch"] = 0.0; pi["lookTwist"] = 0.0;
            // the LAND's slope under the two wheels (no rock domes)
            double hx = Gd.cos(st.heading), hz = -Gd.sin(st.heading);
            double fx = st.x + hx * (st.L - st.BB_REAR), fz = st.z + hz * (st.L - st.BB_REAR);
            double rx = st.x - hx * st.BB_REAR, rz = st.z - hz * st.BB_REAR;
            pi["slope"] = Gd.atan2(st.host.terrain.deck_height(fx, fz) - st.host.terrain.deck_height(rx, rz), st.L);
            pi["frontUp"] = st.wheelie_up;
            pi["airTilt"] = (double)_atilt_s;
            pi["bodyLat"] = (double)_blat_s;
            pi["airWhip"] = (double)_awhip_s;
            pi["torsoVmax"] = T.get("torsoMaxSpeed", 2.5);
            pi["latG"] = (double)mcap("lat_g", (float)(st.lat_a / BikeSim.G), pdt);
            if (rig.wheel_r != null) pi["wheelR"] = V(rig.LeanLocal(GodotSpace.WorldPos(rig.wheel_r)));
            pi["wheelRR"] = (double)rig.wheel_rr;
            if (rig.wheel_f != null) pi["wheelF"] = V(rig.LeanLocal(GodotSpace.WorldPos(rig.wheel_f)));
            pi["wheelRF"] = (double)rig.wheel_rf;
            pi["t"] = (double)t;
            pi["airSpin"] = (double)_aspin_s;
            pi["flipTwist"] = 0.0; pi["flipArch"] = 0.0; pi["flipExt"] = 0.0;
            if (!st.air && st.throw_v > 0.5)
            {
                double thr = Gd.clampf(st.throw_v / Math.Max(T.f("flipRate"), 0.1), 0.0, 1.0);
                pi["preload"] = (double)pi["preload"] * (1.0 - thr);
                pi["extend"] = Math.Max((double)pi["extend"], 0.1 * thr);
                pi["lookPitch"] = 0.45 * thr;
                if (st.throw_v > 0.0) pi["flipArch"] = thr;
            }
            else if (st.air && Math.Abs(st.flip_acc) > 0.25)
            {
                double fon = Gd.smoothstep(1.0, 2.2, Math.Abs(st.air_w));
                double ph = Gd.clampf(Math.Abs(st.flip_acc) / Gd.TAU, 0.0, 1.0);
                double f_head = fon * (1.0 - Gd.smoothstep(0.15, 0.35, ph));
                double f_look = fon * Gd.smoothstep(0.35, 0.55, ph) * (1.0 - Gd.smoothstep(0.85, 1.0, ph));
                double f_open = Math.Max(fon, Gd.smoothstep(0.6, 0.75, ph)) * Gd.smoothstep(0.7, 0.9, ph);
                pi["lookPitch"] = (0.5 * f_head - 0.35 * f_look) * Gd.signf(st.flip_acc);
                pi["lookYaw"] = 0.75 * f_look;
                pi["flipTwist"] = 0.4 * f_look;
                if (st.flip_acc > 0.0) pi["flipArch"] = fon * (1.0 - Gd.smoothstep(0.2, 0.4, ph));
                double f_ext = fon * Gd.smoothstep(0.1, 0.3, ph);
                pi["flipExt"] = Math.Max(f_ext, f_open);
                pi["landReach"] = Math.Max((double)pi["landReach"], Math.Max(f_ext, f_open));
            }
            pi["wheelY"] = rig.wheel_f != null && rig.wheel_r != null ? (double)((GodotSpace.WorldPos(rig.wheel_f).y + GodotSpace.WorldPos(rig.wheel_r).y) * 0.5f) : 0.0;
            pi["turn"] = (double)_turn_s;
            pi["pedalTop"] = (double)rig.pedal_top;
            pose.update_pose(dt, pi);
            fingers.update(dt, false, st.brake_f, st.brake_r, (double)pi["landFold"]);
            // the pedals turn with the feet (ankling): flat pedals tip under the shoe, about their axle (Godot game.gd)
            rig.pose_pedals((float)st.crank, (float)pose.foot_pitch[0], (float)pose.foot_pitch[1]);
            Retarget();
        }

        /// the solver's humanoid bones onto the model: world rotation = (rider frame) * D * (the model's T-pose), D the
        /// bone's change from its rest in rider space; the hips are put where the solver has them
        void Retarget()
        {
            if (character == null) return;
            Quaternion frame = GodotSpace.WRot(rig.ModelRot);   // rider space -> Unity world, for rotations (W R W)
            // the model's root sits under the hips' place, turned with the bike (only the bones are moved after this)
            Transform root = character.transform;
            root.rotation = frame * Quaternion.Inverse(FACE_X);
            // the root rides with the bike (its bounds / culling are the root's; the bones are placed in world space below)
            root.position = GodotSpace.W(rig.position);
            if (!_offscreenSet)
            {
                foreach (var smr in character.GetComponentsInChildren<SkinnedMeshRenderer>()) smr.updateWhenOffscreen = true;
                _offscreenSet = true;
            }
            // No conversion of Godot's bones: our solver gives POINTS and FRAMES (where the pelvis, spine, head, hands, feet
            // are and which way they face; Godot axes: x forward, y up, z right) and every Unity bone is turned to match
            // from the model's own rest axes (its T-pose: forward +Z, up +Y in the root's space). Arms / legs are IK on
            // the model's own bones; clavicles, toes, eyes, jaw stay at rest. Everything from rest each frame (no drift)
            foreach (var b in _bones) b.t.localRotation = RestLocal(b.t);
            Vector3 Dir(Vec3 v) => frame * GodotSpace.W(U(v));
            Vector3 P(Vec3 v) => GodotSpace.W(rig.LeanToWorld(U(v)));
            Transform hips = character.GetBoneTransform(HumanBodyBones.Hips);
            if (hips != null) hips.position = P(pose.J[2]);
            Face(HumanBodyBones.Hips, Dir(pose.pelvis_xf.b.x), Dir(pose.pelvis_xf.b.y));
            Face(HumanBodyBones.Spine, Dir(pose.spine[1].b.x), Dir(pose.spine[1].b.y));
            Face(HumanBodyBones.Chest, Dir(pose.spine[2].b.x), Dir(pose.spine[2].b.y));
            Face(HumanBodyBones.UpperChest, Dir(pose.spine[3].b.x), Dir(pose.spine[3].b.y));
            Face(HumanBodyBones.Neck, Dir(pose.head.b.x), Dir(pose.head.o - pose.J[1]));
            Face(HumanBodyBones.Head, Dir(pose.head.b.x), Dir(pose.head.b.y));
            Face(HumanBodyBones.LeftFoot, Dir(pose.shoeL.b.x), Dir(pose.shoeL.b.y));
            Face(HumanBodyBones.RightFoot, Dir(pose.shoeR.b.x), Dir(pose.shoeR.b.y));
            SetHands(frame);
            ContactIK(frame);
            HumanMuscles();     // (fingers + every joint in its human range)
            ContactIK(frame);   // (the range may have moved a hand a little off its grip)
        }
    }
}
