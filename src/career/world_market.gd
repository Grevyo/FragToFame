class_name WorldMarket
extends RefCounted
## The AI side of the player market, run every day: contracts that reach their end are renewed
## or let go, and organisations short of five starters promote a substitute or sign the best
## fitting free agent. Once a week all year round organisations may also upgrade their weakest
## starter, buying a better player from another organisation or signing a better free agent and
## benching (or releasing) the starter. Most moves happen in the January and July windows; an
## organisation in poor form acts more readily at any time. Organisations judge players by perceived values (what the world believes),
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
## The market runs every 7th day of the year. The windows (months, 0 = January) are its busiest
## time, but it never closes.
const WINDOW_MONTHS: Array[int] = [0, 6]
const WINDOW_DAY_STEP: int = 7
## Weekly chance an organisation tries to upgrade: in a window, outside one, and the extra for an
## organisation whose form is this poor (struggling teams shake things up mid-season).
const BUY_CHANCE: float = 0.3
const OFF_WINDOW_CHANCE: float = 0.015
const STRUGGLING_FORM: int = -30
const STRUGGLING_BONUS: float = 0.1
const STRUGGLING_OFF_WINDOW_BONUS: float = 0.06
## How much better (perceived) a signing must be than the starter it replaces.
const UPGRADE_MARGIN: int = 4
## Players are not moved again this soon after signing, nor past this age.
const SETTLE_DAYS: int = 120
const MAX_TRANSFER_AGE: int = 31
## Selling: base willingness, raised when the contract is nearly over, lowered for a key player.
const SELL_BASE: float = 0.55
const SELL_EXPIRING: float = 0.3
const EXPIRING_DAYS: int = 180
const SELL_BEST_PLAYER: float = 0.3
## A buyer with more than this many players releases the displaced starter instead of benching.
const MAX_SQUAD: int = 7
## Money trouble: organisations in debt renew less and sell more readily.
const DEBT_RENEWAL_PENALTY: float = 0.2
const DEBT_SELL_BONUS: float = 0.3


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
		var person := repo.person(player_id)
		var chance := renewal_chance(age, rating, tier, substitute) + CareerPeople.renewal_modifier(person)
		if repo.organisation_balance(org_id) < 0:
			chance -= DEBT_RENEWAL_PENALTY
		if rng.randf() < chance:
			var years := rng.randi_range(MIN_YEARS, MAX_YEARS)
			if not _sign(repo, rng, player_id, org_id, StringName(str(found["role"])), substitute, tier, rating, day, years):
				return false
			if tier <= 2 and not repo.add_news(day, WorldSimulation.NEWS_CONTRACT, WorldSimulation.MINOR,
					"%s extends with %s until %s." % [nickname, org_name, GameDate.format_year(day + years * GameDate.DAYS_PER_YEAR)],
					player_id, org_id):
				return false
		elif not repo.add_news(day, WorldSimulation.NEWS_RELEASE, WorldSimulation.NOTABLE if tier <= 2 else WorldSimulation.MINOR,
				("%s turns down a new deal and leaves %s as a free agent." if int(person.get("wants_move", 0)) == 1
					else "%s leaves %s and becomes a free agent.") % [nickname, org_name], player_id, org_id):
			return false
		elif not person.is_empty() and not repo.set_person_mood(player_id, int(person["happiness"]), false, "a fresh start", day):
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


## True on the weekly market days (all year).
static func is_market_day(day: int) -> bool:
	return day > 0 and GameDate.day_of_year(day) % WINDOW_DAY_STEP == 0


## True on market days inside the January and July windows.
static func in_window(day: int) -> bool:
	return is_market_day(day) and WINDOW_MONTHS.has(GameDate.month_and_day(day).x)


## Weekly chance an organisation tries to strengthen its five.
static func buy_chance(window: bool, form: int) -> float:
	var chance := BUY_CHANCE if window else OFF_WINDOW_CHANCE
	if form <= STRUGGLING_FORM:
		chance += STRUGGLING_BONUS if window else STRUGGLING_OFF_WINDOW_BONUS
	return clampf(chance, 0.0, 0.9)


## A player wants the move when it is a step up: a better tier, or the same tier with more
## reputation.
static func wants_move(from_tier: int, from_reputation: int, to_tier: int, to_reputation: int) -> bool:
	return to_tier < from_tier or (to_tier == from_tier and to_reputation > from_reputation)


## Chance the current organisation lets the player go.
static func sell_chance(days_left: int, is_best: bool) -> float:
	var chance := SELL_BASE
	if days_left <= EXPIRING_DAYS:
		chance += SELL_EXPIRING
	if is_best:
		chance -= SELL_BEST_PLAYER
	return clampf(chance, 0.05, 0.95)


## Index of the best upgrade in [param pool] for a buyer replacing a starter rated
## [param weakest] in [param role], or -1. Candidates must clear [constant UPGRADE_MARGIN] and
## want the move.
static func upgrade_target(pool: Array[Dictionary], buyer_id: String, buyer_tier: int, buyer_reputation: int,
		weakest: int, role: StringName, region: String) -> int:
	var best := -1
	var best_score := -INF
	for i: int in pool.size():
		var candidate := pool[i]
		var rating := int(candidate["rating"])
		if str(candidate["organisation_id"]) == buyer_id or rating < weakest + UPGRADE_MARGIN:
			continue
		if not wants_move(int(candidate["tier"]), int(candidate["org_reputation"]), buyer_tier, buyer_reputation):
			continue
		var score := float(rating)
		if StringName(str(candidate["preferred_role"])) == role:
			score += ROLE_FIT_BONUS
		if str(candidate["region_id"]) == region:
			score += SAME_REGION_BONUS
		if score > best_score:
			best_score = score
			best = i
	return best


## Weekly market (all year, busiest in the windows): organisations, best tier first, try to
## replace their weakest AI starter. First choice is a better player from another organisation
## for a fee they can afford ([WorldFinance]); otherwise a better free agent.
static func transfers(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	if not is_market_day(day):
		return true
	var window := in_window(day)
	var pool: Array[Dictionary] = []
	for found: Dictionary in repo.transfer_pool(day - SETTLE_DAYS):
		if GameDate.age(int(found["birth_day"]), day) <= MAX_TRANSFER_AGE:
			pool.append(found)
	var best_by_org: Dictionary[String, String] = {}
	for found: Dictionary in pool:
		var org_id := str(found["organisation_id"])
		if not best_by_org.has(org_id):
			best_by_org[org_id] = str(found["player_id"])  # pool is sorted best first
	var free_agents := repo.free_agent_pool()
	for entry: Dictionary in repo.organisations():
		var buyer := entry["organisation"] as CareerRecords.OrganisationRecord
		if rng.randf() >= buy_chance(window, repo.organisation_form(buyer.id)):
			continue
		var roster := repo.roster(buyer.id)
		var weakest: Dictionary = {}
		for member: Dictionary in roster:
			var contract := member["contract"] as CareerRecords.ContractRecord
			if not contract.is_substitute and not (member["player"] as CareerRecords.PlayerRecord).is_human:
				weakest = member
		if weakest.is_empty():
			continue
		var weak_contract := weakest["contract"] as CareerRecords.ContractRecord
		var funds := repo.organisation_balance(buyer.id)
		var pick := upgrade_target(pool, buyer.id, buyer.tier, int(entry["reputation"]), int(weakest["rating"]),
			weak_contract.role, buyer.region_id) if funds > 0 else -1
		if pick >= 0:
			var target := pool[pick]
			var seller_id := str(target["organisation_id"])
			var days_left := int(target["end_day"]) - day
			var fee := WorldFinance.transfer_fee(int(target["rating"]), GameDate.age(int(target["birth_day"]), day), days_left)
			var is_best: bool = str(best_by_org.get(seller_id, "")) == str(target["player_id"])
			var person := repo.person(str(target["player_id"]))
			var willing := sell_chance(days_left, is_best) + (DEBT_SELL_BONUS if repo.organisation_balance(seller_id) < 0 else 0.0) \
				+ CareerPeople.sell_modifier(person)
			if WorldFinance.can_afford(funds, fee, salary_for(buyer.tier, int(target["rating"]))) and rng.randf() < willing:
				if not CareerPeople.accepts_move(person, int(target["tier"]), buyer.tier, rng):
					pool.remove_at(pick)
					if int(target["tier"]) <= 2 and not repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.MINOR,
							"%s turns down a move to %s to stay at %s." % [target["nickname"], buyer.name, target["org_name"]],
							str(target["player_id"]), seller_id):
						return false
					continue
				pool.remove_at(pick)
				if not _transfer(repo, rng, target, buyer, weakest, roster.size(), fee, day):
					return false
				continue
		var free_pick := free_agent_upgrade(free_agents, int(weakest["rating"]), weak_contract.role, buyer.region_id)
		if free_pick < 0:
			continue
		var signing := free_agents[free_pick]
		free_agents.remove_at(free_pick)
		if not _make_room(repo, buyer, weakest, roster.size(), day) or not _sign(repo, rng, str(signing["id"]), buyer.id,
				weak_contract.role, false, buyer.tier, int(signing["rating"]), day, rng.randi_range(MIN_YEARS, MAX_YEARS - 1)):
			return false
		if not repo.add_news(day, WorldSimulation.NEWS_SIGNING, WorldSimulation.NOTABLE if buyer.tier <= 2 else WorldSimulation.MINOR,
				"%s sign free agent %s, and %s loses their place." % [buyer.name, signing["nickname"],
				(weakest["player"] as CareerRecords.PlayerRecord).nickname], str(signing["id"]), buyer.id):
			return false
	return true


## Index of the best free agent clearly better than a starter rated [param weakest], or -1.
static func free_agent_upgrade(pool: Array[Dictionary], weakest: int, role: StringName, region: String) -> int:
	var eligible: Array[Dictionary] = pool.filter(func(c: Dictionary) -> bool: return int(c["rating"]) >= weakest + UPGRADE_MARGIN)
	var pick := best_candidate(eligible, role, region)
	return pool.find(eligible[pick]) if pick >= 0 else -1


## The displaced starter goes to the bench, or is released when the squad is already full.
static func _make_room(repo: CareerRepository, buyer: CareerRecords.OrganisationRecord, weakest: Dictionary,
		squad_size: int, day: int) -> bool:
	var weak_contract := weakest["contract"] as CareerRecords.ContractRecord
	var weak_player := weakest["player"] as CareerRecords.PlayerRecord
	if squad_size < MAX_SQUAD:
		return repo.set_contract_substitute(weak_contract.id, true)
	return repo.end_contract(weak_contract.id, "terminated", day) and repo.add_news(day, WorldSimulation.NEWS_RELEASE,
		WorldSimulation.MINOR, "%s release %s to make room." % [buyer.name, weak_player.nickname], weak_player.id, buyer.id)


static func _transfer(repo: CareerRepository, rng: RandomNumberGenerator, target: Dictionary,
		buyer: CareerRecords.OrganisationRecord, weakest: Dictionary, squad_size: int, fee: int, day: int) -> bool:
	var weak_contract := weakest["contract"] as CareerRecords.ContractRecord
	var player_id := str(target["player_id"])
	if not repo.end_contract(str(target["contract_id"]), "terminated", day) \
			or not WorldFinance.pay_fee(repo, buyer.id, str(target["organisation_id"]), fee, str(target["nickname"]), day) \
			or not _make_room(repo, buyer, weakest, squad_size, day):
		return false
	if not _sign(repo, rng, player_id, buyer.id, weak_contract.role, false, buyer.tier, int(target["rating"]), day,
			rng.randi_range(MIN_YEARS + 1, MAX_YEARS)):
		return false
	if not repo.add_news(day, WorldSimulation.NEWS_TRANSFER, WorldSimulation.NOTABLE if buyer.tier <= 2 else WorldSimulation.MINOR,
			"%s joins %s from %s for %s." % [target["nickname"], buyer.name, target["org_name"], CareerCatalog.format_money(fee)],
			player_id, buyer.id):
		return false
	var person := repo.person(player_id)
	if not person.is_empty() and not repo.set_person_mood(player_id, maxi(int(person["happiness"]), 10), false, "excited by the move", day):
		return false
	if buyer.tier > CareerPeople.NEWS_TIERS:
		return true
	return CareerPeople.interview(repo, player_id, str(target["organisation_id"]), "new_club", buyer.name, WorldSimulation.MINOR, day, rng)


static func _sign(repo: CareerRepository, rng: RandomNumberGenerator, player_id: String, org_id: String,
		role: StringName, substitute: bool, tier: int, rating: int, day: int, years: int) -> bool:
	var contract := CareerRecords.ContractRecord.new()
	contract.id = Ids.seeded("con", rng)
	contract.player_id = player_id
	contract.organisation_id = org_id
	contract.role = role
	contract.is_substitute = substitute
	contract.monthly_salary = WorldFinance.affordable_salary(repo.organisation_balance(org_id), salary_for(tier, rating), tier)
	contract.start_day = day
	contract.end_day = day + years * GameDate.DAYS_PER_YEAR
	return repo.sign_contract(contract)
