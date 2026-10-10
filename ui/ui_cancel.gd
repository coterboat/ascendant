class_name UiCancel
extends RefCounted
## UX-1 (design/UX_WAR_TABLE.md §1.4): one cancel, in order. Esc, and a right-click on empty board, go through this one
## dispatcher, which closes the topmost thing only, in this order:
##   1. "modal"      a modal panel or dialog (research, ruler, codex, cast, the report, the menu and its dialogs)
##   2. "march"      march targeting (UX-3: the map screen registers the selection cards' march strip)
##   3. "chronicle"  the Chronicle (UX-6; nothing yet)
##   4. "card"       the selection card
##   5. "lens"       the active lens (UX-7; the LensHost registers its clear)
##   6. "closeup"    the board's fortress close-up
##   7. "menu"       nothing left: Esc opens the menu (a right-click never does: it only closes things)
## Each layer is a list of providers: an `is_open` Callable() -> bool and a `close` Callable(), with a priority (higher is
## tried first; several modals can be open at once and the one drawn on top closes first). The map screen owns the
## dispatcher and registers the layers it owns; the game screen registers its overlays and the menu; later tickets register
## their own layer here instead of editing the two files. The codex, the board's close-up and the game screen's Esc all
## call cancel(), so a stack of them closes one layer a press.
##
## API:
##   register(layer, is_open, close, priority = 0)   add a provider to a layer from LAYERS
##   set_menu_opener(open_menu)                      what Esc does when nothing is open (the game screen's open_menu)
##   cancel(from_pointer = false) -> String          closes the topmost open thing and returns its layer; "" when there
##                                                   was nothing to close and nothing was opened. From the pointer
##                                                   the menu step is skipped.
##   topmost() -> String                             the layer cancel() would close now ("menu" for the menu step)
##   is_open(layer) -> bool
##   signal cancelled(layer)

signal cancelled(layer: String)

const LAYERS := ["modal", "march", "chronicle", "card", "lens", "closeup", "menu"]

var _providers := {}  # layer -> [{"open": Callable, "close": Callable, "priority": int, "seq": int}]
var _menu_opener := Callable()
var _seq := 0


func register(layer: String, is_open: Callable, close: Callable, priority: int = 0) -> void:
	if not LAYERS.has(layer) or layer == "menu":
		push_error("UiCancel: '%s' is not a layer a provider can register in." % layer)
		return
	if not _providers.has(layer):
		_providers[layer] = []
	_seq += 1
	_providers[layer].append({"open": is_open, "close": close, "priority": priority, "seq": _seq})
	(_providers[layer] as Array).sort_custom(func(a, b): return a.priority > b.priority or (a.priority == b.priority and a.seq < b.seq))


func set_menu_opener(open_menu: Callable) -> void:
	_menu_opener = open_menu


## True when something in `layer` is open now.
func is_open(layer: String) -> bool:
	return not _first_open(layer).is_empty()


## The layer cancel() would close now: the first of LAYERS with something open, "menu" when only the menu is left, and ""
## when there is not even a menu to open.
func topmost() -> String:
	for layer in LAYERS:
		if layer != "menu" and is_open(layer):
			return layer
	return "menu" if _menu_opener.is_valid() else ""


## Closes the topmost open thing, and only that. Returns its layer, or "" when nothing was open and no menu was opened.
func cancel(from_pointer: bool = false) -> String:
	for layer in LAYERS:
		if layer == "menu":
			break
		var p := _first_open(layer)
		if p.is_empty():
			continue
		(p.close as Callable).call()
		cancelled.emit(layer)
		return layer
	if from_pointer or not _menu_opener.is_valid():
		return ""
	_menu_opener.call()
	cancelled.emit("menu")
	return "menu"


func _first_open(layer: String) -> Dictionary:
	for p: Dictionary in _providers.get(layer, []):
		if (p.open as Callable).is_valid() and bool((p.open as Callable).call()):
			return p
	return {}
