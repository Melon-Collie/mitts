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
| `actors/keeper/keeper_gear_view.gd`, `keeper_box_view.gd` | the gear drawn on the bones; the boxes drawn for debugging |
| `actors/keeper/keeper_knee_break.gd` | the break above each knee, lofted between the knee stack and the thigh rise |

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
  the paddle from there and the arm reaches it. Placing the hand first fights a
  rigid stick.

The thigh rise is the pad carried on past the knee, and it is stiff: it rides
the shin and bends back onto the thigh only at the break above the knee, by at
most `PAD_BREAK_MAX_RAD` and only as far as the shin stands up. Upright, it
leans on the thigh; in the butterfly it lies flat on the ice with the pad, and
the two rises meet under him to close the five-hole. Never hang it on the thigh:
a butterfly would stand it up off the ice. The break itself is drawn as a loft
between the knee stack's and the rise's sections (`KeeperKneeBreak`); it is not
a save surface.

## Seeing him

`.claude/hooks/render-keeper.sh` renders every stance from the front, side and
three-quarter to `.preview/keeper/` (`tools/keeper_capture.gd`), with the save
boxes overlaid unless `KEEPER_CAPTURE_BOXES=0`. `tests/unit/keeper/
test_keeper_body.gd` holds the proportions, the bones' lengths, the gear on the
ice and inside the rule book, the rigid stick, the packed layout and the sealed
butterfly; `test_keeper_coverage.gd` snapshots each stance's coverage straight
on and from the dot line.

He is authored left-catching; a right-catcher's mirror is not built yet.
