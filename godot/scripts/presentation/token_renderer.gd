class_name TokenRenderer
extends RefCounted

const Palette = preload("res://scripts/presentation/ternary_palette.gd")
const Icons = preload("res://scripts/presentation/piece_icon_renderer.gd")

# Each buried checker exposes enough of its wall and rim to make all three
# physical layers countable without a numeric height badge.
const STACK_RISE_RATIO := 0.27


static func draw_stack(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	owner: String,
	kinds: Array,
	selected := false,
	hovered := false
) -> void:
	var count := kinds.size()
	var rise := radius * STACK_RISE_RATIO
	for index in range(count):
		var layer_center := center + Vector2(0.0, float(count - 1 - index) * rise)
		var is_top := index == count - 1
		draw_token(canvas, layer_center, radius, owner, str(kinds[index]), is_top, selected and is_top, hovered and is_top)


static func draw_token(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	owner: String,
	kind: String,
	show_icon := true,
	selected := false,
	hovered := false
) -> void:
	var lift := radius * 0.07 if hovered else 0.0
	var c := center - Vector2(0.0, lift)
	var shadow_alpha := 0.38 if not hovered else 0.50
	canvas.draw_colored_polygon(
		_ellipse(c + Vector2(radius * 0.08, radius * 0.32), Vector2(radius * 0.94, radius * 0.40)),
		Color(0.0, 0.0, 0.0, shadow_alpha)
	)
	if selected:
		canvas.draw_circle(c + Vector2(0.0, radius * 0.11), radius * 1.12, Color(Palette.SELECTED, 0.22))
		canvas.draw_arc(c, radius * 1.06, 0.0, TAU, 48, Palette.SELECTED, maxf(2.0, radius * 0.075), true)

	# Visible lower wall gives each checker physical thickness.
	canvas.draw_circle(c + Vector2(0.0, radius * 0.16), radius, Palette.token_edge(owner))
	canvas.draw_circle(c + Vector2(0.0, radius * 0.08), radius, Palette.token_body(owner).darkened(0.10))
	canvas.draw_arc(c + Vector2(0.0, radius * 0.13), radius * 0.93, 0.18, PI - 0.18, 24, Color(0.0, 0.0, 0.0, 0.34), maxf(1.0, radius * 0.055), true)
	canvas.draw_circle(c, radius, Palette.token_body(owner))
	canvas.draw_arc(c, radius * 0.91, PI * 1.08, PI * 1.92, 28, Color(1.0, 1.0, 1.0, 0.18), maxf(1.0, radius * 0.055), true)
	canvas.draw_arc(c, radius * 0.91, PI * 0.08, PI * 0.92, 28, Color(0.0, 0.0, 0.0, 0.30), maxf(1.0, radius * 0.07), true)
	canvas.draw_circle(c, radius * 0.72, Palette.token_edge(owner))
	canvas.draw_circle(c - Vector2(0.0, radius * 0.025), radius * 0.64, Palette.token_face(owner))
	canvas.draw_arc(c, radius * 0.61, PI, TAU, 24, Color(1.0, 1.0, 1.0, 0.17), maxf(1.0, radius * 0.035), true)
	if show_icon:
		Icons.draw_icon(canvas, kind, c - Vector2(0.0, radius * 0.03), radius * 0.58, Palette.token_ink(owner))


static func _ellipse(center: Vector2, radii: Vector2, segments := 36) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points
