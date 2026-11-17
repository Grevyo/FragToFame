class_name WorldRookies
extends RefCounted
## New original players entering the scene each year as unsigned 16–18 year olds, so the world
## keeps its size as veterans retire. Names come from the same original pools as the world
## generator. Rookies are raw (lower abilities) with room to grow (hidden potential), and the
## world knows little about them yet (low scouting confidence).

const MIN_AGE: int = 16
const MAX_AGE: int = 18
## Mean ability of a rookie class, and how widely individual talent varies around it.
const ABILITY_MEAN: float = 44.0
const TALENT_SPREAD: float = 5.0
const ABILITY_SPREAD: float = 6.0
const FOCUS_BONUS: float = 6.0
## Hidden potential above the rookie's current overall.
const POTENTIAL_HEADROOM: Vector2i = Vector2i(8, 34)
const POTENTIAL_CAP: int = 95
const CONFIDENCE: int = 22
const REPUTATION: Vector2i = Vector2i(1, 8)


## Creates [param count] rookies dated [param day]. Appends their ids to [param created].
## Returns false if a write failed.
static func generate(repo: CareerRepository, count: int, day: int, rng: RandomNumberGenerator,
		created: Array[String]) -> bool:
	var nations_by_region: Dictionary[String, Array] = {}
	for nation_id: String in CareerCatalog.NATIONS:
		var region := CareerCatalog.nation_region(nation_id)
		if not nations_by_region.has(region):
			nations_by_region[region] = []
		nations_by_region[region].append(nation_id)
	for i: int in count:
		var id := _rookie(repo, day, rng, nations_by_region)
		if id.is_empty():
			return false
		created.append(id)
	return true


## Fresh abilities for a rookie of [param role]: {ability: value} plus potential.
static func roll_abilities(rng: RandomNumberGenerator, role: StringName) -> Dictionary:
	var truth: Dictionary = {}
	var focus: Array = CareerCatalog.ROLE_FOCUS.get(role, [])
	var talent := rng.randfn(0.0, TALENT_SPREAD)
	for ability: StringName in CareerCatalog.ABILITIES:
		var value := ABILITY_MEAN + talent + rng.randfn(0.0, ABILITY_SPREAD)
		if focus.has(ability):
			value += FOCUS_BONUS
		if ability == &"leadership" and role != &"igl":
			value -= 4.0
		truth[ability] = clampi(roundi(value), 1, 99)
	var current := WorldDevelopment.overall(truth)
	truth[CareerCatalog.POTENTIAL] = clampi(current + rng.randi_range(POTENTIAL_HEADROOM.x, POTENTIAL_HEADROOM.y),
		current, POTENTIAL_CAP)
	return truth


static func _rookie(repo: CareerRepository, day: int, rng: RandomNumberGenerator,
		nations_by_region: Dictionary[String, Array]) -> String:
	var region := _pick_region(rng)
	var nations: Array = nations_by_region.get(region, ["gb"])
	var nation_id := str(nations[rng.randi() % nations.size()])
	var culture: String = NamePools.NATION_CULTURE.get(nation_id, "anglo")
	var role := CareerCatalog.ROLES[rng.randi() % CareerCatalog.ROLES.size()]
	var player := CareerRecords.PlayerRecord.new()
	player.id = Ids.seeded("ply", rng)
	player.first_name = _pick(rng, NamePools.FIRST_NAMES[culture])
	player.last_name = _pick(rng, NamePools.LAST_NAMES[culture])
	player.nickname = _nickname(repo, rng)
	player.nation_id = nation_id
	player.birth_day = day - rng.randi_range(MIN_AGE, MAX_AGE) * GameDate.DAYS_PER_YEAR - rng.randi_range(0, GameDate.DAYS_PER_YEAR - 1)
	player.preferred_role = role
	player.created_day = day
	if not repo.insert_player(player):
		return ""
	var truth := roll_abilities(rng, role)
	var seen: Dictionary = truth.duplicate()
	seen.erase(CareerCatalog.POTENTIAL)
	if not repo.set_abilities(player.id, truth) \
			or not repo.set_perceived(player.id, CareerStart.perceive(rng, seen, CONFIDENCE), CONFIDENCE, day) \
			or not repo.set_reputation(player.id, rng.randi_range(REPUTATION.x, REPUTATION.y), day):
		return ""
	var leaning: Array = WorldGenerator.ROLE_TRAITS.get(role, [])
	var all := TraitLibrary.ids()
	for attempt: int in rng.randi_range(1, 3):
		var candidate: StringName = leaning[rng.randi() % leaning.size()] if rng.randf() < 0.45 and not leaning.is_empty() \
			else all[rng.randi() % all.size()]
		repo.add_trait(player.id, candidate, rng.randi_range(1, 2))
	return player.id


static func _nickname(repo: CareerRepository, rng: RandomNumberGenerator) -> String:
	for attempt: int in 40:
		var base := _pick(rng, NamePools.NICKNAMES)
		var nickname := base if attempt < 15 else base + _pick(rng, NamePools.NICKNAME_SUFFIXES)
		if not repo.nickname_taken(nickname):
			return nickname
	return "%s%d" % [_pick(rng, NamePools.NICKNAMES), rng.randi_range(10, 999)]


static func _pick_region(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	for region: String in WorldGenerator.REGION_WEIGHTS:
		roll -= WorldGenerator.REGION_WEIGHTS[region]
		if roll <= 0.0:
			return region
	return "eu_west"


static func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return str(list[rng.randi() % list.size()])
