class_name WorldGenerator
extends RefCounted
## Drafts a world database ([WorldDatabase]): organisations across regions and tiers, their
## rosters, free agents, ability/potential **ranges**, reputation ranges, traits and competitions.
## It is a content tool — the default database is drafted with it and then curated in the
## Database Editor; careers start from a database, never from the generator.
## Deterministic: the same seed and options produce the same database.

const GENERATOR_VERSION: int = 2

## Organisations per tier (1 = top) for the default world.
const DEFAULT_TIER_COUNTS: Dictionary[int, int] = {1: 6, 2: 10, 3: 12, 4: 12}
const DEFAULT_FREE_AGENTS: int = 80

## [ability mean, reputation min, reputation max, salary min, salary max]
const TIER_PROFILE: Dictionary[int, Array] = {
	1: [78, 66, 92, 9000, 22000],
	2: [70, 46, 70, 3500, 9000],
	3: [61, 24, 48, 900, 3500],
	4: [52, 8, 28, 0, 600],
	0: [46, 2, 20, 0, 0],  # free agents
}
## Probability of an organisation being based in each region.
const REGION_WEIGHTS: Dictionary[String, float] = {
	"eu_west": 0.2, "eu_north": 0.14, "eu_east": 0.16, "na": 0.16, "sa": 0.12, "apac": 0.12,
	"mea": 0.05, "oce": 0.05,
}
const ROSTER_ROLES: Array[StringName] = [&"igl", &"sniper", &"entry", &"rifler", &"support"]
const ROLE_TRAITS: Dictionary[StringName, Array] = {
	&"entry": [&"tr_aggressive", &"tr_risk_taker", &"tr_flick_specialist"],
	&"igl": [&"tr_tactician", &"tr_vocal", &"tr_calm"],
	&"lurker": [&"tr_lone_wolf", &"tr_passive", &"tr_clutch_player"],
	&"support": [&"tr_team_player", &"tr_utility_expert", &"tr_vocal"],
	&"sniper": [&"tr_passive", &"tr_calm", &"tr_clutch_player"],
	&"rifler": [&"tr_spray_master", &"tr_steady", &"tr_adaptable"],
}
## International events: [tier, kind, team count, start month].
const INTERNATIONAL_EVENTS: Array[Array] = [[1, "cup", 16, 3], [1, "cup", 8, 11], [2, "league", 16, 2]]

var world: WorldDatabase
var rng := RandomNumberGenerator.new()
var tier_counts: Dictionary[int, int] = DEFAULT_TIER_COUNTS.duplicate()
var free_agents: int = DEFAULT_FREE_AGENTS
var today: int = 0

var _used_nicknames: Dictionary[String, bool] = {}
var _used_org_names: Dictionary[String, bool] = {}
var _nations_by_region: Dictionary[String, Array] = {}
var _regions_used: Dictionary[String, bool] = {}


func _init(world_database: WorldDatabase, world_seed: int) -> void:
	world = world_database
	rng.seed = world_seed
	for nation_id: String in CareerCatalog.NATIONS:
		var region := CareerCatalog.nation_region(nation_id)
		if not _nations_by_region.has(region):
			_nations_by_region[region] = []
		_nations_by_region[region].append(nation_id)


## Creates a world database file at [param path] and fills it. Returns "" or an error.
static func build(path: String, world_seed: int, database_id: String, name: String, description: String,
		organisations_per_tier: Dictionary[int, int] = DEFAULT_TIER_COUNTS, free_agent_count: int = DEFAULT_FREE_AGENTS) -> String:
	var world_database := WorldDatabase.new()
	var error := world_database.create(path, database_id, name, "Frag to Fame world generator", description)
	if error.is_empty():
		var generator := WorldGenerator.new(world_database, world_seed)
		generator.tier_counts = organisations_per_tier.duplicate()
		generator.free_agents = free_agent_count
		error = generator.generate()
	world_database.close()
	return error


## Fills the (empty, open) world database. Returns "" on success or an error (nothing is
## written on failure).
func generate() -> String:
	var ok := world.transaction(func() -> bool:
		for tier: int in [1, 2, 3, 4]:
			for i: int in int(tier_counts.get(tier, 0)):
				if not _generate_organisation(tier):
					return false
		for i: int in free_agents:
			var region := _pick_region()
			if _generate_player(0, _random_role(), region).is_empty():
				return false
		if not _generate_competitions():
			return false
		return world.set_meta_value("generator_version", GENERATOR_VERSION))
	return "" if ok else "world generation failed: %s" % world.db.last_error


func _generate_organisation(tier: int) -> bool:
	var org := CareerRecords.OrganisationRecord.new()
	org.id = Ids.seeded("org", rng)
	org.name = _unique_org_name()
	org.short_name = _short_name(org.name)
	org.region_id = _pick_region()
	_regions_used[org.region_id] = true
	org.tier = tier
	org.founded_day = today - rng.randi_range(200, 3000)
	org.colour = Color.from_hsv(rng.randf(), rng.randf_range(0.45, 0.8), rng.randf_range(0.55, 0.9)).to_html(false)
	var profile: Array = TIER_PROFILE[tier]
	if not world.insert_organisation(org, _reputation_range(profile)):
		return false
	var roles := ROSTER_ROLES.duplicate()
	if rng.randf() < 0.35:
		roles[3] = &"lurker"
	var squad_size := 6 if tier <= 2 else 5
	for i: int in squad_size:
		var role: StringName = roles[i] if i < roles.size() else _random_role()
		var player_id := _generate_player(tier, role, org.region_id)
		if player_id.is_empty():
			return false
		var contract := CareerRecords.ContractRecord.new()
		contract.player_id = player_id
		contract.organisation_id = org.id
		contract.role = role
		contract.is_substitute = i >= 5
		contract.monthly_salary = rng.randi_range(int(profile[3]), int(profile[4]))
		contract.start_day = today - rng.randi_range(20, 700)
		contract.end_day = today + rng.randi_range(90, 900)
		if not world.add_to_roster(contract):
			return false
	return true


## Creates one AI professional. [param tier] 0 = free agent. Returns the player ID or "".
func _generate_player(tier: int, role: StringName, region: String) -> String:
	var nation_id := _pick_nation(region)
	var culture: String = NamePools.NATION_CULTURE.get(nation_id, "anglo")
	var player := CareerRecords.PlayerRecord.new()
	player.id = Ids.seeded("ply", rng)
	player.first_name = _pick(NamePools.FIRST_NAMES[culture])
	player.last_name = _pick(NamePools.LAST_NAMES[culture])
	player.nickname = _unique_nickname()
	player.nation_id = nation_id
	var age := rng.randi_range(16, 31)
	player.birth_day = today - age * GameDate.DAYS_PER_YEAR - rng.randi_range(0, GameDate.DAYS_PER_YEAR - 1)
	player.preferred_role = role
	var profile: Array = TIER_PROFILE[tier]
	var centre := _abilities(float(profile[0]), role, age)
	if not world.insert_player(player, _ranges(centre, age), _reputation_range(profile)):
		return ""
	_add_traits(player.id, role)
	return player.id


## Turns centre values into ranges. Young players are less known (wider ranges) and have more
## room to grow (higher, wider potential).
func _ranges(centre: Dictionary, age: int) -> Dictionary[StringName, Vector2i]:
	var result: Dictionary[StringName, Vector2i] = {}
	var extra := 2 if age <= 20 else 0
	for ability: Variant in centre:
		var value := int(centre[ability])
		var half := rng.randi_range(2, 5) + extra
		result[StringName(str(ability))] = Vector2i(clampi(value - half, 1, 99), clampi(value + half, 1, 99))
	var average := _average(centre)
	var low := average
	var high := average
	if age <= 21:
		low += rng.randi_range(0, 6)
		high += rng.randi_range(12, 28)
	elif age <= 26:
		high += rng.randi_range(4, 12)
	else:
		low -= 2
		high += rng.randi_range(1, 5)
	result[CareerCatalog.POTENTIAL] = Vector2i(clampi(low, 1, 99), clampi(maxi(high, low), 1, 100))
	return result


func _reputation_range(profile: Array) -> Vector2i:
	var centre := rng.randi_range(int(profile[1]), int(profile[2]))
	var half := rng.randi_range(3, 8)
	return Vector2i(clampi(centre - half, 0, 100), clampi(centre + half, 0, 100))


## Competition definitions: international events for the top tiers, a league and an open cup
## for every region that has organisations. Scheduling and play arrive with Milestone 13.
func _generate_competitions() -> bool:
	var words: Array[String] = NamePools.COMPETITION_WORDS.duplicate()
	for event: Array in INTERNATIONAL_EVENTS:
		var word: String = words.pop_at(rng.randi() % words.size())
		var kind := str(event[1])
		var suffix := "Pro Series" if kind == "league" else _pick(NamePools.EVENT_SUFFIXES)
		if not _add_competition("%s %s" % [word, suffix], kind, "", int(event[0]), int(event[2]), int(event[3])):
			return false
	for region_id: String in CareerCatalog.REGIONS:
		if not _regions_used.has(region_id):
			continue
		var region_name := CareerCatalog.region_name(region_id)
		if not _add_competition("%s Challenger League" % region_name, "league", region_id, 3, 8, 1):
			return false
		if not _add_competition("%s Open" % region_name, "cup", region_id, 4, 16, 6):
			return false
	return true


func _add_competition(name: String, kind: String, region_id: String, tier: int, teams: int, month: int) -> bool:
	var competition := CareerRecords.CompetitionRecord.new()
	competition.id = Ids.seeded("cmp", rng)
	competition.name = name
	competition.short_name = _short_name(name)
	competition.kind = kind
	competition.region_id = region_id
	competition.tier = tier
	competition.team_count = teams
	competition.start_month = month
	return world.insert_competition(competition)


func _abilities(mean: float, role: StringName, age: int) -> Dictionary:
	var values: Dictionary = {}
	var focus: Array = CareerCatalog.ROLE_FOCUS.get(role, [])
	var talent := rng.randfn(0.0, 4.0)
	var age_shift := -4.0 if age <= 18 else (2.0 if age >= 23 and age <= 28 else 0.0)
	for ability: StringName in CareerCatalog.ABILITIES:
		var value := mean + talent + age_shift + rng.randfn(0.0, 6.5)
		if focus.has(ability):
			value += 6.0
		if ability == &"leadership" and role != &"igl":
			value -= 4.0
		values[ability] = clampi(roundi(value), 1, 99)
	return values


func _add_traits(player_id: String, role: StringName) -> void:
	var count := rng.randi_range(2, 4)
	var leaning: Array = ROLE_TRAITS.get(role, [])
	var all := TraitLibrary.ids()
	var attempts := 0
	while world.traits(player_id).size() < count and attempts < 20:
		attempts += 1
		var candidate: StringName = leaning[rng.randi() % leaning.size()] if rng.randf() < 0.45 and not leaning.is_empty() \
			else all[rng.randi() % all.size()]
		world.add_trait(player_id, candidate, rng.randi_range(1, 3))


func _unique_nickname() -> String:
	for attempt: int in 40:
		var base := _pick(NamePools.NICKNAMES)
		var nickname := base if attempt < 20 else base + _pick(NamePools.NICKNAME_SUFFIXES)
		if not _used_nicknames.has(nickname.to_lower()):
			_used_nicknames[nickname.to_lower()] = true
			return nickname
	var fallback := "%s%d" % [_pick(NamePools.NICKNAMES), _used_nicknames.size()]
	_used_nicknames[fallback.to_lower()] = true
	return fallback


func _unique_org_name() -> String:
	for attempt: int in 60:
		var core := "%s %s" % [_pick(NamePools.ORG_PLACES), _pick(NamePools.ORG_NOUNS)]
		var name := _pick(NamePools.ORG_STYLES) % core
		if not _used_org_names.has(core):
			_used_org_names[core] = true
			return name
	return "Organisation %d" % (_used_org_names.size() + 1)


static func _short_name(name: String) -> String:
	var letters := ""
	for word: String in name.replace("Team ", "").replace(" Esports", "").replace(" Gaming", "").split(" "):
		if not word.is_empty():
			letters += word.substr(0, 1).to_upper()
	return letters.substr(0, 4)


func _pick_region() -> String:
	var roll := rng.randf()
	for region: String in REGION_WEIGHTS:
		roll -= REGION_WEIGHTS[region]
		if roll <= 0.0:
			return region
	return "eu_west"


func _pick_nation(region: String) -> String:
	var nations: Array = _nations_by_region.get(region, ["gb"])
	# Some players move abroad: 12% come from any nation.
	if rng.randf() < 0.12:
		var all := CareerCatalog.NATIONS.keys()
		return str(all[rng.randi() % all.size()])
	return str(nations[rng.randi() % nations.size()])


func _random_role() -> StringName:
	return CareerCatalog.ROLES[rng.randi() % CareerCatalog.ROLES.size()]


func _pick(list: Array) -> String:
	return str(list[rng.randi() % list.size()])


static func _average(values: Dictionary) -> int:
	if values.is_empty():
		return 0
	var total := 0
	for v: Variant in values.values():
		total += int(v)
	return roundi(float(total) / values.size())
