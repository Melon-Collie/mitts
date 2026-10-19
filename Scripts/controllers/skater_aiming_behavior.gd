class_name SkaterAimingBehavior
extends RefCounted

# ── Wrister charge state ──────────────────────────────────────────────────────
# Cursor (intent) position in SCREEN-space, packed into a Vector3 as
# (screen.x, 0, screen.y) — the previous tick's, which the cursor-speed EMA
# differences against. Screen space is the camera-immune frame — pixel motion
# captures pure mouse drag intent regardless of camera lag, body rotation, or
# skater locomotion.
# Public (no underscore): LocalController saves and restores it across
# reconcile() replay alongside the rest of the charge state.
var prev_intent_pos: Vector3 = Vector3.ZERO
# EMA of the raw SCREEN-space cursor speed (px/s) — THE wrister power signal.
# Unfiltered hand motion, NOT the ROM-clamped, speed-capped blade speed: flick
# fast = hard, sweep slow = soft. Saved/restored across reconcile
# like the rest of the charge state.
var cursor_speed_ema: float = 0.0
# World position of the blade/puck at the MOMENT the wrister charge began (mouse
# down), captured in reset_wrister. This is a human shot's aim ORIGIN: the
# release fires along origin→cursor, so the
# aim is anchored where the stroke STARTED, not on the live blade (which has
# swung to an extreme by release — a leading, arcing point that made the aim
# whip at tight angles / a close cursor). Pinned at stroke start so it doesn't
# move as the stick sweeps. Saved/restored across reconcile like the rest of the
# charge state (set once on the entry edge; restored so replay can't re-perturb).
var wrister_origin_world: Vector3 = Vector3.ZERO
# Skater world position (XZ, y = 0) at that same charge-start moment — the
# reference WristerLoad reads the frozen puck against. Saved/restored across
# reconcile alongside wrister_origin_world.
var wrister_origin_skater_pos: Vector3 = Vector3.ZERO

# ── Slapper charge state ──────────────────────────────────────────────────────
var slapper_charge_timer: float = 0.0
var one_timer_window_timer: float = 0.0
# Seconds left in the one-timer's committed catch-and-load hold. Counts down in
# ONE_TIMER_RETENTION only; the shot fires when it reaches zero. Saved/restored
# across reconcile like the other shot timers — the retention handler ticks it
# inside the replay loop, so without that it would drain O(N) per broadcast and
# fire the shot early.
var one_timer_retention_timer: float = 0.0

# ── Wrister ───────────────────────────────────────────────────────────────────

func reset_wrister(initial_intent_pos: Vector3,
		initial_origin_world: Vector3 = Vector3.ZERO,
		initial_origin_skater_pos: Vector3 = Vector3.ZERO) -> void:
	cursor_speed_ema = 0.0
	prev_intent_pos = initial_intent_pos
	wrister_origin_world = initial_origin_world
	wrister_origin_skater_pos = initial_origin_skater_pos


# Raw screen-space cursor speed (px/s), EMA-smoothed — THE wrister power signal.
func tick_wrister_charge(intent_pos: Vector3, delta: float,
		cursor_speed_smoothing: float) -> void:
	if delta > 0.0:
		var screen_delta := intent_pos - prev_intent_pos
		screen_delta.y = 0.0
		var inst_speed: float = screen_delta.length() / delta
		var a: float = clampf(cursor_speed_smoothing * delta, 0.0, 1.0)
		cursor_speed_ema = lerpf(cursor_speed_ema, inst_speed, a)
	prev_intent_pos = intent_pos


# ── Slapper ───────────────────────────────────────────────────────────────────

func reset_slapper() -> void:
	slapper_charge_timer = 0.0
	one_timer_window_timer = 0.0
	one_timer_retention_timer = 0.0


func tick_slapper(delta: float) -> void:
	slapper_charge_timer += delta


func tick_one_timer_window(delta: float) -> void:
	if one_timer_window_timer > 0.0:
		one_timer_window_timer -= delta


func tick_one_timer_retention(delta: float) -> void:
	if one_timer_retention_timer > 0.0:
		one_timer_retention_timer -= delta
