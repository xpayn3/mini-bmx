using Godot;

/// GDScript view of a designed feature of TerrainFieldCs (what TerrainField.Feat offers the chunk builder)
public partial class TerrainFeatCs : RefCounted
{
	public double x, z, dx, dz, len, b0, b1, half, s;
	public string type = "";
	public TerrainWoodCs wood;

	public TerrainFeatCs() { }

	internal TerrainFeatCs(TfFeat f)
	{
		x = f.x; z = f.z; dx = f.dx; dz = f.dz; len = f.len; b0 = f.b0; b1 = f.b1; half = f.half; s = f.s; type = f.type;
		wood = f.wood != null ? new TerrainWoodCs(f.wood) : null;
	}
}
