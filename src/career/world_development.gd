class_name WorldDevelopment
extends RefCounted
## How AI professionals change over time: monthly growth towards their hidden potential while
## young, decline of the mechanical abilities with age, the world's opinion (perceived values)
## slowly catching up with the truth, and retirement at the turn of the year.
##
## The decisions are pure functions over plain dictionaries so they can be tested without a
## database; [method monthly] and [method retirements] apply them to a career.
## Humans are never touched: their real skill is the person playing.

## Mechanical abilities fade with age; the rest is experience and keeps longer.
const MECHANICAL: Array[StringName] = [&"aim", &"reaction", &"spray_control", &"crosshair_placement", &"movement"]
## Share of the gap to potential closed per year, by age (upper bound inclusive).
const GROWTH_BY_AGE: Array[Vector2] = [Vector2(20, 0.35), Vector2(23, 0.25), Vector2(26, 0.15), Vector2(28, 0.05)]
## Role-focus abilities grow faster.
const FOCUS_BONUS: float = 1.3
## Veterans still pick up experience (monthly chance per non-mechanical ability).
const VETERAN_LEARNING: float = 0.03
## Monthly chance per mechanical ability to drop a point, per year of age past this.
const DECLINE_START_AGE: int = 29
const DECLINE_PER_YEAR: float = 0.06
## Experience abilities only start to fade this late, at a fraction of the mechanical rate.
const LATE_DECLINE_AGE: int = 33
const LATE_DECLINE_SHARE: float = 0.3
## Perceived values move one point towards the truth with this chance plus a confidence share.
const DRIFT_BASE: float = 0.2
const DRIFT_CONFIDENCE: float = 0.5
## Maps in a month at which opinions drift and confidence grows at full pace.
const FULL_EXPOSURE_MAPS: float = 8.0
## Retirement: chance per year of age past this, certainty-ish at the hard age, extra for
## unsigned players who are not good enough to keep going.
const RETIREMENT_START_AGE: int = 28
const RETIREMENT_PER_YEAR: float = 0.05
const RETIREMENT_HARD_AGE: int = 37
const STRUGGLING_RATING: int = 50
const STRUGGLING_CHANCE: float = 0.25


## Mean of the real abilities (potential excluded). 0 when there are none.
static func overall(values: Dictionary) -> int:
	var total := 0
	var count := 0
	for ability: StringName in CareerCatalog.ABILITIES:
		if values.has(ability):
			total += int(values[ability])
			count += 1
	return roundi(float(total) / count) if count > 0 else 0


static func growth_rate(age: int) -> float:
	for step: Vector2 in GROWTH_BY_AGE:
		if age <= int(step.x):
			return step.y
	return 0.0


## Monthly chance that a mechanical ability drops a point.
static func decline_chance(age: int) -> float:
	return maxf(0.0, DECLINE_PER_YEAR * (age - DECLINE_START_AGE))


## One month of development for a player. Returns only the abilities that changed.
static func develop(truth: Dictionary, age: int, role: StringName, rng: RandomNumberGenerator) -> Dictionary:
	var changes: Dictionary = {}
	var potential := int(truth.get(CareerCatalog.POTENTIAL, 0))
	var gap := potential - overall(truth)
	var focus: Array = CareerCatalog.ROLE_FOCUS.get(role, [])
	var grow := clampf(growth_rate(age) * gap / 12.0, 0.0, 0.9) if gap > 0 else 0.0
	var decline := decline_chance(age)
	for ability: StringName in CareerCatalog.ABILITIES:
		if not truth.has(ability):
			continue
		var value := int(truth[ability])
		var mechanical := MECHANICAL.has(ability)
		var chance := grow * (FOCUS_BONUS if focus.has(ability) else 1.0)
		if age > 28 and not mechanical and gap > -3:
			chance = maxf(chance, VETERAN_LEARNING)
		if rng.randf() < chance and value < 99:
			value += 1
		var fade := decline if mechanical else (decline * LATE_DECLINE_SHARE if age >= LATE_DECLINE_AGE else 0.0)
		if rng.randf() < fade:
			value -= 1
		value = clampi(value, 1, 99)
		if value != int(truth[ability]):
			changes[ability] = value
	return changes


## Opinion catching up with reality: each perceived ability may move a point towards the truth.
## Returns only the abilities that changed.
static func drift(seen: Dictionary, truth: Dictionary, confidence: int, rng: RandomNumberGenerator,
		exposure: float = 1.0) -> Dictionary:
	var changes: Dictionary = {}
	var chance := (DRIFT_BASE + DRIFT_CONFIDENCE * clampf(confidence / 100.0, 0.0, 1.0)) * clampf(exposure, 0.0, 1.0)
	for ability: StringName in CareerCatalog.ABILITIES:
		if not seen.has(ability) or not truth.has(ability):
			continue
		var difference := int(truth[ability]) - int(seen[ability])
		if difference != 0 and rng.randf() < chance:
			changes[ability] = int(seen[ability]) + signi(difference)
	return changes


## How much the world saw of a player in a month (0.4..1): mostly the maps they played. Even an
## unseen month leaves something (online play, streams, word of mouth).
static func exposure(maps: int) -> float:
	return 0.4 + 0.6 * minf(maps / FULL_EXPOSURE_MAPS, 1.0)


## The world's confidence in a player after a month. Every map watched closes part of the
## room to the tier's visibility ceiling [param cap]; a month unseen lets the view go stale.
static func confidence_after(confidence: int, maps: int, cap: int, rng: RandomNumberGenerator) -> int:
	if maps == 0:
		return confidence - (1 if confidence > cap / 2 and rng.randf() < 0.3 else 0)
	var room := maxf(cap - confidence, 0.0)
	return confidence + roundi(room * minf(maps / FULL_EXPOSURE_MAPS, 1.5) * 0.2)


## Chance an AI player retires at the turn of the year.
static func retirement_chance(age: int, rating: int, has_contract: bool) -> float:
	var chance := 0.0
	if age > RETIREMENT_START_AGE:
		chance = RETIREMENT_PER_YEAR * (age - RETIREMENT_START_AGE)
	if age >= RETIREMENT_HARD_AGE:
		chance = 0.9
	if not has_contract and age >= 26 and rating < STRUGGLING_RATING:
		chance += STRUGGLING_CHANCE
	return clampf(chance, 0.0, 0.95)


## Applies one month of development and opinion drift to every AI player on [param day].
static func monthly(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	var truths := repo.all_abilities()
	var opinions := repo.all_perceived()
	var watched := repo.maps_since(day - 30)
	for found: Dictionary in repo.ai_players():
		var id := str(found["id"])
		var truth: Dictionary = truths.get(id, {})
		if truth.is_empty():
			continue
		var age := GameDate.age(int(found["birth_day"]), day)
		var changes := develop(truth, age, StringName(str(found["preferred_role"])), rng)
		if not changes.is_empty():
			if not repo.set_abilities(id, changes):
				return false
			truth.merge(changes, true)
			if not repo.record_ability_history(id, day, overall(truth)):
				return false
		var seen: Dictionary = opinions.get(id, {})
		if seen.is_empty():
			continue
		var confidence := repo.perceived_confidence(id)
		var tier := int(found["tier"]) if found["tier"] != null else 0
		var cap: int = CareerStart.TIER_CONFIDENCE.get(tier, CareerStart.TIER_CONFIDENCE[0])
		var maps := int(watched.get(id, 0))
		var new_confidence := confidence_after(confidence, maps, cap, rng)
		var revised := drift(seen, truth, confidence, rng, exposure(maps))
		if revised.is_empty() and new_confidence == confidence:
			continue
		seen.merge(revised, true)
		if not repo.set_perceived(id, seen, new_confidence, day):
			return false
	return true


## Turn-of-the-year retirements, appended to [param retired] as {id, nickname, reputation, age,
## org_name}. Returns false if a write failed.
static func retirements(repo: CareerRepository, day: int, rng: RandomNumberGenerator,
		retired: Array[Dictionary]) -> bool:
	var truths := repo.all_abilities()
	for found: Dictionary in repo.ai_players():
		var id := str(found["id"])
		var age := GameDate.age(int(found["birth_day"]), day)
		var rating := overall(truths.get(id, {}))
		if rng.randf() >= retirement_chance(age, rating, found["organisation_id"] != null):
			continue
		var org_name := ""
		if found["organisation_id"] != null:
			var org := repo.get_organisation(str(found["organisation_id"]))
			org_name = org.name if org != null else ""
		if not repo.retire_player(id, day):
			return false
		retired.append({"id": id, "nickname": str(found["nickname"]), "reputation": int(found["reputation"]),
			"age": age, "org_name": org_name})
	return true
