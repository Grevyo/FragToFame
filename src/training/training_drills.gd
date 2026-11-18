class_name TrainingDrills
extends RefCounted
## The training ground's drills: what each one measures, how long it runs and how its measured
## numbers become a 1–100 score. Pure data and maths (no nodes), so scoring is testable.
##
## Drills measure the person at the keyboard. Their results are recorded as measured evidence;
## they never change aim, recoil, movement or reaction in the FPS runtime.

const FLICK: StringName = &"flick"
const REACTION: StringName = &"reaction"
const TRACKING: StringName = &"tracking"
const MOVEMENT: StringName = &"movement"
## A 5v5 practice match against an organisation (played through the match runtime).
const SCRIM: StringName = &"scrim"

const MAP_RANGE: String = "range"
const MAP_COURSE: String = "course"

## id → {name, summary, ability (career attribute the evidence speaks to), map, duration (s),
## reps, weapon}.
const DRILLS: Dictionary[StringName, Dictionary] = {
	FLICK: {"name": "Flick range", "summary": "Targets appear one at a time around the range. Kill as many as you can in 60 seconds.",
		"ability": &"aim", "map": MAP_RANGE, "duration": 60.0, "reps": 0, "weapon": WeaponCatalog.AK47},
	REACTION: {"name": "Reaction test", "summary": "Wait for the target, then hit it as fast as you can. Twelve reps; shooting early is a false start.",
		"ability": &"reaction", "map": MAP_RANGE, "duration": 0.0, "reps": 12, "weapon": WeaponCatalog.G17},
	TRACKING: {"name": "Tracking lane", "summary": "Stay on a strafing target for 30 seconds. Accuracy and damage count.",
		"ability": &"aim", "map": MAP_RANGE, "duration": 30.0, "reps": 0, "weapon": WeaponCatalog.M4A1},
	MOVEMENT: {"name": "Movement course", "summary": "Jump and run the course through every checkpoint to the finish. Falling sends you back to the last checkpoint.",
		"ability": &"movement", "map": MAP_COURSE, "duration": 0.0, "reps": 0, "weapon": WeaponCatalog.G17},
}

const COUNTDOWN: float = 3.0
## Reaction test: random wait before the target appears, and how long it stays up.
const REACTION_WAIT_MIN: float = 1.2
const REACTION_WAIT_MAX: float = 3.0
const REACTION_WINDOW: float = 1.5
## Tracking: seconds before a downed target stands up again.
const TRACKING_RESPAWN: float = 0.3
## Movement course par time (seconds) when the map does not set one.
const COURSE_PAR: float = 40.0


static func ids() -> Array[StringName]:
	var list: Array[StringName] = []
	list.assign(DRILLS.keys())
	return list


static func is_drill(id: StringName) -> bool:
	return DRILLS.has(id)


static func drill_name(id: StringName) -> String:
	if id == SCRIM:
		return "Scrim (5v5)"
	return str(DRILLS[id]["name"]) if DRILLS.has(id) else String(id)


## The career attribute a drill's evidence speaks to (&"" for scrims).
static func ability(id: StringName) -> StringName:
	return DRILLS[id]["ability"] as StringName if DRILLS.has(id) else &""


## 1–100 from a drill's measured numbers. Benchmarks: a strong flick run is ~50 kills a minute
## at 60% accuracy; an elite reaction average is under 200 ms; a clean course is under par.
static func score(id: StringName, metrics: Dictionary) -> int:
	var value := 0.0
	match id:
		FLICK:
			var per_minute := float(metrics.get("kills", 0)) * 60.0 / maxf(float(metrics.get("duration", 60.0)), 1.0)
			value = per_minute * 1.25 + float(metrics.get("accuracy", 0.0)) * 22.0 + float(metrics.get("headshot_rate", 0.0)) * 10.0
		REACTION:
			if int(metrics.get("reps_hit", 0)) == 0:
				return 1
			value = 160.0 - float(metrics.get("average_ms", 500.0)) * 0.32 - float(metrics.get("false_starts", 0)) * 3.0 \
				- float(metrics.get("misses", 0)) * 4.0
		TRACKING:
			var per_second := float(metrics.get("damage", 0)) / maxf(float(metrics.get("duration", 30.0)), 1.0)
			value = float(metrics.get("accuracy", 0.0)) * 75.0 + per_second * 0.35
		MOVEMENT:
			var time := float(metrics.get("time", 0.0))
			if time <= 0.0 or not bool(metrics.get("finished", false)):
				return 1
			value = 70.0 * float(metrics.get("par", COURSE_PAR)) / time - float(metrics.get("resets", 0)) * 2.0
		_:
			return 0
	return clampi(roundi(value), 1, 100)


## One line summary of a result's numbers for tables ("42 kills · 61% acc · 38% HS").
static func describe(id: StringName, metrics: Dictionary) -> String:
	match id:
		FLICK:
			return "%d kills · %d%% accuracy · %d%% headshots" % [int(metrics.get("kills", 0)),
				roundi(float(metrics.get("accuracy", 0.0)) * 100.0), roundi(float(metrics.get("headshot_rate", 0.0)) * 100.0)]
		REACTION:
			return "average %d ms · best %d ms · %d false starts · %d missed" % [roundi(float(metrics.get("average_ms", 0.0))),
				roundi(float(metrics.get("best_ms", 0.0))), int(metrics.get("false_starts", 0)), int(metrics.get("misses", 0))]
		TRACKING:
			return "%d damage · %d%% accuracy · %d kills" % [int(metrics.get("damage", 0)),
				roundi(float(metrics.get("accuracy", 0.0)) * 100.0), int(metrics.get("kills", 0))]
		MOVEMENT:
			if not bool(metrics.get("finished", false)):
				return "not finished · %d of %d checkpoints" % [int(metrics.get("checkpoints", 0)), int(metrics.get("checkpoint_total", 0))]
			return "%.2f s (par %.0f s) · %d resets" % [float(metrics.get("time", 0.0)), float(metrics.get("par", COURSE_PAR)),
				int(metrics.get("resets", 0))]
		SCRIM:
			return "%s %d–%d vs %s · %d–%d K–D" % ["Won" if bool(metrics.get("won", false)) else "Lost", int(metrics.get("score_for", 0)),
				int(metrics.get("score_against", 0)), str(metrics.get("opponent", "?")), int(metrics.get("kills", 0)), int(metrics.get("deaths", 0))]
	return ""
