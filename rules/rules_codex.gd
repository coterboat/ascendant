class_name RulesCodex
## Plain-language rules text for the in-game codex, tooltips and the turn report.
## Every turn event carries a "codex" key naming one of these entries.
## This text is the player-facing statement of the rules in TurnResolver and AutoBattleResolver
## (the "battle_*" and "trait_*" entries); keep them in sync. The battle and trait entries take their
## numbers from AutoBattleResolver's constants (the trait entries start with its TRAIT_TEXT), so a
## retuned number shows up here by itself. StubBattleResolver is a test-only stand-in and has no
## entry: players never see its rules.

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
		"text": "Some provinces have a fort, drawn as a small tower on the map. An army holding a province with a fort gets +2 defense in battles there, on top of the terrain. Only the defender gets it, never armies that just arrived. A fort does not change income.",
	},
	"terrain_plains": {
		"title": "Plains",
		"text": "Open flat land. Plains give no bonus in battle to either side, and Knights charge at full strength here. Like all terrain, plains do not change movement or income.",
	},
	"terrain_forest": {
		"title": "Forest",
		"text": "Dense woodland. An army holding a forest province gets +2 defense in battles there; armies that just arrived get nothing. Knights' charge is weaker in a forest. Terrain does not change movement or income.",
	},
	"terrain_hills": {
		"title": "Hills",
		"text": "Rugged high ground. An army holding a hills province gets +1 defense and +1 attack in battles there; armies that just arrived get nothing. Terrain does not change movement or income.",
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
		"text": "Courage: how much a side can lose before it breaks and flees. In battle a side's morale is the average morale of its units, raised while its commander or ruler stands (more with Inspire) and lowered by enemy War Bears' Fury (and the Great Thornmane's Dread). The higher it is, the larger the share of its starting hit points a side can lose before it routs, and a side that routs loses the battle. Morale and routs has the exact numbers.",
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
	# --- the pre-game build screen (M2-5, #33): BuildScreen. The rules it shows are in the ruler block below. ---
	"build_screen": {
		"title": "Choosing builds",
		"text": "In a game with rulers, each player picks a build before the first turn: one of their faction's two rulers, and the mandates it buys with its power. Tick mandates to spend power, or press a preset for a ready-made build; the balanced preset is picked to start with. The power bar shows how much you spend and how much your ruler keeps, and the previews show what your ruler and your nation get with this build. Hover any number to see where it comes from. With two players on one computer, the screen is covered between builders, so neither sees the other's build until the game starts. A computer player picks one of its faction's presets in secret, decided by the seed. Builds are public from the first turn.",
	},
	"phase_order": {
		"title": "How a turn resolves",
		"text": "Everyone gives orders first. Then the whole turn resolves at once, always in this order: 1. sacrifice: each ruler's Sacrifice order is checked and applied, faction by faction, so its new mandate already counts this turn; 2. orders: every other order is checked against the state after the sacrifices; 3. movement; 4. battles; 5. capture, then Sworn Vassals; 6. recruitment; 7. income; 8. rulers: Mending Light heals, rulers heal, then successors who are due arrive. Without rulers, steps 1 and 8 have nothing to do. In a game with paths (the M4 preview), research resolves between income and rulers: see the research phase. The same orders and seed always give the same result.",
	},
	"orders": {
		"title": "Orders",
		"text": "Each turn you can move each army once, to a province next to it, and recruit units at your capital. An army with no move order holds where it is. An order that breaks a rule is rejected, and the turn report says why. In a game with rulers there is more. With King's Roads an army can instead make a road move, two provinces through your own land. With Warband Muster you can also recruit with the Ninth Fang where it stands. And a living ruler can give one Sacrifice order per turn, giving up power for a new mandate: it resolves before every other order, so your other orders are checked as if it had already happened. In a game with paths, a research order chooses what your faction researches.",
	},
	"move": {
		"title": "Moving",
		"text": "An army moves one province per turn, to a neighbor of the province it is in. It arrives during this turn's resolution and is ready to act next turn. All armies move at the same time, so an army that leaves a province is gone before anyone arrives there. In a game with rulers, King's Roads let an army move two provinces instead, through a neighbor to a province next to that, when you owned both at the start of the turn. Such a road move never fights a border battle and never stops halfway.",
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
	# The battle_* entries state AutoBattleResolver's rules, with its numbers taken from its constants.
	"battle_rounds": {
		"title": "Battles",
		"text": "A battle is fought in rounds, at most %d." % AutoBattleResolver.ROUND_CAP
			+ " Each round every unit, commander and ruler attacks one enemy at the same time, so a fighter that falls still strikes that round. Attacks go at the enemy's front rank. Crossbowmen stand in the second rank, behind their other units, which shield them while at least as many of those stand as crossbowmen (Fangthrowers reach them anyway); commanders stand behind everyone and are only attacked once no unit is left in front of them. In a game with rulers, a ruler fights in its own rank: King Corvane, the Great Thornmane and the Ninth Fang in the front rank, the Ever-Regent in the second rank, where the same shield rule covers him. The battle ends when one side is wiped out or breaks and flees (a rout). If every side left breaks in the same round, the one with more of its strength left keeps the field. The winner keeps its wounded units; units that fell are gone, and a ruler that fell dies. The losing side loses every army it had in the battle, even units still standing: a side that routs is destroyed as it flees, and attackers who have not won after %d rounds are destroyed too. There are no retreats yet." % AutoBattleResolver.ROUND_CAP,
	},
	"battle_round_cap": {
		"title": "When a battle runs out of time",
		"text": "If nobody has won after %d rounds, the defender holds its ground and wins, and the attacking armies are destroyed (there are no retreats yet). With no defender (a border battle, or armies that all arrived together), the side with the larger share of its starting hit points left wins and the other side's armies are destroyed; an exact tie is settled by a seeded roll." % AutoBattleResolver.ROUND_CAP,
	},
	"battle_hit_chance": {
		"title": "Hit chance and damage",
		"text": "Every attack rolls to hit. The chance is %d%%" % AutoBattleResolver.BASE_HIT
			+ " (70% for a side with the Drilled Ranks mandate),"
			+ " plus %d%% for every point the attacker's attack is above the target's defense" % AutoBattleResolver.HIT_PER_POINT
			+ " (or minus %d%% for every point below)," % AutoBattleResolver.HIT_PER_POINT
			+ " never lower than %d%%" % AutoBattleResolver.MIN_HIT + " or higher than %d%%." % AutoBattleResolver.MAX_HIT
			+ " A hit deals half the attacker's attack (rounded up) minus a quarter of the target's defense (rounded down), at least %d." % AutoBattleResolver.MIN_DAMAGE
			+ " The battle report shows how often each side actually hit next to the chances it had. It measures luck in damage: how much more or less damage a side's hits did than average rolls would have. One big hit landing can outweigh several small misses, so a side can be lucky in damage while hitting less often than expected.",
	},
	"battle_terrain": {
		"title": "Terrain in battle",
		"text": "Only the defender, the side that was already holding the province, gets the ground: forest +%d defense," % AutoBattleResolver.TERRAIN.forest.defense
			+ " hills +%d defense" % AutoBattleResolver.TERRAIN.hills.defense + " and +%d attack, plains nothing." % AutoBattleResolver.TERRAIN.hills.attack
			+ " A fort adds +%d defense on top." % AutoBattleResolver.FORT_DEFENSE
			+ " Border battles and armies that all arrived at once have no defender, so nobody gets terrain. Knights' charge is weaker in a forest.",
	},
	"battle_morale": {
		"title": "Morale and routs",
		"text": "A side's morale is the average morale of its units, +%d while its commander stands, plus trait effects (Inspire, Fury)." % AutoBattleResolver.COMMANDER_MORALE
			+ " In a game with rulers, a side's ruler adds +%d while it stands, on top of the commander's," % RulerData.RULER_MORALE
			+ " and the Great Thornmane's Dread takes 1 or 2 from every enemy side in a province battle while the avatar stands. A side with no units uses the highest morale among its commanders and ruler."
			+ " Morale decides how much a side can lose before it breaks: %d%%" % AutoBattleResolver.BREAK_BASE_PCT
			+ " plus %d%% per point of morale, of its starting hit points" % AutoBattleResolver.MORALE_PCT_PER_POINT
			+ " (at least %d%%," % AutoBattleResolver.MIN_BREAK_PCT + " at most %d%%)." % AutoBattleResolver.MAX_BREAK_PCT
			+ " Morale 10 breaks after losing %d%% of its hit points;" % (AutoBattleResolver.BREAK_BASE_PCT + 10 * AutoBattleResolver.MORALE_PCT_PER_POINT)
			+ " morale 6 after %d%%." % (AutoBattleResolver.BREAK_BASE_PCT + 6 * AutoBattleResolver.MORALE_PCT_PER_POINT)
			+ " A side that breaks flees and loses the battle, even with units still standing, and its armies are destroyed as they flee (there are no retreats yet)."
			+ " With the Iron Discipline mandate, a side does not break while one of its commanders stands, except at the end of the last round (round %d)." % AutoBattleResolver.ROUND_CAP,
	},
	"battle_commanders": {
		"title": "Commanders in battle",
		"text": "A commander fights from the back line, so enemies reach it only after its units have fallen. While it stands its side gets +%d morale," % AutoBattleResolver.COMMANDER_MORALE
			+ " and its own trait: the Knight Captain inspires (+%d more morale)," % AutoBattleResolver.INSPIRE_MORALE
			+ " the Warchief leads the pack (+%d attack to every unit)." % AutoBattleResolver.PACK_LEADER_ATTACK
			+ " When the battle report explains a result, a commander's damage counts only as far as it beat what the same gold in its side's ordinary units would have dealt; its morale and its trait are counted on their own."
			+ " A ruler is not a commander: it fights in its own rank, its +%d morale adds to the commander's," % RulerData.RULER_MORALE
			+ " and Iron Discipline holds a line only while a commander stands. The report counts all the damage a ruler deals, since it costs no gold.",
	},
	"army_strength": {
		"title": "Army strength",
		"text": "The strength shown for an army is a quick guide to its size: the attack plus defense of every unit and its commander. It does not decide battles. Battles are fought round by round with hit points, morale, terrain and traits, so a stronger-looking army can still lose.",
	},
	"battle_odds": {
		"title": "Battle odds",
		"text": "Before you attack, the forecast fights the same battle with the real rules 24 times on fixed test seeds and tells you how often you won: likely win (65% or more), close, or likely loss (35% or less), with the main reasons. The real battle uses this turn's own rolls, so a likely win can still go wrong.",
	},
	# --- battle playback (M3-2, #57; design/M3_BATTLES.md §7.2): the terms the battle player's captions,
	# key moments and hover explanations use (BattleCaptions, BattleMoments and BattleExplain link here).
	# Numbers from AutoBattleResolver's constants.
	"battle_playback": {
		"title": "Watching a battle",
		"text": "A battle is fought by the rules first, all at once, and only then played back. The playback shows exactly what happened: the same rolls, hits, wounds and morale checks as the battle report, round by round, so watching it can never change the result. A caption after every round says what mattered most, and hovering anyone shows what it is doing and the numbers behind it. Speed it up, pause it, skip to the end or jump to its key moments whenever you like.",
	},
	"battle_formation": {
		"title": "Ranks on the battlefield",
		"text": "Fighters stand in the ranks the battle rules give them. The front rank holds every unit without Volley, and the rulers who fight in front. The second rank holds the Crossbowmen and the Ever-Regent, shielded while at least as many front-rank fighters stand as second-rank ones. Commanders stand in the back line, out of reach while any unit stands. The defender holds its own ground. Where a fighter stands within its rank is only for show: who attacks whom is decided by the rules, among the enemies it can reach.",
	},
	"battle_strength": {
		"title": "Strength bars",
		"text": "Each side has a strength bar: the hit points it has left, out of what it started the battle with. A white notch marks where the side breaks, with the exact number beneath it (\"breaks at 26 hp or less\"): a side breaks at the end of a round once it has lost %d%%" % AutoBattleResolver.BREAK_BASE_PCT
			+ " plus %d%% per point of morale of its starting hit points" % AutoBattleResolver.MORALE_PCT_PER_POINT
			+ " (at least %d%%," % AutoBattleResolver.MIN_BREAK_PCT + " at most %d%%)." % AutoBattleResolver.MAX_BREAK_PCT
			+ " When its morale changes, because a commander, a ruler or an enemy War Bear fell, the notch moves. Whoever is further above its notch is closer to winning.",
	},
	"battle_pending_damage": {
		"title": "Damage lands at the end of the round",
		"text": "Every fighter attacks once a round, all at the same time. The damage of a round's hits shows as a hatched chunk on the hit points bar and lands only at the end of the round, so a fighter that falls still makes its own attack that round. Then the fallen fall, and each side's morale is checked.",
	},
	"battle_key_moments": {
		"title": "Key moments",
		"text": "The battle player can jump to five key moments. First to fall: the first fighter whose hit points reach 0 (not the first hit). Charge: the first attack of a Knights' charge in round 1. Ruler falls: each ruler that falls. Turning point: the round after which the winner stayed further from breaking than every other side to the end (how far a side is from breaking is its break percentage minus the share of its hit points it has lost); there is none when the winner was ahead from the start, when the battle lasted one round, or when it ended in a mutual rout or at the round cap. Rout: each side that breaks, or has no one left standing. A moment the battle doesn't have is greyed out, with the reason.",
	},
	"battle_auras": {
		"title": "Morale auras",
		"text": "Some fighters change morale while they stand, shown as a ring at their feet. Rings marked ▲ raise their own side's morale: a commander +%d," % AutoBattleResolver.COMMANDER_MORALE
			+ " the Knight Captain's Inspire +%d more," % AutoBattleResolver.INSPIRE_MORALE + " a ruler +%d." % RulerData.RULER_MORALE
			+ " Rings marked ▼ lower every enemy side's morale: each War Bear's Fury -%d" % AutoBattleResolver.FURY_MORALE
			+ " (at most -%d in all), and the Great Thornmane's Dread -1 or -2." % AutoBattleResolver.FURY_MAX
			+ " When the fighter falls, its ring fades, and the next morale check counts without it.",
	},
	# Trait entries start with AutoBattleResolver.TRAIT_TEXT, built from the constants the rules use.
	"trait_shield_wall": {
		"title": "Shield Wall (Spearmen)",
		"text": AutoBattleResolver.TRAIT_TEXT["Shield Wall"] + " Spearmen standing alone lose it.",
	},
	"trait_volley": {
		"title": "Volley (Crossbowmen)",
		"text": AutoBattleResolver.TRAIT_TEXT["Volley"] + " Behind a line of Spearmen or Knights at least as big as theirs, Crossbowmen keep shooting, out of reach of everything but Fangthrowers.",
	},
	"trait_charge": {
		"title": "Charge (Knights)",
		"text": AutoBattleResolver.TRAIT_TEXT["Charge"] + " Heavy horses are slowed in a forest.",
	},
	"trait_inspire": {
		"title": "Inspire (Knight Captain)",
		"text": AutoBattleResolver.TRAIT_TEXT["Inspire"] + " With it, the Knight Captain's side can take more losses before it breaks.",
	},
	"trait_berserk": {
		"title": "Berserk (Tuskers)",
		"text": AutoBattleResolver.TRAIT_TEXT["Berserk"] + " Wounds carry over between battles, so a wounded Tusker starts the next battle already berserk.",
	},
	"trait_skirmish": {
		"title": "Skirmish (Fangthrowers)",
		"text": AutoBattleResolver.TRAIT_TEXT["Skirmish"] + " Fangthrowers are the Thornmane answer to Crossbowmen shooting from behind a shield wall.",
	},
	"trait_fury": {
		"title": "Fury (War Bear)",
		"text": AutoBattleResolver.TRAIT_TEXT["Fury"] + " Each War Bear still standing roars; kill the bears and the roar stops.",
	},
	"trait_pack_leader": {
		"title": "Pack Leader (Warchief)",
		"text": AutoBattleResolver.TRAIT_TEXT["Pack Leader"] + " Commanders don't get it, only units.",
	},
	"capture": {
		"title": "Capturing provinces",
		"text": "After battles, a province with armies of only one faction in it becomes that faction's. This happens whether it was neutral or an enemy's. Taking the enemy capital stops them from recruiting.",
	},
	"recruit": {
		"title": "Recruiting",
		"text": "Recruit units from your own roster at your capital. Each unit costs gold, paid in the order you gave the orders, from your gold before this turn's income. Recruiting happens after capture, so if your capital falls this turn your recruits are cancelled and you keep the gold. New units join your army at the capital, or form a new army if none is there. In a game with rulers, recruits never join the ruler's army: they join another army of yours there, or form a new one. With Muster Grounds every recruit costs less, and every price on screen already includes it. With Warband Muster the Ninth Fang can also recruit regular units where it starts the turn, a few each turn (more at a higher ability rank), paid from the same gold; they appear there at the end of the turn, and are cancelled and cost nothing if the Fang has fallen or that province isn't yours after the battles.",
	},
	"income": {
		"title": "Income",
		"text": "At the end of the turn, each faction earns the income of every province it owns, after this turn's captures and recruits. In a game with rulers, two things can add to it. With Heavy Tithes every province you own earns more gold, the capital included. And King Corvane's Royal Court adds gold to the province he is in at the end of the turn, if you own it, as long as he lives. The income shown for each province and in the top bar already includes both; hover it to see each part.",
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
		"text": "Capture the enemy capital to win. A capital is captured like any other province: after battles, if only your armies are in it, it becomes yours. The game ends when that turn finishes resolving, and the victory screen shows the turns played, the battles fought and how many provinces each side holds. In a game with rulers, a ruler's death never ends the game, however often it happens: a successor takes over at the capital, and only the capital decides who wins. The victory screen also shows each player's build.",
	},
	"simultaneous_capture": {
		"title": "Both capitals fall in the same turn",
		"text": "Turns resolve at the same time for everyone, so both sides can capture each other's capital in the same turn. If that happens, nobody wins: the game ends in a draw.",
	},
	# --- the ruler (M2, #29): rulers, succession, mandates, builds. Rules: RulerRules; numbers: data/rulers.gd,
	# data/mandates.gd, data/build_presets.gd. The M2 ticket that ships a mechanic finishes its entry. ---
	"ruler": {
		"title": "Ruler",
		"text": "Every faction is led by a ruler, chosen before the game: the Aurel Crown picks King Corvane or the Ever-Regent, the Thornmane Clans pick the Great Thornmane or the Ninth Fang. Each ruler has a power pool of 10. Power the ruler keeps makes it strong in person: its hit points, attack, defense and the rank of its province ability. Power it spends buys mandates, faction-wide traits that last the whole game. The ruler travels as its own army and fights in battles. Its death never ends the game: capturing the enemy capital does.",
	},
	"ruler_power": {
		"title": "Ruler power",
		"text": "Every ruler has a pool of 10 power. Before the game you split it: power spent buys mandates for your whole faction, and power kept makes the ruler strong in person. Mandates cost 2 to 4 power each, and taking all of them would cost far more than 10, so every build is a choice. Later in the game a living ruler can give up more power for a new mandate by sacrifice.",
	},
	"kept_power": {
		"title": "Kept power",
		"text": "Kept power is the ruler power you did not spend: 10, minus the mandates chosen before the game, minus sacrifices, minus what a succession costs. It is a whole number from 0 to 10 and never goes up. It sets the ruler's hit points, attack and defense, and its ability rank. A ruler with little kept power is easier to kill.",
	},
	"ability_rank": {
		"title": "Ability rank",
		"text": "Each ruler has one province ability, which works in the province the ruler is in. Its strength is the ability rank: 1, plus 1 for every 3 kept power, rounded down. That is rank 1 with 0 to 2 kept power, rank 2 with 3 to 5, rank 3 with 6 to 8 and rank 4 with 9 or 10.",
	},
	"ruler_rank": {
		"title": "Where a ruler fights",
		"text": "King Corvane, the Great Thornmane and the Ninth Fang fight in the front rank, with the other units, so enemies can attack them from the first round, and they count as part of the line that shields the crossbowmen. The Ever-Regent fights in the second rank, with the crossbowmen, under the same rule: the front rank shields him while at least as many front-rank fighters stand as second-rank ones (the Regent counts among those), and Fangthrowers, with Skirmish, reach him anyway. Once his side's front rank is too thin, or gone, any enemy can attack him. Commanders still stand behind everyone.",
	},
	"ruler_in_battle": {
		"title": "Rulers in battle",
		"text": "A ruler fights beside every army of yours in the same battle, with the hit points, attack and defense its kept power gives it. While it stands, its side gets +2 morale, on top of a commander's +2. If no regular units fight on its side, the side's morale is the highest morale among its commanders and its ruler. Rulers are not units: mandates and traits that name units, such as Royal Armories, Veteran Levies or Pack Leader, skip them; those that name fighters, such as Drilled Ranks, Blood Frenzy and Feast of Victory, count it. A ruler whose hit points reach 0 falls and dies even if its side wins, and a ruler on a losing side is lost with its army. The battle report lists the ruler under Who fought, counts it among the losses, and names it in the why when its damage or its morale decided the battle: all of its damage counts, since a ruler costs no gold.",
	},
	"ruler_healing": {
		"title": "Ruler healing",
		"text": "At the end of every turn a living ruler heals a quarter of its maximum hit points, rounded up, wherever it is, even after a battle that turn: a King with 46 maximum hit points heals 12. This happens in the rulers phase, the last step of the turn after income: first Mending Light heals, then rulers heal, then successors who are due arrive. Regular units and commanders do not heal on their own; only Mending Light and Feast of Victory heal them.",
	},
	"ruler_army": {
		"title": "The ruler's army",
		"text": "A ruler travels alone, as its own army: no units and no commander. It moves like any army, one province per turn, or two by a road move with King's Roads. It captures provinces like any army, and it fights together with every other army of yours in the same province or on the same border. Recruits never join the ruler's army, so it can always move on its own: with Warband Muster, the Ninth Fang's recruits join another army of yours where it started the turn, or form a new one. At the start of the game each capital holds the starting army and the ruler's army. A living ruler is always on the map in its army: when the ruler dies the army goes with it, and a successor arrives later in a new ruler's army at the capital.",
	},
	"ruler_death": {
		"title": "When a ruler dies",
		"text": "A ruler dies when its hit points reach 0, even if its side wins the battle, or when it is on the losing side of a battle: a ruler on a losing side is lost with its army; there are no retreats yet. The death is recorded right after that battle, and the turn report says who succeeds, where, when and with how much kept power. While a faction has no ruler it has no province ability, no ruler in battle and cannot sacrifice, but its mandates stay. What comes next depends on the kind of ruler: see Succession. A ruler's death never ends the game; only the capital decides that.",
	},
	"succession": {
		"title": "Succession",
		"text": "When a ruler dies during a turn, a successor arrives at your capital at the end of a later turn, in the rulers phase, at full hit points, in a new ruler's army of its own, and can take orders from the next turn. How long that takes and how much kept power the successor has depend on the kind of ruler, and the kept power at the moment of death decides it. A mortal line crowns an heir 2 turns later with half the kept power, rounded down. The undying Ever-Regent re-forms 4 turns later with all of it. The Great Thornmane takes a new body 1 turn later with 3 less kept power, for good, never below 0. Each successor is the next generation of the line, and mandates always stay. If you don't hold your capital when the successor is due, it waits and arrives at the end of the first turn you hold it again.",
	},
	"succession_mortal": {
		"title": "Succession: mortal line",
		"text": "King Corvane and the Ninth Fang are mortal lines. When one dies during turn 4, the heir is crowned at your capital at the end of turn 6, 2 turns later, and can take orders from turn 7. The heir has half the dead ruler's kept power, rounded down: 10 kept power becomes 5, and 7 becomes 3. The heir is the next of the line: Corvane II after King Corvane I (crowned as King Corvane II), the Tenth Fang after the Ninth.",
	},
	"succession_undying": {
		"title": "Succession: undying",
		"text": "The Ever-Regent is bound to the sunstone in Crownkeep and cannot truly die. When he is destroyed during turn 4, he re-forms at your capital at the end of turn 8, 4 turns later, with the same kept power he had, and can take orders from turn 9.",
	},
	"succession_god": {
		"title": "Succession: god",
		"text": "The Great Thornmane is a god walking in a body of briar and fur. When the body is slain during turn 4, the god takes a new one at your capital at the end of turn 5, 1 turn later, and can take orders from turn 6. The new body has 3 less kept power for good, never below 0: 10 becomes 7, and 2 becomes 0.",
	},
	"mandates": {
		"title": "Mandates",
		"text": "Mandates are faction-wide traits bought with ruler power. Each faction can take the six shared mandates (Iron Discipline, Drilled Ranks, Veteran Levies, Heavy Tithes, Muster Grounds and Sworn Vassals) and two of its own: Royal Armories and King's Roads for the Aurel Crown, Blood Frenzy and Feast of Victory for the Thornmane Clans. They cost 2 to 4 power, each can be taken once, and together they must fit in the pool of 10. Mandates work from turn 1, or from the turn a sacrifice buys them, and never go away, even when the ruler dies. Regular units means a faction's roster units, not commanders or rulers; fighters means units, commanders and the ruler.",
	},
	"sacrifice": {
		"title": "Sacrifice",
		"text": "During the game a living ruler can give up kept power for a new mandate with a Sacrifice order: open the ruler panel (Ruler in the top bar) and press Sacrifice for a mandate. It costs the mandate's price plus 1, so Royal Armories costs 4. The mandate must be on your faction's list and not yours yet, the ruler must be alive and keep at least that much power, and you can give one Sacrifice order per turn. It resolves first in the turn, before any other order is checked, so the new mandate already counts in that turn's moves, battles, recruits and income: King's Roads bought this way allows a road move the same turn. Kept power drops for good, and with it the ruler's hit points, attack, defense and ability rank; its current hit points drop by as much as its maximum, never below 1. Your other orders are checked as if the sacrifice had already happened. If you cancel it, any order that relied on it is removed, and your orders list says why. Before you confirm, the dialog shows every number of yours it changes, before and after, and your queued attacks fought again. The other player learns of it from the turn report.",
	},
	"build": {
		"title": "Builds",
		"text": "Before the game each player picks a build: one of their faction's two rulers and the mandates it buys. Whatever the mandates don't cost is the ruler's kept power, so a build with no mandates keeps all 10. A build is illegal if it costs more than 10, takes a mandate twice, or takes a mandate only another faction can have. Builds are picked in secret but are public from turn 1, so battle odds can count the enemy's mandates.",
	},
	"build_presets": {
		"title": "Build presets",
		"text": "Each faction has three ready-made builds: one keeps all its power, one spends it all, and one is balanced. Aurel Crown: Warrior King (King Corvane, no mandates), Iron Crown (King Corvane with Royal Armories, Heavy Tithes and Veteran Levies) and Regent's Court (the Ever-Regent with Royal Armories and King's Roads, keeping 5). Thornmane Clans: Beast-God Unbound (the Great Thornmane, no mandates), Clan Moot (the Ninth Fang with Iron Discipline, Blood Frenzy and Sworn Vassals) and Blood of the Fang (the Ninth Fang with Iron Discipline and Drilled Ranks, keeping 5). A game with rulers gives a faction its balanced build unless another is chosen. AI seats pick one of the three.",
	},
	"ai_seat": {
		"title": "AI seats",
		"text": "A seat can be played by the computer (see Playing against the computer). In a game with rulers, an AI seat picks one of its faction's three build presets with a seeded roll, the first roll of its own sequence, so the same seed always gives the same build; nobody sees it before the game starts, and it is public from the first turn. The preset says how it plays its ruler. A ruler that keeps 2 or less power, or one whose build keeps it home, stays at or walks back to the capital. Any other ruler marches with the computer's strongest army, joins its attacks only when the odds with the ruler fighting are a likely win, and never ends a turn alone next to an enemy army or anywhere it would more likely lose than win if attacked; otherwise it holds or falls back toward the capital. Once per turn at most, it gives up power for its preset's next mandate when an enemy army next to its capital could win there, or from turn 8 when its income has fallen to four fifths of the strongest enemy's or less. It uses what it owns: road moves with King's Roads when they shorten a march or bring an army home in time, and recruits with the Ninth Fang wherever the Fang stands in its own land, unless the capital needs the defenders. It recruits with traits in mind, never fielding more crossbowmen than front-rank units to shield them, and buying skirmishers against enemy crossbowmen. Its orders go through the same checks as yours and are recorded like anyone's, so the game can be replayed, and after each turn the report says what it was thinking.",
	},
	"ruler_aurel_king": {
		"title": "King Corvane",
		"text": "Ruler of the Aurel Crown, a mortal line. An ordinary man of the Aurel line: spend his power and he governs the best-equipped kingdom in the land; keep it and he rides to war as a paladin. He fights in the front rank. Hit points 18, plus 2 for every kept power; attack 9 and defense 8, each plus 1 for every 2 kept power, rounded down; morale 10. With all 10 kept: 38 hit points, attack 14, defense 13. Province ability: Royal Court. When he dies, his heir is crowned 2 turns later with half his kept power.",
	},
	"ruler_ever_regent": {
		"title": "The Ever-Regent",
		"text": "Ruler of the Aurel Crown, undying. An archmage who bound his life to the sunstone in Crownkeep: he cannot die, only be broken, and he re-forms slowly. His spells count as attacks until magic comes to the game. He fights in the second rank. Hit points 14, plus 1 for every kept power; attack 8, plus 1 for every kept power; defense 6, plus 1 for every 2 kept power, rounded down; morale 10. With all 10 kept: 24 hit points, attack 18, defense 11. Province ability: Mending Light. When he is destroyed, he re-forms 4 turns later with all his kept power.",
	},
	"ruler_thornmane_avatar": {
		"title": "The Great Thornmane",
		"text": "Ruler of the Thornmane Clans, a god. The clans' beast-god, walking among them in a body of briar and fur: when the body is slain, the god takes a new one, a little less of itself each time. It fights in the front rank. Hit points 24, plus 3 for every kept power; attack 8, plus 1 for every kept power; defense 7, plus 1 for every 2 kept power, rounded down; morale 14. With all 10 kept: 54 hit points, attack 18, defense 12. Province ability: Dread. When its body is slain, the god returns 1 turn later with 3 less kept power, for good.",
	},
	"ruler_fang_chieftain": {
		"title": "The Ninth Fang",
		"text": "Ruler of the Thornmane Clans, a mortal line. The high chieftain of the old fang bloodline: when one Fang falls, the next of the blood takes the mantle. The Fang fights in the front rank. Hit points 20, plus 2 for every kept power; attack 9, plus 1 for every kept power; defense 7, plus 1 for every 2 kept power, rounded down; morale 12. With all 10 kept: 40 hit points, attack 19, defense 12. Province ability: Warband Muster. When the Fang dies, the next Fang is crowned 2 turns later with half the kept power.",
	},
	"ability_royal_court": {
		"title": "Royal Court",
		"text": "King Corvane's province ability. In the income phase, the province the King is in earns more gold, if you own it: 2 more at ability rank 1, 3 at rank 2, 4 at rank 3 and 5 at rank 4. It follows him: it counts where he ends the turn, after movement and battles. While he is dead there is no Royal Court. It shows in that province's income and in your gold.",
	},
	"ability_mending_light": {
		"title": "Mending Light",
		"text": "The Ever-Regent's province ability. At the end of each turn, each of your wounded units and commanders in the Regent's province heals 3 hit points at ability rank 1, 6 at rank 2, 9 at rank 3 or 12 at rank 4, up to its maximum. It doesn't heal rulers; they heal on their own.",
	},
	"ability_dread": {
		"title": "Dread",
		"text": "The Great Thornmane's province ability. Every enemy side in a province battle the avatar fights in has 1 less morale at every ability rank, while the avatar stands, so it breaks sooner. It doesn't work in border battles. It adds to a War Bear's Fury.",
	},
	"ability_warband_muster": {
		"title": "Warband Muster",
		"text": "The Ninth Fang's province ability. Each turn you may recruit regular units with the Fang: 1 at ability rank 1, 2 at rank 2, 3 at rank 3 and 4 at rank 4, at the usual prices (Muster Grounds included). Select the Fang's province to find the Recruit with the Ninth Fang buttons. The recruits gather where the Fang starts the turn and join your armies there at the end of the turn, even if the Fang marches on, so they can't reinforce an army the moment it moves up; if the Fang has fallen or that province isn't yours by then, they are cancelled and cost nothing. They are paid from the same gold as capital recruits, in the order you gave them. Commanders still come only from the capital.",
	},
	"mandate_iron_discipline": {
		"title": "Iron Discipline",
		"text": "Shared mandate, 3 power. Your side never breaks (routs) while one of your commanders in that battle stands, except at the end of the last round (round %d): there the usual morale check applies, so a line it holds past its breaking point can't win by lasting out the round cap. Rulers don't count: it needs a commander. Once the last commander falls, the usual morale check applies from the end of that round. It is worth more to the Thornmane Clans, whose morale is lower." % AutoBattleResolver.ROUND_CAP,
	},
	"mandate_drilled_ranks": {
		"title": "Drilled Ranks",
		"text": "Shared mandate, 2 power. Your fighters' base hit chance is 70% instead of 60%: every attack your units, commanders and ruler make hits 70% of the time, plus 4% for every point of attack above the target's defense (or minus 4% for every point below), never lower than 30% or higher than 90%.",
	},
	"mandate_veteran_levies": {
		"title": "Veteran Levies",
		"text": "Shared mandate, 3 power. Each of your regular units has 2 more maximum hit points than its type, and new recruits, the starting army included, arrive at the new maximum. Bought by sacrifice, your regular units already on the map gain 2 maximum and 2 current hit points at once.",
	},
	"mandate_heavy_tithes": {
		"title": "Heavy Tithes",
		"text": "Shared mandate, 4 power. In the income phase, every province you own earns 2 more gold, the capital included. It shows in each province's income and in your gold.",
	},
	"mandate_muster_grounds": {
		"title": "Muster Grounds",
		"text": "Shared mandate, 4 power. Every recruit, commanders included, costs a fifth less: a fifth of its price, rounded down, comes off. Aurel Crown: Spearmen 7, Crossbowmen 8, Knights 16, Knight Captain 28. Thornmane Clans: Tuskers 9, Fangthrowers 7, War Bear 18, Warchief 28. It counts at the capital and for recruits made with Warband Muster, and every price on screen already includes it.",
	},
	"mandate_sworn_vassals": {
		"title": "Sworn Vassals",
		"text": "Shared mandate, 4 power. Each turn, in the capture phase after armies have captured provinces, one neutral province next to your land swears fealty and joins you: of the provinces with no owner and no army in them that border one you own, the one with the highest income (a tie goes to the one first in alphabetical order). If another faction's Sworn Vassals picks the same province that turn, neither gets it, and neither picks another. At most one province joins you per turn, and no gold changes hands. The map marks the province that will join with a pennant in its new owner's colour (slate when two factions want it); its forecast counts your queued moves and assumes every other army stays put.",
	},
	"mandate_royal_armories": {
		"title": "Royal Armories",
		"text": "Aurel Crown mandate, 3 power. Your regular units have +1 attack: the starting army, every recruit, and the units you already have when it is bought by sacrifice.",
	},
	"mandate_kings_roads": {
		"title": "King's Roads",
		"text": "Aurel Crown mandate, 2 power. Armies can move two provinces in one turn inside your own territory, through a province next to them to one next to that, when you owned both at the start of the turn. Select an army: the provinces it can reach by road get a dashed gilt ring, and clicking one orders the road move, with an arrow that bends through the province it goes through. A road move never fights on a border and never stops halfway. If an enemy army moves into the same province, you fight there, and nobody defends unless one of your armies held it.",
	},
	"mandate_blood_frenzy": {
		"title": "Blood Frenzy",
		"text": "Thornmane Clans mandate, 3 power. Each of your fighters below its full hit points has +3 attack: units, commanders and the ruler. A Tusker's Berserk adds to it, for +6. Wounds carry over between battles, so a wounded army starts its next battle in a frenzy.",
	},
	"mandate_feast_of_victory": {
		"title": "Feast of Victory",
		"text": "Thornmane Clans mandate, 3 power. After each battle you win, every fighter of yours still standing in it heals to its full hit points: units, commanders and the ruler. It works against Blood Frenzy, which wants wounds.",
	},
	"road_move": {
		"title": "Road moves",
		"text": "With King's Roads, a move order can name a province to go through: from A through B to C, where B is next to A, C is next to B, C is not A, and you owned both B and C at the start of the turn. The army moves straight from A to C during movement. It never fights a border battle and never stops in B. If enemies are in C after movement, there is a battle there as usual: an enemy army that arrived too fights you with nobody defending. When two ways through are open, the order line has a button to take the other one; it arrives at the same time either way. The forecast says which way it goes and when it arrives.",
	},
	"field_recruit": {
		"title": "Recruiting in the field",
		"text": "With Warband Muster, the Ninth Fang can recruit regular units where it stands, not only at the capital: up to its ability rank each turn, at the usual prices. Select the Fang's province to recruit with it. They gather where the Fang starts the turn and appear there at the end of the turn, joining your first army there that isn't the Fang's own, or forming a new one, even if the Fang has marched on; if you no longer own that province then, or if the Fang has fallen, they are cancelled and you keep the gold. Commanders still come only from the capital.",
	},
	# --- M4-1 (#66): research and the paths of ascension (design/M4_ASCENSION.md §2, §3, §9.3). One contiguous
	# block. The numbers match data/paths.gd; tests/test_research.gd checks them. M4-2 adds the rules of the
	# transformations (blood_levy, raiding_parties, forest_stride, hallowed_land, the_forges, wild_spreads,
	# dread_lands) and M4-3 the new traits.
	"research": {
		"title": "Research",
		"text": "In a game with paths (the M4 preview), every faction researches one node of its path at a time. Research points come from land: 5 a turn for your capital and 1 for every other province you own. They go into one pool, and when the pool holds the cost of your research target, the node is done and its effects start. You choose the target with a research order, and it stays until the node is done or you change it. Switching costs nothing and spare points are never lost. Every node shows how many turns it would take before you pick it.",
	},
	"research_points": {
		"title": "Research points",
		"text": "Research points come from the provinces you own, counted in the research phase after the turn's captures and Sworn Vassals: your capital yields 5 while you hold it, and every other province 1. A faction holding 4 provinces makes 8 a turn; one holding 9 makes 13. They are saved in one pool that never loses points: what is left over after a node is done stays, and so do points gained with no target. Capturing or losing a province changes your research by 1 a turn.",
	},
	"research_order": {
		"title": "Research orders",
		"text": "A research order makes one node of your path your research target. It is checked in the orders phase, after sacrifices, and is legal when the node is on your path, not researched yet, not closed by an Oath you swore, and all its prerequisites were researched by the start of the turn. The target stays from turn to turn until the node is done or you change it, so most turns need no research order. Only one counts per turn: choosing another replaces it. Changing the target moves nothing: the pool simply saves toward the new node. Your target is yours alone; the other player never sees it.",
	},
	"research_phase": {
		"title": "The research phase",
		"text": "In a game with paths, research resolves after income and before rulers. For each faction in turn, the pool gains this turn's research; then, if the pool holds the cost of the target, the cost is paid and the node is done. Its effects start at once, so they count from the next turn's orders, moves, battles, recruits and income. At most one node is done per faction per turn. Units already on the map change at once: a node that raises maximum hit points raises current hit points by as much, and one that lowers it lowers them by as much, never below 1. When a node is done the target becomes empty, except after an Oath: then its transformation becomes the target at once.",
	},
	"path": {
		"title": "Paths of ascension",
		"text": "Paths are a preview of the next milestone, behind the Paths (M4 preview) box on the new game screen, which needs rulers. Each faction has one path of 8 nodes: two tier I nodes (10 research each), two tier II nodes (15 each, each needing one tier I node), then a fork. Each side of the fork is an Oath (20), which needs any two of the four ordinary nodes, followed by a transformation (30), which needs its Oath. Swearing one Oath closes the other side for the rest of the game, so a faction completes at most 6 of its 8 nodes, 100 research in all. Completed nodes, Oaths and transformations are public; your research target is not.",
	},
	"path_node": {
		"title": "Path nodes",
		"text": "A node is one step of your path. Ordinary nodes (tier I and tier II) give a unit type a bonus or your provinces more gold, and they are never closed: the ones you skip stay open after the fork. Each bonus is a named part, shown in every tooltip, on regular units only, never commanders or rulers, and it adds to your mandates. Attack bonuses are always +2, a whole damage step, and defense bonuses land on the usual safe values, so terrain, forts and Shield Wall still change only the hit chance.",
	},
	"fork": {
		"title": "The fork",
		"text": "After the ordinary nodes, every path forks in two. Each side is an Oath and then a transformation. Targeting an Oath is not a commitment: until it is done you can change your research freely, and nothing is closed. The moment an Oath is done it is sworn, and the other Oath and its transformation are closed for good. Closed nodes stay visible, with the reason. Rushing two tier I nodes before the Oath transforms about three turns sooner than researching all four ordinary nodes first, and the skipped ones stay open afterwards.",
	},
	"oath": {
		"title": "Oaths",
		"text": "An Oath costs 20 research and needs any two of the four ordinary nodes. It is the lock-in: when it is done you have sworn to that side of the fork, the other side closes for the rest of the game, its economy rule starts at once, and its transformation becomes your research target. The Aurel Crown has the Oath of the Dawn (Tithe of Light) and the Oath of the Forge (Deep Mines); the Thornmane Clans the Oath of the Grove (Bounty of the Wild) and the Oath of Blood (Blood Levy).",
	},
	"lock_in": {
		"title": "Lock-in",
		"text": "Swearing an Oath is the one choice on a path you can't take back. Before you make an Oath your target, the lock-in preview shows what you gain, what you lose access to, and every unit number before and after. Nothing is queued until you swear, and nothing is closed until the Oath is done: until then you can change your research freely.",
	},
	"transformation": {
		"title": "Transformations",
		"text": "A transformation costs 30 research and needs its own Oath. It changes your people: one unit type you already have is renamed and changed in place, so every unit of that type on the map changes at once; one new unit joins your roster; a province rule starts; and your ruler can buy one new mandate by sacrifice while another is forsworn. The Aurel Crown becomes the Celestial Host or Living Iron; the Thornmane Clans become the Thorn Wild or the Blood Pact. Rulers and commanders don't change.",
	},
	"forsworn": {
		"title": "Forsworn mandates",
		"text": "Each transformation forswears one mandate: the Celestial Host forswears Heavy Tithes, Living Iron forswears King's Roads, the Thorn Wild forswears Blood Frenzy and the Blood Pact forswears Feast of Victory. A forsworn mandate can no longer be bought by sacrifice. Mandates you already have are never removed.",
	},
	"path_kingdom": {
		"title": "The Sunstone Path",
		"text": "The path of the Aurel Crown. Tier I: Drillyard (Spearmen +3 maximum hit points) and Market Charters (every plains province you own earns 2 more gold). Tier II: Arbalests (Crossbowmen +2 attack; needs Drillyard) and Remount Stables (Knights cost 4 gold less; needs Market Charters). The fork: the Oath of the Dawn leads to the Celestial Host, a field army that heals on its own land, and the Oath of the Forge leads to Living Iron, armies that are slow to kill, a hills economy and forts that repair them.",
	},
	"path_beasts": {
		"title": "The Old Ways",
		"text": "The path of the Thornmane Clans. Tier I: Boar Hide (Tuskers +3 maximum hit points) and Raiding Parties (gold when your armies capture a province). Tier II: Bone Fangs (Fangthrowers +2 attack; needs Boar Hide) and Forest Stride (two-province moves through your forests; needs Raiding Parties). The fork: the Oath of the Grove leads to the Thorn Wild, which turns your land to forest, and the Oath of Blood leads to the Blood Pact, cheap recruits paid for in blood and a home that is costly to invade.",
	},
	"node_crown_drillyard": {
		"title": "Drillyard",
		"text": "Aurel Crown path, tier I, 10 research, no prerequisite. Spearmen have 3 more maximum hit points (8 to 11). The Spearmen already on the map gain 3 hit points at once, and recruits arrive at the new maximum.",
	},
	"node_crown_charters": {
		"title": "Market Charters",
		"text": "Aurel Crown path, tier I, 10 research, no prerequisite. In the income phase every plains province you own earns 2 more gold. It shows in each province's income and in your gold.",
	},
	"node_crown_arbalests": {
		"title": "Arbalests",
		"text": "Aurel Crown path, tier II, 15 research, needs Drillyard. Crossbowmen have 2 more attack (11 to 13), one whole damage step.",
	},
	"node_crown_stables": {
		"title": "Remount Stables",
		"text": "Aurel Crown path, tier II, 15 research, needs Market Charters. Knights cost 4 gold less (20 to 16). With Living Iron it cancels the Iron Knights' price rise.",
	},
	"node_crown_oath_dawn": {
		"title": "Oath of the Dawn",
		"text": "Aurel Crown path, Oath, 20 research, needs any two ordinary nodes. Swearing it leads to the Celestial Host and closes the Oath of the Forge and Living Iron for the rest of the game. Its economy rule, Tithe of Light, starts at once: your capital earns 1 more gold for every province you own, the capital included.",
	},
	"node_crown_celestial_host": {
		"title": "Celestial Host",
		"text": "Aurel Crown transformation, 30 research, needs the Oath of the Dawn. Spearmen become Sunspears: 2 more maximum hit points (8 to 10) and 2 more morale (6 to 8); Shield Wall stays. Seraphs join the roster: 14 hit points, attack 13, defense 9, morale 12, 24 gold, trait Wings. Hallowed Land: at the end of every turn each of your wounded units and commanders in a province you own heals 3 hit points, up to its maximum. Opens Hymn of Dawn for sacrifice and forswears Heavy Tithes.",
	},
	"node_crown_oath_forge": {
		"title": "Oath of the Forge",
		"text": "Aurel Crown path, Oath, 20 research, needs any two ordinary nodes. Swearing it leads to Living Iron and closes the Oath of the Dawn and the Celestial Host for the rest of the game. Its economy rule, Deep Mines, starts at once: every hills province you own earns 3 more gold, and every forest province you own 1 less.",
	},
	"node_crown_living_iron": {
		"title": "Living Iron",
		"text": "Aurel Crown transformation, 30 research, needs the Oath of the Forge. Knights become Iron Knights: 4 more defense (9 to 13) and a price 4 gold higher (20 to 24); Charge stays. The Iron Colossus joins the roster: 26 hit points, attack 13, defense 9, morale 12, 30 gold, trait Iron Hide. The Forges: at the end of every turn each of your wounded units and commanders in a province with a fort that you own heals to full. Opens Forge Tithe for sacrifice and forswears King's Roads.",
	},
	"node_beasts_boar_hide": {
		"title": "Boar Hide",
		"text": "Thornmane Clans path, tier I, 10 research, no prerequisite. Tuskers have 3 more maximum hit points (14 to 17). The Tuskers already on the map gain 3 hit points at once, and recruits arrive at the new maximum.",
	},
	"node_beasts_raiding": {
		"title": "Raiding Parties",
		"text": "Thornmane Clans path, tier I, 10 research, no prerequisite. When your armies capture a province (not by Sworn Vassals), you take gold equal to twice its base income, once.",
	},
	"node_beasts_bone_fangs": {
		"title": "Bone Fangs",
		"text": "Thornmane Clans path, tier II, 15 research, needs Boar Hide. Fangthrowers have 2 more attack (11 to 13), one whole damage step.",
	},
	"node_beasts_forest_stride": {
		"title": "Forest Stride",
		"text": "Thornmane Clans path, tier II, 15 research, needs Raiding Parties. Your armies can make a road move from a province through a forest you owned at the start of the turn into another forest next to it, two provinces in one turn. Like a King's Roads move, it never fights on a border and never stops halfway.",
	},
	"node_beasts_oath_grove": {
		"title": "Oath of the Grove",
		"text": "Thornmane Clans path, Oath, 20 research, needs any two ordinary nodes. Swearing it leads to the Thorn Wild and closes the Oath of Blood and the Blood Pact for the rest of the game. Its economy rule, Bounty of the Wild, starts at once: every forest province you own earns 2 more gold.",
	},
	"node_beasts_thorn_wild": {
		"title": "Thorn Wild",
		"text": "Thornmane Clans transformation, 30 research, needs the Oath of the Grove. Fangthrowers become Thornthrowers: 3 more defense (5 to 8); Skirmish stays. Briarwardens join the roster: 26 hit points, attack 11, defense 9, morale 10, 24 gold, trait Rooted. The Wild Spreads: at the end of every turn one province you own, next to one of your forests, turns to forest for good. Opens Deep Roots for sacrifice and forswears Blood Frenzy.",
	},
	"node_beasts_oath_blood": {
		"title": "Oath of Blood",
		"text": "Thornmane Clans path, Oath, 20 research, needs any two ordinary nodes. Swearing it leads to the Blood Pact and closes the Oath of the Grove and the Thorn Wild for the rest of the game. Its economy rule, Blood Levy, starts at once: your regular recruits cost a quarter less and arrive missing a quarter of their hit points, never below 1.",
	},
	"node_beasts_blood_pact": {
		"title": "Blood Pact",
		"text": "Thornmane Clans transformation, 30 research, needs the Oath of Blood. Tuskers become Bloodtuskers: 2 more attack (11 to 13) and 2 fewer maximum hit points (14 to 12); Berserk stays. Bloodsworn join the roster: 16 hit points, attack 13, defense 5, morale 9, 18 gold, trait Lifedrinker. Dread Lands: in a province battle in a province you owned at the start of the turn, every enemy side has 1 less morale. Opens Red Harvest for sacrifice and forswears Feast of Victory.",
	},
	"tithe_of_light": {
		"title": "Tithe of Light",
		"text": "The economy rule of the Oath of the Dawn. In the income phase your capital earns 1 more gold for every province you own, the capital included: 7 more with 7 provinces. It counts the provinces you own after the turn's captures, and it shows in your capital's income and in your gold.",
	},
	"deep_mines": {
		"title": "Deep Mines",
		"text": "The economy rule of the Oath of the Forge. In the income phase every hills province you own earns 3 more gold, and every forest province you own 1 less; a province never earns less than nothing. It shows in each province's income and in your gold.",
	},
	"bounty_of_the_wild": {
		"title": "Bounty of the Wild",
		"text": "The economy rule of the Oath of the Grove. In the income phase every forest province you own earns 2 more gold. It shows in each province's income and in your gold.",
	},
}


static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})


static func text(id: String) -> String:
	return entry(id).get("text", "")
