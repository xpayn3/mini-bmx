using UnityEngine;
using UnityEngine.Rendering.HighDefinition;
using UnityEngine.SceneManagement;

namespace Runout.Game
{
    /// Floating origin, the usual Unity way for big worlds: when the camera gets `limit` metres from (0, 0, 0), every
    /// root object of the loaded scenes moves back by a whole number of `step` metres, so Unity transforms stay small
    /// and float32-precise however far the trail runs (it roams ~7 km+). The ride physics is unaffected: it lives in
    /// absolute sim coordinates; GodotSpace.Origin (sim -> Unity) is moved by the same amount, so everything the sim
    /// places next frame lands in the same spot. HDRP's camera history (TAA, motion vectors) is reset on the shift frame
    /// so the jump doesn't smear.
    [DefaultExecutionOrder(10000)]   // after the camera has moved this frame
    public sealed class WorldOrigin : MonoBehaviour
    {
        [Tooltip("shift once the camera is this far from (0, 0, 0) on the ground plane (m)")] public float limit = 1024f;
        [Tooltip("shifts are whole multiples of this (keep = the world tile size)")] public float step = 128f;

        /// how far the origin has moved in total (Unity metres): diagnostics
        public static Vector3 Total { get; private set; }
        /// the frame of the last shift (diagnostics: spike reports)
        public static int LastShiftFrame { get; private set; } = -1;

        void LateUpdate()
        {
            var cam = Camera.main;
            if (cam == null) return;
            Vector3 p = cam.transform.position;
            if (Mathf.Abs(p.x) < limit && Mathf.Abs(p.z) < limit) return;
            var d = new Vector3(Mathf.Round(p.x / step) * step, 0f, Mathf.Round(p.z / step) * step);
            Shift(d);
        }

        /// move the world by -d (Unity metres, y ignored)
        public static void Shift(Vector3 d)
        {
            d.y = 0f;
            for (int i = 0; i < SceneManager.sceneCount; i++)
            {
                var s = SceneManager.GetSceneAt(i);
                if (!s.isLoaded) continue;
                foreach (var go in s.GetRootGameObjects()) go.transform.position -= d;
            }
            // Unity = W(godot - Origin): moving Unity by -d moves the origin by +d in x and -d in z (Godot's z is mirrored)
            GodotSpace.Origin += new Vector3(d.x, 0f, -d.z);
            Total += d;
            LastShiftFrame = Time.frameCount;
            foreach (var c in Camera.allCameras) HDCamera.GetOrCreate(c).Reset();
            Physics.SyncTransforms();
        }
    }
}
