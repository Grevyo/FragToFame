class_name BotSkill
extends RefCounted
## How well a bot plays the FPS layer: perception, reaction, aim and discipline.
##
## These are bot-only mechanics. A career match derives every one of them from the AI player's
## abilities ([method from_abilities]); the sandbox uses the presets. Human players are never
## affected by any of these values.

var label: String = "Normal"
## Seconds between first seeing an enemy and being allowed to fire (randomised ±).
var reaction_time: float = 0.32
## Maximum view turn speed in degrees per second.
var turn_speed: float = 420.0
## Fraction of the remaining angle closed per second (smooth, slightly lagging aim).
var aim_gain: float = 9.0
## Initial aim error in degrees when acquiring a target; decays at [member error_decay] per second.
var initial_error: float = 4.0
var error_decay: float = 2.5
## Chance of picking the head (instead of the chest) as aim point on acquisition.
var headshot_bias: float = 0.35
## Fraction of weapon recoil the bot pulls against (0 = none, 1 = perfect).
var recoil_control: float = 0.6
## Fires when the aim is within (target angular radius × this) of the aim point.
var fire_tolerance: float = 1.6
## Field of view for spotting, degrees.
var view_angle: float = 110.0
var view_distance: float = 60.0
## Enemies closer than this are noticed regardless of facing (footsteps, contact).
var awareness_radius: float = 4.0
## Beyond this distance automatic weapons fire in bursts instead of spraying.
var burst_distance: float = 14.0
## Movement discipline in a fight, 0..1: how often the bot strafes between bursts and stops dead
## to shoot (counter-strafe) instead of standing still or shooting on the move.
var strafe: float = 0.55
## How readily the bot jiggle-peeks a held angle to look for information, 0..1.
var peek: float = 0.5
## Shoots only at this share of full-run speed or slower: disciplined players stop dead first.
var accurate_share: float = 0.38
## Chance of actually checking each angle on the way (a careless player skips some).
var clearing: float = 0.75
## Seconds an angle is held after the enemy drops out of sight, before following up.
var search_hold: float = 1.0
## How far ahead (seconds) the bot sees a teammate's flash coming and turns away; slow readers
## of the team's calls turn late and catch some of it.
var flash_lead: float = 0.7
## Throwing: spread of the release around the line-up (degrees; a clumsy throw lands off the
## spot) and the seconds taken lining up before letting go (never instant).
var utility_error: float = 1.1
var lineup_time: float = 0.85


## Bot mechanics from an AI professional's simulated abilities (1–100, see CareerCatalog).
## Each value blends between the easy and hard presets (slightly beyond hard for elite values);
## missing abilities count as 50. Only AI players have abilities — humans are never mapped.
static func from_abilities(abilities: Dictionary, label_text: String = "") -> BotSkill:
	var easy := preset(&"easy")
	var hard := preset(&"hard")
	var skill := BotSkill.new()
	var aim: float = _blend(abilities, ["aim"])
	var placement: float = _blend(abilities, ["crosshair_placement", "aim"])
	var game_sense: float = _blend(abilities, ["game_sense"])
	var composure: float = _blend(abilities, ["composure", "consistency"])
	skill.reaction_time = maxf(lerpf(easy.reaction_time, hard.reaction_time, _blend(abilities, ["reaction"])), 0.15)
	skill.turn_speed = lerpf(easy.turn_speed, hard.turn_speed, _blend(abilities, ["movement", "reaction"]))
	skill.aim_gain = lerpf(easy.aim_gain, hard.aim_gain, aim)
	skill.initial_error = maxf(lerpf(easy.initial_error, hard.initial_error, placement), 1.5)
	skill.error_decay = lerpf(easy.error_decay, hard.error_decay, aim)
	skill.headshot_bias = clampf(lerpf(easy.headshot_bias, hard.headshot_bias, placement), 0.05, 0.7)
	skill.recoil_control = clampf(lerpf(easy.recoil_control, hard.recoil_control, _blend(abilities, ["spray_control"])), 0.0, 0.92)
	skill.fire_tolerance = maxf(lerpf(easy.fire_tolerance, hard.fire_tolerance, composure), 1.1)
	skill.view_angle = lerpf(easy.view_angle, hard.view_angle, game_sense)
	skill.awareness_radius = lerpf(3.0, 6.0, game_sense)
	skill.burst_distance = lerpf(11.0, 17.0, composure)
	skill.strafe = clampf(lerpf(easy.strafe, hard.strafe, _blend(abilities, ["movement", "spray_control"])), 0.0, 1.0)
	skill.peek = clampf(lerpf(easy.peek, hard.peek, _blend(abilities, ["game_sense", "movement"])), 0.0, 1.0)
	var sense := _blend(abilities, ["game_sense", "positioning"])
	var utility := _blend(abilities, ["utility"])
	skill.view_distance = lerpf(easy.view_distance, hard.view_distance, game_sense)
	skill.accurate_share = maxf(lerpf(easy.accurate_share, hard.accurate_share, _blend(abilities, ["movement", "composure"])), 0.22)
	skill.clearing = clampf(lerpf(easy.clearing, hard.clearing, sense), 0.1, 1.0)
	skill.search_hold = maxf(lerpf(easy.search_hold, hard.search_hold, sense), 0.3)
	skill.flash_lead = maxf(lerpf(easy.flash_lead, hard.flash_lead, _blend(abilities, ["teamwork", "communication"])), 0.2)
	skill.utility_error = maxf(lerpf(easy.utility_error, hard.utility_error, utility), 0.15)
	skill.lineup_time = maxf(lerpf(easy.lineup_time, hard.lineup_time, _blend(abilities, ["utility", "composure"])), 0.35)
	var overall := 0.0
	for value: Variant in abilities.values():
		overall += float(value)
	skill.label = label_text if not label_text.is_empty() else "Rated %d" % roundi(overall / maxf(abilities.size(), 1))
	return skill


## 0 at ability 35, 1 at 90, up to 1.12 for elite values (mean of [param keys]).
static func _blend(abilities: Dictionary, keys: Array) -> float:
	var total := 0.0
	for key: Variant in keys:
		total += float(abilities.get(key, 50))
	return clampf((total / keys.size() - 35.0) / 55.0, 0.0, 1.12)


static func preset(name: StringName) -> BotSkill:
	var skill := BotSkill.new()
	match name:
		&"easy":
			skill.label = "Easy"
			skill.reaction_time = 0.55
			skill.turn_speed = 240.0
			skill.aim_gain = 5.0
			skill.initial_error = 7.0
			skill.error_decay = 1.4
			skill.headshot_bias = 0.15
			skill.recoil_control = 0.25
			skill.fire_tolerance = 2.4
			skill.view_angle = 95.0
			skill.strafe = 0.2
			skill.peek = 0.15
			skill.view_distance = 45.0
			skill.accurate_share = 0.6
			skill.clearing = 0.35
			skill.search_hold = 0.5
			skill.flash_lead = 0.3
			skill.utility_error = 2.6
			skill.lineup_time = 1.5
		&"hard":
			skill.label = "Hard"
			skill.reaction_time = 0.22
			skill.turn_speed = 600.0
			skill.aim_gain = 13.0
			skill.initial_error = 2.5
			skill.error_decay = 3.5
			skill.headshot_bias = 0.55
			skill.recoil_control = 0.85
			skill.fire_tolerance = 1.3
			skill.view_angle = 120.0
			skill.strafe = 0.9
			skill.peek = 0.8
			skill.view_distance = 70.0
			skill.accurate_share = 0.28
			skill.clearing = 0.95
			skill.search_hold = 1.5
			skill.flash_lead = 1.0
			skill.utility_error = 0.35
			skill.lineup_time = 0.5
	return skill
