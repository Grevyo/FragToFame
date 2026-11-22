class_name SimEconomy
extends RefCounted
## Each player's own money and equipment in a simulated match, with the same prices, rewards and
## weapons as a played one: prices from [ShopCatalog], money rules from [MatchRules], weapons and
## grenades from [WeaponCatalog] and [EquipmentCatalog]. Pure data and rules; no nodes.
##
## Every round the leader makes the team's call (pistol, eco, force, full) from what the players
## hold between them; then each player buys for their role: a sniper's rifle, the entry's flashes,
## the support's smokes and fire, a kit for some defenders. Players with money to spare drop a rifle
## for a teammate who cannot afford one (team players do; lone wolves rarely). Survivors keep what
## they carried; the dead start again with the sidearm everyone spawns with.

const ATTACK_RIFLE: StringName = WeaponCatalog.AK47
const DEFENCE_RIFLE: StringName = WeaponCatalog.M4A1
const SNIPER_RIFLE: StringName = WeaponCatalog.L118A1
const CHEAP_SNIPER: StringName = WeaponCatalog.M24
const CHEAP_RIFLE: StringName = WeaponCatalog.SKS
const HEAVY_PISTOL: StringName = WeaponCatalog.DESERT_EAGLE
const BETTER_PISTOL: StringName = WeaponCatalog.MK23
const SIDEARM: StringName = WeaponCatalog.DEFAULT_SECONDARY
## Grenades each role reaches for first, most wanted first.
const UTILITY_BY_ROLE: Dictionary[StringName, Array] = {
	&"support": [EquipmentCatalog.SMOKE, EquipmentCatalog.FLASH, EquipmentCatalog.FIRE, EquipmentCatalog.FLASH],
	&"igl": [EquipmentCatalog.SMOKE, EquipmentCatalog.FLASH, EquipmentCatalog.FIRE],
	&"entry": [EquipmentCatalog.FLASH, EquipmentCatalog.FLASH, EquipmentCatalog.FRAG],
	&"lurker": [EquipmentCatalog.SMOKE, EquipmentCatalog.FLASH],
	&"sniper": [EquipmentCatalog.FLASH, EquipmentCatalog.SMOKE],
	&"rifler": [EquipmentCatalog.FLASH, EquipmentCatalog.SMOKE, EquipmentCatalog.FRAG],
}


## What the last [method buy] paid for, in order: {"buyer", "for" (the player who gets it; a
## drop when it is not the buyer), "item"}. A played match carries these out in its own shop.
static var receipts: Array[Dictionary] = []


static func rules() -> MatchRules:
	return MatchRules.competitive()


## What a full buy costs a player: a rifle, vest and helmet, and some utility.
static func full_buy_cost(player: MatchEngine.SimPlayer, side: String) -> int:
	return ShopCatalog.price(_rifle_for(player, side, 1000000)) + ShopCatalog.price(ShopCatalog.ARMOUR_VEST_HELMET) + 600


## Resets a player at the start of a half (or overtime): money and only the sidearm.
static func start_half(player: MatchEngine.SimPlayer, money: int) -> void:
	player.money = money
	_strip(player)


## The leader's call for the round from the money the players hold between them.
static func call_buy(team: MatchEngine.SimTeam, side: String, pistol: bool, their_money: float) -> StringName:
	if pistol:
		return &"pistol"
	var spare := 0
	var short := 0
	var ready := 0
	for player: MatchEngine.SimPlayer in team.players:
		var have := player.money + (ShopCatalog.price(player.primary) if not player.primary.is_empty() else 0)
		var need := full_buy_cost(player, side)
		if have >= need:
			ready += 1
			spare += have - need
		else:
			short += need - have
	# Drops can cover a teammate or two.
	if ready >= team.players.size() - 1 or spare >= short:
		return &"full"
	var streak := team.loss_streak
	# A force: after a run of losses (the bonus keeps the next round safe), or against a team
	# that is on an eco itself.
	var average := 0.0
	for player: MatchEngine.SimPlayer in team.players:
		average += player.money
	average /= maxf(team.players.size(), 1.0)
	if average >= 2000.0 and (streak >= 3 or their_money < 2000.0):
		return &"force"
	return &"eco"


## Every player buys for the call; then drops. Returns the money spent.
static func buy(team: MatchEngine.SimTeam, side: String, call: StringName) -> int:
	receipts.clear()
	var spent := 0
	var order := team.players.duplicate()
	# Snipers and entries choose first; supports last (they drop and buy utility).
	order.sort_custom(func(a: MatchEngine.SimPlayer, b: MatchEngine.SimPlayer) -> bool: return _priority(a) > _priority(b))
	for player: MatchEngine.SimPlayer in order:
		spent += _buy_player(player, side, call)
	if call == &"full" or call == &"force":
		spent += _drops(team, side)
	if side == "defence" and call != &"eco":
		spent += _kits(team)
	team.buy = call
	return spent


## Money for the round's end: win or loss, kills by weapon, plant bonus.
static func settle(team: MatchEngine.SimTeam, won: bool, how: String, attacking: bool, planted: bool) -> void:
	var match_rules := rules()
	var reward := 0
	if won:
		reward = int(match_rules.win_rewards.get(_reason(how), 3100))
	else:
		reward = match_rules.loss_bonus_for(team.loss_streak + 1)
	for player: MatchEngine.SimPlayer in team.players:
		var income := reward
		for weapon: StringName in player.round_kill_weapons:
			income += ShopCatalog.kill_reward(weapon)
		if attacking and planted:
			income += match_rules.plant_bonus
		player.money = clampi(player.money + income, 0, match_rules.max_money)
		if not player.alive:
			_strip(player)
		player.round_kill_weapons.clear()


## After the round, survivors on the winning side without a rifle pick one up from the dead.
static func pick_up(team: MatchEngine.SimTeam, dropped: Array[StringName]) -> void:
	var left := dropped.duplicate()
	for player: MatchEngine.SimPlayer in team.players:
		if left.is_empty():
			return
		if player.alive and player.primary.is_empty():
			player.primary = left.pop_back()


static func _reason(how: String) -> StringName:
	match how:
		"detonated":
			return MatchRules.REASON_DETONATED
		"defused":
			return MatchRules.REASON_DEFUSED
		"time":
			return MatchRules.REASON_TIME
	return MatchRules.REASON_ELIMINATION


static func _strip(player: MatchEngine.SimPlayer) -> void:
	player.primary = &""
	player.secondary = SIDEARM
	player.armour = 0
	player.helmet = false
	player.kit = false
	player.grenades.clear()


static func _priority(player: MatchEngine.SimPlayer) -> int:
	return {&"sniper": 4, &"entry": 3, &"lurker": 2, &"rifler": 2, &"igl": 1, &"support": 0}.get(player.role, 1)


static func _rifle_for(player: MatchEngine.SimPlayer, side: String, money: int) -> StringName:
	if player.role == &"sniper":
		if money >= ShopCatalog.price(SNIPER_RIFLE):
			return SNIPER_RIFLE
		if money >= ShopCatalog.price(CHEAP_SNIPER) + 650:
			return CHEAP_SNIPER
	return ATTACK_RIFLE if side == "attack" else DEFENCE_RIFLE


static func _spend(player: MatchEngine.SimPlayer, item: StringName, receiver: MatchEngine.SimPlayer = null) -> int:
	var price := ShopCatalog.price(item)
	if price > player.money:
		return 0
	player.money -= price
	receipts.append({"buyer": player.id, "for": (receiver if receiver != null else player).id, "item": item})
	return price


static func _buy_player(player: MatchEngine.SimPlayer, side: String, call: StringName) -> int:
	var spent := 0
	match call:
		&"pistol":
			# Entries and riflers take a vest; supports and leaders buy utility; others a better pistol.
			if player.role in [&"entry", &"rifler", &"lurker"]:
				spent += _armour(player, false)
			elif player.role == &"sniper":
				if player.money >= ShopCatalog.price(BETTER_PISTOL) + 200:
					spent += _spend(player, BETTER_PISTOL)
					player.secondary = BETTER_PISTOL
			spent += _utility(player, 2)
		&"full":
			if player.primary.is_empty() or (player.role == &"sniper" and player.primary != SNIPER_RIFLE \
					and player.money >= ShopCatalog.price(SNIPER_RIFLE) + 1000):
				var rifle := _rifle_for(player, side, player.money - 1000)
				if player.money >= ShopCatalog.price(rifle):
					spent += _spend(player, rifle)
					player.primary = rifle
			spent += _armour(player, true)
			spent += _utility(player, 4)
		&"force":
			if player.primary.is_empty():
				var choice := CHEAP_RIFLE if player.money >= ShopCatalog.price(CHEAP_RIFLE) + 650 else &""
				if choice.is_empty() and player.money >= ShopCatalog.price(HEAVY_PISTOL) + 650:
					spent += _spend(player, HEAVY_PISTOL)
					player.secondary = HEAVY_PISTOL
				elif not choice.is_empty():
					spent += _spend(player, choice)
					player.primary = choice
			spent += _armour(player, false)
			spent += _utility(player, 1)
		_:
			# Eco: only money above next round's full buy is spent (a pistol, maybe a vest).
			var spare := player.money - full_buy_cost(player, side)
			if spare >= ShopCatalog.price(HEAVY_PISTOL) and player.secondary == SIDEARM and player.skill(&"aim") >= 60:
				spent += _spend(player, HEAVY_PISTOL)
				player.secondary = HEAVY_PISTOL
				spare -= ShopCatalog.price(HEAVY_PISTOL)
			if spare >= ShopCatalog.price(ShopCatalog.ARMOUR_VEST) and player.armour <= 0:
				spent += _armour(player, false)
	return spent


static func _armour(player: MatchEngine.SimPlayer, helmet: bool) -> int:
	if player.armour >= ShopCatalog.FULL_ARMOUR and (player.helmet or not helmet):
		return 0
	if helmet and player.armour >= ShopCatalog.FULL_ARMOUR and not player.helmet and player.money >= ShopCatalog.HELMET_UPGRADE_PRICE:
		player.money -= ShopCatalog.HELMET_UPGRADE_PRICE
		player.helmet = true
		receipts.append({"buyer": player.id, "for": player.id, "item": ShopCatalog.ARMOUR_VEST_HELMET})
		return ShopCatalog.HELMET_UPGRADE_PRICE
	var item := ShopCatalog.ARMOUR_VEST_HELMET if helmet and player.money >= ShopCatalog.price(ShopCatalog.ARMOUR_VEST_HELMET) \
		else ShopCatalog.ARMOUR_VEST
	var spent := _spend(player, item)
	if spent > 0:
		player.armour = ShopCatalog.FULL_ARMOUR
		player.helmet = player.helmet or item == ShopCatalog.ARMOUR_VEST_HELMET
	return spent


## Grenades for the player's role, up to [param most]; a player with more utility skill fills
## more of the list.
static func _utility(player: MatchEngine.SimPlayer, most: int) -> int:
	var wanted: Array = UTILITY_BY_ROLE.get(player.role, UTILITY_BY_ROLE[&"rifler"])
	var limit := mini(most, maxi(1, roundi(wanted.size() * (0.5 + player.skill(&"utility") / 100.0))))
	var spent := 0
	for item: Variant in wanted.slice(0, limit):
		var id := item as StringName
		if player.grenades.size() >= EquipmentCatalog.UTILITY_CARRY_LIMIT:
			break
		if player.grenades.count(id) >= EquipmentCatalog.carry_limit(id):
			continue
		var price := _spend(player, id)
		if price > 0:
			player.grenades.append(id)
			spent += price
	return spent


static func _drops(team: MatchEngine.SimTeam, side: String) -> int:
	var spent := 0
	for needy: MatchEngine.SimPlayer in team.players:
		if not needy.primary.is_empty():
			continue
		for giver: MatchEngine.SimPlayer in team.players:
			if giver == needy or giver.trait_strength(&"tr_lone_wolf") > 0:
				continue
			var rifle := ATTACK_RIFLE if side == "attack" else DEFENCE_RIFLE
			if giver.money >= ShopCatalog.price(rifle) + 200:
				spent += _spend(giver, rifle, needy)
				needy.primary = rifle
				break
	return spent


## One or two defenders buy a kit (the anchors-to-be: the most patient players with money).
static func _kits(team: MatchEngine.SimTeam) -> int:
	var spent := 0
	var kits := 0
	for player: MatchEngine.SimPlayer in team.players:
		kits += 1 if player.kit else 0
	var order := team.players.duplicate()
	order.sort_custom(func(a: MatchEngine.SimPlayer, b: MatchEngine.SimPlayer) -> bool: return a.money > b.money)
	for player: MatchEngine.SimPlayer in order:
		if kits >= 2:
			break
		if not player.kit and player.money >= ShopCatalog.price(ShopCatalog.DEFUSE_KIT) + 200:
			spent += _spend(player, ShopCatalog.DEFUSE_KIT)
			player.kit = true
			kits += 1
	return spent
