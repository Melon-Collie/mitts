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
| `keeper_poses.gd` | the taught stances, each written as where the body goes; the low ready among them, the ready stance sat down into a deep A for a shot he may not have time to read |
| `keeper_coverage.gd` | how much of the mouth his body covers as the puck sees it |
| `keeper_seams.gd` | the holes a flat puck fits through in the shape he shows a shot straight on, inside his outline |
| `keeper_footwork.gd` | his skates moving him, on GoaliePushRules' kinematics at each move's top speed: the T-push (push off the planted trail skate up to the speed that carries him the rest of the way in `CLOSE_S`, glide on the lead, `push_time`), straight to its spot up to 45° off his line, square to the shooter; across his line the shuffle (square, in strokes, the trail skate holding its place as he passes over it); in and out the C-cuts (the skates taking turns to carve a C, heel out); the edge stop onto the spot that ends each; and the ready stance they bend |
| `keeper_glide.gd` | skating to a spot that moves: driven by velocity, never stopped between spots, read against the spot's own motion; a gap stroked for at the speed that closes it in `CLOSE_S`, then glided on, the edges digging only when the glide would carry him past, stopped exactly on one that stops; the legs stroking only while he gains speed (the trail skate holding its place on the ice, then sliding back in along it; the T-push's form past a shuffle's speed; C-cuts in depth), gliding in the stance once matched, the lead edge dug as he slows |
| `keeper_low_ready.gd` | the low ready laid over his stance on his feet: sunk into it while set and asked, out of it as any move starts, the skates going out first and the knees after; the share of a drop's time the fall from it takes (`fall_share`, the root of the knees' fall to the ice) |
| `keeper_drop.gd` | his butterfly drop, rise and recovery: how far down he is (a fall down, a push up, from wherever he is), and the pose that far between the ready stance (or the stance he dropped from, `drop_from`) and the butterfly; the recovery bringing the leg away from where he is going up first, so he stands with the skate that pushes him there loaded |
| `keeper_slide.gd` | his butterfly slide, from the butterfly or from his feet (the lead knee dropping to the half butterfly as the push starts, the push skate never leaving where it stood): the push leg's knee up off the ice to about 45° and its skate catching the ice out wide (`KeeperPoses.butterfly_push`), driving him off it while the lead pad stays down, folding back to seal as the pads slide; the lead skate's edge stopping him on his spot; to a spot off his line, turned as he loads until his lead side faces it, and `post_spot`, the spot that lands the lead pad's end on a post; and the reach and time that gives the brain |
| `keeper_post.gd` | his RVH on a post: dropping into it from his feet on the overlap (the post knee falling, the off skate sliding out wide on its edge; from a turn, swung square at his pivot's rate as it falls, `drop_in_s`) and rising back out, coming up into it from the butterfly after a slide and folding back; `overlap_spot` and `seal_spot`, where he is on the post standing (his pad's outside on the post, `KeeperGear.post_contact`, not the stick's shaft held out wider) and sealed; `overlap_facing`, the turn on the post that puts a puck dead ahead of him |
| `keeper_play_read.gd` | what he sees of the play before a shot: the puck read his leg read late and carried on along the motion he read it with (the carrier's body when carried), so a change of direction beats him by his read; a carried puck read where it is on average about its carrier (its offset followed over `HANDLE_S`), so a stickhandle does not drive his feet; a puck he sees loose read to the first opposing stick its line reaches before it stops (`read_pass`, `meet`), until he sees it caught; a wind-up (the opposing carrier holding the puck on his blade for a shot) seen as late, and how long he has watched it, which primes the save past `PRIME_S`; and the receivers a pass could reach, through lanes no defender's stick reaches |
| `keeper_positioning.gd` | the first brain, from the puck as he reads it: where he wants to be by zone (beyond the blue line, in the zone, at a sharp angle below the dots, below the goal line), each held a margin past where it took him in, set on the motor as its goal at the planner's rate with its own motion; in the zone his depth answering the puck's motion from his own skating (`depth_for`: backed in against a puck coming at him, deeper against one swinging across him, and against a pass across to an open receiver no further out than the push he has time for sets him on its angle, `pass_depth`); a shot he sees wound up he is set for at depth, not backing in for the shooter's approach; a pass he reads skated to where its stick meets it, stopped on the one-timer's angle rather than following the puck across; sunk into the low ready once a shot (a hard wrister from a carrier of theirs, or from a pass's meeting stick once it gets there) could reach him before his legs and his drop from the ready stance could answer it, since the low ready covers more of the net than the butterfly from anywhere in front of him; a carrier driving at a post from wide of it raced there only once at a sharp angle or in tight, a stick's length from the post (`_race_to_post`): until then the angle line covers the shot he can still take, and going for the post sooner gives the rest of the net to a feint; on the post he drops into the RVH as the drop-in only just beats the puck, off it he takes his fastest way in (the slide across), and he holds the seal while the puck still heads there |
| `keeper_motor.gd` | his moves strung together: where he is, his turn and his rest (feet, down, post), each move asked for in order and started from where the last came to rest; the pivot on his feet; footwork in his turned frame; or given where to be (`go_to`, `seal`), making each time he comes to rest the first move of the route there, a new spot or facing taken on by a pivot or footwork under way; footwork toward a goal turning his trunk to its facing as he goes (`lead`), his skates catching up once he is set, and chaining into the next footwork as soon as the push leg is back under him; a goal on his feet that moves, or within `KeeperRoute.GLIDE_REACH_M`, or asked to be skated to (`go_to`'s `skate`), skated to by the glide and held as it moves (`go_to`'s velocity), stopped for where he is before a goal off his feet; a low save cutting any of it; sunk into the low ready when set and asked (`low_ready`), a drop or a save from it the shorter fall |
| `keeper_route.gd` | where he is asked to be (on his feet at a spot and facing, down at a spot, sealed on a post), and the fastest way there from where he is and his rest: its first move and the whole way's time, from the movers' own models, each move's settle included (none after a glide: nothing waits for its legs); a spot on his feet within `GLIDE_REACH_M` glided to (a T-push's time, `KeeperFootwork.push_time`, beside the turn), and a way's second leg within it too when the goal is on his feet; past it footwork's moves, the shuffle where it is no slower than the T-push, a turn before the feet, a spot steeper than a diagonal in depth and across or the steepest diagonal then depth, a slide only within `KeeperSlide.MAX_OFF_LINE_RAD` of his line; the RVH dropped into straight from where he stands when that is the post's overlap at his turn (`ON_POST_M`), as at a sharp angle, or skated onto that overlap still turned first; `time_to_seal`, a way's time into the RVH whatever goal he is given, for the brain's race to a post |
| `keeper_shot_read.gd` | what he reads of a shot: nothing until he has watched the puck's own flight for his leg read, then its flight carried on under gravity; the arm read later; a tip restarts it; the flight as it left the stick (`rewind`), for a shot that beat his read |
| `keeper_save.gd` | which save he makes (a low half with a hand half, each candidate posed and the flight tested against its own gear, least committed first: the first that covers his read's band in time, else the first that covers the believed line in time, else the soonest; a save holds only if what comes off the gear it meets stays out), and the hand laid over whatever pose the motor gives him at its tier speed; the glove sent onto a puck to cover it (`cover`), without a read, the trunk folding after it |
| `keeper_cover.gd` | covering a loose puck he can reach: whether one slowing on the ice will still be under his glove when the glove can land there (from his feet once his drop lands, down at once, no sooner than the glove gets there) and slow enough for it to stop it; where the hand goes so the glove lies flat on top of it, and how far he leans on over his pads to get it there (`KeeperPoses.cover_lean`, no further than it takes) |
| `keeper_save_move.gd` | a low save's body: cut in from whatever pose he is in, into the save's stance in the drop's time, held, gathered into the stance he rests in, the speed it caught him at carried on |
| `controllers/keeper_controller.gd` | him in a match, in the old goalie's place (below) |
| `actors/keeper/keeper.gd` | the node: solves a pose on the tick, draws it at render rate when it moved |
| `actors/keeper/keeper_gear_meshes.gd` | each gear piece's mesh, built inside its save box |
| `actors/keeper/keeper_gear_view.gd`, `keeper_box_view.gd` | the gear drawn on the bones and painted from the team kit; the boxes drawn for debugging |
| `actors/keeper/keeper_body_rig.gd` | the gear drawn as one skinned mesh, a bone per piece posed on its save box: the plain slots one surface (BodyZonePaint), each kit-shader material one more, its pieces' box-frame places in CUSTOM0/1 since skinning moves VERTEX |
| `actors/keeper/keeper_jersey_decal.gd`, `Assets/Shaders/keeper_jersey.gdshader` | the jersey's crest and lettering, and the shader painting the kit onto the jersey, sleeves and pants (whose stripes run down the side, as the skaters' do) |
| `actors/keeper/keeper_knee_break.gd` | the break above each knee, lofted between the knee stack and the thigh rise |
| `actors/keeper/keeper_jersey_tail.gd` | the jersey's untucked tail, all the way round: cloth (`HemFlaps`, the skater's solver), a flap down each column, skinned onto the body rig from the protector's own hem and shaded on from its facets so the two read as one jersey; its rest the cloth settled on him standing ready |
| `actors/keeper/keeper_tail_colliders.gd` | what the tail drapes over: the pants and thigh guards as their rounded sections |

## In a match

On this branch every match spawns him (`ActorSpawner` makes a `KeeperController`
for each net), offline and online. The old `Goalie` node stays as his shell, since
the puck, the skaters, the bots and the game all address it: its own meshes are
hidden, its colliders off and nothing of it processed (its merged-body rig and
ice effects read parts he now places), a `Keeper` child draws him, the node is placed on
him every tick, and one box per piece of his gear (`KeeperGear.box`) is seated
under the old part body that names its material for the puck
(`Goalie.set_stand_in`, `add_save_box`, `seat_save_box`). Each part's first box
also places that part body, so the old getters (glove position for the catch
pin, the pads and hands the bots read through `fill_state`) read his gear. The
controller extends `GoalieController`, overriding the tick, the reset, the
stance the bots read and the puck handlers: a release read and saved (below), a
tip read again, a contact only timed, a glove catch held and covered for the
whistle, and a loose puck he can reach covered (below); where no whistle
comes (`GameRules.whistles_a_cover`, Off only) he sets it down out from his
glove side and sweeps it on toward that corner, out of his reach.

He plays on the host only. His pose goes on the wire with his root
(`fill_state`, `KeeperPoseCodec`: every target his skeleton solves from), so a
client buffers the snapshots and draws him at the interpolated past as it does
the old goalie (`GoalieController._interpolate_and_apply`), root and pose
blended between them (`KeeperPose.blend`), his skeleton solved and his save
boxes seated on it: its puck prediction stops against the gear the host saves
with, to about a centimetre. A replay (the goal cinematic, the post-game reel,
a replay file) poses him the same way (`apply_replay_state`). The shot
release's rewind of the goalie moves his root only, not his pose.

## Saves

A shot is read from its release, the puck's own flight only: no aim before it
(the shooter's drawn body shows that a shot is wound up, not yet where it
goes). His legs answer after the tier's leg read and his hands after the arm
read, the old goalie's tiered delays and speeds (`GoalieSkillProfile`), and
both after its primed read for a release he watched wound up for
`KeeperPlayRead.PRIME_S` (the quiet-eye read: the save programmed during the
look); a tip is read cold. He is beaten by a shot that arrives before a limb
can, never by a draw. Once his legs have
read a shot that would go in, the save is chosen by his shape: every
candidate a low half (none, the kick, the half butterfly, the butterfly, the
extension, to the puck's side) with a hand half (none, the blade along the
ice, the glove, the blocker), its hand aimed at the point of the flight the arm
reaches with the most time to spare, posed, and the flight tested against
that pose's gear boxes. His read is good to `KeeperSave.READ_BAND_RAD` of the
flight's direction, so where it crosses him is known to a band that widens with
the way it still has to come; he makes the least committed save that covers
the whole band in time, else the least committed that covers the line he
believes in time, else the soonest. So a low shot at the five-hole he has time
for takes him down (the blade alone leaves the band over it open), and one he
has none for is left to the blade. A save holds only if what comes off the gear
it meets (`GoalieSaveRules.resolve_contact`, the puck's own contact) is caught,
smothered, goes away from the net or meets more of him before the mouth: a puck
that clips the outside of a pad glances on in. Height is no rule: a hand goes only where its gear stays above the
ice, and the blade only for a puck low enough for it. A low save cuts whatever
move is under way (`KeeperMotor.save`); the hand rides any pose. The save goes on
until it is there, and he lets it go his leg read after it is there and the
shot is over — off him, past the line, stopped, off the iron or boards (a tip
starts a new read, a pick-up ends it at once) — so a save made too late is
still seen made; then the hand comes back and the motor rests him where the
save left him for the brain to bring back up. A shot over before his legs
have read it at all (from in tight, in or off him) he answers once they have:
the least committed save that would have covered the flight he saw leave the
stick, however late (`KeeperSave.choose`, not `timed`), made and held the
same way. The brain rests while
a save is under way (a hand save sets him where he stands, the hand aimed from
there); since his read of the play lags it by his leg read, a shot's flight
reaches the brain no sooner than the save does.
A loose puck he can reach, with no shot being read, he covers
(`KeeperCover`, `KeeperController._cover_the_puck`): one slowing on the ice
that will still be under his glove when the glove can land there, slow enough
by then for the glove to stop it. From his feet he drops into the butterfly
(the motor's low save, cutting any move), and the glove goes flat onto it,
palm down and fingers ahead, his trunk folding on over the pads and turning
until the puck is ahead of his glove shoulder, as far as it takes. The glove
follows the puck as it slides. Until the glove is on it the puck is live: a
puck poked out of his reach ends the cover and he gets back up. Secured, it is
dead under the glove and covered for the whistle. So a rebound dying at his
feet, a dribble at the crease or a puck caught behind his stick or between his
pads is smothered rather than dropped on and popped up from.

`test_keeper_save.gd` (the five-hole down with time and left to the blade
without, a save holding or not by its rebound), `test_keeper_cover.gd` (a
puck at his feet coverable from his feet once his drop lands and sooner down,
one out of reach or too fast not, a sliding one covered where it will be, and
the cover played out unbroken with the glove ending flat on it),
`test_keeper_save_move.gd`,
and the match through the
puck's own contact test in `test_keeper_controller.gd`.
`tests/unit/controllers/test_keeper_controller.gd` holds the swap, a catch
played out, a shot in before his read answered late and carried into, a puck at his feet covered or, poked away first, escaping, and a
client posed from his state through the wire with every save box where the
host's is. `test_keeper_pose_codec.gd` holds the pose on the wire: every
stance and every tick of a run of his moves solving to the same gear, the
flags, and a blend that is each snapshot at its ends.

## One body, solved once, read three ways

The skeleton is pure and the gear boxes hang off it, so the save geometry, the
drawn gear and (later) the planner's coverage all come from the same solve —
there is no second copy of his shape to drift. A mesh is built inside the box it
draws on: what he looks like is what he saves with. The skeleton is solved on
the tick wherever its boxes are gameplay, which is why it is not the skater's
render-rate rig. The gear is drawn from that solve at render rate
(`Keeper._process`), once a pose has moved a bone and only while he is on
camera (`SkaterCameraCull`); the boxes are reseated only when a pose moved one.
The jersey's tail is cloth and steps every frame against the acceleration his
controller measures off his motion (`Keeper.acceleration`), on camera or not,
writing its bones only when drawn; it runs in C++ where the extension is built.
A tool that poses him shot by shot steps it itself (`Keeper.step_cloth`).

## Poses are where the body goes, not joint angles

A stance names the ice the skates stand on, where the knees land, where the
hands are held and where the blade lies; the joints follow. Two things decide
more than they look like:

- **A kneeling joint keeps its height.** A pinned knee or ankle is placed at its
  target's height and turns only in plan (`KeeperSkeleton.toward_at_height`), so
  a knee on the ice stays on the ice wherever the hips go.
- **In reach, the stick decides the blocker hand.** The blade lies flat, the
  lie fixes the paddle's angle to it in its own plane (which leans the paddle
  about 27° toward the blocker side), and `stick_tilt` tips it back toward him.
  The grip is up the paddle from there, the gloved fist holds it, and the arm
  reaches the wrist on the back of the fist (`KeeperAnatomy.BLOCKER_WRIST`),
  where the glove's cuff on the forearm meets it. Every taught stance is laid
  in reach.
- **Past reach, the hand brings the stick.** The stick never leaves the fist:
  the arm reaches as far as it goes toward the grip, and the stick, still
  rigid, pivots on its heel to the fist, sliding through it along the shaft
  (`GRIP_LOWEST_M` to `GRIP_HIGHEST_M`), its blade turned to lie flat under the
  new lean. A hand nearer the heel than the paddle's top slides the heel out
  along the ice; the blade comes off the ice only for a hand past the butt or
  under a paddle stood too upright for it to lie flat, and then rests on its
  toe. The glove's hand likewise goes no further than its arm reaches.
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
(`KeeperGear.post_pad_contact`, the post pad's toe, on the post's inner face,
on the goal line) with one
more view from a sharp angle on that side. `tests/unit/keeper/
test_keeper_body.gd` holds the proportions, the bones' lengths, the arms
reaching their hands and going into their gloves from the wrist, the gear on the ice and inside the rule book, no skate through its boot, the rigid
stick, the packed layout, the ice sealed in the butterfly, the extension and
the kick, the post sealed in the RVH, and its post pad's toe what meets the
iron (nothing of him past it but that leg's skate, turned out beside the post
under the toe); `test_keeper_coverage.gd` snapshots
each stance's coverage straight on and from the dot line, and
`test_keeper_seams.gd` holds every hole a puck fits through to its stance's
intended windows (the five-holes the ready stance, the low ready, the half
butterflies, the extensions and the kicks open, the ice under the low ready's
blocker pad and the RVH's off pad).
`test_keeper_footwork.gd` holds the T-push, the shuffle and the C-cuts: set on
his spot in `KeeperFootwork.push_time` (the T-push, glided on before its stop
however short) or `GoaliePushRules.time_to_set` (the strokes), a diagonal T-push straight there and
one steeper than it goes to where its spot falls on his line, the T-push skate
on its plant until the leg is out, a stroke's skate holding its place and never sliding back, a
C-cut's skates taking turns with their heels out, the shuffle square, a spot
on the other axis waiting until he is set, skates on and gear out of the ice
every tick, nothing jumping a tick, a slower stop showing less, and the ready
stance once settled. `test_keeper_drop.gd` holds the drop, rise and recovery:
their times, the ready stance to the butterfly, the drop a fall, a change of
mind going from where he is, the recovery's far leg up first and its skate
holding its place, and every tick out of the ice, on the stick and without a
jump. `test_keeper_low_ready.gd` holds the low ready: sunk into its own
pose when set and asked, out of it as a move starts, a drop and a low save
from it the shorter fall by the root of the knees' heights (a kick, a push,
not), the save pricing it, and every tick of each out of the ice, on the
stick and without a jump. `test_keeper_slide.gd` holds the slide (short ones too, whose stop comes as the push leg folds): at rest on the spot in
`KeeperSlide.time_to`, or at its reach past it, from the butterfly and from his feet (where the push skate holds from the drop's first frame), friction then the lead edge
slowing him once pushed and the stop beating a coast, the push skate holding
its place, the lead pad down on the ice the whole way and both through the
stop, butterfly to butterfly, a spot off his line turning him to it as he loads, a
slide to a post landing the pad's end on it angled back and opened toward
that side, and every tick out of the ice, on the stick and without a jump.
`test_keeper_post.gd` holds the RVH's ways in and out: each in its time, from
and to the overlap and the butterfly, sealed with the pad's end on the post,
the puck dead ahead of him turned on the post (`overlap_facing`),
the off skate on the ice through the drop-in and the rise, and every tick out
of the ice, on the stick and without a jump. `test_keeper_motor.gd` holds the
moves strung together: whole sequences across the crease and back with nothing
jumping at a hand-off, the pivot at its rate onto its facing, footwork in his
turned frame, and a move from the wrong rest refused. `test_keeper_route.gd`
holds him given where to be: from every rest to every kind of goal, there,
every tick unbroken, no move refused and in the time the route planned (the
brain will read it); a near spot skated to and a far one pushed for, past the
glide's reach a turn first, a recovery toward a spot on his feet, a drop-in
from the overlap, and straight in from it turned to a sharp angle, or
skated onto it still turned from short of it; a spot or facing moved under a move taken on by it; and the
last order winning. `test_keeper_glide.gd` holds the glide: a moving spot
caught and skated with, never stopped for, gliding once matched; a still one
stroked for, glided on and stopped on, no further, in the glide's time; one that turns back followed
unbroken. `test_keeper_positioning.gd` holds a carrier cutting across the slot
tracked on the angle line, his depth against the puck's motion (the top of the
crease still or slow, a rush backing him in no further than the floor and on it
in time, a swing across him no faster than his shuffle), a rush straight in
skated back as it comes, and an open receiver across the slot holding him as
deep as the push to its angle he has time for, a shot wound up on the rush
met set at the top, a pass he reads played from its stick's angle, turned
to it, in front of the net for a pass out from behind it, and the low ready
asked for once a shot of theirs could beat his reaction, held a margin past
it, a shorter reach once primed, none for a puck of ours or on the post, and
a pass by when its stick can shoot it; a carrier driving down the wing at a
post, him on his feet until it is in tight, the ice inside the post covered
as the puck gets there and then sealed; the same drive feinted from range
finding him still on the angle line, and cut back out bringing him back up.
`test_keeper_play_read.gd` holds the read: a puck on its line read where it
is, a change of direction read after his read (a slower tier later), a
wind-up seen his read late and priming the save once watched long enough, the
receivers a pass can reach, a stickhandle read where the puck is on average
and the carrier's skating as it is, and a pass read to the stick that meets
it once seen and until seen caught, none for a line no stick reaches or a
puck that stops short.
`test_keeper_body.gd` also holds a grip past reach in every direction, both
catching hands: the fist on the stick, the arm no longer than an arm, the grip
on the shaft, the lie, and the blade flat on the ice unless it cannot be.
`test_keeper_positioning.gd` holds the first brain: the spot and facing in
each zone (on the angle line at the top of the crease, the middle of it out of
the zone, the near post turned at a sharp angle with his edge on it and the
near post sealed along the ice as the puck sees it, the RVH on
the near post below the line), behind the net the post held until the puck
will beat him across by his own time to the other, a boundary crossed back and
forth holding him in one zone, and a puck carried round the zone tracked every
tick unbroken to rest where it stops.
`tests/instruments/ai/test_goalie_scoreboard.gd` scores him against scripted
shooters beside the old goalie (`test_report_the_keeper`, his numbers in
`data/keeper_scoreboard.txt`), through the harness the old goalie's
instruments use: `KeeperController` keeps the old goalie's getters true for it
(his stance in the old state machine, his lateral x and challenge radius). The
shooter is a skater both goalies see, and each staging looks afresh, since a
goalie stepped by hand never advances the frame his view is cached on.
`.claude/hooks/render-keeper-strip.sh` draws a move a few ticks a frame from
the shooter's side, behind and high in front (`tools/keeper_strip.gd`), the
stick swept out of reach (`stick_reach`), and the first brain tracking a puck
round the zone (`track`).

He is authored left-catching. A right-catcher (`KeeperSkeleton.mirrored`) is
that body reflected across his centre line once solved: each bone frame is
reflected on both sides, so every save box is the reflected box, and the stick's
boxes are turned to the same frame. A stance's `side` stays his own (the glove
side is his right); `KeeperSkeleton.world_side` turns it into keeper space's,
which is what `KeeperGear.post_contact` and `post_pad_contact` take. The drawn gear, which is not
symmetric, is turned over on each piece's own x (`KeeperGearView`), and the
jersey's lettering and crest read the other way across so they still read
forwards. `KEEPER_CAPTURE_RIGHT=1` renders him.
