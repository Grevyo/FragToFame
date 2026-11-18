class_name CareerTraining
extends RefCounted
## Records real training (drills and scrims played in the FPS runtime) to the career, including
## the sessions of a booked bootcamp.
##
## A human professional has no hidden stats: the person at the keyboard is the player. What the
## career keeps is the measured record (scores, times, accuracy) and the world's opinion of you
## (perceived attributes). Nothing here changes aim, recoil, movement or reaction in a match.
##
## There are no fixed rates. Every session is evidence, and how much it says comes from how it
## went (see [method assess]). A scrim with your own team moves each teammate's feelings by the
## result and by who they are ([method CareerPeople.scrim_reaction]). A completed bootcamp is
## judged on the whole week ([method _finish_bootcamp]).

const CONFIDENCE_LIMIT: int = 95
## Share of the gap between score and belief that a fully trusted session closes.
const LEARNING_RATE: float = 0.35
## A reviewed session (personal coach, bootcamp staff) is believed more.
const REVIEW_TRUST: float = 1.5
## Distance (points) from your record at which a session counts as half consistent.
const CONSISTENCY_SPREAD: float = 15.0
## How many earlier sessions of a drill form your record.
const RECORD_SESSIONS: int = 5
## Gap (points) between score and belief beyond which a session no longer confirms the belief.
const CONFIRM_RANGE: float = 30.0
## How consistent a run counts when you have no record for the drill yet (one run says little).
const NO_RECORD_CONSISTENCY: float = 0.35


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
	var reviewed := in_camp or CareerSpending.has_service(repo, player_id, "coach")
	var evidence := {"change": 0, "confidence": 0}
	if ability != &"":
		evidence = assess(result.score, int(repo.perceived(player_id).get(ability, 50)), repo.perceived_confidence(player_id),
			repo.training_scores(player_id, drill, RECORD_SESSIONS), repo.training_count(player_id, drill, day), reviewed)
	# Lambdas capture locals by value: the transaction reports back through this dictionary.
	var outcome: Dictionary = {"bonds": {}, "camp": {}}
	var saved := repo.transaction(func() -> bool:
		if ability != &"" and not _apply(repo, player_id, ability, evidence, day):
			return false
		if not repo.insert_training(player_id, day, drill, result.score, result.metrics, int(evidence["change"]), in_camp):
			return false
		if result.drill_id == TrainingDrills.SCRIM:
			outcome["bonds"] = _scrim_bonds(repo, player_id, result.metrics, day)
			if not bool((outcome["bonds"] as Dictionary).get("ok", true)):
				return false
		if in_camp and bool(CareerSpending.bootcamp_state(repo, player_id)["complete"]):
			outcome["camp"] = _finish_bootcamp(repo, player_id, camp, day)
			return bool((outcome["camp"] as Dictionary)["ok"])
		return true)
	if not saved:
		return "Could not save the training session."
	return _summary(result, in_camp, camp, best_before, ability, evidence, outcome)


## What one session tells the world: {change, confidence, trust}. [param believed] is the
## world's current view of the attribute and [param confidence] how sure it is; [param recent]
## are your earlier scores for the drill and [param earlier_today] how many times you already
## ran it today. A session moves the view more when the world is unsure, when it fits your record
## (a fluke says little), when it is your first run of the day and when someone reviewed it. It
## raises confidence when it confirms the view and lowers it when it contradicts it.
static func assess(score: int, believed: int, confidence: int, recent: Array[int], earlier_today: int,
		reviewed: bool) -> Dictionary:
	var gap := float(score - believed)
	var openness := 1.0 - clampf(confidence / 100.0, 0.0, 0.95)
	var consistency := NO_RECORD_CONSISTENCY
	if not recent.is_empty():
		var mean := 0.0
		for value: int in recent:
			mean += value
		mean /= recent.size()
		consistency = 1.0 / (1.0 + absf(score - mean) / CONSISTENCY_SPREAD)
	var trust := consistency / (1.0 + earlier_today) * (REVIEW_TRUST if reviewed else 1.0)
	var closeness := 1.0 - minf(absf(gap) / CONFIRM_RANGE, 1.0)
	return {"change": roundi(gap * LEARNING_RATE * openness * trust), "confidence": roundi((3.0 * closeness - 1.0) * trust),
		"trust": trust}


## Writes a session's evidence. Confidence is one figure across every attribute, so all rows move.
static func _apply(repo: CareerRepository, player_id: String, ability: StringName, evidence: Dictionary, day: int) -> bool:
	if int(evidence["change"]) == 0 and int(evidence["confidence"]) == 0:
		return true
	var seen := repo.perceived(player_id)
	seen[ability] = clampi(int(seen.get(ability, 50)) + int(evidence["change"]), 1, 100)
	var confidence := clampi(repo.perceived_confidence(player_id) + int(evidence["confidence"]), 0,
		maxi(CONFIDENCE_LIMIT, repo.perceived_confidence(player_id)))
	return repo.set_perceived(player_id, seen, confidence, day)


## A scrim with your own team: each teammate who played reacts to how it went. Returns
## {ok, closer: PackedStringArray, friction: PackedStringArray} (names).
static func _scrim_bonds(repo: CareerRepository, player_id: String, metrics: Dictionary, day: int) -> Dictionary:
	var out := {"ok": true, "closer": PackedStringArray(), "friction": PackedStringArray()}
	var contract := repo.active_contract(player_id)
	var mates: Array = metrics.get("teammates", [])
	if contract == null or mates.is_empty():
		return out
	var score_for := int(metrics.get("score_for", 0))
	var score_against := int(metrics.get("score_against", 0))
	var margin := float(score_for - score_against) / maxf(score_for + score_against, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|%d-%d|%d" % [player_id, day, score_for, score_against, int(metrics.get("kills", 0))])
	for entry: Variant in mates:
		var mate := entry as Dictionary
		var mate_id := str(mate.get("player_id", ""))
		var their := repo.active_contract(mate_id)
		if their == null or their.organisation_id != contract.organisation_id or mate_id == player_id:
			continue
		var before := repo.relationship(player_id, mate_id)
		var delta := CareerPeople.scrim_reaction(repo.person(mate_id), margin, float(metrics.get("rating", 1.0)),
			float(mate.get("rating", 1.0)), before, rng)
		if delta == 0:
			continue
		if not repo.set_relationship(player_id, mate_id, before + delta, day):
			out["ok"] = false
			return out
		var record := repo.get_player(mate_id)
		var name := record.nickname if record != null else mate_id
		if delta >= 2:
			(out["closer"] as PackedStringArray).append(name)
		elif delta <= -2:
			(out["friction"] as PackedStringArray).append(name)
	return out


## The whole programme is done; the week is judged as a whole. Confidence follows how steady your
## sessions were against what the world believes (a steady week is a clear picture, an erratic
## one is not), and each teammate reacts to how well you worked by how much they care about the
## work. Returns {ok, verdict, confidence}.
static func _finish_bootcamp(repo: CareerRepository, player_id: String, camp: Dictionary, day: int) -> Dictionary:
	var seen := repo.perceived(player_id)
	var gaps: Array[float] = []
	for session: Dictionary in repo.bootcamp_sessions(player_id, int(camp["start_day"])):
		var ability := TrainingDrills.ability(StringName(str(session["drill_id"])))
		if ability != &"":
			gaps.append(float(int(session["score"]) - int(seen.get(ability, 50))))
	var mean := 0.0
	for gap: float in gaps:
		mean += gap
	mean /= maxf(gaps.size(), 1.0)
	var spread := 0.0
	for gap: float in gaps:
		spread += (gap - mean) * (gap - mean)
	spread = sqrt(spread / maxf(gaps.size(), 1.0))
	var steadiness := 1.0 / (1.0 + spread / CONSISTENCY_SPREAD)
	var quality := clampf(mean / 20.0, -1.0, 1.0)
	var before := repo.perceived_confidence(player_id)
	var confidence := clampi(before + roundi(4.0 * steadiness - 1.5), 0, maxi(CONFIDENCE_LIMIT, before))
	var out := {"ok": false, "verdict": _verdict(quality, steadiness), "confidence": confidence - before}
	if not repo.set_perceived(player_id, seen, confidence, day):
		return out
	var contract := repo.active_contract(player_id)
	var text := "You complete a bootcamp: %s." % out["verdict"]
	if contract != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|camp|%d" % [player_id, day])
		for member: Dictionary in repo.roster(contract.organisation_id):
			var mate := member["player"] as CareerRecords.PlayerRecord
			if mate.id == player_id:
				continue
			var professionalism := float(repo.person(mate.id).get("professionalism", 10))
			var delta := roundi((professionalism - 8.0) / 4.0 * (0.5 + quality) + rng.randf_range(-1.0, 1.0))
			if delta != 0 and not repo.set_relationship(player_id, mate.id, repo.relationship(player_id, mate.id) + delta, day):
				return out
		text = "You complete a bootcamp with %s behind you: %s." % [repo.get_organisation(contract.organisation_id).name, out["verdict"]]
	out["ok"] = repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.MINOR, text, player_id,
		contract.organisation_id if contract != null else "")
	return out


static func _verdict(quality: float, steadiness: float) -> String:
	var level := "a strong week, above what the scene thought of you" if quality > 0.3 \
		else ("a rough week, below what the scene thought of you" if quality < -0.3 else "a week in line with your reputation")
	return level + (", and a steady one" if steadiness > 0.6 else (", but an erratic one" if steadiness < 0.35 else ""))


static func _summary(result: TrainingResult, in_camp: bool, camp: Dictionary, best_before: int, ability: StringName,
		evidence: Dictionary, outcome: Dictionary) -> String:
	var parts: PackedStringArray = ["Saved to your career"]
	var finished := outcome["camp"] as Dictionary
	if not finished.is_empty():
		parts.append("bootcamp complete: %s (confidence %+d)" % [finished["verdict"], int(finished["confidence"])])
	elif in_camp:
		parts.append("bootcamp session %d of %d" % [(camp["done"] as Array).size() + 1, CareerSpending.BOOTCAMP_PROGRAMME.size()])
	if result.score > best_before and result.drill_id != TrainingDrills.SCRIM:
		parts.append("new personal best")
	var change := int(evidence["change"])
	if change != 0:
		parts.append("the world's view of your %s %+d" % [CareerCatalog.ability_name(ability).to_lower(), change])
	elif ability != &"":
		parts.append("this run did not change the world's view of you")
	var bonds := outcome["bonds"] as Dictionary
	if not (bonds.get("closer", PackedStringArray()) as PackedStringArray).is_empty():
		parts.append("closer to %s" % ", ".join(bonds["closer"] as PackedStringArray))
	if not (bonds.get("friction", PackedStringArray()) as PackedStringArray).is_empty():
		parts.append("friction with %s" % ", ".join(bonds["friction"] as PackedStringArray))
	return " · ".join(parts) + "."
