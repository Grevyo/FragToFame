class_name CareerStart
extends RefCounted
## Copies the fixed world database's organisations, professionals, rosters and competitions into
## an independent career save. Where the database specifies ranges, sample initial values within
## those authored bounds and derive starting scouting opinions.

## Scouting confidence the world starts with, by organisation tier (0 = free agent).
const TIER_CONFIDENCE: Dictionary[int, int] = {1: 82, 2: 66, 3: 46, 4: 30, 0: 22}


## Fills [param repo] (open, empty, migrated) from [param world]. Returns "" or an error; nothing
## is written on failure.
static func populate(repo: CareerRepository, world: WorldDatabase) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var today := repo.current_day()
	var ranges_by_player: Dictionary[String, Dictionary] = {}
	for found: Dictionary in world.range_rows():
		var player_id := str(found["player_id"])
		if not ranges_by_player.has(player_id):
			ranges_by_player[player_id] = {}
		ranges_by_player[player_id][StringName(str(found["ability"]))] = Vector2i(int(found["min_value"]), int(found["max_value"]))
	var traits_by_player: Dictionary[String, Array] = {}
	for found: Dictionary in world.trait_rows():
		var player_id := str(found["player_id"])
		if not traits_by_player.has(player_id):
			traits_by_player[player_id] = []
		traits_by_player[player_id].append(found)
	var org_tier: Dictionary[String, int] = {}
	var organisations := world.organisation_rows()
	for found: Dictionary in organisations:
		org_tier[str(found["id"])] = int(found["tier"])
	var rosters := world.roster_rows()
	var player_tier: Dictionary[String, int] = {}
	for found: Dictionary in rosters:
		player_tier[str(found["player_id"])] = org_tier.get(str(found["organisation_id"]), 4)
	var players := world.player_rows()
	var competitions := world.competition_rows()

	var ok := repo.transaction(func() -> bool:
		if not repo.seed_reference_data():
			return false
		for found: Dictionary in organisations:
			var org := CareerRecords.OrganisationRecord.from_row(found.merged({"active": 1}))
			if not repo.insert_organisation(org):
				return false
			repo.set_organisation_reputation(org.id, _roll(rng, _span(found)), today)
		for found: Dictionary in players:
			var id := str(found["id"])
			if not _add_player(repo, rng, found, ranges_by_player.get(id, {}), traits_by_player.get(id, []),
					TIER_CONFIDENCE[player_tier.get(id, 0)], today):
				return false
		for found: Dictionary in rosters:
			var contract := CareerRecords.ContractRecord.new()
			contract.id = Ids.seeded("con", rng)
			contract.player_id = str(found["player_id"])
			contract.organisation_id = str(found["organisation_id"])
			contract.role = StringName(str(found["role"]))
			contract.is_substitute = int(found["is_substitute"]) == 1
			contract.monthly_salary = int(found["monthly_salary"])
			contract.start_day = int(found["start_day"])
			contract.end_day = int(found["end_day"])
			if not repo.sign_contract(contract):
				return false
		for found: Dictionary in competitions:
			if not repo.insert_competition(CareerRecords.CompetitionRecord.from_row(found)):
				return false
		return repo.set_meta_value("database_id", world.database_id()) \
			and repo.set_meta_value("database_name", world.display_name()))
	return "" if ok else "could not start the career from '%s': %s" % [world.display_name(), repo.db.last_error]


static func _add_player(repo: CareerRepository, rng: RandomNumberGenerator, found: Dictionary,
		ranges: Dictionary, trait_rows: Array, confidence: int, today: int) -> bool:
	var player := CareerRecords.PlayerRecord.from_row(found.merged({"is_human": 0, "status": "active", "created_day": today}))
	if not repo.insert_player(player):
		return false
	var truth: Dictionary = {}
	var total := 0
	var potential: Vector2i = ranges[CareerCatalog.POTENTIAL]
	for ability: StringName in CareerCatalog.ABILITIES:
		var value := _roll(rng, ranges[ability])
		truth[ability] = value
		total += value
	# Fit current ability under the authored potential ceiling without leaving any range.
	var excess := maxi(0, total - potential.y * CareerCatalog.ABILITIES.size())
	for ability: StringName in CareerCatalog.ABILITIES:
		var span: Vector2i = ranges[ability]
		var reduction := mini(excess, int(truth[ability]) - span.x)
		truth[ability] = int(truth[ability]) - reduction
		excess -= reduction
	var stored: Dictionary = truth.duplicate()
	stored[CareerCatalog.POTENTIAL] = maxi(_roll(rng, potential),
		roundi(float(mini(total, potential.y * CareerCatalog.ABILITIES.size())) / CareerCatalog.ABILITIES.size()))
	if not repo.set_abilities(player.id, stored):
		return false
	var player_confidence := clampi(confidence + rng.randi_range(-8, 8), 5, 95)
	if not repo.set_perceived(player.id, perceive(rng, truth, player_confidence), player_confidence, today):
		return false
	if not repo.set_reputation(player.id, _roll(rng, _span(found)), today):
		return false
	for trait_row: Dictionary in trait_rows:
		repo.add_trait(player.id, StringName(str(trait_row["trait_id"])), int(trait_row["strength"]))
	return true


## Perceived values: the truth seen through scouting noise (less confident → noisier).
static func perceive(rng: RandomNumberGenerator, truth: Dictionary, confidence: int) -> Dictionary:
	var spread := (100.0 - confidence) / 8.0
	var seen: Dictionary = {}
	for ability: Variant in truth:
		seen[ability] = clampi(roundi(float(truth[ability]) + rng.randfn(0.0, spread)), 1, 99)
	return seen


## A value inside [param span] (min, max), leaning towards the middle (mean of two rolls).
static func _roll(rng: RandomNumberGenerator, span: Vector2i) -> int:
	return roundi((rng.randi_range(span.x, span.y) + rng.randi_range(span.x, span.y)) / 2.0)


static func _span(found: Dictionary) -> Vector2i:
	return Vector2i(int(found["reputation_min"]), int(found["reputation_max"]))
