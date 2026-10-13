extends "res://tests/test_case.gd"
## UX-6 (design/UX_WAR_TABLE.md §5.2, §9): the Chronicle under fog of war. The Chronicle reads the viewer's report events only
## (GameSession.turn_report_for, filtered for fog exactly as the Turn report reads it) and the viewer's own view (state_for). Pinned here:
##   - the announcements are a function of the viewer's report and view: with everything hidden from the viewer perturbed
##     (FogTestKit.perturb_hidden), over the kit's 20 seeded fog games, every announcement of every turn for both seats is unchanged;
##   - nothing a seat has no right to is in its announcements: a rival's private business (its recruits, its gold, its research) never is;
##     ARM-1's muster events are the owner's only;
##   - the pinned-card fog perturbation: a pinned card keeps the payload it was shown with, so it cannot change when a rival's hidden
##     facts change, nor reveal what was learned since: pinned at one turn, read back after the hidden state is perturbed and the game goes
##     on, it is the same bytes, and the column shows exactly those bytes;
##   - the Chronicle's code reads no truth accessor (the static scan in test_fog_ui covers ui/chronicle/ with the rest of ui/).

const Kit := preload("res://tests/fog_test_kit.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
## Event types that are a rival's private business: whatever the report holds of them, they are not announced to the other seat.
const PRIVATE := ["income", "recruited", "research_gained", "research_done", "mending", "ruler_healed", "path_healed", "sacrificed", "order_rejected",
	"army_split", "units_transferred", "armies_merged", "commanders_swapped", "army_disbanded"]


func _announce(t: Dictionary, v: String, view: GameState) -> Array:
	var report: Dictionary = {"turn": t.turn, "events": t.report[v], "fog": true}
	return ChronicleModel.build(report, view, v, {"before": t.view_before[v], "needs": ChronicleModel.needs(view, v, int(t.turn))})


func test_announcements_do_not_change_when_everything_hidden_from_the_viewer_does() -> void:
	var compared := 0
	var cards := 0
	var changed := 0
	for g in Kit.games():
		for i in [0, g.turns.size() / 2, g.turns.size() - 1]:
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var base := _announce(t, v, t.view_after[v])
				var p := Kit.perturb_hidden(t.after, v, hash([g.seed, t.turn, v, "chronicle"]))
				assert_eq(p.errors, [], "the perturbed state is a valid game")
				if p.state == null:
					continue
				var view := FogRules.view_state(p.state, v, t.memory_after[v], t.intel_after[v])
				var perturbed := _announce(t, v, view)
				assert_eq(JSON.stringify(perturbed), JSON.stringify(base), "%s turn %d, %s: the announcements are the same" % [g.name, t.turn, v])
				assert_eq(JSON.stringify(ChronicleModel.summary(perturbed, {"events": t.report[v]}, view, v)),
					JSON.stringify(ChronicleModel.summary(base, {"events": t.report[v]}, t.view_after[v], v)), "and so is the summary line")
				compared += 1
				cards += base.size()
				for k in p.changed:
					changed += int(p.changed[k])
	assert_true(compared >= 100, "turns compared: %d" % compared)
	assert_true(cards >= 200, "announcements compared: %d" % cards)
	assert_true(changed > 0, "the perturbation really changed hidden things (%d)" % changed)
	_notes.append("%d turn-views, %d announcements, %d hidden facts perturbed" % [compared, cards, changed])


func test_a_seat_is_never_told_a_rivals_private_business() -> void:
	var told := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				for it in _announce(t, v, t.view_after[v]):
					if String(it.type) == "need":
						continue
					told += 1
					if PRIVATE.has(String(it.type)):
						assert_true(bool(it.own), "%s %s: %s is the seat's own" % [g.name, v, it.type])
	assert_true(told >= 300, "announcements checked: %d" % told)
	# And the reverse, on the real reports: a private event of the rival in the viewer's report is dropped.
	var dropped := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var rival := Kit.rival_of(v)
				var leaked: Array = t.report[v].filter(func(ev): return PRIVATE.has(String(ev.get("type", ""))) and Array(ev.get("factions", [])).has(rival) \
					and String(Array(ev.get("factions", [""]))[0]) == rival)
				dropped += leaked.size()
				assert_eq(leaked, [], "%s turn %d: the fog filter already keeps the rival's private events out of %s's report" % [g.name, t.turn, v])
	assert_eq(dropped, 0)


func test_a_rivals_private_event_in_an_unfiltered_report_is_still_not_announced() -> void:
	# A game without fog hands every event to every viewer: the Chronicle applies the same audience table, so it reads the same.
	var checked := 0
	for g in Kit.games().slice(0, 4):
		for t in g.turns:
			for v in Kit.SEATS:
				var truth_report := {"turn": t.turn, "events": t.events, "fog": false}
				var items := ChronicleModel.build(truth_report, t.after, v)
				for it in items:
					if String(it.type) == "need":
						continue
					var rival_private: bool = PRIVATE.has(String(it.type)) and not bool(it.own)
					assert_false(rival_private, "%s turn %d for %s: %s is not the rival's to tell" % [g.name, t.turn, v, it.headline])
					checked += 1
	assert_true(checked > 50)


# --- the pinned card ------------------------------------------------------------------------------------------

func _hotseat_free_game() -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.save_store = SaveStore.new("user://chronicle_fog_test_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(game.save_store.root)
	if _real_settings_path.is_empty():
		_real_settings_path = GameSettings.default_path
	GameSettings.default_path = game.save_store.root.path_join("settings.cfg")  # never the run's shared settings file (hints, the Chronicle's own)
	game._bind()
	game.chronicle_hud.settings.auto_open = "never"
	game.start_game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}, "fog": true, "rulers": true, "paths": true})
	return game


static var _real_settings_path := ""


func _clean(game: GameScreen) -> void:
	var dir := game.save_store.root
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	if not _real_settings_path.is_empty():
		GameSettings.default_path = _real_settings_path


func _play(game: GameScreen, brain: AIPlayer, rng: SeededRNG, turns: int) -> void:
	for k in turns:
		if game.session.is_over():
			return
		for o in brain.plan_orders(game.session.state_for(CROWN), CROWN, rng, "normal"):
			game.session.queue_order(o)
		assert_eq(game.end_turn(), "")


func _text_of(card: NoticeCard) -> Array:
	return [String(card.item.headline), String(card.item.detail), card.item.source_rows.duplicate(), String(card.item.province), String(card.item.place)]


func test_a_pinned_card_cannot_change_when_a_rivals_hidden_facts_do() -> void:
	var game := _hotseat_free_game()
	var hud := game.chronicle_hud
	var brain := AIPlayer.new()
	brain.configure(4242, 0)
	var rng := SeededRNG.new(4242 * 31)
	_play(game, brain, rng, 4)
	assert_true(int(game.session.turn_report_for(CROWN).turn) >= 4)
	hud.open()
	assert_true(hud.column.cards.size() > 0, "the fog turn has news")
	# Pin every card of this turn; keep exactly what each was shown with.
	var shown := {}
	for card in hud.column.cards.duplicate():
		shown[String(card.item.id)] = _text_of(card)
		hud.pin(String(card.item.id))
	assert_eq(hud.store.pinned(CROWN).size(), shown.size(), "every card pinned")
	var payload_json := JSON.stringify(hud.store.pinned(CROWN))
	var announcements_json := JSON.stringify(hud.announcements)
	var turn_pinned := hud.turn
	# Perturb everything hidden from the Crown in the truth, and show the screens again: the announcements are the same, the pins too.
	var truth: GameState = game.session._state
	var changed := 0
	for k in 3:
		var p := Kit.perturb_hidden(truth, CROWN, 7700 + k)
		assert_eq(p.errors, [], "a valid perturbed game")
		if p.state == null:
			continue
		game.session._state = p.state
		game.session._fog_cache.erase("state|" + CROWN)
		hud._build()
		assert_eq(JSON.stringify(hud.announcements), announcements_json, "perturbation %d: the turn's announcements are unchanged" % k)
		assert_eq(JSON.stringify(hud.store.pinned(CROWN)), payload_json, "perturbation %d: and so are the pins" % k)
		for card in hud.column.cards:
			if shown.has(String(card.item.id)):
				assert_eq(_text_of(card), shown[String(card.item.id)], "perturbation %d: a pinned card reads as it did" % k)
		changed += 1
		game.session._state = truth
		game.session._fog_cache.erase("state|" + CROWN)
	assert_true(changed > 0)
	hud._build()
	# The game goes on, from the perturbed truth: later turns bring a different world. The pinned cards of the earlier turn are the same bytes,
	# are not re-rendered against it, and show exactly what they showed.
	var perturbed := Kit.perturb_hidden(truth, CROWN, 7800)
	if perturbed.state != null:
		game.session._state = perturbed.state
		game.session._fog_cache.clear()
	hud.close()
	_play(game, brain, rng, 2)
	assert_true(hud.turn > turn_pinned, "two turns later (%d)" % hud.turn)
	hud.open()
	assert_eq(JSON.stringify(hud.store.pinned(CROWN)), payload_json, "the pins on disk and in memory are the same bytes")
	var carried := hud.column.cards.filter(func(c): return c.item.get("carried", false))
	assert_eq(carried.size(), shown.size(), "every pinned card is carried to the later turn")
	for card in carried:
		assert_eq(_text_of(card), shown[String(card.item.id)], "%s: exactly as it was shown" % card.item.headline)
	# And a sidecar read cold gives the same payloads.
	var cold := ChronicleStore.new(game.save_store.root)
	cold.open_game(hud.store.game, false)
	assert_eq(JSON.stringify(cold.pinned(CROWN)), payload_json, "read back from the sidecar file")
	_clean(game)
	game.free()


func test_what_a_card_says_is_in_the_viewers_own_report() -> void:
	# Every word of a fog card comes from the viewer's report rows or the templates over its fields: its source rows ARE report rows.
	var checked := 0
	for g in Kit.games().slice(0, 8):
		for t in g.turns:
			for v in Kit.SEATS:
				var rows := TurnReportText.rows(t.report[v], t.view_after[v], v).map(func(r): return String(r.text))
				for it in _announce(t, v, t.view_after[v]):
					if String(it.type) == "need":
						continue
					for row in it.source_rows:
						if String(row).begins_with("What you didn't see"):
							continue
						assert_true(rows.has(String(row)), "%s turn %d for %s: a source row is a row of the viewer's report" % [g.name, t.turn, v])
						checked += 1
	assert_true(checked > 100, "source rows checked: %d" % checked)
