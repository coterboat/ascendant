class_name MarkData
## Marks on the land (CW-1, #252; design/CANDLEWAKE.md §3.1, §3.2). A faction with a row here marks the provinces it holds, and
## the mark grows through stages the longer it holds them; lose the province and the mark lingers as a scar for a while.
## Only the Candlewake have a row in this milestone, and the engine is generic: another people's marks need a row, not code
## (§13). GameState.marks holds the marks in play; MarkRules owns them.
##
## A row:
##   "stages"      in order, stage 1 first: {"id", "name" (as players read it), "held" (the turns held it takes: held =
##                 E - since_turn, on the end clock E = current_turn + 1), "harbour" (a Wick army ending a turn there keeps
##                 its flame), "gold" (the change to the province's income), "risen" (the dead rise there, §3.6), "sooner"
##                 (CW-4: a path's "wake_sooner" brings this stage that many turns sooner, never before 1 turn held)}
##   "scar_turns"  a lost mark lingers as a scar this many turns for each stage it had (§3.3)
##   "capital"     a capital counts as held since this end clock, so it stands at the last stage from the start
##   "risen"       the dead rise (§3.6) where the mark stands at a stage whose "risen" is true: "count" of the roster's "unit"
##                 every "every" turns past that stage's threshold (held = threshold + every, threshold + 2 × every, ...)
## CW-1 shipped the shape and the numbers, and CW-3 (#254) the wake step that reads them (MarkRules: stages, scars, harbours,
## gold, the Risen). Every number is a starting point that CW-11 (#262) tunes.

const ROWS := {
	"candlewake": {
		"stages": [
			{"id": "sitting_up", "name": "Sitting Up", "held": 0, "harbour": false, "gold": 0, "risen": false},
			{"id": "wake_line", "name": "the Wake-Line", "held": 3, "harbour": true, "gold": -1, "risen": false, "sooner": true},
			{"id": "deep_wake", "name": "Deep Wake", "held": 6, "harbour": true, "gold": -1, "risen": true},
		],
		"scar_turns": 2,
		"capital": -6,
		"risen": {"unit": "wickwardens", "every": 4, "count": 1},
	},
}


## The row of `faction_id`, or {} for a faction that marks nothing.
static func row(faction_id: String) -> Dictionary:
	return ROWS.get(faction_id, {})


## How many stages `faction_id`'s mark has (0 without a row).
static func stage_count(faction_id: String) -> int:
	return Array(row(faction_id).get("stages", [])).size()


## The turns a mark of `faction_id` is held before the dead rise there: the threshold of its first stage whose "risen" is true,
## or -1 when they never do.
static func risen_threshold(faction_id: String) -> int:
	for st in row(faction_id).get("stages", []):
		if bool(st.get("risen", false)):
			return int(st.held)
	return -1


## The 1-based number of `faction_id`'s stage `stage_id` ("wake_line": 2), or 0.
static func stage_index(faction_id: String, stage_id: String) -> int:
	var stages: Array = row(faction_id).get("stages", [])
	for i in stages.size():
		if String(stages[i].id) == stage_id:
			return i + 1
	return 0


## Stage `stage` (1-based) of `faction_id`'s mark, or {}.
static func stage(faction_id: String, stage_number: int) -> Dictionary:
	var stages: Array = row(faction_id).get("stages", [])
	return stages[stage_number - 1] if stage_number >= 1 and stage_number <= stages.size() else {}
