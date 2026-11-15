class_name HumanCareer
extends RefCounted
## Creates the human's fictional professional in a career world.
##
## Humans get **perceived** values (what the esports world believes, set by career difficulty)
## and reputation — never simulated abilities. Their real skill is the person at the keyboard.


## [param profile]: first_name, last_name, nickname, nation_id, preferred_role (StringName),
## difficulty (StringName), age (int, 16–30). Returns the new player ID or "" (see [param errors]).
static func create(repo: CareerRepository, profile: Dictionary, slot: int, seed_value: int,
		errors: Array[String] = []) -> String:
	errors.append_array(validate(profile))
	if not errors.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var today := repo.current_day()
	var difficulty := StringName(str(profile["difficulty"]))
	var tuning: Array = CareerCatalog.DIFFICULTIES[difficulty]
	var role := StringName(str(profile["preferred_role"]))
	var player := CareerRecords.PlayerRecord.new()
	player.id = Ids.generate("ply")
	player.first_name = str(profile["first_name"]).strip_edges()
	player.last_name = str(profile["last_name"]).strip_edges()
	player.nickname = str(profile["nickname"]).strip_edges()
	player.nation_id = str(profile["nation_id"])
	player.birth_day = today - int(profile.get("age", 18)) * GameDate.DAYS_PER_YEAR - rng.randi_range(0, 300)
	player.preferred_role = role
	player.is_human = true
	player.created_day = today
	var focus: Array = CareerCatalog.ROLE_FOCUS.get(role, [])
	var ok := repo.transaction(func() -> bool:
		if not repo.insert_player(player):
			return false
		var seen: Dictionary = {}
		for ability: StringName in CareerCatalog.ABILITIES:
			var value := float(tuning[0]) + rng.randfn(0.0, 4.0) + (5.0 if focus.has(ability) else 0.0)
			seen[ability] = clampi(roundi(value), 1, 99)
		if not repo.set_perceived(player.id, seen, int(tuning[2]), today):
			return false
		if not repo.set_reputation(player.id, int(tuning[1]), today):
			return false
		return repo.db.execute("INSERT INTO human_profile (player_id, slot, difficulty, created_day) VALUES (?, ?, ?, ?);",
			[player.id, slot, String(difficulty), today]))
	if not ok:
		errors.append("could not create the player: %s" % repo.db.last_error)
		return ""
	return player.id


## Returns a list of problems with [param profile] (empty when valid).
static func validate(profile: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for key: String in ["first_name", "last_name", "nickname"]:
		var text := str(profile.get(key, "")).strip_edges()
		if text.is_empty():
			problems.append("%s is required" % key.replace("_", " ").capitalize())
		elif text.length() > 24:
			problems.append("%s is too long (max 24)" % key.replace("_", " ").capitalize())
	if not CareerCatalog.NATIONS.has(str(profile.get("nation_id", ""))):
		problems.append("choose a nationality")
	if not CareerCatalog.ROLES.has(StringName(str(profile.get("preferred_role", "")))):
		problems.append("choose a preferred role")
	if not CareerCatalog.DIFFICULTIES.has(StringName(str(profile.get("difficulty", "")))):
		problems.append("choose a career difficulty")
	var age := int(profile.get("age", 18))
	if age < 16 or age > 30:
		problems.append("age must be between 16 and 30")
	return problems
