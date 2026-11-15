class_name CombatTally
extends RefCounted
## Recorded shooting numbers for one shooter (shots, hits, headshots, kills, damage).
##
## Raw recorded values only. Ratings and perceived/scouted values are calculated elsewhere and
## never stored here (see docs/ARCHITECTURE.md, data rules).

var shots: int = 0
var hits: int = 0
var headshots: int = 0
var kills: int = 0
var damage: int = 0


func record_shot() -> void:
	shots += 1


func record_hit(info: DamageInfo, killed: bool) -> void:
	hits += 1
	damage += info.applied
	if info.is_headshot():
		headshots += 1
	if killed:
		kills += 1


func accuracy() -> float:
	return float(hits) / float(shots) if shots > 0 else 0.0


func headshot_rate() -> float:
	return float(headshots) / float(hits) if hits > 0 else 0.0


func reset() -> void:
	shots = 0
	hits = 0
	headshots = 0
	kills = 0
	damage = 0
