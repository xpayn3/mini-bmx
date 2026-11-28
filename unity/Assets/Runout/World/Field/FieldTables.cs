using System.Collections.Generic;

namespace Runout.World
{
	/// Everything the world setup builds that the height field reads (terrain_field.gd setup(): the noise lattice,
	/// the mountain's pitches, the course's query tables, the route spine, B-lines, route features, colours, the Land
	/// Lab knobs). Names = the GDScript variables. Filled by WorldSetup (the C# port of setup) or, in the tests, from
	/// Godot's dump (godot/tools/world_dump.gd).
	public sealed class FieldTables
	{
		public long seed_value;
		public double sz, rp_a, rp_sg, pitch_share, grade_k = 1.0, biome_dry, biome_rug;
		public double[] NT, pitches;
		public double[] cX, cZ, cTX, cTZ, cKAP, cW, cBT, cE, cRD, cRK, cLN, cRO, cROS, cDL, c_drops, c_seg, c_far;
		public int[] cKD, c_run_start, c_runs;
		public long c_gx0, c_gz0, c_gnx, c_gnz, c_far_x0, c_far_z0, c_far_nx, c_far_nz;
		public double[] sX, sZ, sS;
		public long s_gx0, s_gz0, s_gnx, s_gnz;
		public int[] s_start, s_items;
		public double[] alt_pts, alt_lines;
		public List<long[]> alt_feats = new List<long[]>();
		public List<FeatDesc> route_feats = new List<FeatDesc>();
		public Dictionary<string, TfColor> col = new Dictionary<string, TfColor>();
		public TfColor[] red_bands, grey_bands;
		public Dictionary<string, double> land = new Dictionary<string, double>();
		public object course;
	}

	/// a route feature as the setup places it (TerrainField.Feat's placement; its shape is made from the type)
	public sealed class FeatDesc
	{
		public double x, z, dx, dz, b0, b1, s;
		public string type;
		public int size = 3;
	}
}
