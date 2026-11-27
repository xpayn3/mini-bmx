using System;
using System.Collections.Generic;
using Godot;

/// The crash ragdoll as RIGID BODIES with real joints (2026-11-27, user: "make the ragdoll like GTA", "we have joint
/// sockets that limit this"). The old ragdoll (ragdoll.gd) was 15 points held by distance rods with rules bolted on; a
/// point has no twist, and every limit had to be faked. Here every body part is a solid with a mass and an inertia, and
/// every joint limits each axis like the real one, the way articulated ragdolls in games are built (GTA's Euphoria,
/// Unreal / Unity ragdolls):
///   - 11 bodies: pelvis, chest, head, upper arms, forearms (+ hand), thighs, shins (+ foot); capsules.
///   - 10 joints: spine (pelvis-chest) and neck: limited ball (swing cone + twist); shoulders, hips: ball sockets with a
///     swing cone round their natural direction + a twist limit; elbows, knees: hinges, 0 (straight) .. ~150 deg, never
///     backwards or sideways.
///   - Muscles = soft joint motors (XPBD compliance: a spring of a chosen frequency per joint) toward target limb
///     directions the behaviour layer (ragdoll.gd: tone, tuck, brace, windmill, pain, spread) sets each step; joint
///     damping. Motors act equal and opposite on the two bodies: they bend the body, they can't push or spin it.
///   - Contacts: three spheres per capsule against the drawn ground (TerrainFieldCs.top_height, or a callable), trunks
///     (vertical cylinders), and limbs against the trunk / each other; Coulomb friction, a little bounce.
/// Solver: XPBD for rigid bodies (Mueller, Macklin, Chentanez, Jeschke, Kim 2020, "Detailed Rigid Body Simulation with
/// Extended Position Based Dynamics"): many substeps, one pass each, velocities from positions.
/// ragdoll.gd reads the 15 joint points (Ragdoll order) and their velocities back, so blood, get-up, camera and the
/// drawing are unchanged.
public partial class RagdollRbCs : RefCounted
{
	// ---- points (Ragdoll order) ----
	private const int HEAD = 0, CHEST = 1, PELVIS = 2, SH_L = 3, EL_L = 4, HA_L = 5, SH_R = 6, EL_R = 7, HA_R = 8,
		HIP_L = 9, KN_L = 10, FT_L = 11, HIP_R = 12, KN_R = 13, FT_R = 14;
	// ---- bodies ----
	public const int B_PELVIS = 0, B_CHEST = 1, B_HEAD = 2, B_UARM_L = 3, B_FARM_L = 4, B_UARM_R = 5, B_FARM_R = 6,
		B_THIGH_L = 7, B_SHIN_L = 8, B_THIGH_R = 9, B_SHIN_R = 10, B_FOOT_L = 11, B_FOOT_R = 12, NB = 13;
	// (feet, 2026-11-27, user: "we don't have feet?!": a foot is its own body on an ankle joint, the shoe drawn from it)
	private static readonly double[] MASS = { 12, 26, 5.5, 2.2, 1.8, 2.2, 1.8, 8.5, 3.4, 8.5, 3.4, 1.1, 1.1 };

	private class Body
	{
		public DV X, XP, V, W;            // position (centre of mass), last substep's, velocity, angular velocity (world)
		public DQ Q = DQ.Identity, QP = DQ.Identity;
		public double InvM;
		public DV InvI;                    // diagonal, body space
		public DV A0, A1; public double R; // capsule ends (body space), radius
		public DV B0, B1; public double RB; // a second capsule (chest: across the shoulders), RB = 0: none
		public double Iscalar;             // for joint damping
		public bool Free;                  // torn off its parent (its own body now)
		// helpers
		public DV ToWorld(DV l) => X + Q.Rot(l);
		public DV ToLocal(DV w) => Q.Conj().Rot(w - X);
		public DV Dir(DV l) => Q.Rot(l);
		public DV InvIW(DV a) { DV l = Q.Conj().Rot(a); return Q.Rot(new DV(l.X * InvI.X, l.Y * InvI.Y, l.Z * InvI.Z)); }
	}
	private readonly Body[] _b = new Body[NB];

	// a joint: parent p, child c, anchors in each body's space, its kind and limits
	private class Joint
	{
		public int P, C;
		public DV AP, AC;                 // anchor (body spaces)
		public int Kind;                  // 0 ball (swing + twist), 1 hinge
		public DV SwingP;                 // ball: the cone's axis (parent space); hinge: the hinge axis (parent space)
		public DV AxisC;                  // ball: the child's long axis (child space); hinge: the hinge axis (child space)
		public DV RefP, RefC;             // twist / hinge angle references (perpendicular to the axes)
		public double Swing, TwistLo, TwistHi;   // ball: cone half angle, twist range; hinge: angle range (TwistLo..Hi)
		public bool Limits = true, On = true;
		public double Damp = 8.0;         // 1/s on the relative spin
	}
	private readonly List<Joint> _j = new();

	// contact spheres: body, centre (body space), radius, the point it stands for
	private readonly List<(int b, DV c, double r, int pt)> _sph = new();
	// output points: body + offset (body space)
	private readonly List<(int b, DV off)> _pts = new();

	// ---- the world ----
	private TerrainFieldCs _field; private Callable _top; private bool _useField;
	private double[] _cyl = Array.Empty<double>();
	private double _water = -1e9;
	private double[] _gh = Array.Empty<double>(), _gx = Array.Empty<double>(), _gz = Array.Empty<double>();
	private DV[] _gn = Array.Empty<DV>();

	// ---- motors (set by ragdoll.gd each step) ----
	// [target world direction of the child's long axis, strength] per joint; strength 0 = no muscle
	private readonly DV[] _mDir = new DV[12];
	private readonly double[] _mK = new double[12];
	private readonly Transform3D[] _shoeOff = new Transform3D[2];   // foot body -> the shoe node (drawing)
	public static bool OldTwistRef = System.Environment.GetEnvironmentVariable("BMX_OLD_TWISTREF") == "1";
	public double LegDampMul = 1.0;   // the leg joints' damping x (the balance controller: PD, not a bouncing spring)
	public float AnkleMax = 1e9f;   // the ankles' strength at most (the balance controller: a stiff ankle on a flat foot springs him up)
	public int DbgJ = 0;   // tests: joint limits off by bit (joint index)
	public double ToneHz = 1.4;        // a joint at strength 1 springs back at about this frequency
	public double Mu = 0.85, Bounce = 0.1, BounceMin = 2.5;
	public double MaxDepenV = 3.0;
	public double MaxV = 40.0, MaxW = 40.0;   // m/s, rad/s
	public int Dbg;   // tests: 1 = no limits, 2 = no motors, 4 = no contacts, 8 = no self contacts, 16 = no anchors   // m/s at most from pushing a part out of the ground
	public int Substeps = 10;
	public double LinDrag = 0.02, AirAngDrag = 0.15;

	// per step results
	private byte[] _touch = new byte[15];
	private double[] _hit = new double[15];   // the hardest speed into the ground this step, per point (m/s)
	public double Speed;

	// =================================================================================================================
	/// pts: the 15 joint points (world); vel: each point's velocity; fsign: +1 if the body's forward is (right x up)
	/// computed as Ragdoll._frame does (the knees' side). neutralArm / neutralLeg: the arms' / thighs' natural directions
	/// in the torso frame (right side; x right, y up, z forward).
	/// shoeL / shoeR: the shoes' world transforms; shoeMin / shoeMax: a shoe's mesh box in its own space (x heel -> toe,
	/// y sole -> top): the feet are built from them
	public void Begin(Vector3[] pts, Vector3[] vel, float fsign, Vector3 neutralArm, Vector3 neutralLeg,
		Transform3D shoeL, Transform3D shoeR, Vector3 shoeMin, Vector3 shoeMax)
	{
		_j.Clear(); _sph.Clear(); _pts.Clear();
		DV P(int i) => DV.From(pts[i]);
		DV Vl(int i) => DV.From(vel[i]);
		// the torso frame (Ragdoll._frame): x = right, y = up the spine, z = forward
		DV up = (P(CHEST) - P(PELVIS)).Norm();
		DV rgt = (P(HIP_R) - P(HIP_L)) + (P(SH_R) - P(SH_L));
		rgt = (rgt - up * rgt.Dot(up)).Norm();
		DV fwd = up.Cross(rgt) * fsign;
		DV TF(DV d) => rgt * d.X + up * d.Y + fwd * d.Z;   // torso frame -> world
		DV waist = P(PELVIS) + (P(CHEST) - P(PELVIS)) * 0.4;
		DV neck = P(CHEST) + (P(HEAD) - P(CHEST)) * 0.35;

		// bodies: each built along its bone (body y = proximal -> distal; torso: up)
		_b[B_PELVIS] = MakeBody(MASS[B_PELVIS], P(PELVIS), up, rgt, P(HIP_L), P(HIP_R), 0.09);
		_b[B_CHEST] = MakeBody(MASS[B_CHEST], (waist + P(CHEST)) * 0.5, up, rgt, waist, P(CHEST), 0.12);
		var ch = _b[B_CHEST]; ch.B0 = ch.ToLocal(P(SH_L)); ch.B1 = ch.ToLocal(P(SH_R)); ch.RB = 0.08;
		_b[B_HEAD] = MakeBody(MASS[B_HEAD], P(HEAD), (P(HEAD) - neck).Norm(), rgt, P(HEAD), P(HEAD), 0.15);
		_b[B_UARM_L] = MakeLimb(B_UARM_L, P(SH_L), P(EL_L), rgt, 0.06);
		_b[B_FARM_L] = MakeLimb(B_FARM_L, P(EL_L), P(HA_L), rgt, 0.05);
		_b[B_UARM_R] = MakeLimb(B_UARM_R, P(SH_R), P(EL_R), rgt, 0.06);
		_b[B_FARM_R] = MakeLimb(B_FARM_R, P(EL_R), P(HA_R), rgt, 0.05);
		_b[B_THIGH_L] = MakeLimb(B_THIGH_L, P(HIP_L), P(KN_L), rgt, 0.075);
		_b[B_SHIN_L] = MakeLimb(B_SHIN_L, P(KN_L), P(FT_L), rgt, 0.06);
		_b[B_THIGH_R] = MakeLimb(B_THIGH_R, P(HIP_R), P(KN_R), rgt, 0.075);
		_b[B_SHIN_R] = MakeLimb(B_SHIN_R, P(KN_R), P(FT_R), rgt, 0.06);
		// feet: heel -> toe along the shoe, on its sole (a capsule a little in from the shoe's box)
		const double FR = 0.035;
		DV[] heel = new DV[2], toe = new DV[2];
		Transform3D[] sx = { shoeL, shoeR };
		for (int f = 0; f < 2; f++)
		{
			Transform3D t = sx[f];
			heel[f] = DV.From(t * new Vector3(shoeMin.X + (float)FR, shoeMin.Y + (float)FR, 0));
			toe[f] = DV.From(t * new Vector3(shoeMax.X - (float)FR, shoeMin.Y + (float)FR, 0));
			DV sup = DV.From(t.Basis.Y).Norm();
			int bi = f == 0 ? B_FOOT_L : B_FOOT_R;
			_b[bi] = MakeBody(MASS[bi], (heel[f] + toe[f]) * 0.5, (toe[f] - heel[f]).Norm(), sup, heel[f], toe[f], FR);
			_shoeOff[f] = BodyNow(bi).AffineInverse() * t;
		}

		// velocities: each body moves with its points' mean
		int[][] own = {
			new[] { PELVIS, HIP_L, HIP_R }, new[] { CHEST, SH_L, SH_R }, new[] { HEAD },
			new[] { SH_L, EL_L }, new[] { EL_L, HA_L }, new[] { SH_R, EL_R }, new[] { EL_R, HA_R },
			new[] { HIP_L, KN_L }, new[] { KN_L, FT_L }, new[] { HIP_R, KN_R }, new[] { KN_R, FT_R }, new[] { FT_L }, new[] { FT_R } };
		for (int i = 0; i < NB; i++)
		{
			DV v = default; foreach (int k in own[i]) v += Vl(k);
			_b[i].V = v / own[i].Length; _b[i].W = default; _b[i].Free = false;
		}

		// joints
		// spine: chest on pelvis at the waist; bends 0.75 rad any way, twists +-0.5
		AddBall(B_PELVIS, B_CHEST, waist, up, up, rgt, 0.75, -0.5, 0.5, 10);
		// neck: head on chest; 0.8 rad, turns +-1.1
		AddBall(B_CHEST, B_HEAD, neck, up, (P(HEAD) - neck).Norm(), rgt, 0.8, -1.1, 1.1, 10);
		// shoulders: a cone of 2.0 rad round the arm's natural direction, twist +-1.3
		DV armR = TF(DV.From(neutralArm)).Norm(), armL = TF(new DV(-neutralArm.X, neutralArm.Y, neutralArm.Z)).Norm();
		AddBall(B_CHEST, B_UARM_L, P(SH_L), armL, (P(EL_L) - P(SH_L)).Norm(), fwd, 2.0, -1.3, 1.3, 6);
		AddBall(B_CHEST, B_UARM_R, P(SH_R), armR, (P(EL_R) - P(SH_R)).Norm(), fwd, 2.0, -1.3, 1.3, 6);
		// hips: 1.35 rad round the thigh's natural direction, twist +-0.6
		DV legR = TF(DV.From(neutralLeg)).Norm(), legL = TF(new DV(-neutralLeg.X, neutralLeg.Y, neutralLeg.Z)).Norm();
		AddBall(B_PELVIS, B_THIGH_L, P(HIP_L), legL, (P(KN_L) - P(HIP_L)).Norm(), fwd, 1.35, -0.6, 0.6, 8);
		AddBall(B_PELVIS, B_THIGH_R, P(HIP_R), legR, (P(KN_R) - P(HIP_R)).Norm(), fwd, 1.35, -0.6, 0.6, 8);
		// elbows / knees: hinges. The axis: the limb's own bend axis as it is now (the riding pose bends both the right
		// way), else the body's right (elbows) / left (knees). 0 = straight .. 2.6 rad
		// (anatomical right = forward x up: the hips' labels can be either side of the body, see fsign)
		DV anatR = fwd.Cross(up).Norm();
		AddHinge(B_UARM_L, B_FARM_L, P(SH_L), P(EL_L), P(HA_L), anatR, 0.0, 2.6, 6);
		AddHinge(B_UARM_R, B_FARM_R, P(SH_R), P(EL_R), P(HA_R), anatR, 0.0, 2.6, 6);
		AddHinge(B_THIGH_L, B_SHIN_L, P(HIP_L), P(KN_L), P(FT_L), anatR * -1, 0.0, 2.6, 8);
		AddHinge(B_THIGH_R, B_SHIN_R, P(HIP_R), P(KN_R), P(FT_R), anatR * -1, 0.0, 2.6, 8);
		// ankles (joints 10 / 11): the foot round its riding position: toes up / down and turned within 0.55 rad, rolled
		// onto its edges +-0.35 rad (the twist about the foot's length)
		for (int f = 0; f < 2; f++)
		{
			int sh = f == 0 ? B_SHIN_L : B_SHIN_R, fo = f == 0 ? B_FOOT_L : B_FOOT_R;
			DV dir = (toe[f] - heel[f]).Norm();
			AddBall(sh, fo, P(f == 0 ? FT_L : FT_R), dir, dir, DV.From(sx[f].Basis.Y).Norm(), 0.55, -0.35, 0.35, 8);
		}

		// contact spheres (+ the point each stands for)
		Sph(B_PELVIS, P(HIP_L), 0.11, HIP_L); Sph(B_PELVIS, P(HIP_R), 0.11, HIP_R); Sph(B_PELVIS, P(PELVIS), 0.12, PELVIS);
		Sph(B_CHEST, waist, 0.14, PELVIS); Sph(B_CHEST, P(CHEST), 0.14, CHEST); Sph(B_CHEST, (waist + P(CHEST)) * 0.5, 0.15, CHEST);
		Sph(B_CHEST, P(SH_L), 0.08, SH_L); Sph(B_CHEST, P(SH_R), 0.08, SH_R);
		Sph(B_HEAD, P(HEAD), 0.15, HEAD);
		void Limb(int b, int a, int e, double r) { Sph(b, P(a), r, a); Sph(b, (P(a) + P(e)) * 0.5, r, e); Sph(b, P(e), r, e); }
		Limb(B_UARM_L, SH_L, EL_L, 0.06); Limb(B_FARM_L, EL_L, HA_L, 0.055); Limb(B_UARM_R, SH_R, EL_R, 0.06); Limb(B_FARM_R, EL_R, HA_R, 0.055);
		Limb(B_THIGH_L, HIP_L, KN_L, 0.075); Limb(B_SHIN_L, KN_L, FT_L, 0.065); Limb(B_THIGH_R, HIP_R, KN_R, 0.075); Limb(B_SHIN_R, KN_R, FT_R, 0.065);
		// a foot stands on five spheres: heel, middle, toe and both sides of the ball (a sole, not a ball)
		for (int f = 0; f < 2; f++)
		{
			int bi = f == 0 ? B_FOOT_L : B_FOOT_R, pt = f == 0 ? FT_L : FT_R;
			DV side = DV.From(sx[f].Basis.Z).Norm() * Math.Max(0.02, (shoeMax.Z - shoeMin.Z) * 0.5 - FR);
			DV ball = heel[f] + (toe[f] - heel[f]) * 0.7;
			Sph(bi, heel[f], FR, pt); Sph(bi, (heel[f] + toe[f]) * 0.5, FR, pt); Sph(bi, toe[f], FR, pt);
			Sph(bi, ball + side, FR, pt); Sph(bi, ball - side, FR, pt);
		}
		int ns = _sph.Count;
		_gh = new double[ns]; _gx = new double[ns]; _gz = new double[ns]; _gn = new DV[ns];
		for (int i = 0; i < ns; i++) _gx[i] = double.NaN;

		// output points
		Pt(B_HEAD, P(HEAD)); Pt(B_CHEST, P(CHEST)); Pt(B_PELVIS, P(PELVIS));
		Pt(B_CHEST, P(SH_L)); Pt(B_UARM_L, P(EL_L)); Pt(B_FARM_L, P(HA_L));
		Pt(B_CHEST, P(SH_R)); Pt(B_UARM_R, P(EL_R)); Pt(B_FARM_R, P(HA_R));
		Pt(B_PELVIS, P(HIP_L)); Pt(B_THIGH_L, P(KN_L)); Pt(B_SHIN_L, P(FT_L));
		Pt(B_PELVIS, P(HIP_R)); Pt(B_THIGH_R, P(KN_R)); Pt(B_SHIN_R, P(FT_R));
		for (int k = 0; k < 10; k++) _mK[k] = 0;
		_touch = new byte[15]; _hit = new double[15];
		_settle = true;
	}

	// the start pose can have parts in the ground (a crash upside down in a flip: the joints are lifted onto it, but the
	// capsules round them are 6-15 cm thick): pushed out in one substep, an off-centre part was also twisted, and that
	// read as spins of hundreds of rad/s. So before the first step, overlaps and joints are resolved a few times with the
	// velocities untouched (they are their own state); the ground must be set first, so it runs at the first Step
	private bool _settle;
	private void Settle()
	{
		_settle = false;
		for (int it = 0; it < 12; it++)
		{
			for (int k = 0; k < _j.Count; k++)
			{
				var jt = _j[k]; if (!jt.On) continue;
				Body P = _b[jt.P], C = _b[jt.C];
				PosConstraint(P, C, P.ToWorld(jt.AP), C.ToWorld(jt.AC), 0);
				if (jt.Limits) { if (jt.Kind == 1) HingeLimits(jt, P, C); else BallLimits(jt, P, C); }
			}
			for (int i = 0; i < _sph.Count; i++)
			{
				var (bi, lc, r, pt) = _sph[i];
				Body b = _b[bi];
				DV c = b.ToWorld(lc);
				_Ground(i, c.X, c.Z, out double g, out DV gn);
				double pen = r - (c.Y - g) * gn.Y;
				if (pen <= 0) continue;
				DV rr = c - gn * r - b.X;
				double w = b.InvM + rr.Cross(gn).Dot(b.InvIW(rr.Cross(gn)));
				ApplyPos(b, gn * (pen / Math.Max(w, 1e-9)), rr, 1);
			}
			SelfContacts();
		}
		foreach (var b in _b) { b.XP = b.X; b.QP = b.Q; }
	}

	private Body MakeBody(double m, DV centre, DV yAxis, DV xHint, DV a, DV b, double r)
	{
		DV y = yAxis.Norm();
		DV x = (xHint - y * xHint.Dot(y)); if (x.Len2() < 1e-8) x = Perp(y); x = x.Norm();
		DV z = x.Cross(y);
		var bd = new Body { X = centre, Q = DQ.FromBasis(x, y, z), InvM = 1.0 / m, R = r };
		bd.XP = bd.X; bd.QP = bd.Q;
		bd.A0 = bd.ToLocal(a); bd.A1 = bd.ToLocal(b);
		// inertia of a capsule ~ a solid cylinder along its local axis (+ a floor: no needle-thin bodies)
		DV ax = bd.A1 - bd.A0; double L = ax.Len(); DV au = L > 1e-6 ? ax / L : new DV(0, 1, 0);
		double iAx = 0.5 * m * r * r, iPerp = m * (3 * r * r + L * L) / 12.0;
		double ix = iPerp + (iAx - iPerp) * au.X * au.X, iy = iPerp + (iAx - iPerp) * au.Y * au.Y, iz = iPerp + (iAx - iPerp) * au.Z * au.Z;
		double fl = m * 0.004;
		ix = Math.Max(ix, fl); iy = Math.Max(iy, fl); iz = Math.Max(iz, fl);
		bd.InvI = new DV(1 / ix, 1 / iy, 1 / iz);
		bd.Iscalar = (ix + iy + iz) / 3.0;
		return bd;
	}
	private Body MakeLimb(int i, DV a, DV b, DV xHint, double r) => MakeBody(MASS[i], (a + b) * 0.5, (b - a).Norm(), xHint, a, b, r);
	private void Sph(int b, DV world, double r, int pt) => _sph.Add((b, _b[b].ToLocal(world), r, pt));
	private void Pt(int b, DV world) => _pts.Add((b, _b[b].ToLocal(world)));
	private static DV Perp(DV v) => Math.Abs(v.X) < 0.9 ? v.Cross(new DV(1, 0, 0)).Norm() : v.Cross(new DV(0, 1, 0)).Norm();

	private void AddBall(int p, int c, DV anchor, DV coneAxis, DV childAxis, DV refHint, double swing, double twLo, double twHi, double damp)
	{
		Body P = _b[p], C = _b[c];
		DV r1 = (refHint - coneAxis * refHint.Dot(coneAxis)); if (r1.Len2() < 1e-8) r1 = Perp(coneAxis); r1 = r1.Norm();
		// the child's reference = the parent's carried over by the swing (the shortest turn cone axis -> child axis), so the
		// start pose has no twist. (It was the hint projected onto the child's axis: a riding thigh points nearly along
		// "forward", that projection degenerated, the hip started ~1 rad "twisted" and its limit spun the pelvis.)
		DV r2;
		if (OldTwistRef) { r2 = (refHint - childAxis * refHint.Dot(childAxis)); if (r2.Len2() < 1e-8) r2 = Perp(childAxis); r2 = r2.Norm(); }
		else
		{
			DV ca = coneAxis.Norm(), cb = childAxis.Norm();
			DV ax = ca.Cross(cb); double sn = ax.Len(), cs = ca.Dot(cb);
			r2 = sn > 1e-7 ? DQ.AxisAngle(ax / sn, Math.Atan2(sn, cs)).Rot(r1) : (cs > 0 ? r1 : r1 * -1);
			r2 = (r2 - cb * r2.Dot(cb)).Norm();
		}
		_j.Add(new Joint { P = p, C = c, AP = P.ToLocal(anchor), AC = C.ToLocal(anchor), Kind = 0,
			SwingP = P.Q.Conj().Rot(coneAxis.Norm()), AxisC = C.Q.Conj().Rot(childAxis.Norm()),
			RefP = P.Q.Conj().Rot(r1), RefC = C.Q.Conj().Rot(r2), Swing = swing, TwistLo = twLo, TwistHi = twHi, Damp = damp });
	}

	/// a hinge at `mid` between the bone root->mid (parent) and mid->end (child); fallback = the axis if the limb is straight
	private void AddHinge(int p, int c, DV root, DV mid, DV end, DV fallback, double lo, double hi, double damp)
	{
		Body P = _b[p], C = _b[c];
		DV u = mid - root, w = end - mid;
		DV n = u.Cross(w);
		double bend = n.Len() / Math.Max(u.Len() * w.Len(), 1e-9);
		DV axis = bend > 0.15 ? n.Norm() : (fallback - u.Norm() * fallback.Dot(u.Norm())).Norm();
		// references: each bone's own direction, so the hinge angle = the bend (0 = straight)
		_j.Add(new Joint { P = p, C = c, AP = P.ToLocal(mid), AC = C.ToLocal(mid), Kind = 1,
			SwingP = P.Q.Conj().Rot(axis), AxisC = C.Q.Conj().Rot(axis),
			RefP = P.Q.Conj().Rot(u.Norm()), RefC = C.Q.Conj().Rot(w.Norm()), TwistLo = lo, TwistHi = hi, Damp = damp });
	}

	// =================================================================================================================
	public void SetGround(GodotObject field, Callable top, float water)
	{
		_field = field as TerrainFieldCs; _top = top; _useField = _field != null; _water = water;
	}
	/// trunks: x, z, r, top per cylinder
	public void SetTrunks(float[] cyl) { _cyl = new double[cyl.Length]; for (int i = 0; i < cyl.Length; i++) _cyl[i] = cyl[i]; }

	/// joint motors: dirs[k] = where the child's long axis should point (world), k = joint index (0 spine, 1 neck, 2/3
	/// shoulders L/R, 4/5 hips L/R, 6/7 elbows L/R, 8/9 knees L/R); strength[k] (0 = off, 1 = the tone)
	public void SetMotors(Vector3[] dirs, float[] strength)
	{
		for (int k = 0; k < 10 && k < dirs.Length; k++) { _mDir[k] = DV.From(dirs[k]); _mK[k] = strength[k]; }
	}

	/// a couple between two bodies (an angular impulse on a, minus on b): the squirm, the righting twist
	public void Couple(int a, int b, Vector3 angImpulse)
	{
		DV L = DV.From(angImpulse);
		_b[a].W += _b[a].InvIW(L); _b[b].W -= _b[b].InvIW(L);
	}

	/// a joint's limits off (a broken elbow / knee: it folds any way) or the joint gone (a torn-off limb)
	public void BreakJoint(int j) { if (j >= 0 && j < _j.Count) { _j[j].Limits = false; _mK[j] = 0; } }
	/// tear the joint: the child (and what hangs on it) is its own body. Returns the index of a new output point at the
	/// child's root (ragdoll.gd: the torn piece's root point)
	public int Sever(int j)
	{
		if (j < 0 || j >= _j.Count || !_j[j].On) return -1;
		var jt = _j[j]; jt.On = false; _mK[j] = 0;
		_b[jt.C].Free = true;
		_pts.Add((jt.C, jt.AC));
		return _pts.Count - 1;
	}

	/// move a point now (a push from outside: the bike) by dpos without speed from it, and change its velocity by dvel
	public void PushPoint(int pt, Vector3 dpos, Vector3 dvel)
	{
		if (pt < 0 || pt >= _pts.Count) return;
		var (bi, off) = _pts[pt];
		Body b = _b[bi];
		DV r = b.Q.Rot(off);
		DV d = DV.From(dpos);
		double dl = d.Len();
		if (dl > 1e-7)
		{
			DV n = d / dl;
			double w = b.InvM + r.Cross(n).Dot(b.InvIW(r.Cross(n)));
			DV P = n * (dl / Math.Max(w, 1e-9));
			ApplyPos(b, P, r, 1);   // (positions only: velocities are their own state)
		}
		DV dv = DV.From(dvel);
		double vl = dv.Len();
		if (vl > 1e-7)
		{
			DV n = dv / vl;
			double w = b.InvM + r.Cross(n).Dot(b.InvIW(r.Cross(n)));
			DV J = n * (vl / Math.Max(w, 1e-9));
			b.V += J * b.InvM; b.W += b.InvIW(r.Cross(J));
		}
	}

	// =================================================================================================================
	public void Step(float dtf)
	{
		Array.Clear(_touch); Array.Clear(_hit);
		double h = dtf / Math.Max(1, Substeps);
		if (_settle) Settle();
		for (int s = 0; s < Substeps; s++)
		{
			// integrate
			for (int i = 0; i < NB; i++)
			{
				Body b = _b[i];
				bool wet = b.X.Y < _water;
				b.V.Y -= (wet ? 2.0 : 9.81) * h;
				double ld = Math.Exp(-(wet ? 3.0 : LinDrag) * h);
				b.V *= ld; b.W *= Math.Exp(-(wet ? 3.0 : AirAngDrag) * h);
				b.XP = b.X; b.QP = b.Q;
				b.X += b.V * h;
				b.Q = (b.Q + new DQ(0, b.W.X, b.W.Y, b.W.Z) * b.Q * (0.5 * h)).Normalized();
			}
			// joints: anchors together, then limits, then muscles
			for (int k = 0; k < _j.Count; k++)
			{
				var jt = _j[k]; if (!jt.On) continue;
				Body P = _b[jt.P], C = _b[jt.C];
				// anchor: the two points together (rigid)
				DV pa = P.ToWorld(jt.AP), ca = C.ToWorld(jt.AC);
				if ((Dbg & 16) == 0) PosConstraint(P, C, pa, ca, 0);
				if (jt.Limits && (Dbg & 1) == 0 && ((DbgJ >> k) & 1) == 0)
				{
					if (jt.Kind == 1) HingeLimits(jt, P, C);
					else BallLimits(jt, P, C);
				}
				if (k >= 10 && k < 12) { _mDir[k] = P.Dir(jt.SwingP); _mK[k] = Math.Min(AnkleMax, Math.Max(0.3, _mK[k - 2])); }   // ankles: held at their natural angle, as firm as the knee
				if (k < 12 && _mK[k] > 1e-4 && !C.Free && (Dbg & 2) == 0) Motor(k, jt, P, C, h);
			}
			// contacts
			if ((Dbg & 4) == 0) Contacts(h);
			if ((Dbg & 8) == 0) SelfContacts();
			// velocities from the move
			for (int i = 0; i < NB; i++)
			{
				Body b = _b[i];
				b.V = (b.X - b.XP) / h;
				DQ dq = b.Q * b.QP.Conj();
				DV w = new DV(dq.X, dq.Y, dq.Z) * (2.0 / h);
				b.W = dq.W >= 0 ? w : w * -1;
				// a safety net (the old ragdoll had one too): no part faster / spinning faster than a body can
				double vl = b.V.Len(); if (vl > MaxV) b.V *= MaxV / vl;
				double wl = b.W.Len(); if (wl > MaxW) b.W *= MaxW / wl;
			}
			ContactVelocities(h);
			JointDamping(h);
		}
		Speed = 0;
		foreach (var b in _b) Speed = Math.Max(Speed, b.V.Len() + b.W.Len() * 0.3);
	}

	// ---- constraints --------------------------------------------------------------------------------------------------
	// a positional impulse P (impulse x h) at r (offset from the centre, world) on b, sign +1 / -1
	private static void ApplyPos(Body b, DV P, DV r, double sign)
	{
		b.X += P * (b.InvM * sign);
		DV dw = b.InvIW(r.Cross(P)) * sign;
		b.Q = (b.Q + new DQ(0, dw.X, dw.Y, dw.Z) * b.Q * 0.5).Normalized();
	}
	private static void ApplyRot(Body b, DV dphi, double sign)
	{
		DV dw = b.InvIW(dphi) * sign;
		b.Q = (b.Q + new DQ(0, dw.X, dw.Y, dw.Z) * b.Q * 0.5).Normalized();
	}

	/// pull a (on p) and b (on c) together by the fraction (1 - compliance share); compliance 0 = rigid
	private static void PosConstraint(Body p, Body c, DV a, DV b, double alphaTilde)
	{
		DV d = b - a; double len = d.Len();
		if (len < 1e-9) return;
		DV n = d / len;
		DV r1 = a - p.X, r2 = b - c.X;
		double w1 = p.InvM + r1.Cross(n).Dot(p.InvIW(r1.Cross(n)));
		double w2 = c.InvM + r2.Cross(n).Dot(c.InvIW(r2.Cross(n)));
		double lam = len / (w1 + w2 + alphaTilde);
		DV P = n * lam;
		ApplyPos(p, P, r1, 1); ApplyPos(c, P, r2, -1);
	}

	/// rotate p by +theta about n and c by -theta's share (XPBD angular constraint, compliance alphaTilde)
	private static void AngConstraint(Body p, Body c, DV dphi, double alphaTilde)
	{
		double th = dphi.Len(); if (th < 1e-9) return;
		DV n = dphi / th;
		double w1 = n.Dot(p.InvIW(n)), w2 = n.Dot(c.InvIW(n));
		double lam = th / (w1 + w2 + alphaTilde);
		ApplyRot(p, n * lam, 1); ApplyRot(c, n * lam, -1);
	}

	/// the signed angle of n2 from n1 about n, clamped to [lo, hi]: the correction rotation (for body 1) or zero
	private static DV LimitAngle(DV n, DV n1, DV n2, double lo, double hi)
	{
		double phi = Math.Atan2(n.Dot(n1.Cross(n2)), n1.Dot(n2));
		if (phi >= lo && phi <= hi) return default;
		double tgt = Math.Clamp(phi, lo, hi);
		DV n1r = DQ.AxisAngle(n, tgt).Rot(n1);
		return n1r.Cross(n2);
	}

	private static void HingeLimits(Joint j, Body P, Body C)
	{
		// the hinge axes aligned (no sideways bend, no twist)
		DV a1 = P.Dir(j.SwingP), a2 = C.Dir(j.AxisC);
		AngConstraint(P, C, a1.Cross(a2), 0);
		// the bend within its range: angle from the parent bone's direction to the child's about the axis
		a1 = P.Dir(j.SwingP);
		DV b1 = P.Dir(j.RefP), b2 = C.Dir(j.RefC);
		DV corr = LimitAngle(a1, b1, b2, j.TwistLo, j.TwistHi);
		if (corr.Len2() > 0) AngConstraint(P, C, corr, 0);
	}

	private static void BallLimits(Joint j, Body P, Body C)
	{
		// swing: the child's axis within the cone round the parent's
		DV a1 = P.Dir(j.SwingP), a2 = C.Dir(j.AxisC);
		double ang = Math.Acos(Math.Clamp(a1.Dot(a2), -1, 1));
		if (ang > j.Swing)
		{
			DV n = a1.Cross(a2); double nl = n.Len();
			if (nl < 1e-6) n = Perp(a1); else n /= nl;
			AngConstraint(P, C, n * (ang - j.Swing), 0);
		}
		// twist: the references about the mean axis
		a1 = P.Dir(j.SwingP); a2 = C.Dir(j.AxisC);
		DV m = a1 + a2; double ml = m.Len();
		if (ml < 1e-6) return;
		m /= ml;
		DV b1 = P.Dir(j.RefP), b2 = C.Dir(j.RefC);
		DV n1 = b1 - m * m.Dot(b1), n2 = b2 - m * m.Dot(b2);
		if (n1.Len2() < 1e-8 || n2.Len2() < 1e-8) return;
		DV corr = LimitAngle(m, n1.Norm(), n2.Norm(), j.TwistLo, j.TwistHi);
		if (corr.Len2() > 0) AngConstraint(P, C, corr, 0);
	}

	/// muscle: the child's long axis toward the target direction, a spring of ToneHz x sqrt(strength) on its inertia
	private void Motor(int k, Joint j, Body P, Body C, double h)
	{
		DV tgt = _mDir[k]; if (tgt.Len2() < 1e-8) return;
		tgt = tgt.Norm();
		DV axis = j.Kind == 1 ? C.Dir(j.RefC) : C.Dir(j.AxisC);   // the child bone's direction
		DV n; double th;
		if (j.Kind == 1)
		{
			// a hinge only turns about its own axis: the target seen in the hinge's plane (a turn about any other axis
			// fought the hinge every substep and spun the limb up)
			DV ha = C.Dir(j.AxisC);
			DV tp = tgt - ha * tgt.Dot(ha);
			if (tp.Len2() < 1e-6) return;
			tp = tp.Norm();
			th = Math.Atan2(ha.Dot(axis.Cross(tp)), axis.Dot(tp));
			n = th >= 0 ? ha : ha * -1; th = Math.Abs(th);
			if (th < 1e-5) return;
		}
		else
		{
			DV rot = axis.Cross(tgt);
			double s = rot.Len(), c = axis.Dot(tgt);
			th = Math.Atan2(s, c);
			if (th < 1e-5) return;
			n = s > 1e-9 ? rot / s : Perp(axis);
		}
		double wn = 2 * Math.PI * ToneHz * Math.Sqrt(_mK[k]);
		double kSpring = C.Iscalar * wn * wn;            // torque per rad
		double alphaTilde = 1.0 / (kSpring * h * h);
		// rotate the child (+) toward the target, the parent (-) back: equal and opposite
		AngConstraint(C, P, n * th, alphaTilde);
	}

	private void JointDamping(double h)
	{
		foreach (var j in _j)
		{
			if (!j.On) continue;
			Body P = _b[j.P], C = _b[j.C];
			double dm = (j.C == B_THIGH_L || j.C == B_THIGH_R || j.C == B_SHIN_L || j.C == B_SHIN_R || j.C == B_FOOT_L || j.C == B_FOOT_R) ? LegDampMul : 1.0;
			double d = 1 - Math.Exp(-j.Damp * dm * h);
			DV wr = C.W - P.W;
			DV L = wr * (d / (1 / C.Iscalar + 1 / P.Iscalar));
			C.W -= L / C.Iscalar; P.W += L / P.Iscalar;
		}
	}

	// ---- contacts -----------------------------------------------------------------------------------------------------
	private readonly List<(int si, DV n, double vnPre, double pen)> _ct = new();

	private double _GroundAt(double x, double z)
	{
		if (_useField) return _field.top_height(x, z);
		if (_top.Target == null) return -1e9;
		Variant r = _top.Call(x, z);
		return r.VariantType == Variant.Type.Nil ? -1e9 : r.AsDouble();
	}
	private void _Ground(int i, double x, double z, out double g, out DV n)
	{
		if (!double.IsNaN(_gx[i]) && Math.Abs(x - _gx[i]) < 0.02 && Math.Abs(z - _gz[i]) < 0.02) { g = _gh[i]; n = _gn[i]; return; }
		g = _GroundAt(x, z);
		const double e = 0.12;
		double gx = _GroundAt(x + e, z) - g, gz = _GroundAt(x, z + e) - g;
		n = new DV(-gx, e, -gz).Norm();
		_gh[i] = g; _gx[i] = x; _gz[i] = z; _gn[i] = n;
	}

	private void Contacts(double h)
	{
		_ct.Clear();
		int nc = _cyl.Length / 4;
		for (int i = 0; i < _sph.Count; i++)
		{
			var (bi, lc, r, pt) = _sph[i];
			Body b = _b[bi];
			DV c = b.ToWorld(lc);
			// trunks: out sideways
			for (int k = 0; k < nc; k++)
			{
				double cx = _cyl[4 * k], cz = _cyl[4 * k + 1], cr = _cyl[4 * k + 2] + r, top = _cyl[4 * k + 3];
				if (c.Y > top) continue;
				double dx = c.X - cx, dz = c.Z - cz, d2 = dx * dx + dz * dz;
				if (d2 >= cr * cr || d2 < 1e-10) continue;
				double d = Math.Sqrt(d2);
				DV n = new DV(dx / d, 0, dz / d);
				SolveContact(b, c - n * r, n, cr - d, h, i, pt);
				c = b.ToWorld(lc);
			}
			_Ground(i, c.X, c.Z, out double g, out DV gn);
			double dist = (c.Y - g) * gn.Y;
			double pen = r - dist;
			if (pen > 0) SolveContact(b, c - gn * r, gn, pen, h, i, pt);
		}
	}

	private void SolveContact(Body b, DV pc, DV n, double pen, double h, int si, int pt)
	{
		DV r = pc - b.X;
		DV lp = b.Q.Conj().Rot(r);   // the contact point, fixed on the body
		// the point's speed into the surface before this substep's push (for the bounce / the hit)
		DV vpt = b.V + b.W.Cross(r);
		double vn = vpt.Dot(n);
		double w = b.InvM + r.Cross(n).Dot(b.InvIW(r.Cross(n)));
		ApplyPos(b, n * (pen / Math.Max(w, 1e-9)), r, 1);
		// a deep start (a crash beginning with parts in the ground, upside down in a flip) pushed out in one substep read as
		// a launch: at most MaxDepenV of speed comes from a push-out, the rest moves the body without speed (the game
		// engines' "max depenetration velocity")
		double excess = pen - MaxDepenV * h;
		if (excess > 0) b.XP += n * (excess * b.InvM / Math.Max(w, 1e-9));
		// static friction (positional): the contact point's slide this substep, undone up to mu x the push
		DV now = b.X + b.Q.Rot(lp);
		DV before = b.XP + b.QP.Rot(lp);
		r = now - b.X;
		DV dp = now - before;
		DV dt = dp - n * dp.Dot(n);
		double tl = dt.Len();
		if (tl > 1e-9)
		{
			double cut = Math.Min(tl, Mu * pen);
			DV tn = dt / tl;
			double wt = b.InvM + r.Cross(tn).Dot(b.InvIW(r.Cross(tn)));
			ApplyPos(b, tn * (-cut / Math.Max(wt, 1e-9)), r, 1);
		}
		_ct.Add((si, n, vn, pen));
		if (pt >= 0 && pt < 15) { _touch[pt] = 1; _hit[pt] = Math.Max(_hit[pt], -vn); }
	}

	private void ContactVelocities(double h)
	{
		foreach (var (si, n, vnPre, pen) in _ct)
		{
			var (bi, lc, r, pt) = _sph[si];
			Body b = _b[bi];
			DV rr = b.Q.Rot(lc) - n * r;
			DV v = b.V + b.W.Cross(rr);
			double vn = v.Dot(n);
			DV vt = v - n * vn;
			DV dv = default;
			// dynamic friction: the slide slowed by mu x the normal push's speed
			double vtl = vt.Len();
			if (vtl > 1e-6) dv -= vt / vtl * Math.Min(Mu * Math.Max(pen / h, -vnPre), vtl);
			// a hard hit bounces a little; else nothing into the surface
			double want = vnPre < -BounceMin ? -vnPre * Bounce : 0;
			if (vn < want) dv += n * (want - vn);
			double dl = dv.Len();
			if (dl < 1e-7) continue;
			DV d = dv / dl;
			double w = b.InvM + rr.Cross(d).Dot(b.InvIW(rr.Cross(d)));
			DV J = d * (dl / Math.Max(w, 1e-9));
			b.V += J * b.InvM; b.W += b.InvIW(rr.Cross(J));
		}
	}

	// limbs against the trunk and against each other (not against their own neighbours)
	private static readonly (int a, int b)[] SELF = {
		(B_FARM_L, B_CHEST), (B_FARM_R, B_CHEST), (B_FARM_L, B_PELVIS), (B_FARM_R, B_PELVIS), (B_UARM_L, B_PELVIS), (B_UARM_R, B_PELVIS),
		(B_THIGH_L, B_CHEST), (B_THIGH_R, B_CHEST), (B_SHIN_L, B_CHEST), (B_SHIN_R, B_CHEST), (B_SHIN_L, B_PELVIS), (B_SHIN_R, B_PELVIS),
		(B_THIGH_L, B_THIGH_R), (B_SHIN_L, B_SHIN_R), (B_SHIN_L, B_THIGH_R), (B_SHIN_R, B_THIGH_L),
		(B_FARM_L, B_FARM_R), (B_FARM_L, B_HEAD), (B_FARM_R, B_HEAD), (B_SHIN_L, B_HEAD), (B_SHIN_R, B_HEAD),
		(B_FOOT_L, B_SHIN_R), (B_FOOT_R, B_SHIN_L), (B_FOOT_L, B_FOOT_R), (B_FOOT_L, B_THIGH_R), (B_FOOT_R, B_THIGH_L) };
	private void SelfContacts()
	{
		foreach (var (ia, ib) in SELF)
		{
			Body A = _b[ia], B = _b[ib];
			Capsule(A, A.A0, A.A1, A.R, B, B.A0, B.A1, B.R);
			if (B.RB > 0) Capsule(A, A.A0, A.A1, A.R, B, B.B0, B.B1, B.RB);
		}
	}
	private static void Capsule(Body A, DV a0l, DV a1l, double ra, Body B, DV b0l, DV b1l, double rb)
	{
		DV a0 = A.ToWorld(a0l), a1 = A.ToWorld(a1l), b0 = B.ToWorld(b0l), b1 = B.ToWorld(b1l);
		ClosestSeg(a0, a1, b0, b1, out DV pa, out DV pb);
		DV d = pa - pb; double dl = d.Len(); double pen = ra + rb - dl;
		if (pen <= 0 || dl < 1e-7) return;
		DV n = d / dl;
		DV r1 = pa - n * ra - A.X, r2 = pb + n * rb - B.X;
		double w1 = A.InvM + r1.Cross(n).Dot(A.InvIW(r1.Cross(n)));
		double w2 = B.InvM + r2.Cross(n).Dot(B.InvIW(r2.Cross(n)));
		DV P = n * (pen / (w1 + w2));
		ApplyPos(A, P, r1, 1); ApplyPos(B, P, r2, -1);
	}
	private static void ClosestSeg(DV p1, DV q1, DV p2, DV q2, out DV c1, out DV c2)
	{
		DV d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2;
		double a = d1.Dot(d1), e = d2.Dot(d2), f = d2.Dot(r);
		double s, t;
		if (a <= 1e-9 && e <= 1e-9) { c1 = p1; c2 = p2; return; }
		if (a <= 1e-9) { s = 0; t = Math.Clamp(f / e, 0, 1); }
		else
		{
			double c = d1.Dot(r);
			if (e <= 1e-9) { t = 0; s = Math.Clamp(-c / a, 0, 1); }
			else
			{
				double b = d1.Dot(d2), den = a * e - b * b;
				s = den > 1e-9 ? Math.Clamp((b * f - c * e) / den, 0, 1) : 0;
				t = (b * s + f) / e;
				if (t < 0) { t = 0; s = Math.Clamp(-c / a, 0, 1); }
				else if (t > 1) { t = 1; s = Math.Clamp((b - c) / a, 0, 1); }
			}
		}
		c1 = p1 + d1 * s; c2 = p2 + d2 * t;
	}

	// ---- results ------------------------------------------------------------------------------------------------------
	public Vector3[] Points()
	{
		var o = new Vector3[_pts.Count];
		for (int i = 0; i < o.Length; i++) { var (b, off) = _pts[i]; o[i] = _b[b].ToWorld(off).ToV(); }
		return o;
	}
	public Vector3[] PointVel()
	{
		var o = new Vector3[_pts.Count];
		for (int i = 0; i < o.Length; i++) { var (bi, off) = _pts[i]; Body b = _b[bi]; o[i] = (b.V + b.W.Cross(b.Q.Rot(off))).ToV(); }
		return o;
	}
	public byte[] Touch() => (byte[])_touch.Clone();
	private Transform3D BodyNow(int i) => new Transform3D(new Basis(_b[i].Q.ToQuat()), _b[i].X.ToV());
	/// the shoe node's world transform (0 left, 1 right): drawn from the foot body
	public Transform3D ShoeXf(int f) => BodyNow(f == 0 ? B_FOOT_L : B_FOOT_R) * _shoeOff[f];
	/// each body's speed and spin (tests): v0, w0, v1, w1 ...
	public float[] BodySpeeds() { var o = new float[NB * 2]; for (int i = 0; i < NB; i++) { o[2 * i] = (float)_b[i].V.Len(); o[2 * i + 1] = (float)_b[i].W.Len(); } return o; }
	public float[] Hit() { var o = new float[15]; for (int i = 0; i < 15; i++) o[i] = (float)_hit[i]; return o; }
	/// each body's transform (world): tests / a debug drawing
	public Transform3D BodyXf(int i) => new Transform3D(new Basis(_b[i].Q.ToQuat()), _b[i].X.ToV());
	/// how far each limited joint is past its limits (rad, worst): tests
	/// tests: each joint's excess past its limit (rad), in joint order
	public float[] LimitEach()
	{
		var o = new float[_j.Count];
		for (int i = 0; i < _j.Count; i++)
		{
			var j = _j[i];
			if (!j.On || !j.Limits) continue;
			Body P = _b[j.P], C = _b[j.C];
			if (j.Kind == 1)
			{
				DV a = P.Dir(j.SwingP);
				double phi = Math.Atan2(a.Dot(P.Dir(j.RefP).Cross(C.Dir(j.RefC))), P.Dir(j.RefP).Dot(C.Dir(j.RefC)));
				o[i] = (float)Math.Max(Math.Max(j.TwistLo - phi, phi - j.TwistHi), 0);
			}
			else o[i] = (float)Math.Max(Math.Acos(Math.Clamp(P.Dir(j.SwingP).Dot(C.Dir(j.AxisC)), -1, 1)) - j.Swing, 0);
		}
		return o;
	}

	public float WorstLimit()
	{
		double worst = 0;
		foreach (var j in _j)
		{
			if (!j.On || !j.Limits) continue;
			Body P = _b[j.P], C = _b[j.C];
			if (j.Kind == 1)
			{
				DV a = P.Dir(j.SwingP);
				double phi = Math.Atan2(a.Dot(P.Dir(j.RefP).Cross(C.Dir(j.RefC))), P.Dir(j.RefP).Dot(C.Dir(j.RefC)));
				worst = Math.Max(worst, Math.Max(j.TwistLo - phi, phi - j.TwistHi));
				worst = Math.Max(worst, Math.Acos(Math.Clamp(a.Dot(C.Dir(j.AxisC)), -1, 1)));
			}
			else
			{
				double ang = Math.Acos(Math.Clamp(P.Dir(j.SwingP).Dot(C.Dir(j.AxisC)), -1, 1));
				worst = Math.Max(worst, ang - j.Swing);
			}
		}
		return (float)worst;
	}

	/// tests: a body in the riding pose dropped from rest in the air (no ground), stepped n times; returns the biggest
	/// spin (rad/s) any body reached, and the worst joint gap (m) and limit overshoot as floats [spin, gap, limit]
	public float[] SelfTest(int dbg, int n, float hingeBend)
	{
		var p = new Vector3[15]; var v = new Vector3[15];
		float[] y = { 1.75f, 1.45f, 1.0f, 1.45f, 1.2f, 1.05f, 1.45f, 1.2f, 1.05f, 0.95f, 0.55f, 0.1f, 0.95f, 0.55f, 0.1f };
		float[] z = { 0, 0, 0, -0.2f, -0.22f, -0.22f, 0.2f, 0.22f, 0.22f, -0.1f, -0.1f, -0.1f, 0.1f, 0.1f, 0.1f };
		float[] x = { 0.05f, 0, 0, 0, 0.15f, 0.4f, 0, 0.15f, 0.4f, 0, 0.25f, 0.1f, 0, 0.25f, 0.1f };
		for (int i = 0; i < 15; i++) p[i] = new Vector3(x[i] * hingeBend, y[i] + 50, z[i]);
		Begin(p, v, 1, new Vector3(0.25f, -0.68f, 0.69f), new Vector3(0.1f, -0.64f, 0.76f),
			new Transform3D(Basis.Identity, p[FT_L] + new Vector3(0.02f, -0.05f, 0)), new Transform3D(Basis.Identity, p[FT_R] + new Vector3(0.02f, -0.05f, 0)),
			new Vector3(-0.1f, 0, -0.05f), new Vector3(0.16f, 0.1f, 0.05f));
		_useField = false; _top = new Callable();
		Dbg = dbg;
		var d = new Vector3[10]; var st = new float[10]; for (int k = 0; k < 10; k++) { d[k] = Vector3.Down; st[k] = 1; }
		SetMotors(d, st);
		double spin = 0, gap = 0;
		for (int i = 0; i < n; i++)
		{
			Step(1f / 120f);
			if (i > n * 3 / 4) foreach (var b in _b) spin = Math.Max(spin, b.W.Len());
			foreach (var j in _j) gap = Math.Max(gap, (_b[j.P].ToWorld(j.AP) - _b[j.C].ToWorld(j.AC)).Len());
		}
		Dbg = 0;
		return new float[] { (float)spin, (float)gap, WorstLimit() };
	}

	/// run every path once on a throwaway body (the ride loading): the first crash then costs no JIT compile
	public void Warm()
	{
		var p = new Vector3[15]; var v = new Vector3[15];
		float[] y = { 1.7f, 1.4f, 1.0f, 1.4f, 1.15f, 0.9f, 1.4f, 1.15f, 0.9f, 1.0f, 0.55f, 0.1f, 1.0f, 0.55f, 0.1f };
		float[] z = { 0, 0, 0, -0.2f, -0.25f, -0.25f, 0.2f, 0.25f, 0.25f, -0.1f, -0.1f, -0.1f, 0.1f, 0.1f, 0.1f };
		float[] x = { 0, 0, 0, 0, 0.05f, 0.25f, 0, 0.05f, 0.25f, 0, 0.1f, 0, 0, 0.1f, 0 };
		for (int i = 0; i < 15; i++) p[i] = new Vector3(x[i], y[i] + 2, z[i]);
		Begin(p, v, 1, new Vector3(0.25f, -0.68f, 0.69f), new Vector3(0.1f, -0.64f, 0.76f),
			new Transform3D(Basis.Identity, p[FT_L] + new Vector3(0.02f, -0.05f, 0)), new Transform3D(Basis.Identity, p[FT_R] + new Vector3(0.02f, -0.05f, 0)),
			new Vector3(-0.1f, 0, -0.05f), new Vector3(0.16f, 0.1f, 0.05f));
		SetTrunks(new float[] { 0.5f, 0.5f, 0.2f, 1e6f });
		var d = new Vector3[10]; var s = new float[10]; for (int k = 0; k < 10; k++) { d[k] = Vector3.Down; s[k] = 1; }
		SetMotors(d, s);
		for (int i = 0; i < 3; i++) Step(1f / 120f);
		PushPoint(5, new Vector3(0.01f, 0, 0), new Vector3(0, 1, 0)); Couple(1, 0, Vector3.Up * 0.1f);
		Points(); PointVel(); Touch(); Hit(); WorstLimit(); ShoeXf(0); ShoeXf(1); BreakJoint(6); Sever(7);
	}

	// ---- small double maths -------------------------------------------------------------------------------------------
	private struct DV
	{
		public double X, Y, Z;
		public DV(double x, double y, double z) { X = x; Y = y; Z = z; }
		public static DV From(Vector3 v) => new DV(v.X, v.Y, v.Z);
		public Vector3 ToV() => new Vector3((float)X, (float)Y, (float)Z);
		public static DV operator +(DV a, DV b) => new DV(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
		public static DV operator -(DV a, DV b) => new DV(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
		public static DV operator *(DV a, double k) => new DV(a.X * k, a.Y * k, a.Z * k);
		public static DV operator /(DV a, double k) => new DV(a.X / k, a.Y / k, a.Z / k);
		public double Dot(DV b) => X * b.X + Y * b.Y + Z * b.Z;
		public DV Cross(DV b) => new DV(Y * b.Z - Z * b.Y, Z * b.X - X * b.Z, X * b.Y - Y * b.X);
		public double Len2() => X * X + Y * Y + Z * Z;
		public double Len() => Math.Sqrt(Len2());
		public DV Norm() { double l = Len(); return l > 1e-12 ? this / l : new DV(0, 1, 0); }
	}
	private struct DQ
	{
		public double W, X, Y, Z;
		public DQ(double w, double x, double y, double z) { W = w; X = x; Y = y; Z = z; }
		public static readonly DQ Identity = new DQ(1, 0, 0, 0);
		public Quaternion ToQuat() => new Quaternion((float)X, (float)Y, (float)Z, (float)W).Normalized();
		public static DQ AxisAngle(DV a, double ang) { double s = Math.Sin(ang * 0.5); return new DQ(Math.Cos(ang * 0.5), a.X * s, a.Y * s, a.Z * s); }
		public static DQ FromBasis(DV x, DV y, DV z)
		{
			var q = new Basis(x.ToV(), y.ToV(), z.ToV()).Orthonormalized().GetRotationQuaternion();
			return new DQ(q.W, q.X, q.Y, q.Z).Normalized();
		}
		public static DQ operator *(DQ a, DQ b) => new DQ(
			a.W * b.W - a.X * b.X - a.Y * b.Y - a.Z * b.Z,
			a.W * b.X + a.X * b.W + a.Y * b.Z - a.Z * b.Y,
			a.W * b.Y - a.X * b.Z + a.Y * b.W + a.Z * b.X,
			a.W * b.Z + a.X * b.Y - a.Y * b.X + a.Z * b.W);
		public static DQ operator *(DQ a, double k) => new DQ(a.W * k, a.X * k, a.Y * k, a.Z * k);
		public static DQ operator +(DQ a, DQ b) => new DQ(a.W + b.W, a.X + b.X, a.Y + b.Y, a.Z + b.Z);
		public DQ Conj() => new DQ(W, -X, -Y, -Z);
		public DQ Normalized() { double l = Math.Sqrt(W * W + X * X + Y * Y + Z * Z); return l > 1e-12 ? new DQ(W / l, X / l, Y / l, Z / l) : Identity; }
		public DV Rot(DV v) { DV q = new DV(X, Y, Z); DV t = q.Cross(v) * 2.0; return v + t * W + q.Cross(t); }
	}
}
