# Hockey Net Geometry Spec

Implementation spec for a realistic NHL-style hockey net. Hand off to Claude Code for implementation.

---

## Overview

The modern NHL net is a modified Art Ross design. It consists of:

- **Two vertical posts** at the front (red steel tubes)
- **A horizontal crossbar** connecting the post tops (red steel tube)
- **A top shelf curve** — a horizontal arc at crossbar height (Y = 1.22m), curving backward to 0.56m depth
- **A base curve** — a horizontal arc at ice level (Y = 0), curving backward to 1.02m depth and flaring wider than the posts
- **Netting** stretched between the two curves and the posts

The top shelf is perfectly flat in Y — it only curves in the X/Z horizontal plane. Both curves are symmetric about the Z axis.

---

## Coordinate System

Origin is at the center of the goal mouth, at ice level.

- **X** = left/right (positive = right when facing the net)
- **Y** = up (positive = up)
- **Z** = depth into the net, away from play (positive = into net)

The goal line runs along the X axis at Z = 0.

---

## Key Dimensions (meters)

| Measurement | Imperial | Metric |
|---|---|---|
| Opening width (between posts) | 72" | 1.83m |
| Opening height | 48" | 1.22m |
| Top shelf depth (at crossbar height) | 22" | 0.56m |
| Base depth (at ice level) | 40" | 1.02m |
| Base overall width | 88" | 2.24m |
| Base side radius | 18" | 0.457m |
| Post/crossbar tube OD | 2 3/8" | 0.06m |
| Top corner elbows | 90° sharp | 90° sharp |

---

## Steel Frame Components

### Posts

Two vertical cylinders (or capsule shapes), painted red.

- **Left post:** center at X = −0.915, from Y = 0 to Y = 1.22, at Z = 0
- **Right post:** center at X = +0.915, from Y = 0 to Y = 1.22, at Z = 0
- **Radius:** 0.03m (OD = 0.06m)

### Crossbar

Horizontal cylinder connecting the post tops, painted red.

- From (−0.915, 1.22, 0) to (+0.915, 1.22, 0)
- Same radius as posts: 0.03m
- Corners where crossbar meets posts are sharp 90° elbows (forged, not radiused)

### Top Shelf Frame

A horizontal arc at Y = 1.22m, painted red. This is a steel tube that curves backward from each post top. It is perfectly flat — no change in Y, only curves in X/Z.

Defined as two mirrored cubic Bézier curves (see Curve Definitions below). Same tube radius as posts: 0.03m.

### Base Frame

A horizontal arc at Y = 0 (on the ice), painted white. This steel tube curves backward from each post base and flares wider than the posts.

Defined as two mirrored cubic Bézier curves (see Curve Definitions below). Same tube radius as posts: 0.03m.

---

## Curve Definitions

Both curves are symmetric about the Z axis. Each is defined as two mirrored cubic Bézier halves that meet at the center back. The left half mirrors the right half by negating all X values.

All coordinates are (X, Z) in meters. Y is constant for each curve.

### Base Curve (Y = 0)

**Right half control points:**

```
P0 = ( 0.915,  0.00)   # Right post — start point
P1 = ( 0.915,  0.46)   # Tangent: straight back from post
P2 = ( 1.12,   0.92)   # Pulls outward — creates the flare
P3 = ( 0.00,   1.02)   # Center back — deepest point
```

**Left half control points (mirror):**

```
P0 = (-0.915,  0.00)   # Left post — start point
P1 = (-0.915,  0.46)   # Tangent: straight back from post
P2 = (-1.12,   0.92)   # Pulls outward — creates the flare
P3 = ( 0.00,   1.02)   # Center back — shared with right half
```

**Tangent properties:**
- At posts (P0): P1 shares X with P0, so the curve leaves the post going straight back, parallel to the Z axis
- At center (P3): P2 is nearly horizontal relative to P3, so the curve arrives at the center perpendicular to the Z axis (smooth, no cusp)
- P2.x = 1.12 > P0.x = 0.915 — this is what makes the base flare wider than the posts

### Top Shelf Curve (Y = 1.22m)

**Right half control points:**

```
P0 = ( 0.915,  0.00)   # Right post top — start point
P1 = ( 0.915,  0.28)   # Tangent: straight back from post
P2 = ( 0.60,   0.52)   # Pulls inward — no flare, tighter curve
P3 = ( 0.00,   0.56)   # Center back — deepest point
```

**Left half control points (mirror):**

```
P0 = (-0.915,  0.00)   # Left post top — start point
P1 = (-0.915,  0.28)   # Tangent: straight back from post
P2 = (-0.60,   0.52)   # Pulls inward — no flare, tighter curve
P3 = ( 0.00,   0.56)   # Center back — shared with right half
```

**Tangent properties:**
- Same straight-back departure from posts as the base curve
- Same smooth perpendicular arrival at center
- P2.x = 0.60 < P0.x = 0.915 — the top shelf pulls inward, stays narrower than the posts. This is the key difference from the base curve.

---

## GDScript Bézier Evaluation

To sample points along either curve, evaluate the cubic Bézier at parameter `t` from 0.0 to 1.0:

```gdscript
## Evaluate a cubic Bézier at parameter t.
## p0, p1, p2, p3 are Vector2 (X, Z coordinates).
## Returns Vector2.
func cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3
```

Sample both halves and combine:

```gdscript
const SEGMENTS := 16  # per half-curve

# Right half: t goes from 0 (post) to 1 (center)
# Left half: mirror the right half points (negate X)

func get_curve_points(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> PackedVector2Array:
	var right_half: Array[Vector2] = []
	for i in range(SEGMENTS + 1):
		var t: float = float(i) / float(SEGMENTS)
		right_half.append(cubic_bezier(p0, p1, p2, p3, t))

	# Build full curve: left half (reversed, mirrored) + right half
	var points: PackedVector2Array = PackedVector2Array()
	# Left half — iterate right_half in reverse, negate X
	for i in range(SEGMENTS, 0, -1):  # skip index 0 to avoid duplicate center point
		var pt: Vector2 = right_half[i]
		points.append(Vector2(-pt.x, pt.y))
	# Right half — forward
	for pt in right_half:
		points.append(pt)

	return points
```

### Curve Constants

```gdscript
# Base curve (Y = 0) — right half control points (X, Z)
const BASE_P0 := Vector2(0.915, 0.0)
const BASE_P1 := Vector2(0.915, 0.46)
const BASE_P2 := Vector2(1.12, 0.92)
const BASE_P3 := Vector2(0.0, 1.02)

# Top shelf curve (Y = 1.22) — right half control points (X, Z)
const TOP_P0 := Vector2(0.915, 0.0)
const TOP_P1 := Vector2(0.915, 0.28)
const TOP_P2 := Vector2(0.60, 0.52)
const TOP_P3 := Vector2(0.0, 0.56)

const NET_HEIGHT := 1.22       # Post/crossbar height (meters)
const POST_RADIUS := 0.03     # Tube radius (meters)
const POST_HALF_WIDTH := 0.915 # Half of 1.83m opening
```

---

## Mesh Construction

### Frame Tubes (Posts, Crossbar, Curves)

Each frame element is a tube — a circle swept along a path. For the posts and crossbar these are straight lines. For the curves, sweep a circle along the sampled Bézier points.

Approach: for each sampled point along a curve, generate a ring of vertices (e.g., 8 vertices) perpendicular to the curve tangent. Connect adjacent rings with triangle strips.

For posts and crossbar, `CylinderMesh` or `CapsuleMesh` may be simpler than procedural generation.

**Colors:**
- Posts, crossbar, and top shelf frame: red (`Color(0.9, 0.1, 0.1)`)
- Base frame: white (`Color(0.95, 0.95, 0.95)`)

### Netting

The netting fills the space between the two curves and the posts. A few approaches from simplest to most realistic:

**Option A — Simple flat panels (recommended starting point):**
Generate a series of vertical slices connecting corresponding points on the base and top shelf curves at the same parameter `t`. Each slice is a quad (two triangles) from base point at Y=0 to top shelf point at Y=1.22. This creates a smooth ruled surface.

Additionally, generate the "back wall" netting — at each `t`, draw a vertical line from the base curve up to the top shelf curve. The netting between these verticals fills the back.

**Option B — Grid mesh with net texture:**
Same as Option A, but subdivide each panel vertically (e.g., 4 subdivisions in Y) and apply a semi-transparent net/mesh texture with alpha cutout. This looks much more realistic.

**Option C — Actual net geometry:**
Generate horizontal and vertical lines in a grid pattern across the netting surface. Each line is a thin cylinder. Most realistic but highest vertex count.

**For all options:** The netting material should be semi-transparent white. Use `StandardMaterial3D` with `transparency = ALPHA`, `albedo_color = Color(1, 1, 1, 0.3)`, and `cull_mode = DISABLED` (double-sided).

### Connecting the Curves

At each sample index `i` (from 0 to `2 * SEGMENTS`), you have:
- A base point: `(base_points[i].x, 0.0, base_points[i].y)`
- A top shelf point: `(top_points[i].x, 1.22, top_points[i].y)`

The netting quad between index `i` and `i+1` uses these four 3D vertices:
```
bottom-left:  (base_points[i].x,   0.0,   base_points[i].y)
bottom-right: (base_points[i+1].x, 0.0,   base_points[i+1].y)
top-left:     (top_points[i].x,    1.22,  top_points[i].y)
top-right:    (top_points[i+1].x,  1.22,  top_points[i+1].y)
```

Note: the base curve is wider and deeper than the top shelf curve, so these quads are not rectangular — they're trapezoids that taper inward as Y increases. This is what creates the characteristic net shape.

---

## Collision Shapes

### For Puck Physics (Most Important)

The puck slides on the ice (Y ≈ 0), so the base curve is the primary collision boundary. Options:

**Option A — `ConcavePolygonShape3D` from the netting mesh:**
Use the same mesh vertices to generate a trimesh collision shape. Most accurate but slightly more expensive.

**Option B — Series of `BoxShape3D` segments:**
Approximate the base curve with short straight segments. At each segment, place a thin box rotated to match the segment angle. Fast and works well with 16+ segments.

**Option C — `ConvexPolygonShape3D`:**
Generate a convex hull from the base curve points extruded to the full height. Won't work because the net shape is concave (it curves inward from both sides).

Recommended: **Option A** for accuracy, since the net is already generating mesh data.

### For Elevated Puck / Shot Physics

Elevated pucks can hit the crossbar, posts, and netting at any height. The netting collision should cover the full surface between the two curves. The crossbar and posts need their own cylinder collision shapes.

### For Skater Collision

Skaters should collide with the posts and the base frame but generally not with the netting. Use separate collision layers:
- Posts + crossbar + base frame: layer 1 (general physics)
- Netting: only collides with puck (mask accordingly)

---

## Scene Tree Structure

```
Goal (Node3D)
├── Posts (Node3D)
│   ├── LeftPost (MeshInstance3D + StaticBody3D + CollisionShape3D)
│   └── RightPost (MeshInstance3D + StaticBody3D + CollisionShape3D)
├── Crossbar (MeshInstance3D + StaticBody3D + CollisionShape3D)
├── TopShelfFrame (MeshInstance3D)  — visual only, thin tube
├── BaseFrame (MeshInstance3D + StaticBody3D + CollisionShape3D)
└── Netting (MeshInstance3D + StaticBody3D + ConcavePolygonShape3D)
```

Consider making this a `@tool` script so the net is visible in the editor, consistent with the existing rink generation approach.

---

## Placement

Goals sit on the goal line. In the existing rink (60×26m, Z is the long axis), goals are at each end, 3.4m from the boards (per ARCHITECTURE.md). The net extends backward (away from play) from the goal line.

Each goal's origin (center of goal mouth) aligns with the center of the rink's X axis.

---

## Tuning Notes

- The Bézier control points above are based on NHL regulation dimensions. If the net looks too deep or too shallow in-game, adjust P3.y (depth) and P2 (shape) on either curve.
- The base flare (P2.x = 1.12 on the base curve) is subtle — only about 0.2m beyond each post. If it's not visible from the top-down camera, consider exaggerating slightly.
- With a potential rink scale reduction to ~2/3 size (open question from ARCHITECTURE.md), the net dimensions may need proportional scaling. Keep the curve constants as `@export` or in a resource so they're easy to tune.
- Segment count of 16 per half-curve (32 total points per curve) should be more than enough for visual quality. Can reduce to 8 for lower-end targets.
