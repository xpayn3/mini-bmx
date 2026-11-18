"""Export a second bike from the same BMX hip, sized as a regular downhill
bike, to assets/dh.glb. Same parts, node split and materials as bmx.glb
(see export_bmx.py) -- only the sizing changes. The numbers are the asset's
own DH preset (DH_S3 + its PRESET_KIND "dh" extras in make_hda.py):

  29 x 2.5 front / 27.5 rear (mullet), 30 mm rims
  HA 62.8, SA 76.8, reach 446, stack 632, CS 443, BB drop 25,
  head tube 105, seat tube 400, fork offset 58, 110 / 148 hubs,
  800 x 30 riser bar (7 back, 5 up), 50 mm stem, 165 mm cranks

The BMX-only parts are switched off (pegs, bar crossbar and pad, U-fork,
topload stem). It stays rigid -- no suspension -- so the exporter's part
classification still holds.

Run with Houdini 21 hython:
  & "C:\\Program Files\\Side Effects Software\\Houdini 21.0.440\\bin\\hython.exe" tools\\export_dh.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export_bmx

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "dh.glb")

DH = dict(
    # wheels: 29 x 2.5 DH front, 27.5 rear, radius from the tyre
    tire_size=14, tire_bsd=622.0, tire_auto_r=1, rear_rim=1,
    rim_inner_size=8,  # 30 mm internal
    rim_depth=24.0, rim_bed=36.0, rim_inner=30.0, rim_bead_h=5.0,
    rim_hook=0.0, rim_seat=3.5, rim_well=4.5, rim_well_w=17.0,
    rim_wide=36.5, rim_wide_at=8.0, rim_nose=8.0,
    hub_std_f=0, fork_sp=110.0, hub_std_r=0, rear_sp=148.0,
    # frame geometry
    head_angle=62.8, seat_angle=76.8, reach=446.0, stack=632.0,
    cs_len=443.0, bb_drop=25.0, ht_len=105.0, st_len=400.0, rake=58.0,
    seatpost=20.0,  # slammed, as DH riders run it (the rider stands above and behind it)
    # DH-sized tubes (straight ZS56 head tube)
    r_tt=19.0, r_dt=24.0, r_st=17.5, r_ht=31.0, r_ht_bot=31.0,
    r_stays=14.0, r_fork=19.0,
    # cockpit: Renthal Fatbar 35 800 x 30 style, 50 mm stem
    bar_type=2, bar_w_size=21, bar_w=800.0, bar_w_mode=1,
    bar_rise_size=13, bar_rise=30.0, bar_bsweep=7.0, bar_usweep=5.0,
    bar_clamp_w=106.0, bar_rise_len=55.0, bar_bend_r=45.0, bar_bend_r2=70.0,
    stem_len_size=4, stem_len=50.0, stem_angle=0.0,
    # drivetrain
    crank_len_size=5, crank_len=165.0,
    # strip the BMX-only parts: pegs, bar crossbar + pad, U-fork, topload stem
    do_pegs=0, do_crossbar=0, do_bar_pad=0, fork_u=0, stem_top=0,
)


def setup(node):
    missing = [k for k in DH if node.parm(k) is None]
    if missing:
        raise RuntimeError("bmx_skeleton has no parm(s): %s" % missing)
    # most sizing parms are preset-driven expressions (chs("preset") ...):
    # drop the expression, or set() is ignored
    for k, v in DH.items():
        p = node.parm(k)
        p.deleteAllKeyframes()
        p.set(v)
        if abs(p.eval() - v) > 1e-6:
            raise RuntimeError("%s did not take %s (reads %s)" % (k, v, p.eval()))


if __name__ == "__main__":
    export_bmx.main(setup, OUT, root="dh")
