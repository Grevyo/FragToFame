class_name BotSkill
extends RefCounted
## How well a bot plays the FPS layer: perception, reaction, aim and discipline.
##
## These are bot-only mechanics. Later milestones derive them from AI players' career attributes;
## human players are never affected by any of these values.

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
	return skill
