using System;

namespace Runout.World
{
	/// Test / dev switches (BMX_OLD_* ...) for the world, engine-free. The host sets Env (Unity: dev builds only, like
	/// Godot's DevFlags); unset = every switch off, as in a release.
	public static class WorldFlags
	{
		public static Func<string, string> Env = _ => null;
	}
}
