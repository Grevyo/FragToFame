class_name SiteExecute
extends RefCounted
## A simple utility take of one bombsite, worked out from the map's own data: where attackers
## gather (the place before the entrance they walk in by), which entrance they take, and where
## their utility goes. Smokes go on the defenders' hold spot nearest that entrance (it cannot see
## out) and on the site's other entrance nearest the defence spawn (cuts the rotation); fire goes
## on the next hold spot; the flash pops over the entrance into the site. Pure data: the squad
## solves the throws against the geometry ([UtilityLineup]) and drops any that cannot be made.
## Milestone 7 C replaces the choice of site and entrance with the round plans of the IGL layer.

## The flash pops this far past the entrance into the site, this high.
const FLASH_DEPTH: float = 5.0
const FLASH_HEIGHT: float = 2.4
## Fire only goes on a hold this close to the entrance (further ones are out of the fight).
const FIRE_REACH: float = 18.0
## The spot just outside the entrance to throw from when the staging place has no line-up.
const THROW_SPOT_BACK: float = 2.5

var site: String = ""
## Places (SimMap IDs) and their positions; empty IDs when the map has no route to the site.
var staging_id: String = ""
var entrance_id: String = ""
var staging: Vector3 = Vector3.ZERO
var entrance: Vector3 = Vector3.ZERO
var throw_spot: Vector3 = Vector3.ZERO
var smokes: Array[Vector3] = []
var fire: Vector3 = Vector3.INF
var flash: Vector3 = Vector3.INF


## The take of site [param letter] on [param map] with the hold hints of [param holds] (the map
## document's "ai_hold" pieces for that site). Null when the map has no walk from attack spawn.
static func plan(map: SimMap, letter: String, holds: Array = []) -> SiteExecute:
	if map == null:
		return null
	var site_id := "site_" + letter
	var route := map.route(map.spawn("attack"), site_id)
	if route.size() < 2:
		return null
	var cluster := map.site_cluster(site_id)
	var first := 0
	while first < route.size() and not cluster.has(route[first]):
		first += 1
	if first == 0 or first >= route.size():
		return null
	var take := SiteExecute.new()
	take.site = letter
	take.entrance_id = route[first - 1]
	take.staging_id = route[first - 2] if first >= 2 else take.entrance_id
	take.entrance = _centre(map, take.entrance_id)
	take.staging = _centre(map, take.staging_id)
	var site_centre := _centre(map, site_id)
	var by_distance: Array[Vector3] = []
	for hold: Variant in holds:
		by_distance.append((hold as Dictionary)["position"] as Vector3)
	var from := take.entrance
	by_distance.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(from) < b.distance_to(from))
	if not by_distance.is_empty():
		take.smokes.append(by_distance[0])
	# The other way into the site nearest the defenders' spawn: their rotation.
	var defence := _centre(map, map.spawn("defence"))
	var rotation := ""
	for other: String in map.entrances(site_id):
		if other == take.entrance_id:
			continue
		if rotation.is_empty() or _centre(map, other).distance_to(defence) < _centre(map, rotation).distance_to(defence):
			rotation = other
	if not rotation.is_empty():
		take.smokes.append(_centre(map, rotation))
	if by_distance.size() >= 2 and by_distance[1].distance_to(take.entrance) <= FIRE_REACH:
		take.fire = by_distance[1]
	var back := take.staging - take.entrance
	take.throw_spot = take.entrance + back.normalized() * minf(THROW_SPOT_BACK, back.length()) if back.length() > 0.1 \
		else take.entrance
	var inward := Vector3(site_centre.x - take.entrance.x, 0.0, site_centre.z - take.entrance.z)
	if inward.length() > 0.5:
		take.flash = take.entrance + inward.normalized() * minf(FLASH_DEPTH, inward.length()) + Vector3(0, FLASH_HEIGHT, 0)
	return take


static func _centre(map: SimMap, id: String) -> Vector3:
	return map.nodes.get(id, {}).get("centre", Vector3.ZERO) as Vector3
