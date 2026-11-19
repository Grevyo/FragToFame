class_name CareerDevelopment
extends RefCounted
## Career opinions, amateur standing and scouting are separate from recorded performance and
## the mechanics used to play a fixture.

const TRAINING: String = "training"
const SCOUTING: String = "scouting"

const STARTING_ELO: Dictionary[StringName, int] = {&"grind": 800, &"standard": 1000, &"prospect": 1200}
const ELO_K: float = 32.0
const SCOUT_CONFIDENCE_LIMIT: int = 95
## How visible each tier is to a scout before counting maps (bigger stage, more footage).
const SCOUT_VISIBILITY: Dictionary[int, float] = {1: 0.2, 2: 0.15, 3: 0.1, 4: 0.05, 0: 0.0}
## Maps in the last [constant SCOUT_WINDOW] days that give a scout a full picture.
const SCOUT_FULL_MAPS: float = 12.0
const SCOUT_WINDOW: int = 90


## Existing careers use the difficulty baseline until their first recorded fixture.
static func current_elo(repo: CareerRepository, player_id: String) -> int:
	var saved := repo.amateur_rating(player_id)
	if not saved.is_empty():
		return int(saved["rating"])
	var profile := repo.human_profile(player_id)
	return STARTING_ELO.get(StringName(str(profile.get("difficulty", ""))), STARTING_ELO[&"standard"])


static func scout(repo: CareerRepository, player_id: String, subject_id: String) -> String:
	var subject := repo.get_player(subject_id)
	if repo.human_profile(player_id).is_empty() or subject == null or subject.is_human or subject.status != "active":
		return "Choose an active AI professional to scout."
	var warning: Array[String] = []
	var saved := repo.transaction(func() -> bool:
		if not repo.development_today(player_id, SCOUTING).is_empty():
			warning.append("Today's scouting report is already complete.")
			return false
		var truth := repo.abilities(subject_id)
		if truth.is_empty():
			warning.append("There is no scouting evidence for this player.")
			return false
		var seen := repo.perceived(subject_id)
		var day := repo.current_day()
		var contract := repo.active_contract(subject_id)
		var org := repo.get_organisation(contract.organisation_id) if contract != null else null
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|scout|%s|%d" % [player_id, subject_id, day])
		var previous_confidence := repo.perceived_confidence(subject_id)
		var report := scout_report(seen, truth, previous_confidence, int(repo.form_since(subject_id, day - SCOUT_WINDOW)["maps"]),
			org.tier if org != null else 0, rng)
		var revised: Dictionary = report["revised"]
		var changed := false
		for ability: Variant in revised:
			changed = changed or not seen.has(ability) or revised[ability] != seen[ability]
		var confidence := _confidence_after(previous_confidence, int(report["gain"]))
		if revised.is_empty() or (not changed and confidence == previous_confidence):
			warning.append("This player's scouting report is already up to date.")
			return false
		return repo.add_development_activity(player_id, SCOUTING, day, subject_id, "",
			confidence - previous_confidence) and repo.set_perceived(subject_id, revised, confidence, day))
	if saved:
		return ""
	return warning[0] if not warning.is_empty() else "Could not record the scouting report."


## What one scouting report learns: {revised, gain, evidence}. Evidence is how much there is
## to watch: the player's recent maps plus their tier's visibility. Each estimate moves part of
## the way to the truth (further with more evidence). Thin footage makes that progress less
## certain. Confidence grows with the evidence and less when the world is already sure. Pure.
static func scout_report(seen: Dictionary, truth: Dictionary, confidence: int, maps: int, tier: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var evidence := clampf(minf(maps / SCOUT_FULL_MAPS, 1.0) * 0.8 + float(SCOUT_VISIBILITY.get(tier, 0.0)), 0.05, 1.0)
	var share := 0.2 + 0.5 * evidence
	var revised: Dictionary = {}
	for ability: StringName in CareerCatalog.ABILITIES:
		if truth.has(ability):
			var estimate: int = seen.get(ability, 50)
			var actual := int(truth[ability])
			# The scout sees the truth through the evidence: thin footage blurs what they see.
			var observed := actual + rng.randf_range(-1.0, 1.0) * (1.0 - evidence) * 6.0
			var next_estimate := estimate + roundi((observed - estimate) * share)
			revised[ability] = clampi(next_estimate, mini(estimate, actual), maxi(estimate, actual))
	var openness := 1.0 - clampf(confidence / 100.0, 0.0, 0.95)
	return {"revised": revised, "gain": roundi((4.0 + 16.0 * evidence) * openness), "evidence": evidence}


## Called once by fixture publication, inside its transaction and after telemetry validation.
## [param counts] is empty for a simulated match: the result still moves ELO and reputation,
## but there is no performance rating or evidence to change opinions.
static func apply_amateur_result(repo: CareerRepository, fixture: CareerFixture,
		result: MatchResult, counts: Dictionary) -> bool:
	var id := fixture.player_id
	var day := fixture.scheduled_day
	var prior_elo := current_elo(repo, id)
	var won := result.home_score > result.away_score
	var opponent_elo := _opponent_elo(fixture.setup)
	var expected := 1.0 / (1.0 + pow(10.0, (opponent_elo - prior_elo) / 400.0))
	var next_elo := clampi(prior_elo + roundi(ELO_K * (float(won) - expected)), 100, 3500)

	var rounds := result.home_score + result.away_score
	var margin := float(result.home_score - result.away_score) / maxf(rounds, 1.0)
	var reputation := repo.reputation(id)
	# A result without statistics contributes only its outcome and margin.
	var rating := 1.0 if counts.is_empty() else MatchStatistics.rating(counts)
	var next_reputation := clampi(reputation + amateur_reputation(won, expected, margin, rating, reputation), 0, 100)
	if won and not repo.add_player_money(id, CareerSpending.AMATEUR_WIN_PRIZE, day, "prize", "Amateur match win"):
		return false
	if counts.is_empty():
		return repo.set_amateur_rating(id, next_elo, next_elo - prior_elo, day) \
			and repo.set_reputation(id, next_reputation, day)

	var opinions := repo.perceived(id)
	var previous_confidence := repo.perceived_confidence(id)
	var confidence := _confidence_after(previous_confidence, amateur_confidence_gain(previous_confidence, rounds))
	# Move only opinions supported by recorded evidence. The recorded counts and rating stay fixed.
	if int(counts["shots"]) >= 5:
		_update_opinion(opinions, &"aim", int(counts["hits"]), int(counts["shots"]))
	if int(counts["first_shots"]) >= 3:
		_update_opinion(opinions, &"crosshair_placement", int(counts["first_hits"]), int(counts["first_shots"]))
	if int(counts["clutch_attempts"]) > 0:
		_update_opinion(opinions, &"composure", int(counts["clutch_wins"]), int(counts["clutch_attempts"]))
	return repo.set_amateur_rating(id, next_elo, next_elo - prior_elo, day) \
		and repo.set_reputation(id, next_reputation, day) \
		and repo.set_perceived(id, opinions, confidence, day)


## How an amateur result moves reputation. What counts is the surprise (a win you were expected
## to lose says far more than one you were expected to win; [param expected] is the ELO win
## chance), the margin (-1..1), and how you played ([param rating], neutral at 1.0).
## The amateur scene matters less the better known you already are. Pure.
static func amateur_reputation(won: bool, expected: float, margin: float, rating: float, reputation: int) -> int:
	var result_part := (float(won) - expected) * 4.0 + margin * 1.5
	var performance := (rating - 1.0) * 3.0
	return roundi((result_part + performance) * clampf(1.1 - reputation / 100.0, 0.2, 1.1))


## Confidence a played amateur match adds: more rounds are more evidence, and a world that is
## already sure of you learns less. Pure.
static func amateur_confidence_gain(confidence: int, rounds: int) -> int:
	return roundi(minf(rounds / 16.0, 1.5) * 5.0 * (1.0 - clampf(confidence / 100.0, 0.0, 0.95)))


static func _opponent_elo(setup: MatchSetup) -> float:
	var sum := 0
	var samples := 0
	for member: Dictionary in setup.away_lineup:
		var abilities := member.get("abilities", {}) as Dictionary
		for value: Variant in abilities.values():
			sum += int(value)
			samples += 1
	return 600.0 + 8.0 * float(sum) / samples if samples > 0 else 1000.0


static func _update_opinion(opinions: Dictionary[StringName, int], ability: StringName,
		successes: int, attempts: int) -> void:
	var before: int = opinions.get(ability, 50)
	var observed := clampi(roundi(float(successes) / attempts * 100.0), 1, 100)
	# A larger sample moves the opinion further: a handful of shots says little.
	var share := attempts / (attempts + 80.0) * 0.3
	opinions[ability] = clampi(before + roundi((observed - before) * share), 1, 100)


static func _confidence_after(previous: int, gain: int) -> int:
	return maxi(previous, mini(SCOUT_CONFIDENCE_LIMIT, previous + gain))
