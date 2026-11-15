extends Node3D
## Procedural test level for the FPS sandbox: floor, perimeter walls, cover, ramp, stairs
## and a raised platform. Built from BlockBuilder boxes — the same primitives the map
## editor will use — rather than engine-authored art.

const FLOOR_COLOR: Color = Color("3a4049")
const WALL_COLOR: Color = Color("5b6370")
const COVER_COLOR: Color = Color("8a6a46")
const ACCENT_COLOR: Color = Color("b8542a")
const PLATFORM_COLOR: Color = Color("4c6b7a")

const ARENA_HALF_SIZE: float = 30.0
const WALL_HEIGHT: float = 4.0


func _ready() -> void:
	build()


func build() -> void:
	var s := ARENA_HALF_SIZE
	# Floor: top surface at y = 0.
	BlockBuilder.make_box(self, Vector3(s * 2.0, 1.0, s * 2.0), Vector3(0, -0.5, 0), FLOOR_COLOR, Vector3.ZERO, "Floor")

	# Perimeter walls.
	var h := WALL_HEIGHT
	BlockBuilder.make_box(self, Vector3(s * 2.0, h, 1.0), Vector3(0, h / 2.0, -s), WALL_COLOR, Vector3.ZERO, "WallNorth")
	BlockBuilder.make_box(self, Vector3(s * 2.0, h, 1.0), Vector3(0, h / 2.0, s), WALL_COLOR, Vector3.ZERO, "WallSouth")
	BlockBuilder.make_box(self, Vector3(1.0, h, s * 2.0), Vector3(-s, h / 2.0, 0), WALL_COLOR, Vector3.ZERO, "WallWest")
	BlockBuilder.make_box(self, Vector3(1.0, h, s * 2.0), Vector3(s, h / 2.0, 0), WALL_COLOR, Vector3.ZERO, "WallEast")

	# Crates and cover of common tactical heights (waist, head, full).
	BlockBuilder.make_box(self, Vector3(1.2, 1.2, 1.2), Vector3(-4, 0.6, 2), COVER_COLOR, Vector3.ZERO, "CrateSmall")
	BlockBuilder.make_box(self, Vector3(1.2, 1.2, 1.2), Vector3(-2.8, 0.6, 2), COVER_COLOR, Vector3.ZERO, "CrateSmall2")
	BlockBuilder.make_box(self, Vector3(1.2, 1.2, 1.2), Vector3(-3.4, 1.8, 2), COVER_COLOR, Vector3.ZERO, "CrateStacked")
	BlockBuilder.make_box(self, Vector3(2.0, 2.0, 2.0), Vector3(5, 1.0, -2), COVER_COLOR, Vector3.ZERO, "CrateLarge")
	BlockBuilder.make_box(self, Vector3(6.0, 1.1, 0.4), Vector3(0, 0.55, -6), WALL_COLOR, Vector3.ZERO, "LowWall")
	BlockBuilder.make_box(self, Vector3(0.6, 3.0, 8.0), Vector3(-10, 1.5, -4), WALL_COLOR, Vector3.ZERO, "Divider")

	# Raised platform spanning x 9..19, z -9..-1, top at y = 3.
	BlockBuilder.make_box(self, Vector3(10.0, 3.0, 8.0), Vector3(14, 1.5, -5), PLATFORM_COLOR, Vector3.ZERO, "Platform")
	# Ramp from the floor (z ≈ 9) up to the platform's south edge (z ≈ -1), about 17 degrees.
	BlockBuilder.make_box(self, Vector3(4.0, 0.3, 10.4), Vector3(14, 1.35, 4), ACCENT_COLOR, Vector3(17.0, 0, 0), "Ramp")

	# Stairs on the platform's east side: 10 visual steps of 0.3 m from x = 24 down to x = 19.
	# CharacterBody3D does not auto-step ledges, so walking uses a hidden 31° slope collider.
	for i: int in range(10):
		var step_top := 0.3 * float(i + 1)
		BlockBuilder.make_box(self, Vector3(0.5, step_top, 3.0),
			Vector3(23.75 - 0.5 * float(i), step_top / 2.0, -5.0),
			ACCENT_COLOR, Vector3.ZERO, "Step%d" % i, false)
	var run := 5.0
	var rise := 3.0
	var slope_length := sqrt(run * run + rise * rise)
	var slope_angle := rad_to_deg(atan2(rise, run))
	BlockBuilder.make_collision_box(self, Vector3(slope_length, 0.2, 3.0),
		Vector3(21.5, 1.5 - 0.1 / cos(deg_to_rad(slope_angle)), -5.0),
		Vector3(0, 0, -slope_angle), "StairsSlope")

	# Pillars to judge depth and strafing.
	for x: int in [-18, -12, -6]:
		BlockBuilder.make_box(self, Vector3(0.8, 3.2, 0.8), Vector3(x, 1.6, 14), WALL_COLOR, Vector3.ZERO, "Pillar%d" % x)
