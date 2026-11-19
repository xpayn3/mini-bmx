using System;
using Godot;

/// Runs C#'s garbage collector + finalizers now, while the engine is still up (GameState.quit, a window close).
/// The terrain chunk builders leave small C# objects (feature wrappers) to the collector; while the game is
/// frozen (the paper map, the pause menu) it doesn't get to run, and finalizing them after the engine shut down
/// crashed the quit.
[GlobalClass]
public partial class CsGc : RefCounted
{
	public void collect()
	{
		GC.Collect();
		GC.WaitForPendingFinalizers();
		GC.Collect();
	}
}
