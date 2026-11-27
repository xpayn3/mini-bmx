using System;
using System.Diagnostics;
using Godot;

/// Runs C#'s garbage collector + finalizers now, while the engine is still up (GameState.quit, a window close).
/// The terrain chunk builders leave small C# objects (feature wrappers) to the collector; while the game is
/// frozen (the paper map, the pause menu) it doesn't get to run, and finalizing them after the engine shut down
/// crashed the quit.
/// stats(): memory + collector numbers for the hitch / memory lines in the session log (Game._hitch_watch).
[GlobalClass]
public partial class CsGc : RefCounted
{
	public void collect()
	{
		GC.Collect();
		GC.WaitForPendingFinalizers();
		GC.Collect();
	}

	/// cheap, every frame: total collector pause (ms), collections per generation
	public Vector4 counters() => new Vector4((float)GC.GetTotalPauseDuration().TotalMilliseconds,
		GC.CollectionCount(0), GC.CollectionCount(1), GC.CollectionCount(2));

	public Godot.Collections.Dictionary stats()
	{
		var info = GC.GetGCMemoryInfo();
		long priv = 0;
		int others = 0;
		try
		{
			using var p = Process.GetCurrentProcess();
			priv = p.PrivateMemorySize64;
			// other copies of the game / editor on this machine (other test windows load every core and ~7 GB each)
			foreach (var q in Process.GetProcesses())
			{
				try { if (q.Id != p.Id && q.ProcessName.StartsWith("Godot", StringComparison.OrdinalIgnoreCase)) others++; }
				catch (Exception) { }
				q.Dispose();
			}
		}
		catch (Exception) { }
		// (the console exe runs the game as a child: a console launch counts its own wrapper as one "other")
		return new Godot.Collections.Dictionary
		{
			{ "heap_mb", GC.GetTotalMemory(false) / 1048576.0 },
			{ "committed_mb", info.TotalCommittedBytes / 1048576.0 },
			{ "proc_mb", priv / 1048576.0 },
			{ "gen0", GC.CollectionCount(0) },
			{ "gen1", GC.CollectionCount(1) },
			{ "gen2", GC.CollectionCount(2) },
			{ "pause_ms", GC.GetTotalPauseDuration().TotalMilliseconds },
			{ "alloc_mb", GC.GetTotalAllocatedBytes(false) / 1048576.0 },
			{ "sys_load", info.TotalAvailableMemoryBytes > 0 ? 100.0 * info.MemoryLoadBytes / info.TotalAvailableMemoryBytes : -1.0 },
			{ "other_godot", others },
		};
	}
}
