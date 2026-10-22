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
| `actors/keeper/keeper.gd` | the node: solves a pose and draws it |
| `actors/keeper/keeper_gear_meshes.gd` | each gear piece's mesh, built inside its save box |
| `actors/keeper/keeper_gear_view.gd`, `keeper_box_view.gd` | the gear drawn on the bones and painted from the team kit; the boxes drawn for debugging |
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

## Seeing him

`.claude/hooks/render-keeper.sh` renders every stance from the front, side,
three-quarter and the shooter's spot on the dot line to `.preview/keeper/`
(`tools/keeper_capture.gd`), with the save boxes overlaid unless
`KEEPER_CAPTURE_BOXES=0`; a one-sided stance renders once per side
(`kick_glove`, `kick_blocker`), and the RVH is drawn against its post
(`KeeperGear.post_contact` on the post's inner face, on the goal line) with a
fifth view from a sharp angle on that side. `tests/unit/keeper/
test_keeper_body.gd` holds the proportions, the bones' lengths, the arms
reaching their hands and going into their gloves from the wrist, the gear on the ice and inside the rule book, the rigid
stick, the packed layout, the ice sealed in the butterfly, the extension and
the kick, and the post sealed in the RVH; `test_keeper_coverage.gd` snapshots
each stance's coverage straight on and from the dot line.

He is authored left-catching; a right-catcher's mirror is not built yet.
