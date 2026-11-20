class_name UtilityModels
extends RefCounted
## Original procedural models for the four kinds of utility, used in the hand (viewmodel), in
## flight and in the Armoury. Presentation only. Each model stands upright with its base at the
## origin, about 10–13 cm tall.

static var _materials: Dictionary[String, StandardMaterial3D] = {}


## A new model for [param id], or null for anything that is not utility.
static func build(id: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "Utility"
	match EquipmentCatalog.utility_kind(id):
		EquipmentCatalog.KIND_FRAG:
			_part(root, _sphere(0.034), Vector3(0, 0.04, 0), "frag_body", Vector3(1, 1.15, 1))
			_part(root, _cylinder(0.012, 0.012, 0.022), Vector3(0, 0.083, 0), "steel")
			_part(root, _box(Vector3(0.012, 0.075, 0.006)), Vector3(0.022, 0.06, 0), "steel", Vector3.ONE, Vector3(0, 0, -12))
			_part(root, _torus(0.009, 0.0022), Vector3(-0.014, 0.092, 0), "steel", Vector3.ONE, Vector3(90, 0, 0))
		EquipmentCatalog.KIND_FLASH:
			_part(root, _cylinder(0.022, 0.022, 0.1), Vector3(0, 0.05, 0), "flash_body")
			for y: float in [0.02, 0.08]:
				_part(root, _cylinder(0.0225, 0.0225, 0.008), Vector3(0, y, 0), "band_dark")
			_part(root, _cylinder(0.011, 0.014, 0.02), Vector3(0, 0.11, 0), "steel")
			_part(root, _box(Vector3(0.01, 0.07, 0.005)), Vector3(0.024, 0.075, 0), "steel")
		EquipmentCatalog.KIND_SMOKE:
			_part(root, _cylinder(0.026, 0.026, 0.11), Vector3(0, 0.055, 0), "smoke_body")
			_part(root, _cylinder(0.0265, 0.0265, 0.014), Vector3(0, 0.09, 0), "band_light")
			_part(root, _cylinder(0.012, 0.015, 0.02), Vector3(0, 0.12, 0), "steel")
			_part(root, _box(Vector3(0.01, 0.075, 0.005)), Vector3(0.028, 0.08, 0), "steel")
		EquipmentCatalog.KIND_FIRE:
			_part(root, _cylinder(0.028, 0.03, 0.08), Vector3(0, 0.04, 0), "glass")
			_part(root, _cylinder(0.011, 0.026, 0.03), Vector3(0, 0.095, 0), "glass")
			_part(root, _cylinder(0.011, 0.011, 0.025), Vector3(0, 0.12, 0), "glass")
			_part(root, _box(Vector3(0.018, 0.035, 0.012)), Vector3(0.004, 0.142, 0), "rag", Vector3.ONE, Vector3(0, 0, 14))
			_part(root, _cylinder(0.0285, 0.0305, 0.03), Vector3(0, 0.03, 0), "fuel")
		_:
			root.free()
			return null
	return root


static func _part(root: Node3D, mesh: Mesh, at: Vector3, material: String, scale_value: Vector3 = Vector3.ONE,
		rotation_value: Vector3 = Vector3.ZERO) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _material(material)
	part.position = at
	part.scale = scale_value
	part.rotation_degrees = rotation_value
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(part)


static func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	var colours: Dictionary[String, Array] = {
		"frag_body": [Color(0.29, 0.34, 0.2), 0.0, 0.75],
		"steel": [Color(0.55, 0.56, 0.58), 0.85, 0.35],
		"flash_body": [Color(0.72, 0.74, 0.76), 0.3, 0.5],
		"band_dark": [Color(0.12, 0.13, 0.14), 0.0, 0.7],
		"smoke_body": [Color(0.24, 0.28, 0.27), 0.1, 0.7],
		"band_light": [Color(0.8, 0.78, 0.7), 0.0, 0.7],
		"glass": [Color(0.42, 0.55, 0.38, 0.55), 0.0, 0.1],
		"fuel": [Color(0.62, 0.34, 0.08, 0.85), 0.0, 0.2],
		"rag": [Color(0.78, 0.7, 0.55), 0.0, 1.0],
	}
	var entry: Array = colours.get(key, [Color.WHITE, 0.0, 0.8])
	material.albedo_color = entry[0]
	material.metallic = float(entry[1])
	material.roughness = float(entry[2])
	if (entry[0] as Color).a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = material
	return material


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _torus(radius: float, thickness: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius + thickness
	mesh.rings = 12
	mesh.ring_segments = 6
	return mesh
