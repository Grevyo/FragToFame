extends SceneTree
## Projects every weapon's five authored Magnet slots (WeaponModels "slots") onto its mesh and
## writes the surface points to data/weapons/magnet_slots.json. Run again after changing a
## slot layout, a model or its orientation.
##
## Each slot is a ray fired at the weapon from its left or right side. The point it hits
## becomes the slot position; the Magnet decal projects straight in from that side, so it
## follows whatever surface is there. A slot whose ray misses the mesh is nudged in a small
## spiral until it lands, and is reported.
##
## Run:  <godot> --headless --path <project> --script res://tools/build_magnet_slots.gd

const NUDGE_STEP: float = 0.004
const NUDGE_RINGS: int = 6


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var output: Dictionary = {}
	var problems := 0
	for weapon_id: StringName in WeaponModels.ids():
		var visual := WeaponVisual.new()
		root.add_child(visual)
		visual.setup(weapon_id)
		var shape := visual.geometry()
		var triangles: PackedVector3Array = shape[0]
		var uvs: PackedVector2Array = shape[1]
		var list: Array = []
		var specs := WeaponModels.slot_specs(weapon_id)
		for index: int in specs.size():
			var spec := specs[index]
			var side := -1.0 if spec["side"] == "left" else 1.0
			var aim := Vector2(float(spec["y"]) * visual.size.y, float(spec["z"]) * visual.size.z)
			var hit: Variant = null
			var nudged := false
			for ring: int in NUDGE_RINGS + 1:
				for step: int in maxi(1, ring * 8):
					var angle := TAU * float(step) / float(maxi(1, ring * 8))
					var offset := Vector2(cos(angle), sin(angle)) * NUDGE_STEP * float(ring)
					hit = _cast(triangles, uvs, side, aim + offset)
					if hit != null:
						nudged = ring > 0
						break
				if hit != null:
					break
			if hit == null:
				problems += 1
				print("  MISS  %s slot %d (%s) — no surface near y %.2f z %.2f" % [weapon_id, index + 1, spec["side"], spec["y"], spec["z"]])
				hit = [Vector3(side * visual.size.x / 2.0, aim.x, aim.y), Vector2.ZERO]
			elif nudged:
				print("  nudged  %s slot %d (%s)" % [weapon_id, index + 1, spec["side"]])
			var point: Vector3 = (hit as Array)[0]
			var uv: Vector2 = (hit as Array)[1]
			list.append({"position": [snappedf(point.x, 0.0001), snappedf(point.y, 0.0001), snappedf(point.z, 0.0001)],
				"normal": [side, 0.0, 0.0], "size": spec["size"], "uv": [snappedf(uv.x, 0.0001), snappedf(uv.y, 0.0001)]})
		output[String(weapon_id)] = list
		print("%s  %d slots  size %s  (%d triangles)" % [weapon_id, list.size(), visual.size.snappedf(0.001), triangles.size() / 3])
		visual.queue_free()
		await process_frame
	DirAccess.make_dir_recursive_absolute(WeaponModels.SLOT_DATA_PATH.get_base_dir())
	var file := FileAccess.open(WeaponModels.SLOT_DATA_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": WeaponModels.SLOT_FORMAT, "format_version": WeaponModels.SLOT_FORMAT_VERSION,
		"weapons": output}, "\t") + "\n")
	file.close()
	print("wrote %s, %d slot(s) missed" % [WeaponModels.SLOT_DATA_PATH, problems])
	quit(0 if problems == 0 else 1)


## Nearest hit of a ray from the given side (x = side * 1 m): [point, uv at that point], or null.
func _cast(triangles: PackedVector3Array, uvs: PackedVector2Array, side: float, aim: Vector2) -> Variant:
	var origin := Vector3(side, aim.x, aim.y)
	var direction := Vector3(-side, 0, 0)
	var best: Variant = null
	var best_distance := INF
	for i: int in range(0, triangles.size(), 3):
		var a := triangles[i]
		var b := triangles[i + 1]
		var c := triangles[i + 2]
		# Cheap reject: the ray is axis-aligned, so the triangle must straddle it in Y and Z.
		if (a.y < aim.x and b.y < aim.x and c.y < aim.x) or (a.y > aim.x and b.y > aim.x and c.y > aim.x) \
				or (a.z < aim.y and b.z < aim.y and c.z < aim.y) or (a.z > aim.y and b.z > aim.y and c.z > aim.y):
			continue
		var point: Variant = Geometry3D.ray_intersects_triangle(origin, direction, a, b, c)
		if point != null and origin.distance_to(point as Vector3) < best_distance:
			best_distance = origin.distance_to(point as Vector3)
			var weights := Geometry3D.get_triangle_barycentric_coords(point as Vector3, a, b, c)
			best = [point, uvs[i] * weights.x + uvs[i + 1] * weights.y + uvs[i + 2] * weights.z]
	return best
