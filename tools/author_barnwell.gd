extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Barnwell": a 1950s English housing estate of
## red-brick semi-detached houses with rendered upper floors, tiled gable roofs and chimneys,
## gravel drives, privet hedges, panel fences and telegraph poles. The layout follows the
## owner's drawing: three lanes run north to south (the West Lane, Ashby Avenue in the middle and
## Fen Walk) from the defenders on Larch Road to the attackers on Marsh Lane in the south-east,
## with a block either side of the avenue. Every name is made up.
##
## Site A is the Green in the east block, entered by the West Gate off the avenue (short) or the
## Fen Gap off Fen Walk (long). Site B is the Lock-ups, a garage court in the west block, entered
## by the Ginnel Mouth off the avenue (short), the Chapel Gate at the top of Chapel Path, or
## Church Walk from the West Lane through the churchyard. Larch Alley and Garage Drive bring the
## defenders down from Larch Road.
##
## Bots cannot climb more than 0.1 m, so there are no kerbs: pavements sit 2 cm proud.
##
## Run:  <godot> --headless --path <project> --script res://tools/author_barnwell.gd
## (add `-- --dry-run` to validate and print timings without publishing).

const SITE_A: Vector3 = Vector3(29, 0, -12)
const SITE_B: Vector3 = Vector3(-27, 0, -11)
const WEST: float = -56.0
const EAST: float = 50.0
const FENCE: float = 1.85
const EAVE: float = 5.4
const RIDGE: float = 7.9
const DEPTH: float = 8.0
const PAVE_TOP: float = 0.02

## Houses facing the play space: [x1, x2, halves]. North row fronts on Larch Road at z -40,
## south row on Marsh Lane at z 42.
const NORTH_ROW: Array = [[-49.5, -38.5, 2], [-36.0, -25.0, 2], [-18.0, -11.0, 1],
	[19.5, 31.0, 2], [32.5, 43.5, 2]]
const SOUTH_ROW: Array = [[-48.5, -35.5, 2], [-24.5, -11.5, 2], [19.0, 30.5, 2], [32.0, 43.5, 2]]
## The rows across the two roads (backdrop, fronting the play space).
const FAR_ROW: Array = [[-55.0, -43.0, 2], [-40.0, -28.0, 2], [-25.0, -13.0, 2], [-10.0, 2.0, 2],
	[5.0, 17.0, 2], [20.0, 32.0, 2], [35.0, 47.0, 2]]


func _official_id() -> String:
	return "map_f2f_barnwell"


func _revision() -> int:
	return 1


func _build() -> void:
	controller.set_metadata("Barnwell", "F2F official",
		"A 1950s English housing estate with three lanes north to south: the West Lane, Ashby Avenue in the middle and Fen Walk. A: the Green, by the West Gate off the avenue or the Fen Gap off Fen Walk. B: the Lock-ups garage court, by the Ginnel Mouth off the avenue, Chapel Path or Church Walk from the West Lane.")
	controller.set_lighting({"sun_yaw": 205.0, "sun_pitch": 38.0, "sun_energy": 0.85, "sun_color": "f1eee6",
		"ambient_color": "aeb8c2", "ambient_energy": 0.78})
	_ground()
	_roads()
	_lanes()
	_houses()
	_gardens()
	_avenue()
	_lockups()
	_green()
	_chapel()
	_street_furniture()
	_curves()
	_barn_and_well()
	_props()
	_gameplay()
	_callouts()
	_tactical()


# --- helpers ------------------------------------------------------------------------------------

## A walkable surface 2 cm above the tarmac.
func pave(x1: float, x2: float, z1: float, z2: float, material: String, top: float = PAVE_TOP) -> void:
	mass("floor", x1, x2, z1, z2, top + 0.03, material, -0.03)


## Garden lawn out of play: a block (not a floor), so the analysis does not report it as an island.
func lawn(x1: float, x2: float, z1: float, z2: float, material: String = "grass_worn") -> void:
	mass("block", x1, x2, z1, z2, 0.05, material, -0.02)


func fence(x1: float, x2: float, z1: float, z2: float, material: String = "planks", height: float = FENCE) -> void:
	walls_around([Vector2(x1, z1), Vector2(x2, z1), Vector2(x2, z2), Vector2(x1, z2)], height, 0.0, material,
		{}, [], "wall", 0.12)


## A fenced back garden (and the house standing on its front edge).
func plot(x1: float, x2: float, z1: float, z2: float, material: String = "planks", height: float = FENCE) -> void:
	lawn(x1, x2, z1, z2)
	fence(x1, x2, z1, z2, material, height)


## The yaw that faces from [param from] toward [param to] (0 faces -Z).
static func face(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(-(to.x - from.x), -(to.z - from.z)))


## A gable roof over x1..x2 by z1..z2 drawn with the brush tool, its ridge along X (or Z).
func gable(x1: float, x2: float, z1: float, z2: float, eave: float, ridge: float, material: String,
		along_x: bool = true) -> void:
	var vertices: Array = [[x1, eave, z1], [x2, eave, z1], [x2, eave, z2], [x1, eave, z2]]
	var faces: Array = [0, 1, 2, 0, 2, 3]
	if along_x:
		var zm := (z1 + z2) / 2.0
		vertices.append_array([[x1, ridge, zm], [x2, ridge, zm]])
		faces.append_array([0, 4, 5, 0, 5, 1, 3, 2, 5, 3, 5, 4, 0, 3, 4, 1, 5, 2])
	else:
		var xm := (x1 + x2) / 2.0
		vertices.append_array([[xm, ridge, z1], [xm, ridge, z2]])
		faces.append_array([0, 4, 5, 0, 5, 3, 1, 2, 5, 1, 5, 4, 0, 1, 4, 3, 5, 2])
	if (studio.call("draw_brushes", [{"vertices": vertices, "faces": faces, "two_sided": true, "material": material}]) as Array).is_empty():
		printerr("Brush refused roof ", [x1, x2, z1, z2])


## A hipped roof over x1..x2 by z1..z2 (ridge along X, the ends sloping in as far as the sides).
func hip(x1: float, x2: float, z1: float, z2: float, eave: float, ridge: float, material: String) -> void:
	var zm := (z1 + z2) / 2.0
	var inset := minf((z2 - z1) / 2.0, (x2 - x1) / 2.0 - 0.1)
	var vertices: Array = [[x1, eave, z1], [x2, eave, z1], [x2, eave, z2], [x1, eave, z2],
		[x1 + inset, ridge, zm], [x2 - inset, ridge, zm]]
	var faces: Array = [0, 1, 2, 0, 2, 3, 0, 1, 5, 0, 5, 4, 3, 4, 5, 3, 5, 2, 0, 4, 3, 1, 2, 5]
	if (studio.call("draw_brushes", [{"vertices": vertices, "faces": faces, "two_sided": true, "material": material}]) as Array).is_empty():
		printerr("Brush refused hipped roof ", [x1, x2, z1, z2])


## Points round an arc (x/z plane), [param a0] to [param a1] degrees, 0 along +X, 90 along +Z.
static func arc(centre: Vector2, radius: float, a0: float, a1: float, steps: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i: int in steps + 1:
		var angle := deg_to_rad(lerpf(a0, a1, float(i) / steps))
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


## A round solid (planter, bed, trampoline, island) of [param radius] from [param base] up.
func disc(centre: Vector2, radius: float, base: float, height: float, material: String, steps: int = 16) -> void:
	var outline: Array = arc(centre, radius, 0.0, 360.0 - 360.0 / steps, steps - 1)
	prism(outline, base, height, material)


## A walkable path along [param points] (x/z), [param width] wide, drawn segment by segment with
## round joints, a centimetre above the ground it crosses.
func path(points: Array[Vector2], width: float, material: String, top: float = 0.03) -> void:
	for i: int in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var side := (b - a).normalized().orthogonal() * (width / 2.0)
		surface([a + side, b + side, b - side, a - side], top, 0.05, material)
	for i: int in range(1, points.size() - 1):
		var joint: Array = arc(points[i], width / 2.0, 0.0, 315.0, 7)
		surface(joint, top, 0.05, material)


## A quadratic curve from [param a] through the pull of [param control] to [param b].
static func curve(a: Vector2, control: Vector2, b: Vector2, steps: int = 8) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i: int in steps + 1:
		var t := float(i) / steps
		points.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return points


## A door or window set into a wall facing along Z: its glazed or panelled face outward
## ([param outward] +1 for +Z, -1 for -Z), just proud of the wall surface at [param face_z].
func opening(type: String, x: float, y: float, face_z: float, outward: float, size: Vector3, props: Dictionary = {}) -> void:
	put(type, Vector3(x, y, face_z + outward * (size.z / 2.0 - 0.03)), size, 0.0 if outward > 0.0 else 180.0, props, "wood_dark")


## The same for a wall facing along X ([param outward] +1 for +X, -1 for -X).
func opening_x(type: String, face_x: float, y: float, z: float, outward: float, size: Vector3, props: Dictionary = {}) -> void:
	put(type, Vector3(face_x + outward * (size.z / 2.0 - 0.03), y, z), size, 90.0 if outward > 0.0 else -90.0, props, "wood_dark")


## An angled bay window on a facade at [param face_z]: brick base, glazing and a slate cap.
func bay(x: float, face_z: float, outward: float) -> void:
	var o := outward
	var outline: Array = [Vector2(x - 1.25, face_z), Vector2(x + 1.25, face_z), Vector2(x + 0.85, face_z + o * 0.75),
		Vector2(x - 0.85, face_z + o * 0.75)]
	prism(outline, 0.0, 0.75, "red_brick")
	prism(outline, 0.75, 1.5, "glass")
	for corner: Vector2 in outline:
		put("pillar", Vector3(corner.x, 0.75, corner.y + o * 0.03), Vector3(0.09, 1.5, 0.09), 0.0, {}, "wood_dark")
	for along: float in [-0.42, 0.42]:
		put("pillar", Vector3(x + along, 0.75, face_z + o * 0.77), Vector3(0.07, 1.5, 0.07), 0.0, {}, "wood_dark")
	put("block", Vector3(x, 1.5, face_z + o * 0.77), Vector3(1.7, 0.06, 0.06), 0.0, {}, "wood_dark")
	var cap: Array = [Vector2(x - 1.4, face_z), Vector2(x + 1.4, face_z), Vector2(x + 0.95, face_z + o * 0.9),
		Vector2(x - 0.95, face_z + o * 0.9)]
	prism(cap, 2.25, 0.22, "slate")


## One house (two halves for a semi): brick ground floor, rendered upper floor, tiled gable or
## hipped roof, chimney with an aerial, drainpipes; per half a front door under a canopy, a bay
## or flat front window, upper windows, back windows and a wheelie bin. Every door and window
## faces out of the house. [param front] is the facade's z; the house runs [constant DEPTH] back
## from it, toward -Z when it faces south.
func house(x1: float, x2: float, front: float, faces_south: bool, halves: int) -> void:
	var back := front - DEPTH if faces_south else front + DEPTH
	var out_front := 1.0 if faces_south else -1.0
	var z1 := minf(front, back)
	var z2 := maxf(front, back)
	var style := posmod(int(roundf(x1 * 3.0 + front)), 4)
	mass("building", x1, x2, z1, z2, 2.8, "red_brick")
	mass("building", x1, x2, z1, z2, EAVE - 2.8, "render" if style != 3 else "red_brick", 2.8)
	if style % 2 == 0:
		hip(x1 - 0.3, x2 + 0.3, z1 - 0.35, z2 + 0.35, EAVE, RIDGE, "roof_tile")
	else:
		gable(x1 - 0.25, x2 + 0.25, z1 - 0.35, z2 + 0.35, EAVE, RIDGE, "roof_tile" if style != 3 else "slate")
	var stack_x := (x1 + x2) / 2.0 if halves == 2 else x1 + 1.4
	var stack_z := (z1 + z2) / 2.0
	put("block", Vector3(stack_x, 6.6, stack_z), Vector3(0.9 if halves == 1 else 1.4, 2.4, 0.8), 0.0, {}, "red_brick")
	put("pillar", Vector3(stack_x + 0.3, 9.0, stack_z), Vector3(0.06, 1.5, 0.06), 0.0, {}, "metal_dark")
	put("block", Vector3(stack_x + 0.3, 10.2, stack_z), Vector3(0.05, 0.05, 1.1), 0.0, {}, "metal_dark")
	for corner: float in [x1 + 0.08, x2 - 0.08]:
		put("pillar", Vector3(corner, 0, front + out_front * 0.08), Vector3(0.1, EAVE, 0.1), 0.0, {}, "metal_dark")
	var width := (x2 - x1) / halves
	var bins_colour: Array[String] = ["metal_painted", "metal_dark", "cloth_blue"]
	for i: int in halves:
		var hx := x1 + i * width
		var mirrored := i == 1
		var door_x := hx + width * (0.78 if mirrored else 0.22)
		var bay_x := hx + width * (0.38 if mirrored else 0.62)
		opening("door", door_x, 0.0, front, out_front, Vector3(1.0, 2.1, 0.26), {"fanlight": false})
		put("roof", Vector3(door_x, 2.3, front + out_front * 0.45), Vector3(1.6, 0.1, 0.9), 0.0, {}, "slate")
		if (style + i) % 3 != 2:
			bay(bay_x, front, out_front)
		else:
			opening("window", bay_x, 0.85, front, out_front, Vector3(1.9, 1.3, 0.3), {"panes_x": 3})
		for along: float in [0.27, 0.73]:
			opening("window", hx + width * along, 3.3, front, out_front, Vector3(1.2, 1.25, 0.3))
			opening("window", hx + width * along, 3.3, back, -out_front, Vector3(1.1, 1.2, 0.3))
		opening("window", hx + width * 0.5, 0.85, back, -out_front, Vector3(2.0, 1.3, 0.3), {"panes_x": 3})
		var bin_x := hx + (width - 0.5 if mirrored else 0.5)
		put("block", Vector3(bin_x, 0, front + out_front * 0.5), Vector3(0.6, 1.1, 0.7), 0.0, {},
			bins_colour[posmod(style + i, 3)])


## Front gardens between a low brick wall at [param wall_z] and the facades at [param house_z]:
## lawn, a gravel drive for each half, the wall open at the drives.
func front_gardens(x1: float, x2: float, wall_z: float, house_z: float, houses: Array) -> void:
	var z1 := minf(wall_z, house_z)
	var z2 := maxf(wall_z, house_z)
	pave(x1, x2, z1, z2, "grass_worn")
	var drives: Array[float] = []
	for entry: Array in houses:
		var hx1 := float(entry[0])
		var hx2 := float(entry[1])
		if hx1 < x1 - 0.01 or hx2 > x2 + 0.01:
			continue
		drives.append(hx1 + 1.6)
		if int(entry[2]) == 2:
			drives.append(hx2 - 1.6)
	drives.sort()
	var gaps: Array = []
	for drive: float in drives:
		pave(drive - 1.5, drive + 1.5, z1, z2, "gravel", PAVE_TOP + 0.01)
		gaps.append([maxf(drive - 1.5 - x1, 0.0), minf(drive + 1.5 - x1, x2 - x1)])
	wall_line(Vector2(x1, wall_z), Vector2(x2, wall_z), 0.75, 0.0, "red_brick", gaps, "wall", 0.25)


## A wooden telegraph pole with its cross-arm.
func pole(x: float, z: float) -> void:
	put("pillar", Vector3(x, 0, z), Vector3(0.26, 8.4, 0.26), 0.0, {}, "weathered_wood")
	put("block", Vector3(x, 7.9, z), Vector3(1.5, 0.12, 0.14), 0.0, {}, "weathered_wood")


## An overhead wire between two poles.
func wire(a: Vector2, b: Vector2, height: float = 7.95) -> void:
	var centre := (a + b) / 2.0
	var yaw := rad_to_deg(atan2(-(b.y - a.y), b.x - a.x))
	put("block", Vector3(centre.x, height, centre.y), Vector3(a.distance_to(b), 0.05, 0.05), yaw, {}, "metal_dark")


func shed(x: float, z: float, yaw: float = 0.0) -> void:
	put("block", Vector3(x, 0, z), Vector3(2.0, 2.1, 2.4), yaw, {}, "weathered_wood")
	put("roof", Vector3(x, 2.1, z), Vector3(2.3, 0.12, 2.7), yaw, {}, "slate")


func bins(x: float, z: float, yaw: float = 0.0) -> void:
	put("block", Vector3(x, 0, z), Vector3(0.6, 1.1, 0.7), yaw, {}, "metal_painted")


# --- the map ------------------------------------------------------------------------------------

func _ground() -> void:
	layer("Ground and boundary")
	mass("floor", WEST - 0.6, EAST + 0.6, -68, 68, 1.0, "tarmac", -1.0)
	mass("wall", WEST - 0.6, WEST, -68, 68, 3.2, "red_brick")
	mass("wall", EAST, EAST + 0.6, -68, 68, 3.2, "red_brick")


## Larch Road (z -56..-44) and Marsh Lane (z 45..57): pavements, centre lines, far-side houses.
func _roads() -> void:
	layer("Roads")
	pave(WEST, EAST, -56, -54, "concrete")
	pave(WEST, EAST, -46, -44, "concrete")
	pave(WEST, EAST, 45, 47, "concrete")
	pave(WEST, EAST, 55, 57, "concrete")
	var x := WEST + 2.0
	while x < EAST - 3.0:
		mass("floor", x, x + 2.5, -50.08, -49.92, 0.05, "plaster_white", -0.025)
		mass("floor", x, x + 2.5, 50.92, 51.08, 0.05, "plaster_white", -0.025)
		x += 6.0
	# The far side of both roads: front gardens and houses facing the estate.
	front_gardens(WEST, EAST, -56, -59.5, FAR_ROW)
	front_gardens(WEST, EAST, 57, 59.5, FAR_ROW)
	lawn(WEST, EAST, -68, -59.5)
	lawn(WEST, EAST, 59.5, 68)
	layer("Houses")
	for entry: Array in FAR_ROW:
		house(float(entry[0]), float(entry[1]), -59.5, true, int(entry[2]))
		house(float(entry[0]), float(entry[1]), 59.5, false, int(entry[2]))
	# A fence 1 m behind each far facade line closes the gaps between houses.
	wall_line(Vector2(WEST, -60.5), Vector2(EAST, -60.5), 2.2, 0.0, "planks", [], "wall", 0.12)
	wall_line(Vector2(WEST, 60.5), Vector2(EAST, 60.5), 2.2, 0.0, "planks", [], "wall", 0.12)


## The three lanes north to south (the owner's black lines): the West Lane, Ashby Avenue in the
## middle and Fen Walk; and the alleys, paths and the two sites.
func _lanes() -> void:
	layer("Lanes")
	# Ashby Avenue: the main lane, carriageway x -5..5 with pavements and grass verges.
	pave(-7, -5, -44, 45, "concrete")
	pave(5, 7, -44, 45, "concrete")
	pave(-10, -7, -44, 45, "grass_worn")
	pave(7, 10, -44, 45, "grass_worn")
	var z := -42.0
	while z < 43.0:
		if z + 2.5 < 12.0 or z > 16.0:
			mass("floor", -0.08, 0.08, z, z + 2.5, 0.05, "plaster_white", -0.025)
		z += 6.0
	pave(WEST, -51, -44, 45, "grass_worn")     # West Lane (a gravel path winds along it)
	pave(-51, -41, -10, -4, "flagstones")      # Church Walk
	pave(-23, -19, -44, -26, "concrete")       # Garage Drive
	pave(15, 19, -44, -26, "flagstones")       # Larch Alley
	pave(44, EAST, -44, 45, "grass_worn")      # Fen Walk (a dirt path winds along it)
	pave(-41, -10, 22, 27, "gravel")           # Back Lane (west)
	pave(10, 44, 22, 27, "gravel")             # Garage Row (east)
	pave(-32, -27, 2, 22, "flagstones")        # Chapel Path
	pave(-32, -27, 27, 45, "flagstones")
	pave(14, 18, 27, 45, "flagstones")         # Kennel Ginnel
	pave(-41, -11, -26, 2, "concrete")         # the Lock-ups court
	pave(11, 43, -26, 2, "grass_worn")         # the Green
	pave(10, 15, -44, -40, "concrete")         # the corner shop's forecourt
	pave(10, 14, 42, 45, "concrete")           # the garage forecourt
	for gap: Array in [[-11, -10, -26, -24], [-11, -10, -6, -1], [10, 11, -26, -24], [10, 11, -11, -6], [43, 44, -16, -10]]:
		pave(gap[0], gap[1], gap[2], gap[3], "flagstones")
	# Hedges between the avenue's verges and the sites, open at the gaps.
	layer("Hedges")
	for hedge: Array in [[-11, -10, -24, -6], [-11, -10, -1, 2], [10, 11, -24, -11], [10, 11, -6, 2],
			[43, 44, -26, -16], [43, 44, -10, 2]]:
		mass("block", hedge[0], hedge[1], hedge[2], hedge[3], 2.1, "hedge")


func _houses() -> void:
	layer("Houses")
	for entry: Array in NORTH_ROW:
		house(float(entry[0]), float(entry[1]), -40.0, false, int(entry[2]))
	for entry: Array in SOUTH_ROW:
		house(float(entry[0]), float(entry[1]), 42.0, true, int(entry[2]))
	for segment: Array in [[-51.0, -23.0], [-19.0, -10.0], [19.0, 44.0]]:
		front_gardens(float(segment[0]), float(segment[1]), -44, -40, NORTH_ROW)
	for segment: Array in [[-51.0, -32.0], [-27.0, -10.0], [18.0, 44.0]]:
		front_gardens(float(segment[0]), float(segment[1]), 45, 42, SOUTH_ROW)
	# The corner shop on Larch Road and the avenue: single storey, flat roof, shop window.
	mass("building", 10.5, 14.6, -40, -32, 3.4, "red_brick")
	put("roof", Vector3(12.55, 3.4, -36), Vector3(4.5, 0.2, 8.4), 0.0, {}, "slate")
	opening("window", 12.8, 0.6, -40, -1.0, Vector3(2.6, 1.8, 0.3), {"panes_x": 3, "panes_y": 1})
	opening_x("door", 10.5, 0.0, -38.2, -1.0, Vector3(1.0, 2.1, 0.26), {"fanlight": false})
	put("roof", Vector3(12.55, 2.45, -40.6), Vector3(4.2, 0.08, 1.2), 0.0, {}, "cloth_striped")   # awning
	put("enamel_sign", Vector3(12.55, 2.6, -40.2), Vector3(3.6, 0.6, 0.08), 180.0, {"text": "STORES"}, "metal_dark")
	# A pair of garages on Marsh Lane at the foot of the avenue.
	mass("building", 10.4, 13.6, 35, 42, 2.6, "red_brick")
	put("roof", Vector3(12.0, 2.6, 38.5), Vector3(3.6, 0.15, 7.4), 0.0, {}, "slate")
	put("shutter_panel", Vector3(12.0, 0, 42), Vector3(2.6, 2.1, 0.2), 0.0, {}, "metal_painted")
	# The attackers' house on Marsh Lane: a garage beside it and a hedge along its front wall.
	mass("building", 30.7, 31.9, 36.0, 42.0, 2.5, "red_brick")
	put("roof", Vector3(31.3, 2.5, 39.0), Vector3(1.4, 0.12, 6.2), 0.0, {}, "slate")
	mass("block", 22.0, 26.0, 44.75, 45.25, 1.3, "hedge")


## Back gardens out of play behind panel fences: sheds, washing lines, trees.
func _gardens() -> void:
	layer("Gardens")
	# Plot fences start 1 m inside the houses, so they close the side gaps without covering facades.
	for entry: Array in [[-51, -23, -39, -26], [-19, -10, -39, -26], [10, 15, -39, -26], [19, 44, -39, -26],
			[-51, -32, 27, 41], [-27, -10, 27, 41], [10, 14, 27, 41], [18, 44, 27, 41],
			[-41, -32, 2, 22], [-27, -10, 2, 22]]:
		plot(entry[0], entry[1], entry[2], entry[3])
	for entry: Array in [[-46.0, -29.0], [-33.0, -29.5], [-13.0, -29.0], [25.0, -29.0], [39.0, -29.5],
			[-47.0, 30.0], [-16.0, 30.0], [24.0, 30.0], [38.0, 30.5], [-36.0, 8.0], [-20.0, 18.0]]:
		shed(float(entry[0]), float(entry[1]))
	for entry: Array in [[-40.5, -29.5], [-22.5, 29.5], [35.0, -29.0], [-15.0, 6.0]]:
		put("washing_line", Vector3(float(entry[0]), 0, float(entry[1])), Vector3(4.5, 2.6, 0.2), 0.0, {}, "canvas")
	for entry: Array in [[-28.0, -28.0], [28.0, 31.0], [-40.0, 30.0], [-22.0, 10.0], [-38.0, 16.0]]:
		put("tree", Vector3(float(entry[0]), 0, float(entry[1])), Vector3(4.5, 7.5, 4.5), 0.0, {}, "foliage")
	# Allotments between the Green and Garage Row: raised beds, a shed, a water butt.
	plot(10, 44, 2, 22, "planks", FENCE)
	for row: int in 4:
		for column: int in 3:
			put("planter", Vector3(14.0 + column * 6.0, 0, 6.0 + row * 4.0), Vector3(3.6, 0.45, 1.4), 0.0, {}, "weathered_wood")
	put("coopered_barrel", Vector3(29.0, 0, 20.5), Vector3.ZERO, 0.0, {}, "weathered_wood")
	put("vehicle_cart", Vector3(28.5, 0, 9.0), Vector3.ZERO, 20.0)
	put("block", Vector3(25.0, 0, 4.0), Vector3(2.4, 2.2, 3.2), 0.0, {}, "glass")       # greenhouse
	put("roof", Vector3(25.0, 2.2, 4.0), Vector3(2.5, 0.06, 3.3), 0.0, {}, "glass")


## Ashby Avenue, the middle lane from Larch Road to Marsh Lane: parked cars, a van, a skip, a bus
## shelter and a traffic island break up the long view; a zebra crossing at z 12..16.
func _avenue() -> void:
	layer("Ashby Avenue")
	for i: int in 9:
		var x := -4.6 + i * 1.1
		mass("floor", x, x + 0.55, 12.4, 15.6, 0.055, "plaster_white", -0.03)
	for beacon: Vector2 in [Vector2(-5.6, 11.6), Vector2(5.6, 16.4)]:
		put("pillar", Vector3(beacon.x, 0, beacon.y), Vector3(0.14, 2.5, 0.14), 0.0, {}, "metal_dark")
		put("block", Vector3(beacon.x, 2.5, beacon.y), Vector3(0.36, 0.36, 0.36), 0.0, {}, "lamp_glass")
	for car: Array in [[-3.6, -30.0, "plaster_white"], [3.6, -21.0, "cloth_red"], [-3.6, -4.0, "slate"],
			[3.6, 6.0, "cloth_blue"], [-3.6, 24.0, "cloth_red"], [3.6, 33.0, "slate"]]:
		put("vehicle_car", Vector3(float(car[0]), 0, float(car[1])), Vector3.ZERO, 0.0, {}, str(car[2]))
	put("vehicle_truck", Vector3(3.4, 0, -36.0), Vector3.ZERO, 0.0, {}, "plaster_white")
	# Traffic island in the middle of the road: a brick planter with a bollard at each end.
	disc(Vector2(0, 19), 1.3, 0.0, 0.6, "red_brick")
	disc(Vector2(0, 19), 1.05, 0.6, 0.45, "hedge")
	for end: float in [16.6, 21.4]:
		put("bollard", Vector3(0, 0, end), Vector3.ZERO, 0.0)
	# Bus shelter on the east pavement.
	put("block", Vector3(6.6, 0, -9.0), Vector3(0.12, 2.3, 3.2), 0.0, {}, "glass")
	put("roof", Vector3(6.1, 2.3, -9.0), Vector3(1.4, 0.1, 3.4), 0.0, {}, "metal_dark")
	put("park_bench", Vector3(6.2, 0, -9.0), Vector3(1.6, 0.9, 0.5), 90.0)
	mass("block", -2.2, 0.8, -14.0, -12.2, 1.5, "metal_painted")       # builder's skip


## The Lock-ups: two rows of garages round a concrete court (site B). The west row is broken by
## Church Walk, which comes in from the West Lane through the churchyard.
func _lockups() -> void:
	layer("Lock-ups")
	for i: int in 5:
		var x1 := -41.0 + i * 3.4
		mass("block", x1, x1 + 3.4, -26, -20, 2.6, "concrete")
		put("shutter_panel", Vector3(x1 + 1.7, 0, -20), Vector3(2.7, 2.1, 0.2), 0.0, {}, "metal_painted")
	put("roof", Vector3(-32.5, 2.6, -23), Vector3(17.4, 0.15, 6.4), 0.0, {}, "slate")
	for z1: float in [-18.0, -14.0, -4.0]:
		mass("block", -41, -36, z1, z1 + 4.0, 2.6, "concrete")
		put("shutter_panel", Vector3(-36, 0, z1 + 2.0), Vector3(3.2, 2.1, 0.2), 90.0, {}, "metal_painted")
	put("roof", Vector3(-38.5, 2.6, -14), Vector3(5.4, 0.15, 8.4), 0.0, {}, "slate")
	put("roof", Vector3(-38.5, 2.6, -2), Vector3(5.4, 0.15, 4.4), 0.0, {}, "slate")
	# Cover in the court.
	put("vehicle_car", Vector3(-25.5, 0, -10), Vector3.ZERO, 70.0, {}, "cloth_blue")
	mass("block", -22.0, -18.2, -1.6, 0.2, 1.5, "metal_painted")        # builder's skip
	for i: int in 3:
		put("pallet", Vector3(-33.0, 0.15 * i, -15.5), Vector3.ZERO, 0.0)
	put("crate_stack", Vector3(-15.5, 0, -17.5), Vector3.ZERO, 90.0)
	put("wall_half", Vector3(-17.5, 0, -8.5), Vector3(3.2, 1.1, 0.35), 90.0, {}, "red_brick")
	put("barrel_cluster", Vector3(-34.8, 0, -1.0), Vector3.ZERO, 0.0)
	bins(-29.0, -19.3)
	bins(-28.2, -19.3)


## The Green: grass, oaks, a fenced playground, benches and an electricity substation (site A).
func _green() -> void:
	layer("The Green")
	for tree: Vector2 in [Vector2(13.5, -1.0), Vector2(40.5, -23.5), Vector2(13.5, -18.0), Vector2(40.0, -1.0)]:
		put("tree", Vector3(tree.x, 0, tree.y), Vector3(5, 8, 5), 0.0, {}, "foliage")
	put("block", Vector3(24.0, 0, -15.5), Vector3(2.6, 2.3, 1.9), 0.0, {}, "metal_painted")   # substation
	put("wall_half", Vector3(32.5, 0, -9.0), Vector3(4.0, 1.1, 0.45), 0.0, {}, "red_brick")
	put("planter", Vector3(20.0, 0, -7.0), Vector3(2.2, 0.9, 0.9), 90.0, {}, "red_brick")
	# Playground railings with a gate, north-east of the site.
	for rail: Array in [[Vector2(30, -25), Vector2(38, -25)], [Vector2(38, -25), Vector2(38, -19.5)],
			[Vector2(30, -19.5), Vector2(33, -19.5)], [Vector2(35, -19.5), Vector2(38, -19.5)], [Vector2(30, -25), Vector2(30, -19.5)]]:
		var a: Vector2 = rail[0]
		var b: Vector2 = rail[1]
		var centre := (a + b) / 2.0
		put("railing", Vector3(centre.x, 0, centre.y), Vector3(a.distance_to(b), 1.05, 0.08),
			rad_to_deg(atan2(-(b.y - a.y), b.x - a.x)), {}, "metal_painted")
	mass("block", 32.5, 35.5, -23.5, -21.5, 1.4, "planks")    # climbing frame
	put("park_bench", Vector3(33.0, 0, -3.5), Vector3.ZERO, 180.0)
	put("park_bench", Vector3(23.0, 0, -25.0), Vector3.ZERO, 180.0)
	put("notice_board", Vector3(13.6, 0, -15.0), Vector3.ZERO, -90.0)
	bins(41.8, -6.0)


## The chapel and its churchyard between the West Lane and the Lock-ups, crossed by Church Walk.
func _chapel() -> void:
	layer("Chapel")
	lawn(-51, -41, -26, 27)
	wall_line(Vector2(-41, -26), Vector2(-41, 27), 2.4, 0.0, "red_brick", [[16.0, 22.0]], "wall", 0.35)
	wall_line(Vector2(-51, -26), Vector2(-51, 27), 2.4, 0.0, "red_brick", [[16.0, 22.0]], "wall", 0.35)
	wall_line(Vector2(-51, 27), Vector2(-41, 27), 2.4, 0.0, "red_brick", [], "wall", 0.35)
	for side: float in [-10.0, -4.0]:
		wall_line(Vector2(-51, side), Vector2(-41, side), 1.6, 0.0, "metal_dark", [], "wall", 0.08)
	mass("building", -50, -44, 0, 22, 6.5, "red_brick")
	gable(-50.4, -43.6, -0.3, 22.3, 6.5, 10.6, "slate", false)
	for z: float in [4.0, 9.0, 14.0, 19.0]:
		opening_x("window", -44, 2.0, z, 1.0, Vector3(1.1, 2.8, 0.3), {"panes_x": 2, "panes_y": 4})
		opening_x("window", -50, 2.0, z, -1.0, Vector3(1.1, 2.8, 0.3), {"panes_x": 2, "panes_y": 4})
	put("block", Vector3(-47, 0, -1.2), Vector3(2.6, 3.4, 1.2), 0.0, {}, "red_brick")   # porch
	gable(-48.5, -45.5, -1.95, -0.5, 3.4, 4.6, "slate", false)
	opening("door", -47, 0.0, -1.8, -1.0, Vector3(1.4, 2.6, 0.26))
	# The rounded apse at the south end, with a half-cone roof.
	var rim := arc(Vector2(-47, 22), 3.0, 0.0, 180.0, 10)
	prism(Array(rim), 0.0, 6.5, "red_brick")
	var vertices: Array = [[-47.0, 9.4, 22.0]]
	var faces: Array = []
	for i: int in rim.size():
		var rp := arc(Vector2(-47, 22), 3.3, 0.0, 180.0, 10)[i]
		vertices.append([rp.x, 6.5, rp.y])
		if i > 0:
			faces.append_array([0, i, i + 1])
	studio.call("draw_brushes", [{"vertices": vertices, "faces": faces, "two_sided": true, "material": "slate"}])
	for angle: float in [45.0, 90.0, 135.0]:
		var at := Vector2(-47, 22) + Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle))) * 3.0
		put("window", Vector3(at.x, 2.4, at.y) + Vector3(cos(deg_to_rad(angle)), 0, sin(deg_to_rad(angle))) * 0.12,
			Vector3(0.8, 2.4, 0.3), rad_to_deg(atan2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle)))), {"panes_x": 1, "panes_y": 4}, "wood_dark")
	for stone: Vector2 in [Vector2(-43.0, -18), Vector2(-43.0, -14), Vector2(-46.0, -18), Vector2(-49.0, -14),
			Vector2(-46.0, -22), Vector2(-42.5, 8), Vector2(-42.5, 16), Vector2(-42.8, 24), Vector2(-50.3, 24.5)]:
		put("block", Vector3(stone.x, 0, stone.y), Vector3(0.6, 0.9, 0.15), 0.0, {}, "limestone")
	put("tree", Vector3(-42.8, 0, -22.5), Vector3(5, 8, 5), 0.0, {}, "foliage")


## Telegraph poles and wires, street lamps, parked cars, bins, bollards and street signs.
func _street_furniture() -> void:
	layer("Street furniture")
	var larch: Array[Vector2] = [Vector2(-50, -45), Vector2(-33, -45), Vector2(-14, -45), Vector2(24, -45), Vector2(41, -45)]
	var marsh: Array[Vector2] = [Vector2(-50, 46), Vector2(-34, 46), Vector2(-15, 46), Vector2(29, 46), Vector2(41, 46)]
	var fen: Array[Vector2] = [Vector2(49.4, -30), Vector2(49.4, -8), Vector2(49.4, 14), Vector2(49.4, 34)]
	for line: Array[Vector2] in [larch, marsh, fen]:
		for i: int in line.size():
			pole(line[i].x, line[i].y)
			if i > 0:
				wire(line[i - 1], line[i])
	wire(Vector2(41, -45), Vector2(49.4, -30))
	wire(Vector2(49.4, 34), Vector2(41, 46))
	for x: float in [-44.0, -24.0, -4.0, 16.0, 36.0]:
		put("lamp_post", Vector3(x, 0, -55.2), Vector3(0.5, 5.5, 0.5), 180.0)
		put("lamp_post", Vector3(x, 0, 56.2), Vector3(0.5, 5.5, 0.5), 0.0)
	for spot_at: Vector3 in [Vector3(-6.2, 0, 30), Vector3(-6.2, 0, -18), Vector3(6.2, 0, -26), Vector3(-27.6, 0, 12),
			Vector3(17.4, 0, 36), Vector3(45.0, 0, -36), Vector3(45.0, 0, 10)]:
		put("lamp_post", spot_at, Vector3(0.5, 4.2, 0.5), 0.0)
	# Warm fill where the houses shade the sites and lanes: the Lock-ups court, the Green and the
	# Ginnel Mouth under the eaves.
	lamp(Vector3(-30.0, 3.2, -11.0), 1.6, 10.0)
	lamp(Vector3(-20.0, 3.2, -3.5), 1.4, 8.0)
	lamp(Vector3(30.0, 3.2, -13.0), 1.4, 9.0)
	spot(Vector3(-10.5, 3.6, -3.5), 2.8, 9.0, 60.0)
	# Parked cars along the kerbs, clear of both spawns.
	for car: Array in [[-42.0, -53.0, "cloth_red"], [-30.0, -53.0, "slate"], [24.0, -53.0, "plaster_white"],
			[38.0, -47.0, "cloth_blue"], [-40.0, 48.5, "plaster_white"], [-21.0, 48.5, "cloth_red"],
			[38.0, 48.5, "slate"], [-48.0, 53.8, "cloth_blue"], [-6.0, 53.8, "slate"], [44.0, 53.8, "cloth_red"]]:
		put("vehicle_car", Vector3(float(car[0]), 0, float(car[1])), Vector3.ZERO, 90.0, {}, str(car[2]))
	put("vehicle_truck", Vector3(47.0, 0, 6.0), Vector3.ZERO, 0.0, {}, "plaster_white")      # van on Fen Walk
	# A bollard at the foot of each ginnel, and bins.
	for bollard: Vector2 in [Vector2(-7.5, 44.0), Vector2(16.0, 44.0), Vector2(-29.5, 44.0)]:
		put("bollard", Vector3(bollard.x, 0, bollard.y), Vector3.ZERO, 0.0)
	for bin_at: Vector2 in [Vector2(-9.4, 6.0), Vector2(-9.4, 6.8), Vector2(9.4, 0.0), Vector2(43.4, 24.0),
			Vector2(-31.4, 18.0), Vector2(17.4, 30.0), Vector2(-40.4, 26.4)]:
		bins(bin_at.x, bin_at.y)
	put("notice_board", Vector3(-31.9, 0, 32.0), Vector3.ZERO, -90.0)
	# Street names on the fences, white on black.
	for sign: Array in [["LARCH ROAD", Vector3(-12.0, 0.25, -44.16), 180.0], ["MARSH LANE", Vector3(-20.0, 0.25, 45.16), 0.0],
			["ASHBY AVENUE", Vector3(-9.9, 1.0, -30.0), 90.0], ["WEST LANE", Vector3(-51.2, 1.0, 32.0), -90.0],
			["CHAPEL PATH", Vector3(-27.1, 1.0, 40.0), -90.0], ["FEN WALK", Vector3(44.1, 1.0, 40.0), 90.0]]:
		put("enamel_sign", sign[1], Vector3(1.8, 0.4, 0.06), float(sign[2]), {"text": sign[0]}, "metal_dark")


## Curves against the grid: winding paths down the West Lane and Fen Walk and across the Green,
## rounded kerbs where the avenue meets the two roads, a round flower bed and rounded hedge ends.
func _curves() -> void:
	layer("Curves")
	var west: Array[Vector2] = []
	var fen: Array[Vector2] = []
	var z := -44.0
	while z <= 45.0:
		west.append(Vector2(-53.5 + sin(z * 0.11) * 0.9, z))
		fen.append(Vector2(47.0 + sin(z * 0.09 + 1.2) * 1.2, z))
		z += 4.45
	path(west, 2.4, "gravel")
	path(fen, 2.6, "dirt")
	# Across the Green: West Gate to the Fen Gap, and from Larch Alley down to it.
	path(curve(Vector2(11, -8.5), Vector2(25, 1.0), Vector2(44, -13), 10), 1.8, "gravel")
	path(curve(Vector2(17, -26), Vector2(20.5, -16), Vector2(26.5, -3.2), 8), 1.6, "gravel")
	# Rounded kerbs: the pavement sweeps round into the avenue's verges.
	for corner: Array in [[Vector2(-7, -44), Vector2(-10, -41), 270.0, 360.0], [Vector2(7, -44), Vector2(10, -41), 270.0, 180.0],
			[Vector2(-7, 45), Vector2(-10, 42), 90.0, 0.0], [Vector2(7, 45), Vector2(10, 42), 90.0, 180.0]]:
		var outline: Array = [corner[0]]
		outline.append_array(arc(corner[1], 3.0, float(corner[2]), float(corner[3]), 6))
		surface(outline, 0.03, 0.05, "concrete")
	# A round flower bed on the Green.
	disc(Vector2(16.5, -19.5), 1.7, 0.0, 0.5, "red_brick")
	disc(Vector2(16.5, -19.5), 1.45, 0.5, 0.35, "hedge")
	# Rounded ends on the hedges either side of each gap.
	for end: Vector2 in [Vector2(-10.5, -6), Vector2(-10.5, -1), Vector2(10.5, -11), Vector2(10.5, -6),
			Vector2(43.5, -16), Vector2(43.5, -10)]:
		disc(end, 0.62, 0.0, 2.1, "hedge", 10)


## The barn behind the allotments and the well on the Green that give Barnwell its name.
func _barn_and_well() -> void:
	layer("Barn and well")
	# A timber barn with a steep slate roof, its great doors facing Garage Row, hay outside.
	mass("building", 31, 43, 5, 20, 4.6, "weathered_wood")
	mass("block", 31, 43, 4.9, 5.1, 0.6, "mossy_stone")
	gable(30.6, 43.4, 4.6, 20.4, 4.6, 9.6, "slate", false)
	put("block", Vector3(37, 0, 20.08), Vector3(4.6, 4.2, 0.16), 0.0, {}, "wood_dark")
	put("block", Vector3(37, 0, 20.2), Vector3(0.16, 4.2, 0.1), 0.0, {}, "weathered_wood")
	put("block", Vector3(37, 5.6, 20.12), Vector3(1.6, 1.4, 0.16), 0.0, {}, "wood_dark")    # hay loft door
	for vent: float in [33.0, 41.0]:
		put("block", Vector3(vent, 2.0, 20.06), Vector3(0.9, 1.2, 0.12), 0.0, {}, "wood_dark")
	for bale: Vector3 in [Vector3(32.5, 0, 21.2), Vector3(33.9, 0, 21.2), Vector3(33.2, 0.9, 21.2)]:
		put("block", bale, Vector3(1.3, 0.9, 0.7), 0.0, {}, "burlap")
	# The well: a round stone well with its winding frame on the Green, cover in site A.
	put("well", Vector3(35.5, 0, -14.5), Vector3.ZERO, 30.0, {}, "mossy_stone")


## Everyday clutter: street trees, a post box, grit bin, bus stop, phone cabinet, cones, garden
## life (trampolines, greenhouses, benches, barbecues), hay on Fen Walk, junk in the Lock-ups and
## goalposts on the Green.
func _props() -> void:
	layer("Props")
	for tree_z: float in [-36.0, -22.0, 8.0, 28.0, 38.0]:
		put("tree", Vector3(-8.6, 0, tree_z), Vector3(3.6, 7.0, 3.6), 0.0, {}, "foliage")
		put("tree", Vector3(8.6, 0, tree_z + 3.0), Vector3(3.6, 7.0, 3.6), 0.0, {}, "foliage")
	# Larch Road and Marsh Lane.
	put("column", Vector3(-8.0, 0, -45.3), Vector3(0.5, 1.1, 0.5), 0.0, {}, "cloth_red")          # post box
	put("block", Vector3(-8.0, 1.1, -45.3), Vector3(0.6, 0.12, 0.6), 0.0, {}, "metal_dark")
	put("block", Vector3(30.0, 0, -45.3), Vector3(1.0, 0.8, 0.6), 0.0, {}, "plaster_ochre")       # grit bin
	put("block", Vector3(-17.0, 0, 46.3), Vector3(1.2, 1.3, 0.5), 0.0, {}, "metal_painted")       # phone cabinet
	put("pillar", Vector3(6.4, 0, -45.6), Vector3(0.1, 2.6, 0.1), 0.0, {}, "metal_dark")          # bus stop
	put("enamel_sign", Vector3(6.4, 2.3, -45.6), Vector3(0.7, 0.45, 0.05), 180.0, {"text": "BUS"}, "metal_dark")
	for bench: Array in [[Vector3(-36.0, 0, -55.4), 180.0], [Vector3(26.0, 0, 55.6), 0.0], [Vector3(-55.4, 0, -20.0), 90.0]]:
		put("park_bench", bench[0], Vector3.ZERO, float(bench[1]))
	for cone: Vector2 in [Vector2(-3.0, -11.6), Vector2(1.6, -11.6), Vector2(1.6, -14.6), Vector2(-4.2, -12.0)]:
		put("bollard", Vector3(cone.x, 0, cone.y), Vector3(0.36, 0.7, 0.36), 0.0, {}, "plaster_ochre")
	# The Lock-ups: tyres, an old sofa, oil drums, a ladder.
	put("barrel_cluster", Vector3(-33.5, 0, -3.5), Vector3(1.4, 0.9, 1.4), 0.0, {}, "rubber")
	put("block", Vector3(-21.5, 0, -18.6), Vector3(2.0, 0.45, 0.85), 0.0, {}, "cloth_striped")
	put("block", Vector3(-21.5, 0.45, -18.95), Vector3(2.0, 0.5, 0.2), 0.0, {}, "cloth_striped")
	put("block", Vector3(-14.0, 0, 1.0), Vector3(0.6, 0.9, 0.6), 0.0, {}, "metal_rust")
	put("block", Vector3(-13.2, 0, 1.3), Vector3(0.6, 0.9, 0.6), 0.0, {}, "metal_rust")
	put("block", Vector3(-24.5, 0.0, -19.9), Vector3(0.5, 2.5, 0.1), 0.0, {}, "weathered_wood")
	# The Green: goalposts, picnic benches, a bin by each path end, a lamp.
	for post: float in [15.5, 19.5]:
		put("pillar", Vector3(post, 0, 0.8), Vector3(0.12, 2.0, 0.12), 0.0, {}, "plaster_white")
	put("block", Vector3(17.5, 2.0, 0.8), Vector3(4.1, 0.12, 0.12), 0.0, {}, "plaster_white")
	put("park_bench", Vector3(22.0, 0, -22.5), Vector3.ZERO, 0.0)
	put("park_bench", Vector3(22.0, 0, -21.3), Vector3.ZERO, 180.0)
	bins(12.0, -12.0)
	bins(42.2, -17.0)
	put("lamp_post", Vector3(27.0, 0, -1.2), Vector3(0.5, 4.2, 0.5), 0.0)
	# Fen Walk: hay bales by the field fence, a field gate.
	for bale: Vector3 in [Vector3(49.3, 0, -20.0), Vector3(49.3, 0, -18.6), Vector3(49.3, 0.9, -19.3), Vector3(49.3, 0, 24.0)]:
		put("block", bale, Vector3(0.9, 0.9, 1.3), 0.0, {}, "burlap")
	put("railing", Vector3(49.7, 0, -2.0), Vector3(3.0, 1.2, 0.1), 90.0, {}, "weathered_wood")
	# Back gardens: trampolines, greenhouses, garden benches, barbecues.
	for trampoline: Vector2 in [Vector2(30.5, -29.0), Vector2(33.0, 30.5), Vector2(-44.0, 30.5)]:
		disc(trampoline, 1.5, 0.8, 0.08, "rubber", 14)
		for leg: float in [0.0, 120.0, 240.0]:
			var at := trampoline + Vector2(cos(deg_to_rad(leg)), sin(deg_to_rad(leg))) * 1.4
			put("pillar", Vector3(at.x, 0, at.y), Vector3(0.06, 0.8, 0.06), 0.0, {}, "metal_dark")
	for greenhouse: Vector2 in [Vector2(-17.0, -28.5), Vector2(41.5, -28.5), Vector2(-12.5, 30.5)]:
		put("block", Vector3(greenhouse.x, 0, greenhouse.y), Vector3(2.0, 2.0, 2.6), 0.0, {}, "glass")
	for seat: Vector2 in [Vector2(-36.5, -27.0), Vector2(20.5, -27.0), Vector2(-25.0, 28.0), Vector2(41.0, 28.0)]:
		put("park_bench", Vector3(seat.x, 0, seat.y), Vector3.ZERO, 0.0)
	for grill: Vector2 in [Vector2(-11.0, -27.0), Vector2(28.5, 28.2)]:
		put("block", Vector3(grill.x, 0, grill.y), Vector3(0.8, 0.9, 0.5), 0.0, {}, "metal_dark")


func _gameplay() -> void:
	layer("Gameplay")
	spawns("attack", Vector3(18, 0, 52.5), 0.0, Vector3(26, 3, 8))
	spawns("defence", Vector3(0, 0, -50), 180.0, Vector3(26, 3, 9))
	put("bombsite", SITE_A, Vector3(14, 3, 12), 0.0, {"site": "A"})
	put("bombsite", SITE_B, Vector3(14, 3, 12), 0.0, {"site": "B"})


func _callouts() -> void:
	layer("Tactics")
	area("Larch Road", WEST, EAST, -56, -44)
	area("West Lane", WEST, -51, -44, 45)
	area("Church Walk", -51, -41, -10, -4, "entrance_b")
	area("Garage Drive", -23, -19, -44, -26)
	area("Larch Alley", 15, 19, -44, -26)
	area("Lock-ups", -41, -11, -26, 2)
	area("Ginnel Top", -11, -10, -26, -24)
	area("Ginnel Mouth", -11, -10, -6, -1, "entrance_b")
	area("Chapel Gate", -32, -27, 0, 4, "entrance_b")
	area("Chapel Path", -32, -27, 4, 45)
	area("Back Lane", -41, -10, 22, 27)
	area("Top of the Avenue", -10, 10, -44, -12)
	area("Ashby Avenue", -10, 10, -12, 22, "mid")
	area("Foot of the Avenue", -10, 10, 22, 45)
	area("West Gate", 10, 11, -11, -6, "entrance_a")
	area("The Green", 11, 43, -26, 2)
	area("Fen Gap", 43, 44, -16, -10, "entrance_a")
	area("Fen Walk", 44, EAST, -44, 45)
	area("Garage Row", 10, 44, 22, 27)
	area("Kennel Ginnel", 14, 18, 27, 45)
	area("Marsh Lane", WEST, EAST, 45, 57)


func _tactical() -> void:
	layer("Tactics")
	var west_gate := Vector3(10.5, 0, -8.5)
	var fen_gap := Vector3(43.5, 0, -13)
	var ginnel_mouth := Vector3(-10.5, 0, -3.5)
	var chapel_gate := Vector3(-29.5, 0, 2)
	anchor("Green plant substation", "plant", SITE_A + Vector3(-3, 0, -2))
	anchor("Green plant wall", "plant", SITE_A + Vector3(4, 0, 1.5))
	anchor("Lock-ups plant car", "plant", SITE_B + Vector3(-3, 0, 2))
	anchor("Lock-ups plant pallets", "plant", SITE_B + Vector3(-5, 0, -4))
	anchor("Avenue east hold", "default", Vector3(8.5, 0, 4))
	anchor("Fen Walk hold", "default", Vector3(47, 0, 14))
	anchor("Avenue west hold", "default", Vector3(-8.5, 0, 6))
	anchor("West Lane hold", "default", Vector3(-53.5, 0, 10))
	anchor("Church Walk smoke", "utility", Vector3(-46, 0, -7))
	anchor("Chapel Path hold", "default", Vector3(-29.5, 0, 16))
	anchor("Island hold", "default", Vector3(0, 0, 23))
	anchor("West Gate smoke", "utility", west_gate)
	anchor("Fen Gap smoke", "utility", fen_gap)
	anchor("Ginnel Mouth smoke", "utility", ginnel_mouth)
	anchor("Chapel Gate smoke", "utility", chapel_gate)
	anchor("Avenue smoke", "utility", Vector3(0, 0, 10))
	for hold: Array in [[Vector3(38, 0, -3), west_gate, "A"], [Vector3(16, 0, -22), fen_gap, "A"],
			[Vector3(25, 0, -21), west_gate, "A"], [Vector3(-14, 0, -22), chapel_gate, "B"],
			[Vector3(-34.5, 0, -18.5), ginnel_mouth, "B"], [Vector3(-19, 0, -18), chapel_gate, "B"]]:
		hint("ai_hold", hold[0], face(hold[0], hold[1]), str(hold[2]))
	for cover: Array in [[Vector3(25.5, 0, -15.5), "A"], [Vector3(32.5, 0, -10), "A"],
			[Vector3(-25.5, 0, -12.5), "B"], [Vector3(-18.5, 0, -8.5), "B"]]:
		hint("ai_cover", cover[0], 180.0, str(cover[1]))
	hint("ai_angle", west_gate, face(west_gate, SITE_A), "A")
	hint("ai_angle", fen_gap, face(fen_gap, SITE_A), "A")
	hint("ai_angle", ginnel_mouth, face(ginnel_mouth, SITE_B), "B")
	hint("ai_angle", chapel_gate, face(chapel_gate, SITE_B), "B")
	var church_walk := Vector3(-38.5, 0, -7)
	hint("ai_angle", church_walk, face(church_walk, SITE_B), "B")
	hint("ai_hold", Vector3(-20, 0, -4), face(Vector3(-20, 0, -4), church_walk), "B")


func _check(analysis: MapAnalysis) -> bool:
	var west := analysis.path_length(Vector3(-53.5, 0, 40), Vector3(-53.5, 0, -40))
	var middle := analysis.path_length(Vector3(0, 0, 44), Vector3(0, 0, -43))
	print("West Lane end to end: %.1f m; Ashby Avenue end to end: %.1f m" % [west, middle])
	if west < 0.0 or middle < 0.0 or middle > 100.0:
		printerr("A lane does not run from Larch Road to Marsh Lane.")
		return false
	return analysis.issues.is_empty()
