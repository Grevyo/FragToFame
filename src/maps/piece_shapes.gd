class_name PieceShapes
extends RefCounted
## Solid parts of "compound" catalogue pieces. A part is a Dictionary:
##   {"shape": "box" | "cylinder", "size": Vector3, "pos": Vector3 (part centre, relative to the
##    piece's bottom-centre origin), "rot": Vector3 (degrees), "mat": String (fixed material id,
##    "" = the piece's material)}
## For cylinders size.x is the diameter and size.y the height (axis along local Y before "rot").
## MapBuilder creates one mesh AND one identical collider per part, so collision always matches
## what the player sees. All measurements derive from the piece size and props, so resized
## pieces stay consistent.

const MIN_OPENING: float = 0.8


static func parts(type: String, size: Vector3, props: Dictionary) -> Array[Dictionary]:
	match type:
		"doorway":
			return _opening(size, _opening_width(size, props, 1.4), _opening_height(size, props, 2.2), 0.0)
		"double_door":
			return _double_door(size, props)
		"arch":
			return _arch(size, props)
		"wall_window":
			return _opening(size, _opening_width(size, props, 1.6), _opening_height(size, props, 2.2),
				clampf(float(props.get("sill_height", 1.0)), 0.2, size.y - 0.6))
		"wall_parapet":
			return _parapet(size)
		"wall_battlement":
			return _battlement(size, props)
		"tower_round":
			return _tower(size)
		"catwalk":
			return _catwalk(size, props)
		"railing":
			return _railing(size)
		"gate_portcullis":
			return _portcullis(size, props)
		"pipe_run":
			return _pipe_run(size)
		"storage_tank":
			return _storage_tank(size)
		"banner":
			return _banner(size)
		"tree":
			return _tree(size)
		"shipping_container":
			return _container(size)
		"column":
			return [_cyl(minf(size.x, size.z), size.y, Vector3(0, size.y / 2.0, 0))]
		"crate_stack":
			return _crate_stack(size)
		"barrel":
			return [_cyl(minf(size.x, size.z), size.y, Vector3(0, size.y / 2.0, 0))]
		"barrel_cluster":
			return _barrel_cluster(size)
		"well":
			return _well(size)
		"kiln":
			return _kiln(size)
		"awning":
			return _awning(size)
		"pottery_jar":
			return _pottery_jar(size)
		"coopered_barrel":
			return _coopered_barrel(size)
		"braced_crate":
			return _braced_crate(size)
		"stone_bench":
			return _stone_bench(size)
		"market_shelf":
			return _market_shelf(size)
		"quay_fence":
			return _paling_fence(size, props)
		"freight_gate":
			return _freight_gate(size)
		"shutter_panel":
			return _shutter_panel(size, props)
		"signal_ball":
			var body := _turned_body(size, [Vector2(0.43,0.12), Vector2(0.47,0.62), Vector2(0.55,0.94),
				Vector2(0.62,1), Vector2(0.69,0.94), Vector2(0.77,0.62), Vector2(0.81,0.12)])
			body.append(_cyl(minf(size.x,size.z)*0.11, size.y, Vector3.UP * size.y * 0.5, "metal_dark"))
			return body
		"transit_scope":
			return _transit_scope(size)
		"stone_trough":
			return _stone_trough(size)
		"sandbag_wall":
			return _sandbags(size)
		"market_stall":
			return _market_stall(size)
		"cloth_screen":
			return _cloth_screen(size)
		"vehicle_truck":
			return _truck(size)
		"vehicle_car":
			return _car(size)
		"vehicle_cart":
			return _cart(size)
	return [_box(size, Vector3(0, size.y / 2.0, 0))]


static func _paling_fence(size: Vector3, props: Dictionary) -> Array[Dictionary]:
	var spacing := clampf(float(props.get("spacing", 0.36)), 0.18, 0.55)
	var bars := clampi(ceili(size.x / spacing), 2, 256)
	var pitch := size.x / bars
	var parts: Array[Dictionary] = []
	for i in bars:
		var width := minf(pitch * 0.32, 0.10 if i % 8 == 0 else 0.055)
		var height := size.y * (1.0 if i % 8 == 0 else 0.95)
		parts.append(_box(Vector3(width,height,size.z*0.6),Vector3((i+0.5)*pitch-size.x/2,height/2,-size.z*0.2)))
	for fraction: float in [0.24,0.76]:
		parts.append(_box(Vector3(size.x,minf(size.y*0.08,0.11),size.z*0.4),
			Vector3(0,size.y*fraction,size.z*0.3)))
	return parts


static func _freight_gate(size: Vector3) -> Array[Dictionary]:
	var post := minf(size.x * 0.09,0.28)
	var leaf := (size.x-2*post)*0.5
	var parts: Array[Dictionary] = []
	for side: int in [-1,1]:
		parts.append(_box(Vector3(post,size.y,size.z),Vector3(side*(size.x-post)/2,size.y/2,0),"granite_blocks"))
		parts.append(_box(Vector3(leaf*0.995,size.y*0.93,size.z*0.5),
			Vector3(side*leaf/2,size.y*0.465,0)))
		for band: float in [0.18,0.78]:
			parts.append(_box(Vector3(leaf*0.94,size.y*0.045,size.z*0.16),
				Vector3(side*leaf/2,size.y*band,size.z*0.33),"metal_dark"))
	return parts


static func _shutter_panel(size: Vector3, props: Dictionary) -> Array[Dictionary]:
	var count := clampi(int(props.get("slats", 8)), 2, 20)
	var pitch := size.y / count
	var tilt := clampf(float(props.get("tilt", 25)), 0, 70)
	var depth := size.z * 0.3
	var blade := minf(pitch * 0.85, (size.z - depth) / maxf(sin(deg_to_rad(tilt)), 0.01))
	var parts: Array[Dictionary] = []
	var rail := minf(size.x * 0.1, 0.12)
	for side: int in [-1, 1]:
		parts.append(_box(Vector3(rail,size.y,size.z),Vector3(side*(size.x-rail)*0.5,size.y*0.5,0),"metal_dark"))
	for i in count:
		parts.append(_box(Vector3(size.x - 2 * rail, blade, depth),
			Vector3(0, pitch * (i + 0.5), 0), "", Vector3(tilt, 0, 0)))
	return parts


static func _box(size: Vector3, pos: Vector3, mat: String = "", rot: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"shape": "box", "size": size, "pos": pos, "rot": rot, "mat": mat}


static func _cyl(diameter: float, height: float, pos: Vector3, mat: String = "", rot: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"shape": "cylinder", "size": Vector3(diameter, height, diameter), "pos": pos, "rot": rot, "mat": mat}


## Builds a turned profile from (fractional height, radius as a fraction of the widest point).
static func _turned_body(size: Vector3, profile: Array[Vector2]) -> Array[Dictionary]:
	var diameter := minf(size.x, size.z)
	var sections: Array[Dictionary] = []
	for index: int in profile.size() - 1:
		var bottom := profile[index]
		var top := profile[index + 1]
		var part := _cyl(diameter, (top.x - bottom.x) * size.y,
			Vector3(0.0, (bottom.x + top.x) * size.y / 2.0, 0.0))
		part["bottom_radius_scale"] = bottom.y
		part["top_radius_scale"] = top.y
		sections.append(part)
	return sections


static func _pottery_jar(size: Vector3) -> Array[Dictionary]:
	var sections := _turned_body(size, [
		Vector2(0.0, 0.55), Vector2(0.09, 0.62), Vector2(0.45, 1.0),
		Vector2(0.66, 0.92), Vector2(0.83, 0.48), Vector2(0.91, 0.48),
		Vector2(0.94, 0.61), Vector2(0.98, 0.49), Vector2(1.0, 0.18),
	])
	sections.append(_cyl(minf(size.x, size.z) * 0.56, size.y * 0.034,
		Vector3(0.0, size.y * 0.88, 0.0), "mud_brick"))
	return sections


static func _coopered_barrel(size: Vector3) -> Array[Dictionary]:
	var sections := _turned_body(size, [
		Vector2(0.0, 0.79), Vector2(0.19, 0.89), Vector2(0.44, 1.0),
		Vector2(0.56, 1.0), Vector2(0.81, 0.89), Vector2(1.0, 0.79),
	])
	for band_height: float in [0.17, 0.83]:
		sections.append(_cyl(minf(size.x, size.z) * 0.92, size.y * 0.055,
			Vector3(0.0, size.y * band_height, 0.0), "metal_dark"))
	return sections


static func _braced_crate(size: Vector3) -> Array[Dictionary]:
	var parts: Array[Dictionary] = [_box(size * Vector3(0.94, 0.98, 0.92), Vector3(0, size.y * 0.49, 0))]
	var diagonal := Vector2(size.x * 0.76, size.y * 0.68)
	for side: float in [-1.0, 1.0]:
		var z := size.z * 0.478 * side
		parts.append(_box(Vector3(diagonal.length(), size.y * 0.12, size.z * 0.044),
			Vector3(0, size.y * 0.5, z), "wood_dark", Vector3(0, 0, rad_to_deg(diagonal.angle()) * side)))
		for rail: float in [0.13, 0.87]:
			parts.append(_box(Vector3(size.x * 0.95, size.y * 0.12, size.z * 0.044),
				Vector3(0, size.y * rail, z), "wood_dark"))
	return parts


static func _stone_bench(size: Vector3) -> Array[Dictionary]:
	var parts: Array[Dictionary] = [_box(Vector3(size.x, size.y * 0.15, size.z), Vector3(0, size.y * 0.925, 0))]
	for side: float in [-1.0, 1.0]:
		parts.append(_box(Vector3(size.x * 0.14, size.y * 0.85, size.z * 0.72),
			Vector3(side * size.x * 0.36, size.y * 0.425, 0.0)))
	parts.append(_box(Vector3(size.x * 0.76, size.y * 0.12, size.z * 0.2),
		Vector3(0.0, size.y * 0.35, 0.0), "wood_dark"))
	return parts


static func _market_shelf(size: Vector3) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	for shelf: float in [0.17, 0.52, 0.87]:
		parts.append(_box(Vector3(size.x, size.y * 0.048, size.z),
			Vector3(0.0, size.y * shelf, 0.0)))
	for x_side: float in [-1.0, 1.0]:
		for z_side: float in [-1.0, 1.0]:
			parts.append(_box(Vector3(size.x * 0.055, size.y, size.z * 0.13),
				Vector3(x_side * size.x * 0.46, size.y * 0.5, z_side * size.z * 0.42), "wood_dark"))
	parts.append(_box(Vector3(size.x * 0.87, size.y * 0.055, size.z * 0.08),
		Vector3(0.0, size.y * 0.31, size.z * 0.45), "wood_dark"))
	return parts


static func _stone_trough(size: Vector3) -> Array[Dictionary]:
	var parts: Array[Dictionary] = [_box(Vector3(size.x, size.y * 0.32, size.z), Vector3(0.0, size.y * 0.16, 0.0))]
	var y := size.y * 0.66
	var wall_height := size.y * 0.68
	var wall_depth := minf(size.x, size.z) * 0.15
	for side: float in [-1.0, 1.0]:
		parts.append(_box(Vector3(size.x, wall_height, wall_depth),
			Vector3(0.0, y, side * (size.z - wall_depth) / 2.0)))
		parts.append(_box(Vector3(wall_depth, wall_height, size.z - wall_depth * 2.0),
			Vector3(side * (size.x - wall_depth) / 2.0, y, 0.0), "sandstone"))
	return parts


static func _opening_width(size: Vector3, props: Dictionary, fallback: float) -> float:
	return clampf(float(props.get("opening_width", fallback)), MIN_OPENING, maxf(MIN_OPENING, size.x - 0.4))


static func _opening_height(size: Vector3, props: Dictionary, fallback: float) -> float:
	return clampf(float(props.get("opening_height", fallback)), 1.0, maxf(1.0, size.y - 0.2))


## A wall with a centred rectangular hole from [param sill] up to [param top].
static func _opening(size: Vector3, width: float, top: float, sill: float) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var jamb := (size.x - width) / 2.0
	for side: float in [-1.0, 1.0]:
		list.append(_box(Vector3(jamb, size.y, size.z), Vector3(side * (width + jamb) / 2.0, size.y / 2.0, 0)))
	if size.y - top > 0.01:
		list.append(_box(Vector3(width, size.y - top, size.z), Vector3(0, top + (size.y - top) / 2.0, 0)))
	if sill > 0.01:
		list.append(_box(Vector3(width, sill, size.z), Vector3(0, sill / 2.0, 0)))
	return list


static func _double_door(size: Vector3, props: Dictionary) -> Array[Dictionary]:
	var width := _opening_width(size, props, 2.4)
	var top := _opening_height(size, props, 2.4)
	var list := _opening(size, width, top, 0.0)
	# Zero closes a leaf toward the centre, positive angles open toward local -Z.
	var leaf := width / 2.0
	var angles: Array[float] = [float(props.get("left_swing", 90.0)), float(props.get("right_swing", 90.0))]
	for i: int in angles.size():
		var side := float(i * 2 - 1)
		var swing := clampf(angles[i], -180.0, 180.0)
		var yaw := side * (90.0 - swing)
		var hinge := Vector3(side * (width / 2.0 + 0.04), top / 2.0, -size.z / 2.0)
		var centre := hinge + (Vector3.FORWARD * (leaf / 2.0)).rotated(Vector3.UP, deg_to_rad(yaw))
		list.append(_box(Vector3(0.08, top, leaf), centre, "wood_dark", Vector3(0, yaw, 0)))
	return list


## Jambs, a stepped round arch above the spring line, and solid wall above the crown.
static func _arch(size: Vector3, props: Dictionary) -> Array[Dictionary]:
	var width := _opening_width(size, props, 2.4)
	var spring := clampf(float(props.get("opening_height", 2.2)), 1.0, maxf(1.0, size.y - 0.6))
	var rise := minf(width / 2.0, size.y - spring - 0.2)
	var list := _opening(size, width, spring + rise, 0.0)
	var steps := 4
	for k: int in steps:
		var band := rise / float(steps)
		var mid := (float(k) + 0.5) / float(steps)
		var half_open := (width / 2.0) * sqrt(maxf(0.0, 1.0 - mid * mid))
		var fill := width / 2.0 - half_open
		if fill < 0.03:
			continue
		for side: float in [-1.0, 1.0]:
			list.append(_box(Vector3(fill, band, size.z),
				Vector3(side * (half_open + fill / 2.0), spring + band * (float(k) + 0.5), 0)))
	return list


static func _parapet(size: Vector3) -> Array[Dictionary]:
	var base := size.y * 0.65
	var list: Array[Dictionary] = [_box(Vector3(size.x, base, size.z), Vector3(0, base / 2.0, 0))]
	var slots := maxi(3, int(round(size.x / 0.6)) | 1)
	var slot := size.x / float(slots)
	for i: int in range(0, slots, 2):
		list.append(_box(Vector3(slot, size.y - base, size.z),
			Vector3(-size.x / 2.0 + slot * (float(i) + 0.5), base + (size.y - base) / 2.0, 0)))
	return list


static func _crate_stack(size: Vector3) -> Array[Dictionary]:
	var crate := Vector3(size.x / 2.0, size.y / 2.0, size.z)
	return [
		_box(crate, Vector3(-crate.x / 2.0, crate.y / 2.0, 0)),
		_box(crate, Vector3(crate.x / 2.0, crate.y / 2.0, 0)),
		_box(crate, Vector3(0, crate.y * 1.5, 0)),
	]


static func _barrel_cluster(size: Vector3) -> Array[Dictionary]:
	var diameter := minf(size.x * 0.47, size.z * 0.5)
	return [
		_cyl(diameter, size.y, Vector3(-size.x / 4.0, size.y / 2.0, size.z / 4.0)),
		_cyl(diameter, size.y, Vector3(size.x / 4.0, size.y / 2.0, size.z / 4.0)),
		_cyl(diameter, size.y * 0.9, Vector3(0, size.y * 0.45, -size.z / 4.0), "metal_painted"),
	]


static func _well(size: Vector3) -> Array[Dictionary]:
	var diameter := minf(size.x, size.z)
	return [
		_cyl(diameter, size.y, Vector3(0, size.y / 2.0, 0)),
		_cyl(diameter * 0.78, 0.06, Vector3(0, size.y + 0.03, 0), "water"),
	]


static func _kiln(size: Vector3) -> Array[Dictionary]:
	var diameter := minf(size.x, size.z)
	return [
		_cyl(diameter, size.y * 0.6, Vector3(0, size.y * 0.3, 0)),
		_cyl(diameter * 0.72, size.y * 0.25, Vector3(0, size.y * 0.725, 0)),
		_cyl(diameter * 0.28, size.y * 0.15, Vector3(0, size.y * 0.925, 0), "metal_rust"),
	]


## Two front posts and a canopy that drops 0.5 m from the back (-Z, wall side) to the front.
static func _awning(size: Vector3) -> Array[Dictionary]:
	var drop := 0.5
	var list: Array[Dictionary] = []
	for side: float in [-1.0, 1.0]:
		list.append(_box(Vector3(0.1, size.y - drop, 0.1),
			Vector3(side * (size.x / 2.0 - 0.05), (size.y - drop) / 2.0, size.z / 2.0 - 0.05), "wood_dark"))
	var length := sqrt(size.z * size.z + drop * drop)
	list.append(_box(Vector3(size.x, 0.06, length), Vector3(0, size.y - drop / 2.0, 0), "",
		Vector3(rad_to_deg(atan2(drop, size.z)), 0, 0)))
	return list


static func _sandbags(size: Vector3) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var layers := 3
	var layer_height := size.y / float(layers)
	for i: int in layers:
		list.append(_box(Vector3(size.x - 0.3 * float(i), layer_height, maxf(0.3, size.z - 0.15 * float(i))),
			Vector3(0, layer_height * (float(i) + 0.5), 0)))
	return list


static func _market_stall(size: Vector3) -> Array[Dictionary]:
	var counter := 0.9
	var list: Array[Dictionary] = [
		_box(Vector3(size.x, counter, size.z * 0.5), Vector3(0, counter / 2.0, size.z * 0.25)),
		_box(Vector3(size.x, size.y - counter, 0.06), Vector3(0, counter + (size.y - counter) / 2.0, -size.z / 2.0 + 0.03)),
		_box(Vector3(size.x, 0.08, size.z), Vector3(0, size.y - 0.04, 0), "cloth_striped"),
	]
	for side: float in [-1.0, 1.0]:
		list.append(_box(Vector3(0.1, size.y - 0.08, 0.1),
			Vector3(side * (size.x / 2.0 - 0.05), (size.y - 0.08) / 2.0, size.z / 2.0 - 0.05), "wood_dark"))
	return list


static func _cloth_screen(size: Vector3) -> Array[Dictionary]:
	var gap := 0.4
	var list: Array[Dictionary] = [
		_box(Vector3(size.x - 0.2, size.y - gap, 0.04), Vector3(0, gap + (size.y - gap) / 2.0, 0)),
	]
	for side: float in [-1.0, 1.0]:
		list.append(_box(Vector3(0.1, size.y, minf(size.z, 0.1)), Vector3(side * (size.x / 2.0 - 0.05), size.y / 2.0, 0), "wood_dark"))
	return list


static func _wheels(list: Array[Dictionary], half_track: float, diameter: float, width: float, axles: Array[float]) -> void:
	for z: float in axles:
		for side: float in [-1.0, 1.0]:
			list.append(_cyl(diameter, width, Vector3(side * half_track, diameter / 2.0, z), "rubber", Vector3(0, 0, 90)))


## Cab at the front (-Z), canvas-covered cargo bed behind it.
static func _truck(size: Vector3) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var deck := 0.85
	_wheels(list, size.x / 2.0 - 0.15, 0.9, 0.3, [-size.z * 0.32, size.z * 0.3])
	list.append(_box(Vector3(size.x * 0.85, 0.25, size.z), Vector3(0, deck - 0.125, 0), "metal_dark"))
	list.append(_box(Vector3(size.x, (size.y - deck) * 0.8, size.z * 0.26), Vector3(0, deck + (size.y - deck) * 0.4, -size.z * 0.37)))
	list.append(_box(Vector3(size.x, size.y - deck, size.z * 0.66), Vector3(0, deck + (size.y - deck) / 2.0, size.z * 0.16), "canvas"))
	return list


static func _car(size: Vector3) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	_wheels(list, size.x / 2.0 - 0.11, 0.66, 0.22, [-size.z * 0.3, size.z * 0.3])
	list.append(_box(Vector3(size.x, 0.6, size.z), Vector3(0, 0.3 + 0.3, 0)))
	list.append(_box(Vector3(size.x * 0.9, size.y - 0.9, size.z * 0.5), Vector3(0, 0.9 + (size.y - 0.9) / 2.0, size.z * 0.05), "metal_dark"))
	return list


static func _cart(size: Vector3) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	_wheels(list, size.x / 2.0 - 0.05, 0.9, 0.1, [0.0])
	var bed_length := size.z * 0.75
	list.append(_box(Vector3(size.x - 0.24, 0.15, bed_length), Vector3(0, 0.7, -size.z * 0.125 + bed_length * 0.0)))
	for side: float in [-1.0, 1.0]:
		list.append(_box(Vector3(0.06, size.y - 0.775, bed_length),
			Vector3(side * (size.x / 2.0 - 0.15), 0.775 + (size.y - 0.775) / 2.0, -size.z * 0.125)))
		list.append(_box(Vector3(0.06, 0.06, size.z * 0.25), Vector3(side * (size.x / 2.0 - 0.3), 0.7, size.z * 0.375), "wood_dark"))
	list.append(_box(Vector3(0.08, 0.625, 0.08), Vector3(0, 0.3125, -size.z * 0.4), "wood_dark"))
	return list


## A full-height wall crowned with merlons ([code]merlon_height[/code], default 0.9 m).
static func _battlement(size: Vector3, props: Dictionary) -> Array[Dictionary]:
	var merlon := clampf(float(props.get("merlon_height", 0.9)), 0.3, maxf(0.3, size.y - 0.5))
	var base := size.y - merlon
	var list: Array[Dictionary] = [_box(Vector3(size.x, base, size.z), Vector3(0, base / 2.0, 0))]
	var slots := maxi(3, int(round(size.x / 0.8)) | 1)
	var slot := size.x / float(slots)
	for i: int in range(0, slots, 2):
		list.append(_box(Vector3(slot, merlon, size.z),
			Vector3(-size.x / 2.0 + slot * (float(i) + 0.5), base + merlon / 2.0, 0)))
	return list


## A solid round tower with an overhanging ring and merlons around its top.
static func _tower(size: Vector3) -> Array[Dictionary]:
	var diameter := minf(size.x, size.z)
	var merlon := minf(0.9, size.y * 0.2)
	var ring := minf(0.5, size.y * 0.1)
	var body := size.y - merlon - ring
	var list: Array[Dictionary] = [
		_cyl(diameter * 0.92, body, Vector3(0, body / 2.0, 0)),
		_cyl(diameter, ring, Vector3(0, body + ring / 2.0, 0)),
	]
	var count := maxi(8, int(round(PI * diameter / 0.9)))
	count += count % 2
	var depth := minf(0.5, diameter * 0.12)
	for i: int in range(0, count, 2):
		var angle := TAU * float(i) / float(count)
		var radius := diameter / 2.0 - depth / 2.0
		list.append(_box(Vector3(PI * diameter / float(count) * 0.95, merlon, depth),
			Vector3(sin(angle) * radius, body + ring + merlon / 2.0, cos(angle) * radius), "", Vector3(0, rad_to_deg(angle), 0)))
	return list


## A thin walkable deck (its top is 0.12 m above the base) with railings on its long sides.
## [code]rail_left[/code] / [code]rail_right[/code] switch each side off.
static func _catwalk(size: Vector3, props: Dictionary) -> Array[Dictionary]:
	var deck := minf(0.12, size.y)
	var list: Array[Dictionary] = [_box(Vector3(size.x, deck, size.z), Vector3(0, deck / 2.0, 0))]
	var rail_height := size.y - deck
	if rail_height < 0.3:
		return list
	for side: float in [-1.0, 1.0]:
		if not bool(props.get("rail_left" if side < 0.0 else "rail_right", true)):
			continue
		for part: Dictionary in _railing(Vector3(size.z, rail_height, 0.06)):
			# The railing is built along X; turn it to run along local Z on this side of the deck.
			var pos: Vector3 = part["pos"]
			var part_size: Vector3 = part["size"]
			part["pos"] = Vector3(side * (size.x / 2.0 - 0.03), deck + pos.y, pos.x)
			part["size"] = Vector3(part_size.z, part_size.y, part_size.x)
			part["mat"] = "metal_dark"
			list.append(part)
	return list


## Posts, a top rail and a mid rail: cover you can see and shoot through between the rails.
static func _railing(size: Vector3) -> Array[Dictionary]:
	var bar := clampf(size.z, 0.03, 0.08)
	var list: Array[Dictionary] = []
	var posts := maxi(2, ceili(size.x / 1.5) + 1)
	for i: int in posts:
		var x := -size.x / 2.0 + bar / 2.0 + (size.x - bar) * float(i) / float(posts - 1)
		list.append(_box(Vector3(bar, size.y, bar), Vector3(x, size.y / 2.0, 0)))
	for height: float in [size.y - bar / 2.0, size.y * 0.5]:
		list.append(_box(Vector3(size.x, bar, bar), Vector3(0, height, 0)))
	return list


## A deep gateway whose iron portcullis is raised: its bars hang in the top of the opening down
## to [code]clearance[/code] (at least 2 m, so people and bots walk under it).
static func _portcullis(size: Vector3, props: Dictionary) -> Array[Dictionary]:
	var width := _opening_width(size, props, 3.2)
	var top := _opening_height(size, props, 4.0)
	var list := _opening(size, width, top, 0.0)
	var clearance := clampf(float(props.get("clearance", top - 1.0)), minf(2.0, top), top)
	var hang := top - clearance
	if hang < 0.05:
		return list
	var bars := maxi(2, int(width / 0.4))
	for i: int in bars:
		var x := -width / 2.0 + width * (float(i) + 0.5) / float(bars)
		list.append(_box(Vector3(0.07, hang, 0.07), Vector3(x, clearance + hang / 2.0, 0), "metal_dark"))
	list.append(_box(Vector3(width, 0.1, 0.09), Vector3(0, clearance + 0.05, 0), "metal_dark"))
	return list


## A horizontal pipe along local X. A piece taller than the pipe stands it on legs.
static func _pipe_run(size: Vector3) -> Array[Dictionary]:
	var diameter := minf(size.y, size.z)
	var centre := size.y - diameter / 2.0
	var list: Array[Dictionary] = [_cyl(diameter, size.x, Vector3(0, centre, 0), "", Vector3(0, 0, 90))]
	var flanges := maxi(2, int(size.x / 4.0) + 1)
	for i: int in flanges:
		var x := -size.x / 2.0 + 0.06 + (size.x - 0.12) * float(i) / float(flanges - 1)
		list.append(_cyl(diameter * 1.25, 0.12, Vector3(x, centre, 0), "metal_dark", Vector3(0, 0, 90)))
		if centre - diameter / 2.0 > 0.05:
			list.append(_box(Vector3(0.12, centre, 0.12), Vector3(x, centre / 2.0, 0), "metal_dark"))
	return list


## A banded vertical tank with a conical cap.
static func _storage_tank(size: Vector3) -> Array[Dictionary]:
	var diameter := minf(size.x, size.z)
	var body := size.y * 0.86
	var list: Array[Dictionary] = [_cyl(diameter, body, Vector3(0, body / 2.0, 0))]
	var cap := _cyl(diameter, size.y - body, Vector3(0, body + (size.y - body) / 2.0, 0))
	cap["top_radius_scale"] = 0.25
	list.append(cap)
	for band: float in [0.12, 0.5, 0.82]:
		list.append(_cyl(diameter * 1.03, 0.14, Vector3(0, body * band, 0), "metal_dark"))
	return list


## A cloth banner hanging from a pole, for a wall face.
static func _banner(size: Vector3) -> Array[Dictionary]:
	var pole := minf(0.08, size.y * 0.1)
	return [
		_cyl(pole, size.x, Vector3(0, size.y - pole / 2.0, 0), "wood_dark", Vector3(0, 0, 90)),
		_box(Vector3(size.x * 0.9, size.y - pole, minf(0.04, size.z)), Vector3(0, (size.y - pole) / 2.0, 0)),
	]


## A ribbed shipping container: corner rails, corrugated long sides and a door seam at +Z.
static func _container(size: Vector3) -> Array[Dictionary]:
	var rib := 0.05
	var list: Array[Dictionary] = [_box(Vector3(size.x - rib * 2.0, size.y, size.z), Vector3(0, size.y / 2.0, 0))]
	var ribs := maxi(2, int(size.z / 0.6))
	for i: int in ribs:
		var z := -size.z / 2.0 + size.z * (float(i) + 0.5) / float(ribs)
		for side: float in [-1.0, 1.0]:
			list.append(_box(Vector3(rib, size.y * 0.9, 0.16), Vector3(side * (size.x / 2.0 - rib / 2.0), size.y / 2.0, z)))
	for end: float in [-1.0, 1.0]:
		list.append(_box(Vector3(size.x, 0.14, 0.14), Vector3(0, size.y - 0.07, end * (size.z / 2.0 - 0.07)), "metal_dark"))
	list.append(_box(Vector3(0.05, size.y * 0.85, 0.04), Vector3(0, size.y * 0.5, size.z / 2.0 + 0.02), "metal_dark"))
	return list


## A trunk under three tapering layers of foliage. The canopy blocks sight and shots.
static func _tree(size: Vector3) -> Array[Dictionary]:
	var diameter := minf(size.x, size.z)
	var trunk := size.y * 0.35
	var list: Array[Dictionary] = [_cyl(maxf(0.25, diameter * 0.1), trunk, Vector3(0, trunk / 2.0, 0), "wood_dark")]
	var layer_height := (size.y - trunk) / 3.0
	for i: int in 3:
		var bottom := 1.0 - float(i) * 0.25
		var layer := _cyl(diameter * bottom, layer_height * 1.2, Vector3(0, trunk + layer_height * (float(i) + 0.5), 0))
		layer["top_radius_scale"] = 0.45
		list.append(layer)
	return list


## Meridian telescope on twin masonry piers. Fit the tilted barrel within the piece bounds.
static func _transit_scope(size: Vector3) -> Array[Dictionary]:
	var diameter := minf(size.x * 0.29, minf(size.y, size.z) * 0.24)
	var rise := size.y * 0.47
	var run := size.z - diameter
	var axis := Vector3(0, rise, -run).normalized()
	var rotation := Vector3(-rad_to_deg(atan2(run, rise)), 0, 0)
	var length := Vector2(rise, run).length()
	var pivot := Vector3.UP * size.y * 0.59
	var parts: Array[Dictionary] = [_cyl(diameter, length, pivot, "", rotation),
		_cyl(diameter * 0.53, size.x, pivot, "metal_dark", Vector3(0,0,90))]
	for side: int in [-1, 1]:
		parts.append(_box(Vector3(size.x * 0.18, pivot.y, size.z * 0.28),
			Vector3(side * size.x * 0.37, pivot.y / 2, 0), "limestone"))
	for fraction: float in [-0.4, 0.15, 0.46]:
		parts.append(_cyl(diameter * 1.18, length * 0.07, pivot + axis * length * fraction, "metal_dark", rotation))
	return parts
