class_name DamageModel
extends RefCounted
## How much damage a hit does: weapon base damage × hit-zone multiplier × range falloff.
##
## Armour: a vest protects every zone except the legs; the head needs a helmet. Protected hits
## pass only the weapon's armour penetration fraction to health and cost armour points.
## Wall penetration is not modelled yet.

const ZONE_HEAD: StringName = &"head"
const ZONE_CHEST: StringName = &"chest"
const ZONE_STOMACH: StringName = &"stomach"
const ZONE_ARMS: StringName = &"arms"
const ZONE_LEGS: StringName = &"legs"

const ZONE_MULTIPLIERS: Dictionary[StringName, float] = {
	ZONE_HEAD: 4.0,
	ZONE_CHEST: 1.0,
	ZONE_STOMACH: 1.25,
	ZONE_ARMS: 0.9,
	ZONE_LEGS: 0.75,
}


static func zone_multiplier(zone: StringName) -> float:
	return ZONE_MULTIPLIERS.get(zone, 1.0)


static func falloff(weapon: WeaponDefinition, distance: float) -> float:
	return pow(weapon.falloff_per_10m, maxf(distance, 0.0) / 10.0)


## Fraction of the absorbed damage that is taken from armour points.
const ARMOUR_WEAR: float = 0.5


static func is_protected(zone: StringName, armour: int, helmet: bool) -> bool:
	if armour <= 0 or zone == ZONE_LEGS:
		return false
	return zone != ZONE_HEAD or helmet


## Splits [param amount] into [health damage, armour damage] given the target's armour.
static func armour_split(amount: int, penetration: float, zone: StringName, armour: int, helmet: bool) -> Array[int]:
	if penetration >= 1.0 or not is_protected(zone, armour, helmet):
		return [amount, 0]
	var to_health := roundi(amount * penetration)
	var to_armour := mini(roundi((amount - to_health) * ARMOUR_WEAR), armour)
	return [to_health, to_armour]


## Whole-number damage for a hit on [param zone] at [param distance] metres (at least 1).
static func damage_for(weapon: WeaponDefinition, zone: StringName, distance: float) -> int:
	return maxi(roundi(weapon.damage * zone_multiplier(zone) * falloff(weapon, distance)), 1)
