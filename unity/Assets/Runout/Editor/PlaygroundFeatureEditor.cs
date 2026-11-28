using Runout.Game;
using UnityEditor;
using UnityEngine;

namespace Runout.EditorTools
{
    [CustomEditor(typeof(PlaygroundFeature)), CanEditMultipleObjects]
    public sealed class PlaygroundFeatureEditor : UnityEditor.Editor
    {
        public override void OnInspectorGUI()
        {
            var f = (PlaygroundFeature)target;
            serializedObject.Update();
            EditorGUI.BeginChangeCheck();
            EditorGUILayout.PropertyField(serializedObject.FindProperty("kind"));
            bool kindChanged = EditorGUI.EndChangeCheck();
            serializedObject.ApplyModifiedProperties();
            if (kindChanged) { Undo.RecordObject(f, "Feature kind"); f.ResetArgs(); EditorUtility.SetDirty(f); }
            f.FitArgs();

            var spec = PlaygroundFeature.ARGS[f.kind];
            EditorGUI.BeginChangeCheck();
            var vals = (float[])f.args.Clone();
            for (int i = 0; i < spec.Length; i++) vals[i] = EditorGUILayout.FloatField(spec[i].label, vals[i]);
            float hw = EditorGUILayout.FloatField("Riding half width (m)", f.halfWidth);
            if (EditorGUI.EndChangeCheck())
            {
                Undo.RecordObject(f, "Feature numbers");
                f.args = vals; f.halfWidth = hw;
                EditorUtility.SetDirty(f);
                Notify();
            }
            if (f.placed != null) EditorGUILayout.HelpBox(f.placed.feat.desc, MessageType.None);

            EditorGUILayout.Space();
            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button("Reset to defaults")) { Undo.RecordObject(f, "Reset feature"); f.ResetArgs(); EditorUtility.SetDirty(f); Notify(); }
                if (GUILayout.Button("Ride from here")) RideFrom(f);
            }
            EditorGUILayout.HelpBox("The red arrow (local +X) is the way it's ridden; its position is where the feature starts. W pedal, S brake, A / D steer, Space hop, arrows = body.", MessageType.Info);
        }

        static void Notify()
        {
            var w = Object.FindFirstObjectByType<PlaygroundWorld>();
            if (w != null) w.MarkPlacedDirty();
        }

        static void RideFrom(PlaygroundFeature f)
        {
            var w = Object.FindFirstObjectByType<PlaygroundWorld>();
            if (w == null) { Debug.LogWarning("No PlaygroundWorld in the scene"); return; }
            Undo.RecordObject(w, "Ride from here");
            w.startAt = f; w.startFeatureId = "";
            EditorUtility.SetDirty(w);
            EditorApplication.EnterPlaymode();
        }

        /// GameObject > Runout > Playground Feature: a new feature where the Scene view looks
        [MenuItem("GameObject/Runout/Playground Feature", false, 10)]
        static void Create(MenuCommand cmd)
        {
            var go = new GameObject("Feature");
            var f = go.AddComponent<PlaygroundFeature>();
            f.ResetArgs();
            var sv = SceneView.lastActiveSceneView;
            if (sv != null)
            {
                var ray = new Ray(sv.camera.transform.position, sv.camera.transform.forward);
                var plane = new Plane(Vector3.up, Vector3.zero);
                if (plane.Raycast(ray, out float d)) go.transform.position = ray.GetPoint(Mathf.Min(d, 200f));
                go.transform.position = new Vector3(Mathf.Round(go.transform.position.x), 0f, Mathf.Round(go.transform.position.z));
            }
            var parent = GameObject.Find("Placed Features");
            if (parent != null) go.transform.SetParent(parent.transform, true);
            if (cmd.context is GameObject ctx) go.transform.SetParent(ctx.transform, true);
            Undo.RegisterCreatedObjectUndo(go, "Playground Feature");
            Selection.activeObject = go;
        }
    }
}
