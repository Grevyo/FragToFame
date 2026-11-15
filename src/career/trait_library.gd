class_name TraitLibrary
extends RefCounted
## Data-driven personality/playstyle traits. Saves store only trait IDs + strength (1–3); the
## definitions live here so they can be extended or rebalanced without migrating saves.
##
## Each trait: category, display name, description, conflicts (traits that cannot coexist) and
## "leans" — the abilities or behaviours it nudges. In Milestone 9 traits are generated, stored
## and shown; the decision systems that consume them (tactics, transfers, interviews,
## development) read them as they are built (M7, M12, M14).

const CATEGORIES: Array[StringName] = [&"mechanics", &"aggression", &"tactics", &"teamwork",
	&"mentality", &"career"]

const TRAITS: Dictionary[StringName, Dictionary] = {
	&"tr_flick_specialist": {"category": &"mechanics", "name": "Flick specialist",
		"description": "Wins duels with fast flicks; less steady in long sprays.", "conflicts": []},
	&"tr_spray_master": {"category": &"mechanics", "name": "Spray master",
		"description": "Controls recoil exceptionally in sustained fights.", "conflicts": []},
	&"tr_aggressive": {"category": &"aggression", "name": "Aggressive",
		"description": "Takes early fights and pushes for space.", "conflicts": [&"tr_passive"]},
	&"tr_passive": {"category": &"aggression", "name": "Patient",
		"description": "Holds angles and waits for the enemy to make mistakes.", "conflicts": [&"tr_aggressive"]},
	&"tr_risk_taker": {"category": &"aggression", "name": "Risk-taker",
		"description": "Goes for high-reward plays, sometimes recklessly.", "conflicts": [&"tr_cautious"]},
	&"tr_cautious": {"category": &"aggression", "name": "Cautious",
		"description": "Avoids unnecessary risks; saves when a round is lost.", "conflicts": [&"tr_risk_taker"]},
	&"tr_tactician": {"category": &"tactics", "name": "Tactician",
		"description": "Reads opponents and adapts plans mid-round.", "conflicts": []},
	&"tr_utility_expert": {"category": &"tactics", "name": "Utility expert",
		"description": "Precise, well-timed utility.", "conflicts": []},
	&"tr_lone_wolf": {"category": &"teamwork", "name": "Lone wolf",
		"description": "Prefers to play alone; hard to coordinate.", "conflicts": [&"tr_team_player"]},
	&"tr_team_player": {"category": &"teamwork", "name": "Team player",
		"description": "Trades, supports and puts the team first.", "conflicts": [&"tr_lone_wolf"]},
	&"tr_vocal": {"category": &"teamwork", "name": "Vocal communicator",
		"description": "Constant, useful information for teammates.", "conflicts": [&"tr_quiet"]},
	&"tr_quiet": {"category": &"teamwork", "name": "Quiet",
		"description": "Says little; teammates get less information.", "conflicts": [&"tr_vocal"]},
	&"tr_clutch_player": {"category": &"mentality", "name": "Clutch player",
		"description": "Thrives in 1vX situations and big moments.", "conflicts": [&"tr_pressure_prone"]},
	&"tr_pressure_prone": {"category": &"mentality", "name": "Feels the pressure",
		"description": "Performs worse in decisive rounds and big events.", "conflicts": [&"tr_clutch_player"]},
	&"tr_streaky": {"category": &"mentality", "name": "Streaky",
		"description": "Form swings between brilliant and poor.", "conflicts": [&"tr_steady"]},
	&"tr_steady": {"category": &"mentality", "name": "Steady",
		"description": "Rarely has a very bad game.", "conflicts": [&"tr_streaky"]},
	&"tr_hot_headed": {"category": &"mentality", "name": "Hot-headed",
		"description": "Tilts after setbacks; volatile in interviews.", "conflicts": [&"tr_calm"]},
	&"tr_calm": {"category": &"mentality", "name": "Calm",
		"description": "Unshaken by losses or trash talk.", "conflicts": [&"tr_hot_headed"]},
	&"tr_ambitious": {"category": &"career", "name": "Ambitious",
		"description": "Wants to play at the highest level and win titles.", "conflicts": []},
	&"tr_loyal": {"category": &"career", "name": "Loyal",
		"description": "Values staying with a team; hard to tempt away.", "conflicts": [&"tr_mercenary"]},
	&"tr_mercenary": {"category": &"career", "name": "Mercenary",
		"description": "Follows the best contract offer.", "conflicts": [&"tr_loyal"]},
	&"tr_hard_worker": {"category": &"career", "name": "Hard worker",
		"description": "Disciplined in training; improves faster.", "conflicts": [&"tr_coaster"]},
	&"tr_coaster": {"category": &"career", "name": "Coasts in training",
		"description": "Relies on talent; develops slower.", "conflicts": [&"tr_hard_worker"]},
	&"tr_adaptable": {"category": &"tactics", "name": "Adaptable",
		"description": "Comfortable in any role or system.", "conflicts": []},
}


static func has_trait(id: StringName) -> bool:
	return TRAITS.has(id)


static func trait_name(id: StringName) -> String:
	return str(TRAITS[id]["name"]) if TRAITS.has(id) else String(id)


static func describe(id: StringName) -> String:
	return str(TRAITS[id]["description"]) if TRAITS.has(id) else ""


static func conflicts(a: StringName, b: StringName) -> bool:
	if not TRAITS.has(a) or not TRAITS.has(b):
		return false
	return (TRAITS[a]["conflicts"] as Array).has(b) or (TRAITS[b]["conflicts"] as Array).has(a)


## True when no two traits in [param ids] conflict.
static func compatible(ids: Array[StringName]) -> bool:
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			if conflicts(ids[i], ids[j]):
				return false
	return true


static func ids() -> Array[StringName]:
	var list: Array[StringName] = []
	for id: StringName in TRAITS:
		list.append(id)
	return list
