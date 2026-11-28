using UnityEngine;

namespace Runout.Game
{
    /// The bridge between Godot's space (where the ride physics and every ported drawing formula live) and Unity's.
    ///   world:  sim / Godot (x, y, z) -> Unity (x, y, -z)                  (W = mirror z)
    ///   models: a Godot-made glb, imported by glTFast, is mirrored in x:   (M = mirror x)
    /// So the drawing does its maths in Godot space exactly as the Godot game does (numbers line for line), and only
    /// these functions touch Unity transforms: a node's Unity world matrix U = W * G * M, its Unity local L = M * Gl * M.
    /// (Unity's Quaternion / Matrix4x4 maths is plain maths: a Godot rotation is the same numbers in them.)
    public static class GodotSpace
    {
        /// Godot point / direction <-> Unity world (mirror z, self-inverse)
        public static Vector3 W(Vector3 v) => new Vector3(v.x, v.y, -v.z);
        /// Godot model space <-> Unity model-local space (mirror x, self-inverse)
        public static Vector3 M(Vector3 v) => new Vector3(-v.x, v.y, v.z);

        /// a Godot-space rotation conjugated by the mirror in x (M R M): what it is in a glTFast-imported node's local space
        public static Quaternion MRot(Quaternion q) => new Quaternion(q.x, -q.y, -q.z, q.w);
        /// ... and by the mirror in z (W R W): a Godot world rotation seen in Unity's world
        public static Quaternion WRot(Quaternion q) => new Quaternion(-q.x, -q.y, q.z, q.w);

        /// set a model part's LOCAL transform from its Godot-space local position / rotation
        public static void SetLocal(Transform t, Vector3 gpos, Quaternion grot)
        {
            t.localPosition = M(gpos);
            t.localRotation = MRot(grot);
        }

        public static Vector3 LocalPos(Transform t) => M(t.localPosition);
        public static Quaternion LocalRot(Transform t) => MRot(t.localRotation);

        /// place a model (a glTFast-imported Godot node) so its Godot-space world transform is (gpos, grot):
        /// U = W * G * M, whose rotation part W R M is a proper rotation (two mirrors)
        public static void SetModelWorld(Transform model, Vector3 gpos, Quaternion grot)
        {
            // W R M = (W R W)(W M), and W M = diag(-1, 1, -1) = a half turn about y
            Quaternion r = WRot(grot) * Quaternion.Euler(0f, 180f, 0f);
            model.SetPositionAndRotation(W(gpos), r);
        }

        /// a part's Godot-space world origin / axes, from its Unity transform (G = W U M)
        public static Vector3 WorldPos(Transform t) => W(t.position);
        public static Vector3 WorldAxisX(Transform t) => -W(t.right);
        public static Vector3 WorldAxisY(Transform t) => W(t.up);
        public static Vector3 WorldAxisZ(Transform t) => W(t.forward);

        /// a part's whole Godot-space world transform (scale included), G = W U M, as the engine-free code's Xf
        public static Runout.Rider.Xf WorldXf(Transform t)
        {
            Matrix4x4 u = t.localToWorldMatrix;
            Vector3 cx = -W((Vector3)u.GetColumn(0)), cy = W((Vector3)u.GetColumn(1)), cz = W((Vector3)u.GetColumn(2));
            return new Runout.Rider.Xf(new Runout.Rider.Basis(V(cx), V(cy), V(cz)), V(W(t.position)));
        }
        public static Runout.Rider.Vec3 V(Vector3 v) => new Runout.Rider.Vec3(v.x, v.y, v.z);
        public static Vector3 U(Runout.Rider.Vec3 v) => new Vector3((float)v.x, (float)v.y, (float)v.z);
        /// a Godot basis (scale allowed) as a rotation
        public static Quaternion Rot(Runout.Rider.Basis b)
        {
            Vector3 x = U(b.x).normalized, y = U(b.y).normalized, z = U(b.z).normalized;
            var m = Matrix4x4.identity;
            m.SetColumn(0, x); m.SetColumn(1, y); m.SetColumn(2, z);
            return m.rotation;
        }
        /// place a model so its Godot world transform is xf (rotation part only; the model keeps its scale)
        public static void SetModelWorld(Transform model, Runout.Rider.Xf xf) => SetModelWorld(model, U(xf.o), Rot(xf.b));

        /// a point in `model`'s Godot model space, from a Unity world point
        public static Vector3 ToModel(Transform model, Vector3 unityWorld) => M(model.InverseTransformPoint(unityWorld));
    }
}
