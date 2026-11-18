class_name TrainingResult
extends RefCounted
## What one training session measured. Produced by the FPS runtime ([TrainingSession]) and
## handed to whoever started it; the runtime never writes the career database.

const FORMAT_VERSION: int = 1

var drill_id: StringName = &""
## Measured numbers (kills, accuracy, average_ms, time, …), see [TrainingDrills].
var metrics: Dictionary = {}
## 1–100 from [method TrainingDrills.score].
var score: int = 0
## False when the session was abandoned before the end (not recorded).
var completed: bool = false


static func make(drill: StringName, measured: Dictionary, done: bool) -> TrainingResult:
	var result := TrainingResult.new()
	result.drill_id = drill
	result.metrics = measured.duplicate(true)
	result.completed = done
	result.score = TrainingDrills.score(drill, measured) if done else 0
	return result


func to_dict() -> Dictionary:
	return {"format_version": FORMAT_VERSION, "drill_id": String(drill_id), "metrics": metrics.duplicate(true),
		"score": score, "completed": completed}


static func from_dict(data: Dictionary) -> TrainingResult:
	if int(data.get("format_version", 0)) != FORMAT_VERSION:
		return null
	var result := TrainingResult.new()
	result.drill_id = StringName(str(data.get("drill_id", "")))
	var measured: Variant = data.get("metrics", {})
	result.metrics = (measured as Dictionary).duplicate(true) if measured is Dictionary else {}
	result.score = int(data.get("score", 0))
	result.completed = bool(data.get("completed", false))
	return result
