extends Control
## A stand-in for the 3D battle stage (M3b) in tests/test_battle_host.gd: the battle view contract of
## ui/battle/README.md and nothing else. It records every play() call, hosts the shared BattleControls on a
## real BattlePlayer, and finishes or closes when a test says so.

signal finished
signal closed

var controls := BattleControls.new()
var player: BattlePlayer = null
var reduced_motion := false
var calls: Array = []


func _init() -> void:
	name = "BattleStageStandIn"
	add_child(controls)


func play(battle_log: Dictionary, report: Dictionary, state: GameState, seats: Array) -> String:
	calls.append({"log": battle_log, "report": report, "state": state, "seats": seats.duplicate()})
	player = BattlePlayer.new(battle_log, report)
	controls.bind(player)
	visible = true
	return ""


## The playback reaches its result.
func finish() -> void:
	player.skip_to_end()
	finished.emit()


func close() -> void:
	if player != null:
		player.pause()
	visible = false
	closed.emit()
