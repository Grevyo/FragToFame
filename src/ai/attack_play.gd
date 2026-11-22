class_name AttackPlay
extends RefCounted
## How a team of attacking bots takes a site this round: who gathers where, who throws what and
## when, and who pushes first. Several styles, so rounds do not all look alike:
##
## - RUSH: everyone runs in at once (no utility).
## - DEFAULT: spread out on the way in; at the entrance one player flashes off the cuff and a
##   teammate peeks off it.
## - EXECUTE: gather, smokes in parallel, the flash once they bloom, then everyone goes.
## - EXECUTE_TOGETHER: gather, everybody throws at once and pushes as they throw (hurried
##   throws: they miss more).
## - SUPPORTED_ENTRY: supports throw from the gathering spot while an entry pair goes in off the
##   first flash; the supports follow.
## - SPLIT: two groups gather at two entrances and push at the same moment.
##
## In every style the first two in form an entry pair: the trader walks shoulder to shoulder with
## the entry so they peek the entrance together (a double peek). Throws are solved against the map
## ([UtilityLineup]) and thrown by the bots; one that cannot be made from the gathering spot is
## tried from the doorway. FPS runtime only (bots and physics), no career data; Milestone 7 C's
## next part maps the career round plans (default, execute, split, rush) onto these styles.

enum Style { RUSH, DEFAULT, EXECUTE, EXECUTE_TOGETHER, SUPPORTED_ENTRY, SPLIT }
enum Phase { APPROACH, GATHER, UTILITY, GO }

const STYLE_NAMES: Dictionary[Style, String] = {
	Style.RUSH: "rush", Style.DEFAULT: "default", Style.EXECUTE: "execute",
	Style.EXECUTE_TOGETHER: "execute together", Style.SUPPORTED_ENTRY: "supported entry", Style.SPLIT: "split",
}
## How hurried each style's throws are (1 = the thrower's own pace; lower = faster and wider).
const HURRY: Dictionary[Style, float] = {
	Style.RUSH: 0.4, Style.DEFAULT: 0.6, Style.EXECUTE: 1.0, Style.EXECUTE_TOGETHER: 0.5,
	Style.SUPPORTED_ENTRY: 0.85, Style.SPLIT: 0.9,
}
const GATHERED_RADIUS: float = 6.0
const GATHER_LIMIT: float = 14.0
## Utility time allowed: this much plus a multiple of the slowest thrower's line-up time.
const UTILITY_BASE: float = 6.0
const UTILITY_PER_LINEUP: float = 2.5
const GO_AFTER_FLASH: float = 0.45
const SMOKE_BLOOM: float = 1.2
## A lane on DEFAULT flashes once its lead is this close to the entrance, with a flasher this close.
const PEEK_RANGE: float = 9.0
const FLASHER_RANGE: float = 16.0
const DEFAULT_PEEK_LIMIT: float = 7.0
## A doorway thrower gives up walking after this long.
const WALK_LIMIT: float = 6.0
const LINEUP_TOLERANCE: float = 2.5
## The trader walks this far to the side of the entry.
const PAIR_OFFSET: float = 1.3


class Lane extends RefCounted:
	var plan: SiteExecute
	var bots: Array[BotController] = []
	var phase: Phase = Phase.GATHER
	var phase_time: float = 0.0
	## Throws still to hand out: {utility, target}; bot ID -> throw it walks to the doorway for.
	var throws: Array[Dictionary] = []
	var walkers: Dictionary[String, Dictionary] = {}
	## Bots let go to push (bot ID -> true) and which bot ID threw which pending throw.
	var released: Dictionary[String, bool] = {}
	var smoked_at: float = -1.0
	var flashed_at: float = -1.0
	var flasher_id: String = ""
	var entry: BotController = null
	var trader: BotController = null
	## Bots that have reached this lane's entrance.
	var through: Dictionary[String, bool] = {}

	func living() -> Array[BotController]:
		return bots.filter(func(bot: BotController) -> bool: return bot.is_alive())


var style: Style = Style.EXECUTE
var lanes: Array[Lane] = []
var site: String = ""
## Bot ID of the bomb carrier (kept off the entry: the bomb goes in behind the first two).
var carrier_id: String = ""
var space: PhysicsDirectSpaceState3D = null
var rng: RandomNumberGenerator = null


## A style for this round, weighed from what the team has: no utility means a rush or a default;
## a split needs four players and a second way in.
static func choose_style(dice: RandomNumberGenerator, attackers: int, utility: int, flashes: int, entrances: int) -> Style:
	var weights: Dictionary[Style, float] = {Style.RUSH: 1.0, Style.DEFAULT: 2.0}
	if utility >= 2:
		weights[Style.EXECUTE] = 3.0
		weights[Style.EXECUTE_TOGETHER] = 2.0
		weights[Style.SUPPORTED_ENTRY] = 2.0 if attackers >= 3 else 0.0
		weights[Style.SPLIT] = 2.0 if attackers >= 4 and entrances >= 2 else 0.0
	if flashes == 0:
		weights[Style.DEFAULT] = 1.0
	var total := 0.0
	for weight: float in weights.values():
		total += weight
	var roll := dice.randf() * total
	for key: Style in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return Style.DEFAULT


## The play of [param chosen] on site [param letter] for [param attackers]. Null when the map has
## no plan for the site (no simulation graph): the squad then walks straight in.
static func create(chosen: Style, map: SimMap, letter: String, holds: Array, attackers: Array[BotController],
		world: PhysicsDirectSpaceState3D, dice: RandomNumberGenerator, bomb_carrier: String = "") -> AttackPlay:
	var main := SiteExecute.plan(map, letter, holds)
	if main == null or attackers.is_empty():
		return null
	var play := AttackPlay.new()
	play.style = chosen
	play.site = letter
	play.space = world
	play.rng = dice
	play.carrier_id = bomb_carrier
	var second: SiteExecute = null
	if chosen == Style.SPLIT:
		for other: String in play._other_entrances(map, letter, main.entrance_id):
			second = SiteExecute.plan(map, letter, holds, other)
			if second != null:
				break
		if second == null or attackers.size() < 2:
			play.style = Style.EXECUTE
	if play.style == Style.SPLIT:
		var half := ceili(attackers.size() / 2.0)
		play._add_lane(main, attackers.slice(0, half))
		play._add_lane(second, attackers.slice(half))
	else:
		play._add_lane(main, attackers)
	return play


## The site's other ways in, nearest to attack spawn first.
func _other_entrances(map: SimMap, letter: String, taken: String) -> Array[String]:
	var spawn := map.spawn("attack")
	var list: Array[String] = []
	for id: String in map.entrances("site_" + letter):
		if id != taken and map.distance(spawn, id) >= 0.0:
			list.append(id)
	list.sort_custom(func(x: String, y: String) -> bool: return map.distance(spawn, x) < map.distance(spawn, y))
	return list


func _add_lane(take: SiteExecute, members: Array[BotController]) -> void:
	var lane := Lane.new()
	lane.plan = take
	lane.bots = members
	match style:
		Style.RUSH:
			lane.phase = Phase.GO
		Style.DEFAULT:
			lane.phase = Phase.APPROACH
		_:
			lane.phase = Phase.GATHER
	if lane.phase == Phase.GO:
		for bot: BotController in members:
			lane.released[bot.bot_id] = true
	# What this lane throws. A split lane keeps to its own entrance (the other lane is coming in
	# through the rotation); a supported entry flashes first for the pair going in.
	var smokes := take.smokes.slice(0, 1) if style == Style.SPLIT else take.smokes
	if style == Style.SUPPORTED_ENTRY and take.flash != Vector3.INF:
		lane.throws.append({"utility": EquipmentCatalog.FLASH, "target": take.flash})
	if style != Style.RUSH and style != Style.DEFAULT:
		for point: Vector3 in smokes:
			lane.throws.append({"utility": EquipmentCatalog.SMOKE, "target": point})
		if take.fire != Vector3.INF and style != Style.SPLIT:
			lane.throws.append({"utility": EquipmentCatalog.FIRE, "target": take.fire})
		if take.flash != Vector3.INF and style != Style.SUPPORTED_ENTRY:
			lane.throws.append({"utility": EquipmentCatalog.FLASH, "target": take.flash})
	lanes.append(lane)


## Advances the play by [param delta] seconds. [param cut_short] (contact, the bomb dropped or
## planted, the clock running down) sends everyone in at once.
func update(delta: float, cut_short: bool) -> void:
	for lane: Lane in lanes:
		lane.phase_time += delta
		if lane.living().is_empty():
			lane.phase = Phase.GO
		if cut_short and lane.phase != Phase.GO:
			_go(lane)
	match style:
		Style.SPLIT:
			_update_split()
		_:
			for lane: Lane in lanes:
				_update_lane(lane)
	for lane: Lane in lanes:
		_update_pair(lane)


func _update_lane(lane: Lane) -> void:
	match lane.phase:
		Phase.GATHER:
			if _gathered(lane) or lane.phase_time > GATHER_LIMIT:
				_start_utility(lane)
		Phase.UTILITY:
			_update_utility(lane)
		Phase.APPROACH:
			_update_default(lane)


## Both lanes gather, throw and go together: neither goes in alone.
func _update_split() -> void:
	var all_gathered := true
	for lane: Lane in lanes:
		if lane.phase == Phase.GATHER and not _gathered(lane) and lane.phase_time <= GATHER_LIMIT:
			all_gathered = false
	if all_gathered:
		for lane: Lane in lanes:
			if lane.phase == Phase.GATHER:
				_start_utility(lane)
	var all_ready := true
	for lane: Lane in lanes:
		if lane.phase == Phase.UTILITY:
			_hand_out(lane)
			if not _lane_ready(lane):
				all_ready = false
	if all_ready:
		for lane: Lane in lanes:
			if lane.phase == Phase.UTILITY:
				_go(lane)


func _gathered(lane: Lane) -> bool:
	return lane.living().all(func(bot: BotController) -> bool:
		return _flat(bot.global_position, lane.plan.staging) <= GATHERED_RADIUS)


func _start_utility(lane: Lane) -> void:
	lane.phase = Phase.UTILITY
	lane.phase_time = 0.0
	if style == Style.EXECUTE_TOGETHER:
		# Everyone not throwing pushes straight away; throwers go as their grenade leaves the hand.
		var throwers := _plan_throwers(lane)
		for bot: BotController in lane.living():
			if not throwers.has(bot.bot_id):
				lane.released[bot.bot_id] = true


## Which bots will throw this lane's grenades (first carrier of each, one grenade each).
func _plan_throwers(lane: Lane) -> Dictionary[String, bool]:
	var busy: Dictionary[String, bool] = {}
	for throw: Dictionary in lane.throws:
		for bot: BotController in lane.living():
			if not busy.has(bot.bot_id) and bot.weapons.utility_count(throw["utility"] as StringName) > 0:
				busy[bot.bot_id] = true
				break
	return busy


func _update_utility(lane: Lane) -> void:
	_hand_out(lane)
	if _lane_ready(lane) or lane.phase_time > _utility_limit(lane):
		_go(lane)


## True when the lane may go: the flash is out and has had its moment, or there is nothing left
## to throw. A supported entry's pair is let go as soon as its flash is out.
func _lane_ready(lane: Lane) -> bool:
	var pending := not lane.throws.is_empty() or not lane.walkers.is_empty() \
		or lane.living().any(func(bot: BotController) -> bool: return bot.is_throwing())
	if style == Style.SUPPORTED_ENTRY:
		if lane.flashed_at >= 0.0 and lane.phase_time - lane.flashed_at >= GO_AFTER_FLASH or (lane.flashed_at < 0.0 and not _flash_pending(lane)):
			_release_pair(lane)
		return not pending
	if lane.flashed_at >= 0.0:
		return lane.phase_time - lane.flashed_at >= GO_AFTER_FLASH and (style != Style.SPLIT or not pending)
	return not pending


func _flash_pending(lane: Lane) -> bool:
	if lane.walkers.values().any(func(throw: Dictionary) -> bool: return throw["utility"] == EquipmentCatalog.FLASH):
		return true
	if lane.throws.any(func(throw: Dictionary) -> bool: return throw["utility"] == EquipmentCatalog.FLASH):
		return true
	return lane.flasher_id != ""


func _utility_limit(lane: Lane) -> float:
	var slowest := 0.0
	for bot: BotController in lane.living():
		slowest = maxf(slowest, bot.skill.lineup_time)
	return UTILITY_BASE + UTILITY_PER_LINEUP * slowest


## Hands this lane's next throw to a free carrier (one line-up solved per update). Throws go out
## in parallel; on an execute the flash waits for the smokes to bloom.
func _hand_out(lane: Lane) -> void:
	for bot_id: String in lane.walkers.keys():
		_walk_and_throw(lane, bot_id)
	if lane.throws.is_empty():
		return
	# A supported entry's flash goes first: the supports hold their grenades until it is out.
	if style == Style.SUPPORTED_ENTRY and lane.flashed_at < 0.0 and lane.flasher_id != "":
		return
	var next: Dictionary = lane.throws[0]
	var utility := next["utility"] as StringName
	if utility == EquipmentCatalog.FLASH and style == Style.EXECUTE:
		var smokes_out := not lane.throws.any(func(throw: Dictionary) -> bool: return throw["utility"] == EquipmentCatalog.SMOKE)
		if not smokes_out or (lane.smoked_at >= 0.0 and lane.phase_time - lane.smoked_at < SMOKE_BLOOM) \
				or lane.living().any(func(bot: BotController) -> bool: return bot.is_throwing()):
			return
	var thrower := _free_carrier(lane, utility)
	if thrower == null:
		# Nobody can throw it right now: try again shortly unless nobody who may throw carries it.
		if not lane.living().any(func(bot: BotController) -> bool:
				return bot.weapons.utility_count(utility) > 0 and _may_throw(lane, bot)):
			lane.throws.pop_front()
		return
	lane.throws.pop_front()
	if utility == EquipmentCatalog.FLASH:
		lane.flasher_id = thrower.bot_id
	if not throw_now(thrower, utility, next["target"] as Vector3):
		next["since"] = lane.phase_time
		lane.walkers[thrower.bot_id] = next


func _free_carrier(lane: Lane, utility: StringName) -> BotController:
	for bot: BotController in lane.living():
		if bot.weapons.utility_count(utility) > 0 and not bot.is_throwing() and bot.target == null \
				and not lane.walkers.has(bot.bot_id) and _may_throw(lane, bot):
			return bot
	return null


## On a supported entry the pair going in carries its utility in; the supports throw.
func _may_throw(lane: Lane, bot: BotController) -> bool:
	return style != Style.SUPPORTED_ENTRY or not _in_pair(lane, bot)


func _walk_and_throw(lane: Lane, bot_id: String) -> void:
	var throw := lane.walkers[bot_id]
	var bot: BotController = null
	for member: BotController in lane.bots:
		if member.bot_id == bot_id:
			bot = member
	var alive := bot != null and bot.is_alive()
	var arrived := alive and _flat(bot.global_position, lane.plan.throw_spot) <= 1.0
	if alive and not arrived and lane.phase_time - float(throw["since"]) < WALK_LIMIT:
		return
	lane.walkers.erase(bot_id)
	if not arrived or not throw_now(bot, throw["utility"] as StringName, throw["target"] as Vector3):
		if throw["utility"] == EquipmentCatalog.FLASH:
			lane.flasher_id = ""


## [param bot] throws [param utility] at [param target] if a line-up exists from where it stands,
## at this style's pace. Returns true when the throw started.
func throw_now(bot: BotController, utility: StringName, target: Vector3) -> bool:
	var lineup := UtilityLineup.solve(space, utility, bot.head.global_position, target, LINEUP_TOLERANCE, bot.weapons.exclude)
	return lineup != null and bot.throw_utility(lineup, HURRY[style])


## Off the cuff: once the lead nears the entrance, a teammate with a flash pops it and the lead
## peeks off it (the lead waits for the flash; everyone else keeps moving).
func _update_default(lane: Lane) -> void:
	if lane.entry == null:
		var lead := _nearest(lane.living(), lane.plan.entrance, "")
		if lead == null or _flat(lead.global_position, lane.plan.entrance) > PEEK_RANGE:
			return
		lane.entry = lead
		lane.phase_time = 0.0
		var flasher: BotController = null
		for bot: BotController in lane.living():
			if bot != lead and bot.weapons.utility_count(EquipmentCatalog.FLASH) > 0 \
					and _flat(bot.global_position, lane.plan.entrance) <= FLASHER_RANGE:
				flasher = bot
				break
		if flasher == null or lane.plan.flash == Vector3.INF:
			_go(lane)
			return
		lane.flasher_id = flasher.bot_id
		if not throw_now(flasher, EquipmentCatalog.FLASH, lane.plan.flash):
			_go(lane)
		return
	if (lane.flashed_at >= 0.0 and lane.phase_time - lane.flashed_at >= GO_AFTER_FLASH) or lane.phase_time > DEFAULT_PEEK_LIMIT \
			or (lane.flasher_id != "" and lane.flashed_at < 0.0 and not _bot(lane, lane.flasher_id).is_throwing()):
		_go(lane)


## A grenade left a hand (or a throw was given up).
func on_utility_finished(bot: BotController, utility: StringName, thrown: bool) -> void:
	for lane: Lane in lanes:
		if not lane.bots.has(bot):
			continue
		var kind := EquipmentCatalog.utility_kind(utility)
		if thrown and kind == EquipmentCatalog.KIND_FLASH:
			lane.flashed_at = lane.phase_time
		elif thrown and kind == EquipmentCatalog.KIND_SMOKE:
			lane.smoked_at = lane.phase_time
		if kind == EquipmentCatalog.KIND_FLASH:
			lane.flasher_id = ""
		# Throw and go: the thrower pushes the moment its grenade is out.
		if style == Style.EXECUTE_TOGETHER and lane.phase == Phase.UTILITY:
			lane.released[bot.bot_id] = true


func _go(lane: Lane) -> void:
	lane.phase = Phase.GO
	lane.walkers.clear()
	for bot: BotController in lane.bots:
		lane.released[bot.bot_id] = true
	_release_pair(lane)


## The entry pair: the nearest two to the entrance (the bomb carrier only if nobody else).
func _release_pair(lane: Lane) -> void:
	if lane.entry != null and lane.trader != null:
		return
	var living := lane.living()
	if lane.entry == null:
		lane.entry = _nearest(living, lane.plan.entrance, carrier_id)
	if lane.entry != null:
		lane.released[lane.entry.bot_id] = true
		lane.trader = _nearest(living.filter(func(bot: BotController) -> bool: return bot != lane.entry), lane.entry.global_position, carrier_id)
		if lane.trader != null:
			lane.released[lane.trader.bot_id] = true


func _in_pair(lane: Lane, bot: BotController) -> bool:
	if lane.entry == null:
		var near := lane.living()
		near.sort_custom(func(a: BotController, b: BotController) -> bool:
			return _flat(a.global_position, lane.plan.entrance) < _flat(b.global_position, lane.plan.entrance))
		var pair := near.filter(func(member: BotController) -> bool: return member.bot_id != carrier_id).slice(0, 2)
		return pair.has(bot)
	return bot == lane.entry or bot == lane.trader


## The pair splits when either falls; released bots on a split note when they are through their
## own entrance (until then they head for it, not the shortest way to the site).
func _update_pair(lane: Lane) -> void:
	if lane.trader != null and (lane.entry == null or not lane.entry.is_alive() or not lane.trader.is_alive()):
		lane.trader = null
	for bot: BotController in lane.living():
		if _flat(bot.global_position, lane.plan.entrance) <= 3.5:
			lane.through[bot.bot_id] = true


## Where [param bot] should be: {goal, watch} for its part in the play, or {} for the squad's
## default site take (pushing in).
func order_for(bot: BotController) -> Dictionary:
	for lane: Lane in lanes:
		if not lane.bots.has(bot):
			continue
		var eye := Vector3(0, 1.5, 0)
		if lane.walkers.has(bot.bot_id):
			return {"goal": lane.plan.throw_spot, "watch": lane.plan.entrance + eye}
		if bot.is_throwing():
			return {"hold": true}
		if bot == lane.trader and lane.entry != null and lane.entry.is_alive() \
				and _flat(lane.entry.global_position, lane.plan.entrance) < PEEK_RANGE * 1.5:
			var ahead := lane.plan.entrance - lane.entry.global_position
			var side := Vector3(-ahead.z, 0.0, ahead.x).normalized() if Vector2(ahead.x, ahead.z).length() > 0.1 else Vector3.RIGHT
			return {"goal": lane.entry.global_position + side * PAIR_OFFSET, "watch": lane.plan.entrance + eye}
		if lane.released.has(bot.bot_id):
			# Through this lane's own entrance, not just the shortest way to the site.
			if lanes.size() > 1 and not lane.through.has(bot.bot_id):
				return {"goal": lane.plan.entrance, "watch": lane.plan.entrance + eye, "spread": true}
			return {}
		if lane.phase == Phase.APPROACH:
			# Off the cuff: move up to the entrance together; once the lead is at the corner,
			# everyone waits for the flash.
			if lane.entry == null:
				return {"goal": lane.plan.throw_spot, "watch": lane.plan.entrance + eye, "spread": true}
			return {"hold": true, "watch": lane.plan.entrance + eye}
		return {"goal": lane.plan.staging, "watch": lane.plan.entrance + eye, "spread": true}
	return {}


## Bot IDs let go to push.
func released() -> Array[String]:
	var list: Array[String] = []
	for lane: Lane in lanes:
		for id: String in lane.released:
			list.append(id)
	return list


func is_going() -> bool:
	return lanes.all(func(lane: Lane) -> bool: return lane.phase == Phase.GO)


func _bot(lane: Lane, id: String) -> BotController:
	for bot: BotController in lane.bots:
		if bot.bot_id == id:
			return bot
	return null


static func _nearest(candidates: Array, point: Vector3, avoid_id: String) -> BotController:
	var best: BotController = null
	for bot: BotController in candidates:
		if bot.bot_id == avoid_id and candidates.size() > 1:
			continue
		if best == null or _flat(bot.global_position, point) < _flat(best.global_position, point):
			best = bot
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
