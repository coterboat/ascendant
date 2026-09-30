class_name StubBattleResolver
extends BattleResolver
## Deterministic placeholder battle rules until #4 lands (text in RulesCodex "battle_stub"):
##   - Each side's strength = sum of attack + defense of every unit and commander in its armies.
##   - Highest strength wins. The winner takes no losses; every losing army is destroyed.
##   - Tie: the defender (a faction that was already in the province and held) wins.
##   - Tie with no defender among the tied sides (both arrived, or a border battle): one seeded roll
##     rng.randi_range(0, tied - 1) over the tied factions sorted by id picks the winner.


static func army_strength(army: Army) -> int:
	var total := 0
	for u in army.units:
		total += u.type.attack + u.type.defense
	if army.commander:
		total += army.commander.type.attack + army.commander.type.defense
	return total


func resolve_battle(battle: Dictionary, rng: SeededRNG) -> Dictionary:
	var strengths := {}
	var best := -1
	for side in battle.sides:
		var total := 0
		for a in side.armies:
			total += army_strength(a)
		strengths[side.faction] = total
		best = maxi(best, total)

	var tied: Array = []
	for side in battle.sides:
		if strengths[side.faction] == best:
			tied.append(side.faction)
	tied.sort()

	var defender: String = battle.get("defender", "")
	if tied.size() == 1:
		return {"winner": tied[0], "strengths": strengths, "tie_break": "none", "roll": 0,
			"why": "the higher total strength (attack + defense of every unit) wins"}
	if tied.has(defender):
		return {"winner": defender, "strengths": strengths, "tie_break": "defender", "roll": 0,
			"why": "strengths were tied, and ties go to the defender who was already holding the province"}
	var roll := rng.randi_range(0, tied.size() - 1)
	return {"winner": tied[roll], "strengths": strengths, "tie_break": "roll", "roll": roll,
		"why": "strengths were tied and nobody was defending, so a seeded roll picked the winner"}
