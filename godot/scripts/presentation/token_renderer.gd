class_name TokenRenderer
extends RefCounted

const Palette = preload("res://scripts/presentation/ternary_palette.gd")
const Icons = preload("res://scripts/presentation/piece_icon_renderer.gd")

# Each buried checker exposes enough of its wall and rim to make all three
# physical layers countable without a numeric height badge.
const STACK_RISE_RATIO := 0.27
const LAYER_PINSTRIPE_WIDTH_RATIO := 0.025


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
		# Anchor the bottom checker on its square and build the stack upward.
		var layer_center := center - Vector2(0.0, float(index) * rise)
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
	if selected:
		canvas.draw_circle(c + Vector2(0.0, radius * 0.11), radius * 1.12, Color(Palette.SELECTED, 0.22))
		canvas.draw_arc(c, radius * 1.06, 0.0, TAU, 48, Palette.SELECTED, maxf(2.0, radius * 0.075), true)

	# The pinstripe is the tile's outermost material, not an overlay or a lighting
	# contour. Everything belonging to the tile is contained inside this circle.
	var pinstripe_width := maxf(1.25, radius * LAYER_PINSTRIPE_WIDTH_RATIO)
	canvas.draw_circle(c, radius, Palette.token_layer_border(owner))
	canvas.draw_circle(c, radius - pinstripe_width, Palette.token_body(owner))
	# Restrained highlights stay inside the painted edge.
	canvas.draw_arc(c, radius - pinstripe_width * 1.55, PI * 1.08, PI * 1.92, 36, Color(1.0, 1.0, 1.0, 0.14), maxf(1.0, radius * 0.025), true)
	canvas.draw_arc(c, radius - pinstripe_width * 1.55, PI * 0.08, PI * 0.92, 36, Color(0.0, 0.0, 0.0, 0.20), maxf(1.0, radius * 0.03), true)
	canvas.draw_circle(c, radius * 0.72, Palette.token_edge(owner))
	canvas.draw_circle(c - Vector2(0.0, radius * 0.025), radius * 0.64, Palette.token_face(owner))
	canvas.draw_arc(c, radius * 0.61, PI, TAU, 24, Color(1.0, 1.0, 1.0, 0.17), maxf(1.0, radius * 0.035), true)
	if show_icon:
		Icons.draw_icon(canvas, kind, c - Vector2(0.0, radius * 0.03), radius * 0.58, Palette.token_ink(owner))


static func draw_empty_token(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	owner: String
) -> void:
	# An empty reserve position keeps the physical inventory layout legible
	# without suggesting that a playable piece remains.
	var ghost := Color(Palette.token_edge(owner), 0.34)
	var inner := Color(Palette.token_face(owner), 0.08)
	canvas.draw_circle(center + Vector2(radius * 0.06, radius * 0.17), radius, Color(0.0, 0.0, 0.0, 0.16))
	canvas.draw_circle(center, radius, inner)
	canvas.draw_arc(center, radius, 0.0, TAU, 40, ghost, maxf(1.5, radius * 0.10), true)
	canvas.draw_arc(center, radius * 0.69, 0.0, TAU, 36, Color(ghost, 0.22), maxf(1.0, radius * 0.06), true)
