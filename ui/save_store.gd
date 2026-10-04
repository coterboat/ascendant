class_name SaveStore
extends RefCounted
## Where saved games live: one JSON file per save (SaveGame) in a folder, user://saves by default.
## Autosaves are "auto_<n>.json" and only the newest AUTOSAVES_KEPT are kept; manual saves are
## "save_<n>.json" and stay until the player deletes them. <n> counts up across both kinds, so the newest
## save always has the highest number, even when two are made in the same second.
##
##   var store := SaveStore.new()            # user://saves (default_root)
##   store.write(SaveGame.make(...))         # {"path", "error"}
##   store.list()                            # newest first: [{"path", "file", "kind", "number", "header", "errors"}]
##   store.latest()                          # the newest save that can be read, or {}
##   store.read(path)                        # {"save", "errors"}
##   store.delete(path)                      # "" or why not
##
## Tests never touch the real saves: they pass their own folder, and tests/runner.gd points default_root
## (and GameSettings.default_path) at a temporary folder before any test runs.
## A file that is not a save, is cut short or was made by a newer version is listed with its reason in
## plain words (SaveGame.check), never a crash.

const AUTOSAVES_KEPT := 3
const EXTENSION := ".json"
const AUTO_PREFIX := "auto_"
const MANUAL_PREFIX := "save_"
const UNREADABLE := "This save file could not be read. It may have been moved, or the disk could not be reached."
const CUT_SHORT := "This save file is damaged: it is incomplete or has been changed, so it can't be read."

static var default_root := "user://saves"

var root := ""


func _init(folder: String = "") -> void:
	root = folder if not folder.is_empty() else default_root


## Writes `save` as a new file. An autosave then drops the oldest autosaves beyond AUTOSAVES_KEPT.
## Returns {"path": the new file, "error": "" or why it could not be saved}.
func write(save: Dictionary) -> Dictionary:
	var made := DirAccess.make_dir_recursive_absolute(root)
	if made != OK and not DirAccess.dir_exists_absolute(root):
		return {"path": "", "error": "The game could not be saved: the save folder could not be created."}
	var kind := String(SaveGame.header_of(save).get("kind", SaveGame.MANUAL))
	var prefix := AUTO_PREFIX if kind == SaveGame.AUTO else MANUAL_PREFIX
	var path := root.path_join("%s%06d%s" % [prefix, _next_number(), EXTENSION])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"path": "", "error": "The game could not be saved: the save file could not be written."}
	file.store_string(JSON.stringify(save))
	file.close()
	if kind == SaveGame.AUTO:
		_rotate()
	return {"path": path, "error": ""}


## Reads one save: {"save": Dictionary or null, "errors": plain-language reasons}.
func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"save": null, "errors": [UNREADABLE]}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"save": null, "errors": [CUT_SHORT]}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"save": null, "errors": [CUT_SHORT]}
	var errors := SaveGame.check(json.data)
	return {"save": json.data if errors.is_empty() else null, "errors": errors}


## Every save file, newest first: {"path", "file", "kind" ("auto" or "manual"), "number", "header",
## "errors"}. A file that can't be read has errors and an empty header.
func list() -> Array:
	var out := []
	for file in _files():
		var path := root.path_join(file)
		var got := read(path)
		out.append({"path": path, "file": file, "kind": SaveGame.AUTO if file.begins_with(AUTO_PREFIX) else SaveGame.MANUAL,
			"number": _number(file), "header": SaveGame.header_of(got.save), "errors": got.errors})
	out.sort_custom(_newer)
	return out


## The newest save that can be read (an entry of list()), or {} when there is none.
func latest() -> Dictionary:
	for entry in list():
		if entry.errors.is_empty():
			return entry
	return {}


func has_saves() -> bool:
	return not _files().is_empty()


## The autosaves, newest first.
func autosaves() -> Array:
	return list().filter(func(e): return e.kind == SaveGame.AUTO)


## Deletes a save file. Returns "" or why it could not.
func delete(path: String) -> String:
	if not path.begins_with(root) or not FileAccess.file_exists(path):
		return "That save is no longer there."
	if DirAccess.remove_absolute(path) != OK:
		return "That save could not be deleted."
	return ""


## Deletes every save file in the folder (tests clean up their temporary folders with this).
func clear() -> void:
	for file in _files():
		DirAccess.remove_absolute(root.path_join(file))


# --- internals ------------------------------------------------------------------------------------

func _files() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(root):
		return out
	for file in DirAccess.get_files_at(root):
		if file.ends_with(EXTENSION) and (file.begins_with(AUTO_PREFIX) or file.begins_with(MANUAL_PREFIX)):
			out.append(file)
	return out


func _number(file: String) -> int:
	var stem := file.get_basename()
	return Serial.to_int(stem.substr(stem.find("_") + 1), 0)


func _next_number() -> int:
	var top := 0
	for file in _files():
		top = maxi(top, _number(file))
	return top + 1


## Newest first: the later save time, then the higher number.
func _newer(a: Dictionary, b: Dictionary) -> bool:
	var ta := Serial.to_int(a.header.get("saved_at", 0))
	var tb := Serial.to_int(b.header.get("saved_at", 0))
	if ta != tb:
		return ta > tb
	return a.number > b.number


func _rotate() -> void:
	var autos := []
	for file in _files():
		if file.begins_with(AUTO_PREFIX):
			autos.append(file)
	autos.sort_custom(func(a, b): return _number(a) > _number(b))
	for i in range(AUTOSAVES_KEPT, autos.size()):
		DirAccess.remove_absolute(root.path_join(autos[i]))
