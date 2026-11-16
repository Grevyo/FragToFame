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
	WeaponCatalog.VANTA_RIFLE: {"name": "VK-12 Vanta rifle", "price": 2800, "kind": KIND_WEAPON},
	WeaponCatalog.WASP_SMG: {"name": "M-5 Wasp SMG", "price": 1250, "kind": KIND_WEAPON},
	WeaponCatalog.KESTREL_PISTOL: {"name": "P-4 Kestrel pistol", "price": 200, "kind": KIND_WEAPON},
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

## Money for killing an enemy, by weapon. Cheaper weapons pay more.
const KILL_REWARDS: Dictionary[StringName, int] = {
	WeaponCatalog.VANTA_RIFLE: 300,
	WeaponCatalog.WASP_SMG: 550,
	WeaponCatalog.KESTREL_PISTOL: 300,
}
const DEFAULT_KILL_REWARD: int = 300


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


static func kill_reward(weapon_id: StringName) -> int:
	return KILL_REWARDS.get(weapon_id, DEFAULT_KILL_REWARD)
