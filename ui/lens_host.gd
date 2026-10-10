class_name LensHost
extends RefCounted
## UX-1 (design/UX_WAR_TABLE.md §1.1): the lens seam. A lens is an optional map view (Owner, Income, Threat, Magic, Making
## and Sight, UX-7): off by default, one at a time, never switched on by the game. UX-1 lands the seam with no lens in it:
## the active lens id is "", the keys list is empty, and the board is fed nothing. UX-7 registers the six lenses here
## instead of editing ui/map_screen.gd.
##
## A lens is registered with its id, its title, its key (a Key, KEY_1 to KEY_6) and a feed Callable(board) that pushes its
## texture and parameters to the board while it is the active one. Pressing a lens's key activates it; pressing the key of
## the active lens again clears it (the art comes back); Esc closes the lens too, through UiCancel's "lens" step. Every
## lens reads only the viewer's view; that is the lens's own business, the host shows nothing.
##
## API:
##   register(id, title, key, feed)      add a lens (re-registering an id replaces it)
##   ids() -> Array, title_of(id), key_of(id), id_for_key(keycode)
##   active_id() -> String               "" when no lens is on
##   activate(id) -> bool, toggle(id), clear()
##   feed_board(board)                   MapScreen calls it before every board sync: the active lens feeds the board
##   signal active_changed(id)

signal active_changed(id: String)

var _lenses := {}  # id -> {"title", "key", "feed"}
var _order: Array = []
var _active := ""


func register(id: String, title: String, key: int, feed: Callable = Callable()) -> void:
	if not _lenses.has(id):
		_order.append(id)
	_lenses[id] = {"title": title, "key": key, "feed": feed}


## The registered lens ids in registration order (none yet).
func ids() -> Array:
	return _order.duplicate()


func title_of(id: String) -> String:
	return String(_lenses.get(id, {}).get("title", ""))


func key_of(id: String) -> int:
	return int(_lenses.get(id, {}).get("key", KEY_NONE))


## The lens a key activates, or "" when it is no lens's key.
func id_for_key(keycode: int) -> String:
	for id in _order:
		if int(_lenses[id].key) == keycode:
			return String(id)
	return ""


## The lens that is on, or "" (no lens: the board as it is).
func active_id() -> String:
	return _active


## Turns `id` on. False when there is no such lens.
func activate(id: String) -> bool:
	if not _lenses.has(id):
		return false
	if _active != id:
		_active = id
		active_changed.emit(id)
	return true


## A lens's key: turns it on, or off when it is the one that is on.
func toggle(id: String) -> bool:
	if _active == id:
		clear()
		return true
	return activate(id)


func clear() -> void:
	if _active.is_empty():
		return
	_active = ""
	active_changed.emit("")


## The active lens feeds the board (its texture, its parameters). Nothing with no lens on.
func feed_board(board: Object) -> void:
	if _active.is_empty() or board == null:
		return
	var feed: Callable = _lenses[_active].feed
	if feed.is_valid():
		feed.call(board)
