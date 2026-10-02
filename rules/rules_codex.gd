class_name RulesCodex
## Plain-language rules text for the in-game codex, tooltips and the turn report.
## Every turn event carries a "codex" key naming one of these entries.
## This text is the player-facing statement of the rules in TurnResolver and StubBattleResolver;
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
