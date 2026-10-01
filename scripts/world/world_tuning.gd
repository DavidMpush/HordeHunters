extends RefCounted

# World tuning (ported from Mawlings scripts/tuning.gd, only the map values).

# Quicksand (desert): slows everything crossing it, never deadly.
const QUICKSAND_SLOW := 0.5
const QUICKSAND_RIM := 1.2
# Lakes and moors with a shallow shore: the shore band (SHALLOW_WIDTH m on the
# water side) is walkable and slows every body to SHALLOW_SLOW (eased in over
# SHALLOW_RIM m); the deep middle blocks like a wall.
const SHALLOW_SLOW := 0.6
const SHALLOW_WIDTH := 2.5
const SHALLOW_RIM := 0.8

# Walls from one cast (arena_border.gd, wall_mesh.gd): heights per kind (m),
# dome of the top, camera-side lowering, inset of the visible edge, smoothing
# band around the bilinear collision field, sample steps (m; in-map chunks /
# border ring), contact shadow and accent spacing.
const WALL_HEIGHT_ROCK := 2.0
const WALL_HEIGHT_HEDGE := 1.75
const WALL_HEIGHT_MASONRY := 1.6
const WALL_DOME_ROCK := 0.25
const WALL_DOME_HEDGE := 0.35
const WALL_CAMERA_LOW := 0.3
const WALL_INSET := 0.22
const WALL_SMOOTH_BAND := 0.22
const WALL_SAMPLE_STEP := 1.0
const WALL_EDGE_STEP := 2.0
const WALL_SHADOW_WIDTH := 1.3
const WALL_SHADOW_ALPHA := 0.55
const WALL_ACCENT_SPACING := 7.0
