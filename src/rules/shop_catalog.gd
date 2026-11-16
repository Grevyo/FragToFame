class_name ShopCatalog
extends RefCounted
## Everything that can be bought in a match, with original prices, plus kill rewards.

const KIND_WEAPON: StringName = &"weapon"
const KIND_ARMOUR: StringName = &"armour"
const KIND_KIT: StringName = &"kit"

const ARMOUR_VEST: StringName = &"armour_vest"
const ARMOUR_VEST_HELMET: StringName = &"armour_vest_helmet"
const DEFUSE_KIT: StringName = &"defuse_kit"

## Price of adding a helmet to an existing full vest.
const HELMET_UPGRADE_PRICE: int = 350
const FULL_ARMOUR: int = 100

## Display order of the buy menu.
const ITEMS: Dictionary[StringName, Dictionary] = {
	WeaponCatalog.AK47: {"name": "AK-47", "price": 2700, "kind": KIND_WEAPON},
	WeaponCatalog.M4A1: {"name": "M4A1", "price": 3000, "kind": KIND_WEAPON},
	WeaponCatalog.SKS: {"name": "SKS", "price": 1900, "kind": KIND_WEAPON},
	WeaponCatalog.M14_EBR: {"name": "M14 EBR", "price": 3300, "kind": KIND_WEAPON},
	WeaponCatalog.L118A1: {"name": "L118A1", "price": 4750, "kind": KIND_WEAPON},
	WeaponCatalog.M24: {"name": "M24", "price": 4200, "kind": KIND_WEAPON},
	WeaponCatalog.G17: {"name": "G17", "price": 200, "kind": KIND_WEAPON},
	WeaponCatalog.M1911: {"name": "M1911", "price": 350, "kind": KIND_WEAPON},
	WeaponCatalog.MK23: {"name": "Mk23 SOCOM", "price": 500, "kind": KIND_WEAPON},
	WeaponCatalog.DESERT_EAGLE: {"name": "Desert Eagle", "price": 700, "kind": KIND_WEAPON},
	ARMOUR_VEST: {"name": "Vest", "price": 650, "kind": KIND_ARMOUR},
	ARMOUR_VEST_HELMET: {"name": "Vest + helmet", "price": 1000, "kind": KIND_ARMOUR},
	DEFUSE_KIT: {"name": "Defuse kit (defence)", "price": 400, "kind": KIND_KIT, "side": "defence"},
}

## Money for killing an enemy.
const KILL_REWARD: int = 300


static func has_item(id: StringName) -> bool:
	return ITEMS.has(id)


static func item_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in ITEMS:
		ids.append(id)
	return ids


static func display_name(id: StringName) -> String:
	return str(ITEMS.get(id, {}).get("name", id))


static func price(id: StringName) -> int:
	return int(ITEMS.get(id, {}).get("price", 0))


static func kind(id: StringName) -> StringName:
	return StringName(str(ITEMS.get(id, {}).get("kind", "")))


## Side restriction ("attack" / "defence"), or empty when anyone may buy it.
static func side_restriction(id: StringName) -> StringName:
	return StringName(str(ITEMS.get(id, {}).get("side", "")))
