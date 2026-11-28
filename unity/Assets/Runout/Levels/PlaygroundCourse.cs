// Engine-free port of godot/dev/playground/playground_course.gd (line for line; checked against Godot by
// unity/SimTests PLAYGROUND, reference written by godot/tools/pg_dump.gd) + PlacedFeature (Unity-side editor: any
// lane feature put down anywhere). C# 9, .NET Standard 2.1.
//
// The test playground's ground: a flat plane (y = 0) with straight test lanes along +x, each a row of measured
// features with a flat run-in between them, plus berm bowls and open flat ground. Pure data + height function.
// Godot conventions (right-handed, y up, heading 0 = +x, direction (cos yaw, -sin yaw)); a lane's v (across) = z - lane z.
using System.Collections.Generic;
using Runout.Sim;
using static Runout.Sim.Gd;

namespace Runout.Levels
{
	/// Godot's Rect2 (float32 components, Godot's has_point / merge / grow / expand). x, z = position; w, h = size.
	public struct Rect4
	{
		public float x, z, w, h;
		public Rect4(double x, double z, double w, double h) { this.x = (float)x; this.z = (float)z; this.w = (float)w; this.h = (float)h; }
		public double end_x => x + w;   // (float sum, like Rect2.end)
		public double end_z => z + h;
		public bool has_point(double px, double pz)
		{
			float fx = (float)px, fz = (float)pz;
			if (fx < x) return false;
			if (fz < z) return false;
			if (fx >= x + w) return false;
			if (fz >= z + h) return false;
			return true;
		}
		public Rect4 merge(Rect4 o)
		{
			float px = o.x < x ? o.x : x, pz = o.z < z ? o.z : z;
			float ex1 = o.x + o.w, ez1 = o.z + o.h, ex2 = x + w, ez2 = z + h;
			float ex = ex1 > ex2 ? ex1 : ex2, ez = ez1 > ez2 ? ez1 : ez2;
			var r = new Rect4 { x = px, z = pz };
			r.w = ex - px; r.h = ez - pz;
			return r;
		}
		public Rect4 grow(double by)
		{
			float b = (float)by;
			var r = this;
			r.x -= b; r.z -= b; r.w += b * 2f; r.h += b * 2f;
			return r;
		}
		/// Rect2.expand: grown to hold the point
		public Rect4 expand(V2 p)
		{
			float bx = x, bz = z, ex = x + w, ez = z + h;
			if (p.fx < bx) bx = p.fx;
			if (p.fy < bz) bz = p.fy;
			if (p.fx > ex) ex = p.fx;
			if (p.fy > ez) ez = p.fy;
			var r = new Rect4 { x = bx, z = bz };
			r.w = ex - bx; r.h = ez - bz;
			return r;
		}
		public override string ToString() => $"[{x}, {z}, {w}, {h}]";
	}

	/// a rock collider (dome) as the ride's Terrain makes them
	public sealed class Rock
	{
		public double x, z, r, top, @base, sink, sx, sy, sc, yaw;
	}

	/// a feature (GDScript: a Dictionary). Keys a feature didn't set keep these defaults.
	public sealed class Feature
	{
		public string id, name, desc;
		public double u0, u1;
		public double lip = -1.0;        // u of the lip / brake line, -1 = none
		public double top;
		public string lane = "";         // the lane id ("" = bowl / ramp / placed)
		public double lip_deg;
		public double land0 = -1.0, land1 = -1.0;   // the landing slope / deck to aim for (jumps)
		public bool jump;
		public string kind;              // null | "brake" | "slalom"
		public string which;             // brake: both | front | rear
		public int surf = -1;            // brake: surface id
		public double gap;               // slalom: cone spacing
		public int n;                    // slalom: cones
		public JumpDesignResult design;  // designed jumps / ramps
		public Bowl bowl;                // bowls
		public PlacedRamp ramp;          // ramps (Godot's ramp editor)
		public PlacedFeature placed;     // features put down with the Unity editor
	}

	public sealed class Lane
	{
		public string id = "";
		public string title = "";
		public double z;
		public double hw = 3.0;          // riding half width
		public double band = 8.0;        // half width of its ground strip
		public List<float> h = new List<float>();   // PackedFloat32Array
		public List<byte> m = new List<byte>();     // 1 = a jump / pump feature here
		public List<Feature> feats = new List<Feature>();
		public List<double[]> camber = new List<double[]>();   // [u0, u1, tan(angle)] (uphill to +z)
		public List<double[]> skews = new List<double[]>();    // [u0, u1, tan(angle)] hips
		public List<double[]> surfs = new List<double[]>();    // [u0, u1, surface id]
		public List<double[]> cones = new List<double[]>();    // [u, v]
		public Rect4 rect;
		public List<double[]> rock_specs = new List<double[]>();   // [u, v, sc, sx, sy, yaw]
		// the turtle
		public double y = 0.0;
		public double s = 0.0;
		public int mask = 0;
		Feature _f;

		const double DU = PlaygroundCourse.DU;

		public double u() => h.Count * DU;
		public double length() => h.Count * DU;

		void _push() { h.Add((float)y); m.Add((byte)mask); }

		public void flat(double L)
		{
			s = 0.0;
			int c = (int)round(L / DU);
			for (int i = 0; i < c; i++) _push();
		}

		public void line(double L)
		{
			int c = (int)round(L / DU);
			for (int i = 0; i < c; i++) { y += tan(s) * DU; _push(); }
		}

		public void line_to(double yt)
		{
			double t = tan(s);
			if (absf(t) < 1e-6) return;
			int guard = 0;
			while (((t > 0.0 && y < yt) || (t < 0.0 && y > yt)) && guard < 200000)
			{
				y += t * DU;
				if ((t > 0.0 && y > yt) || (t < 0.0 && y < yt)) y = yt;
				_push(); guard += 1;
			}
		}

		public void bend(double deg, double R, double floor_y = double.NegativeInfinity)
		{
			double to = deg_to_rad(deg);
			int guard = 0;
			while (absf(s - to) > 1e-5 && guard < 200000)
			{
				s = move_toward(s, to, DU / (R * maxf(0.2, cos(s))));
				y = maxf(floor_y, y + tan(s) * DU); _push(); guard += 1;
			}
		}

		public void descend(double deg, double rk, double rt)
		{
			double k = 1.0 - cos(deg_to_rad(deg));
			double sc = minf(1.0, y / maxf(1e-4, (rk + rt) * k));
			rk *= sc; rt *= sc;
			bend(-deg, maxf(0.05, rk), 0.0); line_to(rt * k); bend(0.0, maxf(0.05, rt), 0.0);
			y = 0.0;
		}

		public void wall_to(double yt) { y = yt; s = 0.0; _push(); }

		public void begin(string id_, string name_, string desc, bool jump = true)
		{
			mask = jump ? 1 : 0;
			_f = new Feature { id = id_, name = name_, desc = desc, u0 = u(), u1 = u(), lip = -1.0, top = 0.0, lane = id,
				lip_deg = 0.0, land0 = -1.0, land1 = -1.0, jump = jump };
		}

		public void lip() { if (_f != null) _f.lip = u(); }

		public void end()
		{
			if (_f == null) return;
			_f.u1 = u();
			double top = 0.0;
			int i1 = (int)mini(h.Count, (int)(_f.u1 / DU) + 1);
			for (int i = (int)(_f.u0 / DU); i < i1; i++) top = maxf(top, absf(h[i]));
			_f.top = top;
			feats.Add(_f);
			_f = null;
			mask = 0;
			y = 0.0; s = 0.0;
		}

		// ---- features
		public void rollin()
		{
			flat(0.0);
			begin("rollin_" + id, "ROLL-IN", fmt("%.0f m deck, %.0f deg", PlaygroundCourse.ROLLIN_H, PlaygroundCourse.ROLLIN_DEG), false);
			y = PlaygroundCourse.ROLLIN_H; flat(10.0);
			bend(-PlaygroundCourse.ROLLIN_DEG, 6.0); line_to(8.0 * (1.0 - cos(deg_to_rad(PlaygroundCourse.ROLLIN_DEG)))); bend(0.0, 8.0);
			end();
			flat(PlaygroundCourse.RUN * 0.6);
		}

		void _kick(double hh, double deg)
		{
			double a = deg_to_rad(deg);
			bend(deg, hh / maxf(0.01, 1.0 - cos(a)));
			lip();
			s = deg_to_rad(-50.0); line_to(0.0); s = 0.0;
		}

		public void hop(double hh, double deg)
		{
			begin(fmt("hop_%s", _n(hh)), "HOP", fmt("%.2f m, %.0f deg lip", hh, deg));
			_kick(hh, deg); end(); flat(14.0);
		}

		public void table(double hh, double up, double deck, double down)
		{
			begin(fmt("table_%s", _n(hh)), fmt("TABLE %.1f m", hh), fmt("%.0f deg lip, deck %.0f m, %.0f deg landing", up, deck, down));
			double a = deg_to_rad(up);
			double rk = minf(2.0, 0.25 * hh / maxf(0.01, 1.0 - cos(a)));
			bend(up, 0.7 * hh / maxf(0.01, 1.0 - cos(a)));
			line_to(hh - rk * (1.0 - cos(a)));
			lip(); _f.lip_deg = up;
			bend(0.0, rk); flat(deck);
			_f.land0 = u();
			descend(down, 2.0, 6.0);
			_f.land1 = u();
			end(); flat(PlaygroundCourse.RUN);
		}

		public void gap(double hh, double deg, double gap_m, double land_h, double land_deg)
		{
			begin(fmt("gap_%s", _n(gap_m)), fmt("GAP %.0f m", gap_m), fmt("%.1f m kicker %.0f deg, landing %.1f m %.0f deg", hh, deg, land_h, land_deg));
			double a = deg_to_rad(deg);
			bend(deg, hh / maxf(0.01, 1.0 - cos(a)));
			lip(); _f.lip_deg = deg;
			double ul = u();
			s = deg_to_rad(-50.0); line_to(0.0); s = 0.0;
			flat(maxf(0.0, gap_m - (u() - ul) - land_h - 0.6));
			s = deg_to_rad(45.0); line_to(land_h); s = 0.0;
			flat(0.6);
			_f.land0 = u();
			descend(land_deg, 2.0, 7.0);
			_f.land1 = u();
			end(); flat(PlaygroundCourse.RUN);
		}

		public void drop(double hh)
		{
			begin(fmt("drop_%s", _n(hh)), fmt("DROP %.1f m", hh), "8 deg run-up, flat lip, to flat");
			bend(8.0, 10.0); line_to(hh - 10.0 * (1.0 - cos(deg_to_rad(8.0)))); bend(0.0, 10.0);
			y = hh; flat(6.0);
			lip();
			wall_to(0.0);
			end(); flat(PlaygroundCourse.RUN);
		}

		public void step_up(double hh, double deg, double gap_m, double up_h)
		{
			begin(fmt("stepup_%s", _n(up_h)), fmt("STEP-UP %.1f m", up_h), fmt("%.1f m kicker %.0f deg, deck %.0f m out", hh, deg, gap_m));
			double a = deg_to_rad(deg);
			bend(deg, hh / maxf(0.01, 1.0 - cos(a)));
			lip(); _f.lip_deg = deg;
			double ul = u();
			s = deg_to_rad(-50.0); line_to(0.0); s = 0.0;
			flat(maxf(0.0, gap_m - (u() - ul) - up_h));
			s = deg_to_rad(45.0); line_to(up_h); s = 0.0;
			_f.land0 = u();
			flat(8.0);
			_f.land1 = u();
			descend(15.0, 3.0, 6.0);
			end(); flat(PlaygroundCourse.RUN);
		}

		/// a jump laid out by JumpDesign
		public void designed(JumpParams prm)
		{
			JumpDesignResult d = JumpDesign.build(prm);
			string tag = d.kind == "gap" ? "dgap" : "dtable";
			begin(prm.id ?? fmt("%s_%s", tag, _n(JumpDesign.snappedf(d.p.v * 3.6, 1.0))),
				prm.name ?? fmt("%s %.0f km/h", d.kind == "gap" ? "DESIGNED GAP" : "DESIGNED TABLE", d.p.v * 3.6),
				JumpDesign.describe(d));
			double u0 = u();
			float[] hs = d.h;
			for (int i = 0; i < hs.Length; i++) { y = hs[i]; _push(); }
			_f.lip = u0 + d.lip_u; _f.lip_deg = d.lip_deg;
			_f.land0 = u0 + d.land0; _f.land1 = u0 + d.land1;
			_f.design = d;
			end(); flat(PlaygroundCourse.RUN);
		}

		public void rollers(double amp, double L, int n, string id_ = "roller")
		{
			begin(fmt("%s_%s", id_, _n(amp)), (id_ == "pump" ? "PUMP" : "ROLLERS") + fmt(" %.1f m", amp), fmt("%d x %.0f m wavelength", n, L));
			int c = (int)round(n * L / DU);
			for (int i = 0; i < c; i++) { y = amp * 0.5 * (1.0 - cos(TAU * i * DU / L)); _push(); }
			end(); flat(PlaygroundCourse.RUN * 0.75);
		}

		public void curb(double hh, double L)
		{
			begin(fmt("curb_%s", _n(hh)), fmt("CURB %.0f cm", hh * 100.0), fmt("square edge up, %.0f m, square edge down", L), false);
			flat(0.5); wall_to(hh); flat(L); wall_to(0.0); flat(0.5);
			end(); flat(16.0);
		}

		public void pothole(double depth, double L)
		{
			begin(fmt("hole_%s", _n(depth)), fmt("POTHOLE %.0f cm", depth * 100.0), fmt("%.1f m long, square edges", L), false);
			flat(0.5); wall_to(-depth); flat(L); wall_to(0.0); flat(0.5);
			end(); flat(16.0);
		}

		public void washboard(double amp, double L, double len_m)
		{
			begin(fmt("wash_%s", _n(amp)), fmt("WASHBOARD %.0f cm", amp * 100.0), fmt("%.1f m wavelength, %.0f m long", L, len_m), false);
			int c = (int)round(len_m / DU);
			for (int i = 0; i < c; i++) { y = amp * 0.5 * (1.0 - cos(TAU * i * DU / L)); _push(); }
			end(); flat(PlaygroundCourse.RUN * 0.6);
		}

		/// Godot's RandomNumberGenerator.randf_range (float32 arithmetic)
		static double randf_range(Pcg32 r, double from, double to)
		{
			float f = (float)from, t = (float)to;
			float v = r.Randf() * (t - f) + f;
			return v;
		}

		/// random humps (seeded): rough ground
		public void chatter(double amp, double len_m, long seed_)
		{
			begin(fmt("rough_%s", _n(amp)), fmt("ROUGH %.0f cm", amp * 100.0), fmt("random humps 0.3-1.5 m long, %.0f m", len_m), false);
			var r = new Pcg32(); r.seed = seed_;
			int left = 0; double L = 1.0; double a = 0.0; int k = 0;
			int c = (int)round(len_m / DU);
			for (int i = 0; i < c; i++)
			{
				if (left <= 0)
				{
					L = randf_range(r, 0.3, 1.5); a = amp * randf_range(r, 0.3, 1.0); left = (int)(L / DU); k = 0;
				}
				y = a * 0.5 * (1.0 - cos(TAU * k / (double)(int)(L / DU))); _push();
				k += 1; left -= 1;
			}
			end(); flat(PlaygroundCourse.RUN * 0.6);
		}

		public void slope(double deg, double len_m)
		{
			begin(fmt("slope_%s", _n(deg)), fmt("SLOPE %.0f deg", deg), fmt("%.0f%% grade, %.0f m up, 8 m top, down", tan(deg_to_rad(deg)) * 100.0, len_m), false);
			double R = 8.0;
			bend(deg, R); line(len_m); bend(0.0, R); flat(8.0);
			bend(-deg, R); line_to(R * (1.0 - cos(deg_to_rad(deg)))); bend(0.0, R);
			end(); flat(PlaygroundCourse.RUN * 0.75);
		}

		public void tilt(double deg, double len_m)
		{
			begin(fmt("camber_%s", _n(deg)), fmt("CAMBER %.0f deg", deg), fmt("side slope, %.0f m long (high side left)", len_m), false);
			double u0 = u();
			flat(len_m + 12.0);
			camber.Add(new[] { u0, u0 + len_m + 12.0, tan(deg_to_rad(deg)) });
			end(); flat(PlaygroundCourse.RUN * 0.5);
		}

		public void step_down(double deck_h, double lip_h, double deg, double gap_m, double land_h, double land_deg)
		{
			begin(fmt("stepdown_%s", _n(deck_h + lip_h - land_h)), fmt("STEP-DOWN %.1f m", deck_h + lip_h - land_h),
				fmt("deck %.1f m, %.1f m kicker %.0f deg, %.0f m to a %.1f m landing", deck_h, lip_h, deg, gap_m, land_h));
			bend(8.0, 10.0); line_to(deck_h - 10.0 * (1.0 - cos(deg_to_rad(8.0)))); bend(0.0, 10.0);
			y = deck_h; flat(6.0);
			double a = deg_to_rad(deg);
			bend(deg, lip_h / maxf(0.01, 1.0 - cos(a)));
			lip(); _f.lip_deg = deg;
			double ul = u();
			s = deg_to_rad(-50.0); line_to(0.0); s = 0.0;
			flat(maxf(0.0, gap_m - (u() - ul) - land_h - 0.6));
			s = deg_to_rad(45.0); line_to(land_h); s = 0.0;
			flat(0.6);
			_f.land0 = u();
			descend(land_deg, 2.0, 7.0);
			_f.land1 = u();
			end(); flat(PlaygroundCourse.RUN);
		}

		public void drop_land(double hh, double land_deg)
		{
			begin(fmt("dropland_%s", _n(hh)), fmt("DROP TO LANDING %.1f m", hh), fmt("8 deg run-up, flat lip, onto a %.0f deg landing", land_deg));
			bend(8.0, 10.0); line_to(hh - 10.0 * (1.0 - cos(deg_to_rad(8.0)))); bend(0.0, 10.0);
			y = hh; flat(6.0);
			lip(); _f.lip_deg = 0.0;
			wall_to(hh * 0.75);
			_f.land0 = u();
			descend(land_deg, 1.0, 7.0);
			_f.land1 = u();
			end(); flat(PlaygroundCourse.RUN);
		}

		public void hip(double hh, double up, double deck, double down, double turn)
		{
			int n0 = feats.Count;
			table(hh, up, deck, down);
			Feature f = feats[n0];
			f.id = fmt("hip_%s", _n(turn)); f.name = fmt("HIP %.0f deg", turn);
			f.desc = fmt("%.1f m table turned %.0f deg to the lane", hh, turn);
			skews.Add(new[] { f.u0, f.u1, tan(deg_to_rad(turn)) });
		}

		static readonly string[] SURF_NAMES = { "GRASS", "DIRT", "WET", "SAND" };

		/// a flat strip on one surface with a brake line (which: both / front / rear). surf: 0 grass, 1 dirt, 2 wet, 3 sand
		public void brake_strip(int surf, string which)
		{
			string sname = SURF_NAMES[clampi(surf, 0, 3)];
			string id_ = fmt("brake_%s%s", sname.ToLowerInvariant(), which == "both" ? "" : "_" + which);
			begin(id_, fmt("BRAKE %s%s", sname, which == "both" ? "" : " · " + which.ToUpperInvariant() + " ONLY"),
				"brake line at the post, stopping distance measured", false);
			double u0 = u();
			flat(4.0);
			lip();
			flat(26.0);
			_f.kind = "brake"; _f.which = which; _f.surf = surf;
			if (surf != 1) surfs.Add(new[] { _f.lip - 0.3, u() + 2.0, surf });
			end(); flat(PlaygroundCourse.RUN * 0.6);
		}

		public void slalom(int n, double gap)
		{
			begin(fmt("slalom_%s", _n(gap)), fmt("SLALOM %.0f m", gap), fmt("%d cones %.0f m apart, pass them on alternate sides", n, gap), false);
			flat(4.0);
			for (int i = 0; i < n; i++)
			{
				cones.Add(new[] { u(), 0.0 });
				flat(gap);
			}
			_f.kind = "slalom"; _f.gap = gap; _f.n = n;
			end(); flat(PlaygroundCourse.RUN);
		}

		// ---- rocks
		public static double rock_top(double sc, double ky) => sc * (0.9 * ky - 0.3);

		public void rock_row(double sc, double ky, int n, double gap)
		{
			double hh = rock_top(sc, ky);
			begin(fmt("rock_%s", _n(JumpDesign.snappedf(hh * 100.0, 1.0))), fmt("ROCK %.0f cm", hh * 100.0),
				fmt("%d in a row, %.0f cm across, %.0f m apart", n, sc * 2.25 * 0.9 * 100.0, gap), false);
			flat(2.0);
			for (int i = 0; i < n; i++)
			{
				rock_specs.Add(new[] { u(), 0.0, sc, sc * 1.25, sc * ky, 0.7 * i });
				flat(gap);
			}
			end(); flat(14.0);
		}

		public void rock_garden(double len_m, long seed_, bool clean)
		{
			begin("garden_" + (clean ? "line" : "full"), "ROCK GARDEN" + (clean ? "" : " (no clean line)"), fmt("like the trail's, %.0f m", len_m), false);
			var r = new Pcg32(); r.seed = seed_;
			double u0 = u();
			int ni = (int)(len_m / 2.0);
			for (int i = 0; i < ni; i++)
			{
				double line_a = sin(i * 0.23) * hw * 0.55;
				for (int k = 0; k < 4; k++)
				{
					double a = (r.randf() * 2.0 - 1.0) * (hw - 0.15);
					double du = r.randf() * 2.0;
					if (clean && absf(a - line_a) < 0.45 && r.randf() < 0.8) continue;
					double r1 = r.randf();
					double sc = 0.13 + r1 * r1 * 0.34;
					double sx = sc * (1.0 + r.randf() * 0.5);
					double sy = sc * (0.5 + r.randf() * 0.35);
					double yw = r.randf() * TAU;
					rock_specs.Add(new[] { u0 + i * 2.0 + du, a, sc, sx, sy, yw });
				}
			}
			flat(len_m);
			end(); flat(PlaygroundCourse.RUN * 0.6);
		}

		/// str(snappedf(v, 0.01)).trim_suffix(".0")
		public static string _n(double v)
		{
			string t = str(JumpDesign.snappedf(v, 0.01));
			return t.EndsWith(".0") ? t.Substring(0, t.Length - 2) : t;
		}

		// ---- the surface
		public double profile(double uu)
		{
			if (uu <= 0.0 || h.Count == 0) return 0.0;
			double f = uu / DU;
			int i = (int)f;
			if (i >= h.Count - 1) return i == h.Count - 1 ? h[h.Count - 1] : 0.0;
			return lerpf(h[i], h[i + 1], f - i);
		}

		public double tilt_at(double uu)
		{
			foreach (var c in camber)
				if (uu > c[0] && uu < c[1])
					return c[2] * smoothstep(c[0], c[0] + 6.0, uu) * (1.0 - smoothstep(c[1] - 6.0, c[1], uu));
			return 0.0;
		}

		public double skew_u(double uu, double v)
		{
			foreach (var k in skews)
				if (uu > k[0] - 4.0 && uu < k[1] + 4.0)
					return uu - clampf(v, -hw - 3.0, hw + 3.0) * k[2];
			return uu;
		}

		/// height at (along, across); v = 0 is the lane's middle
		public double at(double uu, double v)
		{
			if (skews.Count > 0) uu = skew_u(uu, v);
			double p = profile(uu);
			double d = maxf(0.0, absf(v) - hw);
			double t = camber.Count > 0 ? tilt_at(uu) : 0.0;
			if (t != 0.0)
			{
				double vv = clampf(v, -hw, hw);
				p += (vv + hw) * t;
			}
			if (p >= 0.0) return maxf(0.0, p - d * PlaygroundCourse.SIDE);
			return minf(0.0, p + d * PlaygroundCourse.SIDE);
		}

		public double jump_at(double uu, double v)
		{
			if (skews.Count > 0) uu = skew_u(uu, v);
			if (uu <= 0.0 || absf(v) > hw + 2.0) return 0.0;
			int i = (int)(uu / DU);
			return i < m.Count ? m[i] : 0.0;
		}
	}

	public sealed class Bowl
	{
		public string id = "";
		public string title = "";
		public V2 c;          // centre (x, z)
		public double R;      // track centre radius
		public double W;      // banked width
		public double tn;     // tan(bank)
		public double deg;
		public double open_dir = PI;   // the gap you ride in through (PI = faces -x)
		public Rect4 rect;

		/// a banked ring (flat inside, the bank rising outward, a batter outside) with a gap at open_dir
		public double at(double x, double z)
		{
			double dx = x - c.x; double dz = z - c.y;
			double r = sqrt(dx * dx + dz * dz);
			double r0 = R - W * 0.5;
			if (r <= r0) return 0.0;
			double top = W * tn;
			double hh = r <= r0 + W ? (r - r0) * tn : maxf(0.0, top - (r - r0 - W) * PlaygroundCourse.SIDE);
			double ang = absf(wrapf(atan2(dz, dx) - open_dir, -PI, PI));
			return hh * smoothstep(deg_to_rad(22.0), deg_to_rad(48.0), ang);
		}
	}

	/// a jump put down anywhere with Godot's ramp editor: JumpDesign's shape on its own axis
	public sealed class PlacedRamp
	{
		public string id = "";
		public V2 pos = V2.ZERO;    // world (x, z) of its lip
		public double yaw = 0.0;    // heading (0 = +x; direction (cos, -sin))
		public JumpParams prm = new JumpParams();
		public JumpDesignResult d;
		public Feature feat;
		public Rect4 rect;
		public double reach;

		public V2 dir() => new V2(cos(yaw), -sin(yaw));
		public V2 side() => new V2(sin(yaw), cos(yaw));
		public V2 origin() => pos - dir() * d.lip_u;
		public V2 local(double x, double z)
		{
			V2 q = new V2(x, z) - origin();
			return new V2(q.dot(dir()), q.dot(side()));
		}
		public double at_local(double uu, double vv)
		{
			if (uu <= 0.0 || uu >= d.length) return 0.0;
			double hh = JumpDesign.sample(d.h, uu);
			if (wood()) return absf(vv) <= prm.width * 0.5 ? hh : 0.0;
			double o = maxf(0.0, absf(vv) - prm.width * 0.5);
			return maxf(0.0, hh - o * PlaygroundCourse.SIDE);
		}
		public double at(double x, double z)
		{
			if (!rect.has_point(x, z)) return 0.0;
			V2 l = local(x, z);
			return at_local(l.x, l.y);
		}
		public bool wood() => prm.build == "wood";

		public void rebuild()
		{
			d = JumpDesign.build(prm);
			double top = 0.0;
			foreach (float hh in d.h) top = maxf(top, hh);
			reach = prm.width * 0.5 + (wood() ? 0.0 : top * PlaygroundCourse.SIDE) + 0.2;
			V2 o = origin();
			V2 a = o - side() * reach; V2 b = o + side() * reach;
			V2 e = dir() * d.length;
			rect = new Rect4 { x = a.fx, z = a.fy }.expand(b).expand(a + e).expand(b + e).grow(0.2);
			feat = new Feature { id = id, name = "RAMP " + (id.StartsWith("ramp_") ? id.Substring(5) : id), desc = JumpDesign.describe(d),
				u0 = d.face_u, u1 = d.length, lip = d.lip_u, top = top, lane = "", lip_deg = d.lip_deg,
				land0 = d.kind != "kicker" ? d.land0 : -1.0, land1 = d.kind != "kicker" ? d.land1 : -1.0,
				jump = true, ramp = this, design = d };
		}
	}

	/// NEW (Unity editor, not in Godot): any lane feature put down anywhere, on its own axis. Its profile is built by a
	/// private Lane exactly as the lanes build it (flat 2 m, the feature, flat 2 m), so it has the lanes' shape (camber,
	/// skews, rocks, surfaces included). Its frame: u along dir() from origin() = (x, z) = where the feature starts
	/// (feat.u0 = 0; the profile runs from u = -LEAD to `length`), v across (+ = side()). "bowl" = a Bowl centred at (x, z).
	public sealed class PlacedFeature
	{
		public const double LEAD = 2.0;   // flat before the feature (u < 0)

		public string kind;
		public double[] args;
		public JumpParams prm;    // "designed" (made from args when null)
		public double x, z, yaw;
		public double width = 3.0;     // riding half width
		public string id = "";

		public Feature feat;
		public Rect4 rect;             // world bounds incl. the side batter
		public double length;          // u where the profile ends (it starts at -LEAD)
		public double reach;           // half width incl. the batter
		public List<Rock> rocks = new List<Rock>();
		public Lane lane;              // the private profile (u_lane = u + LEAD); null for a bowl
		public Bowl bowl;              // "bowl"

		public static PlacedFeature make(string kind, double[] args, double x, double z, double yaw = 0.0, double width = 3.0, string id = "")
		{
			var pf = new PlacedFeature { kind = kind, args = args ?? new double[0], x = x, z = z, yaw = yaw, width = width, id = id ?? "" };
			pf.rebuild();
			return pf;
		}

		public V2 origin() => new V2(x, z);
		public V2 dir() => new V2(cos(yaw), -sin(yaw));
		public V2 side() => new V2(sin(yaw), cos(yaw));

		double A(int i, double dflt) => args != null && i < args.Length ? args[i] : dflt;

		/// (u, v) of a world point in its own frame
		public V2 local(double wx, double wz)
		{
			double dx = wx - x, dz = wz - z;
			double c = cos(yaw), s = sin(yaw);
			return new V2(dx * c - dz * s, dx * s + dz * c);
		}
		void _local(double wx, double wz, out double u, out double v)
		{
			double dx = wx - x, dz = wz - z;
			double c = cos(yaw), s = sin(yaw);
			u = dx * c - dz * s; v = dx * s + dz * c;
		}
		/// world (x, z) of a point in its frame (V2 = float32; world_xz = the same in doubles)
		public V2 world(double u, double v)
		{
			world_xz(u, v, out double wx, out double wz);
			return new V2(wx, wz);
		}
		public void world_xz(double u, double v, out double wx, out double wz)
		{
			double c = cos(yaw), s = sin(yaw);
			wx = x + u * c + v * s; wz = z - u * s + v * c;
		}

		public void rebuild()
		{
			rocks.Clear();
			lane = null; bowl = null;
			if (kind == "bowl")
			{
				var bw = new Bowl { id = id != "" ? id : "placed_bowl", R = A(0, 12.0), W = A(1, 5.0), deg = A(2, 30.0) };
				bw.title = fmt("BERM R%.0f · %.0f deg", bw.R, bw.deg);
				bw.tn = tan(deg_to_rad(bw.deg));
				bw.c = new V2(x, z);
				bw.open_dir = PI - yaw;
				double rch = bw.R + bw.W * 0.5 + bw.W * bw.tn / PlaygroundCourse.SIDE + 1.0;
				bw.rect = new Rect4(x - rch, z - rch, rch * 2.0, rch * 2.0);
				bowl = bw;
				reach = rch; length = rch;
				rect = bw.rect;
				feat = new Feature { id = bw.id, name = bw.title, desc = fmt("banked ring, %.0f m wide, ride in from the west", bw.W), bowl = bw,
					lane = "", u0 = 0.0, u1 = 0.0, lip = -1.0, top = bw.W * bw.tn, placed = this };
				return;
			}
			var l = new Lane { id = "", title = kind, z = 0.0, hw = width, band = width + 8.0 };
			l.flat(LEAD);
			switch (kind)
			{
				case "table": l.table(A(0, 1.5), A(1, 32), A(2, 4), A(3, 30)); break;
				case "gap": l.gap(A(0, 1.6), A(1, 35), A(2, 7), A(3, 1.7), A(4, 35)); break;
				case "hop": l.hop(A(0, 0.4), A(1, 25)); break;
				case "drop": l.drop(A(0, 1.0)); break;
				case "step_up": l.step_up(A(0, 0.8), A(1, 30), A(2, 3), A(3, 1.0)); break;
				case "step_down": l.step_down(A(0, 1.2), A(1, 0.6), A(2, 28), A(3, 4), A(4, 0.8), A(5, 30)); break;
				case "drop_land": l.drop_land(A(0, 1.5), A(1, 30)); break;
				case "hip": l.hip(A(0, 1.5), A(1, 32), A(2, 4), A(3, 30), A(4, 20)); break;
				case "rollers": l.rollers(A(0, 0.6), A(1, 6), (int)A(2, 5)); break;
				case "pump": l.rollers(A(0, 0.8), A(1, 5), (int)A(2, 8), "pump"); break;
				case "curb": l.curb(A(0, 0.2), A(1, 3)); break;
				case "pothole": l.pothole(A(0, 0.15), A(1, 1)); break;
				case "washboard": l.washboard(A(0, 0.05), A(1, 0.5), A(2, 30)); break;
				case "chatter": l.chatter(A(0, 0.15), A(1, 40), (long)A(2, 11)); break;
				case "slope": l.slope(A(0, 10), A(1, 24)); break;
				case "camber": l.tilt(A(0, 15), A(1, 24)); break;
				case "rock_row": l.rock_row(A(0, 0.3), A(1, 0.7), (int)A(2, 4), A(3, 4)); break;
				case "rock_garden": l.rock_garden(A(0, 40), (long)A(1, 7), A(2, 1) != 0.0); break;
				case "brake_strip": l.brake_strip((int)A(0, 1), A(1, 0) == 1 ? "front" : (A(1, 0) == 2 ? "rear" : "both")); break;
				case "slalom": l.slalom((int)A(0, 8), A(1, 8)); break;
				case "designed":
					var p = prm;
					if (p == null)
					{
						p = new JumpParams { v = A(0, 12.0), lip_deg = A(1, 26.0), kind = A(2, 0) != 0.0 ? "gap" : "table" };
						if (id != "") p.id = id;
					}
					l.designed(p);
					break;
				default: l.table(1.5, 32, 4, 30); break;
			}
			l.flat(LEAD);
			lane = l;
			length = l.length() - LEAD;
			feat = l.feats.Count > 0 ? l.feats[0] : new Feature { id = kind, name = kind, desc = "" };
			feat.u0 -= LEAD; feat.u1 -= LEAD;
			if (feat.lip >= 0.0) feat.lip -= LEAD;
			if (feat.land0 >= 0.0) feat.land0 -= LEAD;
			if (feat.land1 >= 0.0) feat.land1 -= LEAD;
			if (id != "") feat.id = id;
			feat.lane = "";
			feat.placed = this;
			// bounds: the highest / deepest point (camber adds its rise), the rocks, the hips' slide along u
			double top = 0.0;
			foreach (float hh in l.h) top = maxf(top, absf(hh));
			double ct = 0.0;
			foreach (var c in l.camber) ct = maxf(ct, absf(c[2]) * 2.0 * width);
			reach = width + (top + ct) * PlaygroundCourse.SIDE + 0.2;
			foreach (var s in l.rock_specs)
			{
				double sc = s[2];
				double r = (s[3] + sc) * 0.45;
				reach = maxf(reach, absf(s[1]) + r + 0.2);
				world_xz(s[0] - LEAD, s[1], out double rx, out double rz);
				rocks.Add(new Rock { x = rx, z = rz, r = r, @base = 0.0, top = -sc * 0.3 + s[4] * 0.9, sink = sc * 0.3,
					sx = s[3], sy = s[4], sc = sc, yaw = s[5] + yaw });
			}
			double sk = 0.0;
			foreach (var k in l.skews) sk = maxf(sk, absf(k[2]) * (width + 3.0));
			double ua = -LEAD - sk, ub = length + sk;
			V2 p0 = world(ua, -reach), p1 = world(ua, reach), p2 = world(ub, -reach), p3 = world(ub, reach);
			rect = new Rect4 { x = p0.fx, z = p0.fy }.expand(p1).expand(p2).expand(p3).grow(0.2);
		}

		/// height in its own frame (0 outside the profile)
		public double at_local(double u, double v)
		{
			if (bowl != null) { world_xz(u, v, out double wx, out double wz); return bowl.at(wx, wz); }
			return lane.at(u + LEAD, v);
		}

		public double at(double wx, double wz)
		{
			if (!rect.has_point(wx, wz)) return 0.0;
			if (bowl != null) return bowl.at(wx, wz);
			_local(wx, wz, out double u, out double v);
			return lane.at(u + LEAD, v);
		}

		public double jump_at(double wx, double wz)
		{
			if (bowl != null || !rect.has_point(wx, wz)) return 0.0;
			_local(wx, wz, out double u, out double v);
			return lane.jump_at(u + LEAD, v);
		}

		/// surface id where it sets one (brake strips), else -1
		public int surface_at(double wx, double wz)
		{
			if (bowl != null || !rect.has_point(wx, wz)) return -1;
			_local(wx, wz, out double u, out double v);
			if (absf(v) > lane.hw + 1.0) return -1;
			double uu = u + LEAD;
			foreach (var sf in lane.surfs)
				if (uu >= sf[0] && uu <= sf[1]) return (int)sf[2];
			return -1;
		}

		/// built dirt: the riding width along the feature (+-2 m) and every raised / dug bit
		public bool is_dirt(double wx, double wz)
		{
			if (!rect.has_point(wx, wz)) return false;
			if (bowl != null) return bowl.at(wx, wz) > 0.01;
			_local(wx, wz, out double u, out double v);
			if (absf(v) <= lane.hw + 0.6 && u >= feat.u0 - LEAD && u <= feat.u1 + LEAD) return true;
			return absf(lane.at(u + LEAD, v)) > 0.01;
		}

		/// its riding zone (6 m before, 10 m after the feature, its width + 3 m)
		public bool in_zone(double wx, double wz)
		{
			if (bowl != null) return bowl.rect.has_point(wx, wz);
			_local(wx, wz, out double u, out double v);
			return u >= feat.u0 - 6.0 && u <= feat.u1 + 10.0 && absf(v) < reach + 3.0;
		}

		/// (x, heading, z): `back` m before it on its axis (a bowl: in front of its gap)
		public V3 spawn(double back)
		{
			if (bowl != null)
			{
				double d = bowl.R + bowl.W + 14.0;
				return new V3(x - cos(yaw) * d, yaw, z + sin(yaw) * d);
			}
			V2 p = world(feat.u0 - back, 0.0);
			return new V3(p.x, yaw, p.y);
		}
	}

	public sealed class PlaygroundCourse
	{
		public const double DU = 0.05;
		public const double SIDE = 1.0;
		public const double X0 = -30.0;
		public const double ROLLIN_H = 4.0;
		public const double ROLLIN_DEG = 14.0;
		public const double RUN = 32.0;
		public const double SNAP = 4.0;
		public const double ROCK_CELL = 2.0;

		public List<Lane> lanes = new List<Lane>();
		public List<Bowl> bowls = new List<Bowl>();
		public List<Feature> feats = new List<Feature>();   // every lane feature + bowl, flat (not ramps / placed)
		public Rect4 bounds;
		public List<Rock> rocks = new List<Rock>();         // the lanes' rocks (placed ones: PlacedFeature.rocks)
		public List<PlacedRamp> ramps = new List<PlacedRamp>();
		public List<PlacedFeature> placed = new List<PlacedFeature>();
		readonly Dictionary<(long, long), List<Rock>> _rock_cells = new Dictionary<(long, long), List<Rock>>();
		readonly Dictionary<(long, long), List<Rock>> _placed_cells = new Dictionary<(long, long), List<Rock>>();
		static readonly List<Rock> NONE = new List<Rock>();

		public PlaygroundCourse(bool lanes = true) { _build(lanes); }

		// ---- placed features
		public PlacedFeature add_placed(PlacedFeature pf)
		{
			if (pf != null && !placed.Contains(pf)) { placed.Add(pf); _index_placed(); }
			return pf;
		}
		public void remove_placed(PlacedFeature pf) { placed.Remove(pf); _index_placed(); }
		public void clear_placed() { placed.Clear(); _index_placed(); }
		/// after changing a placed feature (moved / new args): pf.rebuild() then this
		public void reindex() => _index_placed();

		void _index_placed()
		{
			_placed_cells.Clear();
			foreach (var pf in placed)
				foreach (var rk in pf.rocks) _cell_add(_placed_cells, rk);
		}

		static void _cell_add(Dictionary<(long, long), List<Rock>> cells, Rock rk)
		{
			for (long gx = floori((rk.x - rk.r) / ROCK_CELL); gx <= floori((rk.x + rk.r) / ROCK_CELL); gx++)
				for (long gz = floori((rk.z - rk.r) / ROCK_CELL); gz <= floori((rk.z + rk.r) / ROCK_CELL); gz++)
				{
					var key = (gx, gz);
					if (!cells.TryGetValue(key, out var lst)) cells[key] = lst = new List<Rock>();
					lst.Add(rk);
				}
		}

		// ---- placed ramps (Godot's ramp editor; save / load are Godot-only)
		public PlacedRamp add_ramp(JumpParams prm, V2 at, double yaw, string id = "")
		{
			var r = new PlacedRamp();
			if (id == "")
			{
				int n = 1;
				while (ramp_by_id("ramp_" + n) != null) n += 1;
				id = "ramp_" + n;
			}
			r.id = id; r.pos = at; r.yaw = yaw; r.prm = JumpDesign.@params(prm);
			r.rebuild();
			ramps.Add(r);
			return r;
		}
		public void remove_ramp(PlacedRamp r) => ramps.Remove(r);
		public PlacedRamp ramp_by_id(string id)
		{
			foreach (var r in ramps) if (r.id == id) return r;
			return null;
		}
		public PlacedRamp ramp_zone(double x, double z, double back = 40.0)
		{
			foreach (var r in ramps)
			{
				V2 l = r.local(x, z);
				if (l.x > -back && l.x < r.d.length + 16.0 && absf(l.y) < r.reach + 3.0) return r;
			}
			return null;
		}
		/// u along the frame of whatever is at (x, z): a placed ramp's / feature's own axis, else the lanes' (x - X0)
		public double u_for(double x, double z)
		{
			var r = ramp_zone(x, z);
			if (r != null) return r.local(x, z).x;
			foreach (var pf in placed)
				if (pf.bowl == null && pf.in_zone(x, z)) return pf.local(x, z).x;
			return x - X0;
		}

		Lane _lane(string id, string title, double z, double band = 8.0, double hw = 3.0)
		{
			var l = new Lane { id = id, title = title, z = z, band = band, hw = hw };
			lanes.Add(l);
			l.rollin();
			return l;
		}

		void _build(bool with_lanes)
		{
			if (with_lanes)
			{
				Lane l;
				l = _lane("tables", "TABLES", 0.0);
				foreach (var t in new[] { new[] { 0.6, 25, 2, 25 }, new[] { 1.0, 30, 3, 28 }, new[] { 1.5, 32, 4, 30 }, new[] { 2.0, 35, 5, 32 }, new[] { 2.5, 38, 6, 35 }, new[] { 3.0, 40, 7, 38 } })
					l.table(t[0], t[1], t[2], t[3]);
				l = _lane("gaps", "GAPS", 20.0);
				foreach (var g in new[] { new[] { 0.8, 30, 3, 0.9, 30 }, new[] { 1.2, 33, 5, 1.3, 32 }, new[] { 1.6, 35, 7, 1.7, 35 }, new[] { 2.2, 38, 9, 2.3, 38 }, new[] { 2.8, 40, 12, 3.0, 40 } })
					l.gap(g[0], g[1], g[2], g[3], g[4]);
				l = _lane("hops", "HOPS & ROLLERS", 40.0);
				foreach (var hp in new[] { new[] { 0.25, 20 }, new[] { 0.4, 25 }, new[] { 0.6, 30 }, new[] { 0.8, 35 } })
					l.hop(hp[0], hp[1]);
				l.flat(RUN * 0.5);
				l.rollers(0.3, 4.0, 6); l.rollers(0.6, 6.0, 5); l.rollers(1.0, 8.0, 4);
				l.rollers(0.8, 5.0, 8, "pump");
				l = _lane("drops", "DROPS & STEP-UPS", 60.0);
				foreach (var d in new[] { 0.5, 1.0, 1.5, 2.0, 3.0 })
					l.drop(d);
				l.step_up(0.8, 30, 3.0, 1.0); l.step_up(1.2, 35, 4.0, 1.6);
				l = _lane("bumps", "BUMPS & EDGES", 80.0);
				foreach (var c in new[] { 0.1, 0.2, 0.3, 0.45 })
					l.curb(c, 3.0);
				l.pothole(0.15, 1.0); l.pothole(0.3, 1.5);
				l.washboard(0.05, 0.5, 30.0); l.washboard(0.12, 1.2, 30.0);
				l.chatter(0.15, 40.0, 11); l.chatter(0.3, 40.0, 23);
				l = _lane("slopes", "SLOPES", 102.0, 10.0);
				foreach (var sl in new[] { new[] { 5, 30.0 }, new[] { 10, 24.0 }, new[] { 15, 18.0 }, new[] { 20, 14.0 }, new[] { 25, 11.0 }, new[] { 30, 9.0 }, new[] { 40, 5.5 } })
					l.slope(sl[0], sl[1]);
				l = _lane("camber", "CAMBER", 126.0, 12.0, 4.0);
				foreach (var cb in new[] { 5, 10, 15, 20, 25, 30, 35 })
					l.tilt(cb, 24.0);
				l = _lane("rocks", "ROCKS", -24.0);
				foreach (var rk in new[] { new[] { 0.13, 0.6, 5, 3.0 }, new[] { 0.22, 0.65, 5, 3.0 }, new[] { 0.3, 0.7, 4, 4.0 }, new[] { 0.38, 0.75, 4, 4.0 }, new[] { 0.47, 0.8, 3, 5.0 }, new[] { 0.47, 0.85, 3, 5.0 }, new[] { 0.8, 0.8, 1, 5.0 } })
					l.rock_row(rk[0], rk[1], (int)rk[2], rk[3]);
				l.rock_garden(40.0, 7, true); l.rock_garden(40.0, 19, false);
				l = _lane("stepdowns", "STEP-DOWNS, DROPS & HIPS", -48.0);
				l.step_down(1.2, 0.6, 28, 4.0, 0.8, 30); l.step_down(2.0, 0.8, 32, 6.0, 1.0, 34);
				l.drop_land(1.5, 30); l.drop_land(2.5, 34);
				l.hip(1.5, 32, 4, 30, 20); l.hip(1.5, 32, 4, 30, 35);
				l = _lane("designed", "DESIGNED JUMPS", -96.0);
				l.flat(20.0); l.designed(new JumpParams { id = "double_s", name = "FREE-RIDE DOUBLE", kind = "gap", v = 10.5, lip_deg = 24.0, lip_g = 1.8, lip_t = 0.12, fill = 1.0, aim = 0.3, land_g = 2.2 });
				l.flat(30.0); l.designed(new JumpParams { id = "dj_video", name = "VIDEO DIRT JUMP", v = 8.0, lip_deg = 42.0, height = 1.45, kind = "gap", land_h = 1.5 });
				foreach (var dj in new[] {
					new JumpParams { v = 8.0, lip_deg = 22.0 }, new JumpParams { v = 10.0, lip_deg = 24.0 }, new JumpParams { v = 12.0, lip_deg = 26.0 },
					new JumpParams { v = 13.5, lip_deg = 26.0 }, new JumpParams { v = 15.0, lip_deg = 25.0 }, new JumpParams { v = 11.0, lip_deg = 30.0, kind = "gap" },
					new JumpParams { v = 13.0, lip_deg = 32.0, kind = "gap" }, new JumpParams { v = 16.7, lip_deg = 28.0 }, new JumpParams { v = 18.3, lip_deg = 30.0 } })
					l.designed(dj);
				l = _lane("brakes", "BRAKES, SURFACES & SLALOM", -72.0);
				l.brake_strip(1, "both"); l.brake_strip(1, "front"); l.brake_strip(1, "rear");
				l.brake_strip(0, "both"); l.brake_strip(2, "both"); l.brake_strip(3, "both");
				l.slalom(8, 8.0); l.slalom(8, 6.0);
				foreach (var ln in lanes)
				{
					ln.flat(20.0);
					ln.rect = _snap(new Rect4(X0, ln.z - ln.band, ln.length(), ln.band * 2.0));
					foreach (var f in ln.feats) feats.Add(f);
				}
				double bz = 175.0;
				var defs = new (string, string, double, double, double, double)[] {
					("berm_20", "BERM R18 · 20 deg", 0.0, 18.0, 6.0, 20.0), ("berm_30", "BERM R10 · 30 deg", 60.0, 10.0, 5.0, 30.0),
					("berm_45", "BERM R13 · 45 deg", 110.0, 13.0, 5.0, 45.0), ("berm_60", "WALL R9 · 60 deg", 160.0, 9.0, 3.5, 60.0) };
				foreach (var b in defs)
				{
					var bw = new Bowl { id = b.Item1, title = b.Item2, R = b.Item4, W = b.Item5, deg = b.Item6, tn = tan(deg_to_rad(b.Item6)) };
					double reach = bw.R + bw.W * 0.5 + bw.W * bw.tn / SIDE + 1.0;
					bw.c = new V2(b.Item3 + reach, bz);
					bw.rect = _snap(new Rect4(bw.c.x - reach, bw.c.y - reach, reach * 2.0, reach * 2.0));
					bowls.Add(bw);
					feats.Add(new Feature { id = bw.id, name = bw.title, desc = fmt("banked ring, %.0f m wide, ride in from the west", bw.W), bowl = bw,
						lane = "", u0 = 0.0, u1 = 0.0, lip = -1.0, top = bw.W * bw.tn });
				}
				foreach (var ln in lanes)
					foreach (var s in ln.rock_specs)
					{
						double sc = s[2];
						var rk = new Rock { x = X0 + s[0], z = ln.z + s[1], r = (s[3] + sc) * 0.45, @base = 0.0, top = -sc * 0.3 + s[4] * 0.9, sink = sc * 0.3,
							sx = s[3], sy = s[4], sc = sc, yaw = s[5] };
						rocks.Add(rk);
						_cell_add(_rock_cells, rk);
					}
			}
			bounds = new Rect4(X0 - 40.0, -60.0, 700.0, 300.0);
			foreach (var ln in lanes) bounds = bounds.merge(ln.rect.grow(20.0));
			foreach (var bw in bowls) bounds = bounds.merge(bw.rect.grow(20.0));
			bounds = _snap(bounds);
		}

		static Rect4 _snap(Rect4 r)
		{
			double x0 = floorf(r.x / SNAP) * SNAP;
			double z0 = floorf(r.z / SNAP) * SNAP;
			double x1 = ceilf(r.end_x / SNAP) * SNAP;
			double z1 = ceilf(r.end_z / SNAP) * SNAP;
			return new Rect4(x0, z0, x1 - x0, z1 - z0);
		}

		/// the ground's surface id at (x, z) where a lane strip / placed feature sets one (brake strips), else -1
		public int surface_at(double x, double z)
		{
			foreach (var pf in placed)
			{
				int s = pf.surface_at(x, z);
				if (s >= 0) return s;
			}
			Lane l = lane_at(x, z);
			if (l == null || absf(z - l.z) > l.hw + 1.0) return -1;
			double uu = x - X0;
			foreach (var sf in l.surfs)
				if (uu >= sf[0] && uu <= sf[1]) return (int)sf[2];
			return -1;
		}

		public Lane lane_at(double x, double z)
		{
			foreach (var l in lanes)
				if (absf(z - l.z) <= l.band && x >= X0 && x <= X0 + l.length())
					return l;
			return null;
		}

		public Lane lane_by_id(string id)
		{
			foreach (var l in lanes) if (l.id == id) return l;
			return null;
		}

		/// the ground: the lanes / bowls, then the ramps (max) and the placed features (max where they rise, min where
		/// they dig: potholes)
		public double height(double x, double z)
		{
			double g = _height_base(x, z);
			foreach (var r in ramps)
				if (r.rect.has_point(x, z)) g = maxf(g, r.at(x, z));
			foreach (var pf in placed)
				if (pf.rect.has_point(x, z))
				{
					double h = pf.at(x, z);
					if (h > 0.0) g = maxf(g, h);
					else if (h < 0.0) g = minf(g, h);
				}
			return g;
		}

		double _height_base(double x, double z)
		{
			foreach (var l in lanes)
				if (absf(z - l.z) <= l.band)
					return l.at(x - X0, z - l.z);
			foreach (var b in bowls)
				if (b.rect.has_point(x, z))
					return b.at(x, z);
			return 0.0;
		}

		/// the rocks reaching into (x, z)'s cell (Terrain.colliders_near): the lanes' and the placed features'
		public List<Rock> rocks_near(double x, double z)
		{
			var key = (floori(x / ROCK_CELL), floori(z / ROCK_CELL));
			_rock_cells.TryGetValue(key, out var a);
			List<Rock> b = null;
			if (_placed_cells.Count > 0) _placed_cells.TryGetValue(key, out b);
			if (b == null) return a ?? NONE;
			if (a == null) return b;
			var both = new List<Rock>(a); both.AddRange(b);
			return both;
		}

		/// Terrain.dome_h: the rideable shape of a rock at q = (distance / r)^2 from its middle
		public static double dome_h(double @base, double top, double sink, double q)
		{
			double a = top - @base + sink;
			double k = a > 1e-9 ? sink / a : 0.0;
			return @base - sink + a * sqrt(1.0 - q * (1.0 - k * k));
		}

		/// the ground with a dome over every rock: exactly Terrain.height()'s formula
		public double height_rocks(double x, double z)
		{
			double g = height(x, z);
			foreach (var c in rocks_near(x, z))
			{
				double dx = x - c.x;
				double dz = z - c.z;
				double q = (dx * dx + dz * dz) / (c.r * c.r);
				if (q < 1.0)
				{
					double hh = dome_h(c.@base, c.top, c.sink, q);
					if (hh > g) g = hh;
				}
			}
			return g;
		}

		public double jump_mask(double x, double z)
		{
			foreach (var r in ramps)
				if (r.rect.has_point(x, z) && r.at(x, z) > 0.0) return 1.0;
			foreach (var pf in placed)
				if (pf.jump_at(x, z) > 0.0) return 1.0;
			foreach (var l in lanes)
				if (absf(z - l.z) <= l.band)
					return l.jump_at(x - X0, z - l.z);
			return 0.0;
		}

		/// built ground (dirt): lanes' riding width + every raised / dug bit, the bowls' banks, placed features
		public bool is_dirt(double x, double z)
		{
			foreach (var r in ramps)
				if (r.rect.has_point(x, z) && r.at(x, z) > 0.01) return true;
			foreach (var pf in placed)
				if (pf.is_dirt(x, z)) return true;
			foreach (var l in lanes)
				if (absf(z - l.z) <= l.band)
					return absf(z - l.z) <= l.hw + 0.6 || absf(height(x, z)) > 0.01;
			foreach (var b in bowls)
				if (b.rect.has_point(x, z))
					return b.at(x, z) > 0.01;
			return false;
		}

		/// the feature under / around (x, z): a ramp's / placed feature's zone, else on a lane the one whose span
		/// (+ 6 m before, + 10 m after) holds x, else a bowl
		public Feature feature_at(double x, double z)
		{
			var r = ramp_zone(x, z, 6.0);
			if (r != null) return r.feat;
			foreach (var pf in placed)
				if (pf.in_zone(x, z)) return pf.feat;
			Lane l = lane_at(x, z);
			if (l != null)
			{
				double uu = x - X0;
				foreach (var f in l.feats)
					if (uu >= f.u0 - 6.0 && uu <= f.u1 + 10.0) return f;
				return null;
			}
			foreach (var f in feats)
				if (f.bowl != null && f.bowl.rect.has_point(x, z)) return f;
			return null;
		}

		/// the world point on feature f's centre line at u (its own frame), on its surface
		public V3 feat_point(Feature f, double uu)
		{
			if (f.placed != null)
			{
				var pf = f.placed;
				V2 p = pf.world(uu, 0.0);
				return new V3(p.x, pf.at_local(uu, 0.0), p.y);
			}
			if (f.ramp != null)
			{
				var r = f.ramp;
				V2 p = r.origin() + r.dir() * uu;
				return new V3(p.x, r.at_local(uu, 0.0), p.y);
			}
			Lane l = lane_by_id(f.lane);
			if (l == null) return V3.ZERO;
			return new V3(X0 + uu, l.profile(uu), l.z);
		}

		public Feature feature_by_id(string id)
		{
			var r = ramp_by_id(id);
			if (r != null) return r.feat;
			foreach (var pf in placed) if (pf.feat.id == id) return pf.feat;
			foreach (var f in feats) if (f.id == id) return f;
			return null;
		}

		/// where to stand to ride feature f: (x, heading, z) like Game.respawn takes it
		public V3 spawn_for(Feature f, double back = 25.0)
		{
			if (f.placed != null) return f.placed.spawn(back);
			if (f.ramp != null)
			{
				var r = f.ramp;
				V2 p = r.origin() + r.dir() * (f.u0 - back);
				return new V3(p.x, r.yaw, p.y);
			}
			if (f.bowl != null)
			{
				var b = f.bowl;
				return new V3(b.c.x - b.R - b.W - 14.0, 0.0, b.c.y);
			}
			Lane l = lane_by_id(f.lane);
			double uu = !f.id.StartsWith("rollin") ? maxf(4.0, f.u0 - back) : 4.0;
			return new V3(X0 + uu, 0.0, l.z);
		}

		/// the start: top of the TABLES roll-in, (x, heading, z)
		public V3 default_spawn() => new V3(X0 + 4.0, 0.0, 0.0);
	}
}
