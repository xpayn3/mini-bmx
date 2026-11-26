using Godot;

/// The C# side of Env.raw (scripts/core/env.gd): a BMX_* test flag, or null in a release export (only the editor
/// and the "Windows Dev" export, feature tag "dev", read them), so no test switch reaches a player.
public static class DevFlags
{
	public static readonly bool On = OS.HasFeature("editor") || OS.HasFeature("dev");

	public static string Env(string key) => On ? System.Environment.GetEnvironmentVariable(key) : null;
}
