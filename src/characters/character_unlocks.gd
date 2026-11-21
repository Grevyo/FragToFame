class_name CharacterUnlocks
extends RefCounted
## The one gate for whether a player may wear a character item. Each catalog item carries
## `unlock` metadata: {"kind": ..., optional "requirement", "note"}.
##
## - starter: everyone has it (every item shipped today).
## - career, event, team: must be owned: its ID is in the player's owned list
##   (CosmeticProfile.owned_character_items), granted later by career progression, events or a
##   team's uniform. Nothing grants these yet.
##
## Developer mode previews every item regardless of unlock status.

const KIND_STARTER: String = "starter"
const KIND_CAREER: String = "career"
const KIND_EVENT: String = "event"
const KIND_TEAM: String = "team"
const KINDS: Array[String] = [KIND_STARTER, KIND_CAREER, KIND_EVENT, KIND_TEAM]


static func kind_of(catalog: CharacterCatalog, item_id: String) -> String:
	var unlock: Dictionary = catalog.item(item_id).get("unlock", {})
	var kind := str(unlock.get("kind", KIND_STARTER))
	return kind if KINDS.has(kind) else KIND_STARTER


static func is_unlocked(catalog: CharacterCatalog, item_id: String, owned: Array[String], developer: bool) -> bool:
	if developer:
		return true
	if not catalog.has_item(item_id):
		return false
	return kind_of(catalog, item_id) == KIND_STARTER or owned.has(item_id)


## Why an item is locked, for the UI ("" when it is not).
static func lock_reason(catalog: CharacterCatalog, item_id: String, owned: Array[String], developer: bool) -> String:
	if is_unlocked(catalog, item_id, owned, developer):
		return ""
	var unlock: Dictionary = catalog.item(item_id).get("unlock", {})
	var requirement := str(unlock.get("requirement", ""))
	match kind_of(catalog, item_id):
		KIND_CAREER:
			return "Locked: earned in a career%s." % (" (%s)" % requirement if not requirement.is_empty() else "")
		KIND_EVENT:
			return "Locked: an event reward."
		KIND_TEAM:
			return "Locked: part of a team's uniform."
	return "Locked."
