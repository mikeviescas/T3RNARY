extends Node3D

const PremiumMaterials = preload("res://scripts/presentation/premium_token_materials.gd")
const TOKENS := {
	"white_infantry": preload("res://assets/poc/token_white_infantry.glb"),
	"white_marshal": preload("res://assets/poc/token_white_marshal.glb"),
	"white_sovereign": preload("res://assets/poc/token_white_sovereign.glb"),
	"black_infantry": preload("res://assets/poc/token_black_infantry.glb"),
	"black_marshal": preload("res://assets/poc/token_black_marshal.glb"),
	"black_sovereign": preload("res://assets/poc/token_black_sovereign.glb"),
}

const STACK_PITCH := 0.150
const TILE_CENTER_HEIGHT := 0.170


func _ready() -> void:
	_build_environment()
	_build_display_surface()
	_build_tile_studies()
	_build_overlay()


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("11100f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a59a8e")
	environment.ambient_light_energy = 0.44
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.68
	environment.tonemap_white = 3.0
	world.environment = environment
	add_child(world)

	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe2bb")
	key.light_energy = 0.74
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-52.0, -34.0, -18.0)
	add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-4.5, 5.5, 4.0)
	fill.light_color = Color("b8cbe0")
	fill.light_energy = 0.38
	fill.omni_range = 15.0
	fill.shadow_enabled = true
	add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color("d5e5f4")
	rim.light_energy = 0.46
	rim.shadow_enabled = false
	rim.rotation_degrees = Vector3(-38.0, 142.0, 22.0)
	add_child(rim)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.2
	camera.position = Vector3(0.0, 7.4, 8.6)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.25, 0.0), Vector3.UP)
	camera.current = true
	add_child(camera)


func _build_display_surface() -> void:
	var surface := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12.5, 0.18, 7.2)
	surface.mesh = box
	surface.position.y = -0.10
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("292623")
	material.roughness = 0.74
	box.material = material
	add_child(surface)


func _build_tile_studies() -> void:
	# Top/material pair.
	_add_tile(Vector3(-4.2, TILE_CENTER_HEIGHT, -1.8), false, "sovereign")
	_add_tile(Vector3(-3.1, TILE_CENTER_HEIGHT, -1.8), true, "sovereign")

	# Low side profile and an inverted underside study.
	var profile := _add_tile(Vector3(-3.65, TILE_CENTER_HEIGHT, 0.10), false, "infantry")
	profile.rotation_degrees.y = -18.0
	var underside := _add_tile(Vector3(-3.65, 0.55, 1.75), true, "infantry")
	underside.rotation_degrees = Vector3(180.0, 12.0, 8.0)

	# Exploded seating pair: the raised tile reveals both the crown and socket.
	_add_tile(Vector3(-0.95, TILE_CENTER_HEIGHT, -0.55), true, "infantry")
	var raised := _add_tile(Vector3(-0.95, 1.15, -0.55), false, "marshal")
	raised.rotation_degrees = Vector3(20.0, -16.0, 8.0)

	# Exact one-, two-, and three-stack pitch. At a 50/50 crown/skirt split,
	# their total heights are approximately 10, 15, and 20 mm equivalents.
	_add_stack(Vector3(1.35, TILE_CENTER_HEIGHT, 0.25), false, 1)
	_add_stack(Vector3(2.75, TILE_CENTER_HEIGHT, 0.25), false, 2)
	_add_stack(Vector3(4.25, TILE_CENTER_HEIGHT, 0.25), false, 3)

	# Horizontal roll confirms that the new profile still stores compactly.
	for index in range(7):
		var tile := _add_tile(Vector3(-0.46 + float(index) * 0.17, 0.44, 2.25), index >= 4, "infantry")
		tile.rotation_degrees.z = 90.0


func _add_stack(center: Vector3, dark: bool, height: int) -> void:
	for index in range(height):
		var kind := "marshal" if index == height - 1 else "infantry"
		var tile := _add_tile(center + Vector3(0.0, float(index) * STACK_PITCH, 0.0), dark, kind)
		tile.rotation_degrees.y = float(index * 9 - 5)


func _add_tile(position: Vector3, dark: bool, kind: String) -> Node3D:
	var key := ("black_" if dark else "white_") + kind
	var token: Node3D = (TOKENS[key] as PackedScene).instantiate()
	PremiumMaterials.apply(token)
	token.position = position
	token.name = ("Black " if dark else "White ") + kind.capitalize()
	add_child(token)
	return token


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.position = Vector2(30.0, 24.0)
	title.text = "T3RNARY · NESTING PLAY TILE STUDY"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("eee5d7"))
	layer.add_child(title)
	var subtitle := Label.new()
	subtitle.position = Vector2(31.0, 58.0)
	subtitle.text = "POLISHED MARBLE + OBSIDIAN · ENGRAVED METAL INLAY · NESTING 28:22:10 FORM"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("c9bda9"))
	layer.add_child(subtitle)
	var labels := [
		[Vector2(68, 216), "TOP / MATERIAL"],
		[Vector2(68, 500), "SIDE + UNDERSIDE"],
		[Vector2(510, 260), "EXPLODED SEAT"],
		[Vector2(850, 260), "LEGAL STACKS"],
		[Vector2(560, 740), "HORIZONTAL STORAGE"],
	]
	for entry in labels:
		var label := Label.new()
		label.position = entry[0]
		label.text = entry[1]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color("d7aa5d"))
		layer.add_child(label)
