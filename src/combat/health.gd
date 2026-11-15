class_name Health
extends Node
## Hit points of a player, bot or target. Emits events; what death *means* is up to the owner.

signal damaged(info: DamageInfo)
signal died(info: DamageInfo)
signal revived

@export var max_health: int = 100

var current: int = 100
## Armour points (0–100) and helmet; see [method DamageModel.armour_split].
var armour: int = 0
var has_helmet: bool = false
var is_dead: bool = false
## The damage event that caused the most recent death (null while alive).
var last_death: DamageInfo = null


func _ready() -> void:
	current = max_health


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


func fraction() -> float:
	return float(current) / float(max_health)
