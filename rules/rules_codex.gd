class_name RulesCodex
## Plain-language rules text for the in-game codex, tooltips and the turn report.
## Every turn event carries a "codex" key naming one of these entries.
## This text is the player-facing statement of the rules in TurnResolver, StubBattleResolver and
## AutoBattleResolver (the "battle_*" and "trait_*" entries);
## keep them in sync.

const ENTRIES := {
	"phase_order": {
		"title": "How a turn resolves",
		"text": "Everyone gives orders first. Then the whole turn resolves at once, always in this order: 1. orders are checked, 2. movement, 3. battles, 4. capture, 5. recruitment, 6. income. The same orders and seed always give the same result.",
	},
	"orders": {
		"title": "Orders",
		"text": "Each turn you can move each army once, to a province next to it, and recruit units at your capital. An army with no move order holds where it is. An order that breaks a rule is rejected, and the turn report says why.",
	},
	"move": {
		"title": "Moving",
		"text": "An army moves one province per turn, to a neighbor of the province it is in. It arrives during this turn's resolution and is ready to act next turn. All armies move at the same time, so an army that leaves a province is gone before anyone arrives there.",
	},
	"same_province": {
		"title": "Armies meeting in a province",
		"text": "If armies of two factions end their moves in the same province, they fight a battle there. If both arrived this turn, nobody is defending.",
	},
	"swap": {
		"title": "Armies swapping places",
		"text": "If your army moves from A to B while an enemy army moves from B to A, they meet on the border between A and B and fight there. Nobody is defending. The winner finishes its move, and the loser never arrives.",
	},
	"hold": {
		"title": "Holding a province",
		"text": "An army with no move order holds its province. If enemies move in, the holding army is the defender, and the defender wins a battle when strengths are tied.",
	},
	"defended": {
		"title": "Moving into a defended province",
		"text": "Moving into a province where an enemy army is holding starts a battle there. The holding army defends.",
	},
	"undefended": {
		"title": "Moving into an undefended province",
		"text": "Moving into an enemy or neutral province with no enemy army in it captures it, as long as no enemy army arrives there too.",
	},
	"battle_stub": {
		"title": "Battles (placeholder rules)",
		"text": "Until full battles arrive, each side's strength is the total attack plus defense of every unit and commander it has there. The higher strength wins and takes no losses. Every losing army is destroyed. On a tie the defender wins. If the tied sides have no defender, a seeded roll picks the winner.",
	},
	"battle_rounds": {
		"title": "Battles",
		"text": "A battle is fought in rounds, at most 8. Each round every unit and commander attacks one enemy at the same time, so a unit that falls still strikes that round. Attacks go at the enemy's front rank: crossbowmen stand behind their other units and commanders behind everyone, so they are only attacked once nothing in front of them is left. The battle ends when one side is wiped out or breaks. If every side left breaks in the same round, the one with more of its strength left keeps the field. The winner keeps its wounded units; units that fell are gone. Every army on a losing side is destroyed or scattered (there are no retreats yet).",
	},
	"battle_round_cap": {
		"title": "When a battle runs out of time",
		"text": "If nobody has won after 8 rounds, the defender holds its ground and wins. With no defender (a border battle, or armies that all arrived together), the side with the larger share of its starting hit points left wins; an exact tie is settled by a seeded roll.",
	},
	"battle_hit_chance": {
		"title": "Hit chance and damage",
		"text": "Every attack rolls to hit. The chance is 60%, plus 4% for every point the attacker's attack is above the target's defense (or minus 4% for every point below), never lower than 30% or higher than 90%. A hit deals half the attacker's attack (rounded up) minus a quarter of the target's defense (rounded down), at least 1. The battle report shows how often each side actually hit next to the chances it had, so you can see how much luck mattered.",
	},
	"battle_terrain": {
		"title": "Terrain in battle",
		"text": "Only the defender, the side that was already holding the province, gets the ground: forest +2 defense, hills +1 defense and +1 attack, plains nothing. A fort adds +2 defense on top. Border battles and armies that all arrived at once have no defender, so nobody gets terrain. Knights' charge is weaker in a forest, and Fangthrowers ignore forest and hills cover (not forts).",
	},
	"battle_morale": {
		"title": "Morale and routs",
		"text": "A side's morale is the average morale of its units, +2 while its commander stands, plus trait effects (Inspire, Fury). Morale decides how much a side can lose before it breaks: 20% plus 5% per point of morale, of its starting hit points (at least 25%, at most 95%). Morale 10 breaks after losing 70% of its hit points; morale 6 after 50%. A side that breaks flees and loses the battle, even with units still standing.",
	},
	"battle_commanders": {
		"title": "Commanders in battle",
		"text": "A commander fights from the back line, so enemies reach it only after its units have fallen. While it stands its side gets +2 morale, and its own trait: the Knight Captain inspires (+2 more morale), the Warchief leads the pack (+1 attack to every unit).",
	},
	"battle_odds": {
		"title": "Battle odds",
		"text": "Before you attack, the forecast fights the same battle with the real rules 24 times on fixed test seeds and tells you how often you won: likely win (65% or more), close, or likely loss (35% or less), with the main reasons. The real battle uses this turn's own rolls, so a likely win can still go wrong.",
	},
	"trait_shield_wall": {
		"title": "Shield Wall (Spearmen)",
		"text": "Spearmen get +2 defense while any other fighter on their side still stands. Alone they lose it.",
	},
	"trait_volley": {
		"title": "Volley (Crossbowmen)",
		"text": "Crossbowmen shoot over their own lines: enemies can only attack them once every other unit on their side (not counting the commander) has fallen.",
	},
	"trait_charge": {
		"title": "Charge (Knights)",
		"text": "Knights deal +4 damage with every hit in the first round of a battle, or +2 in a forest, where heavy horses are slowed.",
	},
	"trait_inspire": {
		"title": "Inspire (Knight Captain)",
		"text": "While the Knight Captain stands, its side gets +2 morale on top of the usual +2 for having a commander, so it can take more losses before it breaks.",
	},
	"trait_berserk": {
		"title": "Berserk (Tuskers)",
		"text": "A wounded Tusker (below full hit points) gets +3 attack. Wounds carry over between battles, so a wounded Tusker starts the next battle already berserk.",
	},
	"trait_skirmish": {
		"title": "Skirmish (Fangthrowers)",
		"text": "Fangthrowers ignore the defender's forest and hills defense bonus when they attack. A fort's bonus still counts.",
	},
	"trait_fury": {
		"title": "Fury (War Bear)",
		"text": "Each War Bear still standing roars: every enemy side gets -2 morale, at most -4 for two or more bears. Kill the bears and the roar stops.",
	},
	"trait_pack_leader": {
		"title": "Pack Leader (Warchief)",
		"text": "While the Warchief stands, every unit on its side gets +1 attack.",
	},
	"capture": {
		"title": "Capturing provinces",
		"text": "After battles, a province with armies of only one faction in it becomes that faction's. This happens whether it was neutral or an enemy's. Taking the enemy capital stops them from recruiting.",
	},
	"recruit": {
		"title": "Recruiting",
		"text": "Recruit units from your own roster at your capital. Each unit costs gold, paid in the order you gave the orders, from your gold before this turn's income. Recruiting happens after capture, so if your capital falls this turn your recruits are cancelled and you keep the gold. New units join your army at the capital, or form a new army if none is there.",
	},
	"income": {
		"title": "Income",
		"text": "At the end of the turn, each faction earns the income of every province it owns, after this turn's captures and recruits.",
	},
}


static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})


static func text(id: String) -> String:
	return entry(id).get("text", "")
