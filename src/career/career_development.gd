class_name CareerDevelopment
extends RefCounted
## Career opinions, amateur standing and scouting are separate from recorded performance and
## the mechanics used to play a fixture.

const TRAINING: String = "training"
const SCOUTING: String = "scouting"

const STARTING_ELO: Dictionary[StringName, int] = {&"grind": 800, &"standard": 1000, &"prospect": 1200}
const ELO_K: float = 32.0
const SCOUT_CONFIDENCE_LIMIT: int = 95
const SCOUT_CONFIDENCE_GAIN: int = 12
const SCOUT_STEP: int = 4


## Existing careers use the difficulty baseline until their first recorded fixture.
static func current_elo(repo: CareerRepository, player_id: String) -> int:
	var saved := repo.amateur_rating(player_id)
	if not saved.is_empty():
		return int(saved["rating"])
	var profile := repo.human_profile(player_id)
	return STARTING_ELO.get(StringName(str(profile.get("difficulty", ""))), STARTING_ELO[&"standard"])


static func train(repo: CareerRepository, player_id: String, ability: StringName) -> String:
	if not CareerCatalog.ABILITIES.has(ability) or repo.human_profile(player_id).is_empty():
		return "Choose a training focus for your career player."
	var warning: Array[String] = []
	var saved := repo.transaction(func() -> bool:
		if not repo.development_today(player_id, TRAINING).is_empty():
			warning.append("Today's training session is already complete.")
			return false
		var rating := repo.perceived(player_id)
		var before: int = rating.get(ability, 1)
		if before >= 100:
			warning.append("This perceived attribute is already at its maximum.")
			return false
		var day := repo.current_day()
		return repo.add_development_activity(player_id, TRAINING, day, player_id, String(ability), 1) \
			and repo.set_perceived(player_id, {ability: before + 1}, repo.perceived_confidence(player_id), day))
	if saved:
		return ""
	return warning[0] if not warning.is_empty() else "Could not record training."


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
		var revised: Dictionary = {}
		var changed := false
		for ability: StringName in CareerCatalog.ABILITIES:
			if truth.has(ability):
				var estimate: int = seen.get(ability, 50)
				var actual := truth[ability]
				revised[ability] = estimate + clampi(actual - estimate, -SCOUT_STEP, SCOUT_STEP)
				changed = changed or not seen.has(ability) or revised[ability] != estimate
		var previous_confidence := repo.perceived_confidence(subject_id)
		var confidence := _confidence_after(previous_confidence, SCOUT_CONFIDENCE_GAIN)
		if revised.is_empty() or (not changed and confidence == previous_confidence):
			warning.append("This player's scouting report is already up to date.")
			return false
		var day := repo.current_day()
		return repo.add_development_activity(player_id, SCOUTING, day, subject_id, "",
			confidence - previous_confidence) and repo.set_perceived(subject_id, revised, confidence, day))
	if saved:
		return ""
	return warning[0] if not warning.is_empty() else "Could not record the scouting report."


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

	var reputation_change := 1 if won else 0
	if counts.is_empty():
		return repo.set_amateur_rating(id, next_elo, next_elo - prior_elo, day) \
			and repo.set_reputation(id, repo.reputation(id) + reputation_change, day)
	var rating := MatchStatistics.rating(counts)
	if rating >= 1.25:
		reputation_change += 1
	elif not won and rating < 0.50:
		reputation_change -= 1

	var opinions := repo.perceived(id)
	var confidence := _confidence_after(repo.perceived_confidence(id), 3)
	# Move only opinions supported by recorded evidence. The recorded counts and rating stay fixed.
	if int(counts["shots"]) >= 5:
		_update_opinion(opinions, &"aim", int(counts["hits"]), int(counts["shots"]))
	if int(counts["first_shots"]) >= 3:
		_update_opinion(opinions, &"crosshair_placement", int(counts["first_hits"]), int(counts["first_shots"]))
	if int(counts["clutch_attempts"]) > 0:
		_update_opinion(opinions, &"composure", int(counts["clutch_wins"]), int(counts["clutch_attempts"]))
	return repo.set_amateur_rating(id, next_elo, next_elo - prior_elo, day) \
		and repo.set_reputation(id, repo.reputation(id) + reputation_change, day) \
		and repo.set_perceived(id, opinions, confidence, day)


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
	opinions[ability] = before + clampi(observed - before, -2, 2)


static func _confidence_after(previous: int, gain: int) -> int:
	return maxi(previous, mini(SCOUT_CONFIDENCE_LIMIT, previous + gain))
