extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Saffra": a desert old town at night, of adobe,
## limewashed and ochre walls, built to the conventions of classic competitive defuse maps:
## three lanes, tight chokes with doors and arches, a long sightline to one site, stairs and
## high ground, a covered market, flat roofs with cornices and timber beam ends, and crate cover.
## The layout and every name are original.
##
## The town stands on two levels: the defenders' half to the north is a plateau 3 m up, the
## attackers' half and the west yard are low. The two sites play differently on purpose:
## - A, Dyers' Court (east), is up on the plateau and favours defenders. Attackers climb to it
##   either by the long Spice Road (through the Spice Doors, a dogleg and the Spice Steps up to the
##   Spice Arch) or by the Balcony Steps off mid onto the Balcony at the court's corner. Defenders
##   walk to it on the level along North Street.
## - B, Cistern Yard (west), is down in the low town nearer the attackers and favours them: the
##   covered Souk and Lantern Passage both reach it quickly, while defenders come down the
##   Garrison Steps into it.
## Mid is broken into three offset lengths (Lower Mid, Caravan Street and Top Mid, up the Mid
## Steps behind the Mid Doors), so no line of sight runs from spawn to spawn. Potters Row and Dye
## Lane let attackers swap lanes on their own half.
##
## The town is the playable space cut out of solid blocks: HOLES lists the streets and yards (with
## their floor level) and every other cell of the grid becomes a building, its height and finish
## set per 10 m tile so the roofline steps. Street-facing walls then get plinths, cornices,
## shuttered windows, doors, beam ends and lanterns.
##
## Bots climb at most 0.1 m and walk slopes up to about 24°, so stairs are long and floors flush.
##
## Run:  <godot> --headless --path <project> --script res://tools/author_saffra.gd
## (add `-- --dry-run` to validate and print timings without publishing).

const UP: float = 3.0
const SITE_A: Vector3 = Vector3(30, UP, -25)
const SITE_B: Vector3 = Vector3(-29, 0, -18)
## The built-up block around the town.
const BOUNDS: Rect2 = Rect2(-50, -68, 100, 130)
const TILE: float = 10.0
## Open space: [name, x1, x2, z1, z2, decorate the walls around it, floor level, raised floor finish].
## Raised areas must not overlap one another.
const HOLES: Array = [
	["Garrison", -16, 12, -60, -46, true, UP, "stone_paving"],
	["North Street", 12, 32, -52, -42, true, UP, "stone_paving"],
	["A Gate", 22, 30, -42, -40, false, UP, "stone_paving"],
	["Dyers' Court", 16, 42, -40, -14, true, UP, "stone_paving"],
	["Balcony", 16, 22, -14, 0, false, UP, "tile_terracotta"],
	["Spice Landing", 34, 42, -14, -10, false, UP, "stone_paving"],
	["Top Mid", -8, 0, -46, -20, true, UP, "packed_earth"],
	["Barracks Lane", -30, -16, -54, -46, true, UP, "stone_paving"],
	["Garrison Steps", -30, -22, -46, -38, false, 0.0, ""],
	["B Gate", -30, -22, -38, -32, true, 0.0, ""],
	["Cistern Yard", -42, -16, -32, -8, true, 0.0, ""],
	["Mid Steps", -8, 0, -20, -12, false, 0.0, ""],
	["Mid Doors", -8, 8, -12, -6, true, 0.0, ""],
	["Caravan Street", 0, 8, -8, 24, true, 0.0, ""],
	["Mid Bend", -10, 8, 18, 24, true, 0.0, ""],
	["Lower Mid", -10, -2, 18, 38, true, 0.0, ""],
	["Balcony Steps", 8, 16, -6, 0, false, 0.0, ""],
	["Caravanserai", -20, 8, 38, 54, true, 0.0, ""],
	["Camel Yard", 8, 38, 38, 48, true, 0.0, ""],
	["Spice Lower", 30, 38, 18, 48, true, 0.0, ""],
	["Spice Road", 34, 42, -2, 24, true, 0.0, ""],
	["Spice Steps", 34, 42, -10, -2, false, 0.0, ""],
	["Dye Lane", 8, 34, 12, 16, true, 0.0, ""],
	["West Yard", -38, -20, 38, 48, true, 0.0, ""],
	["Souk", -38, -30, -8, 48, true, 0.0, ""],
	["Potters Row", -30, -10, 26, 30, true, 0.0, ""],
	["Lantern Row", -16, 0, 2, 8, true, 0.0, ""],
	["Lantern Passage", -20, -14, -8, 8, true, 0.0, ""],
]
const HEIGHTS: Array[float] = [6.0, 6.8, 7.6, 8.4, 9.6]
const FINISHES: Array[String] = ["adobe", "limewash", "plaster_ochre", "limestone", "adobe", "limewash"]

var _lanterns: int = 0


func _official_id() -> String:
	return "map_f2f_saffra"


func _revision() -> int:
	return 3


func _build() -> void:
	controller.set_metadata("Saffra", "F2F official",
		"A desert old town at night, lit by lanterns, braziers and strings of bulbs, on two levels. A, Dyers' Court, up on the defenders' plateau: climb the long Spice Road to the Spice Arch, or the Balcony Steps off mid. B, Cistern Yard, down in the low town: through the covered Souk or Lantern Passage. Mid bends twice up to the Mid Doors and the Mid Steps.")
	# Night: a cold, low moon and a deep blue sky; the town is lit by its lamps.
	controller.set_lighting({"sun_yaw": 128.0, "sun_pitch": 38.0, "sun_energy": 0.28, "sun_color": "9db4e6",
		"ambient_color": "28324c", "ambient_energy": 0.42, "haze": 0.3, "sky": "desert_night"})
	_ground()
	_buildings()
	_facades()
	_landmarks()
	_court_a()
	_yard_b()
	_mid()
	_spice_road()
	_souk()
	_side_lanes()
	_spawn_yards()
	_lights()
	_gameplay()
	_callouts()
	_tactical()


# --- helpers ------------------------------------------------------------------------------------

static func face(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(-(to.x - from.x), -(to.z - from.z)))


## True where (x, z) is open street or yard.
static func is_open(x: float, z: float) -> bool:
	return not hole_at(x, z).is_empty()


static func hole_at(x: float, z: float) -> Array:
	for hole: Array in HOLES:
		if x > float(hole[1]) and x < float(hole[2]) and z > float(hole[3]) and z < float(hole[4]):
			return hole
	return []


## The 10 m tile a point is in; buildings in one tile share a height and finish.
static func tile_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - BOUNDS.position.x) / TILE), floori((z - BOUNDS.position.y) / TILE))


static func _hash(key: Vector2i) -> int:
	return posmod(key.x * 7 + key.y * 13 + key.x * key.y * 3, 1009)


## The rooftop height of the buildings at (x, z): the ring round the town stands tallest and the
## houses on the plateau stand on it.
static func height_at(x: float, z: float) -> float:
	var plateau := UP if z < -9.0 else 0.0
	if x < -44.0 or x > 44.0 or z < -62.0 or z > 56.0:
		return 10.6 + plateau
	return HEIGHTS[_hash(tile_key(x, z)) % HEIGHTS.size()] + plateau


static func finish_at(x: float, z: float) -> String:
	if x < -44.0 or x > 44.0 or z < -62.0 or z > 56.0:
		return "adobe"
	return FINISHES[int(_hash(tile_key(x, z)) / 5.0) % FINISHES.size()]


## A walkable finish laid 2 cm proud of the sand (bots step 10 cm).
func pave(x1: float, x2: float, z1: float, z2: float, material: String) -> void:
	mass("floor", x1, x2, z1, z2, 0.05, material, -0.03)


## A door, window or lantern on a wall facing along Z ([param outward] +1 faces +Z, -1 faces -Z).
func opening(type: String, x: float, y: float, face_z: float, outward: float, size: Vector3,
		props: Dictionary = {}, material: String = "wood_dark") -> void:
	put(type, Vector3(x, y, face_z + outward * (size.z / 2.0 - 0.03)), size, 0.0 if outward > 0.0 else 180.0, props, material)


## The same for a wall facing along X ([param outward] +1 faces +X, -1 faces -X).
func opening_x(type: String, face_x: float, y: float, z: float, outward: float, size: Vector3,
		props: Dictionary = {}, material: String = "wood_dark") -> void:
	put(type, Vector3(face_x + outward * (size.z / 2.0 - 0.03), y, z), size, 90.0 if outward > 0.0 else -90.0, props, material)


## A crate stack: a big crate with a small one on top, offset so it can be peeked round.
func crates(x: float, z: float, yaw: float = 0.0, top: bool = true, y: float = 0.0) -> void:
	put("crate_large", Vector3(x, y, z), Vector3(2.0, 2.0, 2.0), yaw, {}, "planks")
	if top:
		var offset := Vector2(0.35, -0.3).rotated(deg_to_rad(-yaw))
		put("crate", Vector3(x + offset.x, y + 2.0, z + offset.y), Vector3(1.2, 1.2, 1.2), yaw + 12.0, {}, "weathered_wood")


## A date palm: a leaning trunk in short sections and a star of fronds, with a lower ring drooping.
func palm(at: Vector3) -> void:
	var lean := Vector2(0.18, 0.1).rotated(float(posmod(int(at.x * 7.0 + at.z * 3.0), 6)))
	var top := at.y
	for k: int in 5:
		var off := lean * float(k)
		put("column", Vector3(at.x + off.x, top, at.z + off.y), Vector3(0.42 - 0.03 * k, 1.3, 0.42 - 0.03 * k), 0.0, {}, "weathered_wood")
		top += 1.3
	var crown := Vector2(at.x, at.z) + lean * 5.0
	for ring: Array in [[top, 2.9, 0.0], [top - 0.35, 2.4, 22.5]]:
		var outline: Array = []
		for i: int in 16:
			var angle := deg_to_rad(float(ring[2]) + 22.5 * i)
			var radius: float = float(ring[1]) if i % 2 == 0 else 0.45
			outline.append(crown + Vector2(cos(angle), sin(angle)) * radius)
		prism(outline, float(ring[0]), 0.18, "foliage")


## A covered passage bridging a street between two houses, on beams, [param base] m up.
func sabat(x1: float, x2: float, z1: float, z2: float, base: float, finish: String) -> void:
	mass("building", x1, x2, z1, z2, 2.4, finish, base)
	mass("block", x1 - 0.15, x2 + 0.15, z1 - 0.15, z2 + 0.15, 0.3, "limestone", base + 2.4)
	var beams := 3
	for k: int in beams:
		var t := (float(k) + 0.5) / float(beams)
		if x2 - x1 < z2 - z1:
			put("block", Vector3(lerpf(x1, x2, t), base - 0.2, (z1 + z2) / 2.0), Vector3(0.22, 0.2, z2 - z1 + 0.3), 0.0, {}, "wood_dark")
		else:
			put("block", Vector3((x1 + x2) / 2.0, base - 0.2, lerpf(z1, z2, t)), Vector3(x2 - x1 + 0.3, 0.2, 0.22), 0.0, {}, "wood_dark")


# --- the town -----------------------------------------------------------------------------------

func _ground() -> void:
	layer("Ground")
	mass("floor_sand", BOUNDS.position.x, BOUNDS.end.x, BOUNDS.position.y, BOUNDS.end.y, 0.3, "sand", -0.3)
	pave(-41, -17, -31, -9, "limestone")                # Cistern Yard
	pave(-9, -3, 19, 37, "packed_earth")                # the cart track up mid
	pave(1, 7, -5, 17, "packed_earth")
	pave(31, 37, 26, 47, "cobblestone")                 # Spice Road, lower
	pave(35, 41, -1, 17, "cobblestone")                 # Spice Road, upper
	pave(-37, -31, -7, 46, "tile_terracotta")           # Souk
	layer("Plateau")
	for hole: Array in HOLES:
		if float(hole[6]) > 0.0:
			put("platform", Vector3((float(hole[1]) + float(hole[2])) / 2.0, 0, (float(hole[3]) + float(hole[4])) / 2.0),
				Vector3(float(hole[2]) - float(hole[1]), float(hole[6]), float(hole[4]) - float(hole[3])), 0.0, {}, str(hole[7]))


## Every grid cell outside HOLES is a building. Cells are cut at the hole edges and the tile
## lines, then merged greedily into the fewest boxes of one height and finish.
func _buildings() -> void:
	layer("Buildings")
	var xs: Array[float] = [BOUNDS.position.x, BOUNDS.end.x]
	var zs: Array[float] = [BOUNDS.position.y, BOUNDS.end.y]
	for hole: Array in HOLES:
		xs.append_array([float(hole[1]), float(hole[2])])
		zs.append_array([float(hole[3]), float(hole[4])])
	var line := BOUNDS.position.x + TILE
	while line < BOUNDS.end.x:
		xs.append(line)
		line += TILE
	line = BOUNDS.position.y + TILE
	while line < BOUNDS.end.y:
		zs.append(line)
		line += TILE
	xs.append_array([-44.0, 44.0])
	zs.append_array([-62.0, 56.0, -9.0])
	xs = _unique_sorted(xs)
	zs = _unique_sorted(zs)
	var solid: Dictionary[Vector2i, String] = {}
	for i: int in xs.size() - 1:
		for j: int in zs.size() - 1:
			var cx := (xs[i] + xs[i + 1]) / 2.0
			var cz := (zs[j] + zs[j + 1]) / 2.0
			if not is_open(cx, cz):
				solid[Vector2i(i, j)] = "%s|%.1f" % [finish_at(cx, cz), height_at(cx, cz)]
	var used: Dictionary[Vector2i, bool] = {}
	for j: int in zs.size() - 1:
		for i: int in xs.size() - 1:
			var start := Vector2i(i, j)
			if not solid.has(start) or used.has(start):
				continue
			var kind := solid[start]
			var i2 := i
			while solid.get(Vector2i(i2 + 1, j), "") == kind and not used.has(Vector2i(i2 + 1, j)):
				i2 += 1
			var j2 := j
			var grow := true
			while grow:
				for k: int in range(i, i2 + 1):
					var cell := Vector2i(k, j2 + 1)
					if solid.get(cell, "") != kind or used.has(cell):
						grow = false
						break
				if grow:
					j2 += 1
			for k: int in range(i, i2 + 1):
				for l: int in range(j, j2 + 1):
					used[Vector2i(k, l)] = true
			var parts := kind.split("|")
			_house(xs[i], xs[i2 + 1], zs[j], zs[j2 + 1], float(parts[1]), parts[0])


## One flat-roofed building; big ones get a set-back upper storey.
func _house(x1: float, x2: float, z1: float, z2: float, height: float, finish: String) -> void:
	mass("building", x1, x2, z1, z2, height, finish)
	var pick := _hash(tile_key(x1 + 0.5, z1 + 0.5)) + int(x1 * 3.0 + z2)
	if x2 - x1 >= 7.0 and z2 - z1 >= 7.0 and height < 13.0 and posmod(pick, 3) == 0:
		mass("building", x1 + 2.0, x2 - 2.0, z1 + 2.0, z2 - 2.0, 2.6, "limewash" if finish != "limewash" else "adobe", height)
		mass("block", x1 + 1.85, x2 - 1.85, z1 + 1.85, z2 - 1.85, 0.25, "limestone", height + 2.6)


static func _unique_sorted(values: Array[float]) -> Array[float]:
	values.sort()
	var result: Array[float] = []
	for value: float in values:
		if result.is_empty() or value - result[-1] > 0.01:
			result.append(value)
	return result


## Walks every edge of every decorated hole in 1 m steps and dresses the runs of wall behind it.
func _facades() -> void:
	layer("Facades")
	for hole: Array in HOLES:
		if not bool(hole[5]):
			continue
		var x1 := float(hole[1])
		var x2 := float(hole[2])
		var z1 := float(hole[3])
		var z2 := float(hole[4])
		var level := float(hole[6])
		# [start, along, facing]: the wall lies beyond the edge, against the facing direction.
		_edge(Vector2(x1, z1), Vector2(1, 0), Vector2(0, 1), x2 - x1, level)    # north edge, wall faces +Z
		_edge(Vector2(x1, z2), Vector2(1, 0), Vector2(0, -1), x2 - x1, level)   # south edge, faces -Z
		_edge(Vector2(x1, z1), Vector2(0, 1), Vector2(1, 0), z2 - z1, level)    # west edge, faces +X
		_edge(Vector2(x2, z1), Vector2(0, 1), Vector2(-1, 0), z2 - z1, level)   # east edge, faces -X


func _edge(start: Vector2, along: Vector2, facing: Vector2, length: float, level: float) -> void:
	var run_start := -1.0
	var run_key := Vector2i(-999, -999)
	var steps := int(round(length))
	for s: int in steps + 1:
		var key := Vector2i(-999, -999)
		if s < steps:
			var at := start + along * (float(s) + 0.5)
			var behind := at - facing * 0.3
			var front := at + facing * 0.3
			var here := hole_at(front.x, front.y)
			if not here.is_empty() and is_equal_approx(float(here[6]), level) and not is_open(behind.x, behind.y) \
					and BOUNDS.has_point(behind):
				key = tile_key(behind.x, behind.y)
		if key != run_key:
			if run_start >= 0.0:
				_wall_run(start + along * run_start, along, facing, float(s) - run_start, level)
			run_start = float(s) if key != Vector2i(-999, -999) else -1.0
			run_key = key


## Dresses one straight run of wall of one building: plinth, cornice, windows, a door, beam ends
## and now and then a lantern, all from the street's [param level] up.
func _wall_run(from: Vector2, along: Vector2, facing: Vector2, length: float, level: float) -> void:
	if length < 1.5:
		return
	var probe := from + along * (length / 2.0) - facing * 0.3
	var height := height_at(probe.x, probe.y)
	var pick := _hash(tile_key(probe.x, probe.y)) + int(absf(from.x) * 5.0 + absf(from.y) * 3.0)
	var door_at := -1.0
	if length >= 5.0 and posmod(pick, 2) == 0:
		door_at = snappedf(length * (0.3 + 0.4 * float(posmod(pick, 7)) / 6.0), 0.5)
	# Plinth (left open where the door is) and cornice.
	var cuts: Array[Vector2] = []
	if door_at > 0.0:
		cuts = [Vector2(0.0, door_at - 0.8), Vector2(door_at + 0.8, length)]
	else:
		cuts = [Vector2(0.0, length)]
	for cut: Vector2 in cuts:
		if cut.y - cut.x >= 0.3:
			_strip(from, along, facing, cut.x, cut.y, level, 0.55, 0.12, "sandstone")
	_strip(from, along, facing, 0.0, length, height - 0.4, 0.4, 0.22, "limestone")
	# Shuttered windows: one row, two on tall walls.
	var spot := 2.0
	while spot <= length - 1.5:
		if posmod(pick + int(spot), 4) == 1:
			_lit_window(from, along, facing, spot, level + 2.9)
		elif posmod(pick + int(spot), 5) != 0:
			_fixture("window", from, along, facing, spot, level + 2.9, Vector3(1.1, 1.5, 0.3),
				{"panes_x": 2, "panes_y": 2, "shutters": true}, "weathered_wood" if posmod(pick, 3) == 0 else "wood_dark")
		if height - level >= 8.0 and posmod(pick + int(spot), 3) != 0:
			_fixture("window", from, along, facing, spot, level + 5.4, Vector3(1.0, 1.3, 0.3),
				{"panes_x": 2, "panes_y": 2, "shutters": true}, "wood_dark")
		spot += 4.5
	if door_at > 0.0:
		_fixture("door", from, along, facing, door_at, level, Vector3(1.3, 2.5, 0.3),
			{"panels": 2, "fanlight": false}, "cloth_blue" if posmod(pick, 4) == 1 else "wood_dark")
		_lanterns += 1
		_fixture("lamp_wall", from, along, facing, door_at + 1.1, level + 2.3, Vector3(0.36, 0.8, 0.5), {}, "metal_dark")
	# A lantern every 9 m along long walls, between the doors.
	var post := 4.5
	while post <= length - 2.0:
		if door_at < 0.0 or absf(post - door_at) > 3.0:
			_lanterns += 1
			_fixture("lamp_wall", from, along, facing, post + 0.6, level + 2.6, Vector3(0.36, 0.8, 0.5),
				{"energy": 1.3, "range": 7.5}, "metal_dark")
		post += 9.0
	# Timber beam ends under the roofline.
	if posmod(pick, 3) == 0 and length >= 3.0:
		var beam := 0.8
		while beam <= length - 0.6:
			var at := from + along * beam + facing * 0.3
			put("block", Vector3(at.x, height - 1.15, at.y),
				Vector3(0.18, 0.18, 0.6) if absf(facing.y) > 0.5 else Vector3(0.6, 0.18, 0.18), 0.0, {}, "wood_dark")
			beam += 1.4


## A window lit from inside: a glowing pane in a timber frame, shutters folded back.
func _lit_window(from: Vector2, along: Vector2, facing: Vector2, t: float, y: float) -> void:
	_strip(from, along, facing, t - 0.45, t + 0.45, y + 0.1, 1.25, 0.05, "lamp_glass")
	_strip(from, along, facing, t - 0.55, t + 0.55, y, 0.1, 0.16, "limestone")
	_strip(from, along, facing, t - 0.55, t + 0.55, y + 1.35, 0.12, 0.12, "wood_dark")
	for side: float in [-1.0, 1.0]:
		_strip(from, along, facing, t + side * 0.5 - 0.05, t + side * 0.5 + 0.05, y + 0.1, 1.25, 0.1, "wood_dark")
		_strip(from, along, facing, t + side * 0.8 - 0.22, t + side * 0.8 + 0.22, y + 0.12, 1.2, 0.06, "weathered_wood")


## A thin band along a run, [param depth] proud of the wall.
func _strip(from: Vector2, along: Vector2, facing: Vector2, t1: float, t2: float, base: float,
		height: float, depth: float, material: String) -> void:
	var centre := from + along * ((t1 + t2) / 2.0) + facing * (depth / 2.0)
	var length := t2 - t1
	var size := Vector3(length, height, depth) if absf(along.x) > 0.5 else Vector3(depth, height, length)
	put("block", Vector3(centre.x, base, centre.y), size, 0.0, {}, material)


func _fixture(type: String, from: Vector2, along: Vector2, facing: Vector2, t: float, y: float, size: Vector3,
		props: Dictionary, material: String) -> void:
	var at := from + along * t
	if absf(facing.y) > 0.5:
		opening(type, at.x, y, at.y, facing.y, size, props, material)
	else:
		opening_x(type, at.x, y, at.y, facing.x, size, props, material)


# --- landmarks: doors, arches, stairs -------------------------------------------------------------

func _landmarks() -> void:
	layer("Landmarks")
	# Stairs between the low town and the plateau (3 m over 8 m, about 21°).
	put("stairs_stone", Vector3(38, 0, -6), Vector3(8, UP, 8), 0.0, {}, "sandstone")      # Spice Steps
	put("stairs_stone", Vector3(12, 0, -3), Vector3(6, UP, 8), -90.0, {}, "sandstone")    # Balcony Steps
	put("stairs_stone", Vector3(-4, 0, -16), Vector3(8, UP, 8), 0.0, {}, "sandstone")     # Mid Steps
	put("stairs_stone", Vector3(-26, 0, -42), Vector3(8, UP, 8), 0.0, {}, "sandstone")    # Garrison Steps
	# The Spice Arch at the top of the long route, and the Souk Arch into B.
	put("arch", Vector3(38, UP, -13.6), Vector3(8, 6.4, 0.8), 0.0, {"opening_width": 4.2, "opening_height": 3.2}, "sandstone")
	put("arch", Vector3(-34, 0, -8.4), Vector3(8, 6.4, 0.8), 0.0, {"opening_width": 4.6, "opening_height": 3.2}, "sandstone")
	# The Lantern Door: a narrow doorway into B.
	put("doorway", Vector3(-17, 0, -8.4), Vector3(6, 5.6, 0.7), 0.0, {"opening_width": 2.4, "opening_height": 2.8}, "adobe")
	# The defenders' gates: an arch onto the court and one at the foot of the Garrison Steps.
	put("arch", Vector3(26, UP, -40.6), Vector3(8, 6.6, 0.8), 0.0, {"opening_width": 5.0, "opening_height": 3.4}, "sandstone")
	put("arch", Vector3(-26, 0, -35), Vector3(8, 6.6, 0.8), 0.0, {"opening_width": 4.4, "opening_height": 3.2}, "sandstone")
	# The Mid Doors at the foot of the Mid Steps and the Spice Doors: heavy double doors, swung open.
	put("double_door", Vector3(-4, 0, -11.6), Vector3(8, 5.4, 0.7), 0.0,
		{"opening_width": 3.2, "opening_height": 3.2, "left_swing": 100.0, "right_swing": 70.0}, "adobe")
	put("double_door", Vector3(34, 0, 34), Vector3(8, 5.4, 0.7), 0.0,
		{"opening_width": 3.4, "opening_height": 3.2, "left_swing": 80.0, "right_swing": 105.0}, "adobe")
	# Lower Mid's arch from the Caravanserai.
	put("arch", Vector3(-6, 0, 33), Vector3(8, 6.4, 0.8), 0.0, {"opening_width": 4.6, "opening_height": 3.4}, "sandstone")
	# Covered passages over the lanes.
	sabat(34, 42, 6, 9.5, 4.2, "limewash")
	sabat(18, 22, 12, 16, 3.8, "adobe")
	sabat(-38, -30, 0, 3, 4.6, "plaster_ochre")
	sabat(-8, 0, -34, -30, UP + 4.4, "limewash")
	# The Balcony: a parapet along its open side and an awning over the steps.
	put("wall_parapet", Vector3(21.8, UP, -5.0), Vector3(6.0, 1.0, 0.4), 90.0, {}, "sandstone")
	put("awning", Vector3(19, UP, -0.9), Vector3(5.5, 2.8, 1.8), 180.0, {}, "cloth_striped")


# --- the sites ----------------------------------------------------------------------------------

## A: Dyers' Court, a flagged courtyard on the plateau with a cistern, dye vats and crate cover.
func _court_a() -> void:
	layer("Cover")
	crates(28.5, -26.0, 0.0, true, UP)                   # the plant box
	crates(34.5, -31.5, 8.0, true, UP)
	put("crate", Vector3(36.0, UP, -29.8), Vector3(1.2, 1.2, 1.2), -6.0, {}, "planks")
	put("wall_half", Vector3(23.0, UP, -33.5), Vector3(5.0, 1.15, 0.5), 0.0, {}, "adobe")
	put("vehicle_truck", Vector3(39.0, UP, -35.0), Vector3.ZERO, 8.0, {}, "metal_painted")
	put("well", Vector3(19.5, UP, -36.0), Vector3(3, 1.0, 3), 0.0, {}, "sandstone")
	put("crate_long", Vector3(29.0, UP, -15.6), Vector3(2.4, 1.0, 1.0), 0.0, {}, "planks")
	put("crate", Vector3(29.4, UP + 1.0, -15.6), Vector3(1.0, 1.0, 1.0), 20.0, {}, "weathered_wood")
	put("low_cover", Vector3(24.5, UP, -20.0), Vector3(3.0, 1.1, 0.5), 15.0, {}, "sandstone")
	layer("Props")
	for vat: Vector2 in [Vector2(40.6, -23.5), Vector2(40.6, -26.2)]:
		put("stone_trough", Vector3(vat.x, UP, vat.y), Vector3(1.9, 0.75, 1.2), 90.0, {}, "sandstone")
	palm(Vector3(17.5, UP, -39.0))
	palm(Vector3(41.0, UP, -16.0))
	put("awning", Vector3(41.0, UP, -25.0), Vector3(6.0, 2.9, 2.0), -90.0, {}, "cloth_red")
	for jar: Vector2 in [Vector2(16.8, -29.0), Vector2(16.8, -28.0), Vector2(17.6, -28.5)]:
		put("pottery_jar", Vector3(jar.x, UP, jar.y))


## B: Cistern Yard, down in the low town, with a raised stone terrace in its far corner.
func _yard_b() -> void:
	layer("Cover")
	put("platform", Vector3(-38, 0, -28), Vector3(8, 1.4, 8), 0.0, {}, "sandstone")
	put("stairs_stone", Vector3(-38, 0, -21.5), Vector3(4, 1.4, 5), 0.0, {}, "sandstone")
	put("wall_parapet", Vector3(-34.2, 1.4, -29.0), Vector3(5.0, 0.9, 0.4), 90.0, {}, "sandstone")
	crates(-32.0, -16.0, -10.0)                          # the plant box
	put("crate_stack", Vector3(-22.5, 0, -24.0), Vector3(2.4, 2.4, 1.2), 90.0, {}, "planks")
	put("crate_long", Vector3(-31.0, 0, -11.5), Vector3(2.4, 1.0, 1.0), 0.0, {}, "planks")
	put("crate_long", Vector3(-31.0, 1.0, -11.5), Vector3(2.4, 1.0, 1.0), 6.0, {}, "weathered_wood")
	put("low_cover", Vector3(-19.5, 0, -16.0), Vector3(3.0, 1.1, 0.5), 90.0, {}, "sandstone")
	put("vehicle_cart", Vector3(-17.4, 0, -29.5), Vector3.ZERO, 15.0, {}, "planks")
	layer("Props")
	put("barrel_cluster", Vector3(-40.8, 0, -9.8), Vector3(1.5, 1.0, 1.4), 0.0, {}, "metal_rust")
	palm(Vector3(-40.0, 1.4, -30.5))
	for jar: Vector2 in [Vector2(-41.2, -22.5), Vector2(-41.2, -21.6)]:
		put("pottery_jar", Vector3(jar.x, 0, jar.y))
	put("awning", Vector3(-41.0, 0, -14.0), Vector3(5.0, 2.9, 2.0), 90.0, {}, "cloth_blue")


# --- the lanes ----------------------------------------------------------------------------------

func _mid() -> void:
	layer("Cover")
	put("market_stall", Vector3(7.1, 0, 10.0), Vector3(3.0, 2.6, 1.6), -90.0, {}, "planks")
	put("vehicle_cart", Vector3(1.0, 0, 15.5), Vector3.ZERO, -8.0, {}, "planks")
	put("crate", Vector3(-9.0, 0, 30.0), Vector3(1.2, 1.2, 1.2), 10.0, {}, "planks")
	put("barrel_cluster", Vector3(-1.0, UP, -27.0), Vector3(1.5, 1.0, 1.4), 0.0, {}, "metal_rust")
	put("crate", Vector3(-7.0, UP, -38.0), Vector3(1.2, 1.2, 1.2), -15.0, {}, "weathered_wood")
	put("crate", Vector3(7.0, 0, -9.0), Vector3(1.2, 1.2, 1.2), 25.0, {}, "planks")
	layer("Props")
	put("banner", Vector3(0.1, 3.0, -1.0), Vector3(1.0, 2.4, 0.12), 90.0, {}, "cloth_red")
	put("banner", Vector3(7.9, 3.0, 4.0), Vector3(1.0, 2.4, 0.12), -90.0, {}, "cloth_blue")


## The long A route: Camel Yard, the Spice Doors, the dogleg at Spice Corner, the straight past
## the covered passage and the Spice Steps up to the arch — the map's sniper lane.
func _spice_road() -> void:
	layer("Cover")
	put("vehicle_cart", Vector3(31.4, 0, 21.2), Vector3.ZERO, 75.0, {}, "planks")
	crates(40.6, 21.0, 5.0, false)
	put("barrel_cluster", Vector3(35.2, 0, 3.0), Vector3(1.5, 1.0, 1.4), 0.0, {}, "metal_rust")
	put("sack_pile", Vector3(31.0, 0, 40.0), Vector3(1.6, 0.8, 1.1), 90.0, {}, "burlap")
	layer("Props")
	put("awning", Vector3(41.0, 0, 13.0), Vector3(5.0, 2.9, 2.0), -90.0, {}, "cloth_striped")
	put("awning", Vector3(30.9, 0, 29.0), Vector3(4.0, 2.9, 1.8), 90.0, {}, "cloth_red")
	for jar: Vector2 in [Vector2(41.3, 16.0), Vector2(41.3, 17.0)]:
		put("pottery_jar", Vector3(jar.x, 0, jar.y))


## The covered market on the long B route: stalls either side under a timber roof.
func _souk() -> void:
	layer("Souk")
	mass("roof", -38, -30, 14, 36, 0.35, "weathered_wood", 4.4)
	var beam := 14.5
	while beam < 36.0:
		put("block", Vector3(-34, 4.15, beam), Vector3(8, 0.25, 0.25), 0.0, {}, "wood_dark")
		beam += 2.5
	for stall: Array in [[-36.9, 17.0, 90.0], [-31.1, 22.5, -90.0], [-36.9, 28.0, 90.0], [-31.1, 33.5, -90.0],
			[-36.9, 40.0, 90.0], [-31.1, 6.0, -90.0]]:
		put("market_stall", Vector3(float(stall[0]), 0, float(stall[1])), Vector3(3.0, 2.6, 1.6), float(stall[2]), {}, "planks")
	put("sack_pile", Vector3(-31.2, 0, 12.0), Vector3(1.6, 0.8, 1.1), 90.0, {}, "burlap")
	put("crate", Vector3(-36.9, 0, -1.0), Vector3(1.2, 1.2, 1.2), 12.0, {}, "planks")
	put("crate_long", Vector3(-31.0, 0, -4.5), Vector3(2.4, 1.0, 1.0), 90.0, {}, "planks")
	for hang: float in [17.0, 23.0, 29.0, 35.0]:
		put("lamp_hanging", Vector3(-34, 3.2, hang), Vector3(0.6, 0.9, 0.6), 0.0, {"energy": 1.1, "range": 7.0}, "brass")


func _side_lanes() -> void:
	layer("Props")
	# Potters Row: a kiln, fired jars and pallets.
	put("kiln", Vector3(-16.0, 0, 29.3), Vector3(2.2, 2.6, 1.4), 180.0, {}, "mud_brick")
	for jar: Vector2 in [Vector2(-24.0, 26.6), Vector2(-23.2, 26.6), Vector2(-12.0, 29.3)]:
		put("pottery_jar", Vector3(jar.x, 0, jar.y))
	put("pallet", Vector3(-27.0, 0, 29.2), Vector3(1.2, 0.15, 1.0), 0.0, {}, "weathered_wood")
	# Dye Lane: cloth hung to dry.
	put("cloth_screen", Vector3(13.0, 0, 15.6), Vector3(3.0, 2.6, 0.2), 0.0, {}, "cloth_red")
	put("cloth_screen", Vector3(26.0, 0, 12.4), Vector3(3.0, 2.6, 0.2), 0.0, {}, "cloth_blue")
	# Lantern Row and Lantern Passage.
	put("crate", Vector3(-10.0, 0, 7.2), Vector3(1.2, 1.2, 1.2), 0.0, {}, "planks")
	put("barrel_cluster", Vector3(-19.0, 0, -2.0), Vector3(1.5, 1.0, 1.4), 90.0, {}, "metal_rust")
	for lantern: Vector2 in [Vector2(-8.0, 5.0), Vector2(-17.0, 0.0)]:
		put("lamp_hanging", Vector3(lantern.x, 3.0, lantern.y), Vector3(0.6, 0.9, 0.6), 0.0, {}, "brass")


func _spawn_yards() -> void:
	layer("Props")
	# The Caravanserai: carts and loads waiting to leave.
	put("vehicle_truck", Vector3(-17.0, 0, 50.0), Vector3.ZERO, 90.0, {}, "metal_painted")
	put("vehicle_cart", Vector3(5.5, 0, 51.0), Vector3.ZERO, 0.0, {}, "planks")
	crates(5.5, 41.0, 0.0)
	put("well", Vector3(-6, 0, 52.0), Vector3(3, 1.0, 3), 0.0, {}, "sandstone")
	put("sack_pile", Vector3(-18.6, 0, 40.0), Vector3(1.6, 0.8, 1.1), 90.0, {}, "burlap")
	palm(Vector3(-35.5, 0, 46.0))
	palm(Vector3(36.0, 0, 46.0))
	# The Garrison, up on the plateau: supply crates and a truck by the gate.
	put("vehicle_truck", Vector3(8.5, UP, -56.0), Vector3.ZERO, 0.0, {}, "metal_painted")
	crates(-13.0, -57.0, 0.0, true, UP)
	put("crate_stack", Vector3(-13.6, UP, -48.5), Vector3(2.4, 2.4, 1.2), 90.0, {}, "planks")
	palm(Vector3(-2.0, UP, -58.5))


## A string of bulbs from [param a] to [param b], sagging [param sag] m in the middle, with a
## soft light every 8 m or so.
func bulbs(a: Vector3, b: Vector3, sag: float = 0.6) -> void:
	var length := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var count := maxi(2, int(length / 1.2))
	for i: int in count + 1:
		var t := float(i) / float(count)
		var at := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		put("block", at, Vector3(0.12, 0.14, 0.12), 0.0, {}, "lamp_glass")
	var lights := maxi(1, int(round(length / 8.0)))
	for k: int in lights:
		var t := (float(k) + 0.5) / float(lights)
		lamp(a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t) + 0.3, 0), 0.9, 7.0, "ffcf8a")


## Zig-zag strings of bulbs over a street from x1..x2 (or z1..z2 when [param along_z]).
func zigzag(x1: float, x2: float, z1: float, z2: float, y: float, step: float, along_z: bool) -> void:
	if along_z:
		var z := z1
		var west := true
		while z + step <= z2 + 0.01:
			var xa := x1 + 0.3 if west else x2 - 0.3
			var xb := x2 - 0.3 if west else x1 + 0.3
			bulbs(Vector3(xa, y, z), Vector3(xb, y, z + step), 0.45)
			west = not west
			z += step
	else:
		var x := x1
		var north := true
		while x + step <= x2 + 0.01:
			var za := z1 + 0.3 if north else z2 - 0.3
			var zb := z2 - 0.3 if north else z1 + 0.3
			bulbs(Vector3(x, y, za), Vector3(x + step, y, zb), 0.45)
			north = not north
			x += step


func _lights() -> void:
	layer("Lights")
	# Strings of bulbs over the streets, yards and both sites.
	zigzag(0, 8, -4, 16, 4.4, 5.0, true)                 # Caravan Street
	zigzag(-10, -2, 24, 32, 4.4, 4.0, true)              # Lower Mid
	zigzag(34, 42, -2, 6, 4.0, 4.0, true)                # Spice Road, either side of the passage
	zigzag(34, 42, 10, 18, 4.4, 4.0, true)
	zigzag(30, 38, 24, 32, 4.4, 4.0, true)               # Spice Doors
	zigzag(10, 38, 38, 48, 4.8, 7.0, false)              # Camel Yard
	zigzag(-18, 6, 38, 54, 5.0, 6.0, false)              # Caravanserai
	zigzag(-38, -22, 38, 48, 4.8, 8.0, false)            # West Yard
	zigzag(-30, -10, 26, 30, 4.2, 5.0, false)            # Potters Row
	zigzag(10, 18, 12, 16, 3.6, 4.0, false)              # Dye Lane, either side of the passage
	zigzag(22, 34, 12, 16, 4.2, 6.0, false)
	zigzag(-16, 0, 2, 8, 4.2, 4.0, false)                # Lantern Row
	zigzag(-14, 10, -60, -46, UP + 5.0, 6.0, false)      # Garrison
	zigzag(-8, 0, -44, -22, UP + 3.8, 5.5, true)         # Top Mid
	bulbs(Vector3(16.3, UP + 5.2, -39.7), Vector3(41.7, UP + 5.2, -14.3), 1.4)     # over Dyers' Court
	bulbs(Vector3(16.3, UP + 5.2, -14.3), Vector3(41.7, UP + 5.2, -39.7), 1.4)
	bulbs(Vector3(29.0, UP + 5.2, -39.7), Vector3(29.0, UP + 5.2, -14.3), 1.0)
	bulbs(Vector3(-41.7, 5.0, -31.7), Vector3(-16.3, 5.0, -8.3), 1.4)             # over Cistern Yard
	bulbs(Vector3(-41.7, 5.0, -8.3), Vector3(-16.3, 5.0, -31.7), 1.4)
	# Braziers on the sites and in the yards, clear of the routes.
	for fire: Vector3 in [Vector3(41.2, UP, -30.5), Vector3(41.0, UP, -39.0), Vector3(20.0, UP, -39.0),
			Vector3(-41.2, 0, -12.0), Vector3(-16.8, 0, -26.5), Vector3(-41.0, 1.4, -24.8),
			Vector3(-15.0, UP, -59.0), Vector3(11.0, UP, -47.0), Vector3(-19.0, 0, 53.0), Vector3(7.0, 0, 53.0),
			Vector3(41.0, 0, 23.0), Vector3(-9.2, 0, 37.0)]:
		put("brazier", fire, Vector3(0.8, 1.1, 0.8), 0.0, {}, "metal_dark")
	# Street lamps in the open yards.
	for post: Vector3 in [Vector3(-15.4, UP, -46.6), Vector3(11.4, UP, -59.4), Vector3(31.4, UP, -51.4),
			Vector3(-29.4, UP, -53.4), Vector3(16.6, UP, -24.0), Vector3(-41.4, 0, -16.0),
			Vector3(-19.4, 0, 38.6), Vector3(37.4, 0, 38.6), Vector3(-21.0, 0, 47.4), Vector3(-10.0, 0, 53.6)]:
		put("lamp_post", post, Vector3(0.5, 3.8, 0.5), 0.0, {}, "metal_dark")
	# Lamps hung under the arches and the covered passages.
	for hang: Vector3 in [Vector3(38, UP + 4.2, -13.6), Vector3(-34, 4.2, -8.4), Vector3(26, UP + 4.4, -40.6),
			Vector3(-26, 4.2, -35), Vector3(-6, 4.4, 33), Vector3(38, 3.2, 7.75), Vector3(20, 2.8, 14),
			Vector3(-34, 3.6, 1.5), Vector3(-4, UP + 3.4, -32)]:
		put("lamp_hanging", hang, Vector3(0.5, 0.8, 0.5), 0.0, {}, "brass")
	lamp(Vector3(-17, 3.0, -3), 1.4, 8.0, "ffc98a")
	lamp(Vector3(-8, 2.8, 5), 1.2, 7.0, "ffc98a")
	lamp(Vector3(19, UP + 3.0, -6), 1.2, 8.0, "ffd9a0")
	spot(Vector3(-4, UP + 4.5, -16), 2.4, 10.0, 60.0)


# --- gameplay -----------------------------------------------------------------------------------

func _gameplay() -> void:
	layer("Gameplay")
	spawns("attack", Vector3(-6, 0, 43), 0.0, Vector3(26, 3, 14))
	spawns("defence", Vector3(-2, UP, -56), 180.0, Vector3(26, 3, 8))
	put("bombsite", SITE_A, Vector3(14, 3, 12), 0.0, {"site": "A"})
	put("bombsite", SITE_B, Vector3(14, 3, 12), 0.0, {"site": "B"})


func _callouts() -> void:
	layer("Tactics")
	area("Garrison", -16, 12, -60, -46, "", UP)
	area("North Street", 12, 32, -52, -42, "", UP)
	area("A Gate", 22, 30, -42, -40, "", UP)
	area("Barracks Lane", -30, -16, -54, -46, "", UP)
	area("Garrison Steps", -30, -22, -46, -38)
	area("B Gate", -30, -22, -38, -32)
	area("Dyers' Court", 16, 42, -40, -14, "", UP)
	area("Spice Arch", 34, 42, -14, -10, "entrance_a", UP)
	area("Spice Steps", 34, 42, -10, -2)
	area("Spice Road", 34, 42, -2, 18)
	area("Spice Corner", 30, 42, 18, 24)
	area("Spice Doors", 30, 38, 24, 38)
	area("Camel Yard", 8, 38, 38, 48)
	area("Dye Lane", 8, 34, 12, 16)
	area("Balcony", 16, 22, -14, -8, "entrance_a", UP)
	area("Balcony Steps", 8, 16, -6, 0)
	area("Caravanserai", -20, 8, 38, 54)
	area("Lower Mid", -10, -2, 24, 38)
	area("Mid Bend", -10, 8, 18, 24)
	area("Caravan Street", 0, 8, -6, 18, "mid")
	area("Mid Doors", -8, 8, -12, -6)
	area("Mid Steps", -8, 0, -20, -12)
	area("Top Mid", -8, 0, -46, -20, "", UP)
	area("Potters Row", -30, -10, 26, 30)
	area("Lantern Row", -16, 0, 2, 8)
	area("Lantern Passage", -20, -14, -6, 2)
	area("Lantern Door", -20, -14, -10, -6, "entrance_b")
	area("Souk", -38, -30, -4, 38)
	area("Souk Arch", -38, -30, -10, -4, "entrance_b")
	area("West Yard", -38, -20, 38, 48)
	area("Cistern Yard", -42, -16, -32, -10)


func _tactical() -> void:
	layer("Tactics")
	var spice_arch := Vector3(38, UP, -12.5)
	var balcony := Vector3(19, UP, -15)
	var souk_arch := Vector3(-34, 0, -7)
	var lantern_door := Vector3(-17, 0, -7)
	anchor("Court plant box", "plant", Vector3(26.0, UP, -24.5))
	anchor("Court plant crates", "plant", Vector3(33.0, UP, -27.0))
	anchor("Yard plant box", "plant", Vector3(-26.0, 0, -17.0))
	anchor("Yard plant terrace", "plant", Vector3(-33.0, 0, -21.5))
	anchor("Spice Road hold", "default", Vector3(37, 0, 4))
	anchor("Lower Mid hold", "default", Vector3(-6, 0, 28))
	anchor("Souk hold", "default", Vector3(-34, 0, 8))
	anchor("Lantern Row hold", "default", Vector3(-12, 0, 5))
	anchor("Spice Arch smoke", "utility", spice_arch)
	anchor("Balcony smoke", "utility", Vector3(19, UP, -10))
	anchor("Souk Arch smoke", "utility", souk_arch)
	anchor("Lantern Door smoke", "utility", lantern_door)
	anchor("Mid Doors smoke", "utility", Vector3(-4, 0, -10))
	for hold: Array in [[Vector3(24, UP, -37), spice_arch, "A"], [Vector3(33, UP, -38.5), balcony, "A"],
			[Vector3(18, UP, -30), spice_arch, "A"], [Vector3(-38, 1.4, -29), lantern_door, "B"],
			[Vector3(-19, 0, -26), souk_arch, "B"], [Vector3(-26, 0, -30), lantern_door, "B"]]:
		hint("ai_hold", hold[0], face(hold[0], hold[1]), str(hold[2]))
	for cover: Array in [[Vector3(28.5, UP, -28.6), "A"], [Vector3(34.5, UP, -34.0), "A"],
			[Vector3(-32.0, 0, -18.6), "B"], [Vector3(-22.5, 0, -26.4), "B"]]:
		hint("ai_cover", cover[0], 180.0, str(cover[1]))
	hint("ai_angle", spice_arch, face(spice_arch, SITE_A), "A")
	hint("ai_angle", balcony, face(balcony, SITE_A), "A")
	hint("ai_angle", souk_arch, face(souk_arch, SITE_B), "B")
	hint("ai_angle", lantern_door, face(lantern_door, SITE_B), "B")


func _check(analysis: MapAnalysis) -> bool:
	var mid := analysis.path_length(Vector3(-6, 0, 40), Vector3(-4, UP, -40))
	var long_a := analysis.path_length(Vector3(34, 0, 44), Vector3(38, UP, -16))
	var souk := analysis.path_length(Vector3(-34, 0, 44), Vector3(-34, 0, -12))
	var short_a := analysis.path_length(Vector3(4, 0, -3), Vector3(20, UP, -24))
	var down_b := analysis.path_length(Vector3(-2, UP, -56), Vector3(-29, 0, -18))
	print("Mid: %.1f m; Spice Road: %.1f m; Souk: %.1f m; Balcony from mid to A: %.1f m; Garrison to B: %.1f m"
		% [mid, long_a, souk, short_a, down_b])
	if mid < 0.0 or long_a < 0.0 or souk < 0.0 or short_a < 0.0 or down_b < 0.0:
		printerr("A lane is blocked.")
		return false
	return analysis.issues.is_empty()
