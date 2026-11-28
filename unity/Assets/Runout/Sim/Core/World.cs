// Runout.Sim: the game's own simulation (bike, rider body, ragdoll, terrain field).
// This assembly has NO UnityEngine reference (noEngineReferences): it is the "engine plug".
// Unity (or a dotnet test, or anything else) plugs in by implementing IGround / IBikeHost.
// Units: metres, seconds, radians, double precision (GDScript floats are 64-bit: the port matches them).
// Axes as in the Godot game: right-handed, y up, the bike's forward = (cos heading, 0, -sin heading).
using System.Collections.Generic;

namespace Runout.Sim
{
    /// Ground surface code as the Godot Terrain.surface() returns it (physics tables index by it: 0..3).
    public static class Surf
    {
        public const int Ground = 0, Trail = 1, Water = 2, Sand = 3;
    }

    /// Something solid near the bike: rock dome, trunk, fence post, tape span, sign, cactus
    /// (the Godot colliders_near() dictionaries; names kept so the port reads the same).
    public sealed class Obstacle
    {
        public double x, z, r;
        public bool has_top; public double top = double.PositiveInfinity;   // a dome / log / post top (has("top"))
        public bool has_base; public double @base;
        public bool has_sink; public double sink;                           // rock / log sunk into the ground
        public bool has_ceil; public double ceil;                           // overhang / tunnel ceiling
        public bool fence, tape, cactus;
        /// a tape's span (Godot: c["tape"] = {broken, pts}); several colliders share one span object
        public TapeSpan tape_span;
        public string fence_style = "";
        public object handle;   // the host's own reference (to smash it, rock chips...)
    }

    /// One race-tape span between two stakes (world points along it); torn = broken.
    public sealed class TapeSpan
    {
        public bool broken;
        public V3[] pts;
    }

    /// What the simulation asks of the world (Godot: host.terrain).
    public interface IGround
    {
        /// Height the tyres ride on: land + rocks / logs / decks (Terrain.height).
        double height(double x, double z);
        /// Height of the land only, without rocks / logs (Terrain.deck_height: banks, lean room).
        double deck_height(double x, double z);
        /// Highest drawn surface (Terrain.top_height).
        double top_height(double x, double z);
        /// Surf code under (x, z).
        int surface(double x, double z);
        /// 0..1 how much this spot is a built jump / pump feature (Terrain.jump_mask).
        double jump_mask(double x, double z);
        /// Obstacles within reach of (x, z), appended to `into`.
        void colliders_near(double x, double z, List<Obstacle> into);
    }

    /// The drawn suspension the physics reads limits from (Godot: host.susp, Suspension). Null = none drawn (tests).
    public interface ISuspensionLimits
    {
        bool has_f { get; }
        bool has_r { get; }
        /// fork: room to its stop (m), Suspension.F["max"] / F["min"]; rear end the same (max - min = the drawn travel)
        double front_max { get; }
        double rear_max { get; }
        double front_min { get; }
        double rear_min { get; }
        /// tan of the steering axis' tilt (the fork slides along it: brake dive)
        double axis_tan { get; }
        void set_sag(double front, double rear);
    }

    /// Everything the bike physics tells or asks the game (Godot: the host's methods called from bike_physics.gd).
    /// Defaults do nothing, so a test host overrides only what it watches.
    public interface IBikeHost
    {
        IGround terrain { get; }
        ISuspensionLimits susp { get; }
        void flash(string text) { }
        bool msg_idle() { return true; }
        bool smash(Obstacle c, V3 vel, V3 pos) { return false; }
        void rock_chips(Obstacle c) { }
        void burst(V3 pos, int n, int surf, double power) { }
        void start_crash(string reason) { }
        void begin_getup() { }
        void on_style(int points, string name) { }
        void on_trick(string name) { }
        void on_takeoff() { }
        void on_landing(double air_time, double impact) { }
        void on_bad_landing(double severity) { }
        void flow_up() { }
        /// the cranks' rest angles [left, right] (Game.pedal_a0)
        double pedal_a0_left => 0.0;
        double pedal_a0_right => System.Math.PI;
        /// effects each ride step (dust, sound feeds): Game.ride_fx
        void ride_fx(double dt, V3 f, double va, bool in_water) { }
        /// the ride's crash body is running (ragdoll / get-up animation): Game.getup_anim != null
        bool getting_up => false;
    }
}
