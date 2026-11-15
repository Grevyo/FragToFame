class_name Hitbox
extends StaticBody3D
## A damageable body part. Lives on the hitbox physics layer only, so it never blocks movement
## and only shots (which query that layer) can touch it.

var zone: StringName = DamageModel.ZONE_CHEST
var health: Health


static func create(zone_id: StringName, shape: Shape3D, local_position: Vector3, owner_health: Health) -> Hitbox:
	var box := Hitbox.new()
	box.name = "Hitbox_%s" % zone_id
	box.zone = zone_id
	box.health = owner_health
	if owner_health != null:
		owner_health.hitboxes.append(box)
	box.collision_layer = Hitscan.LAYER_HITBOXES
	box.collision_mask = 0
	box.position = local_position
	var collision := CollisionShape3D.new()
	collision.shape = shape
	box.add_child(collision)
	return box


func set_enabled(enabled: bool) -> void:
	collision_layer = Hitscan.LAYER_HITBOXES if enabled else 0
