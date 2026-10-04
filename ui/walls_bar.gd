class_name WallsBar
extends Control
## A fort's walls as a bar (M3c S-3, #101; design/M3C_SIEGES.md §10.1, §13.3 "the walls bar on the province
## plate"): one cell per point of wall strength, grouped in steps of FortData.WALL_STEP with a gap between steps,
## because each step standing is +2 defense if the fort is stormed. Standing walls are pale stone; lost walls
## are dark with a red edge, so the bar reads without colour too (filled against hollow). At 0 the bar is all
## hollow with a red slash: breached. Drawn in code; the plate's chip and the fort panel use it. It only draws
## the numbers it is given (from the state through SiegeRules); the tooltip is its owner's.

const STONE := Color("#E4DCC8")
const STONE_EDGE := Color("#8C8270")
const LOST := Color("#3A2A2A")
const LOST_EDGE := Color("#B04A40")
const BREACH := Color("#F06A64")

var walls := 0:
	set(v):
		walls = v
		queue_redraw()
var walls_max := 0:
	set(v):
		walls_max = v
		queue_redraw()
var step := FortData.WALL_STEP
## Pixels between steps, and between cells inside a step.
var step_gap := 4.0
var cell_gap := 1.0


func _init(p_walls: int = 0, p_max: int = 0, height: float = 8.0, width: float = 0.0) -> void:
	name = "WallsBar"
	walls = p_walls
	walls_max = p_max
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(width if width > 0.0 else _natural_width(height), height)


## The width the bar wants at `height`: square-ish cells, a gap between steps.
func _natural_width(height: float) -> float:
	var cell := maxf(4.0, height * 0.75)
	var steps := ceili(float(maxi(walls_max, 1)) / step)
	return walls_max * cell + (walls_max - steps) * cell_gap + (steps - 1) * step_gap


func _draw() -> void:
	if walls_max <= 0:
		return
	var steps := ceili(float(walls_max) / step)
	var gaps := (walls_max - steps) * cell_gap + (steps - 1) * step_gap
	var cell := maxf(2.0, (size.x - gaps) / walls_max)
	var x := 0.0
	for i in walls_max:
		if i > 0:
			x += step_gap if i % step == 0 else cell_gap
		var r := Rect2(Vector2(x, 0), Vector2(cell, size.y))
		if i < walls:
			draw_rect(r, STONE)
			draw_rect(r, STONE_EDGE, false, 1.0)
		else:
			draw_rect(r, LOST)
			draw_rect(r, LOST_EDGE, false, 1.0)
		x += cell
	if walls <= 0:
		draw_line(Vector2(0, size.y), Vector2(size.x, 0), BREACH, maxf(2.0, size.y * 0.25), true)
