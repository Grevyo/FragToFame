class_name CharacterUnlocks
extends RefCounted
## The one gate for whether a player may wear a character item. Each catalog item carries
## `unlock` metadata: {"kind": ..., optional "requirement" (text for players), "career" (rule)}.
##
## - starter: everyone has it.
## - career: earned by what the player did in a career. The rule is
##   {"stat": <progress key>, "at_least": n}; progress comes from the career world
##   (`CareerUnlockProgress`: matches, kills, contracts, podiums, titles) and
##   [method earned_items] lists what it has earned. Earned items are added to the player's owned
##   list (CosmeticProfile.owned_character_items) and stay owned across careers.
## - event, team: must be owned; nothing grants these yet (team uniforms are colours, see
##   CareerKits).
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


## An item's career rule ({stat, at_least}), empty when it has none.
static func career_rule(catalog: CharacterCatalog, item_id: String) -> Dictionary:
	if kind_of(catalog, item_id) != KIND_CAREER:
		return {}
	var rule: Variant = (catalog.item(item_id).get("unlock", {}) as Dictionary).get("career", {})
	return rule as Dictionary if rule is Dictionary and (rule as Dictionary).has("stat") else {}


## Career items that [param progress] (stat -> count) has earned, in catalog order.
static func earned_items(catalog: CharacterCatalog, progress: Dictionary) -> Array[String]:
	var earned: Array[String] = []
	for item_id: String in catalog.items:
		var rule := career_rule(catalog, item_id)
		if not rule.is_empty() and int(progress.get(str(rule["stat"]), 0)) >= int(rule.get("at_least", 1)):
			earned.append(item_id)
	return earned


## Adds every career item [param progress] has earned to [param owned]. Returns the new ones.
static func grant_earned(catalog: CharacterCatalog, owned: Array[String], progress: Dictionary) -> Array[String]:
	var granted: Array[String] = []
	for item_id: String in earned_items(catalog, progress):
		if not owned.has(item_id):
			owned.append(item_id)
			granted.append(item_id)
	return granted


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
