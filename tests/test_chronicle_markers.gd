extends "res://tests/test_case.gd"
## #278 (QA-1, #250): the Chronicle's numbered markers drew over the 3D board's playback bar ("Turn 7 plays out: the armies march.").
## The bar, its caption and the close-up chip hang in the Table but draw with the board, under the markers' layer, so a marker on a
## province under them covered their words. They are never lifted over: above them is the Table's top row, which the markers' layer
## draws under too. So the markers of a province under them hide while they show, as if drawn under them, and a marker that would only
## touch them goes below them (ChronicleMarkers.row_at).
## In the game the pieces' rects come from the board (top_rects), which the runner can't reach before the scene tree is up. Here the
## Table's own layout places a bar and its caption at 1600x900 with the Chronicle open, and a stand-in layer gives the markers their
## province's point. The PR's shots show the board.
## Pinned:
##   * a row whose middle is under the bar or its caption hides;
##   * a row that only touches the bar stands just below it;
##   * a row that a plate would lift into the bar goes down past the plate instead;
##   * with nothing at the top, a row still lifts just over a plate (#238), and a row that meets nothing stays put;
##   * the layer hides its discs under the bar and puts them back on their province when the bar goes.

const VIEW := Vector2(1600, 900)
## A playback bar's size ("Turn 7 plays out: the armies march." over its phases line) and its caption's: the layout's inputs.
const BAR := Vector2(420, 60)
const CAPTION := Vector2(340, 44)
## The disc set_markers makes.
const W := 24.0


## A layer whose markers stand on `at`, with `plates` as the board's text and `pieces` as the pieces at its top.
class StandIn extends ChronicleMarkers:
	var at := Vector2.ZERO
	var plates: Array = []
	var pieces: Array = []

	func point_of(_province_id: String) -> Vector2:
		return at

	func taken_rects() -> Array:
		return plates.duplicate()

	func top_rects() -> Array:
		return pieces.duplicate()


## Where the Table hangs a playback bar and its caption: {"playback": Rect2, "caption": Rect2}.
func _pieces() -> Dictionary:
	return TableLayout.arrange(VIEW, {"playback": BAR, "caption": CAPTION}, true).rects


## A row of `n` markers centred on `p`, as the layer starts one.
func _row(p: Vector2, n: int) -> Rect2:
	var total := n * W + (n - 1) * ChronicleMarkers.GAP
	return Rect2(p - Vector2(total * 0.5, W * 0.5), Vector2(total, W))


func test_a_marker_on_a_province_under_the_bar_or_its_caption_hides_with_it() -> void:
	var r := _pieces()
	var bar: Rect2 = r.playback
	var caption: Rect2 = r.caption
	assert_true(caption.position.y >= bar.end.y and caption.get_center().x == bar.get_center().x, "the Table hangs the caption under the bar")
	for piece: Rect2 in [bar, caption]:
		var row := _row(piece.get_center(), 2)  # two cards' markers on a province under the piece's words
		assert_false(ChronicleMarkers.row_at(row, [], [bar, caption]).has_area(), "a row whose middle is under %s hides" % piece)
		assert_eq(ChronicleMarkers.row_at(row, [], []), row, "and stands on its province when nothing is at the top")


func test_a_marker_that_only_touches_the_bar_goes_below_it() -> void:
	var bar: Rect2 = _pieces().playback
	var row := _row(Vector2(bar.get_center().x, bar.end.y + W * 0.25), 2)  # its middle just under the bar's foot
	assert_true(row.intersects(bar) and not bar.has_point(row.get_center()), "the row touches the bar, its middle clear of it")
	var got := ChronicleMarkers.row_at(row, [], [bar])
	assert_false(got.intersects(bar), "clear of the bar")
	assert_eq(got.position, Vector2(row.position.x, bar.end.y + 2.0), "just under it, over its province")


func test_a_marker_a_plate_would_lift_into_the_bar_goes_down_past_the_plate() -> void:
	var bar: Rect2 = _pieces().playback
	var row := _row(Vector2(bar.get_center().x, bar.end.y + W), 1)  # a province just under the bar
	var plate := Rect2(row.position + Vector2(-30.0, 6.0), Vector2(row.size.x + 60.0, 22.0))  # its name, under the marker
	assert_false(row.intersects(bar), "the marker starts clear of the bar")
	assert_true(ChronicleMarkers.row_at(row, [plate], []).intersects(bar), "lifted over its plate, it would cover the bar")
	var got := ChronicleMarkers.row_at(row, [plate], [bar])
	assert_false(got.intersects(bar) or got.intersects(plate), "clear of both")
	assert_eq(got.position, Vector2(row.position.x, plate.end.y + 2.0), "it goes down past the plate instead")


func test_with_nothing_at_the_top_a_marker_still_lifts_over_a_plate() -> void:
	var bar: Rect2 = _pieces().playback
	var row := _row(TableLayout.framing_area(VIEW, true).get_center(), 3)  # three markers in the board's middle
	var plate := Rect2(row.position + Vector2(-20.0, 8.0), Vector2(row.size.x + 40.0, 22.0))
	var over := Vector2(row.position.x, plate.position.y - W - 2.0)
	assert_eq(ChronicleMarkers.row_at(row, [plate], []).position, over, "lifted just over its plate")
	assert_eq(ChronicleMarkers.row_at(row, [plate], [bar]).position, over, "a bar it never meets changes nothing")
	assert_eq(ChronicleMarkers.row_at(row, [], [bar]), row, "and a row that meets nothing stays put")


func test_the_layer_hides_its_discs_under_the_bar_and_puts_them_back_when_it_goes() -> void:
	var r := _pieces()
	var m := StandIn.new()
	m.at = (r.playback as Rect2).get_center()
	m.pieces = [r.playback, r.caption]  # a turn plays out
	var list := [{"number": 1, "province": "p", "id": "a", "headline": "A battle won"}, {"number": 3, "province": "p", "id": "b", "headline": "A province taken"}]
	m.set_markers(list)
	for id in ["a", "b"]:
		assert_false(m.marker(id).visible, "marker %s hides under the bar with its province" % id)
	m.pieces = []  # the playback is over
	m.set_markers(list)
	var row := _row(m.at, 2)
	for i in 2:
		var disc := m.marker(["a", "b"][i])
		assert_true(disc.visible, "marker %d is back" % disc.number)
		assert_eq(disc.position, (row.position + Vector2(i * (W + ChronicleMarkers.GAP), 0.0)).round(), "on its province, side by side in the cards' order")
	m.free()
