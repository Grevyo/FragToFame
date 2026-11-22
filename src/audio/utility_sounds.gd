class_name UtilitySounds
extends Node
## The sounds of thrown utility (Milestone 22): grenades bouncing, frags exploding, flashes
## popping, smokes hissing and fire igniting, wherever they happen. Listens to a [UtilityField].

const DETONATION: Dictionary[StringName, StringName] = {
	EquipmentCatalog.KIND_FRAG: &"frag_explode",
	EquipmentCatalog.KIND_FLASH: &"flash_pop",
	EquipmentCatalog.KIND_SMOKE: &"smoke_hiss",
	EquipmentCatalog.KIND_FIRE: &"fire_ignite",
}

var field: UtilityField


static func attach(utility_field: UtilityField) -> UtilitySounds:
	var sounds := UtilitySounds.new()
	sounds.name = "Sounds"
	sounds.field = utility_field
	utility_field.add_child(sounds)
	return sounds


func _ready() -> void:
	field.grenade_bounced.connect(func(_id: StringName, at: Vector3, speed: float) -> void:
		SoundPlayer.play_at(field, &"grenade_bounce", at, &"bounce", clampf(-16.0 + speed * 1.6, -16.0, 0.0)))
	field.detonated.connect(_on_detonated)


func _on_detonated(utility_id: StringName, at: Vector3, _thrower_id: String) -> void:
	var slot: StringName = DETONATION.get(EquipmentCatalog.utility_kind(utility_id), &"")
	if not slot.is_empty():
		SoundPlayer.play_at(field, slot, at, &"explosion" if slot == &"frag_explode" else &"utility")
