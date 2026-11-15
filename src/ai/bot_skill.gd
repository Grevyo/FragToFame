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
	return skill
