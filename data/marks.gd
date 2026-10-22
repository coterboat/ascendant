class_name MarkData
## Marks on the land (CW-1, #252; design/CANDLEWAKE.md §3.1, §3.2). A faction with a row here marks the provinces it holds, and
## the mark grows through stages the longer it holds them; lose the province and the mark lingers as a scar for a while.
## Only the Candlewake have a row in this milestone, and the engine is generic: another people's marks need a row, not code
## (§13). GameState.marks holds the marks in play; MarkRules owns them.
##
## A row:
##   "stages"      in order, stage 1 first: {"id", "name" (as players read it), "held" (the turns held it takes: held =
##                 E - since_turn, on the end clock E = current_turn + 1), "harbour" (a Wick army ending a turn there keeps
##                 its flame), "gold" (the change to the province's income), "risen" (the dead rise there, §3.6)}
##   "scar_turns"  a lost mark lingers as a scar this many turns for each stage it had (§3.3)
##   "capital"     a capital counts as held since this end clock, so it stands at the last stage from the start
## CW-1 ships the shape and the numbers; the wake step that reads them (stages, scars, harbours, gold, the Risen) is CW-3
## (#254). Every number is a starting point that CW-11 (#262) tunes.

const ROWS := {
	"candlewake": {
		"stages": [
			{"id": "sitting_up", "name": "Sitting Up", "held": 0, "harbour": false, "gold": 0, "risen": false},
			{"id": "wake_line", "name": "the Wake-Line", "held": 3, "harbour": true, "gold": -1, "risen": false},
			{"id": "deep_wake", "name": "Deep Wake", "held": 6, "harbour": true, "gold": -1, "risen": true},
		],
		"scar_turns": 2,
		"capital": -6,
	},
}


## The row of `faction_id`, or {} for a faction that marks nothing.
static func row(faction_id: String) -> Dictionary:
	return ROWS.get(faction_id, {})


## How many stages `faction_id`'s mark has (0 without a row).
static func stage_count(faction_id: String) -> int:
	return Array(row(faction_id).get("stages", [])).size()


## Stage `stage` (1-based) of `faction_id`'s mark, or {}.
static func stage(faction_id: String, stage_number: int) -> Dictionary:
	var stages: Array = row(faction_id).get("stages", [])
	return stages[stage_number - 1] if stage_number >= 1 and stage_number <= stages.size() else {}
