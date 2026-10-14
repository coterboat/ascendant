class_name PlanHud
extends RefCounted
## UX-5 (design/UX_WAR_TABLE.md §5.3): the Chronicle's Plan side on the game screen, with the smallest hooks there, as ChronicleHud does
## (one line builds it in _build_hud, the seal calls seal(), and _update_hud calls refresh()). It puts its PlanPage in the Chronicle's
## second tab (ChronicleHud.set_plan_page) and keeps it showing the orders of the person giving them (PlanModel.build on the game map's
## OrdersController, which is that seat's), rebuilt whenever an order changes.
##
## REVIEW BEFORE SEALING (ChronicleSettings.review): when it is on, the End turn seal opens the Chronicle at Plan instead of ending the
## turn, and the Plan's own seal ends it. "first_game" (the default) is on during the player's first game: the game the first-game guide
## is for, decided when this game screen opens (the guide's hint not yet seen), so it stays on for that whole game.
##
## Hotseat: the page shows the current seat's orders only, and is cleared at the handoff (nobody is looking). Watch mode and the end of
## the game: no Plan (the Chronicle is off there, and the seal is Next turn or Results).
##
## API: seal() -> String (what the End turn seal does), open_plan(), is_showing(), review_on(), set_review(mode), refresh(), page

var game: GameScreen
var page: PlanPage
var first_game := false
var _seat := ""
var _sig := ""  # what the page shows now, so an unchanged plan is not drawn again


func _init(p_game: GameScreen) -> void:
	game = p_game
	first_game = not GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME)
	page = PlanPage.new()
	page.cancel_requested.connect(func(i: int): game.map.cancel_order(i))
	page.focus_requested.connect(func(i: int): game.map.show_order(i))
	page.check_focus_requested.connect(func(pid: String, _id: String):
		if not pid.is_empty():
			game.map.focus_province(pid))
	page.seal_requested.connect(func(): game.end_turn())
	page.review_changed.connect(set_review)
	page.codex_requested.connect(game.open_codex)
	game.chronicle_hud.set_plan_page(page)  # GameScreen._update_hud (on every order change too) keeps it current
	game.chronicle_hud.column.plan_tab.pressed.connect(_plan_shown)  # UX-9: the first-game guide ticks its Plan step


func _settings() -> ChronicleSettings:
	return game.chronicle_hud.settings


## Whether the seal opens the Plan first now.
func review_on() -> bool:
	return PlanModel.review_on(_settings().review, first_game)


func set_review(mode: String) -> void:
	if _settings().set_review(mode):
		_settings().save()
	refresh()


## What the End turn seal does: with review before sealing on, and someone giving orders, it opens the Plan, or keeps it open, and only
## the Plan's own seal ends the turn (a quick second press on the seal never seals the orders unread); otherwise it ends the turn as it
## always has. Returns "" or why the turn could not end.
func seal() -> String:
	if review_on() and _looking():
		open_plan()
		return ""
	return game.end_turn()


func open_plan() -> void:
	game.chronicle_hud.open()
	if game.chronicle_hud.is_open():
		game.chronicle_hud.column.show_tab("plan")
		_plan_shown()
	refresh()


## UX-9: the Plan was shown to the person giving orders: the first-game guide ticks its step.
func _plan_shown() -> void:
	if game.first_game_guide != null and _looking():
		game.first_game_guide.note_plan_seen(game.viewer())


func is_showing() -> bool:
	return game.chronicle_hud.is_open() and game.chronicle_hud.column.current_tab() == "plan"


## The person giving orders now ("" while nobody in particular is: watch mode, the handoff cover, the end of the game).
func _looking() -> bool:
	var session := game.session
	return session != null and session.phase() == GameSession.Phase.ORDERS and not session.is_over() and not game.is_watching() \
		and not game.viewer().is_empty() and session.players().has(game.viewer())


## Shows the current seat's plan (or nothing, while nobody is looking). Called whenever an order changes and from GameScreen._update_hud.
func refresh() -> void:
	var looking := _looking()
	var eyes := game.viewer() if looking else ""
	if eyes != _seat:
		_seat = eyes
		if not looking and is_showing():
			game.chronicle_hud.column.show_tab("read")
	var plan := {"sentences": [], "checks": [], "gold": "", "gold_tip": ""}
	if looking and game.map.orders != null:
		var turn := int(game.chronicle_hud.turn) if int(game.chronicle_hud.turn) > 0 else game.session.turn_number() - 1
		plan = PlanModel.build(game.map.orders, game.session.state_for(eyes), eyes, turn)
	var sig := JSON.stringify([plan.sentences.map(func(x): return [x.index, x.text, x.tip]), plan.checks.map(func(x): return [x.id, x.detail]),
		plan.gold, _settings().review, looking])
	if sig == _sig:
		return
	_sig = sig
	page.show_plan(plan, _settings().review, looking, seal_tip(plan.sentences.size()))


func seal_tip(n: int) -> String:
	return TooltipText.plain("Seal the orders · End turn", "End your turn with %s queued. They resolve together with everyone else's once every player has ended the turn." % TooltipText.count(n, "order"))
