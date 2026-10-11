extends "res://tests/test_case.gd"
## UX-6 (design/UX_WAR_TABLE.md §5.2, "Pins and dismissals live outside the game"): ChronicleStore, the Chronicle's UI sidecar.
##   - pins and dismissals are kept in a sidecar file beside the saves, keyed by the game's identity, the seat and the announcement id;
##   - never in GameSession, the save's game state, records or digests: pinning changes none of them, and SaveStore never lists the sidecar;
##   - hotseat: seat 2 is never handed seat 1's pins or dismissals, in memory or through the file;
##   - a pinned card keeps the payload it was shown with, byte for byte, through a save and a load;
##   - a save loaded without its sidecar simply has no pins; a damaged or foreign sidecar is an empty store, never an error;
##   - a new game with the same identity starts clean.

const CROWN := "kingdom"
const CLANS := "beasts"

var _dir := ""


func _root() -> String:
	if _dir.is_empty():
		_dir = "user://chronicle_store_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	return _dir


func _cleanup() -> void:
	if _dir.is_empty() or not DirAccess.dir_exists_absolute(_dir):
		return
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _card(id: String, text: String, turn: int = 3) -> Dictionary:
	return {"id": id, "turn": turn, "kind": "battles", "image": "battle_won", "rank": 10, "headline": "Won at Wildmoor", "detail": text,
		"province": "wildmoor", "place": "Wildmoor", "codex": "defended", "battle": {}, "source_rows": [text, "A second row."], "important": true,
		"routine": false, "own": true, "type": "battle", "facts": {"battle": "won"}}


func test_the_identity_is_the_seed_and_the_seats() -> void:
	assert_eq(ChronicleStore.identity("4242", [CROWN, CLANS]), "4242_kingdom-beasts")
	assert_ne(ChronicleStore.identity("4242", [CROWN, CLANS]), ChronicleStore.identity("4242", [CLANS, CROWN]), "the seat order is part of it")
	assert_ne(ChronicleStore.identity("1", [CROWN, CLANS]), ChronicleStore.identity("2", [CROWN, CLANS]))
	assert_false(ChronicleStore.identity("../../x", ["a/b"]).contains("/"), "file safe")


func test_a_pin_and_a_dismissal_survive_a_save_and_a_load() -> void:
	var store := ChronicleStore.new(_root())
	store.open_game("g1", true)
	store.pin(CROWN, _card("t3.e2", "You beat the Clans."))
	store.dismiss(CROWN, "t3.e5")
	assert_eq(store.save(), "")
	assert_true(FileAccess.file_exists(store.path()), "the sidecar is on disk: %s" % store.path())
	assert_eq(store.path().get_file(), "chronicle_g1.json")
	var again := ChronicleStore.new(_root())
	again.open_game("g1", false)
	assert_true(again.is_pinned(CROWN, "t3.e2"))
	assert_true(again.is_dismissed(CROWN, "t3.e5"))
	assert_false(again.is_pinned(CROWN, "t3.e5"))
	assert_eq(again.pinned(CROWN).size(), 1)
	assert_eq(again.dismissed(CROWN), ["t3.e5"])
	again.restore(CROWN, "t3.e5")
	again.unpin(CROWN, "t3.e2")
	assert_eq(again.save(), "")
	assert_false(FileAccess.file_exists(again.path()), "an empty store leaves no file")
	_cleanup()


func test_a_pinned_card_comes_back_exactly_as_it_was_shown() -> void:
	var store := ChronicleStore.new(_root())
	store.open_game("g2", true)
	var card := _card("t3.e2", "You beat the Clans: none of yours fell, 2 of theirs.")
	card["battle"] = {"type": "battle", "provinces": ["wildmoor"], "numbers": {"winner": CROWN, "log": {"events": [1, 2]}, "report": {"sides": [{"faction": CROWN, "fighters_start": 4}]}}}
	store.pin(CROWN, ChronicleModel.pin_payload(card))
	assert_eq(store.save(), "")
	var again := ChronicleStore.new(_root())
	again.open_game("g2", false)
	var back := again.payload_of(CROWN, "t3.e2")
	assert_eq(back.headline, card.headline)
	assert_eq(back.detail, card.detail, "its text is exactly the text it was shown with")
	assert_eq(back.source_rows, card.source_rows)
	assert_eq(back.province, "wildmoor", "and its focus province")
	assert_true(back.turn is int and back.turn == 3)
	assert_false(back.battle.numbers.has("log"), "the log is not kept")
	assert_eq(back.battle.numbers.report.sides[0].fighters_start, 4, "the report is")
	_cleanup()


func test_hotseat_seat_2_is_never_handed_seat_1s_entries() -> void:
	var store := ChronicleStore.new(_root())
	store.open_game("g3", true)
	store.pin(CROWN, _card("t3.e2", "The Crown's secret news."))
	store.dismiss(CROWN, "t3.e9")
	assert_eq(store.pinned(CLANS), [], "seat 2 has no pins")
	assert_eq(store.dismissed(CLANS), [])
	assert_false(store.is_pinned(CLANS, "t3.e2"), "not even under the same id")
	assert_false(store.is_dismissed(CLANS, "t3.e9"))
	assert_eq(store.payload_of(CLANS, "t3.e2"), {})
	store.pin(CLANS, _card("t3.e2", "The Clans' own news."))
	assert_eq(String(store.payload_of(CROWN, "t3.e2").detail), "The Crown's secret news.", "each seat keeps its own under one id")
	assert_eq(String(store.payload_of(CLANS, "t3.e2").detail), "The Clans' own news.")
	store.forget_seat(CROWN)
	assert_eq(store.pinned(CROWN), [])
	assert_eq(store.pinned(CLANS).size(), 1, "forgetting one seat leaves the other")
	# Through the file too.
	store.pin(CROWN, _card("t4.e1", "More of the Crown's."))
	assert_eq(store.save(), "")
	var again := ChronicleStore.new(_root())
	again.open_game("g3", false)
	assert_eq(again.pinned(CLANS).map(func(p): return String(p.detail)), ["The Clans' own news."])
	_cleanup()


func test_the_sidecar_is_not_a_save_and_a_save_does_not_know_it() -> void:
	var saves := SaveStore.new(_root())
	var session := GameSession.new(GameState.new(5), [CROWN, CLANS], 5, AutoBattleResolver.new())
	var before := JSON.stringify(SaveGame.make(session, {}, SaveGame.MANUAL, "Test", 0))
	var record_before := var_to_str(session.record())
	var store := ChronicleStore.new(_root())
	store.open_game("g4", true)
	store.pin(CROWN, _card("t3.e2", "Pinned."))
	store.dismiss(CROWN, "t3.e3")
	assert_eq(store.save(), "")
	assert_eq(JSON.stringify(SaveGame.make(session, {}, SaveGame.MANUAL, "Test", 0)), before, "the save of the game is byte for byte the same")
	assert_eq(var_to_str(session.record()), record_before, "and so is its record")
	assert_false(JSON.stringify(SaveGame.make(session, {}, SaveGame.MANUAL, "Test", 0)).contains("Pinned"), "nothing of a pin is in a save")
	assert_false(saves.has_saves(), "SaveStore lists no sidecar as a save")
	assert_eq(saves.list(), [])
	assert_true(FileAccess.file_exists(store.path()))
	_cleanup()


func test_a_save_loaded_without_its_sidecar_has_no_pins() -> void:
	var store := ChronicleStore.new(_root())
	store.open_game("never_written", false)
	assert_eq(store.pinned(CROWN), [])
	assert_eq(store.dismissed(CROWN), [])
	assert_eq(store.save(), "", "and saving nothing is fine")
	assert_false(FileAccess.file_exists(store.path()))
	_cleanup()


func test_a_damaged_or_foreign_sidecar_is_an_empty_store() -> void:
	DirAccess.make_dir_recursive_absolute(_root())
	var store := ChronicleStore.new(_root())
	for body in ["", "not json at all {{", "[1, 2, 3]", "{\"format\": \"something-else\", \"game\": \"g5\", \"seats\": {}}",
			"{\"format\": \"ascendant-chronicle\", \"game\": \"another game\", \"seats\": {\"kingdom\": {\"pins\": {\"t1.e1\": {\"id\": \"t1.e1\"}}}}}",
			"{\"format\": \"ascendant-chronicle\", \"game\": \"g5\", \"seats\": \"nope\"}",
			"{\"format\": \"ascendant-chronicle\", \"game\": \"g5\", \"seats\": {\"kingdom\": {\"pins\": 7, \"dismissed\": \"x\"}}}"]:
		var f := FileAccess.open(_root().path_join("chronicle_g5.json"), FileAccess.WRITE)
		f.store_string(body)
		f.close()
		store.open_game("g5", false)
		assert_eq(store.pinned(CROWN), [], "an unreadable sidecar gives no pins: %s" % body.left(40))
		assert_eq(store.dismissed(CROWN), [])
	_cleanup()


func test_a_new_game_with_the_same_identity_starts_clean() -> void:
	var store := ChronicleStore.new(_root())
	store.open_game("g6", true)
	store.pin(CROWN, _card("t2.e1", "From the old game."))
	assert_eq(store.save(), "")
	store.open_game("g6", true)  # a new game with the same seed and seats
	assert_eq(store.pinned(CROWN), [], "the old game's pins are gone")
	assert_false(FileAccess.file_exists(store.path()), "and so is its file")
	_cleanup()


func test_pins_come_back_oldest_turn_first() -> void:
	var store := ChronicleStore.new(_root())
	store.open_game("g7", true)
	store.pin(CROWN, _card("t5.e1", "five", 5))
	store.pin(CROWN, _card("t2.e4", "two", 2))
	store.pin(CROWN, _card("t2.e1", "two b", 2))
	assert_eq(store.pinned(CROWN).map(func(p): return String(p.id)), ["t2.e1", "t2.e4", "t5.e1"])
	_cleanup()
