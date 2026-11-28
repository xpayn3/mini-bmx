using System.IO;
using System.Text;
using UnityEditor;
using UnityEditor.TestTools.TestRunner.Api;
using UnityEngine;

namespace Runout.EditorTools
{
    /// Runs tests in the OPEN editor without touching its UI: write a test name (or "WorldTests") into
    /// unity/Temp/run_tests.txt and the editor starts that play-mode test run on its next update; the result goes to
    /// unity/Logs/editor_tests.txt (and the WORLDTEST lines to the Editor.log as usual). For tools / Claude:
    /// unity/Tools/run_in_editor.ps1. It refreshes the assets itself (scripts changed outside Unity get compiled first).
    [InitializeOnLoad]
    static class TestTrigger
    {
        const string TRIGGER = "Temp/run_tests.txt", RESULT = "Logs/editor_tests.txt";

        static TestTrigger()
        {
            var api = ScriptableObject.CreateInstance<TestRunnerApi>();
            api.RegisterCallbacks(new Report());   // again after every domain reload (play mode may reload)
            EditorApplication.update += Poll;
        }

        static double _next;

        static void Poll()
        {
            if (EditorApplication.timeSinceStartup < _next) return;
            _next = EditorApplication.timeSinceStartup + 1.0;
            if (!File.Exists(TRIGGER) || EditorApplication.isPlayingOrWillChangePlaymode || EditorApplication.isCompiling) return;
            // pick up changed scripts first (the editor only refreshes on focus): recompiles + reloads, then we come back here
            AssetDatabase.Refresh();
            if (EditorApplication.isCompiling) return;
            if (EditorUtility.scriptCompilationFailed)
            {
                File.Delete(TRIGGER);
                File.WriteAllText(RESULT, "DONE CompileError: scripts don't compile (see the Console / Editor.log)" + "\n");
                return;
            }
            string filter = File.ReadAllText(TRIGGER).Trim();
            File.Delete(TRIGGER);
            if (filter.Length == 0) filter = "WorldTests";
            File.WriteAllText(RESULT, $"RUNNING {filter}\n");
            var api = ScriptableObject.CreateInstance<TestRunnerApi>();
            var f = new Filter { testMode = TestMode.PlayMode, groupNames = new[] { filter } };
            api.Execute(new ExecutionSettings(f));
        }

        sealed class Report : ICallbacks
        {
            public void RunStarted(ITestAdaptor tests) { }
            public void TestStarted(ITestAdaptor test) { }
            public void TestFinished(ITestResultAdaptor r)
            {
                if (r.HasChildren) return;
                File.AppendAllText(RESULT, $"TEST {r.FullName}: {r.TestStatus} ({r.Duration:0} s) {r.Message}\n");
            }
            public void RunFinished(ITestResultAdaptor r)
            {
                File.AppendAllText(RESULT, $"DONE {r.TestStatus}: {r.PassCount} passed, {r.FailCount} failed\n");
            }
        }
    }
}
