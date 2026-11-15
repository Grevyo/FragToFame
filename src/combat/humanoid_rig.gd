class_name HumanoidRig
extends RefCounted
## Builds the standard humanoid hitbox layout (head, chest, stomach, arms, legs) for players,
## bots and targets, optionally with simple box/sphere meshes. All bodies share one layout so
## damage is consistent everywhere.

## Standing layout: zone, shape kind, size (radius for spheres), centre position.
const PARTS: Array[Dictionary] = [
	{"zone": DamageModel.ZONE_HEAD, "radius": 0.14, "at": Vector3(0, 1.6, 0)},
	{"zone": DamageModel.ZONE_CHEST, "size": Vector3(0.46, 0.36, 0.26), "at": Vector3(0, 1.29, 0)},
	{"zone": DamageModel.ZONE_STOMACH, "size": Vector3(0.4, 0.3, 0.24), "at": Vector3(0, 0.96, 0)},
	{"zone": DamageModel.ZONE_LEGS, "size": Vector3(0.36, 0.8, 0.22), "at": Vector3(0, 0.4, 0)},
	{"zone": DamageModel.ZONE_ARMS, "size": Vector3(0.11, 0.6, 0.12), "at": Vector3(-0.3, 1.18, 0)},
	{"zone": DamageModel.ZONE_ARMS, "size": Vector3(0.11, 0.6, 0.12), "at": Vector3(0.3, 1.18, 0)},
]
const STANDING_HEIGHT: float = 1.8


class Built extends RefCounted:
	var hitboxes: Array[Hitbox] = []
	var materials: Array[StandardMaterial3D] = []


## Adds hitboxes (and meshes when [param skin]/[param suit] are given with [param with_meshes])
## under [param parent], all reporting to [param health].
static func build(parent: Node3D, health: Health, with_meshes: bool,
		skin: Color = Color("c9b48a"), suit: Color = Color("3c4a5c")) -> Built:
	var built := Built.new()
	for part: Dictionary in PARTS:
		var zone: StringName = part["zone"]
		var shape: Shape3D
		if part.has("radius"):
			var sphere := SphereShape3D.new()
			sphere.radius = float(part["radius"])
			shape = sphere
		else:
			var box := BoxShape3D.new()
			box.size = part["size"]
			shape = box
		var at: Vector3 = part["at"]
		var hitbox := Hitbox.create(zone, shape, at, health)
		hitbox.set_meta(&"base_position", at)
		parent.add_child(hitbox)
		built.hitboxes.append(hitbox)
		if with_meshes:
			var color := skin if zone == DamageModel.ZONE_HEAD else _zone_color(zone, suit)
			built.materials.append(_add_mesh(hitbox, shape, color))
	return built


## Moves hitboxes down for a shorter stance (e.g. crouching: ratio = 1.2 / 1.8).
static func apply_height_ratio(hitboxes: Array[Hitbox], ratio: float) -> void:
	for hitbox: Hitbox in hitboxes:
		var base: Vector3 = hitbox.get_meta(&"base_position", hitbox.position)
		hitbox.position = Vector3(base.x, base.y * ratio, base.z)


static func _zone_color(zone: StringName, suit: Color) -> Color:
	match zone:
		DamageModel.ZONE_STOMACH:
			return suit.lightened(0.1)
		DamageModel.ZONE_LEGS:
			return suit.darkened(0.25)
		DamageModel.ZONE_ARMS:
			return suit.darkened(0.1)
	return suit


static func _add_mesh(hitbox: Hitbox, shape: Shape3D, color: Color) -> StandardMaterial3D:
	var mesh_instance := MeshInstance3D.new()
	if shape is SphereShape3D:
		var sphere := SphereMesh.new()
		sphere.radius = (shape as SphereShape3D).radius
		sphere.height = sphere.radius * 2.0
		mesh_instance.mesh = sphere
	else:
		var box := BoxMesh.new()
		box.size = (shape as BoxShape3D).size
		mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh_instance.material_override = material
	hitbox.add_child(mesh_instance)
	return material
