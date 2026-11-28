using System.Collections.Generic;

namespace Runout.World
{
    /// Godot's world tables (godot/tools/world_dump.gd setup_<seed>.rwd) -> FieldTables. The bridge until the setup is
    /// ported (then WorldSetup builds the tables itself); the tests keep using it as the reference.
    public static class GodotTables
    {
        /// load a dump file: the tables + the dumped TrailCourse (as RwdObject, in FieldTables.course)
        public static FieldTables Load(string path)
        {
            var tree = (Dictionary<object, object>)Rwd.Load(path);
            return FromGodot((RwdObject)tree["field"], (Dictionary<object, object>)tree["land"]);
        }

        /// Godot's TerrainField variables -> FieldTables (what setup_from reads)
        public static FieldTables FromGodot(RwdObject g, Dictionary<object, object> land)
        {
            var t = new FieldTables
            {
                seed_value = Rwd.L(g["seed_value"]), sz = Rwd.D(g["sz"]), NT = Rwd.F64(g["NT"]),
                rp_a = Rwd.D(g["rp_a"]), rp_sg = Rwd.D(g["rp_sg"]), pitches = Rwd.F64(g["pitches"]),
                pitch_share = Rwd.D(g["pitch_share"]), grade_k = Rwd.D(g["grade_k"]),
                biome_dry = Rwd.D(g["biome_dry"]), biome_rug = Rwd.D(g["biome_rug"]),
                cX = Rwd.F64(g["cX"]), cZ = Rwd.F64(g["cZ"]), cKD = Rwd.I32(g["cKD"]),
                cTX = Rwd.F64(g["cTX"]), cTZ = Rwd.F64(g["cTZ"]), cKAP = Rwd.F64(g["cKAP"]), cW = Rwd.F64(g["cW"]),
                cBT = Rwd.F64(g["cBT"]), cE = Rwd.F64(g["cE"]), cRD = Rwd.F64(g["cRD"]), cRK = Rwd.F64(g["cRK"]),
                cLN = Rwd.F64(g["cLN"]), cRO = Rwd.F64(g["cRO"]), cROS = Rwd.F64(g["cROS"]), cDL = Rwd.F64(g["cDL"]),
                c_drops = Rwd.F64(g["c_drops"]),
                c_gx0 = Rwd.L(g["c_gx0"]), c_gz0 = Rwd.L(g["c_gz0"]), c_gnx = Rwd.L(g["c_gnx"]), c_gnz = Rwd.L(g["c_gnz"]),
                c_seg = Rwd.F64(g["c_seg"]), c_run_start = Rwd.I32(g["c_run_start"]), c_runs = Rwd.I32(g["c_runs"]),
                c_far = Rwd.F64(g["c_far"]), c_far_x0 = Rwd.L(g["c_far_x0"]), c_far_z0 = Rwd.L(g["c_far_z0"]),
                c_far_nx = Rwd.L(g["c_far_nx"]), c_far_nz = Rwd.L(g["c_far_nz"]),
                sX = Rwd.F64(g["sX"]), sZ = Rwd.F64(g["sZ"]), sS = Rwd.F64(g["sS"]),
                s_gx0 = Rwd.L(g["s_gx0"]), s_gz0 = Rwd.L(g["s_gz0"]), s_gnx = Rwd.L(g["s_gnx"]), s_gnz = Rwd.L(g["s_gnz"]),
                s_start = Rwd.I32(g["s_start"]), s_items = Rwd.I32(g["s_items"]),
                alt_pts = Rwd.F64(g["alt_pts"]), alt_lines = Rwd.F64(g["alt_lines"]),
                red_bands = (TfColor[])g["red_bands"], grey_bands = (TfColor[])g["grey_bands"],
                course = g["course"],
            };
            foreach (var kv in (Dictionary<object, object>)g["col"]) t.col[(string)kv.Key] = (TfColor)kv.Value;
            foreach (var a in (List<object>)g["alt_feats"])
            {
                var l = (List<object>)a;
                var e = new long[l.Count];
                for (int i = 0; i < l.Count; i++) e[i] = Rwd.L(l[i]);
                t.alt_feats.Add(e);
            }
            foreach (var o in (List<object>)g["route_feats"])
            {
                var j = (RwdObject)o;
                t.route_feats.Add(new FeatDesc
                {
                    x = Rwd.D(j["x"]), z = Rwd.D(j["z"]), dx = Rwd.D(j["dx"]), dz = Rwd.D(j["dz"]), type = (string)j["type"],
                    b0 = Rwd.D(j["b0"]), b1 = Rwd.D(j["b1"]), size = (int)Rwd.L(j["size"]), s = Rwd.D(j["s"]),
                });
            }
            foreach (var kv in land)
                if (kv.Value is double || kv.Value is long) t.land[(string)kv.Key] = Rwd.D(kv.Value);
            return t;
        }

    }
}
