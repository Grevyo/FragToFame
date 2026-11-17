class_name CareerSeriesEngine
extends RefCounted
## Plays the series nobody plays through the round-by-round [MatchEngine] and writes what
## happened back to the career world:
## - every map's score, MVP and notable moments (`sim_map`) and each player's line (`sim_player_map`);
## - morale: a good map lifts a player, a bad one (or a loss) dents it; personality scales the
##   swing, and morale feeds the next day's form;
## - player reputation from standout or poor series, news for upsets, aces and big clutches;
## - monthly, morale fades and the world's opinion of AI players follows their recent simulated
##   form (perceived values only; the hidden truth never moves from results).
## Organisation form, reputation and prize money still move through [method WorldSimulation.apply_series].

## Maps are MR8 like the human's league series.
const ROUNDS_PER_HALF: int = 8
## Morale change per map: rating above or below 1.00, and a win or a loss.
const MORALE_PER_RATING: float = 6.0
const MORALE_RESULT: float = 1.5
## Monthly morale kept (the rest fades towards neutral).
const MORALE_KEEP: float = 0.7
## Series that move a player's reputation by a point, and the chance it does.
const STANDOUT_RATING: float = 1.3
const POOR_RATING: float = 0.7
const STANDOUT_CHANCE: float = 0.5
## A win the pre-match odds gave this little chance of is an upset.
const UPSET_CHANCE: float = 0.3
## Monthly opinion from form: maps needed, the ratings that shift opinion, and how far opinion
## may run ahead of (or behind) the truth.
const OPINION_MAPS: int = 4
const HYPE_RATING: float = 1.15
const DOUBT_RATING: float = 0.85
const OPINION_LIMIT: int = 8
const OPINION_SKILLS: Array[StringName] = [&"aim", &"reaction", &"crosshair_placement"]


## A team for the engine: the organisation's starting five with their skills (true for AI,
## perceived for humans), traits and morale.
static func sim_team(repo: CareerRepository, org_id: String, lineup: Array[Dictionary] = []) -> MatchEngine.SimTeam:
	var team := MatchEngine.SimTeam.new()
	team.id = org_id
	var org := repo.get_organisation(org_id)
	team.name = org.name if org != null else org_id
	team.form = repo.organisation_form(org_id)
	var members := lineup if not lineup.is_empty() else repo.lineup(org_id)
	for member: Dictionary in members:
		team.players.append(sim_player(repo, member))
	return team


static func sim_player(repo: CareerRepository, member: Dictionary) -> MatchEngine.SimPlayer:
	var player := MatchEngine.SimPlayer.new()
	player.id = str(member["player_id"])
	player.name = str(member.get("name", player.id))
	player.role = StringName(str(member.get("role", "rifler")))
	player.is_human = bool(member.get("is_human", false))
	if player.is_human:
		var seen := repo.perceived(player.id)
		for key: StringName in seen:
			player.skills[key] = seen[key]
	else:
		var given: Dictionary = member.get("abilities", {})
		for key: Variant in given:
			player.skills[StringName(str(key))] = int(given[key])
	var traits := repo.traits(player.id)
	for key: StringName in traits:
		player.traits[key] = traits[key]
	player.morale = repo.morale(player.id)
	return player


## Expected map-win chance from the two lineups before a ball is kicked (used for upsets).
static func expected_chance(home: MatchEngine.SimTeam, away: MatchEngine.SimTeam) -> float:
	return SeriesSimulator.map_win_chance(_mean(home), _mean(away))


## Plays a whole series and records it. [param fixture] is a league fixture row with id,
## home_id, away_id, best_of and tier. Returns the series score (home maps, away maps).
static func play_series(repo: CareerRepository, fixture: Dictionary, day: int, rng: RandomNumberGenerator) -> Vector2i:
	var home_id := str(fixture["home_id"])
	var away_id := str(fixture["away_id"])
	var home := sim_team(repo, home_id)
	var away := sim_team(repo, away_id)
	var chance := expected_chance(home, away)
	@warning_ignore("integer_division")
	var target := int(fixture["best_of"]) / 2 + 1
	var engine := MatchEngine.new(rng, ROUNDS_PER_HALF)
	var score := Vector2i.ZERO
	var lines: Dictionary[String, Array] = {}
	var map_number := 0
	var notes: PackedStringArray = []
	while score.x < target and score.y < target:
		map_number += 1
		var map_id := CareerLeagueMatches.MAP_POOL[(map_number - 1) % CareerLeagueMatches.MAP_POOL.size()]
		# The away side starts on attack on even maps.
		var flipped := map_number % 2 == 0
		var played := engine.play_map(away, home) if flipped else engine.play_map(home, away)
		var map_score: Vector2i = played["score"]
		if flipped:
			map_score = Vector2i(map_score.y, map_score.x)
		var home_won := map_score.x > map_score.y
		score += Vector2i(1, 0) if home_won else Vector2i(0, 1)
		if not repo.insert_sim_map(int(fixture["id"]), map_number, map_id, map_score, str(played["mvp"]), played["highlights"]):
			return Vector2i(-1, -1)
		notes.append_array(played["highlights"])
		for team: MatchEngine.SimTeam in [home, away]:
			var won := home_won == (team == home)
			for player: MatchEngine.SimPlayer in team.players:
				var line: Dictionary = played["players"].get(player.id, {})
				if line.is_empty():
					continue
				if not repo.insert_sim_line(day, int(fixture["id"]), "", map_number, player.id, team.id, line, won):
					return Vector2i(-1, -1)
				if not lines.has(player.id):
					lines[player.id] = []
				lines[player.id].append(float(line["rating"]))
				player.morale = next_morale(player.morale, float(line["rating"]), won, player.traits)
	if not _after_series(repo, fixture, home, away, score, chance, lines, notes, day, rng):
		return Vector2i(-1, -1)
	return score


## Morale after one map (−20..20).
static func next_morale(morale: float, rating: float, won: bool, traits: Dictionary) -> float:
	var swing := (rating - 1.0) * MORALE_PER_RATING + (MORALE_RESULT if won else -MORALE_RESULT)
	swing *= 1.0 + 0.25 * int(traits.get(&"tr_hot_headed", 0)) - 0.2 * int(traits.get(&"tr_calm", 0))
	return clampf(morale + swing, -20.0, 20.0)


## Monthly: morale fades and the world's opinion follows AI players' recent simulated form.
static func monthly(repo: CareerRepository, day: int) -> bool:
	if not repo.fade_morale(MORALE_KEEP, day):
		return false
	for found: Dictionary in repo.sim_ratings_since(day - 31, OPINION_MAPS):
		var rating := float(found["rating"])
		var step := 1 if rating >= HYPE_RATING else (-1 if rating <= DOUBT_RATING else 0)
		if step == 0:
			continue
		var player_id := str(found["player_id"])
		var truth := repo.abilities(player_id)
		var seen := repo.perceived(player_id)
		var changed: Dictionary = {}
		for key: StringName in OPINION_SKILLS:
			var value := int(seen.get(key, truth.get(key, 50))) + step
			var real := int(truth.get(key, 50))
			changed[key] = clampi(value, real - OPINION_LIMIT, real + OPINION_LIMIT)
		if not repo.set_perceived(player_id, changed, repo.perceived_confidence(player_id), day):
			return false
	return true


static func _after_series(repo: CareerRepository, fixture: Dictionary, home: MatchEngine.SimTeam, away: MatchEngine.SimTeam,
		score: Vector2i, chance: float, lines: Dictionary[String, Array], notes: PackedStringArray, day: int,
		rng: RandomNumberGenerator) -> bool:
	var tier := int(fixture["tier"])
	var best_id := ""
	var best := 0.0
	for team: MatchEngine.SimTeam in [home, away]:
		for player: MatchEngine.SimPlayer in team.players:
			if not repo.set_morale(player.id, roundi(player.morale), day):
				return false
			var ratings: Array = lines.get(player.id, [])
			if ratings.is_empty() or player.is_human:
				continue
			var average := 0.0
			for value: float in ratings:
				average += value
			average /= ratings.size()
			if average > best:
				best = average
				best_id = player.id
			var step := 1 if average >= STANDOUT_RATING else (-1 if average <= POOR_RATING else 0)
			if step != 0 and rng.randf() < STANDOUT_CHANCE and not repo.set_reputation(player.id, repo.reputation(player.id) + step, day):
				return false
	var home_won := score.x > score.y
	var winner := home if home_won else away
	var loser := away if home_won else home
	var winner_chance := chance if home_won else 1.0 - chance
	var score_text := "%d–%d" % [maxi(score.x, score.y), mini(score.x, score.y)]
	if winner_chance < UPSET_CHANCE and not repo.add_news(day, WorldSimulation.NEWS_SEASON,
			WorldSimulation.NOTABLE if tier <= 2 else WorldSimulation.MINOR, "Upset: %s beat %s %s." % [winner.name, loser.name,
				score_text], "", winner.id):
		return false
	if tier <= 2 and best >= 1.6 and not best_id.is_empty():
		var star := repo.get_player(best_id)
		if star != null and not repo.add_news(day, WorldSimulation.NEWS_SEASON, WorldSimulation.MINOR,
				"%s stars with a %.2f rating as %s beat %s %s." % [star.nickname, best, winner.name, loser.name, score_text], best_id):
			return false
	for note: String in notes:
		if (note.contains("aces") or note.contains("1v4") or note.contains("1v5")) and tier <= 2 \
				and not repo.add_news(day, WorldSimulation.NEWS_SEASON, WorldSimulation.MINOR,
					"%s (%s vs %s)." % [note, home.name, away.name]):
			return false
	return true


static func _mean(team: MatchEngine.SimTeam) -> float:
	var total := 0.0
	var count := 0
	for player: MatchEngine.SimPlayer in team.players:
		for value: Variant in player.skills.values():
			total += float(value)
			count += 1
	return total / count + WorldSimulation.FORM_STRENGTH * team.form if count > 0 else 0.0
