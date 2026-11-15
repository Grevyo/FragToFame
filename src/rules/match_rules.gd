class_name MatchRules
extends RefCounted
## Data-driven competitive rule set: format, timings and economy. Numbers are original to F2F.
##
## Format: "MR n" = n rounds per half; first to n + 1 wins regulation. A tie at n–n goes to
## overtime blocks of [member overtime_max_rounds] rounds per half until someone wins a block.

const SIDE_ATTACK: StringName = &"attack"
const SIDE_DEFENCE: StringName = &"defence"

const REASON_ELIMINATION: StringName = &"elimination"
const REASON_TIME: StringName = &"time"
const REASON_DETONATED: StringName = &"detonated"
const REASON_DEFUSED: StringName = &"defused"

var max_rounds: int = 10
var overtime_max_rounds: int = 3
var team_size: int = 5

## Seconds. Buying is allowed during freeze time and for [member buy_time] after it.
var freeze_time: float = 12.0
var buy_time: float = 20.0
var round_time: float = 105.0
var round_end_delay: float = 5.0
var bomb_timer: float = 40.0
var plant_time: float = 3.0
var defuse_time: float = 10.0
var defuse_time_with_kit: float = 5.0

var start_money: int = 900
var overtime_start_money: int = 9000
var max_money: int = 15000
var win_rewards: Dictionary[StringName, int] = {
	REASON_ELIMINATION: 3100,
	REASON_TIME: 3100,
	REASON_DETONATED: 3400,
	REASON_DEFUSED: 3400,
}
## Loss bonus by consecutive losses (1st loss, 2nd, …; the last value repeats).
var loss_bonus: Array[int] = [1500, 2000, 2500, 3000, 3500]
## Paid to every attacker when the bomb is planted, win or lose.
var plant_bonus: int = 600


## Full competitive timings.
static func competitive(mr: int = 10) -> MatchRules:
	var rules := MatchRules.new()
	rules.max_rounds = mr
	return rules


## Shorter timings for practice/rules testing.
static func practice(mr: int = 3) -> MatchRules:
	var rules := MatchRules.new()
	rules.max_rounds = mr
	rules.freeze_time = 5.0
	rules.buy_time = 15.0
	rules.round_time = 75.0
	rules.round_end_delay = 4.0
	rules.bomb_timer = 30.0
	return rules


static func other_side(side: StringName) -> StringName:
	return SIDE_DEFENCE if side == SIDE_ATTACK else SIDE_ATTACK


func loss_bonus_for(consecutive_losses: int) -> int:
	if loss_bonus.is_empty():
		return 0
	return loss_bonus[clampi(consecutive_losses - 1, 0, loss_bonus.size() - 1)]


func regulation_rounds() -> int:
	return max_rounds * 2


func to_dict() -> Dictionary:
	return {
		"max_rounds": max_rounds, "overtime_max_rounds": overtime_max_rounds, "team_size": team_size,
		"freeze_time": freeze_time, "buy_time": buy_time, "round_time": round_time,
		"round_end_delay": round_end_delay, "bomb_timer": bomb_timer, "plant_time": plant_time,
		"defuse_time": defuse_time, "defuse_time_with_kit": defuse_time_with_kit,
		"start_money": start_money, "overtime_start_money": overtime_start_money,
		"max_money": max_money, "plant_bonus": plant_bonus,
	}
