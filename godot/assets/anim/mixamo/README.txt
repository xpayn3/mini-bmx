Animation clips for the rider (RiderAnim, scripts/rider/rider_anim.gd).

Put Mixamo downloads here: mixamo.com -> pick an animation -> Download -> Format "FBX Binary (.fbx)",
Skin "Without Skin" (smaller; "With Skin" works too), 30 fps. Any character works, the rider keeps its own
proportions. A clip with "idle" in its file name is the one the menus come back to between the others.

The menus' standing rider (garage rider room KIT tab, ride setup CHARACTER step) plays them in turn.
Empty folder = the old procedural standing pose. (Standing clips only: the menu rider has no chair.)

Other folders:
  ../getup/  get-up clips after a light crash (ClipGetUp). Any lying start works: face down, on the back,
             on a side - the one whose first frame lies most like the crashed body is picked.
  ../dizzy/  one standing loop played after getting up, until the player presses hop.
