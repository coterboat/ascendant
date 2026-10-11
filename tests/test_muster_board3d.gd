extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §3, §8): the 3D board's order and selection lookups read the board the plan leaves, so an army a
## queued split forms has its march arrow, its departing entry, its road targets and its hover preview, and with it selected a click
## on another army's formation orders the march. The formations themselves stay on the real board until the turn resolves.

const Kit := preload("res://tests/muster_test_kit.gd")
const BOARD_SIZE := Vector2(1200, 836)
const CROWN := "kingdom"


func _board_for(state: GameState) -> Board3D:
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	map.set_state(state, CROWN)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	b.fit_whole(true)
	b.wv.rig = b.goal.duplicate()
	for k in 30:
		b._camera(1.0 / 30.0)
	return b


func _free_board(b: Board3D) -> void:
	var map: Node = b.map
	if map != null:
		map.free()
	elif is_instance_valid(b):
		b.free()


## The Crown's first army split in two, the new one (the Crown's 3rd; the 2nd is the ruler) selected.
func _split_board() -> Dictionary:
	var s := Kit.game("rulers")
	var b := _board_for(s)
	var map: MapScreen = b.map
	assert_eq(map.queue_muster(MusterOrder.transfer("kingdom-1", "", [0, 1])), "", "the split")
	map.select_army("kingdom-3")
	return {"state": s, "board": b, "map": map}


func test_a_march_ordered_for_a_new_army_draws_an_arrow_and_departs() -> void:
	var f := _split_board()
	var b: Board3D = f.board
	var map: MapScreen = f.map
	assert_eq(map.queue_move("kingdom-3", "westwatch"), "", "the new army is given its march")
	assert_eq(f.state.find_army("kingdom-3"), null, "the real board has no such army: its formation stands only once the turn resolves")
	var arrows: Array = b.overlay.arrow_plan()
	assert_eq(arrows.size(), 1, "one arrow: %s" % [arrows])
	assert_eq([arrows[0].army, arrows[0].to, arrows[0].preview], ["kingdom-3", "westwatch", false])
	assert_true(b.overlay.move_points("kingdom-3", "westwatch", "").size() >= 2, "and it has a road to follow on the ground")
	var plan := b.plan_of_orders()
	assert_true(plan.has("departing") and plan.departing.has("kingdom-3"), "a departing entry for it: %s" % [plan])
	assert_eq(plan.departing["kingdom-3"], {"to": "westwatch", "via": ""})
	_free_board(b)


func test_the_new_armys_road_targets_and_hover_preview_are_the_boards() -> void:
	var f := _split_board()
	var b: Board3D = f.board
	var map: MapScreen = f.map
	b._sync_marks()
	var i: int = b.wv.terrain.index_of("westwatch")
	assert_true(i >= 0)
	assert_eq(b.wv.mark_img.get_pixel(i, 0).g, 1.0, "Westwatch glows as a place the new army can march to")
	assert_eq(b.wv.mark_img.get_pixel(b.wv.terrain.index_of("fangridge"), 0).g, 0.0, "and a far province does not")
	# The pointer over Westwatch: the dashed preview of the move a click would order.
	b.hover_id = "westwatch"
	map.preview_move("westwatch")
	var preview: Array = b.overlay.arrow_plan().filter(func(a): return a.preview)
	assert_eq(preview.size(), 1, "the hover preview is there for the new army: %s" % [map.hover_panel.visible])
	assert_eq([preview[0].army, preview[0].to], ["kingdom-3", "westwatch"])
	_free_board(b)


func test_with_a_new_army_selected_a_click_on_another_formation_orders_the_march() -> void:
	var s := Kit.game("rulers")
	Kit.army(s, CROWN, "westwatch", ["spearmen"])  # the Crown's 3rd stands next door; the split is its 4th
	var b := _board_for(s)
	var map: MapScreen = b.map
	assert_eq(map.queue_muster(MusterOrder.transfer("kingdom-1", "", [0, 1])), "")
	map.select_army("kingdom-4")
	assert_eq(map.selected_army_id, "kingdom-4", "the new army is selected")
	b.click_army("kingdom-3")  # the formation at Westwatch
	var moves := map.orders.orders().filter(func(o): return o is MoveOrder)
	assert_eq(moves.size(), 1, "the click ordered a march: %s" % map.status_text)
	assert_eq([moves[0].army_id, moves[0].to], ["kingdom-4", "westwatch"], "of the new army, to the province of the army clicked")
	_free_board(b)


func test_a_tooltip_for_an_army_only_the_plan_forms_is_not_empty() -> void:
	var f := _split_board()
	var b: Board3D = f.board
	assert_false(b.overlay.army_tooltip("kingdom-3").is_empty(), "the board can describe it")
	assert_eq(b.overlay.army_tooltip("kingdom-99"), "", "and an army nobody has is still nothing")
	_free_board(b)
