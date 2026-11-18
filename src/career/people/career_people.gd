class_name CareerPeople
extends RefCounted
## Every AI professional is a person: a personality (ambition, loyalty, professionalism,
## temperament, ego, sociability), something that drives them, a background, a career goal,
## how happy they are where they are, and relationships with the people they play beside.
##
## Monthly the people layer updates moods and relationships, checks goals, and lets life happen
## (streams, burnout, mentoring, fallings-out). People speak in interviews. Moods feed back into
## the world: unhappy players refuse renewals, get sold, and loyal ones turn moves down. The
## human has no person row: the person is the one playing.

## Relationship levels that count as friends / rivals.
const FRIEND_LEVEL: int = 40
const RIVAL_LEVEL: int = -40
## Relationships: monthly change per point of compatibility, and the share kept (the rest fades).
const BOND_PACE: float = 3.0
const BOND_KEEP: float = 0.95
## Share of the way happiness moves to its target each month.
const MOOD_STEP: float = 0.4
## Unhappy enough to want out (unless very loyal).
const UNSETTLED: int = -15
## Monthly life-event chances.
const STREAM_CHANCE: float = 0.03
const BURNOUT_CHANCE: float = 0.02
const MENTOR_CHANCE: float = 0.05
const FALLOUT_CHANCE: float = 0.15
## News about people is reported for these tiers (and always for the human's organisation).
const NEWS_TIERS: int = 2


## A new person, shaped by their traits (a loyal player is loyal, a hot head is volatile).
static func roll_person(rng: RandomNumberGenerator, traits: Dictionary) -> Dictionary:
	var person := {}
	for field: String in CareerRepository.PERSON_FIELDS:
		person[field] = clampi(roundi(rng.randfn(10.5, 3.6)), 1, 20)
	var lean := func(field: String, amount: int) -> void:
		person[field] = clampi(int(person[field]) + amount, 1, 20)
	if traits.has(&"tr_loyal"):
		lean.call("loyalty", 6)
	if traits.has(&"tr_mercenary"):
		lean.call("loyalty", -6)
	if traits.has(&"tr_ambitious"):
		lean.call("ambition", 6)
	if traits.has(&"tr_hot_headed"):
		lean.call("temperament", -6)
	if traits.has(&"tr_calm"):
		lean.call("temperament", 6)
	if traits.has(&"tr_team_player") or traits.has(&"tr_vocal"):
		lean.call("sociability", 4)
	if traits.has(&"tr_lone_wolf") or traits.has(&"tr_quiet"):
		lean.call("sociability", -4)
	if traits.has(&"tr_lone_wolf"):
		lean.call("ego", 3)
	var drives: Dictionary[String, float] = {"winning": 1.0 + int(person["ambition"]) * 0.12, "money": 1.0 + (20 - int(person["loyalty"])) * 0.08
		+ (2.0 if traits.has(&"tr_mercenary") else 0.0), "fame": 0.6 + int(person["ego"]) * 0.1,
		"team": 0.6 + int(person["loyalty"]) * 0.1, "game": 1.2}
	person["drive"] = _weighted(rng, drives)
	var goals: Dictionary[String, float] = {}
	for goal: String in PersonVoice.GOALS:
		goals[goal] = 3.0 if (PersonVoice.GOALS[goal][1] as Array).has(person["drive"]) else 0.5
	person["goal"] = _weighted(rng, goals)
	person["background"] = PersonVoice.BACKGROUNDS[rng.randi_range(0, PersonVoice.BACKGROUNDS.size() - 1)]
	person["happiness"] = rng.randi_range(-5, 10)
	return person


## Gives a person to every active AI player who has none (new rookies, older saves).
static func ensure(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	for found: Dictionary in repo.players_without_person():
		var person := roll_person(rng, repo.traits(str(found["id"])))
		person["updated_day"] = day
		if not repo.insert_person(str(found["id"]), person):
			return false
	return true


## Where happiness is heading and the main reason: {value, reason, outgrown}.
## [param context]: is_substitute, form, salary, fair_salary (what teammates of that level earn),
## tier, rating, friends, rivals, morale.
static func mood_target(person: Dictionary, context: Dictionary) -> Dictionary:
	var ambition := int(person["ambition"])
	var reasons: Array[Array] = []
	if bool(context.get("is_substitute", false)):
		reasons.append([-(6.0 + ambition * 0.6), "wants more playing time"])
	reasons.append([float(context.get("form", 0)) * 0.15, "team results"])
	var fair := maxf(float(context.get("fair_salary", 1)), 1.0)
	var ratio := float(context.get("salary", fair)) / fair
	if ratio < 0.75:
		reasons.append([-minf((0.75 - ratio) * 50.0 * (1.5 if person["drive"] == "money" else 1.0), 15.0), "feels underpaid"])
	elif ratio > 1.15:
		reasons.append([4.0, "well paid"])
	var tier := int(context.get("tier", 4))
	var outgrown := false
	if tier > 1:
		var above: int = WorldGenerator.TIER_PROFILE.get(tier - 1, WorldGenerator.TIER_PROFILE[1])[0]
		outgrown = int(context.get("rating", 0)) >= above and ambition >= 13
		if outgrown:
			reasons.append([-ambition * 0.7, "believes they belong in a higher tier"])
	var friends := int(context.get("friends", 0))
	var rivals := int(context.get("rivals", 0))
	if friends > 0:
		reasons.append([friends * 3.0, "friends in the squad"])
	if rivals > 0:
		reasons.append([-rivals * 5.0, "tension with teammates"])
	reasons.append([float(context.get("morale", 0)) * 0.5, "recent form"])
	reasons.append([(int(person["loyalty"]) - 10) * 0.4, "loyalty"])
	var total := 0.0
	var worst: Array = [0.0, "settled"]
	var best: Array = [0.0, "settled"]
	for reason: Array in reasons:
		total += float(reason[0])
		if float(reason[0]) < float(worst[0]):
			worst = reason
		if float(reason[0]) > float(best[0]):
			best = reason
	var value := clampi(roundi(total), -50, 50)
	return {"value": value, "reason": str(worst[1]) if value < 0 else str(best[1]), "outgrown": outgrown}


## True when this person, at this mood, wants to leave their club.
static func wants_out(person: Dictionary, happiness: int, outgrown: bool) -> bool:
	var loyalty := int(person["loyalty"])
	return (happiness <= UNSETTLED and loyalty <= 14) or (outgrown and int(person["ambition"]) >= 16 and loyalty <= 12)


## Added to the club's renewal chance: loyal people stay, unsettled ones say no.
static func renewal_modifier(person: Dictionary) -> float:
	if person.is_empty():
		return 0.0
	if int(person.get("wants_move", 0)) == 1:
		return -0.45
	return (int(person["loyalty"]) - 10) * 0.015 + int(person.get("happiness", 0)) * 0.004


## Added to a club's willingness to sell: an unsettled player is easier to buy.
static func sell_modifier(person: Dictionary) -> float:
	return 0.25 if not person.is_empty() and int(person.get("wants_move", 0)) == 1 else 0.0


## Whether the player agrees to join [param to_tier] from [param from_tier].
static func accepts_move(person: Dictionary, from_tier: int, to_tier: int, rng: RandomNumberGenerator) -> bool:
	if person.is_empty() or int(person.get("wants_move", 0)) == 1:
		return true
	var happy := int(person.get("happiness", 0)) >= 5
	if to_tier > from_tier:
		return rng.randf() < (0.2 if happy else 0.5)
	if int(person["loyalty"]) >= 15 and happy:
		return rng.randf() < (0.55 if to_tier < from_tier else 0.3)
	return true


## How a teammate's feelings toward the human move after a scrim together (about -15..15), from
## how it went and who they are. [param margin] is the round difference over rounds played
## (-1..1); ratings are F2F match ratings. A result is felt harder by volatile people when it goes
## wrong; sociable people warm up anyway; being outplayed by you pleases a humble teammate and
## stings an ego; carrying you is shrugged off by professionals and resented by the rest; where
## you already stand and their mood colour all of it.
static func scrim_reaction(person: Dictionary, margin: float, your_rating: float, their_rating: float, bond: int,
		rng: RandomNumberGenerator) -> int:
	var temperament := float(person.get("temperament", 10))
	var shared := margin * 8.0
	if shared < 0.0:
		shared *= 1.0 + (10.0 - temperament) / 15.0
	var warmth := (float(person.get("sociability", 10)) - 10.0) * 0.2
	var gap := your_rating - their_rating
	var pride := gap * 4.0 * (10.0 - float(person.get("ego", 10))) / 10.0 if gap > 0.0 \
		else gap * 3.0 * (10.0 - float(person.get("professionalism", 10))) / 10.0
	var history := bond / 40.0
	var mood := float(person.get("happiness", 0)) / 25.0
	return clampi(roundi(shared + warmth + pride + history + mood + rng.randf_range(-1.5, 1.5)), -15, 15)


## How two people get on (-5..+4; about 0 for a typical pair).
static func compatibility(a: Dictionary, b: Dictionary) -> float:
	var value := 2.2 - absi(int(a.get("sociability", 10)) - int(b.get("sociability", 10))) * 0.35
	if int(a.get("temperament", 10)) <= 7 and int(b.get("temperament", 10)) <= 7:
		value -= 2.0
	if int(a.get("ego", 10)) >= 15 and int(b.get("ego", 10)) >= 15:
		value -= 3.0
	if (int(a.get("sociability", 10)) + int(b.get("sociability", 10))) >= 28:
		value += 1.0
	return clampf(value, -5.0, 4.0)


## The monthly pass: people for newcomers, relationships, moods, goals and life events.
static func monthly(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	if not ensure(repo, day, rng):
		return false
	var everyone := repo.people()
	var bonds := repo.relationships()
	var by_org: Dictionary[String, Array] = {}
	for contract: Dictionary in repo.contracted_players():
		var org_id := str(contract["organisation_id"])
		if not by_org.has(org_id):
			by_org[org_id] = []
		by_org[org_id].append(contract)
	for org_id: String in by_org:
		var squad: Array[Dictionary] = []
		squad.assign(by_org[org_id])
		if not _relationships(repo, squad, everyone, bonds, day, rng) or not _moods(repo, squad, everyone, bonds, day, rng) \
				or not _life(repo, squad, everyone, day, rng):
			return false
	return true


## Has someone speak to the press about [param topic]. Adds an interview story.
static func interview(repo: CareerRepository, player_id: String, org_id: String, topic: String, other: String,
		importance: int, day: int, rng: RandomNumberGenerator) -> bool:
	var person := repo.person(player_id)
	var player := repo.get_player(player_id)
	if person.is_empty() or player == null:
		return true
	var org := repo.get_organisation(org_id)
	var text := PersonVoice.answer(person, topic, org.name if org != null else "my old team", other, rng)
	if text.is_empty():
		return true
	return repo.add_news(day, WorldSimulation.NEWS_INTERVIEW, importance, "%s: \"%s\"" % [player.nickname, text], player_id,
		org_id if org != null else "")


static func _relationships(repo: CareerRepository, squad: Array[Dictionary], everyone: Dictionary[String, Dictionary],
		bonds: Dictionary[String, int], day: int, rng: RandomNumberGenerator) -> bool:
	for i: int in squad.size():
		for j: int in range(i + 1, squad.size()):
			var a := str(squad[i]["player_id"])
			var b := str(squad[j]["player_id"])
			var key := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
			var before: int = bonds.get(key, 0)
			var delta := compatibility(everyone.get(a, {}), everyone.get(b, {})) * BOND_PACE + float(squad[i]["form"]) / 25.0 \
				+ rng.randf_range(-4.0, 4.0)
			var after := clampi(roundi(before * BOND_KEEP + delta), -100, 100)
			if after == before:
				continue
			bonds[key] = after
			if not repo.set_relationship(a, b, after, day):
				return false
			if not _bond_news(repo, squad[i], squad[j], before, after, day, rng):
				return false
	return true


static func _bond_news(repo: CareerRepository, first: Dictionary, second: Dictionary, before: int, after: int, day: int,
		rng: RandomNumberGenerator) -> bool:
	var org := repo.get_organisation(str(first["organisation_id"]))
	var reported := int(first["tier"]) <= NEWS_TIERS or int(first["is_human"]) == 1 or int(second["is_human"]) == 1
	if org == null or not reported:
		return true
	var names := "%s and %s" % [first["nickname"], second["nickname"]]
	if before < FRIEND_LEVEL and after >= FRIEND_LEVEL:
		return repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.MINOR, "%s have become close friends at %s." % [names,
			org.short_name], str(first["player_id"]), org.id)
	if before > RIVAL_LEVEL and after <= RIVAL_LEVEL:
		return repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.NOTABLE, "Tension at %s: %s are not getting on." % [
			org.short_name, names], str(first["player_id"]), org.id)
	if after <= -70 and rng.randf() < FALLOUT_CHANCE:
		return repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.HEADLINE if int(first["tier"]) == 1 else WorldSimulation.NOTABLE,
			"%s clash publicly after a heated scrim at %s." % [names, org.short_name], str(first["player_id"]), org.id)
	return true


static func _moods(repo: CareerRepository, squad: Array[Dictionary], everyone: Dictionary[String, Dictionary],
		bonds: Dictionary[String, int], day: int, rng: RandomNumberGenerator) -> bool:
	# Pay is judged against teammates: what the squad earns for its level.
	var ratings: Dictionary[String, int] = {}
	var pay := 0.0
	var level := 0.0
	for member: Dictionary in squad:
		ratings[str(member["player_id"])] = repo.perceived_rating(str(member["player_id"]))
		pay += float(member["monthly_salary"])
		level += float(ratings[str(member["player_id"])])
	var squad_size := maxf(squad.size(), 1.0)
	for member: Dictionary in squad:
		var id := str(member["player_id"])
		var person: Dictionary = everyone.get(id, {})
		if person.is_empty():
			continue
		var friends := 0
		var rivals := 0
		for other: Dictionary in squad:
			var other_id := str(other["player_id"])
			if other_id == id:
				continue
			var strength: int = bonds.get("%s|%s" % [id, other_id] if id < other_id else "%s|%s" % [other_id, id], 0)
			friends += 1 if strength >= FRIEND_LEVEL else 0
			rivals += 1 if strength <= RIVAL_LEVEL else 0
		var tier := int(member["tier"])
		var rating := ratings[id]
		var fair := pay / squad_size * pow(float(rating) / maxf(level / squad_size, 1.0), 1.5)
		var target := mood_target(person, {"is_substitute": int(member["is_substitute"]) == 1, "form": int(member["form"]),
			"salary": int(member["monthly_salary"]), "fair_salary": roundi(fair), "tier": tier,
			"rating": rating, "friends": friends, "rivals": rivals, "morale": repo.morale(id)})
		var happiness := roundi(lerpf(float(person["happiness"]), float(target["value"]), MOOD_STEP))
		var unsettled := wants_out(person, happiness, bool(target["outgrown"]))
		var was_unsettled := int(person["wants_move"]) == 1
		if not repo.set_person_mood(id, happiness, unsettled, str(target["reason"]), day) \
				or not repo.set_morale(id, repo.morale(id) + roundi(happiness / 12.0), day):
			return false
		person["happiness"] = happiness
		person["wants_move"] = 1 if unsettled else 0
		if unsettled and not was_unsettled and tier <= NEWS_TIERS + 1:
			var importance := WorldSimulation.NOTABLE if tier <= NEWS_TIERS else WorldSimulation.MINOR
			if not repo.add_news(day, WorldSimulation.NEWS_PEOPLE, importance, "%s is unsettled at %s (%s)." % [member["nickname"],
					repo.get_organisation(str(member["organisation_id"])).short_name, target["reason"]], id, str(member["organisation_id"])) \
					or not interview(repo, id, str(member["organisation_id"]), "unsettled", "", WorldSimulation.MINOR, day, rng):
				return false
		if person.get("goal_done_day") == null and _goal_reached(repo, id, person, member, day):
			if not repo.set_goal_done(id, day) or not repo.set_person_mood(id, mini(happiness + 10, 50), unsettled, "achieved a career goal", day):
				return false
			if tier <= NEWS_TIERS + 1 and (not repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.MINOR,
					"%s achieves a career goal: %s." % [member["nickname"], PersonVoice.goal_text(str(person["goal"])).to_lower()], id,
					str(member["organisation_id"])) or not interview(repo, id, str(member["organisation_id"]), "goal_done", "",
					WorldSimulation.MINOR, day, rng)):
				return false
	return true


static func _goal_reached(repo: CareerRepository, player_id: String, person: Dictionary, member: Dictionary, day: int) -> bool:
	match str(person["goal"]):
		"win_title":
			return repo.honours(player_id).any(func(h: Dictionary) -> bool: return int(h["position"]) == 1)
		"reach_tier_1":
			return int(member["tier"]) == 1
		"one_club":
			return day - int(member["start_day"]) >= 5 * GameDate.DAYS_PER_YEAR
		"become_star":
			return repo.reputation(player_id) >= 70
		"play_abroad":
			var player := repo.get_player(player_id)
			var org := repo.get_organisation(str(member["organisation_id"]))
			return player != null and org != null and CareerCatalog.nation_region(player.nation_id) != org.region_id
	return false


static func _life(repo: CareerRepository, squad: Array[Dictionary], everyone: Dictionary[String, Dictionary], day: int,
		rng: RandomNumberGenerator) -> bool:
	for member: Dictionary in squad:
		var id := str(member["player_id"])
		var person: Dictionary = everyone.get(id, {})
		if person.is_empty():
			continue
		var tier := int(member["tier"])
		var reported := tier <= NEWS_TIERS + 1
		var org_id := str(member["organisation_id"])
		if int(person["ego"]) >= 14 and person["drive"] == "fame" and rng.randf() < STREAM_CHANCE:
			if not repo.set_reputation(id, repo.reputation(id) + 1, day):
				return false
			if reported and not repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.MINOR,
					"%s's practice streams are drawing big crowds." % member["nickname"], id, org_id):
				return false
		elif int(person["professionalism"]) <= 7 and rng.randf() < BURNOUT_CHANCE:
			if not repo.set_morale(id, repo.morale(id) - 8, day):
				return false
			if reported and not repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.MINOR,
					"%s admits to burnout and steps back from streaming and bootcamps." % member["nickname"], id, org_id):
				return false
		elif int(person["professionalism"]) >= 15 and GameDate.age(int(member["birth_day"]), day) >= 26 and rng.randf() < MENTOR_CHANCE:
			for other: Dictionary in squad:
				if str(other["player_id"]) != id and GameDate.age(int(other["birth_day"]), day) <= 20:
					var bond := repo.relationship(id, str(other["player_id"]))
					if not repo.set_relationship(id, str(other["player_id"]), bond + 25, day):
						return false
					if reported and not repo.add_news(day, WorldSimulation.NEWS_PEOPLE, WorldSimulation.MINOR,
							"%s has taken young %s under their wing." % [member["nickname"], other["nickname"]], id, org_id):
						return false
					break
	return true


static func _weighted(rng: RandomNumberGenerator, weights: Dictionary[String, float]) -> String:
	var total := 0.0
	for key: String in weights:
		total += weights[key]
	var roll := rng.randf() * total
	for key: String in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return str(weights.keys()[0])
