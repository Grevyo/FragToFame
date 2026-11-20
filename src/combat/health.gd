class_name Health
extends Node
## Hit points of a player, bot or target. Emits events; what death *means* is up to the owner.
##
## Also the combatant's identity for combat code: [member team] (friendly fire / targeting),
## [member owner_id] (stable player or bot ID) and the [member hitboxes] to aim at.

signal damaged(info: DamageInfo)
signal died(info: DamageInfo)
signal revived

@export var max_health: int = 100

var current: int = 100
## Armour points (0–100) and helmet; see [method DamageModel.armour_split].
var armour: int = 0
var has_helmet: bool = false
var is_dead: bool = false
## Team key ("home" / "away" in matches); empty = belongs to no team (training targets).
var team: StringName = &""
## Stable ID of the player/bot this health belongs to (empty for training targets).
var owner_id: String = ""
## Hitboxes registered by [method Hitbox.create].
var hitboxes: Array[Hitbox] = []
## The damage event that caused the most recent death (null while alive).
var last_death: DamageInfo = null


## Every Health in the scene tree joins this group, so area effects (grenades) can find them.
const GROUP: StringName = &"combatant_health"


func _ready() -> void:
	current = max_health
	add_to_group(GROUP)


## Applies [param info]; returns the damage actually removed. Ignored once dead.
func apply_damage(info: DamageInfo) -> int:
	if is_dead or info.amount <= 0:
		return 0
	var split := DamageModel.armour_split(info.amount, info.armour_penetration, info.zone, armour, has_helmet)
	info.armour_damage = split[1]
	armour -= split[1]
	info.applied = mini(split[0], current)
	current -= info.applied
	damaged.emit(info)
	if current <= 0:
		is_dead = true
		last_death = info
		died.emit(info)
	return info.applied


## Kills outright (e.g. falling out of the world).
func kill(info: DamageInfo = null) -> void:
	if is_dead:
		return
	apply_damage(info if info != null else DamageInfo.world(current))


func revive() -> void:
	current = max_health
	is_dead = false
	last_death = null
	revived.emit()


## World position to aim at: the head or the chest hitbox (falls back to the parent's origin).
func aim_point(head: bool) -> Vector3:
	var wanted := DamageModel.ZONE_HEAD if head else DamageModel.ZONE_CHEST
	for hitbox: Hitbox in hitboxes:
		if hitbox.zone == wanted and hitbox.is_inside_tree():
			return hitbox.global_position
	var parent := get_parent() as Node3D
	return parent.global_position + Vector3(0, 1.3, 0) if parent != null else Vector3.ZERO


## The body this health belongs to (its parent node).
func body() -> Node3D:
	return get_parent() as Node3D


func is_enemy_of(other_team: StringName) -> bool:
	return team == &"" or other_team == &"" or team != other_team


func fraction() -> float:
	return float(current) / float(max_health)
