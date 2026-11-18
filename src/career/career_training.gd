class_name CareerTraining
extends RefCounted
## Records real training (drills and scrims played in the FPS runtime) to the career.
##
## A human professional has no hidden stats: the person at the keyboard is the player. What the
## career keeps is the measured record (scores, times, accuracy) and the world's opinion of you
## (perceived attributes). Each day's first completed session of a drill is evidence: it moves
## the perceived attribute the drill measures a little toward the drill's score. Nothing here
## changes aim, recoil, movement or reaction in a match.

## How far one session's evidence moves the perceived attribute toward its score (points).
const EVIDENCE_STEP: int = 3
const COACH_EVIDENCE_STEP: int = 5
const CONFIDENCE_GAIN: int = 2
const CONFIDENCE_LIMIT: int = 95


## Saves [param result] for [param player_id]. Returns a line for the result screen.
static func record(repo: CareerRepository, player_id: String, result: TrainingResult) -> String:
	if result == null or not result.completed:
		return "Session not completed: not recorded."
	if repo.human_profile(player_id).is_empty():
		return "No career player to record this for."
	var day := repo.current_day()
	var drill := String(result.drill_id)
	var ability := TrainingDrills.ability(result.drill_id)
	var best_before := int(repo.training_bests(player_id).get(drill, {}).get("best", 0))
	var change := 0
	var saved := repo.transaction(func() -> bool:
		if ability != &"" and not repo.training_evidence_today(player_id, drill, day):
			change = _evidence(repo, player_id, ability, result.score, day)
		return repo.insert_training(player_id, day, drill, result.score, result.metrics, change))
	if not saved:
		return "Could not save the training session."
	var parts: PackedStringArray = ["Saved to your career"]
	if result.score > best_before and result.drill_id != TrainingDrills.SCRIM:
		parts.append("new personal best")
	if change != 0:
		parts.append("the world's view of your %s %+d" % [CareerCatalog.ability_name(ability).to_lower(), change])
	elif ability != &"":
		parts.append("today's evidence for this drill is already in")
	return " · ".join(parts) + "."


## Moves the perceived attribute toward the score; returns the change.
static func _evidence(repo: CareerRepository, player_id: String, ability: StringName, score: int, day: int) -> int:
	var seen := repo.perceived(player_id)
	var before: int = seen.get(ability, 50)
	var step := COACH_EVIDENCE_STEP if CareerSpending.has_service(repo, player_id, "coach") else EVIDENCE_STEP
	var change := clampi(score - before, -step, step)
	var confidence := mini(repo.perceived_confidence(player_id) + CONFIDENCE_GAIN, CONFIDENCE_LIMIT)
	if change == 0 and confidence == repo.perceived_confidence(player_id):
		return 0
	repo.set_perceived(player_id, {ability: clampi(before + change, 1, 100)}, confidence, day)
	return change
