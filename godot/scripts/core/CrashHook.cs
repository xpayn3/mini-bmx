using System;
using System.IO;
using System.Threading.Tasks;
using Godot;

/// C# side of CrashLog: an exception nobody catches (on any thread, or a faulted Task nobody awaited) is written
/// straight to a file beside the session log, since the engine may already be going down. Exceptions inside
/// engine callbacks are caught by Godot itself and reach CrashLog's logger as errors.
[GlobalClass]
public partial class CrashHook : RefCounted
{
	static string _path = "";
	static bool _installed;

	public void install(string path)
	{
		_path = path;
		if (_installed) return;
		_installed = true;
		AppDomain.CurrentDomain.UnhandledException += (_, e) =>
			Write("UNHANDLED C# EXCEPTION" + (e.IsTerminating ? " (terminating)" : ""), e.ExceptionObject as Exception);
		TaskScheduler.UnobservedTaskException += (_, e) => Write("UNOBSERVED TASK EXCEPTION", e.Exception);
	}

	/// tests (BMX_CRASHTEST=cs): an exception on a plain thread nobody catches = the process goes down
	public void test_throw()
	{
		new System.Threading.Thread(() => throw new InvalidOperationException("BMX_CRASHTEST C# exception")).Start();
	}

	static void Write(string what, Exception ex)
	{
		try
		{
			File.AppendAllText(_path, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {what}\n{ex}\n\n");
		}
		catch { }
		try { GD.PrintErr(what + ": " + ex?.Message); } catch { }
	}
}
