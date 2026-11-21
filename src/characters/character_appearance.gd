class_name CharacterAppearance
extends RefCounted
## What one character looks like: a base character, the item in each slot, colours per item
## channel and a skin tone. Plain data that travels as a small dictionary ([constant FORMAT] v1),
## so it can live in presets, the player's profile, team uniforms and, later, match setups and
## multiplayer messages. Rules about what may be worn together live in [CharacterWardrobe].

const FORMAT: String = "f2f.character_appearance"
const FORMAT_VERSION: int = 1

## Body ID from [CharacterCatalog].
var body: String = ""
## slot ID -> item ID.
var items: Dictionary[String, String] = {}
## item ID -> {channel ID -> "#rrggbb"}. A channel with no entry keeps the model's own colour.
var colours: Dictionary[String, Dictionary] = {}
## "" = the body's own skin; else "#rrggbb" (replaces or multiplies, per the body's skin mode).
var skin_tone: String = ""
## ID of one of the body's skin textures ("" = the first).
var skin_texture: String = ""


func item_in(slot_id: String) -> String:
	return items.get(slot_id, "")


func has_colour(item_id: String, channel_id: String) -> bool:
	return colours.has(item_id) and (colours[item_id] as Dictionary).has(channel_id)


func colour(item_id: String, channel_id: String, fallback: Color = Color.WHITE) -> Color:
	if not has_colour(item_id, channel_id):
		return fallback
	return Color.from_string(str(colours[item_id][channel_id]), fallback)


func set_colour(item_id: String, channel_id: String, value: Color) -> void:
	var entry: Dictionary = colours.get(item_id, {})
	entry[channel_id] = "#" + value.to_html(false)
	colours[item_id] = entry


## Returns an item channel to the model's own colour ("" channel = every channel of the item).
func clear_colour(item_id: String, channel_id: String = "") -> void:
	if channel_id.is_empty():
		colours.erase(item_id)
		return
	if colours.has(item_id):
		(colours[item_id] as Dictionary).erase(channel_id)
		if (colours[item_id] as Dictionary).is_empty():
			colours.erase(item_id)


func to_dict() -> Dictionary:
	var item_map: Dictionary = {}
	for slot_id: String in items:
		item_map[slot_id] = items[slot_id]
	var colour_map: Dictionary = {}
	for item_id: String in colours:
		if items.values().has(item_id):
			colour_map[item_id] = (colours[item_id] as Dictionary).duplicate()
	return {"format": FORMAT, "format_version": FORMAT_VERSION, "body": body, "items": item_map,
		"colours": colour_map, "skin_tone": _tone_text(skin_tone), "skin_texture": skin_texture}


## Reads a dictionary leniently: unknown fields are ignored and malformed values dropped.
## Whether the items exist or fit is checked by [method CharacterWardrobe.sanitize].
static func from_dict(data: Dictionary) -> CharacterAppearance:
	var appearance := CharacterAppearance.new()
	appearance.body = str(data.get("body", ""))
	var item_map: Variant = data.get("items", {})
	if item_map is Dictionary:
		for slot_id: Variant in item_map:
			if str(item_map[slot_id]) != "":
				appearance.items[str(slot_id)] = str(item_map[slot_id])
	var colour_map: Variant = data.get("colours", {})
	if colour_map is Dictionary:
		for item_id: Variant in colour_map:
			var channels: Variant = colour_map[item_id]
			if not channels is Dictionary:
				continue
			var clean: Dictionary = {}
			for channel_id: Variant in channels:
				var text := str(channels[channel_id])
				if Color.html_is_valid(text):
					clean[str(channel_id)] = "#" + Color.html(text).to_html(false)
			if not clean.is_empty():
				appearance.colours[str(item_id)] = clean
	appearance.skin_tone = _tone_text(str(data.get("skin_tone", "")))
	appearance.skin_texture = str(data.get("skin_texture", ""))
	return appearance


## A skin tone as stored: "#rrggbb", or "" (the body's own) when it is not a colour.
static func _tone_text(tone: String) -> String:
	return "#" + Color.html(tone).to_html(false) if Color.html_is_valid(tone) else ""


func duplicate_appearance() -> CharacterAppearance:
	return from_dict(to_dict())


func equals(other: CharacterAppearance) -> bool:
	return other != null and to_dict() == other.to_dict()
