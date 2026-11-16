class_name BrushGeometry
extends RefCounted
## An editable brush in local metres. The same indexed faces drive the preview and collision.

const MAX_VERTICES: int = 289
const MAX_INDICES: int = 1536


static func piece(vertices: Array, faces: Array, two_sided: bool = false) -> Dictionary:
	if vertices.size() < 3 or vertices.size() > MAX_VERTICES or not _valid_indices(faces, vertices.size()):
		return {}
	var points := PackedVector3Array()
	for vertex: Variant in vertices:
		if not vertex is Array or vertex.size() != 3 or not vertex.all(func(v: Variant) -> bool: return v is int or v is float):
			return {}
		var point := Vector3(float(vertex[0]), float(vertex[1]), float(vertex[2]))
		if not point.is_finite() or point.abs().length() > 900.0:
			return {}
		points.append(point)
	var bounds := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		bounds = bounds.expand(point)
	var size := bounds.size.max(Vector3.ONE * MapValidator.MIN_SIZE)
	var origin := bounds.get_center()
	origin.y = bounds.position.y
	var local: Array = []
	for point: Vector3 in points:
		var normalised := (point - origin) / size
		local.append([normalised.x, normalised.y, normalised.z])
	var result := MapDocument.make_piece("mesh_brush", origin, 0.0, size)
	result["props"] = {"vertices": local, "faces": faces.duplicate(), "two_sided": two_sided}
	return result


static func mesh(size: Vector3, props: Dictionary) -> ArrayMesh:
	var points := local_points(size, props)
	var faces: Variant = props.get("faces")
	if points.is_empty() or not faces is Array or not _valid_indices(faces, points.size()):
		return null
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var has_faces := false
	for i: int in range(0, faces.size(), 3):
		var a := points[int(faces[i])]
		var b := points[int(faces[i + 1])]
		var c := points[int(faces[i + 2])]
		if (b - a).cross(c - a).length_squared() < 1.0e-12:
			continue
		has_faces = true
		tool.add_vertex(a)
		tool.add_vertex(b)
		tool.add_vertex(c)
		if props.get("two_sided", false) == true:
			tool.add_vertex(a)
			tool.add_vertex(c)
			tool.add_vertex(b)
	if not has_faces:
		return null
	tool.generate_normals()
	var result := tool.commit()
	return result if result != null and result.get_surface_count() > 0 else null


static func local_points(size: Vector3, props: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	var vertices: Variant = props.get("vertices")
	if not vertices is Array or vertices.size() < 3 or vertices.size() > MAX_VERTICES:
		return result
	var limits := AABB(Vector3(-0.501, -0.001, -0.501), Vector3(1.002, 1.002, 1.002))
	for vertex: Variant in vertices:
		if not vertex is Array or vertex.size() != 3 or not vertex.all(func(v: Variant) -> bool: return v is int or v is float):
			return PackedVector3Array()
		var point := Vector3(float(vertex[0]), float(vertex[1]), float(vertex[2]))
		if not point.is_finite() or not limits.has_point(point):
			return PackedVector3Array()
		result.append(point * size)
	return result


static func _valid_indices(faces: Array, count: int) -> bool:
	if faces.size() < 3 or faces.size() % 3 != 0 or faces.size() > MAX_INDICES:
		return false
	for index: Variant in faces:
		if not (index is int or index is float) or not is_finite(float(index)):
			return false
		if float(index) != float(int(index)) or int(index) < 0 or int(index) >= count:
			return false
	return true
