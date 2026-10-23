# The keeper (the new goalie)

Scope: `Scripts/domain/keeper/` (pure) and `Scripts/actors/keeper/` (drawn).
The goalie being rebuilt from the ground up, beside the old one until it
replaces him (`docs/goalie-rebuild-plan.md`). Files are named `keeper_*` so the
shot field's `goalie_*` fingerprint never sees them while the old goalie is the
one the bots shoot at.

| File | Owns |
|---|---|
| `keeper_anatomy.gd` | his 6'4" frame from stature ratios, and gear at the NHL limits |
| `keeper_pose.gd` | a pose as targets: pelvis and trunk angles, knees, ankles, hands, the stick's blade |
| `keeper_skeleton.gd` | the bones, solved from a pose (legs and arms by two-bone IK, the stick by its lie) |
| `keeper_gear.gd` | one save box per piece of gear, on its bone; the contact test's packed layout |
| `keeper_poses.gd` | the taught stances, each written as where the body goes |
| `keeper_coverage.gd` | how much of the mouth his body covers as the puck sees it |
| `keeper_seams.gd` | the holes a flat puck fits through in the shape he shows a shot straight on, inside his outline |
| `keeper_footwork.gd` | his skates moving him, on GoaliePushRules' kinematics at each move's top speed: across his line the T-push (push off the planted trail skate, glide on the lead) and the shuffle (square, in strokes, the trail skate holding its place as he passes over it); in and out the C-cuts (the skates taking turns to carve a C, heel out); the edge stop onto the spot that ends each; and the ready stance they bend |
| `keeper_drop.gd` | his butterfly drop and rise: how far down he is (a fall down, a push up, from wherever he is), and the pose that far between the ready stance and the butterfly |
| `keeper_slide.gd` | his butterfly slide: the push leg's knee up off the ice to about 45° and its skate catching the ice out wide (`KeeperPoses.butterfly_push`), driving him off it while the lead pad stays down, folding back to seal as the pads slide; the lead skate's edge stopping him on his spot; and the reach and time that gives the brain |
| `actors/keeper/keeper.gd` | the node: solves a pose and draws it |
| `actors/keeper/keeper_gear_meshes.gd` | each gear piece's mesh, built inside its save box |
| `actors/keeper/keeper_gear_view.gd`, `keeper_box_view.gd` | the gear drawn on the bones and painted from the team kit; the boxes drawn for debugging |
| `actors/keeper/keeper_body_rig.gd` | the gear drawn as one skinned mesh, a bone per piece posed on its save box: the plain slots one surface (BodyZonePaint), each kit-shader material one more, its pieces' box-frame places in CUSTOM0/1 since skinning moves VERTEX |
| `actors/keeper/keeper_jersey_decal.gd`, `Assets/Shaders/keeper_jersey.gdshader` | the jersey's crest and lettering, and the shader painting the kit onto the jersey, sleeves and pants (whose stripes run down the side, as the skaters' do) |
| `actors/keeper/keeper_knee_break.gd` | the break above each knee, lofted between the knee stack and the thigh rise |
| `actors/keeper/keeper_jersey_tail.gd` | the jersey's untucked tail, all the way round: hung from the protector's own hem edge and shaded on from its facets so the two read as one jersey, rested on the pants and thighs |

## One body, solved once, read three ways

The skeleton is pure and the gear boxes hang off it, so the save geometry, the
drawn gear and (later) the planner's coverage all come from the same solve —
there is no second copy of his shape to drift. A mesh is built inside the box it
draws on: what he looks like is what he saves with. The skeleton is solved on
the tick wherever its boxes are gameplay, which is why it is not the skater's
render-rate rig.

## Poses are where the body goes, not joint angles

A stance names the ice the skates stand on, where the knees land, where the
hands are held and where the blade lies; the joints follow. Two things decide
more than they look like:

- **A kneeling joint keeps its height.** A pinned knee or ankle is placed at its
  target's height and turns only in plan (`KeeperSkeleton.toward_at_height`), so
  a knee on the ice stays on the ice wherever the hips go.
- **The stick decides the blocker hand.** The blade lies flat, the lie fixes the
  paddle's angle to it in its own plane (which leans the paddle about 27° toward
  the blocker side), and `stick_tilt` tips it back toward him. The grip is up
  the paddle from there, the gloved fist holds it, and the arm reaches the
  wrist on the back of the fist (`KeeperAnatomy.BLOCKER_WRIST`), where the
  glove's cuff on the forearm meets it. A stance that holds the stick past the
  arm's reach is wrong, not the arm: the cuff has no slack to hide a gap.
  Placing the hand first fights a rigid stick.
- **The glove holds its place on the body.** It is placed in the chest's frame
  (`KeeperPose.glove_from_chest`, `KeeperPoses.GLOVE_FROM_CHEST`): just outside
  the chest's width, the elbow a little out, the same spot standing and down,
  so dropping into the butterfly carries the hand with the trunk instead of
  letting it fall and open a hole. Saves move it out from there.

The thigh rise is the pad carried on past the knee, and it is stiff: it rides
the shin and bends back onto the thigh only at the break above the knee, by at
most `PAD_BREAK_MAX_RAD` and only as far as the shin stands up. Upright, it
leans on the thigh; in the butterfly it lies flat on the ice with the pad, and
the two rises meet under him to close the five-hole. Never hang it on the thigh:
a butterfly would stand it up off the ice. The break itself is drawn as a loft
between the knee stack's and the rise's sections (`KeeperKneeBreak`); it is not
a save surface.

The pad's boot, its toe over the skate, is the pad's: a stiff section of it,
rigid on the shin (`KeeperGear._boot_box`), built turned up from the pad by
`KeeperAnatomy.PAD_TOE_ANGLE_RAD`, the ready stance's angle between shin and
skate, as a real pad is built for its keeper's stance. In the stance it lies
along the skate just off the ice; in the butterfly the foot is turned into it
by the same angle (`leg.flex`); where the foot points down under the shin (a
kick, the RVH's standing leg) the skate shows beneath it, as a real one does.
It never bends or turns on the pad, and the skate never comes up through it.

The pad's back is open, as a real one's is: its face and two side wings run
back either side of the leg, which lies in the channel between them in the
kit's socks (painted down the shin as the skaters' are), strapped across at
the ankle, calf and under the knee. The channel is lined in a shaded pad
colour, since most kits' socks are their pads' colour.

## Seeing him

`.claude/hooks/render-keeper.sh` renders every stance from the front, side,
three-quarter, the shooter's spot on the dot line and behind, plus the mouth as a
shot straight on sees him (his body grey, his seams red), to `.preview/keeper/`,
diffed against a baseline recorded with `-- --baseline`
(`tools/keeper_capture.gd`), with the save boxes overlaid unless
`KEEPER_CAPTURE_BOXES=0`; a one-sided stance renders once per side
(`kick_glove`, `kick_blocker`), and the RVH is drawn against its post
(`KeeperGear.post_contact` on the post's inner face, on the goal line) with one
more view from a sharp angle on that side. `tests/unit/keeper/
test_keeper_body.gd` holds the proportions, the bones' lengths, the arms
reaching their hands and going into their gloves from the wrist, the gear on the ice and inside the rule book, no skate through its boot, the rigid
stick, the packed layout, the ice sealed in the butterfly, the extension and
the kick, and the post sealed in the RVH; `test_keeper_coverage.gd` snapshots
each stance's coverage straight on and from the dot line, and
`test_keeper_seams.gd` holds every hole a puck fits through to its stance's
intended windows (the five-holes the ready stance, the half butterflies, the
extensions and the kicks open, the ice under the RVH's off pad).
`test_keeper_footwork.gd` holds the T-push, the shuffle and the C-cuts: set on
his spot in `GoaliePushRules.time_to_set`, the T-push skate on its plant until
the leg is out, a stroke's skate holding its place and never sliding back, a
C-cut's skates taking turns with their heels out, the shuffle square, a spot
on the other axis waiting until he is set, skates on and gear out of the ice
every tick, nothing jumping a tick, a slower stop showing less, and the ready
stance once settled. `test_keeper_drop.gd` holds the drop and rise: their
times, the ready stance to the butterfly, the drop a fall, a change of mind
going from where he is, and every tick out of the ice, on the stick and
without a jump. `test_keeper_slide.gd` holds the slide: at rest on the spot in
`KeeperSlide.time_to`, or at its reach past it, friction then the lead edge
slowing him once pushed and the stop beating a coast, the push skate holding
its place, the lead pad down on the ice the whole way and both through the
stop, butterfly to butterfly, and every tick out of the ice, on the stick
and without a jump.
`.claude/hooks/render-keeper-strip.sh` draws a move a few ticks a frame from
the shooter's side, behind and high in front (`tools/keeper_strip.gd`).

He is authored left-catching. A right-catcher (`KeeperSkeleton.mirrored`) is
that body reflected across his centre line once solved: each bone frame is
reflected on both sides, so every save box is the reflected box, and the stick's
boxes are turned to the same frame. A stance's `side` stays his own (the glove
side is his right); `KeeperSkeleton.world_side` turns it into keeper space's,
which is what `KeeperGear.post_contact` takes. The drawn gear, which is not
symmetric, is turned over on each piece's own x (`KeeperGearView`), and the
jersey's lettering and crest read the other way across so they still read
forwards. `KEEPER_CAPTURE_RIGHT=1` renders him.
