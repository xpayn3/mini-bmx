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
        readonly List<(HumanBodyBones hb, string name, Transform t, Quaternion rest)> _bones = new List<(HumanBodyBones, string, Transform, Quaternion)>();
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
            Quaternion inv = Quaternion.Inverse(root.rotation);
            foreach (HumanBodyBones hb in Enum.GetValues(typeof(HumanBodyBones)))
            {
                if (hb == HumanBodyBones.LastBone) continue;
                Transform bt = character.GetBoneTransform(hb);
                if (bt == null) continue;
                _bones.Add((hb, hb.ToString(), bt, FACE_X * (inv * bt.rotation)));
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
            pose.set_style(new Dictionary<string, double>());   // (after the lengths: they seed the style's torso / shoulders)
            Debug.Log($"RiderView: {character.name} humanoid, {_bones.Count} bones, thigh {th:F3} shin {sh:F3} upper arm {ua:F3} forearm {fa:F3} m");
        }

        static int Depth(Transform t) { int d = 0; while (t.parent != null) { t = t.parent; d++; } return d; }

        static Vec3 V(Vector3 v) => new Vec3(v.x, v.y, v.z);
        static Vector3 U(Vec3 v) => new Vector3((float)v.x, (float)v.y, (float)v.z);
        static Quaternion Q(Basis b)
        {
            var m = new Matrix4x4();
            m.SetColumn(0, new Vector4((float)b.x.x, (float)b.x.y, (float)b.x.z, 0f));
            m.SetColumn(1, new Vector4((float)b.y.x, (float)b.y.y, (float)b.y.z, 0f));
            m.SetColumn(2, new Vector4((float)b.z.x, (float)b.z.y, (float)b.z.z, 0f));
            m.SetColumn(3, new Vector4(0f, 0f, 0f, 1f));
            return m.rotation;
        }

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
            Retarget();
        }

        /// the solver's humanoid bones onto the model: world rotation = (rider frame) * D * (the model's T-pose), D the
        /// bone's change from its rest in rider space; the hips are put where the solver has them
        void Retarget()
        {
            if (character == null || pose.bones == null || pose.bones_rest == null) return;
            Quaternion frame = GodotSpace.WRot(rig.ModelRot);   // rider space -> Unity world, for rotations (W R W)
            // the model's root sits under the hips' place, turned with the bike (only the bones are moved after this)
            Transform root = character.transform;
            root.rotation = frame * Quaternion.Inverse(FACE_X);
            foreach (var b in _bones)
            {
                if (!pose.bones.TryGetValue(b.name, out Xf cur) || !pose.bones_rest.TryGetValue(b.name, out Xf rest)) continue;
                Quaternion d = Q(cur.b) * Quaternion.Inverse(Q(rest.b));
                b.t.rotation = frame * GodotSpace.WRot(d) * b.rest;
                if (b.hb == HumanBodyBones.Hips)
                {
                    Vector3 gw = rig.LeanToWorld(U(cur.o));
                    b.t.position = GodotSpace.W(gw);
                }
            }
        }
    }
}
