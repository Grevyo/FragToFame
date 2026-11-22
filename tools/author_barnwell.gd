extends "res://tools/map_author_base.gd"
## Authoring session for the official map "Barnwell": a 1950s council estate on the edge of the
## fens on a bright late-summer day, traced from the owner's drawing over the street map of a real
## place (owner, 2026-11-22: rework it from the map and the real location). Red-brick semis with
## white upper floors under gabled tile roofs, chimneys and aerials, gravel drives, privet hedges,
## panel fences, telegraph poles, poplars and broadleaf trees, and a primary school beyond the
## estate.
##
## Every coordinate below is a pixel on the owner's drawing (north up), scaled by [constant S]
## metres per pixel round [constant ORIGIN]: the drawing's black lines are the lanes (a loop round
## the estate and Edinburgh Avenue up the middle), its brown lines the footpaths to the sites, its
## orange lines the attackers' paths from their house, the blue box the defenders' spawn and the
## red box the attackers' house. The houses stand where the street map shows them; the people,
## house numbers and interiors are not reproduced.
##
## Only the lanes, paths, sites and forecourts are walkable. Their combined outline is fenced or
## hedged all round, so every back garden is closed off, as on a real estate.
##
## Run:  <godot> --headless --path <project> --script res://tools/author_barnwell.gd
## (add `-- --dry-run` to validate and print timings without publishing).

const S: float = 0.17
const ORIGIN: Vector2 = Vector2(720, 480)
const FLOOR_T: float = 0.05
## How far a house or a drive stands back from the walkable network: the thickest hedge plus a gap.
const HOUSE_CLEARANCE: float = 1.25
const EAVE: float = 5.1
## Drawing pixels of the spawns (the blue and red boxes) and the bombsite centres.
const DEFENDERS: Vector2 = Vector2(734, 232)
const ATTACKERS: Vector2 = Vector2(890, 868)
const SITE_A: Vector2 = Vector2(920, 400)
const SITE_B: Vector2 = Vector2(561, 392)
const RIDGE: float = 7.5

## Walkable areas: {"poly": PackedVector2Array (world x/z), "kind": String}.
var _walk: Array[Dictionary] = []
## House footprints (world), for keeping trees and props off them.
var _houses: Array[PackedVector2Array] = []
## The open fronts of houses that face the network: no fence or hedge is placed inside one.
var _open_fronts: Array[PackedVector2Array] = []
## How far a house's open front reaches past its front corners on each side, so the drive and its
## car stay inside it.
const FRONT_SPREAD: float = 1.8
## A garden gate's width, posts included.
const GATE_WIDTH: float = 1.2

## Fence styles per kind of walkable area: [type, material, height, thickness]; a run takes one
## style picked from its position, so long edges mix hedge and fence like real front gardens.
const FENCES: Dictionary = {
	"road": [["block", "hedge", 1.75, 0.9], ["wall", "planks", 1.85, 0.12], ["block", "hedge", 1.6, 0.8]],
	"lane": [["wall", "planks", 1.85, 0.12], ["block", "hedge", 1.8, 0.9]],
	"alley": [["wall", "planks", 1.85, 0.12], ["wall", "weathered_wood", 1.85, 0.12]],
	"path": [["block", "hedge", 1.9, 1.0], ["wall", "weathered_wood", 1.8, 0.12]],
	"court": [["wall", "red_brick", 2.0, 0.3]],
	"green": [["block", "hedge", 1.7, 0.9]],
	"forecourt": [["wall", "red_brick", 1.8, 0.3], ["block", "hedge", 1.7, 0.9]],
}


func _official_id() -> String:
	return "map_f2f_barnwell"


## Revision 3 (owner, 2026-11-22): rebuilt from the owner's drawing and the real place: the lane
## loop and Edinburgh Avenue, footpaths to a garage court (B) and a green (A), the attackers'
## paths from their house on Barnwell Road, and a fenland summer sky.
func _revision() -> int:
	return 3


func _build() -> void:
	controller.set_metadata("Barnwell", "F2F official",
		"A 1950s council estate on the edge of the fens, traced from a real place. Defenders hold the top of Edinburgh Avenue; attackers start outside their house on Barnwell Road. A: the Green, by the Avenue Gap, the Green Gate up the garden paths or the SE Alley. B: the garage court, by the North Path, the West Path, the Avenue Path or the Back Gate from the ginnels.")
	controller.set_lighting({"sun_yaw": 222.0, "sun_pitch": 42.0, "sun_energy": 1.25, "sun_color": "fff2dc",
		"ambient_color": "c4d2e2", "ambient_energy": 0.62, "haze": 0.22, "sky": "fen_summer"})
	layer("Ground")
	mass("block", -100, 150, -75, 105, 1.0, "grass_worn", -1.0)
	_lanes()
	_footpaths()
	_sites()
	_estate_houses()
	_backdrop()
	_fences()
	_lockups()
	_green()
	_street_furniture()
	_trees()
	_gameplay()
	_callouts()
	_tactical()


# --- drawing coordinates --------------------------------------------------------------------------

## A pixel on the owner's drawing in world x/z.
static func p(px: float, py: float) -> Vector2:
	return (Vector2(px, py) - ORIGIN) * S


static func pts(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Array in list:
		out.append(p(float(point[0]), float(point[1])))
	return out


## A walkable strip along a drawn line, [param width] m wide with square ends (so strips that meet
## overlap), and optionally a narrower strip of [param inner_material] down its middle (tarmac
## between pavements).
func strip(kind: String, line: Array, width: float, material: String, top: float, inner: float = 0.0,
		inner_material: String = "") -> void:
	var points := pts(line)
	for poly: PackedVector2Array in Geometry2D.offset_polyline(points, width / 2.0, Geometry2D.JOIN_MITER, Geometry2D.END_SQUARE):
		_draw_floor(poly, kind, top, material)
		_walk.append({"poly": poly, "kind": kind})
	if inner > 0.0:
		for poly: PackedVector2Array in Geometry2D.offset_polyline(points, inner / 2.0, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT):
			_floor_surface(poly, top + 0.01, FLOOR_T, inner_material)


## A walkable area of any outline.
func zone(kind: String, outline: Array, material: String, top: float) -> PackedVector2Array:
	var poly := pts(outline)
	_draw_floor(poly, kind, top, material)
	_walk.append({"poly": poly, "kind": kind})
	return poly


## Draws [param poly] as floor. Anything that is not a road or lane is drawn less the parts over
## the roads and lanes laid before it, so footpaths, sites and forecourts stop at the kerb instead
## of being painted across the tarmac.
func _draw_floor(poly: PackedVector2Array, kind: String, top: float, material: String) -> void:
	var parts: Array[PackedVector2Array] = [poly]
	if not is_road(kind):
		for entry: Dictionary in _walk:
			if not is_road(str(entry["kind"])):
				continue
			var kept: Array[PackedVector2Array] = []
			for part: PackedVector2Array in parts:
				kept.append_array(_cut(part, entry["poly"]))
			parts = kept
	for part: PackedVector2Array in parts:
		if absf(_area(part)) > 0.05:
			_floor_surface(part, top, FLOOR_T, material)


static func is_road(kind: String) -> bool:
	return kind == "road" or kind == "lane"


# --- the walkable network (the owner's lines) -----------------------------------------------------

func _lanes() -> void:
	layer("Lanes")
	# The north road and Barnwell Road have pavements; the back lanes are plain tarmac.
	strip("road", NORTH_ROAD, 8.0, "concrete", 0.05, 5.6, "tarmac")
	strip("road", BARNWELL_ROAD, 8.0, "concrete", 0.05, 5.6, "tarmac")
	strip("road", AVENUE, 9.0, "concrete", 0.05, 6.2, "tarmac")
	strip("lane", [[1000, 240], [1090, 280], [1150, 340], [1168, 410], [1140, 480], [1085, 540], [1045, 585]], 6.0, "tarmac", 0.055)
	strip("lane", [[1240, 665], [1130, 810], [1010, 965]], 6.0, "tarmac", 0.055)
	strip("lane", [[700, 752], [560, 735], [432, 728]], 6.0, "tarmac", 0.055)
	strip("lane", [[432, 728], [425, 640], [432, 560], [380, 545], [305, 530], [300, 440], [310, 352], [420, 345],
		[432, 250], [432, 186]], 6.0, "tarmac", 0.055)
	strip("path", [[1045, 585], [1150, 622], [1240, 665]], 4.0, "gravel", 0.058)


func _footpaths() -> void:
	layer("Footpaths")
	# West block: the paths into the garage court and the ginnels south of it.
	strip("alley", [[628, 196], [626, 240], [616, 300]], 3.0, "flagstones", 0.062)        # North Path
	strip("alley", [[305, 416], [476, 420]], 3.0, "flagstones", 0.062)                    # West Path
	strip("alley", [[606, 404], [720, 412]], 3.0, "flagstones", 0.062)                    # Avenue Path
	strip("alley", [[376, 545], [378, 500], [552, 494]], 3.0, "concrete", 0.062)          # Back Alley
	strip("alley", [[486, 497], [486, 597], [442, 597]], 3.0, "concrete", 0.062)          # Allotment Path
	strip("alley", [[486, 548], [540, 548]], 3.0, "concrete", 0.062)
	strip("alley", [[548, 480], [542, 560], [538, 730]], 3.0, "concrete", 0.062)          # Ginnel
	strip("alley", [[548, 505], [578, 515], [580, 582], [702, 600]], 3.0, "concrete", 0.062)  # Dog Leg
	# East block: the paths onto the Green.
	strip("alley", [[884, 212], [870, 280], [848, 355]], 3.0, "flagstones", 0.062)        # North Alley
	strip("alley", [[722, 466], [845, 472], [884, 456]], 3.0, "flagstones", 0.062)        # Avenue Gap
	strip("alley", [[1048, 580], [990, 540], [985, 515], [994, 492]], 3.0, "flagstones", 0.062)  # SE Alley
	# The attackers' paths (orange): up the garden paths from their house to the Green.
	strip("path", [[852, 470], [858, 520], [845, 585]], 3.5, "packed_earth", 0.058)       # Green Gate path
	strip("path", [[845, 585], [820, 592], [815, 622], [803, 660], [838, 686], [856, 705], [852, 745]], 3.5, "packed_earth", 0.058)
	strip("path", [[845, 585], [880, 592], [930, 620], [962, 655], [965, 682], [930, 692], [906, 702], [905, 745], [852, 745]], 3.5, "packed_earth", 0.058)
	strip("path", [[838, 686], [800, 740], [760, 782]], 3.5, "packed_earth", 0.058)
	strip("path", [[930, 692], [988, 740], [980, 800], [1058, 856]], 3.5, "packed_earth", 0.058)


func _sites() -> void:
	layer("Sites and forecourts")
	zone("court", [[472, 296], [612, 296], [606, 488], [470, 474]], "concrete", 0.066)            # B: the garage court
	zone("green", [[838, 350], [1040, 375], [1050, 410], [992, 495], [884, 456], [836, 445]], "grass_worn", 0.066)  # A
	zone("forecourt", [[640, 205], [735, 205], [732, 286], [640, 286]], "concrete", 0.052)        # defenders' corner
	zone("forecourt", [[833, 797], [915, 842], [934, 908], [812, 842]], "gravel", 0.052)          # attackers' drives


# --- fences: the outline of the walkable network --------------------------------------------------

## Every edge of every walkable area, less the parts inside another walkable area, is the edge of
## the network: a hedge, fence or wall stands just outside it.
func _fences() -> void:
	layer("Fences and hedges")
	for index: int in _walk.size():
		var poly: PackedVector2Array = _walk[index]["poly"]
		var styles: Array = FENCES[_walk[index]["kind"]]
		for i: int in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if a.distance_to(b) < 0.05:
				continue
			var parts: Array[PackedVector2Array] = [PackedVector2Array([a, b])]
			for other: int in _walk.size():
				if other == index or parts.is_empty():
					continue
				var kept: Array[PackedVector2Array] = []
				for part: PackedVector2Array in parts:
					kept.append_array(Geometry2D.clip_polyline_with_polygon(part, _walk[other]["poly"]))
				parts = kept
			for front: PackedVector2Array in _open_fronts:
				var kept: Array[PackedVector2Array] = []
				for part: PackedVector2Array in parts:
					kept.append_array(Geometry2D.clip_polyline_with_polygon(part, front))
				parts = kept
			for part: PackedVector2Array in parts:
				_fence_run(part[0], part[part.size() - 1], a, b, poly, styles)


## One run of fence outside [param poly] from [param from] to [param to]. Ends at the area's own
## corners overlap by half the thickness so corners close; ends cut by another area stop flush.
func _fence_run(from: Vector2, to: Vector2, a: Vector2, b: Vector2, poly: PackedVector2Array, styles: Array) -> void:
	var length := from.distance_to(to)
	if length < 0.3:
		return
	var dir := (to - from) / length
	var normal := Vector2(-dir.y, dir.x)
	var mid := (from + to) / 2.0
	if Geometry2D.is_point_in_polygon(mid + normal * 0.05, poly):
		normal = -normal
	var style: Array = styles[pick_at(mid, 3) % styles.size()]
	var thickness := float(style[3])
	var start := 0.0
	var end := length
	if from.distance_to(a) < 0.01 or from.distance_to(b) < 0.01:
		start -= thickness / 2.0
	if to.distance_to(a) < 0.01 or to.distance_to(b) < 0.01:
		end += thickness / 2.0
	var yaw := rad_to_deg(atan2(-dir.y, dir.x))
	var runs: Array[Vector2] = [Vector2(start, end)]
	# Now and then a long plank fence has a garden gate in it, so the back gardens look reachable.
	if str(style[0]) == "wall" and str(style[1]) != "red_brick" and length > 6.0 and pick_at(mid, 9) % 3 == 0:
		var g := (start + end) / 2.0 + float(pick_at(mid, 4) % 3 - 1) * 1.5
		runs = [Vector2(start, g - GATE_WIDTH / 2.0), Vector2(g + GATE_WIDTH / 2.0, end)]
		_gate(from + dir * g + normal * (thickness / 2.0), dir, pick_at(mid, 6))
	for run: Vector2 in runs:
		var centre := from + dir * ((run.x + run.y) / 2.0) + normal * (thickness / 2.0)
		put(str(style[0]), Vector3(centre.x, 0, centre.y), Vector3(run.y - run.x, float(style[2]), thickness), yaw, {}, str(style[1]))


## A closed garden gate [constant GATE_WIDTH] m wide centred on [param centre] in a fence running
## along [param dir]: two posts, a boarded leaf a little lower than the fence with a rail across
## each face, and a latch. It is solid, like the fence.
func _gate(centre: Vector2, dir: Vector2, pick: int) -> void:
	var yaw := rad_to_deg(atan2(-dir.y, dir.x))
	var normal := Vector2(-dir.y, dir.x)
	var leaf: String = ["weathered_wood", "wood_dark", "planks", "plaster_white"][pick % 4]
	for side: float in [-1.0, 1.0]:
		var post := centre + dir * (side * (GATE_WIDTH / 2.0 - 0.06))
		put("block", Vector3(post.x, 0, post.y), Vector3(0.12, 1.95, 0.12), yaw, {}, "wood_dark")
	put("block", Vector3(centre.x, 0.06, centre.y), Vector3(GATE_WIDTH - 0.26, 1.66, 0.06), yaw, {}, leaf)
	for face: float in [-1.0, 1.0]:
		var at := centre + normal * (face * 0.055)
		for height: float in [0.3, 1.35]:
			put("block", Vector3(at.x, height, at.y), Vector3(GATE_WIDTH - 0.3, 0.1, 0.05), yaw, {}, leaf)
		var latch := at + dir * (GATE_WIDTH / 2.0 - 0.25) + normal * (face * 0.02)
		put("block", Vector3(latch.x, 1.0, latch.y), Vector3(0.14, 0.06, 0.06), yaw, {}, "metal_dark")


## True when [param footprint] overlaps a house already placed.
func overlaps_house(footprint: PackedVector2Array) -> bool:
	for other: PackedVector2Array in _houses:
		if not Geometry2D.intersect_polygons(footprint, other).is_empty():
			return true
	return false


## True when [param footprint] grown by [param margin] touches the walkable network.
func blocked(footprint: PackedVector2Array, margin: float) -> bool:
	for grown: PackedVector2Array in Geometry2D.offset_polygon(footprint, margin):
		for entry: Dictionary in _walk:
			if not Geometry2D.intersect_polygons(grown, entry["poly"]).is_empty():
				return true
	return false


# --- houses ---------------------------------------------------------------------------------------

## The estate's houses inside the lane loop: [px, py, width px, depth px, facing (0 north, 90
## east), halves]. They stand where the street map shows them.
const ESTATE: Array = [
	[567, 268, 75, 40, 0, 2], [669, 329, 78, 38, 90, 2], [648, 458, 66, 40, 90, 2], [632, 545, 57, 40, 90, 2],
	[624, 643, 60, 42, 90, 2], [360, 456, 71, 42, 0, 2], [431, 456, 71, 42, 0, 2], [490, 655, 70, 40, 180, 2],
	[820, 326, 63, 44, 270, 2], [805, 421, 62, 40, 270, 2], [796, 520, 72, 44, 270, 2], [784, 594, 70, 36, 270, 2],
	[768, 688, 63, 40, 270, 2], [925, 322, 52, 46, 180, 2], [978, 330, 58, 42, 188, 2], [1078, 392, 62, 40, 250, 2],
	[1028, 508, 70, 40, 225, 2], [962, 572, 62, 40, 315, 2], [1010, 662, 70, 40, 225, 2], [883, 791, 80, 44, 210, 2],
	[975, 842, 80, 44, 210, 2], [1110, 676, 75, 42, 225, 2],
]
## The houses round the outside of the loop, fronting the lanes (scenery).
const OUTSIDE: Array = [
	[460, 86, 75, 42, 180, 2], [550, 115, 68, 38, 180, 2], [684, 30, 60, 44, 90, 2], [682, 110, 60, 44, 90, 2],
	[850, 35, 62, 46, 270, 2], [834, 138, 62, 44, 270, 2], [962, 165, 72, 40, 180, 2], [1058, 193, 68, 40, 190, 2],
	[1150, 228, 70, 40, 210, 2], [1230, 282, 70, 40, 225, 2], [1282, 370, 64, 42, 270, 2], [1245, 445, 62, 40, 270, 2],
	[1185, 545, 60, 42, 300, 2], [355, 225, 72, 42, 90, 2], [355, 300, 72, 42, 90, 2], [350, 120, 70, 40, 135, 2],
	[230, 420, 70, 44, 90, 2], [225, 520, 70, 44, 90, 2], [310, 690, 62, 44, 90, 2], [310, 760, 62, 44, 90, 2],
	[392, 800, 70, 40, 0, 2], [486, 802, 62, 42, 0, 2], [576, 806, 68, 38, 0, 2], [655, 832, 56, 44, 30, 2],
	[735, 870, 80, 40, 30, 2], [800, 962, 72, 40, 30, 2], [900, 990, 66, 42, 0, 2],
]


func _estate_houses() -> void:
	layer("Houses")
	for entry: Array in ESTATE:
		_place_house(entry)


## Places a house from a list entry. A house keeps [constant HOUSE_CLEARANCE] m from the walkable
## network, so the hedges and fences outside it never stand in a wall. Where the drawn footprint is
## too close (the street map's outlines are rough) it is nudged up to 2.1 m or made up to 25 %
## smaller, keeping as close to the drawing as it can; a house that still does not fit is left out.
func _place_house(entry: Array) -> void:
	var drawn := p(float(entry[0]), float(entry[1]))
	var facing_angle := deg_to_rad(float(entry[4]))
	var facing := Vector2(sin(facing_angle), -cos(facing_angle))
	var yaw := rad_to_deg(atan2(facing.x, facing.y))
	var along := Vector2(cos(deg_to_rad(yaw)), -sin(deg_to_rad(yaw)))
	var shifts: Array[Vector2] = [Vector2.ZERO]
	for step: float in [0.7, 1.4, 2.1]:
		shifts.append_array([Vector2(0, step), Vector2(0, -step), Vector2(step, 0), Vector2(-step, 0)])
	for scale: float in [1.0, 0.92, 0.84, 0.75]:
		for shift: Vector2 in shifts:
			var centre := drawn + along * shift.x + facing * shift.y
			var w := float(entry[2]) * S * scale
			var d := float(entry[3]) * S * scale
			var footprint := PackedVector2Array([centre - along * w / 2 - facing * d / 2, centre + along * w / 2 - facing * d / 2,
				centre + along * w / 2 + facing * d / 2, centre - along * w / 2 + facing * d / 2])
			if not blocked(footprint, HOUSE_CLEARANCE) and not overlaps_house(footprint):
				_houses.append(footprint)
				house(centre, along, facing, yaw, w, d, int(entry[5]), pick_at(drawn, 11))
				_open_front(centre, along, facing, w, d)
				return
	printerr("House at drawing ", entry[0], ",", entry[1], " touches a path; left out.")


## Opens the front of a house onto the street: where the network lies within 9 m in front of it,
## the hedge or fence across its front is left out (see [method _fences]) and a garden fence runs
## from each side of the house to the street instead, so nothing stands in front of the doors and
## the gardens behind stay closed.
func _open_front(centre: Vector2, along: Vector2, facing: Vector2, w: float, d: float) -> void:
	var front := centre + facing * (d / 2.0)
	var reach := _reach(front, facing, 9.0)
	if reach < 0.0:
		return
	var spread := FRONT_SPREAD
	var own: PackedVector2Array = _houses[_houses.size() - 1]
	for attempt: float in [FRONT_SPREAD, 0.2]:
		spread = attempt
		var wide := box_footprint(front + facing * ((reach + 1.5) / 2.0), facing, reach + 1.5, w + spread * 2.0)
		var clear := true
		for other: PackedVector2Array in _houses:
			if other != own and not Geometry2D.intersect_polygons(wide, other).is_empty():
				clear = false
		if clear:
			break
	_open_fronts.append(box_footprint(front + facing * ((reach + 1.5) / 2.0), facing, reach + 1.5, w + spread * 2.0))
	for side: float in [-1.0, 1.0]:
		var corner := front + along * (side * (w / 2.0 + spread))
		var to_street := _reach(corner, facing, reach + 1.5)
		if to_street < 0.0:
			to_street = reach
		_garden_fence(corner, corner + facing * to_street)
		if spread > 0.3:
			# Between the house and its side fence: mostly a gate to the back garden.
			var wall := front + along * (side * w / 2.0)
			if pick_at(wall, 8) % 4 != 0:
				var out := along * side
				_gate(wall + out * (GATE_WIDTH / 2.0), out, pick_at(wall, 6))
				_garden_fence(wall + out * GATE_WIDTH, corner)
			else:
				_garden_fence(corner, wall)


## How far from [param from] along [param dir] the walkable network starts, up to
## [param limit] m; -1 when it does not.
func _reach(from: Vector2, dir: Vector2, limit: float) -> float:
	var t := 0.1
	while t <= limit:
		for entry: Dictionary in _walk:
			if Geometry2D.is_point_in_polygon(from + dir * t, entry["poly"]):
				return t
		t += 0.1
	return -1.0


## A plank garden fence from [param a] to [param b].
func _garden_fence(a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	if length < 0.3:
		return
	var mid := (a + b) / 2.0
	put("wall", Vector3(mid.x, 0, mid.y), Vector3(length + 0.12, 1.85, 0.12), rad_to_deg(atan2(-(b.y - a.y), b.x - a.x)), {}, "planks")


## A semi like the ones on the street: brick ground floor, white upper floor, a gabled (now and
## then hipped) tile roof with a chimney stack and an aerial on the party wall; per half a front
## door under a little canopy at the outer end, a wide front window, two windows upstairs, back
## windows and a back door, a bin by the door and a gravel drive.
func house(centre: Vector2, along: Vector2, facing: Vector2, yaw: float, w: float, d: float, halves: int, pick: int) -> void:
	var upper: String = ["render", "render", "plaster_white", "red_brick"][pick % 4]
	put("building", Vector3(centre.x, 0, centre.y), Vector3(w, 2.7, d), yaw, {}, "red_brick")
	put("building", Vector3(centre.x, 2.7, centre.y), Vector3(w, EAVE - 2.7, d), yaw, {}, upper)
	put("block", Vector3(centre.x, 2.62, centre.y), Vector3(w + 0.06, 0.12, d + 0.06), yaw, {}, "concrete")
	roof(centre, along, facing, w / 2.0 + 0.3, d / 2.0 + 0.35, pick % 5 == 0, "slate" if pick % 7 == 0 else "roof_tile")
	var stack := centre + along * (0.0 if halves == 2 else w * 0.3)
	put("block", Vector3(stack.x, RIDGE - 1.2, stack.y), Vector3(1.0, 2.1, 0.7), yaw, {}, "red_brick")
	put("pillar", Vector3(stack.x + along.x * 0.3, RIDGE + 0.9, stack.y + along.y * 0.3), Vector3(0.06, 1.6, 0.06), 0.0, {}, "metal_dark")
	# The aerial's boom on top of the mast, pointing out over the front, with two elements.
	var boom := stack + along * 0.3 + facing * 0.2
	put("block", Vector3(boom.x, RIDGE + 2.45, boom.y), Vector3(0.05, 0.05, 1.3), yaw, {}, "metal_dark")
	for element: float in [-0.35, 0.35]:
		var at := boom + facing * element
		put("block", Vector3(at.x, RIDGE + 2.45, at.y), Vector3(0.7 if element < 0.0 else 0.45, 0.05, 0.05), yaw, {}, "metal_dark")
	var front := centre - along * w / 2.0 + facing * d / 2.0
	var back := centre + along * w / 2.0 - facing * d / 2.0
	var hw := w / float(halves)
	var doors: Array[String] = ["wood_dark", "cloth_red", "plaster_white", "cloth_blue"]
	for i: int in halves:
		var outer := i == 0
		var t0 := float(i) * hw
		var door_t := t0 + hw * (0.2 if outer else 0.8)
		var window_t := t0 + hw * (0.62 if outer else 0.38)
		fixture("door", front, along, facing, door_t, 0.0, Vector3(0.95, 2.05, 0.24), {"panels": 1, "fanlight": false},
			doors[(pick + i) % doors.size()], yaw)
		var canopy := front + along * door_t + facing * 0.45
		put("roof", Vector3(canopy.x, 2.25, canopy.y), Vector3(1.5, 0.08, 0.9), yaw, {}, "slate")
		fixture("window", front, along, facing, window_t, 0.9, Vector3(1.8, 1.2, 0.2), {"panes_x": 3, "panes_y": 1},
			"plaster_white", yaw)
		for upstairs: float in [0.28, 0.72]:
			fixture("window", front, along, facing, t0 + hw * upstairs, 3.3, Vector3(1.1, 1.1, 0.2), {"panes_x": 2, "panes_y": 1},
				"plaster_white", yaw)
		var bt := w - (t0 + hw * 0.5)
		fixture("window", back, -along, -facing, bt, 0.9, Vector3(1.6, 1.1, 0.2), {"panes_x": 2, "panes_y": 1}, "plaster_white", yaw + 180.0)
		fixture("window", back, -along, -facing, bt, 3.3, Vector3(1.1, 1.0, 0.2), {"panes_x": 2, "panes_y": 1}, "plaster_white", yaw + 180.0)
		# The drive at the outer end and a bin by the door, where the garden has room.
		var drive := front + along * (t0 + hw * (0.15 if outer else 0.85)) + facing * 2.6
		var apron := PackedVector2Array([drive - along * 1.4 - facing * 2.4, drive + along * 1.4 - facing * 2.4,
			drive + along * 1.4 + facing * 2.4, drive - along * 1.4 + facing * 2.4])
		if not blocked(apron, HOUSE_CLEARANCE) and not overlaps_house(apron):
			put("block", Vector3(drive.x, 0, drive.y), Vector3(2.8, 0.05, 4.8), yaw, {}, "gravel")
			if (pick + i) % 3 == 0:
				put("vehicle_car", Vector3(drive.x, 0.05, drive.y), Vector3.ZERO, yaw, {},
					["slate", "cloth_red", "plaster_white", "cloth_blue", "metal_dark"][(pick + i) % 5])
		var bin := front + along * (door_t + (0.9 if outer else -0.9)) + facing * 0.5
		put("block", Vector3(bin.x, 0, bin.y), Vector3(0.6, 1.1, 0.7), yaw, {}, ["metal_painted", "metal_dark", "cloth_blue"][(pick + i) % 3])


## A gable roof (or a hipped one) over a house turned to [param along]/[param facing], drawn as a
## brush: eaves [param hx] by [param hz] from the centre, ridge along the front.
func roof(centre: Vector2, along: Vector2, facing: Vector2, hx: float, hz: float, hipped: bool, material: String) -> void:
	var corners: Array[Vector2] = [centre - along * hx - facing * hz, centre + along * hx - facing * hz,
		centre + along * hx + facing * hz, centre - along * hx + facing * hz]
	var inset := minf(hz, hx - 0.1) if hipped else 0.0
	var ridge_a := centre - along * (hx - inset)
	var ridge_b := centre + along * (hx - inset)
	var vertices: Array = []
	for corner: Vector2 in corners:
		vertices.append([corner.x, EAVE, corner.y])
	vertices.append_array([[ridge_a.x, RIDGE, ridge_a.y], [ridge_b.x, RIDGE, ridge_b.y]])
	var faces: Array = [0, 1, 2, 0, 2, 3, 0, 4, 5, 0, 5, 1, 3, 2, 5, 3, 5, 4, 0, 3, 4, 1, 5, 2]
	studio.call("draw_brushes", [{"vertices": vertices, "faces": faces, "two_sided": true, "material": material}])


func _backdrop() -> void:
	layer("Houses round the estate (scenery)")
	for entry: Array in OUTSIDE:
		_place_house(entry)
	# The primary school beyond the school lane: a long single-storey brick block with a flat roof,
	# a band of windows and a playground fence.
	var school := p(1400, 760)
	put("building", Vector3(school.x, 0, school.y), Vector3(25, 4.2, 34), 0.0, {}, "red_brick")
	put("roof", Vector3(school.x, 4.2, school.y), Vector3(25.6, 0.4, 34.6), 0.0, {}, "metal_dark")
	put("block", Vector3(school.x - 12.55, 1.2, school.y), Vector3(0.12, 1.6, 30), 0.0, {}, "glass")
	put("building", Vector3(school.x - 6, 0, school.y - 24), Vector3(14, 6.5, 14), 0.0, {}, "red_brick")
	put("roof", Vector3(school.x - 6, 6.5, school.y - 24), Vector3(14.6, 0.4, 14.6), 0.0, {}, "metal_dark")


## B: the garage court. A row of flat-roofed lock-ups stands in its west half with a narrow gap
## behind them; the court's walls are the backs of gardens.
func _lockups() -> void:
	layer("Garage court (B)")
	var centre := p(499, 357)
	var w := 78.0 * S
	var d := 38.0 * S
	put("building", Vector3(centre.x, 0, centre.y), Vector3(d, 2.5, w), 0.0, {}, "red_brick")
	put("roof", Vector3(centre.x + 0.2, 2.5, centre.y), Vector3(d + 0.6, 0.15, w + 0.3), 0.0, {}, "concrete")
	var door_face := centre.x + d / 2.0
	var z := centre.y - w / 2.0 + 1.6
	var k := 0
	while z < centre.y + w / 2.0 - 1.2:
		put("block", Vector3(door_face + 0.04, 0, z), Vector3(0.08, 2.05, 2.3), 0.0, {},
			["metal_painted", "metal_rust", "cloth_blue", "metal_painted"][k % 4])
		z += 2.9
		k += 1
	# A car with its bonnet up, tyres, a skip and pallets for cover.
	put("vehicle_car", Vector3(p(572, 330).x, 0.07, p(572, 330).y), Vector3.ZERO, 15.0, {}, "cloth_red")
	put("barrel_cluster", Vector3(p(530, 460).x, 0.07, p(530, 460).y), Vector3(1.4, 0.9, 1.4), 0.0, {}, "rubber")
	put("shipping_container", Vector3(p(590, 445).x, 0.07, p(590, 445).y), Vector3(1.9, 1.5, 3.8), 80.0, {}, "hazard_paint")
	put("pallet", Vector3(p(545, 318).x, 0.07, p(545, 318).y), Vector3(1.2, 0.6, 1.0), 10.0)
	put("crate_stack", Vector3(p(522, 425).x, 0.07, p(522, 425).y), Vector3(2.4, 1.2, 1.2), 90.0, {}, "weathered_wood")


## A: the Green, the estate's grassed open space with a bench, a bin, goalposts and a
## sapling or two.
func _green() -> void:
	layer("The Green (A)")
	put("park_bench", Vector3(p(905, 380).x, 0.07, p(905, 380).y), Vector3.ZERO, 180.0)
	put("park_bench", Vector3(p(985, 400).x, 0.07, p(985, 400).y), Vector3.ZERO, 200.0)
	for post: Array in [[968, 445], [988, 430]]:
		put("pillar", Vector3(p(post[0], post[1]).x, 0.07, p(post[0], post[1]).y), Vector3(0.12, 2.0, 0.12), 0.0, {}, "plaster_white")
	var bar := (p(968, 445) + p(988, 430)) / 2.0
	put("block", Vector3(bar.x, 2.07, bar.y), Vector3(4.2, 0.12, 0.12), 37.0, {}, "plaster_white")
	for sapling: Array in [[870, 400], [1010, 395], [930, 455]]:
		put("tree", Vector3(p(sapling[0], sapling[1]).x, 0.07, p(sapling[0], sapling[1]).y), Vector3(2.6, 6.0, 2.6), 0.0,
			{"form": "broadleaf"}, "foliage")
	put("block", Vector3(p(880, 438).x, 0.07, p(880, 438).y), Vector3(1.8, 1.0, 0.9), 15.0, {}, "metal_painted")   # electricity box
	put("block", Vector3(p(1030, 400).x, 0.07, p(1030, 400).y), Vector3(0.6, 0.9, 0.6), 0.0, {}, "metal_dark")       # dog bin


# --- street furniture -----------------------------------------------------------------------------

const NORTH_ROAD: Array = [[432, 186], [600, 189], [740, 196], [870, 214], [1000, 240]]
const AVENUE: Array = [[740, 196], [728, 350], [718, 500], [705, 640], [695, 752]]
const BARNWELL_ROAD: Array = [[1010, 965], [900, 905], [790, 820], [700, 752]]
const CAR_COLOURS: Array[String] = ["slate", "cloth_red", "plaster_white", "cloth_blue", "metal_dark", "metal_painted"]


## Points every [param spacing] m along a drawn line, starting [param start] m in (half the spacing
## by default) and [param offset] m to its left (negative: to its right), each with the line's
## direction there: {"at": Vector2, "dir": Vector2}.
static func along_line(line: Array, spacing: float, offset: float, start: float = -1.0) -> Array[Dictionary]:
	var points := pts(line)
	var result: Array[Dictionary] = []
	var next := spacing / 2.0 if start < 0.0 else start
	var walked := 0.0
	for i: int in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		while next <= walked + length:
			result.append({"at": a + dir * (next - walked) + Vector2(-dir.y, dir.x) * offset, "dir": dir})
			next += spacing
		walked += length
	return result


## A rectangle [param length] along [param dir] by [param width] round [param at].
static func box_footprint(at: Vector2, dir: Vector2, length: float, width: float) -> PackedVector2Array:
	var side := Vector2(-dir.y, dir.x) * (width / 2.0)
	var ahead := dir * (length / 2.0)
	return PackedVector2Array([at - ahead - side, at + ahead - side, at + ahead + side, at - ahead + side])


## The yaw that turns a piece's local Z along [param dir] (its local X then lies across it).
static func yaw_along(dir: Vector2) -> float:
	return rad_to_deg(atan2(dir.x, dir.y))


## True when a [param length] by [param width] thing at [param point] lies wholly on roads and lanes,
## keeps [param clearance] m from every footpath, site and forecourt and 8 m from both spawns, so
## nothing parked or planted on a street stands in a hedge, blocks the mouth of a path or crowds a
## spawn.
func fits_on_road(point: Dictionary, length: float, width: float, clearance: float) -> bool:
	var at: Vector2 = point["at"]
	var footprint := box_footprint(at, point["dir"] as Vector2, length, width)
	var rest: Array[PackedVector2Array] = [footprint]
	for entry: Dictionary in _walk:
		if is_road(str(entry["kind"])):
			var kept: Array[PackedVector2Array] = []
			for part: PackedVector2Array in rest:
				kept.append_array(_cut(part, entry["poly"]))
			rest = kept
	for part: PackedVector2Array in rest:
		if absf(_area(part)) > 0.01:
			return false
	for spawn_px: Vector2 in [DEFENDERS, ATTACKERS]:
		if at.distance_to(p(spawn_px.x, spawn_px.y)) < 8.0:
			return false
	for grown: PackedVector2Array in Geometry2D.offset_polygon(footprint, clearance):
		for entry: Dictionary in _walk:
			if not is_road(str(entry["kind"])) and not Geometry2D.intersect_polygons(grown, entry["poly"]).is_empty():
				return false
	return true


## Parks a car (or a van) at each point that has room, turned along the street.
func park(points: Array[Dictionary], type: String, length: float, width: float) -> void:
	for point: Dictionary in points:
		var at: Vector2 = point["at"]
		if fits_on_road(point, length + 0.4, width + 0.2, 1.0):
			put(type, Vector3(at.x, 0.06, at.y), Vector3.ZERO, yaw_along(point["dir"] as Vector2), {},
				CAR_COLOURS[pick_at(at, 5) % CAR_COLOURS.size()])


## The points where an upright street thing [param size] m across has room on the pavement.
func street_points(points: Array[Dictionary], size: float) -> Array[Dictionary]:
	var used: Array[Dictionary] = []
	for point: Dictionary in points:
		if fits_on_road(point, size, size, 0.6):
			used.append(point)
	return used


func _street_furniture() -> void:
	layer("Street furniture")
	# Telegraph poles on one pavement with wires between neighbours; street lamps on the other.
	for line: Array in [[NORTH_ROAD, 3.55], [AVENUE, -4.05], [BARNWELL_ROAD, 3.55]]:
		var last := Vector2.INF
		for point: Dictionary in street_points(along_line(line[0] as Array, 26.0, float(line[1])), 0.4):
			var at: Vector2 = point["at"]
			put("pillar", Vector3(at.x, 0.06, at.y), Vector3(0.26, 8.4, 0.26), 0.0, {}, "weathered_wood")
			put("block", Vector3(at.x, 7.9, at.y), Vector3(1.5, 0.12, 0.14), yaw_along(point["dir"] as Vector2), {}, "weathered_wood")
			if last != Vector2.INF and last.distance_to(at) < 40.0:
				var mid := (last + at) / 2.0
				put("block", Vector3(mid.x, 7.95, mid.y), Vector3(0.05, 0.05, last.distance_to(at)), yaw_along(at - last), {}, "metal_dark")
			last = at
		for point: Dictionary in street_points(along_line(line[0] as Array, 30.0, -float(line[1]), 14.0), 0.4):
			var at: Vector2 = point["at"]
			put("lamp_post", Vector3(at.x, 0.06, at.y), Vector3(0.4, 6.0, 0.4), 0.0)
			lamp(Vector3(at.x, 5.6, at.y), 0.5, 8.0)   # faint by day; the lamp heads are lit
	# Cars parked down both sides of the avenue, staggered so no sightline runs its length, with a
	# van halfway; cars along the north road, Barnwell Road and the lanes.
	park(along_line(AVENUE, 26.0, 2.2, 8.0), "vehicle_car", 4.2, 1.9)
	park(along_line(AVENUE, 26.0, -2.2, 21.0), "vehicle_car", 4.2, 1.9)
	park(along_line(AVENUE, 1000.0, 1.9, 60.0), "vehicle_truck", 6.0, 2.4)
	park(along_line(NORTH_ROAD, 24.0, -1.85, 10.0), "vehicle_car", 4.2, 1.9)
	park(along_line(BARNWELL_ROAD, 24.0, 1.85, 6.0), "vehicle_car", 4.2, 1.9)
	park(along_line([[1000, 240], [1090, 280], [1150, 340], [1168, 410], [1140, 480], [1085, 540]], 40.0, 1.6), "vehicle_car", 4.2, 1.9)
	park(along_line([[700, 752], [560, 735], [432, 728]], 30.0, -1.6), "vehicle_car", 4.2, 1.9)
	# A skip on the west lane, bins out on the avenue's pavement, a post box and a phone cabinet on
	# the north road, and the street names.
	for point: Dictionary in along_line([[305, 530], [300, 440], [310, 352]], 12.0, 1.4, 6.0):
		if fits_on_road(point, 3.8, 2.0, 1.0):
			var at: Vector2 = point["at"]
			put("shipping_container", Vector3(at.x, 0.06, at.y), Vector3(1.8, 1.4, 3.6), yaw_along(point["dir"] as Vector2), {}, "hazard_paint")
			break
	for point: Dictionary in street_points(along_line(AVENUE, 37.0, 3.9, 30.0), 0.8):
		var at: Vector2 = point["at"]
		put("block", Vector3(at.x, 0.06, at.y), Vector3(0.6, 1.1, 0.7), yaw_along(point["dir"] as Vector2), {}, "metal_painted")
	var corner := street_points(along_line(NORTH_ROAD, 7.0, -3.3, 30.0), 1.3)
	if corner.size() >= 2:
		var box: Vector2 = corner[0]["at"]
		put("column", Vector3(box.x, 0.06, box.y), Vector3(0.5, 1.1, 0.5), 0.0, {}, "cloth_red")
		put("block", Vector3(box.x, 1.16, box.y), Vector3(0.6, 0.12, 0.6), 0.0, {}, "metal_dark")
		var cabinet: Vector2 = corner[1]["at"]
		put("block", Vector3(cabinet.x, 0.06, cabinet.y), Vector3(1.2, 1.3, 0.5), yaw_along(corner[1]["dir"] as Vector2) + 90.0, {}, "metal_painted")
	for sign: Array in [["EDINBURGH AVENUE", AVENUE, 4.3], ["BARNWELL ROAD", BARNWELL_ROAD, -3.8]]:
		for point: Dictionary in along_line(sign[1] as Array, 4.0, float(sign[2]), 12.0):
			if fits_on_road(point, 2.0, 0.3, 0.6):
				var at: Vector2 = point["at"]
				put("enamel_sign", Vector3(at.x, 0.3, at.y), Vector3(2.0, 0.4, 0.06), yaw_along(point["dir"] as Vector2) + 90.0,
					{"text": sign[0]}, "metal_dark")
				break


## Trees in the gardens all round: poplars, broadleaf trees and the odd conifer, kept off the
## houses and back from the paths so they shade the lanes without standing in them.
func _trees() -> void:
	layer("Trees")
	var keep_clear: Array[PackedVector2Array] = []
	for entry: Dictionary in _walk:
		keep_clear.append_array(Geometry2D.offset_polygon(entry["poly"], 2.0))
	for footprint: PackedVector2Array in _houses:
		keep_clear.append_array(Geometry2D.offset_polygon(footprint, 1.6))
	var x := -96.0
	while x < 146.0:
		var z := -72.0
		while z < 102.0:
			var pick := pick_at(Vector2(x, z), 21)
			var at := Vector2(x + float(pick % 7) - 3.0, z + float((pick / 7) % 7) - 3.0)
			var clear := pick % 10 < 6
			for area_poly: PackedVector2Array in keep_clear:
				if clear and Geometry2D.is_point_in_polygon(at, area_poly):
					clear = false
			if clear:
				var form: String = ["broadleaf", "broadleaf", "poplar", "broadleaf", "poplar", "conifer"][pick % 6]
				var height := 9.0 + float(pick % 5)
				var width := 5.5 + float(pick % 3)
				if form == "poplar":
					height += 5.0
					width = 2.6
				put("tree", Vector3(at.x, 0, at.y), Vector3(width, height, width), 0.0, {"form": form}, "foliage")
			z += 9.0
		x += 9.0


# --- gameplay -------------------------------------------------------------------------------------

func _gameplay() -> void:
	layer("Gameplay")
	var defenders := p(DEFENDERS.x, DEFENDERS.y)
	var attackers := p(ATTACKERS.x, ATTACKERS.y)
	spawns("defence", Vector3(defenders.x, 0.06, defenders.y), 180.0, Vector3(12, 3, 6))
	spawns("attack", Vector3(attackers.x, 0.06, attackers.y), 320.0, Vector3(12, 3, 6))
	var a := p(SITE_A.x, SITE_A.y)
	var b := p(SITE_B.x, SITE_B.y)
	put("bombsite", Vector3(a.x, 0.07, a.y), Vector3(14, 3, 12), 0.0, {"site": "A"})
	put("bombsite", Vector3(b.x, 0.07, b.y), Vector3(14, 3, 12), 0.0, {"site": "B"})


## A callout over a rectangle of the drawing.
func callout(name: String, x1: float, y1: float, x2: float, y2: float, role: String = "") -> void:
	var a := p(x1, y1)
	var b := p(x2, y2)
	area(name, a.x, b.x, a.y, b.y, role, 0.05)


func _callouts() -> void:
	layer("Tactics")
	callout("Barnwell Road", 790, 800, 1010, 965)
	callout("Defenders' Corner", 636, 205, 735, 286)
	callout("Top Avenue", 700, 286, 760, 380)
	callout("Mid Avenue", 690, 380, 750, 560, "mid")
	callout("Bottom Avenue", 680, 560, 730, 752)
	callout("North Road", 432, 165, 1000, 205)
	callout("North Path", 605, 215, 636, 296, "entrance_b")
	callout("Garage Court", 520, 296, 612, 488)
	callout("Lock-ups", 472, 300, 520, 474)
	callout("West Path", 320, 405, 470, 430, "entrance_b")
	callout("Avenue Path", 612, 395, 700, 420, "entrance_b")
	callout("Back Gate", 535, 482, 560, 505, "entrance_b")
	callout("Back Alley", 370, 485, 535, 505)
	callout("Allotment Path", 476, 505, 530, 605)
	callout("Ginnel", 528, 505, 552, 730)
	callout("Dog Leg", 560, 505, 700, 605)
	callout("West Lane", 282, 345, 450, 560)
	callout("South Lane", 410, 560, 700, 760)
	callout("North Alley", 840, 215, 890, 350)
	callout("Avenue Gap", 755, 455, 850, 482)
	callout("Gap Corner", 850, 450, 886, 480, "entrance_a")
	callout("The Green", 886, 350, 1050, 450)
	callout("Green Gate", 840, 482, 866, 525, "entrance_a")
	callout("Garden Path", 798, 525, 862, 700)
	callout("Paddock", 862, 585, 972, 745)
	callout("Back Gardens", 755, 700, 860, 790)
	callout("Field Gate", 930, 745, 1060, 860)
	callout("SE Alley", 1000, 500, 1050, 585)
	callout("SE Corner", 980, 488, 1000, 525, "entrance_a")
	callout("East Lane", 1000, 240, 1170, 585)
	callout("Field Path", 1045, 590, 1240, 665)
	callout("School Lane", 1010, 665, 1240, 965)


func _tactical() -> void:
	layer("Tactics")
	var a := p(SITE_A.x, SITE_A.y)
	var b := p(SITE_B.x, SITE_B.y)
	anchor("Green benches", "plant", Vector3(a.x - 3, 0.07, a.y - 2))
	anchor("Green goalposts", "plant", Vector3(a.x + 4, 0.07, a.y + 2))
	anchor("Court lock-ups", "plant", Vector3(b.x - 4, 0.07, b.y + 2))
	anchor("Court skip", "plant", Vector3(b.x + 3, 0.07, b.y - 3))
	anchor("Avenue hold", "default", Vector3(p(720, 470).x, 0.06, p(720, 470).y))
	anchor("Garden Path hold", "default", Vector3(p(809, 640).x, 0.06, p(809, 640).y))
	anchor("Ginnel hold", "default", Vector3(p(542, 620).x, 0.06, p(542, 620).y))
	anchor("Avenue Gap smoke", "utility", Vector3(p(860, 468).x, 0.06, p(860, 468).y))
	anchor("Green Gate smoke", "utility", Vector3(p(854, 500).x, 0.06, p(854, 500).y))
	anchor("Back Gate smoke", "utility", Vector3(p(548, 490).x, 0.06, p(548, 490).y))
	anchor("Avenue Path smoke", "utility", Vector3(p(620, 405).x, 0.06, p(620, 405).y))
	for hold: Array in [[960, 380, 200.0, "A"], [1020, 420, 230.0, "A"], [900, 400, 150.0, "A"],
			[590, 330, 200.0, "B"], [540, 460, 20.0, "B"], [595, 470, 330.0, "B"]]:
		hint("ai_hold", Vector3(p(hold[0], hold[1]).x, 0.07, p(hold[0], hold[1]).y), float(hold[2]), str(hold[3]))
	for cover: Array in [[970, 425, 180.0, "A"], [905, 385, 180.0, "A"], [575, 340, 180.0, "B"], [590, 440, 0.0, "B"]]:
		hint("ai_cover", Vector3(p(cover[0], cover[1]).x, 0.07, p(cover[0], cover[1]).y), float(cover[2]), str(cover[3]))
	for angle: Array in [[870, 462, 90.0, "A"], [856, 495, 0.0, "A"], [605, 404, 270.0, "B"], [548, 482, 0.0, "B"]]:
		hint("ai_angle", Vector3(p(angle[0], angle[1]).x, 0.07, p(angle[0], angle[1]).y), float(angle[2]), str(angle[3]))


func _check(analysis: MapAnalysis) -> bool:
	var ok := true
	var defenders := p(DEFENDERS.x, DEFENDERS.y)
	var attackers := p(ATTACKERS.x, ATTACKERS.y)
	for route: Array in [["defenders → A", defenders, p(SITE_A.x, SITE_A.y)], ["defenders → B", defenders, p(SITE_B.x, SITE_B.y)],
			["attackers → A", attackers, p(SITE_A.x, SITE_A.y)], ["attackers → B", attackers, p(SITE_B.x, SITE_B.y)],
			["attackers → West Path", attackers, p(320, 416)], ["attackers → North Alley", attackers, p(870, 280)]]:
		var from: Vector2 = route[1]
		var to: Vector2 = route[2]
		var length := analysis.path_length(Vector3(from.x, 0.06, from.y), Vector3(to.x, 0.07, to.y))
		print("%s: %.1f m" % [route[0], length])
		if length < 0.0:
			printerr("No route: ", route[0])
			ok = false
	return ok and analysis.issues.is_empty()
