extends Control

const Palette = preload("res://scripts/presentation/ternary_palette.gd")
const Tokens = preload("res://scripts/presentation/token_renderer.gd")
const Icons = preload("res://scripts/presentation/piece_icon_renderer.gd")
const Codec = preload("res://scripts/core/ternary_codec.gd")
const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")

const BOARD_DIMENSION := 9
const PIECE_ORDER := [
	"sovereign", "infantry", "dragoon", "chariot", "griffin", "marshal",
	"trebuchet", "ballista", "spy", "reinforcement", "recall",
]

var board_rect := Rect2()
var hovered_square := ""
var selected_square := "E5"
var sample_position := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_sample_position()
	resized.connect(queue_redraw)
	queue_redraw()


func _build_sample_position() -> void:
	sample_position = {
		"A9": _stack("black", ["sovereign"]),
		"C8": _stack("black", ["infantry", "chariot"]),
		"E8": _stack("black", ["dragoon"]),
		"G8": _stack("black", ["infantry", "ballista"]),
		"I8": _stack("black", ["marshal"]),
		"B7": _stack("black", ["infantry"]),
		"D7": _stack("black", ["reinforcement", "griffin"]),
		"H7": _stack("black", ["infantry", "spy"]),
		"C6": _stack("black", ["infantry", "dragoon", "griffin"]),
		"G6": _stack("black", ["trebuchet"]),
		"E5": _stack("white", ["reinforcement", "infantry", "marshal"]),
		"B4": _stack("white", ["infantry", "chariot"]),
		"F4": _stack("white", ["dragoon"]),
		"H4": _stack("white", ["infantry", "spy"]),
		"C3": _stack("white", ["infantry"]),
		"E3": _stack("white", ["reinforcement", "griffin"]),
		"G3": _stack("white", ["infantry", "ballista"]),
		"A1": _stack("white", ["sovereign"]),
		"I2": _stack("white", ["recall"]),
	}


func _stack(owner: String, kinds: Array) -> Dictionary:
	return {"owner": owner, "kinds": kinds}


func _draw() -> void:
	_draw_table()
	_calculate_board_rect()
	_draw_left_panel()
	_draw_board()
	_draw_action_markers()
	_draw_position()
	_draw_right_panel()


func _draw_table() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKGROUND)
	var glow_center := size * Vector2(0.52, 0.45)
	for index in range(8, 0, -1):
		var alpha := 0.012 * float(9 - index)
		draw_circle(glow_center, minf(size.x, size.y) * float(index) * 0.11, Color(Palette.BRASS, alpha))
	for index in range(34):
		var y := fmod(float(index * 83), maxf(1.0, size.y))
		draw_line(Vector2(0.0, y), Vector2(size.x, y + 13.0), Color(0.65, 0.54, 0.40, 0.018), 1.0)


func _calculate_board_rect() -> void:
	var available_height := maxf(540.0, size.y - 72.0)
	var available_width := maxf(540.0, size.x - 510.0)
	var side := floorf(minf(available_height, available_width))
	var left := floorf((size.x - side) * 0.5 - 4.0)
	var top := floorf((size.y - side) * 0.5)
	board_rect = Rect2(Vector2(left, top), Vector2(side, side))


func _draw_board() -> void:
	var frame := board_rect.grow(24.0)
	draw_rect(frame.grow(10.0), Color(0.0, 0.0, 0.0, 0.50))
	draw_rect(frame, Palette.FRAME_DARK)
	draw_rect(frame.grow(-5.0), Palette.FRAME_EDGE, false, 3.0)
	draw_rect(board_rect.grow(6.0), Palette.FRAME_MID)
	var cell := board_rect.size.x / BOARD_DIMENSION
	for row in range(BOARD_DIMENSION):
		var tint := Palette.territory_tint(row)
		for column in range(BOARD_DIMENSION):
			var square_rect := Rect2(board_rect.position + Vector2(column, row) * cell, Vector2(cell, cell))
			var base := Palette.LIGHT_SQUARE if (column + row) % 2 == 0 else Palette.DARK_SQUARE
			var strength := 0.30 if row <= 2 else (0.27 if row >= 6 else 0.24)
			var surface := base.lerp(tint, strength)
			draw_rect(square_rect, surface)
			_draw_square_grain(square_rect, column, row, base)
			draw_rect(square_rect, Palette.GRID_LINE, false, maxf(1.0, cell * 0.018))
			_draw_corner_inlay(square_rect, tint, cell)
	_draw_zone_watermarks(cell)

	# Territory boundaries are constructed into the board, not UI overlays.
	for boundary_row in [3, 6]:
		var y: float = board_rect.position.y + cell * int(boundary_row)
		draw_line(Vector2(board_rect.position.x, y - 3.0), Vector2(board_rect.end.x, y - 3.0), Color(0.08, 0.07, 0.055, 0.88), 3.0)
		draw_line(Vector2(board_rect.position.x, y + 2.0), Vector2(board_rect.end.x, y + 2.0), Palette.BRASS_LIGHT, 2.0)
	_draw_territory_rails(cell)
	_draw_coordinates(cell)


func _draw_square_grain(rect: Rect2, column: int, row: int, base: Color) -> void:
	for index in range(3):
		var seed_value := column * 61 + row * 37 + index * 19
		var x_offset := float((seed_value * 17) % 71) / 100.0
		var y_offset := float((seed_value * 29) % 73) / 100.0
		var start := rect.position + Vector2(rect.size.x * x_offset, rect.size.y * y_offset)
		var length := rect.size.x * (0.16 + float(seed_value % 11) / 80.0)
		draw_line(start, start + Vector2(length, 1.5), Color(base.lightened(0.35), 0.075), 1.0)


func _draw_corner_inlay(rect: Rect2, tint: Color, cell: float) -> void:
	var radius := maxf(2.5, cell * 0.045)
	draw_rect(Rect2(rect.position - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), Palette.FRAME_DARK)
	draw_rect(Rect2(rect.position - Vector2(radius * 0.62, radius * 0.62), Vector2(radius * 1.24, radius * 1.24)), tint.lightened(0.25))


func _draw_territory_rails(cell: float) -> void:
	var font := ThemeDB.fallback_font
	var rail_x := board_rect.position.x - 18.0
	var labels := ["BLACK HOME", "NEUTRAL FIELD", "WHITE HOME"]
	var colors := [Palette.BLACK_TERRITORY, Palette.NEUTRAL_TERRITORY, Palette.WHITE_TERRITORY]
	for zone in range(3):
		var zone_rect := Rect2(Vector2(rail_x - 4.0, board_rect.position.y + cell * zone * 3.0 + 8.0), Vector2(8.0, cell * 3.0 - 16.0))
		var right_zone_rect := Rect2(Vector2(board_rect.end.x + 27.0, zone_rect.position.y), zone_rect.size)
		for marker_rect in [zone_rect, right_zone_rect]:
			draw_rect(marker_rect, colors[zone])
			draw_rect(marker_rect, colors[zone].lightened(0.35), false, 1.0)
		var label_position := Vector2(board_rect.position.x + cell * 0.16, board_rect.position.y + cell * (zone * 3.0 + 0.28))
		draw_string(font, label_position, labels[zone], HORIZONTAL_ALIGNMENT_LEFT, -1.0, maxi(9, roundi(cell * 0.12)), Color(0.98, 0.95, 0.88, 0.50))


func _draw_zone_watermarks(cell: float) -> void:
	var font := ThemeDB.fallback_font
	var labels := ["BLACK HOME", "NEUTRAL FIELD", "WHITE HOME"]
	for zone in range(3):
		var baseline := board_rect.position.y + cell * (float(zone) * 3.0 + 1.72)
		draw_string(
			font,
			Vector2(board_rect.position.x, baseline),
			labels[zone],
			HORIZONTAL_ALIGNMENT_CENTER,
			board_rect.size.x,
			maxi(20, roundi(cell * 0.31)),
			Color(0.98, 0.95, 0.88, 0.115)
		)


func _draw_coordinates(cell: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(10, roundi(cell * 0.17))
	for column in range(BOARD_DIMENSION):
		var label := String.chr(65 + column)
		var x := board_rect.position.x + float(column) * cell
		draw_string(font, Vector2(x, board_rect.end.y + 18.0), label, HORIZONTAL_ALIGNMENT_CENTER, cell, font_size, Palette.TEXT_MUTED)
	for row in range(BOARD_DIMENSION):
		var rank := str(9 - row)
		var y := board_rect.position.y + (float(row) + 0.57) * cell
		draw_string(font, Vector2(board_rect.end.x + 10.0, y), rank, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Palette.TEXT_MUTED)


func _draw_action_markers() -> void:
	var markers := legal_move_markers(selected_square)
	for destination_value in markers:
		var destination := str(destination_value)
		var marker_kind := str(markers[destination])
		var center := _square_center(destination)
		if marker_kind == "capture":
			var capture_radius := board_rect.size.x / BOARD_DIMENSION * 0.40
			draw_circle(center, capture_radius * 0.80, Color(Palette.CAPTURE, 0.10))
			draw_arc(center, capture_radius, 0.0, TAU, 30, Palette.CAPTURE, 4.0, true)
		else:
			var move_radius := board_rect.size.x / BOARD_DIMENSION * 0.12
			draw_circle(center, move_radius, Color(Palette.MOVE, 0.28))
			draw_arc(center, move_radius * 1.34, 0.0, TAU, 24, Color(Palette.MOVE, 0.78), 2.0, true)


func legal_move_markers(square: String) -> Dictionary:
	if not sample_position.has(square):
		return {}
	var selected: Dictionary = sample_position[square]
	var state := _sample_engine_state(str(selected.owner))
	var markers := {}
	for action in GameEngine.legal_actions(state):
		if str(action.get("type", "")) != "move" or str(action.get("source", "")) != square:
			continue
		var destination := str(action.destination)
		markers[destination] = "capture" if sample_position.has(destination) else "move"
	return markers


func _sample_engine_state(turn: String) -> Dictionary:
	var board := {}
	for square_value in sample_position:
		var square := str(square_value)
		var data: Dictionary = sample_position[square]
		var stack: Array = []
		for kind in data.kinds:
			stack.append({"owner": str(data.owner), "kind": str(kind)})
		board[square] = stack
	return Codec.normalize_state({
		"contract_version": Rules.CONTRACT_VERSION,
		"rules": Rules.control_ruleset(),
		"board": board,
		"reserves": {"white": {}, "black": {}},
		"discards": {"white": {}, "black": {}},
		"turn": turn,
		"winner": null,
		"is_draw": false,
		"ply": 0,
		"development_placements": {"white": 0, "black": 0},
		"height_three_unlocked": {"white": true, "black": true},
	})


func _draw_position() -> void:
	var cell := board_rect.size.x / BOARD_DIMENSION
	var radius := cell * 0.37
	var ordered_squares: Array = sample_position.keys()
	ordered_squares.sort_custom(func(a, b): return _screen_row(str(a)) < _screen_row(str(b)))
	for square_value in ordered_squares:
		var square := str(square_value)
		var data: Dictionary = sample_position[square]
		var center := _square_center(square)
		Tokens.draw_stack(
			self, center, radius, str(data.owner), data.kinds,
			square == selected_square, square == hovered_square
		)


func _draw_left_panel() -> void:
	var panel_width := maxf(210.0, board_rect.position.x - 48.0)
	var rect := Rect2(Vector2(20.0, 24.0), Vector2(panel_width - 20.0, size.y - 48.0))
	_draw_panel(rect)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(18.0, 38.0), "T3RNARY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 29, Palette.TEXT)
	draw_string(font, rect.position + Vector2(19.0, 61.0), "VECTOR TABLETOP STUDY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Palette.BRASS_LIGHT)
	draw_line(rect.position + Vector2(18.0, 76.0), Vector2(rect.end.x - 18.0, rect.position.y + 76.0), Palette.PANEL_LINE, 1.0)
	var usable_width := rect.size.x - 36.0
	var column_width := usable_width * 0.5
	var radius := minf(22.0, column_width * 0.25)
	for index in range(PIECE_ORDER.size()):
		var column := index % 2
		var row := index / 2
		var center := rect.position + Vector2(18.0 + column_width * (float(column) + 0.5), 111.0 + float(row) * 82.0)
		Tokens.draw_token(self, center, radius, "white", PIECE_ORDER[index])
		var label := _display_name(PIECE_ORDER[index])
		draw_string(font, center + Vector2(-column_width * 0.46, radius + 24.0), label, HORIZONTAL_ALIGNMENT_CENTER, column_width * 0.92, 11, Palette.TEXT_MUTED)
	draw_string(font, Vector2(rect.position.x + 18.0, rect.end.y - 54.0), "Uniform body. Distinct insignia.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 11, Palette.TEXT_MUTED)
	draw_string(font, Vector2(rect.position.x + 18.0, rect.end.y - 34.0), "No stack-height numerals.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 11, Palette.BRASS_LIGHT)


func _draw_right_panel() -> void:
	var panel_x := board_rect.end.x + 44.0
	var rect := Rect2(Vector2(panel_x, 24.0), Vector2(maxf(220.0, size.x - panel_x - 20.0), size.y - 48.0))
	_draw_panel(rect)
	var font := ThemeDB.fallback_font
	var selected: Dictionary = sample_position.get(selected_square, {})
	draw_string(font, rect.position + Vector2(18.0, 36.0), "STACK INSPECTOR", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Palette.BRASS_LIGHT)
	draw_string(font, rect.position + Vector2(18.0, 68.0), selected_square if not selected.is_empty() else "—", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Palette.TEXT)
	if selected.is_empty():
		draw_string(font, rect.position + Vector2(18.0, 100.0), "Select a stack", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Palette.TEXT_MUTED)
		return
	var kinds: Array = selected.kinds
	var owner := str(selected.owner)
	var radius := minf(34.0, rect.size.x * 0.16)
	var start_y := rect.position.y + 132.0
	for reverse_index in range(kinds.size()):
		var index := kinds.size() - 1 - reverse_index
		var center := Vector2(rect.get_center().x, start_y + float(reverse_index) * 104.0)
		Tokens.draw_token(self, center, radius, owner, str(kinds[index]), true, index == kinds.size() - 1)
		var role := "TOP" if index == kinds.size() - 1 else "BURIED"
		var label := "%s  ·  %s" % [_display_name(str(kinds[index])).to_upper(), role]
		draw_string(font, center + Vector2(-rect.size.x * 0.42, radius + 27.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x * 0.84, 11, Palette.TEXT_MUTED if role == "BURIED" else Palette.SELECTED)
	if kinds.size() > 1:
		for index in range(kinds.size() - 1):
			var y := start_y + 52.0 + float(index) * 104.0
			draw_line(Vector2(rect.get_center().x, y), Vector2(rect.get_center().x, y + 18.0), Palette.PANEL_LINE, 2.0)
	var info_y := rect.end.y - 126.0
	draw_line(Vector2(rect.position.x + 18.0, info_y - 18.0), Vector2(rect.end.x - 18.0, info_y - 18.0), Palette.PANEL_LINE, 1.0)
	draw_string(font, Vector2(rect.position.x + 18.0, info_y + 3.0), "HEIGHT %d" % kinds.size(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Palette.TEXT)
	draw_string(font, Vector2(rect.position.x + 18.0, info_y + 29.0), "Top tile controls movement", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 12, Palette.TEXT_MUTED)
	draw_string(font, Vector2(rect.position.x + 18.0, info_y + 51.0), "Click any occupied square", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 12, Palette.TEXT_MUTED)
	draw_string(font, Vector2(rect.position.x + 18.0, info_y + 73.0), "to inspect its full stack.", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 12, Palette.TEXT_MUTED)


func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.34))
	draw_rect(rect.grow(-2.0), Palette.PANEL)
	draw_rect(rect.grow(-2.0), Palette.PANEL_LINE, false, 1.0)
	draw_line(rect.position + Vector2(10.0, 8.0), Vector2(rect.end.x - 10.0, rect.position.y + 8.0), Color(Palette.BRASS, 0.55), 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var new_hover := _square_at(event.position)
		if new_hover != hovered_square:
			hovered_square = new_hover
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var square := _square_at(event.position)
		if sample_position.has(square):
			selected_square = square
			queue_redraw()


func _square_at(position: Vector2) -> String:
	if not board_rect.has_point(position):
		return ""
	var cell := board_rect.size.x / BOARD_DIMENSION
	var column := clampi(floori((position.x - board_rect.position.x) / cell), 0, 8)
	var row := clampi(floori((position.y - board_rect.position.y) / cell), 0, 8)
	return String.chr(65 + column) + str(9 - row)


func _square_center(square: String) -> Vector2:
	var column := square.unicode_at(0) - 65
	var rank := square.substr(1).to_int()
	var row := 9 - rank
	var cell := board_rect.size.x / BOARD_DIMENSION
	return board_rect.position + Vector2(float(column) + 0.5, float(row) + 0.5) * cell


func _screen_row(square: String) -> int:
	return 9 - square.substr(1).to_int()


func _display_name(kind: String) -> String:
	return Rules.piece_display_name(kind)
