class_name MatchTimes
extends RefCounted
## When series are played: each league round (and cup round) is spread over a few consecutive
## days, each league on its own days of the week, and every series has a kick-off time, so the
## world's matches fall all through the week instead of on one day. Pure calendar maths.

## Kick-off when nothing else says (older saves, ad-hoc matches).
const DEFAULT_KICK_OFF: int = 18 * 60
## Days a round is spread over (fewer when the round gap is shorter).
const ROUND_DAYS: int = 3
## Kick-off times by how many series share a day.
const KICK_OFFS: Dictionary[int, Array] = {
	1: [18 * 60],
	2: [15 * 60 + 30, 19 * 60],
	3: [13 * 60, 16 * 60, 19 * 60],
	4: [13 * 60, 15 * 60 + 30, 18 * 60, 20 * 60 + 30],
}


## Where each of a round's [param count] series goes: [day offset within the round, kick-off],
## spread over [param days] days (at most [constant ROUND_DAYS]). More than four series on a day
## share kick-offs, as real match days do.
static func spread(count: int, days: int) -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	if count <= 0:
		return slots
	var span := clampi(mini(days, ROUND_DAYS), 1, count)
	var on_day: Array[int] = []
	on_day.resize(span)
	for index: int in count:
		@warning_ignore("integer_division")
		on_day[index * span / count] += 1
	var used: Array[int] = []
	used.resize(span)
	for index: int in count:
		@warning_ignore("integer_division")
		var day := index * span / count
		var times: Array = KICK_OFFS[mini(on_day[day], 4)]
		slots.append(Vector2i(day, int(times[used[day] % times.size()])))
		used[day] += 1
	return slots


## Days after the season start that a league's rounds begin: leagues opening in the same month
## take turns through the week by their position ([param order]) so they do not all play on the
## same days. Never more than
## [param room] days (what is left of the season's year).
static func league_offset(order: int, round_gap: int, room: int) -> int:
	var choices := maxi(round_gap - ROUND_DAYS + 1, 1)
	return clampi((order * 2) % choices, 0, maxi(room, 0))
