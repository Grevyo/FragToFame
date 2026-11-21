extends TestSuite
## Individual economy and utility (Milestone 21 stage D): each player's money, weapons, armour and
## grenades with the game's own prices and rules, drops and saves, and grenades thrown in rounds.

const MAP_ID: String = "map_f2f_kilnmarket"


func suite_name() -> String:
	return "Simulated economy and utility"


func run() -> void:
	_test_buying()
	_test_calls()
	_test_settling()
	SimMap.clear_cache()
	var map := SimMap.for_map(MAP_ID)
	if map != null:
		_test_in_rounds(map)
	else:
		check(false, "the test map has a simulation graph")


func _team(name: String, level: float, money: int, traits: Dictionary = {}) -> MatchEngine.SimTeam:
	var team := MatchEngine.SimTeam.new()
	team.id = name
	team.name = name
	var roles: Array[StringName] = [&"igl", &"sniper", &"entry", &"lurker", &"support"]
	for i: int in 5:
		var player := MatchEngine.SimPlayer.new()
		player.id = "%s_%d" % [name, i]
		player.name = player.id
		player.role = roles[i]
		player.traits = traits.duplicate()
		for key: StringName in CareerCatalog.ABILITIES:
			player.skills[key] = roundi(level)
		SimEconomy.start_half(player, money)
		team.players.append(player)
	return team


func _test_buying() -> void:
	section("Buying")
	var pistol := _team("P", 60.0, SimEconomy.rules().start_money)
	SimEconomy.buy(pistol, "attack", &"pistol")
	var entry := pistol.players[2]
	var support := pistol.players[4]
	check(pistol.players.all(func(p: MatchEngine.SimPlayer) -> bool: return p.money >= 0 and p.primary.is_empty()),
		"pistol round: nobody overspends or buys a rifle")
	check(entry.armour == ShopCatalog.FULL_ARMOUR and not support.grenades.is_empty(), "the entry takes a vest, the support utility")
	var rich := _team("R", 60.0, 7000)
	SimEconomy.buy(rich, "attack", &"full")
	var sniper := rich.players[1]
	check(sniper.primary == SimEconomy.SNIPER_RIFLE and rich.players[2].primary == WeaponCatalog.AK47,
		"full buy: the sniper takes the L118A1, riflers the AK-47 on attack")
	check(rich.players.all(func(p: MatchEngine.SimPlayer) -> bool: return p.armour == 100 and p.helmet),
		"full buy: everyone has a vest and helmet")
	check(rich.players[4].grenades.has(EquipmentCatalog.SMOKE) and rich.players[2].grenades.has(EquipmentCatalog.FLASH),
		"the support carries smokes, the entry flashes")
	var defence := _team("D", 60.0, 7000)
	SimEconomy.buy(defence, "defence", &"full")
	var kits := defence.players.filter(func(p: MatchEngine.SimPlayer) -> bool: return p.kit).size()
	check(defence.players[2].primary == WeaponCatalog.M4A1 and kits >= 1 and kits <= 2, "defenders take the M4A1 and one or two kits")
	var spent_total := 0
	for player: MatchEngine.SimPlayer in rich.players:
		spent_total += 7000 - player.money
	var expected := ShopCatalog.price(SimEconomy.SNIPER_RIFLE) + 4 * ShopCatalog.price(WeaponCatalog.AK47) + 5 * ShopCatalog.price(ShopCatalog.ARMOUR_VEST_HELMET)
	check(spent_total >= expected, "prices are the shop's own (spent %d, guns and armour alone %d)" % [spent_total, expected])
	# Drops: one poor teammate gets a rifle from a rich one; a lone wolf keeps their money.
	var mixed := _team("M", 60.0, 9000)
	mixed.players[3].money = 400
	SimEconomy.buy(mixed, "attack", &"full")
	check(not mixed.players[3].primary.is_empty(), "a teammate drops a rifle for the player who cannot afford one")
	var wolves := _team("W", 60.0, 9000, {&"tr_lone_wolf": 1})
	wolves.players[3].money = 400
	SimEconomy.buy(wolves, "attack", &"full")
	check(wolves.players[3].primary.is_empty(), "lone wolves do not drop")


func _test_calls() -> void:
	section("The leader's buy call")
	check(SimEconomy.call_buy(_team("A", 60.0, 900), "attack", true, 900.0) == &"pistol", "the first round is a pistol round")
	check(SimEconomy.call_buy(_team("B", 60.0, 5200), "attack", false, 5000.0) == &"full", "enough for everyone: full buy")
	check(SimEconomy.call_buy(_team("C", 60.0, 1500), "attack", false, 5000.0) == &"eco", "short of money: eco")
	var losing := _team("F", 60.0, 2600)
	losing.loss_streak = 3
	check(SimEconomy.call_buy(losing, "attack", false, 5000.0) == &"force", "after a run of losses with some money: force")
	var against_eco := _team("G", 60.0, 2600)
	check(SimEconomy.call_buy(against_eco, "attack", false, 1200.0) == &"force", "against a team on an eco: force")


func _test_settling() -> void:
	section("Round rewards")
	var rules := SimEconomy.rules()
	var team := _team("S", 60.0, 7000)
	SimEconomy.buy(team, "attack", &"full")
	for player: MatchEngine.SimPlayer in team.players:
		player.money = 1000
	team.players[0].alive = false
	team.players[1].round_kill_weapons = [WeaponCatalog.AK47, EquipmentCatalog.KNIFE]
	SimEconomy.settle(team, true, "detonated", true, true)
	var win := int(rules.win_rewards[MatchRules.REASON_DETONATED])
	check(team.players[2].money == 1000 + win + rules.plant_bonus, "a detonation win pays the win reward and the plant bonus")
	check(team.players[1].money == 1000 + win + rules.plant_bonus + ShopCatalog.KILL_REWARD + ShopCatalog.kill_reward(EquipmentCatalog.KNIFE),
		"kills pay by weapon (a knife kill pays more)")
	check(team.players[0].primary.is_empty() and team.players[0].armour == 0 and not team.players[2].primary.is_empty(),
		"the dead lose their kit; survivors keep theirs")
	var losers := _team("L", 60.0, 14900)
	losers.loss_streak = 4
	SimEconomy.settle(losers, false, "eliminated", false, false)
	check(losers.players[0].money == rules.max_money, "money never passes the cap")
	var broke := _team("K", 60.0, 0)
	SimEconomy.settle(broke, false, "eliminated", false, false)
	check(broke.players[0].money == rules.loss_bonus_for(1), "a first loss pays the first loss bonus")


func _test_in_rounds(map: SimMap) -> void:
	section("Money and grenades over a map")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var engine := MatchEngine.new(rng, 8)
	engine.sim_map = map
	var home := _team("H", 65.0, 0)
	var away := _team("A", 65.0, 0)
	engine.play_map(home, away)
	var totals: Dictionary[String, int] = {}
	for team: MatchEngine.SimTeam in [home, away]:
		for player: MatchEngine.SimPlayer in team.players:
			for key: String in ["utility_thrown", "utility_damage", "enemies_flashed", "flash_assists"]:
				totals[key] = int(totals.get(key, 0)) + int(player.counts[key])
	check(totals["utility_thrown"] > 20 and totals["enemies_flashed"] > 0 and totals["utility_damage"] > 0,
		"grenades get thrown, flashes blind, frags and fire hurt (%s)" % totals)
	var monies: Dictionary[int, bool] = {}
	var within := true
	for player: MatchEngine.SimPlayer in home.players + away.players:
		monies[player.money] = true
		within = within and player.money >= 0 and player.money <= SimEconomy.rules().max_money
	check(within, "everyone's money stays within the rules")
	check(monies.size() > 1, "each player's money is their own")
	# Better utility players blind more of the enemies they flash.
	var flashes := [0.0, 0.0]
	for variant: int in 2:
		var throwers := _team("U", 65.0, 0)
		for player: MatchEngine.SimPlayer in throwers.players:
			player.skills[&"utility"] = 90 if variant == 0 else 25
		var dice := RandomNumberGenerator.new()
		dice.seed = 30
		var run := MatchEngine.new(dice, 8)
		run.sim_map = map
		run.play_map(throwers, _team("O", 65.0, 0))
		var thrown := 0
		var caught := 0
		for player: MatchEngine.SimPlayer in throwers.players:
			thrown += int(player.counts["utility_thrown"])
			caught += int(player.counts["enemies_flashed"])
		flashes[variant] = float(caught) / maxf(thrown, 1.0)
	check(flashes[0] > flashes[1], "skilled throwers catch more enemies per grenade (%.2f vs %.2f)" % flashes)
