class_name CharacterWardrobe
extends RefCounted
## Rules for dressing a [CharacterAppearance] from a [CharacterCatalog]: what fits which body,
## what a worn item covers, which slots must be filled, defaults, randomising and team colours.
## Pure data: the creator, presets, profiles and the FPS runtime all go through these rules.

## Chance that an optional slot is filled when randomising (costumes are rarer).
const OPTIONAL_CHANCE: float = 0.55
const COSTUME_CHANCE: float = 0.12
## Chance that an item channel keeps the model's own colour when randomising.
const FACTORY_COLOUR_CHANCE: float = 0.45


## A body wearing its default items (only those installed).
static func default_appearance(catalog: CharacterCatalog, body_id: String) -> CharacterAppearance:
	var appearance := CharacterAppearance.new()
	appearance.body = body_id
	for slot_id: String in catalog.body_slots(body_id):
		var item_id := catalog.default_item(body_id, slot_id)
		if not item_id.is_empty() and catalog.is_available(item_id):
			equip(catalog, appearance, item_id)
	return appearance


## The first installed body, or "".
static func first_available_body(catalog: CharacterCatalog) -> String:
	for body_id: String in catalog.body_ids():
		if catalog.is_available(body_id):
			return body_id
	return ""


## Puts an item on. Items it covers come off, and so does anything covering its slot.
## Returns "" or why it cannot be worn.
static func equip(catalog: CharacterCatalog, appearance: CharacterAppearance, item_id: String) -> String:
	var problem := catalog.fit_problem(item_id, appearance.body)
	if problem.is_empty():
		problem = catalog.unavailable_reason(item_id)
	if not problem.is_empty():
		return problem
	var slot_id := str(catalog.item(item_id)["slot"])
	for covered: String in catalog.covers(item_id):
		appearance.items.erase(covered)
	for worn_slot: String in appearance.items.keys():
		if catalog.covers(appearance.items[worn_slot]).has(slot_id):
			appearance.items.erase(worn_slot)
	appearance.items[slot_id] = item_id
	return ""


## Empties a slot. Returns "" or why it must stay filled.
static func unequip(catalog: CharacterCatalog, appearance: CharacterAppearance, slot_id: String) -> String:
	if catalog.is_required(appearance.body, slot_id) and covered_by(catalog, appearance, slot_id).is_empty():
		return "%s cannot be left empty on %s." % [catalog.slot_label(slot_id), catalog.display_name(appearance.body)]
	appearance.items.erase(slot_id)
	return ""


## The worn item hiding [param slot_id], or "".
static func covered_by(catalog: CharacterCatalog, appearance: CharacterAppearance, slot_id: String) -> String:
	for worn_slot: String in appearance.items:
		var worn := appearance.items[worn_slot]
		if worn_slot != slot_id and catalog.covers(worn).has(slot_id):
			return worn
	return ""


## Makes an appearance wearable: an unknown or missing body becomes the first installed one;
## unknown, misplaced, unfitting, uninstalled, covered or disallowed items come off; empty
## required slots get their default; colours of items not worn and unknown channels are dropped.
## [param allowed] (item ID -> bool), when valid, is the unlock gate. Returns what was changed.
static func sanitize(catalog: CharacterCatalog, appearance: CharacterAppearance, allowed: Callable = Callable()) -> PackedStringArray:
	var notes := PackedStringArray()
	if not catalog.has_body(appearance.body) or not catalog.is_available(appearance.body):
		var replacement := first_available_body(catalog)
		notes.append("%s is not available; using %s." % [catalog.display_name(appearance.body) if not appearance.body.is_empty() else "No base character",
			catalog.display_name(replacement)])
		var fresh := default_appearance(catalog, replacement) if not replacement.is_empty() else CharacterAppearance.new()
		appearance.body = fresh.body
		appearance.items = fresh.items
		appearance.colours.clear()
		appearance.skin_texture = ""
		return notes
	var kept: Dictionary[String, String] = {}
	for slot_id: String in appearance.items:
		var item_id := appearance.items[slot_id]
		var problem := ""
		if not catalog.has_item(item_id):
			problem = "unknown item"
		elif str(catalog.item(item_id)["slot"]) != slot_id:
			problem = "it belongs in %s" % catalog.slot_label(str(catalog.item(item_id)["slot"])).to_lower()
		else:
			problem = catalog.fit_problem(item_id, appearance.body)
			if problem.is_empty():
				problem = catalog.unavailable_reason(item_id)
			if problem.is_empty() and allowed.is_valid() and not bool(allowed.call(item_id)):
				problem = "locked"
		if problem.is_empty():
			kept[slot_id] = item_id
		else:
			notes.append("Removed %s: %s" % [catalog.display_name(item_id), problem.trim_suffix(".")])
	appearance.items = kept
	for slot_id: String in appearance.items.keys():
		var cover := covered_by(catalog, appearance, slot_id)
		if not cover.is_empty() and appearance.items.has(slot_id):
			notes.append("Removed %s: covered by %s" % [catalog.display_name(appearance.items[slot_id]), catalog.display_name(cover)])
			appearance.items.erase(slot_id)
	for slot_id: String in catalog.body_slots(appearance.body):
		if catalog.is_required(appearance.body, slot_id) and not appearance.items.has(slot_id) \
				and covered_by(catalog, appearance, slot_id).is_empty():
			var fallback := catalog.default_item(appearance.body, slot_id)
			if not fallback.is_empty() and equip(catalog, appearance, fallback).is_empty():
				notes.append("%s was empty; wearing %s." % [catalog.slot_label(slot_id), catalog.display_name(fallback)])
	for item_id: String in appearance.colours.keys():
		if not appearance.items.values().has(item_id):
			appearance.colours.erase(item_id)
			continue
		var known: Array[String] = []
		for channel: Dictionary in catalog.colour_channels(item_id):
			known.append(str(channel["id"]))
		for channel_id: String in (appearance.colours[item_id] as Dictionary).keys():
			if not known.has(channel_id):
				appearance.clear_colour(item_id, channel_id)
	if not appearance.skin_texture.is_empty() and skin_texture_path(catalog, appearance.body, appearance.skin_texture).is_empty():
		appearance.skin_texture = ""
	return notes


## A random wearable appearance. [param body_id] "" picks an installed body at random;
## [param allowed] (item ID -> bool), when valid, limits the items (unlocks).
static func randomise(catalog: CharacterCatalog, rng: RandomNumberGenerator, body_id: String = "",
		allowed: Callable = Callable()) -> CharacterAppearance:
	if body_id.is_empty():
		var choices: Array[String] = []
		for id: String in catalog.body_ids():
			if catalog.is_available(id):
				choices.append(id)
		body_id = choices[rng.randi_range(0, choices.size() - 1)] if not choices.is_empty() else ""
	var appearance := CharacterAppearance.new()
	appearance.body = body_id
	if body_id.is_empty():
		return appearance
	for slot_id: String in catalog.body_slots(body_id):
		var candidates: Array[String] = []
		for item_id: String in catalog.items_for(slot_id, body_id):
			if catalog.is_available(item_id) and (not allowed.is_valid() or bool(allowed.call(item_id))):
				candidates.append(item_id)
		if candidates.is_empty() or not covered_by(catalog, appearance, slot_id).is_empty():
			continue
		var chance := 1.0 if catalog.is_required(body_id, slot_id) else (COSTUME_CHANCE if slot_id == "costume" else OPTIONAL_CHANCE)
		if rng.randf() < chance:
			equip(catalog, appearance, candidates[rng.randi_range(0, candidates.size() - 1)])
	for item_id: String in appearance.items.values():
		for channel: Dictionary in catalog.colour_channels(item_id):
			if rng.randf() >= FACTORY_COLOUR_CHANCE:
				appearance.set_colour(item_id, str(channel["id"]), Color.from_hsv(rng.randf(), rng.randf_range(0.25, 0.85), rng.randf_range(0.25, 0.95)))
	var tones: Array = (catalog.body(body_id).get("skin", {}) as Dictionary).get("tones", [])
	if not tones.is_empty():
		appearance.skin_tone = str(tones[rng.randi_range(0, tones.size() - 1)])
	var textures := skin_textures(catalog, body_id)
	if not textures.is_empty():
		appearance.skin_texture = str(textures[rng.randi_range(0, textures.size() - 1)]["id"])
	sanitize(catalog, appearance, allowed)
	return appearance


## Paints every worn item's team channels: "primary" and "secondary" (team uniforms).
static func apply_team_colours(catalog: CharacterCatalog, appearance: CharacterAppearance, primary: Color, secondary: Color) -> void:
	for item_id: String in appearance.items.values():
		var primary_channel := catalog.team_channel(item_id, "primary")
		if not primary_channel.is_empty():
			appearance.set_colour(item_id, primary_channel, primary)
		var secondary_channel := catalog.team_channel(item_id, "secondary")
		if not secondary_channel.is_empty():
			appearance.set_colour(item_id, secondary_channel, secondary)


## The body's skin textures: [{id, label, texture}] (empty for flat-colour skins).
static func skin_textures(catalog: CharacterCatalog, body_id: String) -> Array[Dictionary]:
	var textures: Array[Dictionary] = []
	for entry: Variant in (catalog.body(body_id).get("skin", {}) as Dictionary).get("textures", []):
		textures.append(entry as Dictionary)
	return textures


static func skin_texture_path(catalog: CharacterCatalog, body_id: String, texture_id: String) -> String:
	for entry: Dictionary in skin_textures(catalog, body_id):
		if str(entry["id"]) == texture_id:
			return str(entry["texture"])
	return ""
