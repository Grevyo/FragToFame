class_name SeriesSimulator
extends RefCounted
## Resolves organisation series that nobody plays: each map is won with a probability set by
## the two lineups' strength, until one side reaches the best-of target. Pure maths (no
## database or scene access) so it can be tested in isolation and reused by cups (M13) and
## world simulation (M14).

## Strength gap that turns into a 73% map-win chance (logistic scale, in ability points).
const STRENGTH_SCALE: float = 6.0
## Even the strongest side keeps a real chance of dropping a map.
const MIN_MAP_CHANCE: float = 0.05


## Chance that the home side wins one map.
static func map_win_chance(home_strength: float, away_strength: float) -> float:
	var chance := 1.0 / (1.0 + exp(-(home_strength - away_strength) / STRENGTH_SCALE))
	return clampf(chance, MIN_MAP_CHANCE, 1.0 - MIN_MAP_CHANCE)


## Plays maps until one side wins [param best_of] (1, 3 or 5). Returns (home maps, away maps).
static func simulate(rng: RandomNumberGenerator, home_strength: float, away_strength: float,
		best_of: int) -> Vector2i:
	@warning_ignore("integer_division")
	var target := best_of / 2 + 1
	var chance := map_win_chance(home_strength, away_strength)
	var score := Vector2i.ZERO
	while score.x < target and score.y < target:
		if rng.randf() < chance:
			score.x += 1
		else:
			score.y += 1
	return score
