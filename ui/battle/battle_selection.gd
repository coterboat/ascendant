class_name BattleSelection
extends RefCounted
## The selected fighter of a battle being watched (M3-4, #59; design/M3_BATTLES.md §5.3, §5.4, §7.3).
## Renderer-agnostic and pure: it talks only to the BattlePlayer, so the 2D Simple view and the 3D stage
## share it. Tab / Shift+Tab (or a click on a fighter) selects; the host keeps the selected fighter
## highlighted, and the why panel (BattleWhyPanel) pins its §5.4 explanation, updated as playback advances.
##
##   var sel := BattleSelection.new()
##   sel.bind(player, order)    order: fighter ids in Tab order (the host's: left side first, front to back);
##                              [] gives BattleSelection.default_order(log, left side)
##   sel.next() / sel.previous()   Tab / Shift+Tab: the next fighter still on the field (fallen markers
##                              count; fled and lost fighters have left it), wrapping round
##   sel.select(fid) / sel.toggle(fid) / sel.clear()
##   sel.selected               the fighter id, or -1
##   signal changed(fid)        after every change (-1: nothing selected)

signal changed(fid: int)

var selected := -1
var order: Array = []
var _player: BattlePlayer = null


func bind(player: BattlePlayer, tab_order: Array = []) -> void:
	_player = player
	order = tab_order.duplicate() if not tab_order.is_empty() else default_order(player.battle_log(), 0)
	if selected >= 0:
		selected = -1
		changed.emit(-1)


## Tab order without a layout: side `left` first, then the other; within a side front rank to back line,
## then log order.
static func default_order(battle_log: Dictionary, left: int) -> Array:
	var out := []
	var sides: Array = battle_log.get("sides", [])
	var picks := [left] + range(sides.size()).filter(func(si): return si != left)
	for si in picks:
		var ids: Array = BattleLog._ints(sides[si].fighters)
		ids.sort_custom(func(a, b):
			var ta := int(battle_log.fighters[a].tier)
			var tb := int(battle_log.fighters[b].tier)
			return ta < tb if ta != tb else a < b)
		out.append_array(ids)
	return out


func select(fid: int) -> void:
	if fid != selected:
		selected = fid
		changed.emit(fid)


## Selects `fid`, or clears the selection when it is already the selected fighter (a second click).
func toggle(fid: int) -> void:
	select(-1 if fid == selected else fid)


func clear() -> void:
	select(-1)


func next() -> int:
	return _step(1)


func previous() -> int:
	return _step(-1)


## Whether fighter `fid` is still on the field at the playhead (standing, or a fallen marker).
func on_field(fid: int) -> bool:
	if _player == null:
		return true
	var fs: Dictionary = _player.live_state().fighters[fid]
	return not (fs.fled or fs.lost) or not fs.alive


func _step(dir: int) -> int:
	if order.is_empty():
		return selected
	var at := order.find(selected)
	if at < 0:
		at = -1 if dir > 0 else order.size()
	for k in order.size():
		at = posmod(at + dir, order.size())
		var fid := int(order[at])
		if on_field(fid):
			select(fid)
			return fid
	return selected
