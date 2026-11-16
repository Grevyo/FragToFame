class_name MatchState
extends RefCounted
## Authoritative competitive match rules as a pure state machine (no nodes, no scenes).
##
## The FPS runtime reports what happened (kills, bomb plant/defuse/drop/pickup, purchases) and
## calls [method tick]; this class decides rounds, money, sides and the final [MatchResult], and
## keeps an event log that later milestones turn into statistics. Bots and the future match host
## use exactly the same rules.
##
## Sides: the home team attacks first. Overtime starts on the sides regulation ended on; sides
## then switch every [member MatchRules.overtime_max_rounds] rounds, and money resets to the
## overtime amount at the start of every overtime half.

signal phase_changed(phase: Phase)
signal round_started(round_number: int)
signal round_ended(winner_team: int, reason: StringName)
signal sides_switched
signal bomb_planted(player_id: String)
signal bomb_defused(player_id: String)
signal bomb_dropped(position: Vector3)
signal bomb_picked_up(player_id: String)
signal player_killed(victim_id: String, killer_id: String)
signal match_ended(result: MatchResult)

enum Phase { WAITING, FREEZE, LIVE, ROUND_END, MATCH_END }

const HOME: int = 0
const AWAY: int = 1


class PlayerState extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var team: int = 0
	var is_human: bool = false
	var money: int = 0
	var alive: bool = true
	var armour: int = 0
	var helmet: bool = false
	var has_kit: bool = false
	var primary: StringName = &""
	var secondary: StringName = WeaponCatalog.DEFAULT_SECONDARY
	var kills: int = 0
	var deaths: int = 0

	## Carried weapons, primary first.
	func loadout() -> Array[StringName]:
		var ids: Array[StringName] = []
		if primary != &"":
			ids.append(primary)
		if secondary != &"":
			ids.append(secondary)
		return ids

	func strip_gear() -> void:
		primary = &""
		secondary = WeaponCatalog.DEFAULT_SECONDARY
		armour = 0
		helmet = false
		has_kit = false


class TeamState extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var side: StringName = MatchRules.SIDE_ATTACK
	var score: int = 0
	var loss_streak: int = 0
	var player_ids: Array[String] = []


var setup: MatchSetup
var rules: MatchRules
var teams: Array[TeamState] = []
var players: Dictionary[String, PlayerState] = {}
var phase: Phase = Phase.WAITING
## Seconds left in the current phase (freeze, round clock or round-end delay).
var phase_time_left: float = 0.0
## Seconds since the round went live (for the buy window).
var live_elapsed: float = 0.0
var round_number: int = 0
var match_time: float = 0.0
var is_bomb_planted: bool = false
var bomb_time_left: float = 0.0
var bomb_carrier_id: String = ""
var is_bomb_dropped: bool = false
var bomb_position: Vector3 = Vector3.ZERO
var last_round_winner: int = -1
var last_round_reason: StringName = &""
var events: Array[Dictionary] = []


## [param match_setup] is the contract from orchestration; its MR value overrides the rules'.
func _init(match_setup: MatchSetup, match_rules: MatchRules, home_side: StringName = MatchRules.SIDE_ATTACK) -> void:
	setup = match_setup
	rules = match_rules
	rules.max_rounds = maxi(setup.max_rounds, 1)
	teams.append(_make_team(setup.home_team_id, setup.home_team_name, home_side))
	teams.append(_make_team(setup.away_team_id, setup.away_team_name, MatchRules.other_side(home_side)))


static func _make_team(id: String, display_name: String, side: StringName) -> TeamState:
	var team := TeamState.new()
	team.id = id
	team.display_name = display_name
	team.side = side
	return team


func add_player(id: String, display_name: String, team_index: int, is_human: bool = false) -> PlayerState:
	assert(phase == Phase.WAITING, "players join before the match starts")
	var player := PlayerState.new()
	player.id = id
	player.display_name = display_name
	player.team = team_index
	player.is_human = is_human
	players[id] = player
	teams[team_index].player_ids.append(id)
	return player


func start() -> void:
	if phase != Phase.WAITING:
		return
	var lineup: Dictionary[String, int] = {}
	for player: PlayerState in players.values():
		player.money = rules.start_money
		lineup[player.id] = player.team
	_log("match_started", {"rules": rules.to_dict(), "fixture_id": setup.fixture_id, "lineup": lineup})
	_begin_round()


# --- Queries -------------------------------------------------------------------------------

func get_player(id: String) -> PlayerState:
	return players.get(id, null)


func side_of(player_id: String) -> StringName:
	var player := get_player(player_id)
	return teams[player.team].side if player != null else &""


func team_on_side(side: StringName) -> int:
	return HOME if teams[HOME].side == side else AWAY


func alive_count(team_index: int) -> int:
	var count := 0
	for id: String in teams[team_index].player_ids:
		if players[id].alive:
			count += 1
	return count


func rounds_played() -> int:
	return teams[HOME].score + teams[AWAY].score


func is_overtime() -> bool:
	return round_number > rules.regulation_rounds()


func can_buy(player_id: String) -> bool:
	var player := get_player(player_id)
	if player == null or not player.alive:
		return false
	return phase == Phase.FREEZE or (phase == Phase.LIVE and live_elapsed < rules.buy_time)


func defuse_duration(player_id: String) -> float:
	var player := get_player(player_id)
	return rules.defuse_time_with_kit if player != null and player.has_kit else rules.defuse_time


## Short label such as "Round 3 · 1st half" or "Round 23 · Overtime 1".
func round_label() -> String:
	var section := ""
	if round_number <= rules.max_rounds:
		section = "1st half"
	elif round_number <= rules.regulation_rounds():
		section = "2nd half"
	else:
		var block := floori(float(round_number - rules.regulation_rounds() - 1) / (rules.overtime_max_rounds * 2)) + 1
		section = "Overtime %d" % block
	return "Round %d · %s" % [round_number, section]


# --- Reported events -------------------------------------------------------------------------

func tick(delta: float) -> void:
	if phase == Phase.WAITING or phase == Phase.MATCH_END:
		return
	match_time += delta
	match phase:
		Phase.FREEZE:
			phase_time_left -= delta
			if phase_time_left <= 0.0:
				_set_phase(Phase.LIVE, rules.round_time)
		Phase.LIVE:
			live_elapsed += delta
			if is_bomb_planted:
				bomb_time_left -= delta
				if bomb_time_left <= 0.0:
					bomb_time_left = 0.0
					_log("bomb_detonated", {})
					_end_round(team_on_side(MatchRules.SIDE_ATTACK), MatchRules.REASON_DETONATED)
			else:
				phase_time_left -= delta
				if phase_time_left <= 0.0:
					_end_round(team_on_side(MatchRules.SIDE_DEFENCE), MatchRules.REASON_TIME)
		Phase.ROUND_END:
			phase_time_left -= delta
			if phase_time_left <= 0.0:
				_after_round()


## Buys [param item_id] for [param player_id]. Returns "" on success or a reason it failed.
func buy(player_id: String, item_id: StringName) -> String:
	var player := get_player(player_id)
	if player == null:
		return "unknown player"
	if not ShopCatalog.has_item(item_id):
		return "unknown item"
	if not can_buy(player_id):
		return "buying is closed"
	var restriction := ShopCatalog.side_restriction(item_id)
	if restriction != &"" and restriction != side_of(player_id):
		return "not available to your side"
	var cost := ShopCatalog.price(item_id)
	match ShopCatalog.kind(item_id):
		ShopCatalog.KIND_WEAPON:
			if player.primary == item_id or player.secondary == item_id:
				return "already owned"
		ShopCatalog.KIND_ARMOUR:
			var wants_helmet := item_id == ShopCatalog.ARMOUR_VEST_HELMET
			if player.armour >= ShopCatalog.FULL_ARMOUR and (player.helmet or not wants_helmet):
				return "already owned"
			if player.armour >= ShopCatalog.FULL_ARMOUR and wants_helmet:
				cost = ShopCatalog.HELMET_UPGRADE_PRICE
		ShopCatalog.KIND_KIT:
			if player.has_kit:
				return "already owned"
	if player.money < cost:
		return "not enough money"
	player.money -= cost
	match ShopCatalog.kind(item_id):
		ShopCatalog.KIND_WEAPON:
			var weapon := WeaponCatalog.get_definition(item_id)
			if weapon.category == WeaponDefinition.CATEGORY_PRIMARY:
				player.primary = item_id
			else:
				player.secondary = item_id
		ShopCatalog.KIND_ARMOUR:
			player.armour = ShopCatalog.FULL_ARMOUR
			player.helmet = player.helmet or item_id == ShopCatalog.ARMOUR_VEST_HELMET
		ShopCatalog.KIND_KIT:
			player.has_kit = true
	_log("purchase", {"player": player_id, "item": String(item_id), "cost": cost})
	return ""


## Captures a live shot before resolving damage, including misses.
func record_shot(weapon_id: StringName, shooter_id: String) -> void:
	var shooter := get_player(shooter_id)
	if phase == Phase.LIVE and shooter != null and shooter.alive:
		_log("shot", {"player": shooter_id, "weapon": String(weapon_id)})


## Uses health actually lost after armour and overkill, before the death event fires.
func record_damage(info: DamageInfo, victim_id: String) -> void:
	if phase != Phase.LIVE or info.applied <= 0 or info.cause != DamageInfo.CAUSE_WEAPON:
		return
	var attacker := get_player(info.source_id)
	var victim := get_player(victim_id)
	if attacker != null and victim != null and attacker.team != victim.team:
		_log("damage", {"player": attacker.id, "victim": victim_id, "hp": info.applied,
			"weapon": String(info.weapon_id), "headshot": info.is_headshot()})


## Records a death. [param killer_id] may be empty (world) or the victim (suicide).
## Returns false if ignored (unknown/dead victim, or not during a live/ending round).
func record_kill(victim_id: String, killer_id: String, weapon_id: StringName, headshot: bool,
		position: Vector3 = Vector3.ZERO) -> bool:
	var victim := get_player(victim_id)
	if victim == null or not victim.alive or not (phase == Phase.LIVE or phase == Phase.ROUND_END):
		return false
	victim.alive = false
	victim.deaths += 1
	var killer := get_player(killer_id)
	var reward := 0
	if killer != null and killer != victim and killer.team != victim.team:
		killer.kills += 1
		reward = ShopCatalog.KILL_REWARD
		_add_money(killer, reward)
	_log("kill", {"victim": victim_id, "killer": killer_id, "weapon": String(weapon_id),
		"headshot": headshot, "reward": reward,
		"teamkill": killer != null and killer != victim and killer.team == victim.team})
	if victim_id == bomb_carrier_id and not is_bomb_planted:
		bomb_carrier_id = ""
		is_bomb_dropped = true
		bomb_position = position
		_log("bomb_dropped", {"player": victim_id})
		bomb_dropped.emit(position)
	player_killed.emit(victim_id, killer_id)
	if phase == Phase.LIVE:
		_check_elimination()
	return true


func pick_up_bomb(player_id: String) -> bool:
	var player := get_player(player_id)
	if not is_bomb_dropped or player == null or not player.alive \
			or side_of(player_id) != MatchRules.SIDE_ATTACK:
		return false
	is_bomb_dropped = false
	bomb_carrier_id = player_id
	_log("bomb_picked_up", {"player": player_id})
	bomb_picked_up.emit(player_id)
	return true


## Completes a plant (the runtime checks the bombsite and the hold time).
func plant_bomb(player_id: String, position: Vector3) -> bool:
	var player := get_player(player_id)
	if phase != Phase.LIVE or is_bomb_planted or player_id != bomb_carrier_id \
			or player == null or not player.alive:
		return false
	is_bomb_planted = true
	bomb_time_left = rules.bomb_timer
	bomb_position = position
	bomb_carrier_id = ""
	for id: String in teams[player.team].player_ids:
		_add_money(players[id], rules.plant_bonus)
	_log("bomb_planted", {"player": player_id})
	bomb_planted.emit(player_id)
	return true


## Completes a defuse (the runtime checks distance and the hold time).
func defuse_bomb(player_id: String) -> bool:
	var player := get_player(player_id)
	if phase != Phase.LIVE or not is_bomb_planted or player == null or not player.alive \
			or side_of(player_id) != MatchRules.SIDE_DEFENCE:
		return false
	_log("bomb_defused", {"player": player_id})
	bomb_defused.emit(player_id)
	_end_round(player.team, MatchRules.REASON_DEFUSED)
	return true


## Lets the runtime write back armour left at the end of a round (survivors keep it).
func set_player_armour(player_id: String, armour: int, helmet: bool) -> void:
	var player := get_player(player_id)
	if player != null:
		player.armour = clampi(armour, 0, ShopCatalog.FULL_ARMOUR)
		player.helmet = helmet and player.armour > 0


func result() -> MatchResult:
	var match_result := MatchResult.create(setup.fixture_id, teams[HOME].score, teams[AWAY].score,
		MatchResult.SOURCE_FPS_RUNTIME)
	match_result.map_id = setup.map_id
	return match_result


## Index of the team that has won the match, or -1.
func match_winner() -> int:
	var home := teams[HOME].score
	var away := teams[AWAY].score
	if maxi(home, away) >= rules.winning_score(mini(home, away)):
		return HOME if home > away else AWAY
	return -1


# --- Internals -------------------------------------------------------------------------------

func _begin_round() -> void:
	round_number += 1
	live_elapsed = 0.0
	is_bomb_planted = false
	is_bomb_dropped = false
	bomb_time_left = 0.0
	for player: PlayerState in players.values():
		player.alive = true
	bomb_carrier_id = _choose_bomb_carrier()
	_set_phase(Phase.FREEZE, rules.freeze_time)
	_log("round_started", {"attack": teams[team_on_side(MatchRules.SIDE_ATTACK)].id, "carrier": bomb_carrier_id})
	round_started.emit(round_number)


## Humans carry first (so a lone human attacker can always plant), then roster order.
func _choose_bomb_carrier() -> String:
	var ids := teams[team_on_side(MatchRules.SIDE_ATTACK)].player_ids
	for id: String in ids:
		if players[id].is_human:
			return id
	return ids[0] if not ids.is_empty() else ""


func _check_elimination() -> void:
	var attack := team_on_side(MatchRules.SIDE_ATTACK)
	var defence := team_on_side(MatchRules.SIDE_DEFENCE)
	if alive_count(defence) == 0:
		_end_round(attack, MatchRules.REASON_ELIMINATION)
	elif alive_count(attack) == 0 and not is_bomb_planted:
		_end_round(defence, MatchRules.REASON_ELIMINATION)


func _end_round(winner: int, reason: StringName) -> void:
	if phase != Phase.LIVE:
		return
	var loser := 1 - winner
	teams[winner].score += 1
	teams[winner].loss_streak = maxi(teams[winner].loss_streak - 1, 0)
	teams[loser].loss_streak += 1
	for id: String in teams[winner].player_ids:
		_add_money(players[id], rules.win_rewards.get(reason, 0))
	for id: String in teams[loser].player_ids:
		_add_money(players[id], rules.loss_bonus_for(teams[loser].loss_streak))
	last_round_winner = winner
	last_round_reason = reason
	_set_phase(Phase.ROUND_END, rules.round_end_delay)
	_log("round_ended", {"winner": teams[winner].id, "winner_team": winner, "reason": String(reason),
		"score": [teams[HOME].score, teams[AWAY].score]})
	round_ended.emit(winner, reason)


func _after_round() -> void:
	for player: PlayerState in players.values():
		if not player.alive:
			player.strip_gear()
	if match_winner() >= 0:
		_set_phase(Phase.MATCH_END, 0.0)
		var final := result()
		_log("match_ended", {"score": [final.home_score, final.away_score]})
		final.events = events.duplicate(true)
		match_ended.emit(final)
		return
	var played := rounds_played()
	var regulation := rules.regulation_rounds()
	if played == rules.max_rounds:
		_switch_sides(rules.start_money)
	elif played == regulation:
		_reset_economy(rules.overtime_start_money)
	elif played > regulation and (played - regulation) % rules.overtime_max_rounds == 0:
		_switch_sides(rules.overtime_start_money)
	_begin_round()


func _switch_sides(money: int) -> void:
	for team: TeamState in teams:
		team.side = MatchRules.other_side(team.side)
	_reset_economy(money)
	_log("sides_switched", {"home_side": String(teams[HOME].side)})
	sides_switched.emit()


func _reset_economy(money: int) -> void:
	for team: TeamState in teams:
		team.loss_streak = 0
	for player: PlayerState in players.values():
		player.strip_gear()
		player.money = mini(money, rules.max_money)


func _add_money(player: PlayerState, amount: int) -> void:
	player.money = clampi(player.money + amount, 0, rules.max_money)


func _set_phase(new_phase: Phase, duration: float) -> void:
	phase = new_phase
	phase_time_left = duration
	phase_changed.emit(new_phase)


func _log(type: String, data: Dictionary) -> void:
	var entry := {"type": type, "t": snappedf(match_time, 0.01), "round": round_number}
	entry.merge(data)
	events.append(entry)
