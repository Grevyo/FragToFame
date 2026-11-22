class_name TeamKnowledge
extends RefCounted
## What one team of bots knows together: which of the map's places (its [SimMap] callouts) a
## teammate has looked into lately, and where enemies were last seen. Bots read it to clear the
## angles nobody has checked and to play carefully where the enemy is; only what a teammate saw
## goes in (no hidden information).

## A place stays cleared this long after someone looked into it.
const CLEARED_SECONDS: float = 8.0
## Sightings older than this are forgotten.
const SIGHTING_SECONDS: float = 10.0

## Seconds since the round started (advanced by the squad).
var now: float = 0.0
## Places to clear: {id, centre: Vector3, site}.
var places: Array[Dictionary] = []
## Place ID -> time it was last looked into.
var cleared: Dictionary[String, float] = {}
## Recent enemy sightings: {position: Vector3, time: float}.
var sightings: Array[Dictionary] = []


## The places of [param map] (spawns left out: there is nothing to clear in your own spawn and
## nothing to see in theirs).
static func from_sim_map(map: SimMap) -> TeamKnowledge:
	var knowledge := TeamKnowledge.new()
	if map == null:
		return knowledge
	for id: String in map.nodes:
		var node: Dictionary = map.nodes[id]
		if str(node.get("kind", "")) == SimMap.KIND_SPAWN:
			continue
		# SimMap has already turned the JSON centre into a Vector3.
		knowledge.places.append({"id": id, "centre": node.get("centre", Vector3.ZERO) as Vector3,
			"site": str(node.get("site", ""))})
	return knowledge


## A new round: nothing is cleared and nobody has been seen.
func reset() -> void:
	now = 0.0
	cleared.clear()
	sightings.clear()


func advance(delta: float) -> void:
	now += delta
	sightings = sightings.filter(func(s: Dictionary) -> bool: return now - float(s["time"]) <= SIGHTING_SECONDS)


func mark_cleared(place_id: String) -> void:
	cleared[place_id] = now


func is_cleared(place_id: String) -> bool:
	return cleared.has(place_id) and now - cleared[place_id] <= CLEARED_SECONDS


func report_enemy(position: Vector3) -> void:
	for sighting: Dictionary in sightings:
		if (sighting["position"] as Vector3).distance_to(position) < 2.0:
			sighting["position"] = position
			sighting["time"] = now
			return
	sightings.append({"position": position, "time": now})


## True when a teammate saw an enemy within [param radius] of [param position] in the last
## [param within] seconds.
func enemy_near(position: Vector3, radius: float, within: float = 5.0) -> bool:
	for sighting: Dictionary in sightings:
		if now - float(sighting["time"]) <= within and (sighting["position"] as Vector3).distance_to(position) <= radius:
			return true
	return false


## Places within [param reach] of [param position] that nobody has cleared lately, nearest first.
func uncleared_near(position: Vector3, reach: float) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for place: Dictionary in places:
		if not is_cleared(str(place["id"])) and (place["centre"] as Vector3).distance_to(position) <= reach:
			list.append(place)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["centre"] as Vector3).distance_to(position) < (b["centre"] as Vector3).distance_to(position))
	return list
