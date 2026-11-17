class_name WorldMarket
extends RefCounted
## The AI side of the player market, run every day: contracts that reach their end are renewed
## or let go, and organisations short of five starters promote a substitute or sign the best
## fitting free agent. Organisations judge players by perceived values (what the world believes),
## never by the hidden truth. The human's own contract simply expires; offers to humans are the
## human path to pro, built separately.

## Daily chance that an organisation short of starters completes a signing (signings take days).
const SIGNING_CHANCE: float = 0.35
## Renewal chances before age and form adjustments.
const RENEW_STARTER: float = 0.8
const RENEW_SUBSTITUTE: float = 0.45
## A player this far below the tier's typical ability is rarely kept.
const UNDERPERFORMING_GAP: int = 8
## Candidate scoring: perceived rating plus these bonuses.
const ROLE_FIT_BONUS: float = 4.0
const SAME_REGION_BONUS: float = 3.0
## Contract lengths (years) for new signings and renewals.
const MIN_YEARS: int = 1
const MAX_YEARS: int = 3


## Chance an organisation renews an expiring contract.
static func renewal_chance(age: int, rating: int, tier: int, is_substitute: bool) -> float:
	var chance := RENEW_SUBSTITUTE if is_substitute else RENEW_STARTER
	if age >= 31:
		chance -= 0.25
	if age >= 34:
		chance -= 0.3
	var typical: int = WorldGenerator.TIER_PROFILE.get(tier, WorldGenerator.TIER_PROFILE[4])[0]
	if typical - rating > UNDERPERFORMING_GAP:
		chance -= 0.3
	return clampf(chance, 0.0, 0.95)


## Monthly salary an organisation of [param tier] offers a player rated [param rating].
static func salary_for(tier: int, rating: int) -> int:
	var profile: Array = WorldGenerator.TIER_PROFILE.get(tier, WorldGenerator.TIER_PROFILE[4])
	var t := clampf((rating - (int(profile[0]) - 10)) / 20.0, 0.0, 1.0)
	return roundi(lerpf(float(profile[3]), float(profile[4]), t) / 50.0) * 50


## The role an organisation needs most: the first standard roster role nobody covers.
static func needed_role(covered: Array[StringName]) -> StringName:
	for role: StringName in WorldGenerator.ROSTER_ROLES:
		if not covered.has(role):
			return role
	return &"rifler"


## Index of the best free agent for an organisation, or -1 when the pool is empty.
static func best_candidate(pool: Array[Dictionary], role: StringName, region: String) -> int:
	var best := -1
	var best_score := -INF
	for i: int in pool.size():
		var candidate := pool[i]
		var score := float(candidate["rating"])
		if StringName(str(candidate["preferred_role"])) == role:
			score += ROLE_FIT_BONUS
		if str(candidate["region_id"]) == region:
			score += SAME_REGION_BONUS
		if score > best_score:
			best_score = score
			best = i
	return best


## Renews or releases every contract ending on [param day].
static func process_contracts(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	for found: Dictionary in repo.contracts_ending(day):
		var contract_id := str(found["id"])
		var player_id := str(found["player_id"])
		var org_id := str(found["organisation_id"])
		var org_name := str(found["org_name"])
		var nickname := str(found["nickname"])
		var tier := int(found["tier"])
		if int(found["is_human"]) == 1:
			if not repo.end_contract(contract_id, "expired", day) or not repo.add_news(day, WorldSimulation.NEWS_CONTRACT,
					WorldSimulation.HEADLINE, "Your contract with %s has expired. You are a free agent." % org_name,
					player_id, org_id):
				return false
			continue
		var rating := repo.perceived_rating(player_id)
		var age := GameDate.age(int(found["birth_day"]), day)
		var substitute := int(found["is_substitute"]) == 1
		if not repo.end_contract(contract_id, "expired", day):
			return false
		if rng.randf() < renewal_chance(age, rating, tier, substitute):
			var years := rng.randi_range(MIN_YEARS, MAX_YEARS)
			if not _sign(repo, rng, player_id, org_id, StringName(str(found["role"])), substitute, tier, rating, day, years):
				return false
			if tier <= 2 and not repo.add_news(day, WorldSimulation.NEWS_CONTRACT, WorldSimulation.MINOR,
					"%s extends with %s until %s." % [nickname, org_name, GameDate.format_year(day + years * GameDate.DAYS_PER_YEAR)],
					player_id, org_id):
				return false
		elif not repo.add_news(day, WorldSimulation.NEWS_RELEASE, WorldSimulation.NOTABLE if tier <= 2 else WorldSimulation.MINOR,
				"%s leaves %s and becomes a free agent." % [nickname, org_name], player_id, org_id):
			return false
	return true


## Organisations short of starters promote a substitute or sign a free agent.
static func fill_rosters(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	var pool := repo.free_agent_pool()
	for org: Dictionary in repo.organisations_short_of_starters():
		if rng.randf() >= SIGNING_CHANCE:
			continue
		var org_id := str(org["id"])
		var tier := int(org["tier"])
		var covered: Array[StringName] = []
		var substitute: Dictionary = {}
		for entry: Dictionary in repo.roster(org_id):
			var contract := entry["contract"] as CareerRecords.ContractRecord
			if contract.is_substitute:
				if substitute.is_empty():
					substitute = entry
			else:
				covered.append(contract.role)
		if not substitute.is_empty():
			var promoted := substitute["contract"] as CareerRecords.ContractRecord
			var promoted_player := substitute["player"] as CareerRecords.PlayerRecord
			if not repo.set_contract_substitute(promoted.id, false) or not repo.add_news(day, WorldSimulation.NEWS_SIGNING,
					WorldSimulation.MINOR, "%s promotes %s into the starting five." % [org["name"], promoted_player.nickname],
					promoted_player.id, org_id):
				return false
			continue
		var pick := best_candidate(pool, needed_role(covered), str(org["region_id"]))
		if pick < 0:
			continue
		var candidate := pool[pick]
		pool.remove_at(pick)
		var role := needed_role(covered)
		var rating := int(candidate["rating"])
		if not _sign(repo, rng, str(candidate["id"]), org_id, role, false, tier, rating, day,
				rng.randi_range(MIN_YEARS, MAX_YEARS - 1)):
			return false
		if not repo.add_news(day, WorldSimulation.NEWS_SIGNING, WorldSimulation.NOTABLE if tier <= 2 else WorldSimulation.MINOR,
				"%s signs %s as their %s." % [org["name"], candidate["nickname"], CareerCatalog.ROLE_NAMES.get(role, String(role)).to_lower()],
				str(candidate["id"]), org_id):
			return false
	return true


static func _sign(repo: CareerRepository, rng: RandomNumberGenerator, player_id: String, org_id: String,
		role: StringName, substitute: bool, tier: int, rating: int, day: int, years: int) -> bool:
	var contract := CareerRecords.ContractRecord.new()
	contract.id = Ids.seeded("con", rng)
	contract.player_id = player_id
	contract.organisation_id = org_id
	contract.role = role
	contract.is_substitute = substitute
	contract.monthly_salary = salary_for(tier, rating)
	contract.start_day = day
	contract.end_day = day + years * GameDate.DAYS_PER_YEAR
	return repo.sign_contract(contract)
