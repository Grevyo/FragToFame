class_name PolygonSurface
extends RefCounted
## Creates a solid floor from a simple X/Z outline with an elevation at each corner.

const MAX_POINTS: int = 32
const MIN_EDGE: float = 0.05


static func piece(points: PackedVector3Array, thickness: float) -> Dictionary:
	if points.size() < 3 or points.size() > MAX_POINTS or thickness < MIN_EDGE:
		return {}
	var bounds := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		if not point.is_finite():
			return {}
		bounds = bounds.expand(point)
	bounds.position.y -= thickness
	bounds.size.y += thickness
	if bounds.size.x < MIN_EDGE or bounds.size.z < MIN_EDGE:
		return {}
	var origin := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var outline: Array = []
	for point: Vector3 in points:
		var local := (point - origin) / bounds.size
		outline.append([local.x, local.y, local.z])
	var props := {"outline": outline, "thickness": thickness / bounds.size.y}
	if not is_valid(props):
		return {}
	var result := MapDocument.make_piece("drawn_surface", origin, 0.0, bounds.size)
	result["props"] = props
	return result


## True when [param point] (world) lies over the drawn outline of a surface piece, not just
## inside its bounding box: an angled strip's box also covers the ground beside it.
static func footprint_has_point(piece: Dictionary, point: Vector3) -> bool:
	var points := _local_points(piece["size"] as Vector3, piece.get("props", {}) as Dictionary)
	if points.size() < 3:
		return false
	var local := MapDocument.piece_transform(piece).affine_inverse() * point
	return Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), _footprint(points))


static func is_valid(props: Dictionary) -> bool:
	var points := _local_points(Vector3.ONE, props)
	return not _triangulate(points).is_empty()


static func build_mesh(size: Vector3, props: Dictionary) -> ArrayMesh:
	var points := _local_points(size, props)
	var triangles := _triangulate(points)
	if triangles.is_empty():
		return null
	var down := Vector3.DOWN * (float(props["thickness"]) * size.y)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_smooth_group(-1)
	for i: int in range(0, triangles.size(), 3):
		var a := points[triangles[i]]
		var b := points[triangles[i + 1]]
		var c := points[triangles[i + 2]]
		_triangle(builder, a, b, c)
		_triangle(builder, a + down, c + down, b + down)
	if Geometry2D.is_polygon_clockwise(_footprint(points)):
		points.reverse()
	for i: int in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		_triangle(builder, a, a + down, b)
		_triangle(builder, b, a + down, b + down)
	builder.generate_normals()
	return builder.commit()


static func _local_points(size: Vector3, props: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	var outline: Variant = props.get("outline")
	var depth: Variant = props.get("thickness")
	if not (depth is float or depth is int) or not (float(depth) > 0.0 and float(depth) <= 1.0):
		return result
	if not outline is Array or outline.size() < 3 or outline.size() > MAX_POINTS:
		return result
	var limits := AABB(Vector3(-0.501, float(depth) - 0.001, -0.501), Vector3(1.002, 1.002 - float(depth), 1.002))
	for entry: Variant in outline:
		if not entry is Array or entry.size() != 3 or not entry.all(func(v: Variant) -> bool: return v is float or v is int):
			return PackedVector3Array()
		var point := Vector3(float(entry[0]), float(entry[1]), float(entry[2]))
		if not limits.has_point(point):
			return PackedVector3Array()
		result.append(point * size)
	return result


static func _footprint(points: PackedVector3Array) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for point: Vector3 in points:
		outline.append(Vector2(point.x, point.z))
	return outline


static func _triangulate(points: PackedVector3Array) -> PackedInt32Array:
	var outline := _footprint(points)
	for i: int in outline.size():
		var next := (i + 1) % outline.size()
		if outline[i].is_equal_approx(outline[next]):
			return PackedInt32Array()
		for j: int in range(i + 2, outline.size()):
			var after := (j + 1) % outline.size()
			if after != i and Geometry2D.segment_intersects_segment(outline[i], outline[next], outline[j], outline[after]) != null:
				return PackedInt32Array()
	return Geometry2D.triangulate_polygon(outline)


static func _triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	builder.add_vertex(a)
	builder.add_vertex(b)
	builder.add_vertex(c)
