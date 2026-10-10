class_name ReportHost
extends RefCounted
## UX-1 (design/UX_WAR_TABLE.md §1.1): the report seam. The life of a turn's report goes through here: a turn resolved, the
## report is ready, it was opened, it was closed. It replaces the call sites of the modal report in ui/game_screen.gd.
## Until UX-6 the presenter is the game screen's modal turn report (the "Turn report" button of the system row opens
## it); UX-6's Chronicle calls set_presenter() instead of editing game_screen.gd, and takes over what happens when a
## report is ready (auto-open, the medallions) and the "Full report" button (which keeps today's modal).
##
## A presenter is any object with these methods (each optional):
##   open_report() -> bool       show the report of the last resolved turn; true when it opened
##   close_report()              hide it
##   is_report_open() -> bool
##   on_report_ready(turn: int, context: Dictionary)   the report is ready to show: open it, light a medallion, or wait.
##                               `context` is {"cue_delay": seconds} for the headline sounds the modal plays
## Whoever shows a report tells the host with notify_opened / notify_closed so that listeners (the Chronicle's unread
## badge, the audio) hear it whichever presenter did it.
##
## API:
##   set_presenter(p), presenter()
##   notify_resolved(turn)       the session resolved `turn` (the board may play it before the report is ready)
##   notify_ready(turn, context) the report of `turn` is ready to show (after the board's playback)
##   open() -> bool, close(), is_open() -> bool
##   notify_opened(turn), notify_closed(turn)
##   last_resolved, last_ready, last_opened   the latest turn of each kind (0 before any)
##   signals turn_resolved(turn), report_ready(turn), report_opened(turn), report_closed(turn)

signal turn_resolved(turn: int)
signal report_ready(turn: int)
signal report_opened(turn: int)
signal report_closed(turn: int)

var last_resolved := 0
var last_ready := 0
var last_opened := 0
var _presenter: Object = null
var _open := false


func set_presenter(p: Object) -> void:
	_presenter = p


func presenter() -> Object:
	return _presenter


func notify_resolved(turn: int) -> void:
	last_resolved = turn
	turn_resolved.emit(turn)


## The report of `turn` is ready: the presenter decides what that means (the modal opens at once, as it always has).
func notify_ready(turn: int, context: Dictionary = {}) -> void:
	last_ready = turn
	report_ready.emit(turn)
	if _live() and _presenter.has_method("on_report_ready"):
		_presenter.call("on_report_ready", turn, context)


## Opens the report of the last resolved turn through the presenter. True when it opened.
func open() -> bool:
	if not _live() or not _presenter.has_method("open_report"):
		return false
	return bool(_presenter.call("open_report"))


func close() -> void:
	if _live() and _presenter.has_method("close_report"):
		_presenter.call("close_report")


func is_open() -> bool:
	if _live() and _presenter.has_method("is_report_open"):
		return bool(_presenter.call("is_report_open"))
	return _open


func notify_opened(turn: int) -> void:
	_open = true
	last_opened = turn
	report_opened.emit(turn)


func notify_closed(turn: int) -> void:
	_open = false
	report_closed.emit(turn)


func _live() -> bool:
	return _presenter != null and is_instance_valid(_presenter)
