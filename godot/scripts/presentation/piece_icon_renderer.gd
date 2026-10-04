class_name PieceIconRenderer
extends RefCounted


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
	var crown := _points(c, r, [
		Vector2(-0.58, 0.28), Vector2(-0.48, -0.38),
		Vector2(-0.18, -0.08), Vector2(0.0, -0.56),
		Vector2(0.18, -0.08), Vector2(0.48, -0.38),
		Vector2(0.58, 0.28),
	])
	canvas.draw_colored_polygon(crown, color)
	canvas.draw_rect(Rect2(c + Vector2(-0.56, 0.26) * r, Vector2(1.12, 0.20) * r), color)
	canvas.draw_line(c + Vector2(-0.50, 0.55) * r, c + Vector2(0.50, 0.55) * r, color, r * 0.12, true)


static func _draw_infantry(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	canvas.draw_line(c + Vector2(-0.26, 0.62) * r, c + Vector2(-0.26, -0.58) * r, color, r * 0.13, true)
	var flag := _points(c, r, [
		Vector2(-0.20, -0.54), Vector2(0.52, -0.32),
		Vector2(0.17, 0.02), Vector2(-0.20, -0.06),
	])
	canvas.draw_colored_polygon(flag, color)


static func _draw_dragoon(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var horse := _points(c, r, [
		Vector2(-0.50, 0.47), Vector2(-0.38, 0.04),
		Vector2(-0.12, -0.28), Vector2(-0.24, -0.60),
		Vector2(0.02, -0.46), Vector2(0.25, -0.62),
		Vector2(0.24, -0.30), Vector2(0.49, -0.10),
		Vector2(0.55, 0.18), Vector2(0.27, 0.28),
		Vector2(0.16, 0.07), Vector2(-0.05, 0.22),
		Vector2(0.17, 0.47),
	])
	canvas.draw_colored_polygon(horse, color)
	canvas.draw_circle(c + Vector2(0.27, -0.18) * r, r * 0.055, Color(0.08, 0.08, 0.08, 0.88))


static func _draw_chariot(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var shield := _points(c, r, [
		Vector2(0.0, -0.62), Vector2(0.53, -0.42),
		Vector2(0.45, 0.24), Vector2(0.0, 0.65),
		Vector2(-0.45, 0.24), Vector2(-0.53, -0.42),
	])
	canvas.draw_colored_polygon(shield, color)
	var inner := _points(c, r, [
		Vector2(0.0, -0.38), Vector2(0.29, -0.26),
		Vector2(0.25, 0.14), Vector2(0.0, 0.39),
		Vector2(-0.25, 0.14), Vector2(-0.29, -0.26),
	])
	canvas.draw_colored_polygon(inner, Color(0.5, 0.5, 0.5, 0.38))


static func _draw_griffin(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var wing := _points(c, r, [
		Vector2(-0.50, 0.42), Vector2(-0.45, -0.23),
		Vector2(-0.14, -0.48), Vector2(-0.02, -0.16),
		Vector2(0.18, -0.56), Vector2(0.26, -0.12),
		Vector2(0.52, -0.40), Vector2(0.42, 0.10),
		Vector2(0.12, 0.31), Vector2(0.46, 0.55),
		Vector2(-0.02, 0.48),
	])
	canvas.draw_colored_polygon(wing, color)
	canvas.draw_circle(c + Vector2(-0.26, -0.26) * r, r * 0.19, color)
	var beak := _points(c, r, [Vector2(-0.39, -0.31), Vector2(-0.67, -0.18), Vector2(-0.39, -0.10)])
	canvas.draw_colored_polygon(beak, color)


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
	var barrel := _points(c, r, [
		Vector2(-0.56, -0.25), Vector2(0.35, -0.16),
		Vector2(0.50, 0.04), Vector2(0.32, 0.22),
		Vector2(-0.56, 0.22),
	])
	canvas.draw_colored_polygon(barrel, color)
	canvas.draw_rect(Rect2(c + Vector2(-0.62, -0.32) * r, Vector2(0.18, 0.62) * r), color)
	canvas.draw_circle(c + Vector2(0.10, 0.39) * r, r * 0.23, color)
	canvas.draw_circle(c + Vector2(0.10, 0.39) * r, r * 0.09, Color(0.5, 0.5, 0.5, 0.42))


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
	for scale in [0.62, 0.41, 0.20]:
		canvas.draw_arc(c, r * scale, -PI * 0.65, PI * 1.05, 24, color, r * 0.10, true)
	var arrow := _points(c, r, [Vector2(0.33, -0.55), Vector2(0.69, -0.50), Vector2(0.50, -0.18)])
	canvas.draw_colored_polygon(arrow, color)


static func _points(center: Vector2, radius: float, normalized: Array[Vector2]) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in normalized:
		result.append(center + point * radius)
	return result
