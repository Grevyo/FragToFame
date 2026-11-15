class_name CareerCatalog
extends RefCounted
## Fixed vocabulary of the career world: abilities, roles, regions, nations, tiers, difficulties.
## IDs are stable strings stored in saves; display names may change freely.

## True simulated abilities (AI players) and the perceived equivalents (everyone), 1–100.
const ABILITIES: Array[StringName] = [
	&"aim", &"reaction", &"spray_control", &"crosshair_placement", &"movement",
	&"game_sense", &"positioning", &"utility", &"teamwork", &"communication",
	&"composure", &"consistency", &"leadership",
]
## Hidden development ceiling (AI only, never shown as a perceived value).
const POTENTIAL: StringName = &"potential"

const ABILITY_NAMES: Dictionary[StringName, String] = {
	&"aim": "Aim", &"reaction": "Reaction", &"spray_control": "Spray control",
	&"crosshair_placement": "Crosshair placement", &"movement": "Movement",
	&"game_sense": "Game sense", &"positioning": "Positioning", &"utility": "Utility usage",
	&"teamwork": "Teamwork", &"communication": "Communication", &"composure": "Composure",
	&"consistency": "Consistency", &"leadership": "Leadership",
}

const ROLES: Array[StringName] = [&"rifler", &"sniper", &"entry", &"support", &"lurker", &"igl"]
const ROLE_NAMES: Dictionary[StringName, String] = {
	&"rifler": "Rifler", &"sniper": "Sniper", &"entry": "Entry fragger", &"support": "Support",
	&"lurker": "Lurker", &"igl": "IGL",
}

## Abilities each role leans on (used by the generator and by role-fit ratings).
const ROLE_FOCUS: Dictionary[StringName, Array] = {
	&"rifler": [&"aim", &"spray_control", &"crosshair_placement"],
	&"sniper": [&"aim", &"reaction", &"positioning"],
	&"entry": [&"reaction", &"movement", &"aim"],
	&"support": [&"utility", &"teamwork", &"communication"],
	&"lurker": [&"game_sense", &"positioning", &"composure"],
	&"igl": [&"leadership", &"game_sense", &"communication"],
}

const REGIONS: Dictionary[String, String] = {
	"eu_north": "Europe North", "eu_west": "Europe West", "eu_east": "Europe East",
	"na": "North America", "sa": "South America", "apac": "Asia Pacific",
	"mea": "Middle East & Africa", "oce": "Oceania",
}

## nation id → [display name, region id]
const NATIONS: Dictionary[String, Array] = {
	"gb": ["United Kingdom", "eu_west"], "ie": ["Ireland", "eu_west"], "fr": ["France", "eu_west"],
	"de": ["Germany", "eu_west"], "nl": ["Netherlands", "eu_west"], "be": ["Belgium", "eu_west"],
	"es": ["Spain", "eu_west"], "pt": ["Portugal", "eu_west"], "it": ["Italy", "eu_west"],
	"se": ["Sweden", "eu_north"], "no": ["Norway", "eu_north"], "dk": ["Denmark", "eu_north"],
	"fi": ["Finland", "eu_north"], "ee": ["Estonia", "eu_north"], "pl": ["Poland", "eu_east"],
	"cz": ["Czechia", "eu_east"], "ua": ["Ukraine", "eu_east"], "ro": ["Romania", "eu_east"],
	"bg": ["Bulgaria", "eu_east"], "rs": ["Serbia", "eu_east"], "hu": ["Hungary", "eu_east"],
	"us": ["United States", "na"], "ca": ["Canada", "na"], "mx": ["Mexico", "na"],
	"br": ["Brazil", "sa"], "ar": ["Argentina", "sa"], "cl": ["Chile", "sa"],
	"jp": ["Japan", "apac"], "kr": ["South Korea", "apac"], "cn": ["China", "apac"],
	"mn": ["Mongolia", "apac"], "id": ["Indonesia", "apac"], "ph": ["Philippines", "apac"],
	"tr": ["Turkey", "mea"], "za": ["South Africa", "mea"], "il": ["Israel", "mea"],
	"eg": ["Egypt", "mea"], "au": ["Australia", "oce"], "nz": ["New Zealand", "oce"],
}

const TIER_NAMES: Dictionary[int, String] = {
	1: "Professional · Tier 1", 2: "Professional · Tier 2", 3: "Semi-pro · Tier 3", 4: "Amateur",
}

## Career difficulty: how the world perceives a new human professional at the start.
## [perceived ability mean, reputation, scouting confidence]
const DIFFICULTIES: Dictionary[StringName, Array] = {
	&"grind": [32, 2, 10],
	&"standard": [45, 8, 20],
	&"prospect": [60, 22, 35],
}
const DIFFICULTY_NAMES: Dictionary[StringName, String] = {
	&"grind": "Long amateur grind", &"standard": "Standard", &"prospect": "Hyped prospect",
}


static func ability_name(id: StringName) -> String:
	return ABILITY_NAMES.get(id, String(id).capitalize())


static func role_name(id: StringName) -> String:
	return ROLE_NAMES.get(id, String(id).capitalize())


static func nation_name(id: String) -> String:
	return str(NATIONS[id][0]) if NATIONS.has(id) else id.to_upper()


static func nation_region(id: String) -> String:
	return str(NATIONS[id][1]) if NATIONS.has(id) else ""


static func region_name(id: String) -> String:
	return REGIONS.get(id, id)


static func tier_name(tier: int) -> String:
	return TIER_NAMES.get(tier, "Unranked")


## Display label for a 0–100 reputation value.
static func reputation_label(value: int) -> String:
	if value >= 85:
		return "World-class star"
	if value >= 70:
		return "Established professional"
	if value >= 50:
		return "Known professional"
	if value >= 30:
		return "Rising name"
	if value >= 12:
		return "Known in amateur circles"
	return "Unknown amateur"
