class_name RenderLayers

# Render layers, which in this project decide two things: whether the
# play-following cameras draw a piece of geometry, and whether the arena's
# reflection probe captures it.
#
# A const class rather than a row in Constants.gd (the engine-facing autoload)
# because @tool scripts build their geometry in the editor, where autoloads
# don't exist. Access anywhere as `RenderLayers.OVERHEAD_DRESSING`.

# Layer 1 (bit 0): Godot's default, which everything renders on unless it says
# otherwise.
const DEFAULT: int = 1 << 0

# Layer 2 (bit 1): the arena's overhead set dressing — the centre-hung
# scoreboard, the end-zone netting, the ceiling light fixtures. All of it hangs
# between a top-down camera and the play somewhere in the zoom range: the
# scoreboard and the netting from below, and the light fixtures from above,
# once the zoom climbs past the 22 m rig.
#
# GameCamera and PovCamera clear this bit. Every other camera — lobby backdrop
# orbit, spectator/broadcast, chase, free, goal-replay — keeps Camera3D's
# everything-on default, so the building is whole in every shot meant to show
# it, and nothing needs per-camera wiring.
const OVERHEAD_DRESSING: int = 1 << 1

# Layer 3 (bit 2): the building, as the reflection probe sees it. Added ON TOP of
# layer 1 to everything under the arena root (ArenaReflection.tag_static), never
# instead of it, so no camera's view changes. The probe captures once, so what it
# draws must hold still: the actors spawn outside the arena root and never carry
# this bit.
const REFLECTED_STATIC: int = 1 << 2
