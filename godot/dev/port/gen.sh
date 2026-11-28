#!/usr/bin/env bash
# Regenerate the C# ride from bike_physics.gd and build the engine-free core alone (no Godot reference).
# bash godot/dev/port/gen.sh [errors]   (from anywhere)
set -u
cd "$(dirname "$0")/../.."
MANUAL="_crash_step,_crash_sim_step,_e_tick,_jolt_probe,_prof,_init,setup,_sus_cache,is_sane"
OUT="${GEN_OUT:-sim/BikeSim.gen.cs}"
python dev/port/gd2cs.py scripts/bike/bike_physics.gd "$OUT" --manual "$MANUAL" --members dev/port/out/members.json | tail -3
cd dev/port/simcheck
LOG=$(dotnet build 2>&1)
N=$(echo "$LOG" | grep -E " error " | sort -u | wc -l)
echo "SIMCHECK errors=$N"
if [ "${1:-}" = "errors" ]; then
	echo "$LOG" | grep -E " error " | sort -u | sed -E 's/.*\\([A-Za-z.]+\.cs)\(([0-9]+),[0-9]+\): error (CS[0-9]+): ([^[]{0,110}).*/\1|\2|\3 \4/' \
		| sort -t'|' -k1,1 -k2,2n | head -${LIMIT:-60} | while IFS='|' read f n m; do
		src="../out/$f"; [ -f "$src" ] || src="../../../sim/$f"
		echo "$f:$n [$m]: $(sed -n "${n}p" "$src" 2>/dev/null | sed 's/^\s*//' | cut -c1-150)"
	done
fi
