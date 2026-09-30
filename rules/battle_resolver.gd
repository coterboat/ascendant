class_name BattleResolver
## Interface the TurnResolver calls for every battle. #4 (autobattle) replaces StubBattleResolver
## with a real implementation of this same method. Implementations must be pure and take all
## randomness from `rng`.
##
## `battle` is:
##   {
##     "kind": "province" | "border",
##     "provinces": [province ids]   # one for a province battle, the two sides of the border otherwise
##     "defender": faction id, or "" when nobody was holding the ground,
##     "sides": [{"faction": id, "armies": [Army, ...]}, ...]   # sorted by faction id
##   }
## Return:
##   {
##     "winner": faction id (must be one of the sides),
##     "strengths": {faction id: int},
##     "tie_break": "none" | "defender" | "roll",
##     "roll": int (only meaningful when tie_break == "roll"),
##     "why": plain-language sentence explaining the result,
##   }
## The TurnResolver destroys every army on a losing side; the winner's armies are kept as returned.

func resolve_battle(_battle: Dictionary, _rng: SeededRNG) -> Dictionary:
	return {}
