// Engine-free: nothing in godot/sim/ may reference the engine (checked by tools/sim_purity.ps1).
// The parts of bike_physics.gd the translator leaves out (dev/port/gen.sh MANUAL): engine glue, lambdas, reflection.
// Keep each in step with its GDScript function by hand.
using System;
using System.Collections.Generic;
using System.Linq;
using static Runout.Sim.Gd;

namespace Runout.Sim
{
	public partial class BikeSim
	{
		public BikeSim(IRideHost h)
		{
			host = h;
		}

		/// setup(extras, bike_cfg): the drawn bike's geometry (glb extras) and the ride config (GameState.bike_config_for).
		/// bike_cfg.mods holds "cogs" (List<double>), "ring_k", "land" and "susp" (SusSetup) when the bike has a build
		public void setup(GdDict extras, GdDict bike_cfg)
		{
			L = extras.get_f("wheelbase", 0.8985);
			RWF = extras.get_f("wheelRadius", 0.261);
			RWR = extras.get_f("wheelRadiusRear", RWF);
			BB_REAR = extras.get_f("bbToRearAxle", 0.3331);
			SH_R = (L - BB_REAR) / L;
			LAND = bike_cfg.get_f("land", 1.0);
			geared = bike_cfg.get_b("geared", false);
			var mods = bike_cfg.get_o("mods", null) as GdDict ?? new GdDict();
			var su = mods.get_o("susp", null) as SusSetup;
			sus = Env.s("BMX_NO_SUS") != "" || su == null ? new SusSetup() : su;   // (BMX_NO_SUS: tests, the old single spring)
			_sus_synced = false;
			_su = new double[0];
			if (mods.has("cogs"))
			{
				cogs = mods.get_o("cogs", null) as List<double> ?? new List<double> { 16 };
				ring_k = mods.get_f("ring_k", 1.0);
				LAND *= mods.get_f("land", 1.0);
			}
			else
			{
				// no garage build (the BMX): one neutral 16T cog, ratio 1 like the web version -- not the DH cassette
				cogs = new List<double> { 16 };
				ring_k = 1.0;
			}
			if (cogs.Count <= 1)
				geared = false;
			gear = geared ? start_gear(cogs, ring_k) : -1;
		}

		/// the suspension setup's numbers once (the vertical step reads them 120 times a second)
		private void _sus_cache()
		{
			_su = new double[18];
			Array.Copy(sus.u, _su, 16);
			_su[16] = clampf(sus.u[16], 5.0, 80.0);
			_su[17] = clampf(sus.u[17], 5.0, 80.0);
		}

		private long _prof(string stage, long t0)
		{
			long now = host.get_ticks_usec();
			string k = "p_step." + stage;
			prof[k] = (prof.TryGetValue(k, out long was) ? was : 0) + (now - t0);
			return now;
		}

		/// the crashed ride: the bike slows and slides, the crashed-bike body and the ragdoll step (host: they are engine
		/// objects), then hold hop to get up
		private void _crash_step(double dt, RideInput inp)
		{
			crash_t += dt;
			V3 f = fwd();
			v *= exp(-dt * 2.2);
			if (absf(v) < 0.05)
				v = 0.0;
			yaw_rate *= exp(-dt * 3);
			heading += yaw_rate * dt;
			if (crash_sim == null)
				_crash_old_step(dt, f);
			host.crash_body_step(this, dt, inp);   // (CrashBikeCs step when crash_sim is set, then the ragdoll's)
			if (host.getup_anim != null)
				return;   // already getting up
			bool holding = crash_armed && inp.b("hop");
			if (holding)
				crash_hold += dt;
			else
			{
				crash_armed = false;
				crash_hold = maxf(0.0, crash_hold - dt * 3);
			}
			if (crash_hold >= getup_need)
				host.begin_getup();
		}

		private static readonly string[] SANE_KEYS =
		{
			"x", "z", "y", "vy", "v", "heading", "pitch", "pitch_v", "lean", "lean_v", "steer", "steer_in", "steer_in_v", "slip",
			"slip_w", "course", "compress", "compress_v", "body_x", "body_xv", "hip_shift", "hip_v", "air_lean", "air_pull",
			"a_drive", "body_y", "body_v", "air_w", "air_tilt", "air_tilt_v", "bike_lean", "counter", "flick", "flick_v",
			"man_a", "man_w", "bank", "corner_g",
		};

		public bool is_sane()
		{
			double[] vals =
			{
				x, z, y, vy, v, heading, pitch, pitch_v, lean, lean_v, steer, steer_in, steer_in_v, slip, slip_w, course, compress,
				compress_v, body_x, body_xv, hip_shift, hip_v, air_lean, air_pull, a_drive, body_y, body_v, air_w, air_tilt, air_tilt_v,
				bike_lean, counter, flick, flick_v, man_a, man_w, bank, corner_g,
			};
			foreach (double d in vals)
				if (!is_finite(d))
					return false;
			return true;
		}

		// ---- tests (BMX_ENERGY_PROBE / BMX_JOLT_PROBE): printed lines only, nothing the ride reads
		private void _e_tick(double dt, bool brake)
		{
			_eb_n.set("t", _eb_n.f("t") + dt);
			_eb_n.set("dist", _eb_n.f("dist") + absf(v) * dt);
			_eb_n.set("vmax", maxf(_eb_n.f("vmax"), absf(v)));
			if (brake && !air && v > 0.5) _eb_n.set("brake", _eb_n.f("brake") + dt);
			if (air) _eb_n.set("air", _eb_n.f("air") + dt);
			if (!air && absf(lat_a) > 3.0 && !is_nan(bank))
			{
				_eb_n.set("turn_t", _eb_n.f("turn_t") + dt);
				_eb_n.set("turn_bank", _eb_n.f("turn_bank") + absf(bank) * dt);
			}
			_eb_t += dt;
			if (_eb_t < 5.0)
				return;
			_eb_t = 0.0;
			var ks = _eb.Keys.Where(k => !k.StartsWith("~")).OrderBy(k => _eb.f(k)).ToList();
			double t = _eb_n.f("t");
			string line = fmt("ENERGY t=%.0fs dist=%.0fm avg=%.1fkmh max=%.1fkmh braking=%.0f%% air=%.0f%% turning: bank=%.1fdeg |",
				t, _eb_n.f("dist"), _eb_n.f("dist") / maxf(t, 0.01) * 3.6, _eb_n.f("vmax") * 3.6, 100.0 * _eb_n.f("brake") / t,
				100.0 * _eb_n.f("air") / t, rad_to_deg(_eb_n.f("turn_bank") / maxf(_eb_n.f("turn_t"), 1e-3)));
			foreach (var k in ks)
				line += fmt(" %s=%.0f", k, _eb.f(k));
			host.log(line);
		}

		private void _jolt_probe(double dt, double brake_k)
		{
			_jp_t += dt;
			if (_jp_prev.Count == 4 && !crash_on && absf(v) > 1.0)
			{
				double vy0 = to_f(_jp_prev[0]), pw0 = to_f(_jp_prev[1]);
				bool air0 = to_b(_jp_prev[2]);
				double dvy = vy - vy0, dpw = pitch_v - pw0;
				if (absf(dvy) > 2.5 || absf(dpw) > 3.0)
				{
					string kind = (air0 && !air) ? "land" : ((!air0 && air) ? "takeoff" : (_jp_rim > 0 ? "rim" : (air ? "air" : "ground")));
					_jp_n.set(kind, _jp_n.f(kind) + 1);
					host.log(fmt("JOLT %s t=%.2f at=%.1f,%.1f v=%.1f vy %.2f->%.2f pw %.2f->%.2f pitch=%.2f gp=%.2f fa=%s ra=%s brake=%.2f lean=%.2f",
						kind, _jp_t, x, z, v, vy0, vy, pw0, pitch_v, pitch, _g_pitch, front_air, rear_air, brake_k, bike_lean));
				}
			}
			_jp_prev = new List<object> { vy, pitch_v, air, 0 };
			_jp_rim = 0;
			if ((long)(_jp_t / 10.0) != (long)((_jp_t - dt) / 10.0))
				host.log(fmt("JOLTSUM t=%.0f %s", _jp_t, string.Join(", ", _jp_n.Select(kv => kv.Key + ": " + str(kv.Value)))));
		}
	}
}
