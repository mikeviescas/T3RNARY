class_name PieceModelView
extends SubViewportContainer

const PremiumMaterials = preload("res://scripts/presentation/premium_token_materials.gd")

const MODELS := {
	"white_sovereign": preload("res://assets/poc/token_white_sovereign.glb"),
	"white_infantry": preload("res://assets/poc/token_white_infantry.glb"),
	"white_dragoon": preload("res://assets/poc/token_white_dragoon.glb"),
	"white_chariot": preload("res://assets/poc/token_white_chariot.glb"),
	"white_griffin": preload("res://assets/poc/token_white_griffin.glb"),
	"white_marshal": preload("res://assets/poc/token_white_marshal.glb"),
	"white_spy": preload("res://assets/poc/token_white_spy.glb"),
	"white_ballista": preload("res://assets/poc/token_white_ballista.glb"),
	"white_trebuchet": preload("res://assets/poc/token_white_trebuchet.glb"),
	"white_reinforcement": preload("res://assets/poc/token_white_reinforcement.glb"),
	"white_recall": preload("res://assets/poc/token_white_recall.glb"),
	"black_sovereign": preload("res://assets/poc/token_black_sovereign.glb"),
	"black_infantry": preload("res://assets/poc/token_black_infantry.glb"),
	"black_dragoon": preload("res://assets/poc/token_black_dragoon.glb"),
	"black_chariot": preload("res://assets/poc/token_black_chariot.glb"),
	"black_griffin": preload("res://assets/poc/token_black_griffin.glb"),
	"black_marshal": preload("res://assets/poc/token_black_marshal.glb"),
	"black_spy": preload("res://assets/poc/token_black_spy.glb"),
	"black_ballista": preload("res://assets/poc/token_black_ballista.glb"),
	"black_trebuchet": preload("res://assets/poc/token_black_trebuchet.glb"),
	"black_reinforcement": preload("res://assets/poc/token_black_reinforcement.glb"),
	"black_recall": preload("res://assets/poc/token_black_recall.glb"),
}

var kind := "sovereign":
	set(value):
		kind = value
		_refresh_models()

var viewport: SubViewport
var model_root: Node3D


func _ready() -> void:
	custom_minimum_size = Vector2(290.0, 150.0)
	stretch = true
	_build_preview()
	_refresh_models()


func _build_preview() -> void:
	viewport = SubViewport.new()
	viewport.name = "Current tabletop piece preview"
	viewport.size = Vector2i(580, 300)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	model_root = Node3D.new()
	viewport.add_child(model_root)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.72
	camera.position = Vector3(0.0, 3.15, 3.25)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.16, 0.0))
	viewport.add_child(camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-58.0, 138.0, 0.0)
	fill.light_color = Color("d7c3a0")
	fill.light_energy = 0.72
	viewport.add_child(fill)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.0, 0.0, 0.0, 0.0)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d9cbb5")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	viewport.add_child(environment)


func _refresh_models() -> void:
	if model_root == null:
		return
	for child in model_root.get_children():
		child.queue_free()
	for preview in [
		{"owner": "white", "x": -0.67, "turn": -10.0},
		{"owner": "black", "x": 0.67, "turn": 10.0},
	]:
		var key := "%s_%s" % [preview.owner, kind]
		if not MODELS.has(key):
			continue
		var model: Node3D = MODELS[key].instantiate()
		model.position = Vector3(float(preview.x), 0.0, 0.0)
		model.rotation_degrees.y = float(preview.turn)
		PremiumMaterials.apply(model)
		model_root.add_child(model)
