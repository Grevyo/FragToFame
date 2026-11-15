class_name BlockBuilder
extends RefCounted
## Builds simple static box geometry (mesh + collision) with a world-space checker texture.
##
## This is the primitive vocabulary the FPS sandbox uses today and the map editor will
## build on, so that test geometry and user-made maps share the same building blocks.

## Size of one checker square in metres.
const CHECKER_SQUARE_METRES: float = 1.0

static var _material_cache: Dictionary[Color, StandardMaterial3D] = {}


static func make_box(parent: Node3D, size: Vector3, position: Vector3, color: Color,
		rotation_degrees: Vector3 = Vector3.ZERO, block_name: String = "Block",
		with_collision: bool = true) -> Node3D:
	var body: Node3D = StaticBody3D.new() if with_collision else Node3D.new()
	body.name = block_name
	body.position = position
	body.rotation_degrees = rotation_degrees

	var mesh := BoxMesh.new()
	mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = checker_material(color)
	body.add_child(mesh_instance)

	if with_collision:
		body.add_child(_box_collision(size))
	parent.add_child(body)
	return body


## Adds an invisible static box collider (e.g. a smooth slope over visual stairs).
static func make_collision_box(parent: Node3D, size: Vector3, position: Vector3,
		rotation_degrees: Vector3 = Vector3.ZERO, block_name: String = "Collider") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = block_name
	body.position = position
	body.rotation_degrees = rotation_degrees
	body.add_child(_box_collision(size))
	parent.add_child(body)
	return body


static func _box_collision(size: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	return collision


## Returns a shared material showing a two-tone checker in world space.
static func checker_material(color: Color) -> StandardMaterial3D:
	if _material_cache.has(color):
		return _material_cache[color]
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var light := color
	var dark := color.darkened(0.12)
	image.set_pixel(0, 0, light)
	image.set_pixel(1, 1, light)
	image.set_pixel(1, 0, dark)
	image.set_pixel(0, 1, dark)
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	var scale: float = 1.0 / (2.0 * CHECKER_SQUARE_METRES)
	material.uv1_scale = Vector3(scale, scale, scale)
	material.roughness = 0.9
	_material_cache[color] = material
	return material
