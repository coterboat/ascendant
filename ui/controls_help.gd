class_name ControlsHelp
extends RefCounted
## UX-1 (design/UX_WAR_TABLE.md §1.3): the ? button of the system row lists every key and mouse binding, and today's hint
## text in full (the top bar's hint and its tooltip, and the board's one-line legend, are gone from the screen). This is the
## text, pure: sections() gives [{"title", "rows": [{"keys", "text"}]}], and text() flattens it for a test or a tooltip.
## The game screen draws it in a modal. Lens keys are listed from the LensHost, so UX-7's lenses appear by themselves.

## The first how-to, in the words the top bar's hint tooltip had: select an army, click a neighbour, recruit at the capital.
const HOW_TO_ORDER := "Select one of your armies, then click a neighboring province to move it there (or press March on its card and then click one); hover a province first to see the forecast and battle odds. Select your capital to recruit: press Recruit on its card. Each army's order is on its card, and every order is a token in the tray along the bottom, numbered as it is on the board: hover it for its forecast, click it to see its card, and right-click it, or press its cross, to cancel it. Hover any number to see where it comes from; right-click it, or press F1, to open its codex entry. End turn when you are done."
const QUICK := "Move: select an army, then a neighbor. Recruit: select your capital."


## The sections of the help. `lens_keys` is [[key name, lens title]] from the LensHost.
static func sections(lens_keys: Array = []) -> Array:
	var out: Array = []
	out.append({"title": "Giving orders", "rows": [
		{"keys": "Click an army, then a province", "text": "Select one of your armies, then click a neighboring province to move it there. Hover the province first to see the forecast and the battle odds. The army's card has March too: it folds into a slim strip while you choose, and Esc cancels."},
		{"keys": "Click your capital, then Recruit", "text": "Select your capital to recruit: press Recruit on its card to see what you can buy. With forts, select any fort you own."},
		{"keys": "End turn (the seal)", "text": "Lock your orders in. Every player's orders then resolve together. Your orders are the tokens in the tray, numbered as they are on the board; each has a cross to cancel it (a right-click does too), and an army's own order is on its card."},
	]})
	out.append({"title": "The board", "rows": [
		{"keys": "Drag, middle-drag, W A S D, arrow keys", "text": "Pan the map."},
		{"keys": "Mouse wheel, + and -", "text": "Zoom in and out, toward the cursor."},
		{"keys": "Double-click a province", "text": "Glide the camera to it. A double-click on a fortress shows its muster yard close up."},
		{"keys": "C or Home", "text": "Back to your capital."},
		{"keys": "F", "text": "Frame the whole map."},
		{"keys": "L", "text": "Switch the board's look between A and B."},
		{"keys": "Space", "text": "Skip the turn playing out on the board (a click on the land does too)."},
	]})
	out.append({"title": "Numbers, plates and the codex", "rows": [
		{"keys": "Hover a number", "text": "See where it comes from: every number has a breakdown."},
		{"keys": "Right-click, or F1 while hovering", "text": "Open the codex at the rule behind a number, a plate, an army or a province."},
		{"keys": "Codex button", "text": "Every rule of the game in plain language, searchable."},
	]})
	var close_row := "Close the topmost thing, one at a time: a panel or dialog, then choosing a march destination, then the Chronicle, then the selection card, then a lens, then the fortress close-up. With nothing left to close, Esc opens the menu."
	out.append({"title": "Closing things", "rows": [
		{"keys": "Esc", "text": close_row},
		{"keys": "Right-click on empty board", "text": "The same, without the menu: it closes the topmost thing and does nothing when nothing is open."},
	]})
	if not lens_keys.is_empty():
		var rows: Array = []
		for lk in lens_keys:
			rows.append({"keys": String(lk[0]), "text": "%s lens. Press it again to bring the art back." % String(lk[1])})
		rows.append({"keys": "` (or Esc)", "text": "The key left of 1: turn the lens off. One lens is on at a time, and none when a game starts. The Lenses button in the system row lists them too, and the legend card at the bottom left says what the one on is showing."})
		out.append({"title": "Lenses", "rows": rows})
	out.append({"title": "The system row", "rows": [
		{"keys": "Research, Magic, Ruler", "text": "Open the research panel (and its Magic tab) and the ruler panel."},
		{"keys": "Chronicle", "text": "The turn's announcements, each with its own image, in a column you open and close: sort them, hide the kinds you don't need, pin the ones to keep, dismiss the rest, and press Full report for every line. The round medallions down the left edge are the same news: hover one to read it, click it to open its card, right-click it to dismiss it. Your plan for the turn joins it in a later update."},
		{"keys": "Lenses", "text": "The optional map views (1 to 6): Owner, Income, Threat, Magic, Making and Sight, one at a time, each with its own colours and a legend. Off by default."},
		{"keys": "Turn report", "text": "Read again every line of what happened last turn."},
		{"keys": "Codex, ?", "text": "The rules, and this list."},
	]})
	return out


## Every row of every section as one text (a test, a tooltip).
static func text(lens_keys: Array = []) -> String:
	var lines := PackedStringArray()
	for s in sections(lens_keys):
		lines.append(String(s.title))
		for r in s.rows:
			lines.append("%s: %s" % [String(r.keys), String(r.text)])
	return "\n".join(lines)
