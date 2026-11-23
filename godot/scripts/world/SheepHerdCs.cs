using Godot;
using System;
using System.Collections.Generic;

/// Woolly sheep roaming in small flocks round the rider (replaces world/sheep_herd.gd). They graze and wander after
/// their flock; when the bike comes they lift their heads and watch it, and if it gets close they bolt out of its
/// path together as a flock (hopping, legs bounding), off the trail first if they're standing on it. Flocks left far
/// behind are placed again ahead, on green grass, off the line. Purely visual: no physics.
///
/// Light: every sheep of every flock is drawn by four MultiMeshes (wool body parts, wool puffs, face parts, legs),
/// four draw calls in all (the GDScript herd was ~32 MeshInstances a sheep); each frame the instance transforms go
/// in as one buffer per MultiMesh. The terrain is read from the C# field directly. Far, calm flocks are stepped every
/// FAR_EVERY frames. Env: BMX_NOSHEEP=1 off, BMX_SHEEP_NEAR=1 a flock right beside the start, BMX_SHEEP_PROBE=1 prints
/// SHEEP lines (state of each flock) twice a second.
public partial class SheepHerdCs : Node3D
{
	const int FLOCKS = 3, FLOCK_MIN = 2, FLOCK_MAX = 4, MAXL = FLOCKS * FLOCK_MAX;
	const double SPAWN_MIN = 70, SPAWN_MAX = 135, SIDE_MIN = 7, SIDE_MAX = 45, DESPAWN = 160;
	const double SCARE = 15, CALM = 32, ALERT = 2.2;   // alert (heads up, watching) out to ALERT x the scare distance
	const double WALK = 0.85, RUN = 7.6, WATER = -2.2, WATER_MARGIN = 0.5;
	const double SEP = 1.0;                             // sheep keep this far apart (m)
	const double FAR = 45; const int FAR_EVERY = 4;
	const string GRASS = "Green Hills";
	const int PUFFS = 18;

	class Lamb
	{
		public Vector2 p, off; public double theta, sp, phase, seed, y, bob, graze, spawnK, spread, turnDir = 1, pitch, roll, size = 1;
		public double look, lookT;          // head turned toward the bike (rad), how much it watches 0..1
		public Vector3 groundAt = new Vector3(float.PositiveInfinity, 0, 0), ground;
		public int wool, face;
		public Transform3D[] puffs = new Transform3D[PUFFS];
		public bool shown;
	}
	class Flock
	{
		public Vector2 c, tgt; public double t, alarm, acc, roadT, retry; public bool roadPref, onRoad;
		public List<Lamb> lambs = new List<Lamb>();
	}

	public bool enabled = true;
	Node _terrain;
	TerrainFieldCs _f;
	readonly RandomNumberGenerator _rng = new RandomNumberGenerator();
	readonly List<Flock> _flocks = new List<Flock>();
	readonly List<Lamb> _all = new List<Lamb>();
	double _time; bool _first = true; int _frame, _probeT;
	bool _near = OS.GetEnvironment("BMX_SHEEP_NEAR") != "", _probe = OS.GetEnvironment("BMX_SHEEP_PROBE") != "";

	// draw: four MultiMeshes, instance buffers (12 floats transform + 4 colour)
	MultiMesh _mmWool, _mmPuff, _mmFace, _mmLeg;
	float[] _bWool, _bPuff, _bFace, _bLeg;
	const int W_PER = 3, F_PER = 6, L_PER = 4;   // per sheep: body + fringe + tail; head, nose, 2 eyes, 2 ears; 4 legs
	static readonly Color[] WOOLS = { new Color(0.95f, 0.93f, 0.86f), new Color(0.90f, 0.89f, 0.86f), new Color(0.93f, 0.88f, 0.78f), new Color(0.97f, 0.96f, 0.93f) };
	static readonly Color[] FACES = { new Color(0.20f, 0.17f, 0.16f), new Color(0.33f, 0.26f, 0.21f), new Color(0.13f, 0.12f, 0.12f) };
	static readonly Color NOSE = new Color(0.55f, 0.38f, 0.38f), EYE = new Color(0.02f, 0.02f, 0.02f), HOOF = new Color(0.12f, 0.11f, 0.11f);

	public void setup(Node terrain)
	{
		_terrain = terrain;
		enabled = OS.GetEnvironment("BMX_NOSHEEP") == "";
		if (!enabled) return;
		_rng.Seed = 7741;
		var unit = new SphereMesh { Radius = 0.5f, Height = 1f, RadialSegments = 16, Rings = 8 };
		var puff = new SphereMesh { Radius = 0.5f, Height = 1f, RadialSegments = 9, Rings = 5 };
		var caps = new CapsuleMesh { Radius = 0.5f, Height = 2f, RadialSegments = 8, Rings = 3 };
		var noise = new NoiseTexture2D { Width = 128, Height = 128, Seamless = true,
			Noise = new FastNoiseLite { NoiseType = FastNoiseLite.NoiseTypeEnum.SimplexSmooth, FractalType = FastNoiseLite.FractalTypeEnum.Fbm, Frequency = 0.06f } };
		// fuzzy wool: clumpy colour + a fine bump, light bleeding through the edges and a faint fuzz rim; the
		// sheep's own wool colour comes in per instance
		var wool = new StandardMaterial3D {
			VertexColorUseAsAlbedo = true, AlbedoTexture = noise, Uv1Scale = new Vector3(3, 3, 3), Roughness = 1f,
			NormalEnabled = true, NormalTexture = noise, NormalScale = 0.6f,
			SubsurfScatterEnabled = true, SubsurfScatterStrength = 0.7f,
			BacklightEnabled = true, Backlight = new Color(0.55f, 0.4f, 0.28f),
			RimEnabled = true, Rim = 0.35f, RimTint = 0.6f };
		var plain = new StandardMaterial3D { VertexColorUseAsAlbedo = true, Roughness = 0.8f };
		_mmWool = Make(unit, wool, MAXL * W_PER, out _bWool);
		_mmPuff = Make(puff, wool, MAXL * PUFFS, out _bPuff);
		_mmFace = Make(unit, plain, MAXL * F_PER, out _bFace);
		_mmLeg = Make(caps, plain, MAXL * L_PER, out _bLeg);
		for (int i = 0; i < FLOCKS; i++)
		{
			var fl = new Flock { roadPref = i == 0 };
			int n = _rng.RandiRange(FLOCK_MIN, FLOCK_MAX);
			for (int k = 0; k < n; k++) { var l = MakeLamb(); fl.lambs.Add(l); _all.Add(l); }
			_flocks.Add(fl);
		}
		reset();
	}

	MultiMesh Make(Mesh mesh, Material mat, int count, out float[] buf)
	{
		var mm = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform3D, UseColors = true, Mesh = mesh, InstanceCount = count };
		var mi = new MultiMeshInstance3D { Multimesh = mm, MaterialOverride = mat };
		AddChild(mi);
		buf = new float[count * 16];   // all zero = every instance collapsed to a point (hidden)
		mm.Buffer = buf;
		return mm;
	}

	Lamb MakeLamb()
	{
		var l = new Lamb { seed = _rng.Randf() * 10.0, size = _rng.RandfRange(0.88f, 1.12f),
			wool = (int)(_rng.Randi() % (uint)WOOLS.Length), face = (int)(_rng.Randi() % (uint)FACES.Length) };
		// ~18 small low-poly puffs scattered over the top and sides of the body
		for (int k = 0; k < PUFFS; k++)
		{
			var d = new Vector3(_rng.RandfRange(-1, 1), _rng.RandfRange(-0.25f, 1f), _rng.RandfRange(-1, 1)).Normalized();
			var pp = new Vector3(0, 0.62f, 0) + d * new Vector3(0.36f, 0.36f, 0.5f);
			float sz = _rng.RandfRange(0.26f, 0.36f);
			l.puffs[k] = new Transform3D(Basis.FromScale(new Vector3(sz, sz * 0.92f, sz)), pp);
		}
		return l;
	}

	/// restart: every flock gets a new spot (new world / respawn); the terrain's C# field is fetched again (a new
	/// world makes a new one)
	public void reset()
	{
		_f = null;
		if (!enabled) return;
		_first = true;
		foreach (var f in _flocks)
		{
			foreach (var l in f.lambs) l.shown = false;
			f.alarm = 0; f.retry = 0; f.c = new Vector2(1e9f, 1e9f);
		}
	}

	TerrainFieldCs Field()
	{
		if (_f == null && _terrain != null && IsInstanceValid(_terrain))
			_f = _terrain.Get("fcs").As<GodotObject>() as TerrainFieldCs;
		return _f;
	}

	double H(double x, double z) => _f.height(x, z);
	bool Grass(double x, double z) => _f.biome_name(x, z) == GRASS;

	bool GroundOk(double x, double z)
	{
		double h = H(x, z);
		if (h < WATER + WATER_MARGIN + 0.6 || !Grass(x, z)) return false;
		double dh = Math.Abs(H(x + 4, z) - h) + Math.Abs(H(x, z + 4) - h);   // not too steep to graze
		return dh < 2.6;
	}

	void Place(Flock f, Vector2 rider, Vector2 fwd, bool near)
	{
		var side = new Vector2(-fwd.Y, fwd.X);
		Vector2 spot = Vector2.Zero; bool ok = false;
		for (int a = 0; a < 24 && !ok; a++)
		{
			double r = _rng.RandfRange((float)SPAWN_MIN, (float)SPAWN_MAX);
			double s = _rng.RandfRange((float)SIDE_MIN, (float)SIDE_MAX) * (_rng.Randf() < 0.5f ? 1 : -1);
			if (f.roadPref) s = _rng.RandfRange(0f, 4f) * (_rng.Randf() < 0.5f ? 1 : -1);
			if (near) { r = 24 + _rng.Randf() * 10; s = (9 + _rng.Randf() * 8) * (_rng.Randf() < 0.5f ? 1 : -1); }
			spot = rider + fwd * (float)r + side * (float)s;
			ok = GroundOk(spot.X, spot.Y);
		}
		if (!ok)
		{
			f.c = new Vector2(1e9f, 1e9f);   // no good ground right now (no green grass ahead): try again in a moment
			f.retry = 0.5;
			foreach (var l in f.lambs) l.shown = false;
			return;
		}
		f.c = spot; f.tgt = spot; f.alarm = 0; f.acc = 0; f.t = _rng.RandfRange(2f, 8f);
		foreach (var l in f.lambs)
		{
			float a = _rng.Randf() * Mathf.Tau, rr = _rng.RandfRange(1f, 5f);
			l.off = new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * rr;
			l.p = spot + l.off;
			l.theta = _rng.Randf() * Mathf.Tau; l.sp = 0;
			l.y = H(l.p.X, l.p.Y);
			l.spawnK = 0; l.spread = _rng.RandfRange(-0.6f, 0.6f); l.turnDir = _rng.Randf() < 0.5f ? 1 : -1;
			l.graze = 1; l.look = 0; l.lookT = 0;
			l.groundAt = new Vector3(float.PositiveInfinity, 0, 0);
			l.shown = true;
		}
	}

	/// per frame, from Game: the drawn bike position, its speed (m/s) and heading
	public void follow(double dt, Vector3 riderPos, double riderV, Vector3 fwd3)
	{
		if (!enabled || dt <= 0) return;
		if (Field() == null) return;
		dt = Math.Min(dt, 0.05);
		_time += dt;
		_frame++;
		var rider = new Vector2(riderPos.X, riderPos.Z);
		var fwd = new Vector2(fwd3.X, fwd3.Z);
		fwd = fwd.Length() < 0.01f ? new Vector2(1, 0) : fwd.Normalized();
		var vel = fwd * (float)riderV;
		double vabs = Math.Abs(riderV);
		double scare = SCARE + Math.Min(vabs * 0.7, 10.0);
		int placed = 0;
		bool firstNear = _first && _near;
		for (int fi = 0; fi < _flocks.Count; fi++)
		{
			var f = _flocks[fi];
			double nearest = 1e9;
			foreach (var l in f.lambs) nearest = Math.Min(nearest, l.p.DistanceTo(rider));
			if (f.c.X > 1e8f || nearest > DESPAWN)
			{
				f.retry -= dt;
				if (placed < 2 && f.retry <= 0) { Place(f, rider, fwd, firstNear && placed == 0); placed++; }
				if (f.c.X > 1e8f) continue;
			}
			f.acc += dt;
			if (nearest > FAR && f.alarm <= 0 && (_frame + fi) % FAR_EVERY != 0) continue;
			StepFlock(f, Math.Min(f.acc, 0.1), rider, vel, vabs, scare);
			f.acc = 0;
		}
		_first = false;
		_hideAt = riderPos;
		Draw();
		if (_probe && (int)(_time * 2) != _probeT)
		{
			_probeT = (int)(_time * 2);
			for (int fi = 0; fi < _flocks.Count; fi++)
			{
				var f = _flocks[fi];
				if (f.c.X > 1e8f) { GD.Print($"SHEEP f={fi} unplaced"); continue; }
				double d = 1e9, sp = 0, look = 0;
				foreach (var l in f.lambs) { d = Math.Min(d, l.p.DistanceTo(rider)); sp = Math.Max(sp, l.sp); look = Math.Max(look, l.lookT); }
				var l0 = f.lambs[0];
				GD.Print(FormattableString.Invariant($"SHEEP f={fi} n={f.lambs.Count} dist={d:F1} alarm={f.alarm:F1} road={f.onRoad} run={sp:F2} watch={look:F2} at={l0.p.X:F1},{l0.y:F1},{l0.p.Y:F1}"));
			}
		}
	}

	void StepFlock(Flock f, double dt, Vector2 rider, Vector2 vel, double vabs, double scare)
	{
		double closest = 1e9; var mean = Vector2.Zero;
		foreach (var l in f.lambs) { closest = Math.Min(closest, l.p.DistanceTo(rider)); mean += l.p; }
		mean /= f.lambs.Count;
		// on the trail? read 4x a second
		f.roadT -= dt;
		if (f.roadT <= 0)
		{
			f.roadT = 0.25; f.onRoad = false;
			foreach (var l in f.lambs) if (_f.trail(l.p.X, l.p.Y) > 0.05) { f.onRoad = true; break; }
		}
		if (f.onRoad) scare = Math.Max(scare, 38 + vabs * 1.3);   // sheep on the road clear off well before you arrive
		// the bike coming at them counts as nearer than one going away
		var toFlock = mean - rider;
		double coming = toFlock.Length() > 0.5f ? Math.Clamp(vel.Dot(toFlock.Normalized()) / 8.0, 0, 1) : 0;
		double eff = closest - coming * 4.0;
		if (eff < scare) f.alarm = 3.5;
		else if (closest > CALM) f.alarm = Math.Max(0, f.alarm - dt);
		else f.alarm = Math.Max(0, f.alarm - dt * 0.4);
		bool fleeing = f.alarm > 0;
		bool alert = !fleeing && closest < scare * ALERT;
		if (fleeing) { f.c = mean; f.tgt = mean; }   // after the scare they settle where they ended up
		else
		{
			// the anchor wanders: pick a spot nearby now and then, drift toward it
			f.t -= dt;
			if (f.t <= 0)
			{
				f.t = _rng.RandfRange(8f, 20f);
				float a = _rng.Randf() * Mathf.Tau;
				f.tgt = f.c + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * _rng.RandfRange(4f, 14f);
			}
			var to = f.tgt - f.c;
			if (to.Length() > 0.3f && !alert)
			{
				var nc = f.c + to.Normalized() * (float)(0.4 * dt);
				if (GroundOk(nc.X, nc.Y)) f.c = nc; else f.tgt = f.c;
			}
		}
		foreach (var l in f.lambs) StepLamb(l, f, dt, rider, vel, mean, fleeing, alert);
	}

	void StepLamb(Lamb l, Flock f, double dt, Vector2 rider, Vector2 vel, Vector2 mean, bool fleeing, bool alert)
	{
		l.spawnK = Math.Min(1, l.spawnK + dt * 0.8);
		double wantTheta = l.theta, wantSp = 0, turnRate = 2.4;
		if (fleeing)
		{
			var away = l.p - rider;
			if (away.Length() < 0.5f) away = new Vector2(Mathf.Sin((float)l.theta), Mathf.Cos((float)l.theta));
			away = away.Normalized();
			// out of the bike's path: the side of its line the sheep is on, more so the faster it comes
			if (vel.Length() > 1f)
			{
				var vd = vel.Normalized();
				var side = new Vector2(-vd.Y, vd.X);
				float s = (l.p - rider).Dot(side) >= 0 ? 1 : -1;
				float k = Mathf.Clamp(vel.Length() / 10f, 0f, 0.7f);
				away = (away * (1 - k) + side * s * k).Normalized();
			}
			if (_f.trail(l.p.X, l.p.Y) > 0.02)
			{
				// on the road: dash sideways off it (down the trail gradient), a little away from the bike
				double tx = _f.trail(l.p.X + 1.5, l.p.Y) - _f.trail(l.p.X - 1.5, l.p.Y);
				double tz = _f.trail(l.p.X, l.p.Y + 1.5) - _f.trail(l.p.X, l.p.Y - 1.5);
				var g = new Vector2((float)-tx, (float)-tz);
				if (g.Length() < 0.01f) g = away.Rotated(Mathf.Pi * 0.5f * (float)l.turnDir);
				away = (g.Normalized() + away * 0.35f).Normalized();
			}
			// run as a flock: a pull toward the others
			var tm = mean - l.p;
			if (tm.Length() > 2.5f) away = (away + tm.Normalized() * 0.3f).Normalized();
			away = away.Rotated((float)(l.spread * 0.5));
			wantTheta = Math.Atan2(away.X, away.Y);
			wantSp = RUN * (0.9 + 0.2 * Mathf.PosMod((float)l.seed, 1f));
			turnRate = 9.0;
		}
		else if (!alert)
		{
			var dd = f.c + l.off - l.p;
			if (dd.Length() > 2.2f)
			{
				wantTheta = Math.Atan2(dd.X, dd.Y);
				wantSp = WALK * (0.75 + 0.5 * Mathf.PosMod((float)(l.seed * 3.1), 1f));
			}
		}
		// keep apart: a push from any flock mate closer than SEP
		var push = Vector2.Zero;
		foreach (var o in f.lambs)
		{
			if (o == l) continue;
			var d = l.p - o.p; float dl = d.Length();
			if (dl < SEP && dl > 1e-3f) push += d / dl * (float)(SEP - dl);
		}
		l.sp += (wantSp - l.sp) * Math.Min(1, dt * (fleeing ? 7.0 : 2.0));
		if (l.sp > 0.05 || fleeing) l.theta = Mathf.LerpAngle((float)l.theta, (float)wantTheta, (float)Math.Min(1, dt * turnRate));
		// move: stop for water / steep ground / the edge of the grass, turning away while it lasts
		var step = new Vector2(Mathf.Sin((float)l.theta), Mathf.Cos((float)l.theta)) * (float)(l.sp * dt) + push * (float)Math.Min(1, dt * 4);
		if (step.LengthSquared() > 1e-8f)
		{
			var np = l.p + step;
			double nh = H(np.X, np.Y);
			bool blocked = nh < WATER + WATER_MARGIN || Math.Abs(nh - l.y) > Math.Max(0.06, step.Length() * 1.4);
			if (!blocked && !Grass(np.X, np.Y) && Grass(l.p.X, l.p.Y)) blocked = true;
			if (blocked) { l.theta += l.turnDir * dt * 4.0; l.sp *= 0.85; }
			else l.p = np;
		}
		// the ground under it + slope pose: read again only when it moved or turned
		var at = new Vector3(l.p.X, l.p.Y, (float)l.theta);
		if (at != l.groundAt)
		{
			l.groundAt = at;
			float sn = Mathf.Sin((float)l.theta), cs = Mathf.Cos((float)l.theta);
			double hf = H(l.p.X + sn * 0.45, l.p.Y + cs * 0.45), hb = H(l.p.X - sn * 0.45, l.p.Y - cs * 0.45);
			double hl = H(l.p.X + cs * 0.3, l.p.Y - sn * 0.3), hr = H(l.p.X - cs * 0.3, l.p.Y + sn * 0.3);
			l.ground = new Vector3((float)H(l.p.X, l.p.Y), (float)-Math.Atan2(hf - hb, 0.9), (float)Math.Atan2(hl - hr, 0.6));
		}
		l.y += (l.ground.X - l.y) * Math.Min(1, dt * 14);
		l.pitch += (l.ground.Y - l.pitch) * Math.Min(1, dt * 8);
		l.roll += (l.ground.Z - l.roll) * Math.Min(1, dt * 8);
		// gait
		double runK = Math.Clamp((l.sp - 2) / 4, 0, 1);
		l.phase += l.sp * dt * Mathf.Lerp(3.2, 2.1, runK);
		double hop = l.sp > 0.1 ? Math.Abs(Math.Sin(l.phase * Mathf.Lerp(1.0, 0.5, runK) * 2)) * Mathf.Lerp(0.02, 0.2, runK) : 0;
		l.bob += (hop - l.bob) * Math.Min(1, dt * 20);
		// head: grazes when standing, now and then looks up; alert = up, turned to watch the bike; running = up
		bool lookUp = Math.Sin(_time * 0.35 + l.seed * 7) > 0.78;
		double gt = (l.sp < 0.3 && !lookUp && !fleeing && !alert) ? 1 : 0;
		l.graze += (gt - l.graze) * Math.Min(1, dt * 3);
		l.lookT += ((alert ? 1 : 0) - l.lookT) * Math.Min(1, dt * 4);
		var tr = rider - l.p;
		double rel = Mathf.Wrap((float)(Math.Atan2(tr.X, tr.Y) - l.theta), -Mathf.Pi, Mathf.Pi);
		l.look += (Math.Clamp(rel, -1.2, 1.2) * l.lookT - l.look) * Math.Min(1, dt * 5);
	}

	// ---------------- drawing: every part of every sheep into four instance buffers ----------------

	static void Put(float[] b, int i, Transform3D t, Color c)
	{
		int o = i * 16;
		var x = t.Basis;
		b[o] = x.X.X; b[o + 1] = x.Y.X; b[o + 2] = x.Z.X; b[o + 3] = t.Origin.X;
		b[o + 4] = x.X.Y; b[o + 5] = x.Y.Y; b[o + 6] = x.Z.Y; b[o + 7] = t.Origin.Y;
		b[o + 8] = x.X.Z; b[o + 9] = x.Y.Z; b[o + 10] = x.Z.Z; b[o + 11] = t.Origin.Z;
		b[o + 12] = c.R; b[o + 13] = c.G; b[o + 14] = c.B; b[o + 15] = c.A;
	}
	// a hidden part: collapsed to a point at the rider (a point at the world origin would stretch the MultiMeshes'
	// bounds, and so their culling, across the whole world)
	Vector3 _hideAt;
	void Hide(float[] b, int i, int n)
	{
		Array.Clear(b, i * 16, n * 16);
		for (int k = i; k < i + n; k++) { b[k * 16 + 3] = _hideAt.X; b[k * 16 + 7] = _hideAt.Y; b[k * 16 + 11] = _hideAt.Z; }
	}
	static Transform3D S(Vector3 pos, Vector3 size) => new Transform3D(Basis.FromScale(size), pos);
	static readonly Vector3[] LEG_AT = { new Vector3(0.2f, 0.4f, 0.28f), new Vector3(-0.2f, 0.4f, 0.28f), new Vector3(0.2f, 0.4f, -0.3f), new Vector3(-0.2f, 0.4f, -0.3f) };
	static readonly double[] OFF_WALK = { 0, Math.PI, Math.PI, 0 }, OFF_RUN = { 0, 0.25, Math.PI * 0.85, Math.PI * 0.95 };

	void Draw()
	{
		for (int i = 0; i < _all.Count; i++)
		{
			var l = _all[i];
			if (!l.shown)
			{
				Hide(_bWool, i * W_PER, W_PER); Hide(_bPuff, i * PUFFS, PUFFS); Hide(_bFace, i * F_PER, F_PER); Hide(_bLeg, i * L_PER, L_PER);
				continue;
			}
			double runK = Math.Clamp((l.sp - 2) / 4, 0, 1);
			var basis = new Basis(Vector3.Up, (float)l.theta) * new Basis(Vector3.Right, (float)l.pitch) * new Basis(Vector3.Back, (float)l.roll);
			var root = new Transform3D(basis.Scaled(Vector3.One * (float)(l.size * l.spawnK)), new Vector3(l.p.X, (float)(l.y + l.bob), l.p.Y));
			Color wool = WOOLS[l.wool], face = FACES[l.face];
			// wool: body, tail (wagging), fringe on the head below
			Put(_bWool, i * W_PER, root * S(new Vector3(0, 0.62f, 0), new Vector3(0.82f, 0.78f, 1.08f)), wool);
			var tail = root * new Transform3D(new Basis(Vector3.Back, (float)(Math.Sin(_time * (3 + l.sp * 2) + l.seed) * (0.12 + 0.25 * runK))), new Vector3(0, 0.7f, -0.52f));
			Put(_bWool, i * W_PER + 2, tail * S(new Vector3(0, -0.04f, -0.05f), new Vector3(0.2f, 0.2f, 0.2f)), wool);
			for (int k = 0; k < PUFFS; k++) Put(_bPuff, i * PUFFS + k, root * l.puffs[k], wool);
			// head on its neck pivot: lowered to graze (with a nod), turned to watch the bike, up and back when running
			double nod = Math.Sin(_time * 5 + l.seed) * 0.05 * l.graze;
			var hb = new Basis(Vector3.Up, (float)l.look) * new Basis(Vector3.Right, (float)(l.graze * 0.95 + nod - runK * 0.25));
			var head = root * new Transform3D(hb, new Vector3(0, (float)(0.82 - l.graze * 0.12), 0.5f));
			Put(_bWool, i * W_PER + 1, head * S(new Vector3(0, 0.13f, 0.08f), new Vector3(0.24f, 0.17f, 0.26f)), wool);
			int fo = i * F_PER;
			Put(_bFace, fo, head * S(new Vector3(0, -0.02f, 0.17f), new Vector3(0.3f, 0.32f, 0.4f)), face);
			Put(_bFace, fo + 1, head * S(new Vector3(0, -0.05f, 0.36f), new Vector3(0.1f, 0.08f, 0.09f)), NOSE);
			for (int s = 0; s < 2; s++)
			{
				float sx = s == 0 ? -1 : 1;
				Put(_bFace, fo + 2 + s, head * S(new Vector3(0.095f * sx, 0.03f, 0.27f), new Vector3(0.05f, 0.06f, 0.05f)), EYE);
				double ear = 0.5 * sx * (1 - 0.7 * runK) * (1 - 0.6 * l.lookT) + Math.Sin(_time * 1.3 + l.seed + s) * 0.04;   // ears prick up watching
				var et = new Transform3D(new Basis(Vector3.Back, (float)ear) * Basis.FromScale(new Vector3(0.19f, 0.06f, 0.1f)), new Vector3(0.17f * sx, 0.06f, 0.04f));
				Put(_bFace, fo + 4 + s, head * et, face);
			}
			// legs swing at the hips (walk: diagonal pairs, run: a bound)
			double amp = Math.Clamp(l.sp / 2.5, 0, 1) * Mathf.Lerp(0.5, 0.95, runK);
			for (int k = 0; k < 4; k++)
			{
				double o = Mathf.Lerp(OFF_WALK[k], OFF_RUN[k], runK);
				var hip = root * new Transform3D(new Basis(Vector3.Right, (float)(Math.Sin(l.phase + o) * amp)), LEG_AT[k]);
				Put(_bLeg, i * L_PER + k, hip * S(new Vector3(0, -0.19f, 0), new Vector3(0.085f, 0.2f, 0.085f)), HOOF);
			}
		}
		_mmWool.Buffer = _bWool; _mmPuff.Buffer = _bPuff; _mmFace.Buffer = _bFace; _mmLeg.Buffer = _bLeg;
	}
}
