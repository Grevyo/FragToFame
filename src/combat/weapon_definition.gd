class_name WeaponDefinition
extends RefCounted
## Static stats for one weapon type. Pure data: tune values in [WeaponCatalog], never in code paths.
##
## Angles are in degrees. Recoil pattern entries are the view kick added *after* each shot
## (x = yaw to the right, y = pitch up), so the first bullet of a spray always goes where the
## player aims (plus spread).

enum FireMode { SEMI, AUTO }

const CATEGORY_PRIMARY: StringName = &"primary"
const CATEGORY_SECONDARY: StringName = &"secondary"
## The knife: always carried, never bought, never dropped.
const CATEGORY_MELEE: StringName = &"melee"
## Thrown utility (grenades); [member magazine_size] is how many of it one player may carry.
const CATEGORY_UTILITY: StringName = &"utility"

var id: StringName = &""
var display_name: String = ""
## Loadout slot (1 = primary, 2 = secondary, 3 = alternative primary in the sandbox).
var slot: int = 1
## Loadout category: a player carries at most one primary and one secondary in matches, always
## the knife, and up to [constant EquipmentCatalog.UTILITY_CARRY_LIMIT] pieces of utility.
var category: StringName = CATEGORY_PRIMARY
var fire_mode: FireMode = FireMode.AUTO
var damage: float = 30.0
## Seconds between shots (60 / rounds per minute).
var fire_interval: float = 0.1
var magazine_size: int = 30
var reserve_ammo: int = 90
var reload_time: float = 2.5
## Seconds after switching to this weapon before it can fire.
var draw_time: float = 0.45
var range_m: float = 250.0
## Damage multiplier applied per 10 m of distance (1.0 = no falloff).
var falloff_per_10m: float = 0.95
## Fraction of damage that reaches health through armour (1.0 = armour ignored).
var armour_penetration: float = 0.7
## Run speed with this weapon in hand, as a fraction of [member PlayerMovement.run_speed]
## (the unencumbered 250 u/s reference). Walk, crouch and acceleration scale with it.
var mobility: float = 1.0

var base_spread: float = 0.2
## Extra spread at full running speed (scales with the square of the speed ratio).
var run_spread: float = 4.0
var air_spread: float = 8.0
var crouch_multiplier: float = 0.75
var bloom_per_shot: float = 0.4
var bloom_max: float = 3.0
## Degrees of bloom recovered per second.
var bloom_recovery: float = 6.0

var recoil_pattern: Array[Vector2] = []
## Seconds without firing before the recoil offset starts to recover.
var recovery_delay: float = 0.12
## Degrees of recoil offset recovered per second.
var recovery_rate: float = 14.0
## Fraction of the recoil offset shown as camera punch (bullets follow the full offset).
var view_punch: float = 0.5
## Knife and utility parameters from [EquipmentCatalog] (empty for firearms).
var equipment: Dictionary = {}


static func from_dict(data: Dictionary) -> WeaponDefinition:
	var d := WeaponDefinition.new()
	d.id = StringName(str(data["id"]))
	d.display_name = str(data["name"])
	d.slot = int(data.get("slot", 1))
	d.category = StringName(str(data.get("category", "primary")))
	d.armour_penetration = float(data.get("armour_penetration", d.armour_penetration))
	d.fire_mode = FireMode.AUTO if bool(data.get("automatic", true)) else FireMode.SEMI
	d.mobility = float(data.get("mobility", d.mobility))
	d.damage = float(data.get("damage", d.damage))
	d.fire_interval = 60.0 / float(data.get("rpm", 60.0 / d.fire_interval))
	d.magazine_size = int(data.get("magazine", d.magazine_size))
	d.reserve_ammo = int(data.get("reserve", d.reserve_ammo))
	d.reload_time = float(data.get("reload_time", d.reload_time))
	d.draw_time = float(data.get("draw_time", d.draw_time))
	d.range_m = float(data.get("range", d.range_m))
	d.falloff_per_10m = float(data.get("falloff_per_10m", d.falloff_per_10m))
	d.base_spread = float(data.get("base_spread", d.base_spread))
	d.run_spread = float(data.get("run_spread", d.run_spread))
	d.air_spread = float(data.get("air_spread", d.air_spread))
	d.crouch_multiplier = float(data.get("crouch_multiplier", d.crouch_multiplier))
	d.bloom_per_shot = float(data.get("bloom_per_shot", d.bloom_per_shot))
	d.bloom_max = float(data.get("bloom_max", d.bloom_max))
	d.bloom_recovery = float(data.get("bloom_recovery", d.bloom_recovery))
	d.recovery_delay = float(data.get("recovery_delay", d.recovery_delay))
	d.recovery_rate = float(data.get("recovery_rate", d.recovery_rate))
	d.view_punch = float(data.get("view_punch", d.view_punch))
	d.equipment = (data.get("equipment", {}) as Dictionary).duplicate(true)
	var ups: Array = data.get("recoil_up", [])
	var yaws: Array = data.get("recoil_yaw", [])
	for i: int in ups.size():
		d.recoil_pattern.append(Vector2(float(yaws[i]) if i < yaws.size() else 0.0, float(ups[i])))
	return d


## True for guns (they shoot bullets through [WeaponState]); false for the knife and utility.
func is_firearm() -> bool:
	return category == CATEGORY_PRIMARY or category == CATEGORY_SECONDARY


func is_melee() -> bool:
	return category == CATEGORY_MELEE


func is_utility() -> bool:
	return category == CATEGORY_UTILITY


func is_automatic() -> bool:
	return fire_mode == FireMode.AUTO


func rounds_per_minute() -> float:
	return 60.0 / fire_interval


## Recoil kick after shot number [param index] (0-based); the last entry repeats.
func recoil_kick(index: int) -> Vector2:
	if recoil_pattern.is_empty():
		return Vector2.ZERO
	return recoil_pattern[clampi(index, 0, recoil_pattern.size() - 1)]
