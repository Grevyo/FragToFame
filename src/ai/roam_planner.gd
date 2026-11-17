class_name RoamPlanner
extends RefCounted
## Free-roam reasoning for a bot with no team plan: where to go next and how. Pure decisions over
## plain data (points, positions, remembered noises) so they can be tested without a scene.
##
## A bot scores every interest point on the map and picks the best:
##   + the point's interest (bombsites and callout areas over random corners)
##   + a comfortable travel distance (not the spot it is standing on, not across the whole map)
##   - places it visited recently (so it tours the map instead of pacing)
##   + recent gunfire it heard (investigate) — or − when badly hurt (stay away)
##   + a little randomness so bots do not move in lockstep
## On arrival it lingers and looks around, and it walks (quietly, more accurately) near danger.

## Interest weight of each kind of point.
const WEIGHTS: Dictionary[StringName, float] = {
	&"site": 1.0, &"area": 0.9, &"anchor": 0.8, &"spawn": 0.55, &"wander": 0.5,
}
## Travel distance the bot is happiest with (metres); farther points are mildly less attractive.
const PREFERRED_DISTANCE: float = 22.0
## Points closer than this are pointless to walk to.
const MIN_DISTANCE: float = 5.0
## How many recent destinations a bot remembers and avoids.
const MEMORY: int = 4
const RECENT_PENALTY: float = 1.2
## Gunshots are heard this far away (metres) and remembered for this long (seconds).
const HEARING_RADIUS: float = 45.0
const NOISE_MEMORY: float = 6.0
## Bonus for points near a heard gunshot (scaled by how close the point is to it).
const NOISE_PULL: float = 1.6
const NOISE_RANGE: float = 15.0
## At or below this health share a bot avoids fights instead of investigating them.
const HURT_SHARE: float = 0.4
const JITTER: float = 0.25
## Seconds spent looking around after arriving.
const LINGER_MIN: float = 1.2
const LINGER_MAX: float = 3.5
## Walk instead of run within this distance of remembered gunfire.
const CAUTION_RADIUS: float = 14.0


## Index of the best point for a bot at [param from], or -1 when there is nothing to choose.
## [param recent]: indices of its last destinations. [param noises]: gunfire it has heard.
static func choose(points: Array[RoamPoint], from: Vector3, recent: Array[int], noises: Array[RoamNoise],
		health_share: float, rng: RandomNumberGenerator) -> int:
	var best := -1
	var best_score := -INF
	for i: int in points.size():
		var score := score_point(points[i], from, recent.has(i), noises, health_share)
		if is_inf(score):
			continue
		score += rng.randf_range(-JITTER, JITTER)
		if score > best_score:
			best_score = score
			best = i
	return best


## The score of one point (−INF = never choose it). Exposed for tests and debugging.
static func score_point(point: RoamPoint, from: Vector3, visited_recently: bool, noises: Array[RoamNoise],
		health_share: float) -> float:
	var distance := _flat(point.position, from)
	if distance < MIN_DISTANCE:
		return -INF
	var score: float = WEIGHTS.get(point.kind, 0.5)
	# Gentle bell around the preferred distance: about 1 at the peak, 0.4 at twice the distance.
	score += exp(-pow((distance - PREFERRED_DISTANCE) / PREFERRED_DISTANCE, 2.0))
	if visited_recently:
		score -= RECENT_PENALTY
	var hurt := health_share <= HURT_SHARE
	for noise: RoamNoise in noises:
		var freshness := 1.0 - clampf(noise.age / NOISE_MEMORY, 0.0, 1.0)
		var closeness := 1.0 - clampf(_flat(point.position, noise.position) / NOISE_RANGE, 0.0, 1.0)
		score += (-NOISE_PULL if hurt else NOISE_PULL) * freshness * closeness
	return score


## True when the bot should walk: close to recent gunfire it heard.
static func should_walk(from: Vector3, noises: Array[RoamNoise]) -> bool:
	for noise: RoamNoise in noises:
		if noise.age < NOISE_MEMORY and _flat(from, noise.position) <= CAUTION_RADIUS:
			return true
	return false


## True when a gunshot at [param at] can be heard from [param listener].
static func hears(listener: Vector3, at: Vector3) -> bool:
	return listener.distance_to(at) <= HEARING_RADIUS


static func linger_time(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(LINGER_MIN, LINGER_MAX)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
