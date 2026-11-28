// Engine-free port of godot/scripts/world/jump_design.gd (line for line; checked against Godot by
// unity/SimTests PLAYGROUND, reference written by godot/tools/pg_dump.gd). C# 9, .NET Standard 2.1.
using System.Collections.Generic;
using Runout.Sim;
using static Runout.Sim.Gd;

namespace Runout.Levels
{
	/// JumpDesign's parameters (GDScript: a Dictionary over DEFAULTS). Field values = DEFAULTS.
	public sealed class JumpParams
	{
		public string kind = "table";   // table | gap | kicker
		public string build = "dirt";   // dirt | wood (placed ramps)
		public double v = 12.0;          // run-in speed at the foot of the face (m/s)
		public double lip_deg = 26.0;
		public double lip_g = 1.5;
		public double lip_t = 0.25;
		public double height = 0.0;      // 0 = what the curve + lip give
		public double deck = 0.0;        // table: lip -> knuckle; 0 = auto
		public double gap = 0.0;         // gap: lip -> landing knuckle; 0 = auto
		public double land_h = 0.0;
		public double fill = 0.0;
		public double land_deg = 0.0;    // 0 = auto
		public double land_g = 2.5;
		public double knuckle_r = 2.5;
		public double aim = 0.2;
		public double width = 3.0;
		// (not in DEFAULTS: the playground lane's designed() reads them when given; null = made from the design)
		public string id;
		public string name;

		public JumpParams Clone() => (JumpParams)MemberwiseClone();
	}

	/// What JumpDesign.build returns (GDScript: a Dictionary; same keys)
	public sealed class JumpDesignResult
	{
		public JumpParams p;
		public float[] h;          // PackedFloat32Array: float32 storage
		public float[] slope;
		public double length;
		public List<double[]> knots;   // [u, h, slope_in, slope_out]
		public double face_u, lip_u, lip_h, lip_deg, R, Ls, lip_gs, v_lip, deck, land0, land1, land_deg, land_h, rk, rb;
		public string kind;        // table | gap | kicker
		public JumpPrediction[] pred;  // at 0.85 / 1 / 1.15 x the design speed
	}

	/// JumpDesign.predict's result
	public sealed class JumpPrediction
	{
		public double v, u, dist, air, apex, efh, v_land;
		public string spot;
	}

	public static class JumpDesign
	{
		public const double G = 9.81;
		public const double DS = 0.05;
		public const double RUN_IN = 1.0;
		public const double LAND_MAX_DEG = 35.0;
		public const double LAND_SOFT = 3.0;
		public const double EFH_MAX = 1.5;
		public const double FACE_LOSS = 0.39;
		public const double TAKEOFF_EXTRA = 0.0;

		public static JumpParams @params(JumpParams p = null) => p == null ? new JumpParams() : p.Clone();

		static double _clo_rise(double th)
		{
			double s = 0.0;
			int n = 64;
			for (int i = 0; i < n; i++)
			{
				double u = (i + 0.5) / n;
				s += sin(th * u * u);
			}
			return s / n;
		}

		struct Landing { public V2 p; public double rk, rb, sx; }

		static Landing _landing(double hk, double phi, double rk, double rb, double aim)
		{
			double k = 1.0 - cos(phi);
			double dk = rk * k;
			double db = rb * k;
			if (dk + db > hk)
			{
				double sc = hk / maxf(1e-4, dk + db);
				rk *= sc; rb *= sc; dk *= sc; db *= sc;
			}
			double ds = maxf(0.0, hk - dk - db);
			double sx = ds / tan(phi);
			var p = new V2(rk * sin(phi) + aim * sx, hk - dk - aim * ds);
			if (sx < 0.3)
			{
				double tot = rk * sin(phi) + rb * sin(phi);
				p = new V2(aim * tot, hk * (1.0 - aim));
			}
			return new Landing { p = p, rk = rk, rb = rb, sx = sx };
		}

		public static JumpDesignResult build(JumpParams p_in = null)
		{
			JumpParams p = @params(p_in);
			double th = deg_to_rad(clampf(p.lip_deg, 5.0, 60.0));
			double v = maxf(2.0, p.v);
			double R = v * v / (maxf(0.3, p.lip_g) * G);
			double rise = _clo_rise(th);
			double H = 0.0;
			double Ls = 0.0;
			double vl = v;
			for (int it = 0; it < 3; it++)
			{
				Ls = maxf(0.0, p.lip_t) * vl;
				if (p.height > 0.0)
				{
					H = p.height;
					R = maxf(1.0, (H - Ls * sin(th)) / maxf(1e-4, 2.0 * th * rise));
					if (H - Ls * sin(th) < 0.05)
					{
						Ls = maxf(0.0, (H - 0.05) / sin(th)); R = maxf(1.0, 0.05 / (2.0 * th * rise));
					}
				}
				else
					H = 2.0 * th * R * rise + Ls * sin(th);
				vl = sqrt(maxf(1.0, v * v - 2.0 * G * H - FACE_LOSS * H * v));
			}
			bool gap_kind = p.kind == "gap";
			if (p.kind == "kicker") return _kicker(p, th, R, H, Ls, vl, v);
			double hk = !gap_kind || p.land_h <= 0.0 ? H : p.land_h;
			double rk = maxf(0.2, p.knuckle_r);
			double vb = sqrt(vl * vl + 2.0 * G * H);
			double rb = vb * vb / (maxf(0.5, p.land_g) * G);
			double aim = clampf(p.aim, 0.0, 1.0);
			double thf = th + deg_to_rad(TAKEOFF_EXTRA);
			double vx = vl * cos(thf);
			double vy = vl * sin(thf);
			double phi = p.land_deg > 0.0 ? deg_to_rad(p.land_deg) : th + deg_to_rad(6.0);
			double D = !gap_kind ? p.deck : p.gap;
			bool auto_d = D <= 0.0;
			bool auto_phi = p.land_deg <= 0.0;
			Landing lnd = default;
			int iters = auto_phi ? 6 : 1;
			for (int it = 0; it < iters; it++)
			{
				lnd = _landing(hk, phi, rk, rb, aim);
				V2 P = lnd.p;
				double dy = P.y - H;
				double a = G / (2.0 * vx * vx);
				double disc = tan(thf) * tan(thf) - 4.0 * a * dy;
				double xt = (tan(thf) + sqrt(maxf(0.0, disc))) / (2.0 * a);
				if (auto_d)
					D = xt - P.x - (!gap_kind ? 0.0 : 0.0);
				double x_hit = D + P.x;
				double slope_t = tan(thf) - 2.0 * a * x_hit;
				if (auto_phi)
					phi = clampf(-atan(slope_t) - deg_to_rad(LAND_SOFT), deg_to_rad(12.0), deg_to_rad(LAND_MAX_DEG));
			}
			D = maxf(0.6, D);
			lnd = _landing(hk, phi, rk, rb, aim);
			rk = lnd.rk; rb = lnd.rb;
			// ---- lay it out
			var t = new Turtle();
			t.flat(RUN_IN);
			double face_u = t.u();
			t.knot();
			t.clothoid(th, R);
			t.knot();
			t.straight_to(H);
			double lip_u = t.u();
			t.knot_kink(!gap_kind ? 0.0 : -deg_to_rad(50.0));
			double land0 = 0.0;
			if (!gap_kind)
				t.flat(D);
			else
			{
				double fl = clampf(p.fill, 0.0, minf(H, hk) - 0.1);
				double bk_a = deg_to_rad(50.0);
				double up = deg_to_rad(35.0);
				double need = (H - fl) / tan(bk_a) + (hk - fl) / tan(up) + 0.6;
				if (need > D)
				{
					bk_a = deg_to_rad(70.0); up = deg_to_rad(70.0);
				}
				t.a = -bk_a;
				t.knots[t.knots.Count - 1][3] = tan(t.a);
				t.straight_to(fl);
				t.knot_kink(0.0);
				double run = D - (t.u() - lip_u) - (hk - fl) / tan(up) - 0.6;
				t.flat(maxf(0.0, run));
				t.knot_kink(up);
				t.straight_to(hk);
				t.knot_kink(0.0);
				t.flat(0.6);
			}
			land0 = t.u();
			t.knot();
			t.arc(-phi, rk);
			t.knot();
			t.straight_to(rb * (1.0 - cos(phi)));
			t.knot();
			t.arc(0.0, rb);
			t.y = 0.0;
			double land1 = t.u();
			t.knot();
			t.flat(1.0);
			t.knot();
			var o = new JumpDesignResult
			{
				p = p, h = t.h.ToArray(), slope = t.s.ToArray(), length = t.u(), knots = t.knots,
				face_u = face_u, lip_u = lip_u, lip_h = H, lip_deg = rad_to_deg(th), R = R, Ls = Ls,
				lip_gs = v * v / R / G, v_lip = vl, deck = D, land0 = land0, land1 = land1, land_deg = rad_to_deg(phi),
				land_h = hk, rk = rk, rb = rb, kind = gap_kind ? "gap" : "table",
			};
			o.pred = new[] { predict(o, v * 0.85), predict(o, v), predict(o, v * 1.15) };
			return o;
		}

		static JumpDesignResult _kicker(JumpParams p, double th, double R, double H, double Ls, double vl, double v)
		{
			var t = new Turtle();
			t.flat(RUN_IN);
			double face_u = t.u();
			t.knot();
			t.clothoid(th, R);
			t.knot();
			t.straight_to(H);
			double lip_u = t.u();
			t.knot_kink(0.0);
			t.y = 0.0; t._push();
			t.knot_kink(0.0);
			t.flat(16.0);
			t.knot();
			var o = new JumpDesignResult
			{
				p = p, h = t.h.ToArray(), slope = t.s.ToArray(), length = t.u(), knots = t.knots,
				face_u = face_u, lip_u = lip_u, lip_h = H, lip_deg = rad_to_deg(th), R = R, Ls = Ls,
				lip_gs = v * v / R / G, v_lip = vl, deck = 0.0, land0 = lip_u, land1 = lip_u, land_deg = 0.0,
				land_h = 0.0, rk = 0.0, rb = 0.0, kind = "kicker",
			};
			o.pred = new[] { predict(o, v * 0.85), predict(o, v), predict(o, v * 1.15) };
			return o;
		}

		/// a rider at run-in speed vr (point mass) over the built shape: where he lands, how hard
		public static JumpPrediction predict(JumpDesignResult d, double vr)
		{
			double H = d.lip_h;
			double th = deg_to_rad(d.lip_deg + TAKEOFF_EXTRA);
			double vl = sqrt(maxf(0.1, vr * vr - 2.0 * G * H - FACE_LOSS * H * vr));
			double vx = vl * cos(th);
			double vy0 = vl * sin(th);
			float[] hs = d.h;
			double u0 = d.lip_u;
			double tt = 0.0;
			double dt = 0.004;
			double top = H;
			while (tt < 6.0)
			{
				tt += dt;
				double uu = u0 + vx * tt;
				double y = H + vy0 * tt - 0.5 * G * tt * tt;
				top = maxf(top, y);
				double g = sample(hs, uu);
				if (uu > u0 + 0.15 && y <= g)
				{
					double sl = (sample(hs, uu + 0.1) - sample(hs, uu - 0.1)) / 0.2;
					double vyl = vy0 - G * tt;
					V2 n = new V2(-sl, 1.0).normalized();
					double vn = -(vx * n.x + vyl * n.y);
					string spot = "flat";
					if (uu < d.land0 - 0.05) spot = d.kind == "table" ? "deck" : "gap";
					else if (uu < d.land0 + d.rk * sin(deg_to_rad(d.land_deg))) spot = "knuckle";
					else if (uu <= d.land1) spot = "landing";
					return new JumpPrediction { v = vr, u = uu, dist = uu - u0, air = tt, apex = top - H, efh = vn * vn / (2.0 * G),
						spot = spot, v_land = sqrt(vx * vx + vyl * vyl) };
				}
			}
			return new JumpPrediction { v = vr, u = INF, dist = INF, air = tt, apex = top - H, efh = INF, spot = "?", v_land = 0.0 };
		}

		public static double sample(float[] hs, double uu)
		{
			if (uu <= 0.0 || hs == null || hs.Length == 0) return 0.0;
			double f = uu / DS;
			int i = (int)f;
			if (i >= hs.Length - 1) return i == hs.Length - 1 ? hs[hs.Length - 1] : 0.0;
			return lerpf(hs[i], hs[i + 1], f - i);
		}

		/// one line for signs / the editor
		public static string describe(JumpDesignResult d)
		{
			if (d.kind == "kicker")
				return fmt("%.2f m kicker %.0f° · R %.1f m (%.1f g) · straight %.1f m · to flat", d.lip_h, d.lip_deg, d.R, d.lip_gs, d.Ls);
			return fmt("%.2f m lip %.0f° · R %.1f m (%.1f g) · straight %.1f m · %s %.1f m · landing %.0f°",
				d.lip_h, d.lip_deg, d.R, d.lip_gs, d.Ls, d.kind == "table" ? "deck" : "gap", d.deck, d.land_deg);
		}

		/// Hermite knots rounded to 0.1 mm
		public static List<double[]> knots(JumpDesignResult d)
		{
			var o = new List<double[]>();
			foreach (var k in d.knots)
				o.Add(new[] { snappedf(k[0], 0.0001), snappedf(k[1], 0.0001), snappedf(k[2], 0.0001), snappedf(k[3], 0.0001) });
			o[0] = new[] { 0.0, 0.0, 0.0, 0.0 };
			return o;
		}

		/// the AIR span for the ground shader (lip -> 2 m past where the design speed lands)
		public static double[] air_span(JumpDesignResult d)
		{
			JumpPrediction pr = d.pred[1];
			return new[] { snappedf(d.lip_u, 0.01), snappedf(minf(d.land1, pr.u + 2.0), 0.01) };
		}

		/// Godot's snappedf
		public static double snappedf(double v, double step) => step != 0.0 ? System.Math.Floor(v / step + 0.5) * step : v;

		/// the profile laid out at DS steps, with Hermite knots
		sealed class Turtle
		{
			const double KNOT_EVERY = 0.8;
			public readonly List<float> h = new List<float>();
			public readonly List<float> s = new List<float>();
			public List<double[]> knots = new List<double[]>();
			public double y = 0.0;
			public double a = 0.0;
			double _last_knot = -1.0;

			public double u() => h.Count * DS;

			public void _push() { h.Add((float)y); s.Add((float)tan(a)); }

			public void knot()
			{
				if (absf(u() - _last_knot) < 1e-6 && knots.Count > 0)
					knots[knots.Count - 1] = new[] { u(), y, knots[knots.Count - 1][2], tan(a) };
				else
					knots.Add(new[] { u(), y, tan(a), tan(a) });
				_last_knot = u();
			}

			public void knot_kink(double to)
			{
				double si = tan(a);
				a = to;
				if (absf(u() - _last_knot) < 1e-6 && knots.Count > 0)
					knots[knots.Count - 1][3] = tan(a);
				else
					knots.Add(new[] { u(), y, si, tan(a) });
				_last_knot = u();
			}

			void _curve_knot() { if (u() - _last_knot >= KNOT_EVERY) knot(); }

			public void flat(double L)
			{
				a = 0.0;
				int n = (int)round(L / DS);
				for (int i = 0; i < n; i++) _push();
			}

			public void straight_to(double yt)
			{
				double t = tan(a);
				if (absf(t) < 1e-6) return;
				int guard = 0;
				while (((t > 0.0 && y < yt) || (t < 0.0 && y > yt)) && guard < 100000)
				{
					y += t * DS;
					if ((t > 0.0 && y > yt) || (t < 0.0 && y < yt)) y = yt;
					_push(); guard += 1;
				}
			}

			public void arc(double to, double R)
			{
				int guard = 0;
				while (absf(a - to) > 1e-6 && guard < 100000)
				{
					double ds = DS / maxf(0.2, cos(a));
					a = move_toward(a, to, ds / maxf(0.05, R));
					y = maxf(0.0, y + tan(a) * DS); _push(); guard += 1;
					_curve_knot();
				}
			}

			public void clothoid(double to, double R)
			{
				double L = 2.0 * absf(to - a) * R;
				double s0 = 0.0;
				double a0 = a;
				int guard = 0;
				while (s0 < L && guard < 100000)
				{
					double ds = DS / maxf(0.2, cos(a));
					double sm = minf(L, s0 + ds * 0.5);
					s0 = minf(L, s0 + ds);
					a = a0 + signf(to - a0) * s0 * s0 / (2.0 * R * L);
					y += tan(a0 + signf(to - a0) * sm * sm / (2.0 * R * L)) * DS;
					_push(); guard += 1;
					_curve_knot();
				}
				a = to;
			}
		}
	}
}
