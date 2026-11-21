class_name CharacterCatalog
extends RefCounted
## Every base character (body) and character cosmetic item the game knows, read from
## res://data/characters/character_catalog.json ([constant FORMAT] v1). Plain data: no nodes.
##
## - A **pack** is one downloaded asset pack (author, licence, whether it may be redistributed).
## - A **body** is a base character on one rig. It offers a set of slots, some required, and
##   default items. The modular body has no model of its own: it is built from its parts.
## - An **item** sits in one slot, fits the bodies it lists (the packs share neither skeletons nor
##   proportions), names its colour channels (one per material, optionally a team-colour role),
##   may cover other slots (a costume hides the clothes under it) and carries unlock metadata.
##
## Items whose model file is missing are "not installed": the ithappy pack has no
## redistribution licence, so builds made from the public repository do not contain it.

const PATH: String = "res://data/characters/character_catalog.json"
const FORMAT: String = "f2f.character_catalog"
const FORMAT_VERSION: int = 1
const ITEM_PREFIX: String = "chr_"
const BODY_PREFIX: String = "body_"
const FIT_SKINNED: String = "skinned"
const FIT_HEAD: String = "head"

static var _shared: CharacterCatalog = null

## "" when the catalog loaded, else why it did not.
var error: String = ""
var animation_library: String = ""
var slots: Array[Dictionary] = []
var packs: Dictionary[String, Dictionary] = {}
var rigs: Dictionary[String, Dictionary] = {}
var bodies: Dictionary[String, Dictionary] = {}
var items: Dictionary[String, Dictionary] = {}

var _slot_index: Dictionary[String, int] = {}
var _available: Dictionary[String, bool] = {}


## The catalog shipped with the game (loaded once).
static func shared() -> CharacterCatalog:
	if _shared == null:
		_shared = load_file(PATH)
	return _shared


static func load_file(path: String) -> CharacterCatalog:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not parsed is Dictionary:
		var broken := CharacterCatalog.new()
		broken.error = "Could not read %s." % path
		return broken
	return from_dict(parsed as Dictionary)


static func from_dict(data: Dictionary) -> CharacterCatalog:
	var catalog := CharacterCatalog.new()
	if str(data.get("format", "")) != FORMAT or int(data.get("format_version", 0)) != FORMAT_VERSION:
		catalog.error = "Not a %s v%d file." % [FORMAT, FORMAT_VERSION]
		return catalog
	catalog.animation_library = str((data.get("animation", {}) as Dictionary).get("library", ""))
	for slot: Variant in data.get("slots", []):
		catalog._slot_index[str((slot as Dictionary)["id"])] = catalog.slots.size()
		catalog.slots.append(slot as Dictionary)
	for entry: Variant in data.get("packs", []):
		catalog.packs[str((entry as Dictionary)["id"])] = entry as Dictionary
	for entry: Variant in data.get("rigs", []):
		catalog.rigs[str((entry as Dictionary)["id"])] = entry as Dictionary
	for entry: Variant in data.get("bodies", []):
		catalog.bodies[str((entry as Dictionary)["id"])] = entry as Dictionary
	for entry: Variant in data.get("items", []):
		catalog.items[str((entry as Dictionary)["id"])] = entry as Dictionary
	return catalog


func is_ok() -> bool:
	return error.is_empty()


# --- slots ---------------------------------------------------------------------------------------

func slot_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot: Dictionary in slots:
		ids.append(str(slot["id"]))
	return ids


func has_slot(slot_id: String) -> bool:
	return _slot_index.has(slot_id)


func slot_label(slot_id: String) -> String:
	return str(slots[_slot_index[slot_id]]["label"]) if _slot_index.has(slot_id) else slot_id


## The slots [param body_id] offers, in catalog slot order.
func body_slots(body_id: String) -> Array[String]:
	var offered: Array = body(body_id).get("slots", [])
	var ids: Array[String] = []
	for slot_id: String in slot_ids():
		if offered.has(slot_id):
			ids.append(slot_id)
	return ids


func is_required(body_id: String, slot_id: String) -> bool:
	return (body(body_id).get("required", []) as Array).has(slot_id)


func default_item(body_id: String, slot_id: String) -> String:
	return str((body(body_id).get("defaults", {}) as Dictionary).get(slot_id, ""))


# --- bodies and items ------------------------------------------------------------------------------

func body_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(bodies.keys())
	return ids


func body(body_id: String) -> Dictionary:
	return bodies.get(body_id, {})


func has_body(body_id: String) -> bool:
	return bodies.has(body_id)


func item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


func has_item(item_id: String) -> bool:
	return items.has(item_id)


func display_name(id: String) -> String:
	if items.has(id):
		return str(items[id]["name"])
	if bodies.has(id):
		return str(bodies[id]["name"])
	return id


## Items in [param slot_id] for [param body_id] ("" = every body), in catalog order.
func items_for(slot_id: String, body_id: String = "") -> Array[String]:
	var ids: Array[String] = []
	for id: String in items:
		var entry := items[id]
		if str(entry["slot"]) == slot_id and (body_id.is_empty() or not fit_mode(id, body_id).is_empty()):
			ids.append(id)
	return ids


func pack_of(id: String) -> Dictionary:
	var entry := item(id) if items.has(id) else body(id)
	return packs.get(str(entry.get("pack", "")), {})


## Colour channels of an item: [{id, material, label, team?}].
func colour_channels(item_id: String) -> Array[Dictionary]:
	var channels: Array[Dictionary] = []
	for channel: Variant in item(item_id).get("colours", []):
		channels.append(channel as Dictionary)
	return channels


## The channel of [param item_id] that takes a team's [param role] colour ("primary" or
## "secondary"), or "".
func team_channel(item_id: String, role: String) -> String:
	for channel: Dictionary in colour_channels(item_id):
		if str(channel.get("team", "")) == role:
			return str(channel["id"])
	return ""


## Slots an item hides when worn (its own slot excluded).
func covers(item_id: String) -> Array[String]:
	var ids: Array[String] = []
	for slot_id: Variant in item(item_id).get("covers", []):
		ids.append(str(slot_id))
	return ids


# --- availability and fit -------------------------------------------------------------------------

## Whether a body's or item's model is in this build. A modular body is available when its
## required default parts are.
func is_available(id: String) -> bool:
	if _available.has(id):
		return _available[id]
	var result := false
	if items.has(id):
		result = ResourceLoader.exists(str(items[id]["model"]))
	elif bodies.has(id):
		var model := str(bodies[id].get("model", ""))
		if not model.is_empty():
			result = ResourceLoader.exists(model)
		else:
			result = true
			for slot_id: Variant in bodies[id].get("required", []):
				var part := default_item(id, str(slot_id))
				result = result and not part.is_empty() and is_available(part)
	_available[id] = result
	return result


## Why a body or item cannot be shown ("" when it can).
func unavailable_reason(id: String) -> String:
	if not items.has(id) and not bodies.has(id):
		return "Unknown item."
	if is_available(id):
		return ""
	var pack := pack_of(id)
	return "Not installed: the %s pack by %s is not in this build (%s)." % [pack.get("name", "?"),
		pack.get("author", "?"), pack.get("license", "?")]


## "" when [param item_id] can be worn on [param body_id], else why not.
func fit_problem(item_id: String, body_id: String) -> String:
	if not items.has(item_id):
		return "Unknown item."
	if not bodies.has(body_id):
		return "Unknown base character."
	var entry := items[item_id]
	if not (body(body_id).get("slots", []) as Array).has(str(entry["slot"])):
		return "%s has no %s slot." % [display_name(body_id), slot_label(str(entry["slot"])).to_lower()]
	if fit_mode(item_id, body_id).is_empty():
		var made_for: Array[String] = []
		for fit: Variant in entry.get("fits", []):
			made_for.append(display_name(str(fit)))
		return "Made for %s: a different skeleton and different proportions." % ", ".join(made_for)
	return ""


## How an item goes on a body: [constant FIT_SKINNED] (skinned to the body's skeleton: same pack),
## [constant FIT_HEAD] (an item rigged to the head alone, carried by the body's Head bone and
## fitted from its own body's head to this one; listed under the item's "adapt") or "" (no fit).
func fit_mode(item_id: String, body_id: String) -> String:
	var entry := item(item_id)
	if (entry.get("fits", []) as Array).has(body_id):
		return FIT_SKINNED
	if (entry.get("adapt", {}) as Dictionary).has(body_id):
		return FIT_HEAD
	return ""


## The body an item was made for (its first "fits" entry).
func native_body(item_id: String) -> String:
	var fits: Array = item(item_id).get("fits", [])
	return str(fits[0]) if not fits.is_empty() else ""


## A body's head box at rest in model space: {"center": Vector3, "size": Vector3}.
func head_box(body_id: String) -> Dictionary:
	var box: Dictionary = body(body_id).get("head_box", {})
	return {"center": _vector(box.get("center", [0.0, 1.7, 0.0])), "size": _vector(box.get("size", [0.2, 0.25, 0.22]))}


static func _vector(values: Variant) -> Vector3:
	var list: Array = values if values is Array else []
	return Vector3(float(list[0]), float(list[1]), float(list[2])) if list.size() == 3 else Vector3.ZERO


## The model whose skeleton a body is built on: its own model, or (modular body) the first
## required part's model. "" when none is available.
func skeleton_model(body_id: String) -> String:
	var model := str(body(body_id).get("model", ""))
	if not model.is_empty():
		return model
	for slot_id: Variant in body(body_id).get("required", []):
		var part := default_item(body_id, str(slot_id))
		if is_available(part):
			return str(items[part]["model"])
	return ""


## Forgets cached availability (tests that add or remove files).
func refresh_availability() -> void:
	_available.clear()
