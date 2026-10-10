class_name SelectionHost
extends RefCounted
## UX-1 (design/UX_WAR_TABLE.md §1.1): the selection seam. "Show this army or province" and "selection cleared" go through
## here, and whoever shows details for a selection is registered here as the presenter. It replaces MapScreen's
## `_show_details`: the map screen tells the host what is selected and the host tells the presenter. Until UX-3 the
## presenter is the temporary details card (ui/details_card.gd); UX-3's army and province cards call set_presenter()
## instead of editing ui/map_screen.gd.
##
## A presenter is any object with these methods (each optional but show_*):
##   show_province(province_id: String)               a province was selected (or its details changed)
##   show_army(army_id: String, province_id: String)  an army was selected, in `province_id`
##   clear_selection()                                nothing is selected any more
##   refresh_selection()                              what is selected is the same but what it shows changed
##                                                    (an order was queued or cancelled, a new turn)
## Reads nothing of the game: the ids are the map screen's own selection.
##
## API:
##   set_presenter(p), presenter()    who shows the selection (null: nobody)
##   show_province(id), show_army(army_id, province_id), clear(), refresh()
##   kind() -> "province" | "army" | ""    and  id() -> the selected id
##   signal changed(kind, id)         the selection changed (not for refresh)

signal changed(kind: String, id: String)

var _presenter: Object = null
var _kind := ""
var _id := ""
var _province := ""


func set_presenter(p: Object) -> void:
	_presenter = p
	_present()


func presenter() -> Object:
	return _presenter


## "province", "army" or "" (nothing selected).
func kind() -> String:
	return _kind


func id() -> String:
	return _id


## The province the selection is in (an army's province, or the province itself).
func province_id() -> String:
	return _province


func show_province(province_id: String) -> void:
	var same := _kind == "province" and _id == province_id
	_kind = "province"
	_id = province_id
	_province = province_id
	_present()
	if not same:
		changed.emit(_kind, _id)


func show_army(army_id: String, province_id: String) -> void:
	var same := _kind == "army" and _id == army_id
	_kind = "army"
	_id = army_id
	_province = province_id
	_present()
	if not same:
		changed.emit(_kind, _id)


func clear() -> void:
	var was := _kind
	_kind = ""
	_id = ""
	_province = ""
	if _presenter != null and is_instance_valid(_presenter) and _presenter.has_method("clear_selection"):
		_presenter.call("clear_selection")
	if not was.is_empty():
		changed.emit("", "")


## What the selection shows changed (an order, a new turn): the presenter rebuilds.
func refresh() -> void:
	if _presenter == null or not is_instance_valid(_presenter):
		return
	if _presenter.has_method("refresh_selection"):
		_presenter.call("refresh_selection")
	else:
		_present()


func _present() -> void:
	if _presenter == null or not is_instance_valid(_presenter):
		return
	if _kind == "army" and _presenter.has_method("show_army"):
		_presenter.call("show_army", _id, _province)
	elif not _province.is_empty() and _presenter.has_method("show_province"):
		_presenter.call("show_province", _province)
	elif _kind.is_empty() and _presenter.has_method("clear_selection"):
		_presenter.call("clear_selection")
