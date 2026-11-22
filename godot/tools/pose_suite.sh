#!/usr/bin/env bash
# tools/pose_suite.sh <tag> [ENV=val ...]: runs the rider-pose scenarios with BMX_POSE_PROBE at 60 fps, two at a time,
# writes $TEMP/ps_<tag>_<scenario>.log and prints the last POSEPROBE lines of each
TAG=$1; shift
GD="$(cd "$(dirname "$0")/.." && pwd)"
G="/c/Users/Luka/Godot/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
PG="BMX_LEVEL=playground BMX_PG_PILOT=lane BMX_PG_PILOT_AUTO=0"
run() {  # name secs env...
  local name=$1 secs=$2; shift 2
  (cd "$GD" && env BMX_MIN=1 BMX_FPS=60 BMX_POSE_PROBE=1 "$@" $XENV "$G" --path . -- --ride --autotest=$secs > "$TEMP/ps_${TAG}_$name.log" 2>&1)
}
XENV="$*"
run rocks 26 $PG BMX_PG_AT=rocks BMX_PG_PILOT_KMH=30 BMX_PG_PILOT_PUMP=0 &
run tables 30 $PG BMX_PG_AT=tables BMX_PG_PILOT_KMH=33 &
wait
run drops 30 $PG BMX_PG_AT=drops BMX_PG_PILOT_KMH=28 &
run bumps 26 $PG BMX_PG_AT=bumps BMX_PG_PILOT_KMH=30 BMX_PG_PILOT_PUMP=0 &
wait
run swaps 22 BMX_SEED=4242 BMX_STRAIGHT=1 BMX_FLIPFLOP=2.4 &
wait
for n in rocks tables drops bumps swaps; do
  f="$TEMP/ps_${TAG}_$n.log"
  echo "== $n $(grep -c 'SCRIPT ERROR' "$f") script errors; $(grep 'AUTOTEST frames' "$f" | sed 's/AUTOTEST //')"
  grep POSEPROBE "$f" | tail -2
done
