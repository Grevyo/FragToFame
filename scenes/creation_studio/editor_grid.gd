class_name EditorGrid
extends MeshInstance3D
## Ground-plane grid drawn as unshaded lines. Minor lines follow the snap size; every metre
## and every 8 m get progressively stronger lines; X and Z axes are coloured.

const MINOR_COLOR: Color = Color(1, 1, 1, 0.06)
const METRE_COLOR: Color = Color(1, 1, 1, 0.16)
const MAJOR_COLOR: Color = Color(1, 1, 1, 0.32)
const X_AXIS_COLOR: Color = Color(0.95, 0.3, 0.3, 0.9)
const Z_AXIS_COLOR: Color = Color(0.3, 0.55, 0.95, 0.9)
const MAJOR_EVERY_METRES: int = 8

@export var half_extent: float = 64.0
@export var snap_size: float = 1.0:
	set(value):
		snap_size = maxf(value, 0.0625)
		if is_inside_tree():
			rebuild()


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var steps := int(round(half_extent / snap_size))
	for i: int in range(-steps, steps + 1):
		var offset := float(i) * snap_size
		var color := _line_color(offset)
		# Line parallel to Z at x = offset.
		vertices.append(Vector3(offset, 0, -half_extent))
		vertices.append(Vector3(offset, 0, half_extent))
		var z_line_color := Z_AXIS_COLOR if is_zero_approx(offset) else color
		colors.append(z_line_color)
		colors.append(z_line_color)
		# Line parallel to X at z = offset.
		vertices.append(Vector3(-half_extent, 0, offset))
		vertices.append(Vector3(half_extent, 0, offset))
		var x_line_color := X_AXIS_COLOR if is_zero_approx(offset) else color
		colors.append(x_line_color)
		colors.append(x_line_color)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	array_mesh.surface_set_material(0, material)
	mesh = array_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Total number of grid lines currently drawn (both directions).
func line_count() -> int:
	if mesh == null:
		return 0
	return int(mesh.surface_get_array_len(0) / 2.0)


func _line_color(offset: float) -> Color:
	if is_zero_approx(fmod(absf(offset), float(MAJOR_EVERY_METRES))):
		return MAJOR_COLOR
	if is_zero_approx(fmod(absf(offset), 1.0)):
		return METRE_COLOR
	return MINOR_COLOR
