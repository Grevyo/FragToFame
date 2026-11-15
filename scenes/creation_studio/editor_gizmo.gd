class_name EditorGizmo
extends Node3D
## Move / rotate / scale gizmo drawn at the selection pivot. It only draws handles and converts
## mouse rays into handle values; the scene controller applies them through MapEditController.
##
## Handles: "x", "y", "z" (axis lines, in every mode) and "ring" (yaw ring, rotate mode).

enum Mode { MOVE, ROTATE, SCALE }

const AXES: Dictionary[String, Vector3] = {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}
const COLORS: Dictionary[String, Color] = {"x": Color(0.95, 0.3, 0.3), "y": Color(0.4, 0.9, 0.4),
	"z": Color(0.35, 0.55, 1.0), "ring": Color(1.0, 0.8, 0.2)}
const PICK_PIXELS: float = 12.0
const RING_SEGMENTS: int = 48

var mode: Mode = Mode.MOVE
## Handle length in metres (kept proportional to the camera distance by the controller).
var length: float = 2.0

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_mesh_instance.material_override = material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	visible = false
	redraw()


## Places the gizmo. [param yaw_degrees] orients the axes (the piece's yaw in scale mode).
func place(pivot: Vector3, yaw_degrees: float, handle_length: float) -> void:
	position = pivot
	rotation_degrees = Vector3(0, yaw_degrees, 0)
	if not is_equal_approx(handle_length, length):
		length = handle_length
		redraw()


func set_mode(next: Mode) -> void:
	mode = next
	redraw()


## Handles available in the current mode.
func handles() -> Array[String]:
	return ["ring"] if mode == Mode.ROTATE else ["x", "y", "z"]


## World-space unit direction of an axis handle.
func axis(handle: String) -> Vector3:
	return (global_transform.basis * AXES.get(handle, Vector3.ZERO)).normalized()


func redraw() -> void:
	if _mesh_instance == null:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if mode == Mode.ROTATE:
		for i: int in RING_SEGMENTS:
			for step: int in [i, i + 1]:
				var angle := TAU * float(step) / float(RING_SEGMENTS)
				mesh.surface_set_color(COLORS["ring"])
				mesh.surface_add_vertex(Vector3(cos(angle), 0, sin(angle)) * length)
	else:
		for handle: String in AXES:
			var tip := AXES[handle] * length
			mesh.surface_set_color(COLORS[handle])
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_set_color(COLORS[handle])
			mesh.surface_add_vertex(tip)
			# Arrow head (move) or end cap (scale).
			var side := (Vector3.UP if handle != "y" else Vector3.RIGHT) * length * 0.08
			var back := tip * (0.85 if mode == Mode.MOVE else 1.0)
			for flip: float in [-1.0, 1.0]:
				mesh.surface_set_color(COLORS[handle])
				mesh.surface_add_vertex(tip if mode == Mode.MOVE else tip - side * flip)
				mesh.surface_set_color(COLORS[handle])
				mesh.surface_add_vertex(back + side * flip)
	mesh.surface_end()
	_mesh_instance.mesh = mesh


## The handle under [param screen_position], or "" (nearest within PICK_PIXELS on screen).
func handle_at(camera: Camera3D, screen_position: Vector2) -> String:
	if not visible:
		return ""
	var best := ""
	var best_distance := PICK_PIXELS
	for handle: String in handles():
		var points: Array[Vector3] = []
		if handle == "ring":
			for i: int in RING_SEGMENTS + 1:
				var angle := TAU * float(i) / float(RING_SEGMENTS)
				points.append(global_transform * (Vector3(cos(angle), 0, sin(angle)) * length))
		else:
			points = [global_position, global_position + axis(handle) * length]
		for i: int in points.size() - 1:
			if camera.is_position_behind(points[i]) or camera.is_position_behind(points[i + 1]):
				continue
			var a := camera.unproject_position(points[i])
			var b := camera.unproject_position(points[i + 1])
			var distance := Geometry2D.get_closest_point_to_segment(screen_position, a, b).distance_to(screen_position)
			if distance < best_distance:
				best_distance = distance
				best = handle
	return best


## Value of a handle for the mouse ray: metres along an axis from the pivot, or the yaw angle in
## degrees around the pivot for the ring. Drags apply the difference from the starting value.
func handle_value(camera: Camera3D, screen_position: Vector2, handle: String) -> float:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if handle == "ring":
		var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(origin, direction)
		if hit == null:
			return 0.0
		var offset := (hit as Vector3) - global_position
		return rad_to_deg(atan2(-offset.z, offset.x))
	return axis_parameter(global_position, axis(handle), origin, direction)


## Distance along the line (point + t * direction) closest to a ray.
static func axis_parameter(line_point: Vector3, line_direction: Vector3, ray_origin: Vector3, ray_direction: Vector3) -> float:
	var w := line_point - ray_origin
	var b := line_direction.dot(ray_direction)
	var denominator := 1.0 - b * b
	if absf(denominator) < 0.0001:
		return 0.0
	return (b * ray_direction.dot(w) - line_direction.dot(w)) / denominator
