class_name PieceIconRenderer
extends RefCounted

const DRAGOON_ICON_PATH := "res://assets/icons/dragoon.svg"
const CHARIOT_ICON_PATH := "res://assets/icons/chariot.svg"
const GRIFFIN_ICON_PATH := "res://assets/icons/griffin.svg"
const BALLISTA_ICON_PATH := "res://assets/icons/ballista.svg"

static var _svg_textures: Dictionary = {}


static func draw_icon(canvas: CanvasItem, kind: String, center: Vector2, radius: float, color: Color) -> void:
	match kind:
		"sovereign":
			_draw_sovereign(canvas, center, radius, color)
		"infantry":
			_draw_infantry(canvas, center, radius, color)
		"dragoon":
			_draw_dragoon(canvas, center, radius, color)
		"chariot":
			_draw_chariot(canvas, center, radius, color)
		"griffin":
			_draw_griffin(canvas, center, radius, color)
		"marshal":
			_draw_marshal(canvas, center, radius, color)
		"trebuchet":
			_draw_trebuchet(canvas, center, radius, color)
		"ballista":
			_draw_ballista(canvas, center, radius, color)
		"spy":
			_draw_spy(canvas, center, radius, color)
		"reinforcement":
			_draw_reinforcement(canvas, center, radius, color)
		"recall":
			_draw_recall(canvas, center, radius, color)
		_:
			canvas.draw_circle(center, radius * 0.12, color)


static func supported_kinds() -> Array[String]:
	return [
		"sovereign", "infantry", "dragoon", "chariot", "griffin", "marshal",
		"trebuchet", "ballista", "spy", "reinforcement", "recall",
	]


static func _draw_sovereign(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	# Crown, orb, and double base: a state emblem rather than a chess King.
	canvas.draw_circle(c + Vector2(0.0, -0.51) * r, r * 0.105, color)
	var crown := _points(c, r, [
		Vector2(-0.58, 0.24), Vector2(-0.50, -0.33),
		Vector2(-0.20, -0.08), Vector2(0.0, -0.42),
		Vector2(0.20, -0.08), Vector2(0.50, -0.33),
		Vector2(0.58, 0.24),
	])
	canvas.draw_colored_polygon(crown, color)
	canvas.draw_line(c + Vector2(-0.58, 0.28) * r, c + Vector2(0.58, 0.28) * r, color, r * 0.16, true)
	canvas.draw_line(c + Vector2(-0.48, 0.52) * r, c + Vector2(0.48, 0.52) * r, color, r * 0.13, true)


static func _draw_infantry(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	# Three grounded spears read as a formation rather than a single Soldier.
	for column in [-0.34, 0.0, 0.34]:
		var tip_y: float = -0.64 if is_zero_approx(column) else -0.49
		canvas.draw_line(c + Vector2(column, 0.55) * r, c + Vector2(column, tip_y + 0.15) * r, color, r * 0.105, true)
		var spearhead := _points(c, r, [
			Vector2(column, tip_y),
			Vector2(column - 0.14, tip_y + 0.22),
			Vector2(column + 0.14, tip_y + 0.22),
		])
		canvas.draw_colored_polygon(spearhead, color)
	canvas.draw_line(c + Vector2(-0.52, 0.34) * r, c + Vector2(0.52, 0.34) * r, color, r * 0.10, true)


static func _draw_dragoon(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	_draw_svg_icon(canvas, DRAGOON_ICON_PATH, c, r, color)


static func _draw_chariot(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	_draw_svg_icon(canvas, CHARIOT_ICON_PATH, c, r, color)


static func _draw_svg_icon(canvas: CanvasItem, path: String, c: Vector2, r: float, color: Color) -> void:
	var texture := _svg_texture(path)
	if texture == null:
		return
	var size := Vector2.ONE * r * 2.0
	canvas.draw_texture_rect(texture, Rect2(c - size * 0.5, size), false, color)


static func _svg_texture(path: String) -> Texture2D:
	if _svg_textures.has(path):
		return _svg_textures[path]
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		return null
	var image := Image.new()
	if image.load_svg_from_string(source, 2.0) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_svg_textures[path] = texture
	return texture


static func _draw_griffin(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	_draw_svg_icon(canvas, GRIFFIN_ICON_PATH, c, r, color)


static func _draw_marshal(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(10):
		var angle := -PI * 0.5 + index * PI / 5.0
		var length := r * (0.62 if index % 2 == 0 else 0.27)
		points.append(c + Vector2(cos(angle), sin(angle)) * length)
	canvas.draw_colored_polygon(points, color)


static func _draw_trebuchet(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var width := r * 0.12
	canvas.draw_line(c + Vector2(-0.50, 0.52) * r, c + Vector2(0.34, 0.52) * r, color, width, true)
	canvas.draw_line(c + Vector2(-0.35, 0.48) * r, c + Vector2(-0.05, -0.47) * r, color, width, true)
	canvas.draw_line(c + Vector2(0.23, 0.48) * r, c + Vector2(-0.05, -0.47) * r, color, width, true)
	canvas.draw_line(c + Vector2(-0.18, -0.34) * r, c + Vector2(0.50, -0.03) * r, color, width, true)
	canvas.draw_line(c + Vector2(0.48, -0.06) * r, c + Vector2(0.48, 0.30) * r, color, width * 0.55, true)
	canvas.draw_circle(c + Vector2(0.48, 0.38) * r, r * 0.13, color)


static func _draw_ballista(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	_draw_svg_icon(canvas, BALLISTA_ICON_PATH, c, r, color)


static func _draw_spy(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var eye := PackedVector2Array()
	for index in range(17):
		var t := float(index) / 16.0
		var x := lerpf(-0.62, 0.62, t)
		var y := -sin(t * PI) * 0.35
		eye.append(c + Vector2(x, y) * r)
	for index in range(16, -1, -1):
		var t := float(index) / 16.0
		var x := lerpf(-0.62, 0.62, t)
		var y := sin(t * PI) * 0.35
		eye.append(c + Vector2(x, y) * r)
	canvas.draw_colored_polygon(eye, color)
	canvas.draw_circle(c, r * 0.23, Color(0.5, 0.5, 0.5, 0.46))
	canvas.draw_circle(c, r * 0.105, color)


static func _draw_reinforcement(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var thickness := r * 0.22
	canvas.draw_line(c + Vector2(-0.52, 0.0) * r, c + Vector2(0.52, 0.0) * r, color, thickness, true)
	canvas.draw_line(c + Vector2(0.0, -0.52) * r, c + Vector2(0.0, 0.52) * r, color, thickness, true)
	canvas.draw_arc(c, r * 0.61, PI * 0.08, PI * 0.42, 10, color, r * 0.08, true)
	canvas.draw_arc(c, r * 0.61, PI * 0.58, PI * 0.92, 10, color, r * 0.08, true)


static func _draw_recall(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	# A single returning path around the piece being called back.
	canvas.draw_arc(c, r * 0.54, -PI * 0.72, PI * 0.78, 30, color, r * 0.12, true)
	var arrow := _points(c, r, [
		Vector2(-0.58, 0.17), Vector2(-0.69, 0.52), Vector2(-0.30, 0.43),
	])
	canvas.draw_colored_polygon(arrow, color)
	var recalled_piece := _points(c, r, [
		Vector2(0.0, -0.25), Vector2(0.24, 0.0),
		Vector2(0.0, 0.25), Vector2(-0.24, 0.0),
	])
	canvas.draw_colored_polygon(recalled_piece, color)


static func _points(center: Vector2, radius: float, normalized: Array[Vector2]) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in normalized:
		result.append(center + point * radius)
	return result
