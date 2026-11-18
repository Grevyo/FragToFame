class_name CareerTraining
extends RefCounted
## Records real training (drills and scrims played in the FPS runtime) to the career, including
## the sessions of a booked bootcamp.
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
	var camp := CareerSpending.bootcamp_state(repo, player_id)
	var in_camp := bool(camp["active"]) and CareerSpending.BOOTCAMP_PROGRAMME.has(result.drill_id) \
		and not (camp["done"] as Array).has(drill)
	# Lambdas capture locals by value: the transaction reports back through this dictionary.
	var outcome: Dictionary = {"change": 0, "finished_camp": false}
	var saved := repo.transaction(func() -> bool:
		if ability != &"" and (in_camp or not repo.training_evidence_today(player_id, drill, day)):
			outcome["change"] = _evidence(repo, player_id, ability, result.score, day, in_camp)
		if not repo.insert_training(player_id, day, drill, result.score, result.metrics, int(outcome["change"]), in_camp):
			return false
		if in_camp and bool(CareerSpending.bootcamp_state(repo, player_id)["complete"]):
			outcome["finished_camp"] = true
			return _finish_bootcamp(repo, player_id, day)
		return true)
	if not saved:
		return "Could not save the training session."
	var change := int(outcome["change"])
	var finished_camp := bool(outcome["finished_camp"])
	var parts: PackedStringArray = ["Saved to your career"]
	if finished_camp:
		parts.append("bootcamp complete")
	elif in_camp:
		parts.append("bootcamp session %d of %d" % [(camp["done"] as Array).size() + 1, CareerSpending.BOOTCAMP_PROGRAMME.size()])
	if result.score > best_before and result.drill_id != TrainingDrills.SCRIM:
		parts.append("new personal best")
	if change != 0:
		parts.append("the world's view of your %s %+d" % [CareerCatalog.ability_name(ability).to_lower(), change])
	elif ability != &"":
		parts.append("today's evidence for this drill is already in")
	return " · ".join(parts) + "."


## The whole programme is done: the world trusts its view of you more, and a week together
## brings you closer to each teammate.
static func _finish_bootcamp(repo: CareerRepository, player_id: String, day: int) -> bool:
	if not repo.set_perceived(player_id, repo.perceived(player_id), mini(repo.perceived_confidence(player_id) + CareerSpending.BOOTCAMP_CONFIDENCE,
			CONFIDENCE_LIMIT), day):
		return false
	var contract := repo.active_contract(player_id)
	var text := "You complete a bootcamp: every drill and a scrim in one week."
	if contract != null:
		for member: Dictionary in repo.roster(contract.organisation_id):
			var mate := member["player"] as CareerRecords.PlayerRecord
			if mate.id != player_id and not repo.set_relationship(player_id, mate.id,
					repo.relationship(player_id, mate.id) + CareerSpending.BOOTCAMP_BOND, day):
				return false
		text = "You complete a bootcamp with your teammates: every drill and a scrim in one week."
	return repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.MINOR, text, player_id,
		contract.organisation_id if contract != null else "")


## Moves the perceived attribute toward the score; returns the change. Bootcamp sessions use
## the coach's larger step (the camp's staff review them).
static func _evidence(repo: CareerRepository, player_id: String, ability: StringName, score: int, day: int,
		in_camp: bool = false) -> int:
	var seen := repo.perceived(player_id)
	var before: int = seen.get(ability, 50)
	var step := COACH_EVIDENCE_STEP if in_camp or CareerSpending.has_service(repo, player_id, "coach") else EVIDENCE_STEP
	var change := clampi(score - before, -step, step)
	var confidence := mini(repo.perceived_confidence(player_id) + CONFIDENCE_GAIN, CONFIDENCE_LIMIT)
	if change == 0 and confidence == repo.perceived_confidence(player_id):
		return 0
	repo.set_perceived(player_id, {ability: clampi(before + change, 1, 100)}, confidence, day)
	return change
