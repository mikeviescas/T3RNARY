class_name PieceEmblemView
extends Control

const EMBLEMS := {
	"sovereign": preload("res://assets/icons/sovereign_reference.svg"),
	"infantry": preload("res://assets/poc/encyclopedia_emblems/infantry.png"),
	"dragoon": preload("res://assets/poc/encyclopedia_emblems/dragoon.png"),
	"chariot": preload("res://assets/poc/encyclopedia_emblems/chariot.png"),
	"griffin": preload("res://assets/poc/encyclopedia_emblems/griffin.png"),
	"marshal": preload("res://assets/poc/encyclopedia_emblems/marshal.png"),
	"spy": preload("res://assets/poc/encyclopedia_emblems/spy.png"),
	"ballista": preload("res://assets/poc/encyclopedia_emblems/ballista.png"),
	"trebuchet": preload("res://assets/poc/encyclopedia_emblems/trebuchet.png"),
	"reinforcement": preload("res://assets/icons/reinforcement_reference.svg"),
	"recall": preload("res://assets/icons/recall_reference.svg"),
}

var kind := "sovereign":
	set(value):
		kind = value
		_refresh_texture()
		queue_redraw()

const GOLD := Color("d0aa59")
const FIELD := Color(0.055, 0.048, 0.041, 0.98)

var _texture: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(104.0, 104.0)
	resized.connect(queue_redraw)
	_refresh_texture()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.43
	var center := size * 0.5
	draw_circle(center, radius, FIELD)
	draw_arc(center, radius, 0.0, TAU, 96, GOLD, 2.0, true)
	draw_arc(center, radius * 0.83, 0.0, TAU, 96, Color(GOLD, 0.42), 1.0, true)
	if _texture != null:
		var icon_scale := 1.82 if kind == "marshal" else 1.45
		var icon_size := Vector2.ONE * radius * icon_scale
		draw_texture_rect(_texture, Rect2(center - icon_size * 0.5, icon_size), false)


func _refresh_texture() -> void:
	_texture = EMBLEMS.get(kind) as Texture2D
