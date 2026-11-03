class_name PieceMoveDiagram
extends Control

var kind := "sovereign":
	set(value):
		kind = value
		queue_redraw()

const GRID_COLOR := Color(0.42, 0.34, 0.24, 0.72)
const LIGHT_SQUARE := Color(0.31, 0.25, 0.19, 0.72)
const DARK_SQUARE := Color(0.20, 0.16, 0.13, 0.76)
const ARROW_COLOR := Color("c49a4e")
const HEIGHT_THREE_ARROW_COLOR := Color("5f88ad")
const SPECIAL_ARROW_COLOR := Color("a8a39a")
const PIECE_COLOR := Color("eee1ca")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(290.0, 210.0)
	resized.connect(queue_redraw)


func _draw() -> void:
	var board_size := minf(size.y, size.x)
	var origin := Vector2((size.x - board_size) * 0.5, 0.0)
	var cell := board_size / 7.0
	for y in range(7):
		for x in range(7):
			var color := LIGHT_SQUARE if (x + y) % 2 == 0 else DARK_SQUARE
			draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell), color)
	for index in range(8):
		var offset := float(index) * cell
		draw_line(origin + Vector2(offset, 0.0), origin + Vector2(offset, board_size), GRID_COLOR, 1.0)
		draw_line(origin + Vector2(0.0, offset), origin + Vector2(board_size, offset), GRID_COLOR, 1.0)
	var center := origin + Vector2(3.5, 3.5) * cell
	_draw_piece(center, cell)
	match kind:
		"sovereign":
			for direction in _queen_directions():
				_draw_arrow(center, center + direction * cell, ARROW_COLOR)
		"infantry":
			_draw_arrow(center, center + Vector2(0.0, -3.0) * cell, ARROW_COLOR)
			_draw_range_ticks(center, Vector2(0.0, -1.0), cell, 3)
		"dragoon":
			for direction in _diagonal_directions():
				_draw_arrow(center, center + direction * cell * 3.0, ARROW_COLOR)
		"chariot":
			for direction in _orthogonal_directions():
				_draw_arrow(center, center + direction * cell * 3.0, ARROW_COLOR)
		"griffin":
			for offset in [Vector2(2, 3), Vector2(3, 2), Vector2(-2, 3), Vector2(-3, 2), Vector2(2, -3), Vector2(3, -2), Vector2(-2, -3), Vector2(-3, -2)]:
				_draw_bent_arrow(center, center + offset * cell, HEIGHT_THREE_ARROW_COLOR)
			for offset in [Vector2(1, 2), Vector2(2, 1), Vector2(-1, 2), Vector2(-2, 1), Vector2(1, -2), Vector2(2, -1), Vector2(-1, -2), Vector2(-2, -1)]:
				_draw_bent_arrow(center, center + offset * cell, ARROW_COLOR)
		"marshal":
			for direction in _queen_directions():
				_draw_arrow(center, center + direction * cell * 3.0, ARROW_COLOR)
		"spy":
			_draw_conversion_arrows(center, cell)
		"ballista":
			for direction in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
				_draw_dashed_arrow(center, center + direction * cell * 3.0, SPECIAL_ARROW_COLOR)
		"trebuchet":
			for direction in [Vector2(-1, -1).normalized(), Vector2(1, -1).normalized()]:
				_draw_dashed_arrow(center, center + direction * cell * 3.9, SPECIAL_ARROW_COLOR)
		"reinforcement":
			_draw_arrow(center + Vector2(0.0, -2.2) * cell, center + Vector2(0.0, -0.55) * cell, SPECIAL_ARROW_COLOR)
			draw_string(ThemeDB.fallback_font, center + Vector2(-1.15, 2.35) * cell, "UNDER A STACK", HORIZONTAL_ALIGNMENT_CENTER, 2.3 * cell, 12, SPECIAL_ARROW_COLOR)
		"recall":
			_draw_recall_arrow(center, cell)


func _draw_piece(center: Vector2, cell: float) -> void:
	draw_circle(center, cell * 0.31, Color(0.04, 0.035, 0.03, 0.95))
	draw_arc(center, cell * 0.31, 0.0, TAU, 32, PIECE_COLOR, 2.0, true)
	draw_circle(center, cell * 0.095, PIECE_COLOR)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var direction := (to - from).normalized()
	var start := from + direction * 11.0
	var end := to - direction * 5.0
	draw_line(start, end, color, 3.0, true)
	_draw_arrow_head(end, direction, color)


func _draw_dashed_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var direction := (to - from).normalized()
	var distance := from.distance_to(to)
	for offset in range(14, floori(distance - 8.0), 12):
		draw_line(from + direction * float(offset), from + direction * minf(float(offset + 7), distance - 8.0), color, 2.5, true)
	_draw_arrow_head(to - direction * 5.0, direction, color)


func _draw_bent_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var delta := to - from
	var elbow := from + Vector2(delta.x, 0.0)
	draw_polyline(PackedVector2Array([from + Vector2(signf(delta.x) * 10.0, 0.0), elbow, to - Vector2(0.0, signf(delta.y) * 5.0)]), color, 2.5, true)
	_draw_arrow_head(to - Vector2(0.0, signf(delta.y) * 5.0), Vector2(0.0, signf(delta.y)), color)


func _draw_arrow_head(point: Vector2, direction: Vector2, color: Color) -> void:
	var side := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([point + direction * 7.0, point - direction * 6.0 + side * 5.0, point - direction * 6.0 - side * 5.0]), color)


func _draw_range_ticks(center: Vector2, direction: Vector2, cell: float, count: int) -> void:
	for index in range(1, count + 1):
		var point := center + direction * cell * float(index)
		draw_circle(point, 3.0, PIECE_COLOR)


func _draw_conversion_arrows(center: Vector2, cell: float) -> void:
	for direction in _queen_directions():
		var target := center + direction * cell * 1.55
		_draw_dashed_arrow(target, center + direction * cell * 0.48, SPECIAL_ARROW_COLOR)


func _draw_recall_arrow(center: Vector2, cell: float) -> void:
	var points := PackedVector2Array()
	for index in range(25):
		var angle := lerpf(-PI * 0.15, PI * 1.45, float(index) / 24.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * cell * 1.25)
	draw_polyline(points, SPECIAL_ARROW_COLOR, 3.0, true)
	var direction := (points[-1] - points[-2]).normalized()
	_draw_arrow_head(points[-1], direction, SPECIAL_ARROW_COLOR)


func _queen_directions() -> Array[Vector2]:
	return _orthogonal_directions() + _diagonal_directions()


func _orthogonal_directions() -> Array[Vector2]:
	return [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]


func _diagonal_directions() -> Array[Vector2]:
	return [Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(), Vector2(1, 1).normalized(), Vector2(-1, 1).normalized()]
