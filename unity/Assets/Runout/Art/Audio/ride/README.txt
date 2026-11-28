Recorded ride layers (scripts/game/ride_layers.gd). Make a folder with the layer's name here and drop
.ogg / .wav files into it (any names; several = picked at random). Empty / missing folder = silent.

LOOPS (play continuously, volume driven by the ride; record 5-20 s that loop cleanly)
  roll_ground   tyre rolling on plain ground / grass        (speed)
  roll_trail    tyre rolling on packed trail dirt           (speed)
  roll_water    riding through water                        (speed)
  roll_sand     tyre on sand / loose dust                   (speed)
  rattle        chain slap / frame rattle                   (how hard the wheels are shaken)
  breath_calm   slow nose breathing                         (heart rate low, coasting)
  breath_work   steady mouth breathing                      (pedalling)
  breath_hard   gasping                                     (sprinting, tired, after a crash)
  ambience      the place: birds, wind in trees             (always, a bit lower at speed)

ONE-SHOTS (short single sounds; a few takes each)
  whoosh        air past a close tree / rock / post (3D, at the object)
  stones        a stone hitting the frame / rim (3D)
  susp_compress fork / shock taking a quick hit (3D)
  bottom_out    fork / shock bottoming out, a clunk (3D)
  heartbeat     ONE beat (lub-dub), fired at the rider's heart rate when tired / hurt / crashed
  breath_exhale a breath let out after a jump or a sprint
  grunt_hop     effort of a hop / pop
  grunt_land    a hard landing
  grunt_crash   crashing ("oof")
