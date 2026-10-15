class_name ChronicleSettings
extends RefCounted
## UX-6 (design/UX_WAR_TABLE.md §5.2): the Chronicle's own settings, in a [chronicle] section of the player's settings file
## (GameSettings.default_path), the way the battle screen keeps [battle]. They are the same for every game and every player at the table
## and hold no game facts: which kinds of announcement are hidden, how the list is sorted, whether the medallion stack is shown, and when
## the Chronicle opens by itself at the start of a turn.
##   auto_open     ChronicleModel.AUTO_OPEN: "important" (the default: a battle you fought with its report, an army lost, land won or lost,
##                 anything that needs you), "needs_you", "always", "never", or "report" (today's full report as a modal, every turn)
##   sort          ChronicleModel.SORTS: "importance" (the default), "place" or "kind"
##   hidden        kinds the filter chips have switched off (a hidden kind still counts: "3 hidden")
##   stack_shown   the left-edge medallions are showing (true) or folded away (false)
##   review        UX-5 (§5.3): whether the seal opens the Plan first, to review the orders before they are sealed: REVIEWS, "first_game"
##                 (the default: during a player's first game, the one the first-game guide is for, and not after), "always" or "never"
## A missing file, section or value gives the defaults; a value this game does not know is ignored. Other sections of the file are kept.

const SECTION := "chronicle"

## What a fresh install opens by itself: "important". tests/runner.gd sets it to "report" for the whole suite, so every older test that
## reads today's modal report at the start of a turn still does; the Chronicle's own tests set the field they mean.
static var default_auto_open := "important"
## UX-5: when the seal opens the Plan first (review before sealing), and what a fresh install does: "first_game". tests/runner.gd sets it
## to "never" for the whole suite, so every older test's End turn still ends the turn at once; the Plan's own tests set the field they mean.
const REVIEWS := ["first_game", "always", "never"]
static var default_review := "first_game"

var path := ""
var auto_open := ""
var sort := "importance"
var hidden: Array = []
var stack_shown := true
var review := ""


func _init(file_path: String = "") -> void:
	path = file_path if not file_path.is_empty() else GameSettings.default_path
	auto_open = default_auto_open
	review = default_review


static func load_from(file_path: String = "") -> ChronicleSettings:
	var s := ChronicleSettings.new(file_path)
	var cfg := ConfigFile.new()
	if cfg.load(s.path) != OK:
		return s
	var mode = cfg.get_value(SECTION, "auto_open", s.auto_open)
	if mode is String and ChronicleModel.AUTO_OPEN.has(mode):
		s.auto_open = mode
	var order = cfg.get_value(SECTION, "sort", "importance")
	if order is String and ChronicleModel.SORTS.has(order):
		s.sort = order
	var off = cfg.get_value(SECTION, "hidden", [])
	if off is Array:
		for k in off:
			if k is String and ChronicleModel.KINDS.has(k) and not s.hidden.has(k):
				s.hidden.append(k)
	var shown = cfg.get_value(SECTION, "stack_shown", true)
	if shown is bool:
		s.stack_shown = shown
	var rv = cfg.get_value(SECTION, "review", s.review)
	if rv is String and REVIEWS.has(rv):
		s.review = rv
	return s


## Writes the section, keeping the rest of the file. "" or why it could not be saved.
func save() -> String:
	var cfg := ConfigFile.new()
	var existed := FileAccess.file_exists(path)
	if existed:
		cfg.load(path)
	GameSettings.stamp_new_file(cfg, existed)
	cfg.set_value(SECTION, "auto_open", auto_open)
	cfg.set_value(SECTION, "sort", sort)
	cfg.set_value(SECTION, "hidden", hidden)
	cfg.set_value(SECTION, "stack_shown", stack_shown)
	cfg.set_value(SECTION, "review", review)
	var folder := path.get_base_dir()
	if not folder.is_empty() and not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
	return "" if cfg.save(path) == OK else "Your settings could not be saved."


func set_auto_open(mode: String) -> bool:
	if not ChronicleModel.AUTO_OPEN.has(mode):
		return false
	auto_open = mode
	return true


## UX-5: when the seal opens the Plan first (REVIEWS). False for a value this game does not know.
func set_review(mode: String) -> bool:
	if not REVIEWS.has(mode):
		return false
	review = mode
	return true


func set_sort(mode: String) -> bool:
	if not ChronicleModel.SORTS.has(mode):
		return false
	sort = mode
	return true


## Hides or shows a kind. False for a kind the model does not know.
func set_kind_hidden(kind: String, off: bool) -> bool:
	if not ChronicleModel.KINDS.has(kind):
		return false
	if off and not hidden.has(kind):
		hidden.append(kind)
	elif not off:
		hidden.erase(kind)
	return true
