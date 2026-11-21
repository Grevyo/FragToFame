extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Saffra": a sun-baked desert old town of sandstone,
## adobe and limewashed walls, built to the conventions of classic competitive defuse maps:
## three lanes, tight chokes with doors and arches, one long sightline, an elevated short route,
## a covered market, flat roofs with cornices and timber beam ends, and crate cover on the sites.
## The layout and every name are original.
##
## Attackers start in the Caravanserai to the south, defenders in the Garrison to the north.
## A, Dyers' Court (east): the long Spice Road with its doors and a dogleg ends at the Spice Arch;
## the short route climbs the Balcony Steps off mid onto the Balcony over the court.
## B, Cistern Yard (west): the covered Souk ends at the Souk Arch; Lantern Row leaves mid and
## turns up Lantern Passage to the Lantern Door. Mid is Caravan Street with the Mid Doors at its
## top. Potters Row and Dye Lane let attackers swap lanes on their own half.
##
## The town is the playable space cut out of solid blocks: HOLES lists the streets and yards and
## every other cell of the grid becomes a building, its height and finish set per 10 m tile so
## the roofline steps. Street-facing walls then get plinths, cornices, shuttered windows, doors,
## beam ends and lanterns.
##
## Bots climb at most 0.1 m and walk slopes up to about 24°, so stairs are long and floors flush.
##
## Run:  <godot> --headless --path <project> --script res://tools/author_saffra.gd
## (add `-- --dry-run` to validate and print timings without publishing).

const SITE_A: Vector3 = Vector3(28, 0, -24)
const SITE_B: Vector3 = Vector3(-28, 0, -24)
const BALCONY: float = 2.8
## The built-up block around the town.
const BOUNDS: Rect2 = Rect2(-50, -68, 100, 130)
const TILE: float = 10.0
## Open space: [name, x1, x2, z1, z2, decorate the walls around it].
const HOLES: Array = [
	["Garrison", -14, 14, -60, -44, true],
	["North Street", 12, 32, -52, -42, true],
	["A Gate", 20, 30, -42, -37, true],
	["Barracks Lane", -32, -12, -52, -42, true],
	["B Gate", -30, -20, -42, -37, true],
	["Dyers' Court", 14, 42, -38, -10, true],
	["Cistern Yard", -42, -14, -38, -10, true],
	["Top Mid", -4, 4, -44, -12, true],
	["Caravan Street", -4, 4, -12, 38, true],
	["Caravanserai", -14, 14, 36, 54, true],
	["Camel Yard", 14, 38, 38, 48, true],
	["Spice Lower", 30, 38, 18, 48, true],
	["Spice Road", 34, 42, -12, 24, true],
	["West Yard", -38, -14, 38, 48, true],
	["Souk", -38, -30, -12, 48, true],
	["Lantern Row", -22, -4, 4, 8, true],
	["Lantern Passage", -22, -18, -12, 8, true],
	["Balcony Steps", 4, 12, -8, -2, false],
	["Balcony", 12, 20, -14, -2, false],
	["Potters Row", -30, -4, 18, 22, true],
	["Dye Lane", 4, 30, 24, 28, true],
]
const HEIGHTS: Array[float] = [6.0, 6.8, 7.6, 8.4, 9.6]
const FINISHES: Array[String] = ["adobe", "limewash", "plaster_ochre", "limestone", "adobe", "limewash"]

var _lanterns: int = 0


func _official_id() -> String:
	return "map_f2f_saffra"


func _revision() -> int:
	return 1


func _build() -> void:
	controller.set_metadata("Saffra", "F2F official",
		"A sun-baked desert old town. A, Dyers' Court: down the long Spice Road through the Spice Doors to the Spice Arch, or up the Balcony Steps off mid. B, Cistern Yard: through the covered Souk to the Souk Arch, or along Lantern Row to the Lantern Door. Mid: Caravan Street up to the Mid Doors.")
	controller.set_lighting({"sun_yaw": 128.0, "sun_pitch": 52.0, "sun_energy": 1.35, "sun_color": "ffe6c0",
		"ambient_color": "c4b296", "ambient_energy": 0.74, "haze": 0.22})
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
	for hole: Array in HOLES:
		if x > float(hole[1]) and x < float(hole[2]) and z > float(hole[3]) and z < float(hole[4]):
			return true
	return false


## The 10 m tile a point is in; buildings in one tile share a height and finish.
static func tile_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - BOUNDS.position.x) / TILE), floori((z - BOUNDS.position.y) / TILE))


static func _hash(key: Vector2i) -> int:
	return posmod(key.x * 7 + key.y * 13 + key.x * key.y * 3, 1009)


## The rooftop height of the buildings at (x, z): the ring round the town stands tallest.
static func height_at(x: float, z: float) -> float:
	if x < -44.0 or x > 44.0 or z < -62.0 or z > 56.0:
		return 10.6
	return HEIGHTS[_hash(tile_key(x, z)) % HEIGHTS.size()]


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
func crates(x: float, z: float, yaw: float = 0.0, top: bool = true) -> void:
	put("crate_large", Vector3(x, 0, z), Vector3(2.0, 2.0, 2.0), yaw, {}, "planks")
	if top:
		var offset := Vector2(0.35, -0.3).rotated(deg_to_rad(-yaw))
		put("crate", Vector3(x + offset.x, 2.0, z + offset.y), Vector3(1.2, 1.2, 1.2), yaw + 12.0, {}, "weathered_wood")


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
	pave(-13, 13, -59, -45, "stone_paving")             # Garrison
	pave(16, 40, -36, -12, "stone_paving")                # Dyers' Court
	pave(-40, -16, -36, -12, "limestone")            # Cistern Yard
	pave(-3, 3, -43, 35, "packed_earth")                # the cart track up mid
	pave(31, 37, 26, 47, "cobblestone")                 # Spice Road, lower
	pave(35, 41, -10, 17, "cobblestone")                # Spice Road, upper
	pave(-37, -31, -10, 46, "tile_terracotta")          # Souk


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
	zs.append_array([-62.0, 56.0])
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


## One flat-roofed building; big ones get a set-back upper storey or a roof parapet.
func _house(x1: float, x2: float, z1: float, z2: float, height: float, finish: String) -> void:
	mass("building", x1, x2, z1, z2, height, finish)
	var w := x2 - x1
	var d := z2 - z1
	var pick := _hash(tile_key(x1 + 0.5, z1 + 0.5)) + int(x1 * 3.0 + z2)
	if w >= 7.0 and d >= 7.0 and height < 10.0 and posmod(pick, 3) == 0:
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
		# [start, along, facing]: the wall lies beyond the edge, against the facing direction.
		_edge(Vector2(x1, z1), Vector2(1, 0), Vector2(0, 1), x2 - x1)    # north edge, wall faces +Z
		_edge(Vector2(x1, z2), Vector2(1, 0), Vector2(0, -1), x2 - x1)   # south edge, faces -Z
		_edge(Vector2(x1, z1), Vector2(0, 1), Vector2(1, 0), z2 - z1)    # west edge, faces +X
		_edge(Vector2(x2, z1), Vector2(0, 1), Vector2(-1, 0), z2 - z1)   # east edge, faces -X


func _edge(start: Vector2, along: Vector2, facing: Vector2, length: float) -> void:
	var run_start := -1.0
	var run_key := Vector2i(-999, -999)
	var steps := int(round(length))
	for s: int in steps + 1:
		var key := Vector2i(-999, -999)
		if s < steps:
			var at := start + along * (float(s) + 0.5)
			var behind := at - facing * 0.3
			var front := at + facing * 0.3
			if is_open(front.x, front.y) and not is_open(behind.x, behind.y) and BOUNDS.has_point(behind):
				key = tile_key(behind.x, behind.y)
		if key != run_key:
			if run_start >= 0.0:
				_wall_run(start + along * run_start, along, facing, float(s) - run_start)
			run_start = float(s) if key != Vector2i(-999, -999) else -1.0
			run_key = key


## Dresses one straight run of wall of one building: plinth, cornice, windows, a door, beam ends
## and now and then a lantern.
func _wall_run(from: Vector2, along: Vector2, facing: Vector2, length: float) -> void:
	if length < 1.5:
		return
	var probe := from + along * (length / 2.0) - facing * 0.3
	var height := height_at(probe.x, probe.y)
	var pick := _hash(tile_key(probe.x, probe.y)) + int(absf(from.x) * 5.0 + absf(from.y) * 3.0)
	var yaw := 0.0 if facing.y > 0.5 else (180.0 if facing.y < -0.5 else (90.0 if facing.x > 0.5 else -90.0))
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
			_strip(from, along, facing, cut.x, cut.y, 0.0, 0.55, 0.12, "sandstone", yaw)
	_strip(from, along, facing, 0.0, length, height - 0.4, 0.4, 0.22, "limestone", yaw)
	# Shuttered windows on the upper storey.
	var spot := 2.0
	while spot <= length - 1.5:
		if posmod(pick + int(spot), 5) != 0:
			_fixture("window", from, along, facing, spot, 2.9, Vector3(1.1, 1.5, 0.3),
				{"panes_x": 2, "panes_y": 2, "shutters": true}, "weathered_wood" if posmod(pick, 3) == 0 else "wood_dark")
		if height >= 8.0 and posmod(pick + int(spot), 3) != 0:
			_fixture("window", from, along, facing, spot, 5.4, Vector3(1.0, 1.3, 0.3),
				{"panes_x": 2, "panes_y": 2, "shutters": true}, "wood_dark")
		spot += 4.5
	if door_at > 0.0:
		_fixture("door", from, along, facing, door_at, 0.0, Vector3(1.3, 2.5, 0.3),
			{"panels": 2, "fanlight": false}, "cloth_blue" if posmod(pick, 4) == 1 else "wood_dark")
		if _lanterns < 26 and posmod(pick, 3) == 1:
			_lanterns += 1
			_fixture("lamp_wall", from, along, facing, door_at + 1.1, 2.3, Vector3(0.36, 0.8, 0.5), {}, "metal_dark")
	# Timber beam ends under the roofline.
	if posmod(pick, 3) == 0 and length >= 3.0:
		var beam := 0.8
		while beam <= length - 0.6:
			var at := from + along * beam + facing * 0.3
			put("block", Vector3(at.x, height - 1.15, at.y),
				Vector3(0.18, 0.18, 0.6) if absf(facing.y) > 0.5 else Vector3(0.6, 0.18, 0.18), 0.0, {}, "wood_dark")
			beam += 1.4


## A thin band along a run, [param depth] proud of the wall.
func _strip(from: Vector2, along: Vector2, facing: Vector2, t1: float, t2: float, base: float,
		height: float, depth: float, material: String, _yaw: float) -> void:
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
	# The Spice Arch and the Souk Arch, the long routes' last chokes into each site.
	put("arch", Vector3(38, 0, -11), Vector3(8, 6.4, 0.9), 0.0, {"opening_width": 4.2, "opening_height": 3.2}, "sandstone")
	put("arch", Vector3(-34, 0, -11), Vector3(8, 6.4, 0.9), 0.0, {"opening_width": 4.2, "opening_height": 3.2}, "sandstone")
	# The Lantern Door: a narrow doorway into B.
	put("doorway", Vector3(-20, 0, -11), Vector3(4, 5.6, 0.7), 0.0, {"opening_width": 2.4, "opening_height": 2.8}, "adobe")
	# The defenders' gates into both sites.
	put("arch", Vector3(25, 0, -39.5), Vector3(10, 6.6, 0.9), 0.0, {"opening_width": 5.0, "opening_height": 3.4}, "sandstone")
	put("arch", Vector3(-25, 0, -39.5), Vector3(10, 6.6, 0.9), 0.0, {"opening_width": 5.0, "opening_height": 3.4}, "sandstone")
	# The Mid Doors and the Spice Doors: heavy double doors, swung open.
	put("double_door", Vector3(0, 0, -14), Vector3(8, 5.4, 0.7), 0.0,
		{"opening_width": 3.2, "opening_height": 3.2, "left_swing": 100.0, "right_swing": 70.0}, "adobe")
	put("double_door", Vector3(34, 0, 34), Vector3(8, 5.4, 0.7), 0.0,
		{"opening_width": 3.4, "opening_height": 3.2, "left_swing": 80.0, "right_swing": 105.0}, "adobe")
	# Covered passages over the lanes.
	sabat(34, 42, 6, 9.5, 4.2, "limewash")
	sabat(14, 18, 24, 28, 3.8, "adobe")
	sabat(-38, -30, 0, 3, 4.6, "plaster_ochre")
	sabat(-4, 4, -34, -30, 4.4, "limewash")
	# Lower mid's arch from the Caravanserai.
	put("arch", Vector3(0, 0, 31), Vector3(8, 6.4, 0.9), 0.0, {"opening_width": 4.6, "opening_height": 3.4}, "sandstone")
	# The Balcony: up the steps off mid, over the court, down a stair into it.
	put("platform", Vector3(16, 0, -8), Vector3(8, BALCONY, 12), 0.0, {}, "tile_terracotta")
	put("stairs_stone", Vector3(8, 0, -5), Vector3(6, BALCONY, 8), -90.0, {}, "sandstone")
	put("stairs_stone", Vector3(18.5, 0, -17.5), Vector3(3, BALCONY, 7), 180.0, {}, "sandstone")
	put("wall_parapet", Vector3(15.5, BALCONY, -13.8), Vector3(3, 1.0, 0.4), 0.0, {}, "sandstone")
	put("wall_parapet", Vector3(19.8, BALCONY, -12.2), Vector3(3.6, 1.0, 0.4), 90.0, {}, "sandstone")
	put("awning", Vector3(16, BALCONY, -3.2), Vector3(7.5, 2.8, 2.2), 180.0, {}, "cloth_striped")


# --- the sites ----------------------------------------------------------------------------------

## A: Dyers' Court, a flagged courtyard with a cistern, dye vats and crate cover.
func _court_a() -> void:
	layer("Cover")
	crates(27.5, -23.0)                                  # the plant box
	crates(33.5, -28.5, 8.0)
	put("crate", Vector3(35.0, 0, -26.8), Vector3(1.2, 1.2, 1.2), -6.0, {}, "planks")
	put("wall_half", Vector3(22.5, 0, -30.5), Vector3(5.0, 1.15, 0.5), 0.0, {}, "adobe")
	put("vehicle_truck", Vector3(38.6, 0, -31.5), Vector3.ZERO, 8.0, {}, "metal_painted")
	put("well", Vector3(19.5, 0, -32.0), Vector3(3, 1.0, 3), 0.0, {}, "sandstone")
	put("crate_long", Vector3(30.0, 0, -14.8), Vector3(2.4, 1.0, 1.0), 0.0, {}, "planks")
	put("crate", Vector3(30.4, 1.0, -14.8), Vector3(1.0, 1.0, 1.0), 20.0, {}, "weathered_wood")
	layer("Props")
	for vat: Vector2 in [Vector2(40.0, -20.5), Vector2(40.0, -23.2)]:
		put("stone_trough", Vector3(vat.x, 0, vat.y), Vector3(1.9, 0.75, 1.2), 90.0, {}, "sandstone")
	palm(Vector3(16.5, 0, -36.0))
	put("awning", Vector3(41.0, 0, -22.0), Vector3(6.0, 2.9, 2.0), -90.0, {}, "cloth_red")
	for jar: Vector2 in [Vector2(14.8, -26.0), Vector2(14.8, -25.0), Vector2(15.6, -25.5)]:
		put("pottery_jar", Vector3(jar.x, 0, jar.y))
	put("sack_pile", Vector3(24.5, 0, -11.0), Vector3(1.6, 0.8, 1.1), 0.0, {}, "burlap")


## B: Cistern Yard, with a raised stone terrace in its far corner.
func _yard_b() -> void:
	layer("Cover")
	put("platform", Vector3(-38, 0, -34), Vector3(8, 1.4, 8), 0.0, {}, "sandstone")
	put("stairs_stone", Vector3(-38, 0, -27.5), Vector3(4, 1.4, 5), 0.0, {}, "sandstone")
	put("wall_parapet", Vector3(-34.2, 1.4, -35.0), Vector3(5.0, 0.9, 0.4), 90.0, {}, "sandstone")
	crates(-27.5, -22.5, -10.0)                          # the plant box
	put("crate_stack", Vector3(-21.5, 0, -28.0), Vector3(2.4, 2.4, 1.2), 90.0, {}, "planks")
	put("crate_long", Vector3(-31.0, 0, -16.5), Vector3(2.4, 1.0, 1.0), 0.0, {}, "planks")
	put("crate_long", Vector3(-31.0, 1.0, -16.5), Vector3(2.4, 1.0, 1.0), 6.0, {}, "weathered_wood")
	put("low_cover", Vector3(-18.5, 0, -20.0), Vector3(3.0, 1.1, 0.5), 90.0, {}, "sandstone")
	put("vehicle_cart", Vector3(-16.4, 0, -33.5), Vector3.ZERO, 15.0, {}, "planks")
	layer("Props")
	put("barrel_cluster", Vector3(-40.8, 0, -14.2), Vector3(1.5, 1.0, 1.4), 0.0, {}, "metal_rust")
	put("well", Vector3(-24.0, 0, -35.5), Vector3(3, 1.0, 3), 0.0, {}, "sandstone")
	palm(Vector3(-40.0, 1.4, -36.4))
	for jar: Vector2 in [Vector2(-15.0, -12.2), Vector2(-15.8, -12.0), Vector2(-15.2, -13.0)]:
		put("pottery_jar", Vector3(jar.x, 0, jar.y))
	put("awning", Vector3(-24.0, 0, -37.0), Vector3(6.0, 2.9, 2.0), 0.0, {}, "cloth_blue")


# --- the lanes ----------------------------------------------------------------------------------

func _mid() -> void:
	layer("Cover")
	put("market_stall", Vector3(2.9, 0, 15.0), Vector3(3.0, 2.6, 1.6), -90.0, {}, "planks")
	put("vehicle_cart", Vector3(-2.9, 0, 4.0), Vector3.ZERO, -8.0, {}, "planks")
	put("crate", Vector3(-3.1, 0, 24.5), Vector3(1.2, 1.2, 1.2), 10.0, {}, "planks")
	put("barrel_cluster", Vector3(2.9, 0, -20.0), Vector3(1.5, 1.0, 1.4), 0.0, {}, "metal_rust")
	put("crate", Vector3(-3.0, 0, -26.0), Vector3(1.2, 1.2, 1.2), -15.0, {}, "weathered_wood")
	layer("Props")
	put("banner", Vector3(-3.9, 3.0, -2.0), Vector3(1.0, 2.4, 0.12), 90.0, {}, "cloth_red")
	put("banner", Vector3(3.9, 3.0, 10.0), Vector3(1.0, 2.4, 0.12), -90.0, {}, "cloth_blue")


## The long A route: Camel Yard, the Spice Doors, the dogleg at Spice Corner and the straight
## up to the arch — the map's sniper lane.
func _spice_road() -> void:
	layer("Cover")
	put("vehicle_cart", Vector3(31.4, 0, 21.2), Vector3.ZERO, 75.0, {}, "planks")
	crates(40.6, 21.0, 5.0, false)
	put("barrel_cluster", Vector3(35.2, 0, 2.0), Vector3(1.5, 1.0, 1.4), 0.0, {}, "metal_rust")
	put("crate", Vector3(41.0, 0, -6.0), Vector3(1.2, 1.2, 1.2), 0.0, {}, "planks")
	put("sack_pile", Vector3(31.0, 0, 40.0), Vector3(1.6, 0.8, 1.1), 90.0, {}, "burlap")
	layer("Props")
	put("awning", Vector3(41.0, 0, 10.0), Vector3(5.0, 2.9, 2.0), -90.0, {}, "cloth_striped")
	put("awning", Vector3(30.9, 0, 30.0), Vector3(4.0, 2.9, 1.8), 90.0, {}, "cloth_red")
	for jar: Vector2 in [Vector2(41.3, 13.0), Vector2(41.3, 14.0)]:
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
			[-36.9, 40.0, 90.0], [-31.1, 4.0, -90.0]]:
		put("market_stall", Vector3(float(stall[0]), 0, float(stall[1])), Vector3(3.0, 2.6, 1.6), float(stall[2]), {}, "planks")
	put("sack_pile", Vector3(-31.2, 0, 12.0), Vector3(1.6, 0.8, 1.1), 90.0, {}, "burlap")
	put("crate", Vector3(-36.9, 0, -4.0), Vector3(1.2, 1.2, 1.2), 12.0, {}, "planks")
	put("crate_long", Vector3(-31.0, 0, -7.5), Vector3(2.4, 1.0, 1.0), 90.0, {}, "planks")
	for hang: float in [17.0, 23.0, 29.0, 35.0]:
		put("lamp_hanging", Vector3(-34, 3.2, hang), Vector3(0.6, 0.9, 0.6), 0.0, {}, "brass")


func _side_lanes() -> void:
	layer("Props")
	# Potters Row: kiln-fired jars and pallets.
	put("kiln", Vector3(-16.0, 0, 21.3), Vector3(2.2, 2.6, 1.4), 180.0, {}, "mud_brick")
	for jar: Vector2 in [Vector2(-24.0, 18.6), Vector2(-23.2, 18.6), Vector2(-9.0, 21.3)]:
		put("pottery_jar", Vector3(jar.x, 0, jar.y))
	put("pallet", Vector3(-27.0, 0, 21.2), Vector3(1.2, 0.15, 1.0), 0.0, {}, "weathered_wood")
	# Dye Lane: cloth hung to dry.
	put("cloth_screen", Vector3(12.0, 0, 27.6), Vector3(3.0, 2.6, 0.2), 0.0, {}, "cloth_red")
	put("cloth_screen", Vector3(22.0, 0, 24.4), Vector3(3.0, 2.6, 0.2), 0.0, {}, "cloth_blue")
	# Lantern Row and Lantern Passage.
	put("crate", Vector3(-14.0, 0, 7.2), Vector3(1.2, 1.2, 1.2), 0.0, {}, "planks")
	put("barrel_cluster", Vector3(-18.8, 0, -4.0), Vector3(1.5, 1.0, 1.4), 90.0, {}, "metal_rust")
	for lantern: float in [-12.0, -20.0]:
		put("lamp_hanging", Vector3(lantern, 3.0, 6.0), Vector3(0.6, 0.9, 0.6), 0.0, {}, "brass")


func _spawn_yards() -> void:
	layer("Props")
	# The Caravanserai: carts and loads waiting to leave.
	put("vehicle_truck", Vector3(-10.0, 0, 50.0), Vector3.ZERO, 90.0, {}, "metal_painted")
	put("vehicle_cart", Vector3(10.5, 0, 51.0), Vector3.ZERO, 0.0, {}, "planks")
	crates(11.5, 40.0, 0.0)
	put("well", Vector3(0, 0, 52.0), Vector3(3, 1.0, 3), 0.0, {}, "sandstone")
	put("sack_pile", Vector3(-12.6, 0, 39.5), Vector3(1.6, 0.8, 1.1), 90.0, {}, "burlap")
	palm(Vector3(-35.5, 0, 46.0))
	palm(Vector3(36.0, 0, 46.0))
	# The Garrison: supply crates and a truck by the gate.
	put("vehicle_truck", Vector3(10.5, 0, -56.0), Vector3.ZERO, 0.0, {}, "metal_painted")
	crates(-11.5, -57.0, 0.0)
	put("crate_stack", Vector3(-11.8, 0, -47.0), Vector3(2.4, 2.4, 1.2), 90.0, {}, "planks")
	palm(Vector3(0, 0, -58.0))


func _lights() -> void:
	layer("Lights")
	for at: Vector3 in [Vector3(-34, 3.4, 20), Vector3(-34, 3.4, 32), Vector3(-34, 3.0, -2)]:
		lamp(at, 1.6, 9.0, "ffc98a")
	lamp(Vector3(-20, 3.0, -2), 1.4, 8.0, "ffc98a")
	lamp(Vector3(-13, 2.8, 6), 1.2, 7.0, "ffc98a")
	lamp(Vector3(16, 4.6, -6), 1.2, 8.0, "ffd9a0")
	spot(Vector3(0, 5.0, -16), 2.4, 9.0, 60.0)


# --- gameplay -----------------------------------------------------------------------------------

func _gameplay() -> void:
	layer("Gameplay")
	spawns("attack", Vector3(0, 0, 45), 0.0, Vector3(26, 3, 14))
	spawns("defence", Vector3(0, 0, -52), 180.0, Vector3(26, 3, 14))
	put("bombsite", SITE_A, Vector3(14, 3, 12), 0.0, {"site": "A"})
	put("bombsite", SITE_B, Vector3(14, 3, 12), 0.0, {"site": "B"})


func _callouts() -> void:
	layer("Tactics")
	area("Garrison", -14, 14, -60, -44)
	area("North Street", 12, 32, -52, -42)
	area("A Gate", 20, 30, -42, -38)
	area("Barracks Lane", -32, -12, -52, -42)
	area("B Gate", -30, -20, -42, -38)
	area("Dyers' Court", 14, 42, -38, -14)
	area("Spice Arch", 34, 42, -14, -10, "entrance_a")
	area("Balcony", 12, 20, -14, -6, "entrance_a", BALCONY)
	area("Balcony Steps", 4, 12, -8, -2)
	area("Spice Road", 34, 42, -10, 18)
	area("Spice Corner", 30, 42, 18, 24)
	area("Spice Doors", 30, 38, 24, 38)
	area("Camel Yard", 14, 38, 38, 48)
	area("Dye Lane", 4, 30, 24, 28)
	area("Caravanserai", -14, 14, 38, 54)
	area("Lower Mid", -4, 4, 24, 38)
	area("Caravan Street", -4, 4, -12, 24, "mid")
	area("Mid Doors", -4, 4, -16, -12)
	area("Top Mid", -4, 4, -44, -16)
	area("Potters Row", -30, -4, 18, 22)
	area("Lantern Row", -22, -4, 4, 8)
	area("Lantern Passage", -22, -18, -10, 4)
	area("Lantern Door", -22, -18, -14, -10, "entrance_b")
	area("Souk", -38, -30, -8, 38)
	area("Souk Arch", -38, -30, -14, -8, "entrance_b")
	area("West Yard", -38, -14, 38, 48)
	area("Cistern Yard", -42, -14, -38, -14)


func _tactical() -> void:
	layer("Tactics")
	var spice_arch := Vector3(38, 0, -11)
	var balcony := Vector3(18.5, 0, -20.5)
	var souk_arch := Vector3(-34, 0, -11)
	var lantern_door := Vector3(-20, 0, -11)
	anchor("Court plant box", "plant", SITE_A + Vector3(-1.5, 0, 1.8))
	anchor("Court plant truck", "plant", SITE_A + Vector3(5.5, 0, -2.0))
	anchor("Yard plant box", "plant", SITE_B + Vector3(1.6, 0, 3.4))
	anchor("Yard plant terrace", "plant", SITE_B + Vector3(-4.5, 0, -3.0))
	anchor("Spice Road hold", "default", Vector3(37, 0, 6))
	anchor("Lower mid hold", "default", Vector3(0, 0, 20))
	anchor("Souk hold", "default", Vector3(-34, 0, 8))
	anchor("Lantern Row hold", "default", Vector3(-12, 0, 6))
	anchor("Spice Arch smoke", "utility", spice_arch)
	anchor("Balcony smoke", "utility", Vector3(16, BALCONY, -10))
	anchor("Souk Arch smoke", "utility", souk_arch)
	anchor("Lantern Door smoke", "utility", lantern_door)
	anchor("Mid Doors smoke", "utility", Vector3(0, 0, -14))
	for hold: Array in [[Vector3(24, 0, -34), spice_arch, "A"], [Vector3(36, 0, -35), balcony, "A"],
			[Vector3(17, 0, -27), spice_arch, "A"], [Vector3(-38, 1.4, -34), lantern_door, "B"],
			[Vector3(-17, 0, -30), souk_arch, "B"], [Vector3(-25, 0, -34), lantern_door, "B"]]:
		hint("ai_hold", hold[0], face(hold[0], hold[1]), str(hold[2]))
	for cover: Array in [[Vector3(27.5, 0, -25.6), "A"], [Vector3(33.5, 0, -31.0), "A"],
			[Vector3(-27.5, 0, -25.0), "B"], [Vector3(-21.5, 0, -30.4), "B"]]:
		hint("ai_cover", cover[0], 180.0, str(cover[1]))
	hint("ai_angle", spice_arch, face(spice_arch, SITE_A), "A")
	hint("ai_angle", balcony, face(balcony, SITE_A), "A")
	hint("ai_angle", souk_arch, face(souk_arch, SITE_B), "B")
	hint("ai_angle", lantern_door, face(lantern_door, SITE_B), "B")


func _check(analysis: MapAnalysis) -> bool:
	var mid := analysis.path_length(Vector3(0, 0, 40), Vector3(0, 0, -40))
	var long_a := analysis.path_length(Vector3(34, 0, 44), Vector3(38, 0, -16))
	var souk := analysis.path_length(Vector3(-34, 0, 44), Vector3(-34, 0, -16))
	var short_a := analysis.path_length(Vector3(0, 0, -5), Vector3(20, 0, -24))
	print("Mid end to end: %.1f m; Spice Road: %.1f m; Souk: %.1f m; Balcony from mid to A: %.1f m"
		% [mid, long_a, souk, short_a])
	if mid < 0.0 or long_a < 0.0 or souk < 0.0 or short_a < 0.0:
		printerr("A lane is blocked.")
		return false
	return analysis.issues.is_empty()
