class_name StubMatchRunner
extends RefCounted
## PLACEHOLDER match runner for Milestone 2: produces a random but valid regulation scoreline.
##
## Stands in for the FPS runtime / match simulator so the career result pipeline can be proven
## end to end. It follows the real contract: MatchSetup in, MatchResult out.


static func run(setup: MatchSetup, rng: RandomNumberGenerator = null) -> MatchResult:
	var random := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		random.randomize()
	var winner_score := setup.rounds_to_win()
	# In regulation the loser has at most max_rounds - 1 (max_rounds each would mean overtime).
	var loser_score := random.randi_range(0, setup.max_rounds - 1)
	var home_wins := random.randf() < 0.5
	var result := MatchResult.create(setup.fixture_id,
		winner_score if home_wins else loser_score,
		loser_score if home_wins else winner_score,
		MatchResult.SOURCE_STUB)
	result.map_id = setup.map_id
	return result
