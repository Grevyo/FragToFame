class_name DamageInfo
extends RefCounted
## One damage event. Plain data so it can later feed the match event stream and statistics.

const CAUSE_WEAPON: StringName = &"weapon"
const CAUSE_WORLD: StringName = &"world"
## Thrown utility (frag blast, fire); [member weapon_id] names the grenade.
const CAUSE_UTILITY: StringName = &"utility"

var amount: int = 0
## Damage actually removed from health (≤ amount); filled in by [Health].
var applied: int = 0
## Armour points removed by this hit; filled in by [Health].
var armour_damage: int = 0
## Fraction of [member amount] that passes through armour (1.0 = ignores armour).
var armour_penetration: float = 1.0
var cause: StringName = CAUSE_WEAPON
var zone: StringName = &""
var weapon_id: StringName = &""
## Stable ID of the attacker (player or bot ID), empty for world damage.
var source_id: String = ""
var distance: float = 0.0
var position: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO


static func world(amount_value: int) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_value
	info.cause = CAUSE_WORLD
	return info


func is_headshot() -> bool:
	return zone == DamageModel.ZONE_HEAD
