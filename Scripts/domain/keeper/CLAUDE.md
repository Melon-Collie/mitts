# The keeper (the new goalie)

Scope: `Scripts/domain/keeper/` (pure) and `Scripts/actors/keeper/` (drawn).
The goalie, rebuilt from the ground up (`docs/goalie-rebuild-plan.md`) in the
old one's place.

| File | Owns |
|---|---|
| `keeper_anatomy.gd` | his 6'4" frame from stature ratios, and gear at the NHL limits |
| `keeper_pose.gd` | a pose as targets: pelvis and trunk angles, knees, ankles, hands, the stick's blade |
| `keeper_skeleton.gd` | the bones, solved from a pose (legs and arms by two-bone IK, the stick by its lie) |
| `keeper_gear.gd` | one save box per piece of gear, on its bone, the pads settled on the ice and their toes flexed off it where a stance would sink them; the contact test's packed layout |
| `keeper_poses.gd` | the taught stances, each written as where the body goes; the low ready among them, the ready stance sat down into a deep A for a shot he may not have time to read |
| `keeper_coverage.gd` | how much of the mouth his body covers as the puck sees it |
| `keeper_seams.gd` | the holes a flat puck fits through in the shape he shows a shot straight on, inside his outline |
| `keeper_footwork.gd` | his skates moving him, on GoaliePushRules' kinematics at each move's top speed: the T-push (push off the planted trail skate up to the speed that carries him the rest of the way in `CLOSE_S`, glide on the lead, `push_time`), straight to its spot up to 45° off his line, square to the shooter; across his line the shuffle (square, in strokes, the trail skate holding its place as he passes over it); in and out the C-cuts (the skates taking turns to carve a C, heel out); the edge stop onto the spot that ends each; and the ready stance they bend |
| `keeper_glide.gd` | skating to a spot that moves: driven by velocity, never stopped between spots, read against the spot's own motion; a gap stroked for at the speed that closes it in `CLOSE_S`, no faster than the C-cuts in depth, then glided on, the edges digging only when the glide would carry him past, stopped exactly on one that stops; the legs stroking only while he gains speed (the trail skate holding its place on the ice, then sliding back in along it; the T-push's form past a shuffle's speed; C-cuts in depth), gliding in the stance once matched, the lead edge dug as he slows |
| `keeper_low_ready.gd` | the low ready laid over his stance on his feet: sunk into it while asked and set, shuffling or skating with the play no faster across his line than he shuffles (backing in at any glide), a stroke's skate carried onto its wide stance so he strokes from it (the trail skate holding the ice as he passes over it), out of it as any other move starts, as quick both ways, the skates going out first and the knees after; the share of a drop's time the fall from it takes (`fall_share`, the root of the knees' fall to the ice) |
| `keeper_drop.gd` | his butterfly drop, rise and recovery: how far down he is (a fall down, a push up, from wherever he is), and the pose that far between the ready stance (or the stance he dropped from, `drop_from`) and the butterfly; the recovery bringing the leg away from where he is going up first, so he stands with the skate that pushes him there loaded |
| `keeper_slide.gd` | his butterfly slide, from the butterfly or from his feet (the power push: out of the stance he is in, the lead knee falling to the half butterfly as the drop from it does, the shorter fall from the low ready, while the push skate drives off where it stood through the last of the fall, so he lands on the pad at the push's speed): the push leg's knee up off the ice to about 45° and its skate catching the ice out wide (`KeeperPoses.butterfly_push`), driving him off it while the lead pad stays down, folding back to seal as the pads slide; the lead skate's edge stopping him on his spot, done once stopped with the push leg folded back (`is_settled`), the lean back against the stop easing out through whatever comes next; to a spot off his line, turned as he loads until his lead side faces it, and `post_spot`, the spot that lands the lead pad's end on a post (`post_seal_spot` the place down that puts it there turned as asked); the reach and time that gives the brain; the push off the post from the RVH (`push_off`, `From.POST`): the off knee falling to the ice as the lead pad while the post leg's knee comes up off it, its boot's toe staying on the post, so the push drives him off the post itself, only ever away from it; and the rotation on his knees (`rotate_to`): loaded as for a slide on the side he turns away from, the planted push skate swivelling him round at the push's speed carried by the pads' far ends (`turn_rate`), the leg folding back down as he comes round, no quicker than the fold (`rotate_time`) |
| `keeper_post.gd` | his RVH on a post: dropping into it from his feet on the overlap (the post knee falling, the off skate sliding out wide on its edge; from a turn, swung square at his pivot's rate as it falls, `drop_in_s`) and rising back out, coming up into it from the butterfly after a slide and folding back; `overlap_spot` and `seal_spot`, where he is on the post standing (his pad's outside on the post, `KeeperGear.post_contact`, not the stick's shaft held out wider) and sealed; `overlap_facing`, the turn on the post that puts a puck dead ahead of him; `rvh_pose`, the RVH as the post holds it, for the slide's push off it |
| `keeper_play_read.gd` | what he sees of the play before a shot: the puck read his leg read late and carried on along the motion he read it with, so a change of direction beats him by his read, and the play's motion (`motion`, the carrier's body when carried, which his depth answers) and the carrier's body itself (`carrier`), read as late and carried on; a carried puck carried on along its own motion over his read as a loose one is, but no further from its carrier's body, carried on along his skating, than the carrier reaches (`CARRIER_REACH_M`, the live skater's furthest pull, `test_keeper_reads_the_carriers_reach.gd`), and whose carrier it is (`theirs`), so a release does not reach the brain before his read does; a puck he sees loose read to the first opposing stick its line reaches before it stops (`read_pass`, `meet`), until he sees it caught; a wind-up (the opposing carrier holding the puck on his blade for a shot) seen as late; how long he has held the puck on a stick of theirs in his eyes, unbroken by its getting out of his gaze (pursuing it at up to `PURSUIT_RAD_S` and holding it within the quiet eye's 3°, `LOOK_WINDOW_RAD`) or by a pass, or by its getting behind a body (`hidden`), which primes the save past `PRIME_S`; and the receivers a pass could reach, through lanes no defender's stick reaches |
| `keeper_positioning.gd` | the first brain, from the puck as he reads it: where he wants to be by zone (beyond the blue line, in the zone, at a sharp angle below the dots, below the goal line), each held a margin past where it took him in, set on the motor as its goal at the planner's rate with its own motion; in the zone his depth answering the puck's motion from his own skating (`depth_for`: backed in against a puck coming at him, a carried one of theirs as soon as its carrier could skate there from the speed he has, so one stopped in tight still holds him in, deeper against one swinging across him, and against a pass across to an open receiver no further out than the push he has time for sets him on its angle, `pass_depth`); a shot he sees wound up he is set for at depth, not backing in for the shooter's approach; a pass he reads skated to where its stick meets it, stopped on the one-timer's angle rather than following the puck across; against a carrier of theirs as against a loose puck, his angle line goes through the puck as he reads it, never the carrier's body: a puck held out to one side is the shot that can come now, and a pull across is answered once read; sunk into the low ready once a shot (a hard wrister from a carrier of theirs, or from a pass's meeting stick once it gets there) could reach him before his legs and his drop from the ready stance could answer it, since the low ready covers more of the net than the ready stance, nothing off its gear goes on in (`test_keeper_deflections.gd`) and its drop is the shorter fall; a carrier driving at a post from wide of it raced there only once at a sharp angle or in tight, a stick's length from the post (`_race_to_post`): until then the angle line covers the shot he can still take, and going for the post sooner gives the rest of the net to a feint; on the post he drops into the RVH as the drop-in only just beats the puck, off it he takes his fastest way in (the slide across), and he holds the seal while the puck still heads there; but a carrier of theirs raced so in front of the goal line he meets planted in the butterfly on that post instead (`_plant`): the near pad's end sealing the post along the ice (`KeeperSlide.post_seal_spot`), square to the carrier but turned toward the post no further than a slide back across to the far post goes, the far pad across the front of the crease where a wrap has to go round him; skated to on his feet and dropped once within half a pad's width of it; planted while the carrier stays within two stick lengths of the post (`TIGHT_M`); and a carrier of theirs in front within that of the net he plays down (`_stay_down`): dropped once he is on the spot he skates to, then pushed across at his depth onto the puck's line where the carrier will be when the push lands, a spot within half a pad's width of where he has stopped, or of the one he is still pushing for, no new push, since a push cannot be cut short; in the zone, a body on his sightline to the puck stepped round (`screen`, KeeperScreen, from the `bodies` his controller gives it) |
| `keeper_motor.gd` | his moves strung together: where he is, his turn and his rest (feet, down, post), each move asked for in order and started from where the last came to rest; the pivot on his feet; footwork in his turned frame; or given where to be (`go_to`, `seal`), making each time he comes to rest the first move of the route there, a new spot or facing taken on by a pivot or footwork under way; footwork toward a goal turning his trunk to its facing as he goes (`lead`), his skates catching up once he is set, and chaining into the next footwork as soon as the push leg is back under him; a goal on his feet that moves, or within `KeeperRoute.GLIDE_REACH_M`, or asked to be skated to (`go_to`'s `skate`), skated to by the glide and held as it moves (`go_to`'s velocity), stopped for where he is before a goal off his feet; a low save cutting any of it, a drop, a rise or the gather after the last save included, falling from as far down as he is (`fall`), but never a slide or the post; sunk into the low ready when asked and set, shuffling or skating with the play, across no faster than he shuffles and in depth at any glide (`low_ready`), a drop or a save from it the shorter fall; a goal down while he skates dropped into at once, his speed carried onto the pads (`_drop_carrying`, the low save's drop with its edges out of it); down, one push after another, the next as soon as the last has stopped and folded its leg; frozen where he is (`freeze`) while he holds the puck |
| `keeper_route.gd` | where he is asked to be (on his feet or down at a spot and facing, sealed on a post), and the fastest way there from where he is and his rest: its first move and the whole way's time, from the movers' own models, each move's settle included (none after a glide or a slide: nothing waits for its legs or the lean back against its stop); a spot on his feet within `GLIDE_REACH_M` glided to (a T-push's time, `KeeperFootwork.push_time`, at the C-cuts' speed for its share in depth, beside the turn), and a way's second leg within it too when the goal is on his feet; past it footwork's moves, the shuffle where it is no slower than the T-push, a turn before the feet, a spot steeper than a diagonal in depth and across or the steepest diagonal then depth, a slide only within `KeeperSlide.MAX_OFF_LINE_RAD` of his line; in the RVH, a spot or the other post across the crease pushed off the post for (`RVH_PUSH_OFF`), one on the post's side of him folded out for; down, a facing more than `DOWN_FACED_RAD` off taken by a rotation on his knees, or by a pivot on his feet before he drops, and a slide off his line by rotating onto it first, never turned further off the facing than a slide goes, where that beats getting up; the RVH dropped into straight from where he stands when that is the post's overlap at his turn (`ON_POST_M`), as at a sharp angle, or skated onto that overlap still turned first; `time_to_seal`, a way's time into the RVH whatever goal he is given, for the brain's race to a post |
| `keeper_shot_read.gd` | what he reads of a shot: nothing until he has watched the puck's own flight for his leg read, after the time a body hides its release from him (`hidden_s`), then its flight carried on under gravity, his legs and hands both answering it; a tip restarts it; the flight as it left the stick (`rewind`), for a shot that beat his read |
| `keeper_save.gd` | which save he makes: the one taught for where the shot passes him (below his belly button the butterfly, the half butterfly wide of a pad, the extension past it; above it the glove or the blocker on its side, the glove trapping one at the chest), each candidate posed and the flight tested against its own gear, the first in the taught order whose gear meets the flight and holds it, timing deciding only whether he gets there; a save holds only if what comes off the gear it meets stays out), a stick or blocker save made with the face turned so its rebound goes toward the near corner (`STICK_TURNS_RAD`, `BLOCKER_TURNS_RAD`, `to_corner`), and the hand laid over whatever pose the motor gives him at its tier speed, a hand still going back from the last save going on back by itself as the next goes out; the glove sent onto a puck to cover it (`cover`) and the stick thrust out along the ice to poke or clear one (`poke`, the blade turned as it goes for a clear), without a read, the trunk folding and turning after it no faster than a trunk turns; and where a shot leaves him time to skate onto its line before he sets for it (`square_up_spot`) |
| `keeper_look.gd` | his eyes on the puck: his face turned to follow it in any stance, the neck turning and the head nodding, no faster than a head turns (`TURN_RAD_S`) and no further than a neck does, then the trunk turning on the hips for a puck behind him (a shot gone by, one round the net), over the shoulder he is already turned to when it is dead behind; laid over the pose last, so through a save he watches the puck into the gear |
| `keeper_chest_trap.gd` | a shot caught on his chest: only at the logo (between where his arm pads lie on the protector, the middle of its height, on its face), and only when the nearer hand gets onto it before the foam's rebound carries it out of the glove's pocket |
| `keeper_cover.gd` | covering a loose puck he can reach: whether one lies at his feet (`at_feet`); whether one down on the ice (`on_ice`, never one in the air) and slowing on it will still be under his glove when the glove can land there (from his feet once his drop lands, down at once, no sooner than the glove gets there) and slow enough for it to stop it; where the hand goes so the glove lies flat on top of it, and how far he leans on over his pads, turned and sunk toward it, to get it there (`KeeperPoses.cover_lean`, no further than it takes); a puck his pads come down on (`under_pads`); where a held puck is set down and swept with no whistle for it (`play_out_way`, `set_down_at`), away from his net |
| `keeper_poke.gd` | the poke check: whether a carrier of theirs driving at him (closing at `DRIVING_M_S` on a line inside his reach) has the puck out in front of his body, in front of his goal line, where his blade can lie on it, flat on the ice, where his read says it will be when the stick gets there at his blocker speed (`plan`); the blade sent on after it from where it is, under way (`track`); where the blade's centre is sent so the blade lies on it, the stick pivoting on its heel to his hand (`aim`) |
| `keeper_clear.gd` | clearing a puck at his feet: whether an opponent gets a stick on it before his glove would land on it (`KeeperFetch.their_time`, his read the margin) and the stick gets there first, the blade sent as the poke's and turned toe forward as far as it takes to lie flat on it; the corner it goes to, away from that opponent, out its own side beside a post or against one coming head on, never toward his goal line (`clear_way`), and never through his own body (`_clear_of_him`) |
| `keeper_screen.gd` | looking round a screen: from his spot, a body on his sightline to the puck (`GoalieScreenRules.hides`) stepped round across that line by the least step that sees past it, no further than half his chest (`STEP_MAX_M`); his eyes' height standing and in the low ready, his mask as the stances hold it (`eye_height`) |
| `keeper_fetch.gd` | going for a loose puck: one a push from him (in front, or beside the post below the goal line, never behind the cage), skated to where his glove lands on it, stopping short of his blade's reach, when no opponent at full sprint gets a stick on it before he is down on it, his read as the margin to set out |
| `keeper_save_move.gd` | a low save's body: cut in from whatever pose he is in, into the save's stance in the drop's time, held, gathered into the stance he rests in, the speed it caught him at carried on (stopped by his edges on his feet unless dropped on purpose as he glides, `edges`, then by the pads' friction) |
| `controllers/keeper_controller.gd` | him in a match, in the goalie's seat (below) |
| `actors/keeper/keeper.gd` | the node: solves a pose on the tick, draws it at render rate when it moved |
| `actors/keeper/keeper_gear_meshes.gd` | each gear piece's mesh, built inside its save box |
| `actors/keeper/keeper_gear_view.gd`, `keeper_box_view.gd` | the gear drawn on the bones and painted from the team kit; the boxes drawn for debugging |
| `actors/keeper/keeper_body_rig.gd` | the gear drawn as one skinned mesh, a bone per piece posed on its save box: the plain slots one surface (BodyZonePaint), each kit-shader material one more, its pieces' box-frame places in CUSTOM0/1 since skinning moves VERTEX |
| `actors/keeper/keeper_jersey_decal.gd`, `Assets/Shaders/keeper_jersey.gdshader` | the jersey's crest and lettering, and the shader painting the kit onto the jersey, sleeves and pants (whose stripes run down the side, as the skaters' do) |
| `actors/keeper/keeper_knee_break.gd` | the break above each knee, lofted between the knee stack and the thigh rise |
| `actors/keeper/keeper_jersey_tail.gd` | the jersey's untucked tail, all the way round: cloth (`HemFlaps`, the skater's solver), a flap down each column, skinned onto the body rig from the protector's own hem and shaded on from its facets so the two read as one jersey; its rest the cloth settled on him standing ready |
| `actors/keeper/keeper_tail_colliders.gd` | what the tail drapes over: the pants and thigh guards as their rounded sections |

## In a match

Every match spawns him (`ActorSpawner` makes a `KeeperController` for each net),
offline and online. The `Goalie` node is his shell, since the puck, the skaters,
the bots and the game all address it: it draws nothing of its own and its
scene boxes are switched off, a `Keeper` child draws him, the node is placed on
him every tick, and one box per piece of his gear (`KeeperGear.box`) is seated
under the part body that names its material for the puck
(`Goalie.set_stand_in`, `add_save_box`, `seat_save_box`). Each part's first box
also places that part body, so the node's getters (glove position for the catch
pin, the pads and hands the bots read through `fill_state`) read his gear. The
controller fills the seat `GoalieController` holds: the tick, the reset, the
stance the bots read and the puck handlers: a release read and saved (below), a
tip read again, a contact only timed, a glove catch held and covered for the
whistle, and a loose puck he can reach covered (below); where no whistle
comes (`GameRules.whistles_a_cover`, Off only) he sets it down out from his
glove side as he is turned and sweeps it on, out of his reach, turned ahead as
far as it takes to head away from his net and set down clear in front of his
goal line wherever he held it, the post or below the line included
(`KeeperCover.play_out_way`, `set_down_at`).
A skater's stick meets the same boxes the puck does (`GameManager.get_goalie_boxes`,
gathered once a tick): his gear is a wall to the blade and to a carried puck,
which slide along it and are never stripped by it, and, less his stick, to the
skater's body (`get_goalie_body_boxes`, `Skater.clamp_body_to_goalies`), a disc
standing his whole height that slides along it too (`GoalieGearCollision`,
`tests/unit/rules/test_goalie_gear_collision.gd`,
`tests/unit/controllers/test_skater_meets_the_goalie.gd`).

He plays on the host only. His pose goes on the wire with his root
(`fill_state`, `KeeperPoseCodec`: every target his skeleton solves from), so a
client buffers the snapshots and draws him at the interpolated past
(`GoalieController._interpolate_and_apply`), root and pose
blended between them (`KeeperPose.blend`), his skeleton solved and his save
boxes seated on it: its puck prediction stops against the gear the host saves
with, to about a centimetre. A replay (the goal cinematic, the post-game reel,
a replay file) poses him the same way (`apply_replay_state`). A remote
shooter's release he reads from when its shooter saw it leave the stick (the
back-date GameManager sets just before the release, `KeeperShotRead.start`'s
`seen_s`), as the networking doc's shot lag comp asks. The release's rewind of
the goalie to where its shooter saw him moves his root only, which is all that
reads him at that instant (the shot's xG): his read starts from the flight, not
from his body, and his gear meets the puck only on the ticks after, live.

## Saves

A shot is read from its release, the puck's own flight only: no aim before it
(the shooter's drawn body shows that a shot is wound up, not yet where it
goes). A release a body hides from his eyes, where his mask is, he reads only
once it comes out of the body's shadow (`GoalieController.screen_delay_for`,
`GoalieScreenRules.screen_occlusion_delay`, the delay the shot log prices),
his read after that; a tip the same from where it was tipped. A puck a body
hides from him before the shot breaks his look at it, as a stickhandle out of
his gaze does, so a screened carrier never primes him. In the zone the brain
looks round a screen (`KeeperScreen`): a body on his sightline to the puck
from the spot it wants him on he steps round, across that line, by the least
step that sees past its silhouette, no further than half his chest, so a shot
down the line he left still meets his chest; a body square on his line, which
only a longer step clears, he cannot see round, and is beaten through. Ducking
into the low ready to look under one buys nothing: it lowers his eye some 0.2
m, and the silhouette narrows from the torso only toward a shin at the ice. His legs and his hands answer after the tier's read, one read for
both (a hand reacts no slower than a foot, and the glove is the lighter limb),
at the tier's speeds (`GoalieSkillProfile`), and after its primed read for a release off a puck he had held in his eyes
on a stick of theirs for `KeeperPlayRead.PRIME_S`, wound up or not (the
quiet-eye read: the save programmed during the look), a look a hard
stickhandle, a deke or a pass breaks, the puck getting out of the gaze that
pursues it (`PURSUIT_RAD_S`, held within `LOOK_WINDOW_RAD`) or going loose; a one-timer and a tip are read cold. He is beaten by a shot that arrives before a limb
can, never by a draw. Once his legs have
read a shot that would go in, he makes the save goalies are taught for where
it passes him (Hockey Canada: the butterfly for a shot below the belly button;
USA Hockey: the glove, the blocker, or the arms closing round one at the body
above it), for every shot, whether or not he would be hit standing still:
below his belly button the butterfly, the half butterfly for a shot wide of a
standing pad (the other leg left loaded), the extension past the flat pad's
reach, the hands leading it (the blade to a puck along the ice, else the hand
on its side, unless the legs' save alone meets it better); above it the glove
on its side or at the chest (trapping it), the blocker on the other. Each
candidate (a low half with a hand half: none, the blade along the ice, the
glove, the blocker) is posed, its hand aimed at the point of the flight the arm
reaches with the most time to spare, and the flight tested against that
pose's gear boxes; he makes the first in the taught order whose gear meets
the flight and holds it. Timing does not choose the save, only whether he
gets there: one he is late for he still makes, and is beaten, as a late
butterfly is beaten through the hole it opens on the way down. A save holds only if what comes off the gear
it meets (`GoalieSaveRules.resolve_contact`, the puck's own contact) is caught,
smothered, goes away from the net or meets more of him before the mouth: a puck
that clips the outside of a pad glances on in. A hand goes only where its gear
stays above the ice, and the blade only for a puck low enough for it.
A stick or blocker save that holds he makes with its face turned to steer the
rebound (`KeeperSave._steer`): the blade turned about the ice
(`STICK_TURNS_RAD`), the blocker's board about the vertical
(`BLOCKER_TURNS_RAD`), each turn posed and the believed flight tested against
it through the puck's own contact as every candidate is, and of those whose
gear still meets it and holds it he takes the one whose rebound goes most
toward the near corner (`to_corner`: out along the goal line on the side of
his net it met him, never back across his mouth; from the middle, either way
out), the straight face where none does better. The face turns no faster than
its far edge moves at the hand's speed, and back with the hand. It is his
read's flight he steers, so a shot he misreads comes off as the face it meets
sends it. A low save cuts whatever
move is under way (`KeeperMotor.save`): his feet's moves, a drop, a rise or a
recovery, and the gather after the last save (a rebound takes him back down),
falling from as far down as he is; mid-slide or on the post none can, and a
save chosen then is chosen again once one can, while the puck is still coming.
The hand rides any pose; one still going back from the last save when the
next is chosen goes on back by itself, and the new save's hand goes out from
its own place, or turns from where it is when it is the same hand. The save goes on
until it is there, and he lets it go once it is and the shot is over: at once
for a puck that hit him, which he feels (goalies are taught to start their
recovery the moment the puck hits them); his leg read after it for one that
went by him, past the line, stopped, or off the iron or boards, which he has
to see (a tip starts a new read, a pick-up ends it at once). So a save made
too late is still seen made; then the hand comes back and the motor rests him where the
save left him for the brain to bring back up. A shot over before his legs
have read it at all (from in tight, in or off him) he answers once they have:
the save for the flight he saw leave the stick, however late, made and held
the same way. The brain rests while
a save is under way (a hand save sets him where he stands, the hand aimed from
there); since his read of the play lags it by his leg read, a shot's flight
reaches the brain no sooner than the save does. A shot that leaves him time
he first moves his body onto (`KeeperSave.square_up_spot`): one whose flight
passes him wider than half his chest, where a T-push across onto its line
still leaves his drop to come before it gets there, he skates there on his
feet, square to it, the brain resting, and makes the save from there. The push
and the drop cost more than any shot from the slot gives him, so it is the
long shot's answer: lobbed from the far end into a low corner, the half
butterfly and the glove reaching from where he stood left a gap between them.
A loose puck he can reach, with no shot being read, he covers
(`KeeperCover`, `KeeperController._cover_the_puck`): one slowing on the ice
that will still be under his glove when the glove can land there, slow enough
by then for the glove to stop it. One in the air, a save's soft pop-up
included, he waits out until it lands, so a save he has felt and let go is
not cut into by a cover before the puck is down. From his feet he drops into the butterfly
(the motor's low save, cutting any move), and the glove goes flat onto it,
palm down and fingers out along the ice toward it, his trunk folding on over
the pads and turning until the puck is ahead of his glove shoulder, as far as
it takes and no faster than a trunk turns (`KeeperSave.COVER_TURN_RAD_S`); for
a puck beside or behind him the turn goes round as far as square to his side,
and his hips sink back between his skates (the W-sit a butterfly allows) and
over toward it, so the glove reaches the ice beside his pads and back behind
them on either side (`KeeperPoses.cover_lean`). The plan solves him from the
stance a drop under way lands him in, not the one he is falling through. The
glove follows the puck as it slides. A puck his pads, boots, skates or thigh
pads come down on as he goes down to cover is smothered under them where it
lies, dead and covered for the whistle like one under the glove, not kicked
away by the pads landing (`KeeperCover.under_pads`, `KeeperController._smother`).
Until then the puck is live: one poked away from his feet ends the cover, and
one still at his feet but out of the glove's reach for longer than a drop
reshaping it (`COVER_GRACE_S`) ends it too, and he plays it from his feet again.
Secured, it is dead under the glove and covered for the whistle.
A loose puck at his feet (`KeeperCover.at_feet`: on the ice, slow enough for
the glove, inside what his gear sweeps as he moves, his blade's toe and a
little more) takes him over: the brain and the fetch stop moving him, so he
never skates or shuffles his gear through it, asked to be where he is, and he
plays it where he is (`KeeperController._play_at_feet`): one he can reach he
covers; one ahead past the glove's reach he steps up to, stopping short of
it; one beside or behind him he turns to on his feet, toward it but short of
facing it (`BLADE_CLEAR_RAD`) so the blade held out ahead never sweeps round
onto it, as far as brings it into reach, up off his knees first.
A carrier of theirs driving at him (closing on him at `KeeperPoke.DRIVING_M_S`
or more, on a line inside his reach) with the puck out in front of his body
he poke checks (`KeeperPoke`, `KeeperController._poke_check`) when his read
says it lands; one skating across, stopped or gliding in he plays with his
body. Set on his feet or down, never sliding or sealed on a post, with no
shot coming or wound up, the blade's lying on the puck as he reads it (late,
carried on along the carrier's skating) is checked on his own skeleton, the
stick pivoting on its heel to his hand, and it is jabbed there at his blocker
speed, sent on after the puck as he reads it at the planner's rate
(`KeeperPoke.track`). It is only his stick: the brain goes on placing him
throughout, so a miss costs the stick out of the five-hole and away from its
spot until it is back, not his position. The blade box meeting the carried
puck on the way out knocks it off its carrier as a skater's poke does
(`Puck.apply_goalie_poke_check`), crediting no skater; the stick comes back
at once once it has, once it gets where it was sent, or once his read says
it no longer lands, so a pull or a deke after his read beats it. A save or a
cover taking his hands ends the poke. His tier reaches it through his read's
delay and his blocker speed.
A puck at his feet that an opponent would get a stick on before his glove
lands on it (`KeeperClear`, `KeeperController._clear`, priced as the fetch's
race with his read as the margin; for one out of the glove's reach, no sooner
than his drop) he sweeps away with the stick when the blade gets there first:
thrust at his blocker speed, turned toe forward as far as it takes to lie flat
on it (a puck in close on his blocker side), and the puck sent off at
`KeeperClear.SPEED_M_S` as the blade comes onto it, a tick's travel early, so
the sweep sends it rather than the blade's box arriving on it. It goes to the
corner away from that opponent, out along the boards in front of his goal
line; beside a post, or against a man coming at it head on, out its own side.
One whose way there runs into his own body he does not sweep across himself:
he covers it, as he does one the man gets to before the stick too. Like the
poke it is only his stick, set on his feet or down. Holding a puck, caught in
the glove, on his chest or covered on the ice, he is frozen where he secured
it (`KeeperMotor.freeze`): no ground covered and no move started, the move
under way only settling his pose, until he plays it out. So a rebound dying at his
feet, a dribble at the crease or a puck caught behind his stick or between his
pads is smothered rather than dropped on and popped up from.
Nothing his own gear's motion does carries a puck toward his goal line: a pad,
skate or stick moving through a puck at his feet pushes it across or out but
never in (`GoalieSaveRules.keep_out_of_own_net`, on the puck's host tick), and
one his moving gear ends up overlapping is put back out across or in front,
never behind (`eject_out_of_own_net`). A puck already sliding at his net, or a
shot, comes off him as the contact sends it, in off a pad included.
One a push away that he wins the race to (`KeeperFetch`) he skates to, square
to it, stopping short of it past his blade's reach (`COVER_AHEAD_M`), and once
he has stopped on his spot covers the same way: a loose puck
beside the post below the goal line with nobody near it is his, not left
lying there. The race prices every opponent at full sprint from the first
instant, his stick's length short of it, and he sets out only with his read
to spare.
A shot into his chest (`KeeperController._chest_contact`, through
`Goalie.chest_contact`) is caught there at
the logo when his nearer hand closes on it before what the foam leaves of its
pace carries it out of the glove's pocket (`KeeperChestTrap`): held to his
chest where it hit, the glove come over it, and covered for the whistle like a
glove catch. Anywhere else on his chest's save part (the arms, the pants, off
the logo), or too hard for his hands, it rebounds off the foam; it no longer
dies on him whatever its pace. With his hands at rest in the ready stance that
is a puck under about 5 m/s at Hard; a shot his glove was already sent to by
the save (the taught chest save) is closed on much harder.
His eyes are on the puck throughout (`KeeperLook`, laid over the pose after
the save's hand): his face follows it wherever his neck lets it, so a save is
seen tracked into the gear that makes it, and a shot that goes by him is
looked back at over his shoulder. The pose carries it on the wire, and
the mask, which turns with the head, is a save box.

`test_keeper_save.gd` (a low shot at a pad taking him down, his belly button
splitting the legs' saves from the hands', the half butterfly wide of a pad
led by the blade, the glove leading a drop for one off the ice,
the five-hole down with time and down late without, a shot at the chest
trapped with the glove, a save holding or not by its rebound, a new shot's hand going out while the last save's goes back, a long shot moved onto the line of first and one at his body or from the slot not), `test_keeper_rebound_control.gd` (a steered stick
or blocker save meeting and holding as the unsteered one does and sending its
rebound no less toward the corner, straight on from the slot the face turned
and the rebound more toward it, and the face turning at the hand's pace and
back), `tests/unit/controllers/test_keeper_steers_his_rebounds.gd` (the live
keeper and the real puck: off his blocker and his stick straight on, more
toward the corner than unsteered, and out), `test_keeper_cover.gd` (a
puck at his feet coverable from his feet once his drop lands and sooner down,
one out of reach, too fast or in the air not, a sliding one covered where it will be,
the cover played out unbroken with the glove ending flat on it, from in front
and from beside and behind him either side, what lies at his feet, and a held
puck played out away from his net however he is turned),
`tests/unit/controllers/test_keeper_plays_the_puck_at_his_feet.gd` (the live
keeper and the real puck: a dead puck beside him, behind him either side or a
step ahead covered where it lies, not knocked first; and a reset leaving
nothing of what he did before), `test_keeper_poke.gd` (the poke's plan: a puck
driven at him out in front of its carrier poked with the blade onto where it
will be, standing or down, at his blocker speed; out of reach, beside him, at
his feet, behind the carrier's body or behind his line left, and so a carrier
skating across, stopped, gliding in or driving wide of him; under way the
blade sent on after the puck until it is pulled; a right-catcher's the mirror;
and `REACH_M` culling nothing his stick could lie on),
`tests/unit/controllers/test_keeper_poke_check.gd` (the live keeper against a
real carrier driving in, his gear a wall to the carried puck: the puck out in
front poked off crediting nobody, one held behind the body left, one pulled
back once he has thrust missed with the stick home, the brain placing him
throughout),
`test_keeper_clear.gd` (the clear's plan: a puck an opponent beats his cover
to cleared with the blade on it, toe forward in close on his blocker side;
left to the cover with nobody near, his cover first, or the man there before
the stick; away from the man, out its own side by a post or head on, never
toward his goal line),
`tests/unit/controllers/test_keeper_clears_the_puck_at_his_feet.gd` (the live
keeper and the real puck, an opponent closing: by his skate and out in front
swept clean to the corner away from the man and nowhere near his net, by his
skate with the man on that side covered rather than swept across him, and
covered with the man far off),
`tests/unit/controllers/test_keeper_never_walks_a_puck_in.gd` (set on the
near post and in the RVH, the live keeper never puts a slow puck at his feet
in his net, nor one he holds there and plays out),
`test_keeper_screen.gd` (a body on his line stepped round across it, no
further than half his chest, the puck seen past it; one square on his line
not; the step round the near edge; a hidden release read once out of the
shadow), `tests/unit/controllers/test_keeper_reads_through_a_screen.gd` (the
live keeper and a real skater: a shot from behind the skater read later than
with nobody there, and a skater a little off his line stepped round until he
sees the puck),
`test_keeper_save_move.gd` (cut into a rise and into the gather after a save),
and the match through the
puck's own contact test in `test_keeper_controller.gd`.
`tests/unit/controllers/test_keeper_controller.gd` holds the swap, a catch
played out, a shot in before his read answered late and carried into, a low
shot mid-rise taking him back down, one read mid-slide saved once he lands, a
shot off him let go the tick he feels it, a soft shot at his logo caught on
his chest and a hard one coming off it, a catch on the move freezing
him where he made it, a loose puck beside the post gone for and covered
with nobody near it and left with a stick nearer it, a puck at his feet covered or, poked away first, escaping, one popped up off a save covered only once it lands, a shot lobbed from the far end into his low corner met on its line, and a
client posed from his state through the wire with every save box where the
host's is. `test_keeper_fetch.gd` holds the race, the cage and the push's reach. `test_keeper_chest_trap.gd` holds the logo and the hands closing in time. `test_keeper_look.gd` holds the look: his face onto the puck in every stance,
no faster than a head turns, held at the neck's limit, a puck behind him
looked back at over one shoulder with the trunk, and the stance left
as it is for a puck straight ahead. `test_keeper_pose_codec.gd` holds the pose on the wire: every
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
on the shin (`KeeperGear._boot_box`), built turned up from the pad by
`KeeperAnatomy.PAD_TOE_ANGLE_RAD`, the ready stance's angle between shin and
skate, as a real pad is built for its keeper's stance. In the stance it lies
along the skate just off the ice; in the butterfly the foot is turned into it
by the same angle (`leg.flex`); where the foot points down under the shin (a
kick, the RVH's standing leg) the skate shows beneath it, as a real one does.
It turns on the pad only one way: where its built angle would drive its toe
into the ice past the foam's give (a shin leant on over it, as in the low
ready), the toe bridge flexes it up off the ice, no further than it has to.
The skate never comes up through it.

A pad rests on the ice; it is strapped round the leg, not fixed to the bone.
Where a stance tilts the shin far enough that the rigid pad's bottom corner
(or its boot, after the flex) would sink into the ice past its foam's give,
the pad, its boot and its rise ride up the shin together until it rests on it
(`KeeperGear._pad_settle`, up to `PAD_SETTLE_MAX_M`). The skeleton does not
move; only the gear on it. No stance short of that is touched.

The pad's back is open, as a real one's is: its face and two side wings run
back either side of the leg, which lies in the channel between them in the
kit's socks (painted down the shin as the skaters' are), strapped across at
the ankle, calf and under the knee. The channel is lined in a shaded pad
colour, so the leg stands out even in socks the pads' colour.

The pads, the blocker and the trapper are one set in the kit's `goalie_pads`
colour (white in every bundled kit, changeable per side), trimmed alike in
`TeamColorRegistry`'s `goalie_accent`: the team's primary, or its secondary
where the primary is too faint on the pads. A pad's trim is its knee stack's
front and a stripe inside each roll — a symmetric pair, because both legs wear
one mesh and the keeper is mirrored whole.

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
butterflies, the extensions and the kicks open, the low ready's stick side
down to the ice, and the ice under the RVH's off pad), and
`test_keeper_deflections.gd` holds that no flat puck meeting his gear in a
stance he sets in comes off it on into the net.
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
pose when set and asked, and kept skating with the play and backing in at full glide, a shuffle across made
in it still sunk with the trail skate holding the ice and back in under him once
set, out of it as a move
starts or a chase, a drop and a low save
from it the shorter fall by the root of the knees' heights (a kick, a push,
not), the save pricing it, and every tick of each out of the ice, on the
stick and without a jump. `test_keeper_slide.gd` holds the slide (short ones too, whose stop comes as the push leg folds): at rest on the spot in
`KeeperSlide.time_to`, or at its reach past it, from the butterfly and from his feet (where the push skate holds from the drop's first frame, the push driving through the end of the fall, sooner from the low ready), friction then the lead edge
slowing him once pushed and the stop beating a coast, the push skate holding
its place, the lead pad down on the ice the whole way and both through the
stop, butterfly to butterfly, a spot off his line turning him to it as he loads, a
rotation on his knees onto its facing in its time without leaving his spot, a
push off the post from the RVH to rest on its spot in its time, quicker than
folding out and sliding, the boot on the post holding it until the push ends
and never toward the post, a slide to a post landing the pad's end on it angled back and opened toward
that side, and every tick out of the ice, on the stick and without a jump.
`test_keeper_post.gd` holds the RVH's ways in and out: each in its time, from
and to the overlap and the butterfly, sealed with the pad's end on the post,
the puck dead ahead of him turned on the post (`overlap_facing`),
the off skate on the ice through the drop-in and the rise, and every tick out
of the ice, on the stick and without a jump. `test_keeper_motor.gd` holds the
moves strung together: whole sequences across the crease and back with nothing
jumping at a hand-off, the pivot at its rate onto its facing, footwork in his
turned frame, a move from the wrong rest refused, asked down while skating
down at once carrying his speed, and down pushes one after another, the next
going as soon as the last stops. `test_keeper_route.gd`
holds him given where to be: from every rest to every kind of goal, there,
every tick unbroken, no move refused and in the time the route planned (the
brain will read it); a near spot skated to and a far one pushed for, past the
glide's reach a turn first, a recovery toward a spot on his feet, a drop-in
from the overlap, and straight in from it turned to a sharp angle, or
skated onto it still turned from short of it; down on his spot a new facing
rotated to, a small one left to his trunk, and a spot within one push kept on
his knees for; in the RVH the other post or a spot across pushed off the post
for, one in front on the post's side folded out for; a spot or facing moved under a move taken on by it; and the
last order winning. `test_keeper_glide.gd` holds the glide: a moving spot
caught and skated with, never stopped for, gliding once matched; a still one
stroked for, glided on and stopped on, no further, in the glide's time; one that turns back followed
unbroken; in depth no faster than the C-cuts. `test_keeper_positioning.gd` holds a carrier cutting across the slot
tracked on the angle line, his depth against the puck's motion (the top of the
crease still or slow, a rush backing him in no further than the floor and on it
in time, a swing across him no faster than his shuffle, a carrier stopped in
tight still holding him in where a loose puck there does not), a rush straight in
skated back as it comes, and an open receiver across the slot holding him as
deep as the push to its angle he has time for, a shot wound up on the rush
met set at the top, a pass he reads played from its stick's angle, turned
to it, in front of the net for a pass out from behind it, and the low ready
asked for once a shot of theirs could beat his reaction, held a margin past
it, a shorter reach once primed, none for a puck of ours or on the post, and
a pass by when its stick can shoot it; a carrier driving down the wing at a
post, him on his feet until it is in tight, the ice inside the post covered
as the puck gets there and then sealed; the same drive feinted from range
finding him still on the angle line, and cut back out bringing him back up;
a carrier of theirs driven to just outside the post met planted in the
butterfly on it, the ice inside the post sealed and him turned toward the
carrier no further than a slide back across goes, and a cut across the top of
the crease from there slid with on his knees, never back up, ending square to
the carrier on the far side; a carrier of theirs out of tight holding the puck
out to one side squared to, not the body, and one in tight met down on the
puck's line, square to it.
`test_keeper_play_read.gd` holds the read: a puck on its line read where it
is, a change of direction read after his read (a slower tier later), a
wind-up seen his read late, a steady look at the puck on a stick of theirs
priming the save once held long enough, an ordinary stickhandle skated across
the slot still priming it and a hard one in close, a pass or a body between
breaking it, the
receivers a pass can reach, a carried puck read his read late and carried on
along its own motion, no further from its carrier than he reaches, a release seen his read late, and a pass read to the stick that meets
it once seen and until seen caught, none for a line no stick reaches or a
puck that stops short.
`test_keeper_stances_are_whole.gd` holds that every taught stance writes the
whole of what the skeleton solves from: written over a pose left anywhere
else (a foot turned along its shin, a cover's lean, the hands out), it solves
to the same body and gear as over a fresh one, so his gear never depends on
what he did before.
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
`tests/instruments/keeper/test_keeper_save_timing.gd` says why a shot beats him:
per tier, spot, speed and aim, the save chosen and its margin, how far his hand
and his drop had got when the shot was decided, and what decided it; a
rebound fired at gaps after a save, against what he was doing as it left; and
shots from the far end (`test_report_long_range`).
`tests/instruments/keeper/test_rebound_control.gd` says how far rebound
control steers what comes off him: the live keeper and the real puck, shots
from the slot, the circles and the dots at his blocker and along the ice at
his stick, each steered and unsteered, the share of the rebound heading for
the near corner per shot and on the mean, and the goals each way.
`tests/instruments/keeper/test_priming_look.gd` says how often he gets primed
against a carrier standing, skating across or driving in, stickhandling softly
to hard, at 6, 9 and 12 m, and how fast the puck crosses his view.
`tests/instruments/keeper/test_lateral_race.gd` says how fast he gets across
from the low ready, skated there or slid, and from the butterfly how soon a
down push gets there and he could push again. `tests/instruments/keeper/
test_close_play_probe.gd` plays a carrier in tight moving the puck (a dangle, a
drag across, a walk across the slot, a cut in, a drive with a late pull) and
says per tick how far his angle lags the puck's and how much of the mouth he
covers where he is against the same stance set on the puck's line, and the
saves on shots after a drag by delay.
`tests/instruments/keeper/test_loose_puck_at_his_feet.gd` lays a slow loose
puck all round his feet, set square, at an angle, on the post and in the RVH,
and says how each ended: covered, gone, left lying at his feet or near him,
slid in untouched, or in off him, every goal printed with what touched it last
and what he was doing, and where each puck left at his feet lies;
`test_trace_the_goals_off_him` traces the goals it names contact by contact,
against where each puck goes with him not there.
`tests/instruments/keeper/test_drop_seal_timing.gd` says how soon the
butterfly covers the low net: tick by tick through the drop, from the ready
stance and from the low ready, the share of lines across the mouth a puck on
the ice, at 10 cm and at 20 cm meets his gear on and stays out.
`tests/instruments/ai/test_goalie_scoreboard.gd` scores him against scripted
shooters (`test_report_the_keeper`, his numbers in
`data/keeper_scoreboard.txt`, printed beside the old goalie's last recorded
table), through the shot harness the bots' shot field is measured with: it
reads him through the seat's getters (his stance, lateral x and challenge
radius). The shooter is a skater he sees, and each staging looks afresh, since a
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
