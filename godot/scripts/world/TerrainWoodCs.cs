using Godot;

/// GDScript view of a wooden deck (TrailFeatures.Wood): top(u) above the flattened ground
public partial class TerrainWoodCs : RefCounted
{
	public long kind;
	public double u0, u1, half;
	public bool back_wall;
	private TfWood _w;

	public TerrainWoodCs() { }

	internal TerrainWoodCs(TfWood w)
	{
		_w = w; kind = w.kind; u0 = w.u0; u1 = w.u1; half = w.half; back_wall = w.back_wall;
	}

	public double top(double u) => _w.top(u);
}
