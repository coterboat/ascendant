class_name RulesCodex
## Plain-language rules text for the in-game codex, tooltips and the turn report.
## Every turn event carries a "codex" key naming one of these entries.
## This text is the player-facing statement of the rules in TurnResolver and AutoBattleResolver
## (the "battle_*" and "trait_*" entries); keep them in sync. StubBattleResolver is a test-only
## stand-in and has no entry: players never see its rules.

const ENTRIES := {
	# --- the basic terms (#8): the map, gold, armies, units and their stats. The map's tooltips link here
	# (TooltipText.CODEX). The terrain and fort numbers match AutoBattleResolver.TERRAIN and FORT_DEFENSE;
	# tests/test_codex_terms.gd checks them. Plain text only (no [url] links): tooltips quote these too.
	"province": {
		"title": "Province",
		"text": "The map is made of provinces. Each has a terrain (plains, forest or hills), an income in gold per turn and an owner: a faction, or nobody if it is neutral. Some have a fort, and each faction has a capital. Provinces joined by a road are neighbors, and armies move from a province to a neighbor. A province becomes yours when your armies are the only ones in it after a turn's battles. It stays yours, paying you its income every turn, until someone else captures it.",
	},
	"neutral": {
		"title": "Neutral provinces",
		"text": "A neutral province belongs to nobody, so its income goes to nobody. At the start every province except the capitals is neutral. On the map it has a slate-grey ring and a shield emblem. There are no neutral armies, so an army that moves into a neutral province captures it without a fight, unless an enemy army arrives there in the same turn.",
	},
	"capital": {
		"title": "Capital",
		"text": "Each faction starts in its capital, marked with a crown on the map. Your capital is the only place you can recruit, and only while you hold it. Capture the enemy capital to win the game: it is captured like any other province. If both capitals fall in the same turn, the game is a draw.",
	},
	"fort": {
		"title": "Fort",
		"text": "Some provinces have a fort, drawn as a small tower on the map. An army holding a province with a fort gets +2 defense in battles there, on top of the terrain. Only the defender gets it, never armies that just arrived, and Fangthrowers' Skirmish does not ignore it. A fort does not change income.",
	},
	"terrain_plains": {
		"title": "Plains",
		"text": "Open flat land. Plains give no bonus in battle to either side, and Knights charge at full strength here. Like all terrain, plains do not change movement or income.",
	},
	"terrain_forest": {
		"title": "Forest",
		"text": "Dense woodland. An army holding a forest province gets +2 defense in battles there; armies that just arrived get nothing. Knights' charge is weaker in a forest, and Fangthrowers' Skirmish ignores the forest's defense bonus. Terrain does not change movement or income.",
	},
	"terrain_hills": {
		"title": "Hills",
		"text": "Rugged high ground. An army holding a hills province gets +1 defense and +1 attack in battles there; armies that just arrived get nothing. Fangthrowers' Skirmish ignores the hills' defense bonus, but not their attack bonus. Terrain does not change movement or income.",
	},
	"gold": {
		"title": "Gold",
		"text": "Your treasury, shown in the top bar with your income per turn. You spend gold to recruit units at your capital, and you earn more at the end of every turn from the provinces you own. Recruits are paid when the turn resolves, from the gold you had before that turn's income. Gold never goes below zero: a recruit you can't afford is cancelled, and the turn report says why.",
	},
	"army": {
		"title": "Army",
		"text": "A group of units in one province, usually led by a commander. Orders go to whole armies: each can move once per turn to a neighboring province, or hold where it is. Its badge on the map counts its units, not its commander. All your armies in a province fight a battle there together, on one side. New recruits join an army at your capital, or form a new one. An army is destroyed when its side loses a battle (there are no retreats yet), or when every fighter in it has fallen.",
	},
	"commander": {
		"title": "Commander",
		"text": "The leader of an army: the Knight Captain for the Aurel Crown, the Warchief for the Thornmane Clans. An army has at most one, and it is not counted among the army's units. In battle it fights from the back line, so enemies reach it only after every unit in front of it has fallen. While it stands, its side gets extra morale and the commander's own trait: Inspire or Pack Leader.",
	},
	"units": {
		"title": "Units",
		"text": "The fighters in an army. The Aurel Crown has Spearmen, Crossbowmen and Knights; the Thornmane Clans have Tuskers, Fangthrowers and War Bears. Every kind of unit has hit points, attack, defense, morale and a recruit cost, plus one trait. Hover a unit's line in the side panel, or a recruit button, to see its numbers. Wounds carry over between battles, and a unit that falls is gone for good.",
	},
	"stat_hit_points": {
		"title": "Hit points",
		"text": "How much damage a unit can take. Every hit in battle takes some away, and a unit at 0 falls and is gone for good. Units do not heal yet: a wounded unit starts its next battle wounded. A side breaks once it has lost a large enough share of the hit points it started the battle with (see Morale and routs).",
	},
	"stat_attack": {
		"title": "Attack",
		"text": "How dangerous a unit's strikes are. Each round of a battle every unit attacks once. The further its attack is above the target's defense, the more likely it is to hit, and a higher attack deals more damage with every hit. A defender on hills, Berserk and Pack Leader add attack in battle. Hit chance and damage has the exact numbers.",
	},
	"stat_defense": {
		"title": "Defense",
		"text": "How hard a unit is to hurt. The further its defense is above the attacker's attack, the less likely an attack is to hit it, and every hit that lands deals less damage. A defender's terrain and fort, and Shield Wall, add defense in battle. Hit chance and damage has the exact numbers.",
	},
	"stat_morale": {
		"title": "Morale",
		"text": "Courage: how much a side can lose before it breaks and flees. In battle a side's morale is the average morale of its units, raised while its commander stands (more with Inspire) and lowered by enemy War Bears' Fury. The higher it is, the larger the share of its starting hit points a side can lose before it routs, and a side that routs loses the battle. Morale and routs has the exact numbers.",
	},
	"stat_cost": {
		"title": "Cost",
		"text": "The gold it takes to recruit one unit at your capital; each recruit button shows it. Recruits are paid when the turn resolves, in the order you gave them, from the gold you had before that turn's income. One you can no longer afford by then is cancelled and costs nothing. Cost plays no part in battle.",
	},
	"unit_traits": {
		"title": "Unit traits",
		"text": "Every kind of unit and every commander has one trait: a special rule for how it fights, such as Shield Wall or Charge. Traits only work in battle. Each trait has its own codex entry, and the battle report points out when one made a difference.",
	},
	# --- computer seats (#35): GameSession computer seats, played by AISeat with the AIPlayer brain.
	"computer_opponent": {
		"title": "Playing against the computer",
		"text": "Any seat can be played by the computer instead of a person. The computer plays by exactly the same rules as you: it sees the same map, it gets the same gold and units, and its orders are checked the same way. It gives its orders at the same time as you, from the map as it stood at the start of the turn, so it never sees the orders you give. After the turn resolves, the turn report shows what it was thinking. Easy makes more mistakes than Normal: it passes up about one in three of its good attacks and captures, recruits at random instead of picking the best mix, works out the odds of fewer battles before it fights, and settles for a thinner guard on its capital. Neither level cheats.",
	},
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
		"text": "If your army moves from A to B while an enemy army moves from B to A, they meet on the border between A and B and fight there. Nobody is defending. The winner finishes its move, and the loser never arrives: its armies are destroyed.",
	},
	"hold": {
		"title": "Holding a province",
		"text": "An army with no move order holds its province. If enemies move in, the holding army is the defender: it gets the province's terrain and fort bonuses in the battle, and if the attackers have not won after 8 rounds, the defender holds and wins.",
	},
	"defended": {
		"title": "Moving into a defended province",
		"text": "Moving into a province where an enemy army is holding starts a battle there. The holding army defends and gets the province's terrain and fort bonuses.",
	},
	"undefended": {
		"title": "Moving into an undefended province",
		"text": "Moving into an enemy or neutral province with no enemy army in it captures it, as long as no enemy army arrives there too.",
	},
	"battle_rounds": {
		"title": "Battles",
		"text": "A battle is fought in rounds, at most 8. Each round every unit and commander attacks one enemy at the same time, so a unit that falls still strikes that round. Attacks go at the enemy's front rank: crossbowmen stand behind their other units and commanders behind everyone, so they are only attacked once nothing in front of them is left. The battle ends when one side is wiped out or breaks and flees (a rout). If every side left breaks in the same round, the one with more of its strength left keeps the field. The winner keeps its wounded units; units that fell are gone. The losing side loses every army it had in the battle, even units still standing: a side that routs is destroyed as it flees, and attackers who have not won after 8 rounds are destroyed too. There are no retreats yet.",
	},
	"battle_round_cap": {
		"title": "When a battle runs out of time",
		"text": "If nobody has won after 8 rounds, the defender holds its ground and wins, and the attacking armies are destroyed (there are no retreats yet). With no defender (a border battle, or armies that all arrived together), the side with the larger share of its starting hit points left wins and the other side's armies are destroyed; an exact tie is settled by a seeded roll.",
	},
	"battle_hit_chance": {
		"title": "Hit chance and damage",
		"text": "Every attack rolls to hit. The chance is 60%, plus 4% for every point the attacker's attack is above the target's defense (or minus 4% for every point below), never lower than 30% or higher than 90%. A hit deals half the attacker's attack (rounded up) minus a quarter of the target's defense (rounded down), at least 1. The battle report shows how often each side actually hit next to the chances it had. It measures luck in damage: how much more or less damage a side's hits did than average rolls would have. One big hit landing can outweigh several small misses, so a side can be lucky in damage while hitting less often than expected.",
	},
	"battle_terrain": {
		"title": "Terrain in battle",
		"text": "Only the defender, the side that was already holding the province, gets the ground: forest +2 defense, hills +1 defense and +1 attack, plains nothing. A fort adds +2 defense on top. Border battles and armies that all arrived at once have no defender, so nobody gets terrain. Knights' charge is weaker in a forest, and Fangthrowers ignore forest and hills cover (not forts).",
	},
	"battle_morale": {
		"title": "Morale and routs",
		"text": "A side's morale is the average morale of its units, +2 while its commander stands, plus trait effects (Inspire, Fury). Morale decides how much a side can lose before it breaks: 20% plus 5% per point of morale, of its starting hit points (at least 25%, at most 95%). Morale 10 breaks after losing 70% of its hit points; morale 6 after 50%. A side that breaks flees and loses the battle, even with units still standing, and its armies are destroyed as they flee (there are no retreats yet).",
	},
	"battle_commanders": {
		"title": "Commanders in battle",
		"text": "A commander fights from the back line, so enemies reach it only after its units have fallen. While it stands its side gets +2 morale, and its own trait: the Knight Captain inspires (+2 more morale), the Warchief leads the pack (+1 attack to every unit).",
	},
	"army_strength": {
		"title": "Army strength",
		"text": "The strength shown for an army is a quick guide to its size: the attack plus defense of every unit and its commander. It does not decide battles. Battles are fought round by round with hit points, morale, terrain and traits, so a stronger-looking army can still lose.",
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
	# --- game flow and winning (#7, #8): GameSession and VictoryCheck ---
	"hotseat": {
		"title": "Taking turns on one computer",
		"text": "Players share one computer and give orders in seat order: player 1 first, then player 2. Your orders stay hidden from the other player. Nothing happens until the last player ends their turn. Then all orders resolve together, and the turn report shows everyone what happened.",
	},
	"handoff": {
		"title": "Passing the computer",
		"text": "When you end your turn, the screen hides the map and your orders and asks you to pass the computer to the next player. The game continues only when they say they are ready, so nobody sees the other side's orders.",
	},
	"victory": {
		"title": "Winning the game",
		"text": "Capture the enemy capital to win. A capital is captured like any other province: after battles, if only your armies are in it, it becomes yours. The game ends when that turn finishes resolving, and the victory screen shows the turns played, the battles fought and how many provinces each side holds.",
	},
	"simultaneous_capture": {
		"title": "Both capitals fall in the same turn",
		"text": "Turns resolve at the same time for everyone, so both sides can capture each other's capital in the same turn. If that happens, nobody wins: the game ends in a draw.",
	},
}


static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})


static func text(id: String) -> String:
	return entry(id).get("text", "")
