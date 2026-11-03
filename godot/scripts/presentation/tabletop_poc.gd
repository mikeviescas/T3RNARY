extends Node3D

const PremiumMaterials = preload("res://scripts/presentation/premium_token_materials.gd")
const Codec = preload("res://scripts/core/ternary_codec.gd")
const GameEngine = preload("res://scripts/core/ternary_engine.gd")
const Rules = preload("res://scripts/core/ternary_rules.gd")
const Session = preload("res://scripts/core/ternary_session.gd")
const TacticalWarnings = preload("res://scripts/core/ternary_tactical_warnings.gd")
const Encyclopedia = preload("res://scripts/presentation/piece_encyclopedia.gd")
const PieceEmblemView = preload("res://scripts/presentation/piece_emblem_view.gd")
const PieceMoveDiagram = preload("res://scripts/presentation/piece_move_diagram.gd")
const SOVEREIGN_REFERENCE_ICON = preload("res://assets/icons/sovereign_reference.svg")
const RESERVE_LABEL_ICONS := {
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
const TABLE_SURFACE = preload("res://assets/poc/table_surface.glb")
const BOARD = preload("res://assets/poc/board.glb")
const PLAYER_TRAY = preload("res://assets/poc/player_tray.glb")
const WHITE_TOKEN = preload("res://assets/poc/token_white.glb")
const BLACK_TOKEN = preload("res://assets/poc/token_black.glb")
const PREMIUM_TOKENS := {
	"white_infantry": preload("res://assets/poc/token_white_infantry.glb"),
	"white_dragoon": preload("res://assets/poc/token_white_dragoon.glb"),
	"white_chariot": preload("res://assets/poc/token_white_chariot.glb"),
	"white_griffin": preload("res://assets/poc/token_white_griffin.glb"),
	"white_marshal": preload("res://assets/poc/token_white_marshal.glb"),
	"white_sovereign": preload("res://assets/poc/token_white_sovereign.glb"),
	"white_trebuchet": preload("res://assets/poc/token_white_trebuchet.glb"),
	"white_ballista": preload("res://assets/poc/token_white_ballista.glb"),
	"white_spy": preload("res://assets/poc/token_white_spy.glb"),
	"white_reinforcement": preload("res://assets/poc/token_white_reinforcement.glb"),
	"white_recall": preload("res://assets/poc/token_white_recall.glb"),
	"black_infantry": preload("res://assets/poc/token_black_infantry.glb"),
	"black_dragoon": preload("res://assets/poc/token_black_dragoon.glb"),
	"black_chariot": preload("res://assets/poc/token_black_chariot.glb"),
	"black_griffin": preload("res://assets/poc/token_black_griffin.glb"),
	"black_marshal": preload("res://assets/poc/token_black_marshal.glb"),
	"black_sovereign": preload("res://assets/poc/token_black_sovereign.glb"),
	"black_trebuchet": preload("res://assets/poc/token_black_trebuchet.glb"),
	"black_ballista": preload("res://assets/poc/token_black_ballista.glb"),
	"black_spy": preload("res://assets/poc/token_black_spy.glb"),
	"black_reinforcement": preload("res://assets/poc/token_black_reinforcement.glb"),
	"black_recall": preload("res://assets/poc/token_black_recall.glb"),
}

const ICONS := {
	"infantry": "res://assets/poc/infantry.svg",
	"marshal": "res://assets/poc/marshal.svg",
	"dragoon": "res://assets/icons/dragoon.svg",
	"chariot": "res://assets/icons/chariot.svg",
	"griffin": "res://assets/icons/griffin.svg",
	"ballista": "res://assets/icons/ballista.svg",
}

var camera: Camera3D
var game_state := {}
var session
var position_root: Node3D
var marker_root: Node3D
var feedback_root: Node3D
var feedback_audio: AudioStreamPlayer
var board_stack_nodes := {}
var selected_source := ""
var selected_reserve_kind := ""
var selected_recall_kind := ""
var exploded_stack_square := ""
var candidate_actions: Array = []
var inspection_destinations: Array[String] = []
var pending_actions: Array = []
var discard_token_nodes := {Rules.WHITE: [], Rules.BLACK: []}
var expanded_discard_owner := ""
var animating := false
var interaction_status: Label3D
var interaction_surface: Control
var surface_material_cache := {}
var table_surface_node: Node3D
var white_tray_node: Node3D
var black_tray_node: Node3D
var title_panel: Control
var interaction_note: Label
var portrait_layout := false
var human_color := Rules.WHITE
var new_game_button: Button
var opponent_button: Button
var color_button: Button
var undo_button: Button
var redo_button: Button
var recall_choice_panel: VBoxContainer
var game_over_overlay: Control
var game_over_panel: PanelContainer
var game_over_headline: Label
var game_over_method: Label
var hamburger_button: Button
var hamburger_panel: PanelContainer
var notation_overlay: PanelContainer
var notation_text: TextEdit
var notation_copy_button: Button
var encyclopedia_overlay: Control
var encyclopedia_icon: Control
var encyclopedia_move_diagram: Control
var encyclopedia_name_label: Label
var encyclopedia_count_label: Label
var encyclopedia_summary_label: Label
var encyclopedia_range_heading: Label
var encyclopedia_range_table: GridContainer
var encyclopedia_piece_buttons := {}
var settings_overlay: Control
var instructional_feedback_toggle: CheckButton
var check_warning_toggle: CheckButton
var checkmate_warning_toggle: CheckButton
var blunder_warning_toggle: CheckButton
var blunder_overlay: Control
var blunder_message: Label
var pending_warning_action := {}
var tactical_warning_checksum := ""
var cached_position_warning := {}
var file_dialog: FileDialog
var replay_controls: HBoxContainer
var replay_status: Label
var replay_first_button: Button
var replay_previous_button: Button
var replay_next_button: Button
var replay_last_button: Button

var view_mode := "play"
var replay_document := {}
var replay_states: Array[Dictionary] = []
var replay_actions: Array[Dictionary] = []
var replay_index := 0
var replay_error := ""
var replay_end_method := ""
var feedback_generation := 0
var last_feedback_reason := ""
var last_instructional_message := ""

const TABLETOP_DESIGN_SIZE := Vector2(1280.0, 800.0)
const PORTRAIT_LAYOUT_THRESHOLD := 1.05
const LANDSCAPE_CAMERA_POSITION := Vector3(0.0, 18.5, 8.0)
const PORTRAIT_CAMERA_POSITION := Vector3(0.0, 23.0, 9.0)
const TRAY_OFFSET := 6.65
const TRAY_COLUMN_OFFSET := 0.58
const TRAY_INFANTRY_Z := -3.88
const TRAY_RESERVE_START_Z := -2.45
const TRAY_RESERVE_PITCH := 1.15
const TRAY_DISCARD_START_Z := 3.53
const TRAY_DISCARD_PITCH := 0.75
const ACTIVE_MOVE_MARKER := Color("9b7b43")
const INACTIVE_MOVE_MARKER := Color("74716a")
const SELECTED_STACK_MARKER := Color("aa8142")
const SHOOT_TARGET_MARKER := Color("c18f42")
const MIN_POINTER_HIT_RADIUS := 36.0
const MIN_ACTION_HIT_RADIUS := 42.0
const MIN_RESERVE_HIT_RADIUS := 42.0
const MIN_TOUCH_CONTROL_HEIGHT := 48.0
const PREFERENCES_PATH := "user://preferences.cfg"

var warn_check := true
var warn_checkmate := true
var warn_major_blunder := true
var instructional_feedback_enabled := true
var feedback_sounds := {}


func _ready() -> void:
	# Let phones and tablets follow the physical device. SCREEN_SENSOR permits
	# both portrait and landscape instead of locking the exported Android app to
	# the desktop-oriented startup dimensions.
	if DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	_build_landscape_composition()
	_build_environment()
	_build_dynamic_roots()
	_load_warning_preferences()
	_build_overlay()
	session = Session.new()
	session.name = "Game Session"
	add_child(session)
	session.state_changed.connect(_on_session_state_changed)
	session.setup_changed.connect(_on_session_setup_changed)
	session.action_committed.connect(_on_session_action_committed)
	session.ai_busy_changed.connect(_on_session_ai_busy_changed)
	session.session_error.connect(_update_interaction_status)
	var automated_test := _is_automated_test_run()
	session.autosave_enabled = not automated_test
	if session.restore_autosave():
		human_color = Rules.opponent(session.ai_player)
	else:
		# A normal launch should be immediately playable: the computer takes
		# Black's setup and turns while the local player begins as White. Keep
		# deterministic UI tests in hot-seat mode so they can drive both sides.
		session.configure_opponent(not automated_test, human_color, false)
		session.start_new_game()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_update_interaction_status()
	set_process_input(true)


func _is_automated_test_run() -> bool:
	for argument in OS.get_cmdline_args():
		if "/tests/" in argument or argument.ends_with("tests.gd"):
			return true
	return false


func _build_dynamic_roots() -> void:
	position_root = Node3D.new()
	position_root.name = "Rules-driven pieces"
	add_child(position_root)
	marker_root = Node3D.new()
	marker_root.name = "Legal action markers"
	add_child(marker_root)
	feedback_root = Node3D.new()
	feedback_root.name = "Instructional feedback"
	add_child(feedback_root)
	feedback_audio = AudioStreamPlayer.new()
	feedback_audio.name = "Gameplay feedback audio"
	feedback_audio.max_polyphony = 4
	add_child(feedback_audio)


func _build_landscape_composition() -> void:
	var composition := Node3D.new()
	composition.name = "Landscape Composition"
	add_child(composition)

	table_surface_node = TABLE_SURFACE.instantiate()
	table_surface_node.name = "Table Surface"
	composition.add_child(table_surface_node)
	_apply_surface_studies(table_surface_node)

	var board := BOARD.instantiate()
	board.name = "Board"
	composition.add_child(board)
	_apply_surface_studies(board)
	_build_status_plate(composition)

	white_tray_node = PLAYER_TRAY.instantiate()
	white_tray_node.name = "White Player Tray"
	white_tray_node.position.x = -TRAY_OFFSET
	composition.add_child(white_tray_node)
	_apply_surface_studies(white_tray_node)

	black_tray_node = PLAYER_TRAY.instantiate()
	black_tray_node.name = "Black Player Tray"
	black_tray_node.position.x = TRAY_OFFSET
	composition.add_child(black_tray_node)
	_apply_surface_studies(black_tray_node)


func _build_status_plate(parent: Node3D) -> void:
	var plate_root := Node3D.new()
	plate_root.name = "Polished turn-status inlay"
	parent.add_child(plate_root)

	var inlay_material := StandardMaterial3D.new()
	inlay_material.albedo_color = Color("e0cf9f")
	inlay_material.metallic = 0.62
	inlay_material.roughness = 0.08
	inlay_material.clearcoat_enabled = true
	inlay_material.clearcoat_roughness = 0.04

	var center := MeshInstance3D.new()
	center.name = "Polished metal inlay center"
	var center_mesh := BoxMesh.new()
	center_mesh.size = Vector3(3.92, 0.075, 0.54)
	center.mesh = center_mesh
	center.position = Vector3(0.0, 0.655, 5.10)
	center.material_override = inlay_material
	plate_root.add_child(center)
	for x in [-1.96, 1.96]:
		var end_cap := MeshInstance3D.new()
		end_cap.name = "Oval inlay end"
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = 0.27
		cap_mesh.bottom_radius = 0.27
		cap_mesh.height = 0.075
		cap_mesh.radial_segments = 48
		end_cap.mesh = cap_mesh
		end_cap.position = Vector3(x, 0.655, 5.10)
		end_cap.material_override = inlay_material
		plate_root.add_child(end_cap)

	interaction_status = Label3D.new()
	interaction_status.name = "Engraved turn inscription"
	interaction_status.position = Vector3(0.0, 0.706, 5.10)
	interaction_status.rotation_degrees.x = -90.0
	interaction_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interaction_status.font_size = 34
	interaction_status.pixel_size = 0.0070
	interaction_status.modulate = Color("171512")
	interaction_status.outline_size = 0
	interaction_status.no_depth_test = false
	plate_root.add_child(interaction_status)


func _apply_surface_studies(root: Node) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface_index)
			if source == null:
				continue
			var material_name := source.resource_name.to_lower()
			var mesh_name := mesh_instance.name.to_lower()
			var cache_key := material_name
			if "neutral field metal border" in mesh_name:
				cache_key = "neutral field metal border"
			if surface_material_cache.has(cache_key):
				mesh_instance.set_surface_override_material(surface_index, surface_material_cache[cache_key])
				continue
			var replacement: Material
			if "neutral field metal border" in mesh_name:
				replacement = _neutral_inlay_material()
			elif "velvet" in material_name or "leather" in material_name:
				replacement = _velvet_material()
			elif "aged brass" in material_name:
				replacement = _brass_material()
			elif "faded maple" in material_name:
				replacement = _wood_material(Color("866344"), Color("b18a60"), 0.57, 1.16, 0.62, 1.15)
			elif "maple" in material_name:
				replacement = _wood_material(Color("9a6b35"), Color("d0a76b"), 0.54, 1.25, 1.0, 1.17)
			elif "faded walnut" in material_name:
				replacement = _wood_material(Color("624633"), Color("8b6a50"), 0.59, 1.16, 0.62, 1.18)
			elif "walnut square" in material_name:
				replacement = _wood_material(Color("2c160d"), Color("5a3520"), 0.55, 1.35, 1.0, 1.24)
			elif "walnut tabletop" in material_name:
				replacement = _wood_material(Color("1c0904"), Color("48210f"), 0.48, 0.58, 1.0, 1.14)
			elif "walnut frame" in material_name:
				replacement = _wood_material(Color("170704"), Color("3d160a"), 0.42, 0.82, 1.0, 1.18)
			elif "warm frame" in material_name:
				replacement = _wood_material(Color("351207"), Color("6c2b11"), 0.46, 0.92, 1.0, 1.16)
			if replacement != null:
				surface_material_cache[cache_key] = replacement
				mesh_instance.set_surface_override_material(surface_index, replacement)


func _brass_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b77a29")
	material.metallic = 0.58
	material.roughness = 0.27
	return material


func _neutral_inlay_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("332d29")
	material.metallic = 0.68
	material.roughness = 0.25
	return material


func _wood_material(dark_color: Color, light_color: Color, roughness: float, scale: float, grain_contrast: float = 1.0, brightness: float = 1.0) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 dark_color : source_color;
uniform vec3 light_color : source_color;
uniform float surface_roughness = 0.5;
uniform float grain_scale = 1.0;
uniform float grain_contrast = 1.0;
uniform float surface_brightness = 1.0;
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz * grain_scale;
	float broad = value_noise(p * vec2(0.33, 2.6));
	float warp = value_noise(p * vec2(0.72, 5.0)) * 4.2;
	float fiber = 0.5 + 0.5 * sin((p.x + warp) * 22.0);
	float fine = value_noise(p * vec2(5.0, 42.0));
	float pattern = clamp(broad * 0.52 + fiber * 0.27 + fine * 0.21, 0.0, 1.0);
	pattern = 0.5 + (pattern - 0.5) * grain_contrast;
	ALBEDO = mix(dark_color, light_color, pattern) * surface_brightness;
	ROUGHNESS = clamp(surface_roughness + (fine - 0.5) * 0.12, 0.25, 0.85);
	SPECULAR = 0.32;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("dark_color", Vector3(dark_color.r, dark_color.g, dark_color.b))
	material.set_shader_parameter("light_color", Vector3(light_color.r, light_color.g, light_color.b))
	material.set_shader_parameter("surface_roughness", roughness)
	material.set_shader_parameter("grain_scale", scale)
	material.set_shader_parameter("grain_contrast", grain_contrast)
	material.set_shader_parameter("surface_brightness", brightness)
	return material


func _velvet_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 45758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_position.xz * 92.0);
	float nap = hash(cell);
	float grazing = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.2);
	vec3 velvet_black = mix(vec3(0.007, 0.006, 0.0055), vec3(0.032, 0.027, 0.024), nap * 0.52);
	ALBEDO = velvet_black + vec3(0.052, 0.042, 0.037) * grazing;
	ROUGHNESS = 0.89 + nap * 0.08;
	SPECULAR = 0.12;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("160b06")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("826f5e")
	environment.ambient_light_energy = 0.18
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.72
	environment.tonemap_white = 3.2
	world.environment = environment
	add_child(world)

	var key := DirectionalLight3D.new()
	key.name = "Warm key light"
	key.light_color = Color("ffd7a2")
	key.light_energy = 0.86
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 30.0
	key.rotation_degrees = Vector3(-54.0, -28.0, -18.0)
	add_child(key)

	var fill := OmniLight3D.new()
	fill.name = "Soft fill light"
	fill.position = Vector3(-6.5, 7.0, 2.5)
	fill.light_color = Color("aac4dd")
	fill.light_energy = 0.34
	fill.omni_range = 18.0
	fill.shadow_enabled = true
	add_child(fill)

	var warm_edge := OmniLight3D.new()
	warm_edge.name = "Warm table light"
	warm_edge.position = Vector3(7.0, 4.0, -5.0)
	warm_edge.light_color = Color("e99a54")
	warm_edge.light_energy = 0.28
	warm_edge.omni_range = 14.0
	add_child(warm_edge)

	camera = Camera3D.new()
	camera.name = "Responsive perspective tabletop camera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 36.0
	camera.position = LANDSCAPE_CAMERA_POSITION
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.15, 0.0), Vector3.UP)
	camera.current = true
	add_child(camera)


func _on_viewport_size_changed() -> void:
	if camera == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# The square project viewport expands to the real window shape. Prefer the
	# platform window dimensions as an additional guard against mobile stretch
	# transforms reporting the desktop design aspect during rotation.
	var window_size := DisplayServer.window_get_size()
	var viewport_aspect := viewport_size.x / viewport_size.y
	if window_size.x > 0 and window_size.y > 0:
		viewport_aspect = float(window_size.x) / float(window_size.y)
	var wants_portrait := viewport_aspect < PORTRAIT_LAYOUT_THRESHOLD
	_set_portrait_layout(wants_portrait)
	_configure_perspective_camera(viewport_aspect)
	_apply_overlay_layout()
	call_deferred("_position_replay_controls_on_plate")


func _set_portrait_layout(enabled: bool) -> void:
	if enabled == portrait_layout:
		return
	portrait_layout = enabled
	_apply_tabletop_layout()
	# Reserve and discard pieces are presentation nodes positioned independently
	# from the tray meshes. They must be rebuilt during Sovereign setup too;
	# checking game_state here left the furniture in portrait orientation while
	# every loose piece remained at its landscape coordinates.
	if session != null:
		_render_game_state()


func _configure_perspective_camera(viewport_aspect: float) -> void:
	var target := Vector3(0.0, 0.15, 0.0)
	var composition_half_width: float
	var composition_half_height: float
	if portrait_layout:
		camera.position = PORTRAIT_CAMERA_POSITION
		composition_half_width = 5.05
		composition_half_height = 7.85
	else:
		camera.position = LANDSCAPE_CAMERA_POSITION
		composition_half_width = 8.75
		composition_half_height = 5.20
	camera.look_at_from_position(camera.position, target, Vector3.UP)
	var distance := camera.position.distance_to(target)
	var required_vertical_half_span := maxf(
		composition_half_height,
		composition_half_width / maxf(viewport_aspect, 0.1),
	)
	# A small breathing margin keeps the nearest raised tray and token edges out
	# of the crop while retaining clear perspective convergence.
	camera.fov = rad_to_deg(2.0 * atan((required_vertical_half_span * 1.025) / distance))


func _apply_tabletop_layout() -> void:
	if table_surface_node == null or white_tray_node == null or black_tray_node == null:
		return
	if portrait_layout:
		table_surface_node.rotation_degrees.y = 90.0
		white_tray_node.position = Vector3(0.0, 0.0, TRAY_OFFSET)
		black_tray_node.position = Vector3(0.0, 0.0, -TRAY_OFFSET)
		white_tray_node.rotation_degrees.y = 90.0
		black_tray_node.rotation_degrees.y = 90.0
	else:
		table_surface_node.rotation_degrees.y = 0.0
		white_tray_node.position = Vector3(-TRAY_OFFSET, 0.0, 0.0)
		black_tray_node.position = Vector3(TRAY_OFFSET, 0.0, 0.0)
		white_tray_node.rotation_degrees.y = 0.0
		black_tray_node.rotation_degrees.y = 0.0
	if title_panel != null:
		title_panel.visible = not portrait_layout
	if interaction_note != null:
		interaction_note.visible = not portrait_layout


func _render_game_state() -> void:
	for child in position_root.get_children():
		child.queue_free()
	board_stack_nodes.clear()
	discard_token_nodes = {Rules.WHITE: [], Rules.BLACK: []}
	exploded_stack_square = ""
	expanded_discard_owner = ""
	var board: Dictionary = session.setup_board() if game_state.is_empty() and session != null else game_state.get("board", {})
	var artillery_facings := _current_artillery_facings()
	for square_value in board:
		var square := str(square_value)
		var stack: Array = board[square]
		var kinds: Array = []
		for piece in stack:
			kinds.append(str(piece.kind))
		board_stack_nodes[square] = _add_stack(
			_square_position(square),
			str(stack[-1].owner) == "black",
			kinds,
			square,
			artillery_facings.get(square, []),
		)
	if game_state.is_empty():
		var white_reserve := Rules.starting_inventory()
		var black_reserve := Rules.starting_inventory()
		if session != null and session.setup_white_file >= 0:
			white_reserve[Rules.SOVEREIGN] -= 1
		if session != null and session.setup_black_file >= 0:
			black_reserve[Rules.SOVEREIGN] -= 1
		_add_reserve_caddy(white_reserve, Rules.WHITE, false)
		_add_reserve_caddy(black_reserve, Rules.BLACK, true)
		_add_discard_inventory(Rules.empty_inventory(), Rules.WHITE, false)
		_add_discard_inventory(Rules.empty_inventory(), Rules.BLACK, true)
	else:
		_add_reserve_caddy(game_state.reserves.white, "white", false)
		_add_reserve_caddy(game_state.reserves.black, "black", true)
		_add_discard_inventory(game_state.discards.white, "white", false)
		_add_discard_inventory(game_state.discards.black, "black", true)


func _square_position(square: String) -> Vector3:
	var file_index := square.unicode_at(0) - "A".unicode_at(0)
	var rank := int(square.substr(1))
	return Vector3(float(file_index - 4), 0.42, float(5 - rank))


func _add_stack(position: Vector3, dark: bool, kinds: Array, square := "", facings: Array = []) -> Node3D:
	var stack_root := Node3D.new()
	stack_root.name = ("Black" if dark else "White") + " stack " + square
	stack_root.position = position
	position_root.add_child(stack_root)
	for index in range(kinds.size()):
		var kind := str(kinds[index])
		var token := _new_token(dark, kind)
		token.position = Vector3(0.0, float(index) * 0.150, 0.0)
		if kind in [Rules.BALLISTA, Rules.TREBUCHET]:
			token.rotation_degrees.y = float(facings[index]) if index < facings.size() and facings[index] != null else 0.0
		else:
			token.rotation_degrees.y = float(index * 7 - 4)
		token.set_meta("piece_kind", kind)
		token.set_meta("stack_index", index)
		stack_root.add_child(token)
	# One physical click target represents the complete game unit. Individual
	# imported token meshes never participate in picking.
	var hit_area := Area3D.new()
	hit_area.name = "Complete stack hit area"
	hit_area.collision_layer = 1
	hit_area.collision_mask = 0
	hit_area.monitoring = false
	hit_area.monitorable = true
	hit_area.set_meta("board_square", square)
	var hit_shape := CollisionShape3D.new()
	hit_shape.name = "Stack hit shape"
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.43
	var sovereign_piece := kinds.size() == 1 and str(kinds[0]) == Rules.SOVEREIGN
	cylinder.height = 0.68 if sovereign_piece else 0.42 + float(kinds.size() - 1) * 0.150
	hit_shape.shape = cylinder
	hit_shape.position.y = 0.15 if sovereign_piece else 0.08 + float(kinds.size() - 1) * 0.075
	hit_area.add_child(hit_shape)
	stack_root.add_child(hit_area)
	return stack_root


func _current_artillery_facings() -> Dictionary:
	if game_state.is_empty():
		return {}
	var states_source: Array = []
	var actions_source: Array = []
	var action_count := 0
	if view_mode == "replay" and not replay_states.is_empty():
		states_source = replay_states
		actions_source = replay_actions
		action_count = mini(replay_index, replay_actions.size())
	elif session != null and not session.states.is_empty():
		states_source = session.states
		actions_source = session.actions
		action_count = session.actions.size()
	if states_source.is_empty():
		return {}
	var facings := {}
	for square_value in states_source[0].get("board", {}):
		var square := str(square_value)
		facings[square] = _empty_facing_array(states_source[0].board[square].size())
	for index in range(action_count):
		if index + 1 >= states_source.size():
			break
		facings = _advance_artillery_facings(
			facings,
			states_source[index],
			actions_source[index],
			states_source[index + 1],
		)
	return facings


func _empty_facing_array(size: int) -> Array:
	var values: Array = []
	values.resize(size)
	values.fill(null)
	return values


func _advance_artillery_facings(previous: Dictionary, before: Dictionary, action: Dictionary, after: Dictionary) -> Dictionary:
	var result := previous.duplicate(true)
	var after_board: Dictionary = after.get("board", {})
	for square_value in result.keys():
		if not after_board.has(str(square_value)):
			result.erase(square_value)
	for square_value in after_board:
		var square := str(square_value)
		if not result.has(square):
			result[square] = _empty_facing_array(after_board[square].size())

	var action_type := str(action.get("type", ""))
	if action_type == "move":
		var source := str(action.get("source", ""))
		var destination := str(action.get("destination", ""))
		var moving_stack: Array = before.board.get(source, [])
		var source_facings: Array = previous.get(source, _empty_facing_array(moving_stack.size()))
		var destination_stack: Array = before.board.get(destination, [])
		var destination_facings: Array = previous.get(destination, _empty_facing_array(destination_stack.size()))
		result.erase(source)
		if not after_board.has(destination):
			result.erase(destination)
		elif not moving_stack.is_empty() and str(after_board[destination][-1].owner) == str(moving_stack[-1].owner):
			result[destination] = source_facings.duplicate()
		else:
			result[destination] = destination_facings.slice(mini(moving_stack.size(), destination_facings.size()))
	else:
		var destination := str(action.get("destination", ""))
		var kind := str(action.get("piece", ""))
		var existing_stack: Array = before.board.get(destination, [])
		var existing_facings: Array = previous.get(destination, _empty_facing_array(existing_stack.size()))
		var placed_facings: Array = []
		if kind == Rules.REINFORCEMENT:
			placed_facings = [null]
			placed_facings.append_array(existing_facings)
		elif kind == Rules.SPY and not existing_stack.is_empty() and str(existing_stack[-1].owner) != str(before.turn):
			placed_facings = _empty_facing_array(after_board.get(destination, []).size())
		else:
			placed_facings = existing_facings.duplicate()
			placed_facings.append(null)
		result[destination] = placed_facings
		var effect_target = action.get("effect_target")
		if effect_target != null:
			var target := str(effect_target)
			var old_target: Array = before.board.get(target, [])
			var old_target_facings: Array = previous.get(target, _empty_facing_array(old_target.size()))
			if after_board.has(target):
				var removed_count := maxi(0, old_target.size() - after_board[target].size())
				result[target] = old_target_facings.slice(removed_count)
			else:
				result.erase(target)
			if kind in [Rules.BALLISTA, Rules.TREBUCHET] and result.has(destination) and not result[destination].is_empty():
				result[destination][-1] = _artillery_rotation(kind, destination, target)

	# Keep the presentation arrays aligned even for retired replay contracts.
	for square_value in after_board:
		var square := str(square_value)
		var expected_size: int = after_board[square].size()
		var aligned: Array = result.get(square, [])
		if aligned.size() > expected_size:
			aligned = aligned.slice(aligned.size() - expected_size)
		elif aligned.size() < expected_size:
			aligned.append_array(_empty_facing_array(expected_size - aligned.size()))
		result[square] = aligned
	return result


func _artillery_rotation(kind: String, source: String, target: String) -> float:
	var source_xy := Rules.square_to_xy(source)
	var target_xy := Rules.square_to_xy(target)
	var dx := float(target_xy.x - source_xy.x)
	var dz := float(source_xy.y - target_xy.y)
	var shot_angle := rad_to_deg(atan2(dx, -dz))
	# The Ballista artwork points toward the board's far edge at zero rotation.
	# The Trebuchet artwork is intentionally drawn 45 degrees counter-clockwise,
	# so compensate for that built-in diagonal before aiming the complete tile.
	return shot_angle + (45.0 if kind == Rules.TREBUCHET else 0.0)


func _tray_local_to_world(local_x: float, height: float, local_z: float, owner: String) -> Vector3:
	if portrait_layout:
		var tray_z := TRAY_OFFSET if owner == "white" else -TRAY_OFFSET
		return Vector3(local_z, height, tray_z - local_x)
	var tray_x := -TRAY_OFFSET if owner == "white" else TRAY_OFFSET
	return Vector3(tray_x + local_x, height, local_z)


func _tray_world_to_local(point: Vector3, owner: String) -> Vector2:
	if portrait_layout:
		var tray_z := TRAY_OFFSET if owner == "white" else -TRAY_OFFSET
		return Vector2(tray_z - point.z, point.x)
	var tray_x := -TRAY_OFFSET if owner == "white" else TRAY_OFFSET
	return Vector2(point.x - tray_x, point.z)


func _rolled_token_rotation() -> Vector3:
	return Vector3(90.0, 0.0, 0.0) if portrait_layout else Vector3(0.0, 0.0, 90.0)


func _add_infantry_roll(owner: String, dark: bool, count: int) -> void:
	var spacing := 0.135
	for index in range(count):
		var token := _new_token(dark, "infantry")
		token.set_meta("reserve_owner", owner)
		token.set_meta("reserve_kind", "infantry")
		var centered_index := float(index) - float(count - 1) * 0.5
		token.position = _tray_local_to_world(centered_index * spacing, 0.51, TRAY_INFANTRY_Z, owner)
		token.rotation_degrees = _rolled_token_rotation()
		position_root.add_child(token)


func _add_discard_inventory(inventory: Dictionary, owner: String, dark: bool) -> void:
	var kinds: Array[String] = []
	for kind in ["infantry", "dragoon", "chariot", "griffin", "marshal", "trebuchet", "ballista", "spy", "reinforcement", "recall", "sovereign"]:
		for _copy in range(int(inventory.get(kind, 0))):
			kinds.append(kind)
	var spacing := 0.135
	for index in range(kinds.size()):
		var token := _new_token(dark, kinds[index])
		var row := index / 9
		var column := index % 9
		var row_start := row * 9
		var row_count := mini(9, kinds.size() - row_start)
		var centered_column := float(column) - float(row_count - 1) * 0.5
		token.position = _tray_local_to_world(centered_column * spacing, 0.51, TRAY_DISCARD_START_Z + float(row) * TRAY_DISCARD_PITCH, owner)
		token.rotation_degrees = _rolled_token_rotation()
		token.set_meta("discard_owner", owner)
		token.set_meta("discard_index", index)
		token.set_meta("discard_home_position", token.position)
		token.set_meta("discard_home_rotation", token.rotation_degrees)
		position_root.add_child(token)
		discard_token_nodes[owner].append(token)


func _add_reserve_caddy(inventory: Dictionary, owner: String, dark: bool) -> void:
	_add_reserve_emblems(owner, dark)
	_add_infantry_roll(owner, dark, int(inventory.get("infantry", 0)))
	var kinds := [
		"sovereign", "marshal", "dragoon", "chariot", "griffin",
		"spy", "trebuchet", "ballista", "reinforcement", "recall",
	]
	for index in range(kinds.size()):
		var kind: String = kinds[index]
		var column := index % 2
		var row := index / 2
		var local_x := -TRAY_COLUMN_OFFSET if column == 0 else TRAY_COLUMN_OFFSET
		var local_z := TRAY_RESERVE_START_Z + float(row) * TRAY_RESERVE_PITCH
		for stack_index in range(int(inventory.get(kind, 0))):
			var token := _new_token(dark, kind)
			token.set_meta("reserve_owner", owner)
			token.set_meta("reserve_kind", kind)
			token.position = _tray_local_to_world(local_x, 0.32 + float(stack_index) * 0.150, local_z, owner)
			token.rotation_degrees.y = float(stack_index * 6 - 3)
			position_root.add_child(token)


func _add_reserve_emblems(owner: String, dark: bool) -> void:
	var kinds := [
		"sovereign", "marshal", "dragoon", "chariot", "griffin",
		"spy", "trebuchet", "ballista", "reinforcement", "recall",
	]
	var grey_base := StandardMaterial3D.new()
	grey_base.albedo_color = Color("77736c") if not dark else Color("4d5054")
	grey_base.roughness = 0.72
	var grey_mark := StandardMaterial3D.new()
	grey_mark.albedo_color = Color("373a3e") if not dark else Color("b3afa6")
	grey_mark.roughness = 0.60
	var sovereign_gold := StandardMaterial3D.new()
	sovereign_gold.albedo_color = Color("b98a32")
	sovereign_gold.metallic = 0.42
	sovereign_gold.roughness = 0.44
	var sovereign_mark := StandardMaterial3D.new()
	# Unlike the ordinary reserve labels, the Sovereign crown identifies its
	# owner directly: dark crown in Black's tray, ivory crown in White's tray.
	sovereign_mark.albedo_color = Color("1c1d20") if dark else Color("f0e6d4")
	sovereign_mark.roughness = 0.52
	for index in range(kinds.size()):
		var column := index % 2
		var row := index / 2
		var kind: String = kinds[index]
		var emblem := _new_flat_reserve_emblem(
			kind,
			sovereign_gold if kind == "sovereign" else grey_base,
			sovereign_mark if kind == "sovereign" else grey_mark,
		)
		emblem.name = ("Black" if dark else "White") + " reserve emblem " + kind
		emblem.set_meta("reserve_emblem", true)
		emblem.position = _tray_local_to_world(
			-TRAY_COLUMN_OFFSET if column == 0 else TRAY_COLUMN_OFFSET,
			0.135,
			TRAY_RESERVE_START_Z + float(row) * TRAY_RESERVE_PITCH,
			owner,
		)
		emblem.scale = Vector3(0.72, 1.0, 0.72)
		position_root.add_child(emblem)


func _new_flat_reserve_emblem(kind: String, base: Material, mark: Material) -> Node3D:
	# Tray labels are graphic inlays, not miniature playing pieces. A single
	# thin circular field and an unshaded logo keep every label completely flat.
	var root := Node3D.new()
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.48
	cylinder.bottom_radius = 0.48
	cylinder.height = 0.012
	cylinder.radial_segments = 48
	disc.mesh = cylinder
	disc.material_override = base
	root.add_child(disc)
	# Print a simple contrasting circle around ordinary tile marks. The
	# Sovereign crown remains unframed so its distinctive profile stands alone.
	if kind != "sovereign":
		var ring := MeshInstance3D.new()
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = 0.405
		ring_mesh.bottom_radius = 0.405
		ring_mesh.height = 0.002
		ring_mesh.radial_segments = 48
		ring.mesh = ring_mesh
		ring.position.y = 0.007
		ring.material_override = mark
		root.add_child(ring)
		var ring_field := MeshInstance3D.new()
		var ring_field_mesh := CylinderMesh.new()
		ring_field_mesh.top_radius = 0.365
		ring_field_mesh.bottom_radius = 0.365
		ring_field_mesh.height = 0.002
		ring_field_mesh.radial_segments = 48
		ring_field.mesh = ring_field_mesh
		ring_field.position.y = 0.009
		ring_field.material_override = base
		root.add_child(ring_field)
	var logo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var logo_size := 0.62 if kind == "sovereign" else 0.76 if kind == "marshal" else 0.54
	quad.size = Vector2(logo_size, logo_size)
	logo.mesh = quad
	logo.position.y = 0.011
	logo.rotation_degrees.x = -90.0
	var logo_material := StandardMaterial3D.new()
	logo_material.albedo_color = mark.albedo_color if mark is StandardMaterial3D else Color("373a3e")
	logo_material.albedo_texture = RESERVE_LABEL_ICONS.get(kind, RESERVE_LABEL_ICONS.infantry)
	logo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	logo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	logo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	logo.material_override = logo_material
	root.add_child(logo)
	return root


func _apply_emblem_material(root: Node, base: Material, mark: Material, sovereign: bool) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var object_name := mesh_instance.name.to_lower()
			# Material names cannot identify emblem roles: the inverse Spy and
			# artillery fields and their logos are both enamel. Geometry names do
			# distinguish the tile body/field from every ring and piece mark.
			var is_mark := (
				"nesting bottle-cap body" not in object_name
				and "opposite-color stack-count inlay" not in object_name
				and "recessed engraved field" not in object_name
			)
			if sovereign:
				is_mark = "crown relief" in object_name or "crown base" in object_name
			mesh_instance.set_surface_override_material(surface_index, mark if is_mark else base)


func _new_token(dark: bool, kind: String) -> Node3D:
	var premium_key := ("black_" if dark else "white_") + kind
	var has_engraved_model := PREMIUM_TOKENS.has(premium_key)
	var token_scene: PackedScene = PREMIUM_TOKENS[premium_key] if has_engraved_model else (BLACK_TOKEN if dark else WHITE_TOKEN)
	var token: Node3D = token_scene.instantiate()
	token.name = ("Black " if dark else "White ") + kind.capitalize()
	PremiumMaterials.apply(token)
	if has_engraved_model:
		return token
	var icon_texture: Texture2D = load(str(ICONS.get(kind, ICONS.infantry)))
	var icon_quad := MeshInstance3D.new()
	icon_quad.name = "Engraved icon study"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.43, 0.43)
	icon_quad.mesh = quad
	var icon_material := StandardMaterial3D.new()
	icon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	icon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	icon_material.albedo_texture = icon_texture
	icon_material.albedo_color = Color("efe3cc") if dark else Color("24282d")
	icon_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	icon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = icon_material
	icon_quad.position = Vector3(0.0, 0.180, 0.0)
	icon_quad.rotation_degrees.x = -90.0
	token.add_child(icon_quad)
	return token


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	interaction_surface = Control.new()
	interaction_surface.name = "Tabletop click surface"
	interaction_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(interaction_surface)
	interaction_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interaction_surface.gui_input.connect(_on_tabletop_gui_input)
	hamburger_button = Button.new()
	hamburger_button.name = "Tabletop menu button"
	hamburger_button.text = "☰"
	hamburger_button.position = Vector2(24.0, 22.0)
	hamburger_button.size = Vector2(58.0, 58.0)
	hamburger_button.custom_minimum_size = Vector2(58.0, 58.0)
	hamburger_button.add_theme_font_size_override("font_size", 28)
	hamburger_button.pressed.connect(_toggle_hamburger)
	layer.add_child(hamburger_button)
	title_panel = ColorRect.new()
	title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.position = Vector2(92.0, 22.0)
	title_panel.size = Vector2(154.0, 58.0)
	title_panel.color = Color(0.035, 0.033, 0.030, 0.86)
	layer.add_child(title_panel)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.position = Vector2(16.0, 16.0)
	title.text = "T3RNARY"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("ead9ba"))
	title_panel.add_child(title)
	hamburger_panel = PanelContainer.new()
	hamburger_panel.name = "Tabletop menu"
	hamburger_panel.position = Vector2(24.0, 90.0)
	hamburger_panel.custom_minimum_size = Vector2(260.0, 0.0)
	hamburger_panel.visible = false
	layer.add_child(hamburger_panel)
	var menu_style := StyleBoxFlat.new()
	menu_style.bg_color = Color(0.035, 0.030, 0.025, 0.97)
	menu_style.border_color = Color("8d7040")
	menu_style.set_border_width_all(1)
	menu_style.set_corner_radius_all(5)
	menu_style.content_margin_left = 12.0
	menu_style.content_margin_right = 12.0
	menu_style.content_margin_top = 12.0
	menu_style.content_margin_bottom = 12.0
	hamburger_panel.add_theme_stylebox_override("panel", menu_style)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 7)
	hamburger_panel.add_child(controls)
	new_game_button = Button.new()
	new_game_button.text = "NEW GAME"
	new_game_button.pressed.connect(_start_new_game)
	_style_touch_button(new_game_button)
	controls.add_child(new_game_button)
	var replay_button := Button.new()
	replay_button.text = "OPEN REPLAY…"
	replay_button.pressed.connect(_open_replay_dialog)
	_style_touch_button(replay_button)
	controls.add_child(replay_button)
	var notation_button := Button.new()
	notation_button.text = "GAME NOTATION"
	notation_button.pressed.connect(_toggle_notation_overlay)
	_style_touch_button(notation_button)
	controls.add_child(notation_button)
	var encyclopedia_button := Button.new()
	encyclopedia_button.text = "TILE INDEX"
	encyclopedia_button.pressed.connect(_toggle_encyclopedia_overlay)
	_style_touch_button(encyclopedia_button)
	controls.add_child(encyclopedia_button)
	var settings_button := Button.new()
	settings_button.text = "SETTINGS"
	settings_button.pressed.connect(_toggle_settings_overlay)
	_style_touch_button(settings_button)
	controls.add_child(settings_button)
	var history_controls := HBoxContainer.new()
	history_controls.add_theme_constant_override("separation", 7)
	controls.add_child(history_controls)
	undo_button = Button.new()
	undo_button.text = "UNDO"
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_button.pressed.connect(_undo_state)
	_style_touch_button(undo_button)
	history_controls.add_child(undo_button)
	redo_button = Button.new()
	redo_button.text = "REDO"
	redo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redo_button.pressed.connect(_redo_state)
	_style_touch_button(redo_button)
	history_controls.add_child(redo_button)
	opponent_button = Button.new()
	opponent_button.pressed.connect(_toggle_opponent)
	_style_touch_button(opponent_button)
	controls.add_child(opponent_button)
	color_button = Button.new()
	color_button.pressed.connect(_toggle_human_color)
	_style_touch_button(color_button)
	controls.add_child(color_button)
	replay_controls = HBoxContainer.new()
	replay_controls.name = "Replay controls"
	replay_controls.custom_minimum_size = Vector2(340.0, MIN_TOUCH_CONTROL_HEIGHT)
	replay_controls.size = Vector2(340.0, MIN_TOUCH_CONTROL_HEIGHT)
	replay_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	replay_controls.add_theme_constant_override("separation", 3)
	replay_controls.visible = false
	layer.add_child(replay_controls)
	replay_first_button = Button.new()
	replay_first_button.text = "|◀"
	_style_plate_replay_button(replay_first_button)
	replay_first_button.pressed.connect(_set_replay_index.bind(0))
	replay_controls.add_child(replay_first_button)
	replay_previous_button = Button.new()
	replay_previous_button.text = "◀"
	_style_plate_replay_button(replay_previous_button)
	replay_previous_button.pressed.connect(_step_replay.bind(-1))
	replay_controls.add_child(replay_previous_button)
	replay_status = Label.new()
	replay_status.custom_minimum_size = Vector2(92.0, MIN_TOUCH_CONTROL_HEIGHT)
	replay_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	replay_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	replay_status.add_theme_font_size_override("font_size", 18)
	replay_status.add_theme_color_override("font_color", Color("171512"))
	replay_controls.add_child(replay_status)
	replay_next_button = Button.new()
	replay_next_button.text = "▶"
	_style_plate_replay_button(replay_next_button)
	replay_next_button.pressed.connect(_step_replay.bind(1))
	replay_controls.add_child(replay_next_button)
	replay_last_button = Button.new()
	replay_last_button.text = "▶|"
	_style_plate_replay_button(replay_last_button)
	replay_last_button.pressed.connect(_go_to_replay_end)
	replay_controls.add_child(replay_last_button)
	recall_choice_panel = VBoxContainer.new()
	recall_choice_panel.position = Vector2(24.0, 184.0)
	recall_choice_panel.visible = false
	recall_choice_panel.add_theme_constant_override("separation", 5)
	layer.add_child(recall_choice_panel)
	_build_notation_overlay(layer)
	_build_encyclopedia_overlay(layer)
	_build_settings_overlay(layer)
	_build_blunder_overlay(layer)
	_build_file_dialog()
	_build_game_over_overlay(layer)
	_update_session_control_labels()
	_apply_overlay_layout()


func _style_touch_button(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, MIN_TOUCH_CONTROL_HEIGHT)
	button.add_theme_font_size_override("font_size", 17)


func _style_encyclopedia_tab(button: Button) -> void:
	# Tile Index navigation is a dense list rather than a primary game control.
	# Keep it comfortably tappable while fitting more entries before scrolling.
	button.custom_minimum_size.y = 40.0
	button.add_theme_font_size_override("font_size", 14)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.075, 0.068, 0.061, 0.94)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 8.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.12, 0.10, 0.075, 0.98)
	var selected := normal.duplicate() as StyleBoxFlat
	selected.bg_color = Color(0.22, 0.17, 0.09, 0.98)
	selected.border_color = Color("c49a4e")
	selected.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("hover_pressed", selected)
	button.add_theme_color_override("font_pressed_color", Color("d0aa59"))
	button.add_theme_color_override("font_hover_pressed_color", Color("d0aa59"))


func _style_plate_replay_button(button: Button) -> void:
	button.flat = true
	button.custom_minimum_size = Vector2(48.0, MIN_TOUCH_CONTROL_HEIGHT)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("171512"))
	button.add_theme_color_override("font_hover_color", Color("4e3518"))
	button.add_theme_color_override("font_pressed_color", Color("0b0907"))
	button.add_theme_color_override("font_disabled_color", Color(0.09, 0.08, 0.07, 0.34))


func _position_replay_controls_on_plate() -> void:
	if replay_controls == null or camera == null or interaction_status == null:
		return
	var plate_center := camera.unproject_position(interaction_status.global_position)
	replay_controls.position = plate_center - Vector2(replay_controls.size.x * 0.5, replay_controls.size.y * 0.5)


func _build_notation_overlay(layer: CanvasLayer) -> void:
	notation_overlay = PanelContainer.new()
	notation_overlay.name = "Game notation overlay"
	notation_overlay.set_anchor(SIDE_LEFT, 0.58)
	notation_overlay.set_anchor(SIDE_TOP, 0.14)
	notation_overlay.set_anchor(SIDE_RIGHT, 0.97)
	notation_overlay.set_anchor(SIDE_BOTTOM, 0.92)
	notation_overlay.visible = false
	notation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(notation_overlay)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.022, 0.020, 0.97)
	style.border_color = Color("9b7a42")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	notation_overlay.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	notation_overlay.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var heading := Label.new()
	heading.text = "GAME NOTATION"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("d0aa59"))
	header.add_child(heading)
	notation_copy_button = Button.new()
	notation_copy_button.text = "COPY"
	notation_copy_button.pressed.connect(_copy_notation_to_clipboard)
	_style_touch_button(notation_copy_button)
	header.add_child(notation_copy_button)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.pressed.connect(_toggle_notation_overlay)
	close_button.custom_minimum_size = Vector2(MIN_TOUCH_CONTROL_HEIGHT, MIN_TOUCH_CONTROL_HEIGHT)
	close_button.add_theme_font_size_override("font_size", 22)
	header.add_child(close_button)
	notation_text = TextEdit.new()
	notation_text.editable = false
	notation_text.selecting_enabled = true
	notation_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notation_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	notation_text.add_theme_font_size_override("font_size", 14)
	notation_text.add_theme_color_override("font_color", Color("e8dfd1"))
	content.add_child(notation_text)


func _overlay_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.022, 0.020, 0.98)
	style.border_color = Color("9b7a42")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style


func _build_encyclopedia_overlay(layer: CanvasLayer) -> void:
	encyclopedia_overlay = Control.new()
	encyclopedia_overlay.name = "Piece encyclopedia"
	encyclopedia_overlay.visible = false
	encyclopedia_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	encyclopedia_overlay.clip_contents = true
	layer.add_child(encyclopedia_overlay)
	var encyclopedia_panel := Panel.new()
	encyclopedia_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	encyclopedia_panel.offset_left = 1.0
	encyclopedia_panel.offset_top = 1.0
	encyclopedia_panel.offset_right = -1.0
	encyclopedia_panel.offset_bottom = -1.0
	encyclopedia_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	encyclopedia_panel.add_theme_stylebox_override("panel", _overlay_panel_style())
	encyclopedia_overlay.add_child(encyclopedia_panel)
	var content_margin := MarginContainer.new()
	content_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_margin.add_theme_constant_override("margin_left", 18)
	content_margin.add_theme_constant_override("margin_right", 18)
	content_margin.add_theme_constant_override("margin_top", 16)
	content_margin.add_theme_constant_override("margin_bottom", 16)
	encyclopedia_panel.add_child(content_margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content_margin.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var heading := Label.new()
	heading.text = "TILE INDEX"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", Color("d0aa59"))
	header.add_child(heading)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(MIN_TOUCH_CONTROL_HEIGHT, MIN_TOUCH_CONTROL_HEIGHT)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(_toggle_encyclopedia_overlay)
	header.add_child(close_button)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	var body_view := ScrollContainer.new()
	body_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(body_view)
	body_view.add_child(body)
	var piece_scroll := ScrollContainer.new()
	piece_scroll.custom_minimum_size.x = 172.0
	piece_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(piece_scroll)
	var piece_list := VBoxContainer.new()
	piece_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	piece_list.add_theme_constant_override("separation", 3)
	piece_scroll.add_child(piece_list)
	var piece_tab_group := ButtonGroup.new()
	for kind_value in Encyclopedia.kinds():
		var kind := str(kind_value)
		var piece_button := Button.new()
		piece_button.text = Rules.piece_display_name(kind)
		piece_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		piece_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		piece_button.toggle_mode = true
		piece_button.button_group = piece_tab_group
		piece_button.pressed.connect(_show_encyclopedia_piece.bind(kind))
		_style_encyclopedia_tab(piece_button)
		piece_list.add_child(piece_button)
		encyclopedia_piece_buttons[kind] = piece_button
	var detail_column := VBoxContainer.new()
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_theme_constant_override("separation", 10)
	body.add_child(detail_column)
	encyclopedia_name_label = Label.new()
	encyclopedia_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	encyclopedia_name_label.add_theme_font_size_override("font_size", 27)
	encyclopedia_name_label.add_theme_color_override("font_color", Color("ead9ba"))
	detail_column.add_child(encyclopedia_name_label)
	var detail_body := HBoxContainer.new()
	detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_body.add_theme_constant_override("separation", 12)
	detail_column.add_child(detail_body)
	var visual_column := VBoxContainer.new()
	visual_column.custom_minimum_size.x = 220.0
	visual_column.alignment = BoxContainer.ALIGNMENT_CENTER
	visual_column.add_theme_constant_override("separation", 6)
	detail_body.add_child(visual_column)
	encyclopedia_icon = PieceEmblemView.new()
	encyclopedia_icon.custom_minimum_size = Vector2(104.0, 104.0)
	encyclopedia_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	visual_column.add_child(encyclopedia_icon)
	encyclopedia_move_diagram = PieceMoveDiagram.new()
	encyclopedia_move_diagram.custom_minimum_size = Vector2(220.0, 210.0)
	encyclopedia_move_diagram.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	visual_column.add_child(encyclopedia_move_diagram)
	var information_column := VBoxContainer.new()
	information_column.custom_minimum_size.x = 310.0
	information_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	information_column.add_theme_constant_override("separation", 10)
	detail_body.add_child(information_column)
	encyclopedia_count_label = Label.new()
	encyclopedia_count_label.add_theme_font_size_override("font_size", 16)
	encyclopedia_count_label.add_theme_color_override("font_color", Color("d0aa59"))
	information_column.add_child(encyclopedia_count_label)
	encyclopedia_summary_label = Label.new()
	encyclopedia_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	encyclopedia_summary_label.add_theme_font_size_override("font_size", 16)
	encyclopedia_summary_label.add_theme_color_override("font_color", Color("e8dfd1"))
	information_column.add_child(encyclopedia_summary_label)
	encyclopedia_range_heading = Label.new()
	encyclopedia_range_heading.text = "Stack Height / Range:"
	encyclopedia_range_heading.add_theme_font_size_override("font_size", 16)
	encyclopedia_range_heading.add_theme_color_override("font_color", Color("ead9ba"))
	information_column.add_child(encyclopedia_range_heading)
	encyclopedia_range_table = GridContainer.new()
	encyclopedia_range_table.columns = 2
	encyclopedia_range_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encyclopedia_range_table.add_theme_constant_override("h_separation", 0)
	encyclopedia_range_table.add_theme_constant_override("v_separation", 0)
	var range_table_margin := MarginContainer.new()
	range_table_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Preserve a visible gutter between the table's ruled edge and the outer
	# encyclopedia frame, even when the information column consumes all of the
	# remaining horizontal space.
	range_table_margin.add_theme_constant_override("margin_right", 24)
	range_table_margin.add_child(encyclopedia_range_table)
	information_column.add_child(range_table_margin)
	_show_encyclopedia_piece(Rules.SOVEREIGN)


func _show_encyclopedia_piece(kind: String) -> void:
	var entry := Encyclopedia.entry(kind)
	for button_kind in encyclopedia_piece_buttons:
		var piece_button := encyclopedia_piece_buttons[button_kind] as Button
		piece_button.button_pressed = str(button_kind) == kind
	encyclopedia_icon.kind = kind
	encyclopedia_move_diagram.kind = kind
	encyclopedia_name_label.text = "%s (%s)" % [str(entry.name), str(entry.notation)]
	encyclopedia_count_label.text = "Count - %d" % int(entry.count)
	encyclopedia_summary_label.text = str(entry.summary)
	for child in encyclopedia_range_table.get_children():
		encyclopedia_range_table.remove_child(child)
		child.queue_free()
	var ranges: Array = entry.get("ranges", [])
	encyclopedia_range_heading.visible = not ranges.is_empty()
	encyclopedia_range_table.visible = not ranges.is_empty()
	if not ranges.is_empty():
		encyclopedia_range_heading.text = str(entry.get("range_heading", "Stack Height / Range:"))
		_add_encyclopedia_range_cell("STACK HEIGHT", true)
		_add_encyclopedia_range_cell(str(entry.get("range_column", "RANGE")), true)
		for range_value in ranges:
			var row: Array = range_value
			_add_encyclopedia_range_cell(str(row[0]), false)
			_add_encyclopedia_range_cell(str(row[1]), false)


func _add_encyclopedia_range_cell(text: String, heading: bool) -> void:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.14, 0.10, 0.90) if heading else Color(0.07, 0.06, 0.05, 0.84)
	style.border_color = Color(0.58, 0.44, 0.25, 0.90)
	style.set_border_width_all(1)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	cell.add_theme_stylebox_override("panel", style)
	# The information column contracts substantially on phones and smaller
	# desktop windows. Keep only a compact first-column minimum and let both
	# columns share the available width instead of forcing the table past the
	# overlay's right edge.
	cell.custom_minimum_size.x = 92.0 if encyclopedia_range_table.get_child_count() % 2 == 0 else 150.0
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13 if heading else 14)
	label.add_theme_color_override("font_color", Color("b99045") if heading else Color("e8dfd1"))
	cell.add_child(label)
	encyclopedia_range_table.add_child(cell)


func _build_settings_overlay(layer: CanvasLayer) -> void:
	settings_overlay = Control.new()
	settings_overlay.name = "Settings"
	settings_overlay.visible = false
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.clip_contents = true
	layer.add_child(settings_overlay)
	var settings_panel := PanelContainer.new()
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.offset_left = 1.0
	settings_panel.offset_top = 1.0
	settings_panel.offset_right = -1.0
	settings_panel.offset_bottom = -1.0
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_panel.add_theme_stylebox_override("panel", _overlay_panel_style())
	settings_overlay.add_child(settings_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	settings_panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var heading := Label.new()
	heading.text = "SETTINGS"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", Color("d0aa59"))
	header.add_child(heading)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(MIN_TOUCH_CONTROL_HEIGHT, MIN_TOUCH_CONTROL_HEIGHT)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(_toggle_settings_overlay)
	header.add_child(close_button)
	var section_scroll := ScrollContainer.new()
	section_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(section_scroll)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 10)
	section_scroll.add_child(sections)
	var gameplay_heading := Label.new()
	gameplay_heading.text = "GAMEPLAY"
	gameplay_heading.add_theme_font_size_override("font_size", 17)
	gameplay_heading.add_theme_color_override("font_color", Color("ead9ba"))
	sections.add_child(gameplay_heading)
	instructional_feedback_toggle = _add_instructional_setting(
		sections,
		"Explain rejected actions and highlight the relevant play area",
		instructional_feedback_enabled,
	)
	var instructional_definition := Label.new()
	instructional_definition.text = "Valid animations remain active when instructional feedback is off."
	instructional_definition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructional_definition.add_theme_color_override("font_color", Color("918a80"))
	sections.add_child(instructional_definition)
	var tactical_heading := Label.new()
	tactical_heading.text = "TACTICAL WARNINGS"
	tactical_heading.add_theme_font_size_override("font_size", 17)
	tactical_heading.add_theme_color_override("font_color", Color("ead9ba"))
	sections.add_child(tactical_heading)
	var explanation := Label.new()
	explanation.text = "These are optional coaching aids. T3RNARY does not make CHECK a move restriction."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_color_override("font_color", Color("bdb3a5"))
	sections.add_child(explanation)
	check_warning_toggle = _add_warning_setting(sections, "Show CHECK when a Sovereign is immediately capturable", warn_check, "check")
	checkmate_warning_toggle = _add_warning_setting(sections, "Show CHECKMATE danger when no safe reply exists", warn_checkmate, "checkmate")
	blunder_warning_toggle = _add_warning_setting(sections, "Confirm major blunders before playing them", warn_major_blunder, "blunder")
	var definition := Label.new()
	definition.text = "Major blunder currently means: leaving your Sovereign open to immediate capture when a safe legal action exists."
	definition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	definition.add_theme_color_override("font_color", Color("918a80"))
	sections.add_child(definition)


func _add_instructional_setting(parent: Control, text: String, enabled: bool) -> CheckButton:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = MIN_TOUCH_CONTROL_HEIGHT
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = enabled
	toggle.custom_minimum_size = Vector2(MIN_TOUCH_CONTROL_HEIGHT, MIN_TOUCH_CONTROL_HEIGHT)
	toggle.toggled.connect(_on_instructional_feedback_changed)
	row.add_child(toggle)
	return toggle


func _add_warning_setting(parent: Control, text: String, enabled: bool, setting: String) -> CheckButton:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = MIN_TOUCH_CONTROL_HEIGHT
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = enabled
	toggle.custom_minimum_size = Vector2(MIN_TOUCH_CONTROL_HEIGHT, MIN_TOUCH_CONTROL_HEIGHT)
	toggle.toggled.connect(_on_warning_setting_changed.bind(setting))
	row.add_child(toggle)
	return toggle


func _build_blunder_overlay(layer: CanvasLayer) -> void:
	blunder_overlay = Control.new()
	blunder_overlay.name = "Major blunder confirmation"
	blunder_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blunder_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	blunder_overlay.visible = false
	layer.add_child(blunder_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.008, 0.006, 0.60)
	blunder_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blunder_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(470.0, 210.0)
	panel.add_theme_stylebox_override("panel", _overlay_panel_style())
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = "MAJOR BLUNDER?"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", Color("d0aa59"))
	content.add_child(heading)
	blunder_message = Label.new()
	blunder_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blunder_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blunder_message.text = "This leaves your Sovereign open to immediate capture."
	content.add_child(blunder_message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(150.0, MIN_TOUCH_CONTROL_HEIGHT)
	cancel.pressed.connect(_cancel_blunder_action)
	actions.add_child(cancel)
	var proceed := Button.new()
	proceed.text = "PLAY ANYWAY"
	proceed.custom_minimum_size = Vector2(170.0, MIN_TOUCH_CONTROL_HEIGHT)
	proceed.pressed.connect(_confirm_blunder_action)
	actions.add_child(proceed)


func _build_file_dialog() -> void:
	if is_instance_valid(file_dialog):
		return
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.display_mode = FileDialog.DISPLAY_LIST
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.json ; T3RNARY replay"])
	file_dialog.title = "Open T3RNARY Replay"
	var replay_dir := ProjectSettings.globalize_path("res://../research/replays")
	if DirAccess.dir_exists_absolute(replay_dir):
		file_dialog.current_dir = replay_dir
	file_dialog.file_selected.connect(_load_replay)
	add_child(file_dialog)


func _build_game_over_overlay(layer: CanvasLayer) -> void:
	game_over_overlay = Control.new()
	game_over_overlay.name = "Game over overlay"
	game_over_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_overlay.visible = false
	layer.add_child(game_over_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.008, 0.006, 0.58)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_over_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.add_child(center)
	game_over_panel = PanelContainer.new()
	game_over_panel.custom_minimum_size = Vector2(480.0, 190.0)
	center.add_child(game_over_panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.030, 0.025, 0.97)
	panel_style.border_color = Color("b99045")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 34.0
	panel_style.content_margin_right = 34.0
	panel_style.content_margin_top = 26.0
	panel_style.content_margin_bottom = 24.0
	game_over_panel.add_theme_stylebox_override("panel", panel_style)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 10)
	game_over_panel.add_child(content)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(close_row)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "Review the finished game"
	close_button.flat = true
	close_button.custom_minimum_size = Vector2(MIN_TOUCH_CONTROL_HEIGHT, MIN_TOUCH_CONTROL_HEIGHT)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(_enter_completed_game_replay)
	close_row.add_child(close_button)
	game_over_headline = Label.new()
	game_over_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_headline.add_theme_font_size_override("font_size", 32)
	game_over_headline.add_theme_color_override("font_color", Color("f0e6d2"))
	content.add_child(game_over_headline)
	game_over_method = Label.new()
	game_over_method.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_method.add_theme_font_size_override("font_size", 16)
	game_over_method.add_theme_color_override("font_color", Color("d0aa59"))
	content.add_child(game_over_method)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	var review_game := Button.new()
	review_game.text = "REVIEW GAME"
	review_game.custom_minimum_size = Vector2(160.0, MIN_TOUCH_CONTROL_HEIGHT)
	review_game.pressed.connect(_enter_completed_game_replay)
	actions.add_child(review_game)
	var new_game := Button.new()
	new_game.text = "NEW GAME"
	new_game.custom_minimum_size = Vector2(160.0, MIN_TOUCH_CONTROL_HEIGHT)
	new_game.pressed.connect(_start_new_game)
	actions.add_child(new_game)


func _safe_viewport_rect() -> Rect2:
	var viewport_size := get_viewport().get_visible_rect().size
	var fallback := Rect2(Vector2.ZERO, viewport_size)
	var safe_pixels := Rect2(DisplayServer.get_display_safe_area())
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_size := Vector2(DisplayServer.screen_get_size(screen_index))
	if safe_pixels.size.x <= 0.0 or safe_pixels.size.y <= 0.0 or screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return fallback
	var scale := Vector2(viewport_size.x / screen_size.x, viewport_size.y / screen_size.y)
	var safe_rect := Rect2(safe_pixels.position * scale, safe_pixels.size * scale)
	# Desktop safe-area APIs describe the monitor rather than the window. Their
	# scaled result is the complete viewport, while phones retain notch/inset
	# margins in the same coordinate space as this CanvasLayer.
	return safe_rect.intersection(fallback)


func _apply_overlay_layout() -> void:
	if hamburger_button == null:
		return
	var safe := _safe_viewport_rect()
	var edge := 14.0
	hamburger_button.position = safe.position + Vector2(edge, edge)
	if title_panel != null:
		title_panel.position = Vector2(hamburger_button.position.x + hamburger_button.size.x + 10.0, hamburger_button.position.y)
	if hamburger_panel != null:
		hamburger_panel.position = Vector2(hamburger_button.position.x, hamburger_button.position.y + hamburger_button.size.y + 8.0)
		hamburger_panel.custom_minimum_size.x = minf(300.0, maxf(220.0, safe.size.x - edge * 2.0))
	if recall_choice_panel != null:
		recall_choice_panel.position = Vector2(hamburger_button.position.x, hamburger_button.position.y + hamburger_button.size.y + 8.0)
	if notation_overlay != null:
		notation_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		if portrait_layout:
			notation_overlay.position = safe.position + Vector2(edge, edge)
			notation_overlay.size = safe.size - Vector2(edge * 2.0, edge * 2.0)
		else:
			var overlay_width := minf(520.0, safe.size.x * 0.42)
			notation_overlay.position = Vector2(safe.end.x - overlay_width - edge, safe.position.y + edge)
			notation_overlay.size = Vector2(overlay_width, safe.size.y - edge * 2.0)
	if encyclopedia_overlay != null:
		encyclopedia_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var encyclopedia_width := minf(820.0, safe.size.x - edge * 2.0)
		var encyclopedia_height := minf(500.0, safe.size.y - edge * 2.0)
		encyclopedia_overlay.position = safe.position + (safe.size - Vector2(encyclopedia_width, encyclopedia_height)) * 0.5
		encyclopedia_overlay.size = Vector2(encyclopedia_width, encyclopedia_height)
	if settings_overlay != null:
		settings_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var settings_width := minf(820.0, safe.size.x - edge * 2.0)
		var settings_height := minf(420.0, safe.size.y - edge * 2.0)
		settings_overlay.position = safe.position + (safe.size - Vector2(settings_width, settings_height)) * 0.5
		settings_overlay.size = Vector2(settings_width, settings_height)
	if game_over_panel != null:
		game_over_panel.custom_minimum_size.x = minf(480.0, maxf(280.0, safe.size.x - edge * 2.0))


func _update_game_over_overlay() -> void:
	if game_over_overlay == null:
		return
	var complete := view_mode == "play" and not game_state.is_empty() and GameEngine.is_over(game_state)
	game_over_overlay.visible = complete
	if not complete:
		return
	if bool(game_state.get("is_draw", false)):
		game_over_headline.text = "DRAW"
	else:
		game_over_headline.text = "%s VICTORY" % str(game_state.get("winner", "")).to_upper()
	var method := str(session.end_method) if session != null else ""
	game_over_method.text = method if not method.is_empty() else "GAME COMPLETE"


func _enter_completed_game_replay() -> void:
	if session == null or session.initial_state.is_empty() or not GameEngine.is_over(session.game_state):
		return
	var completed_document: Dictionary = session.replay_document()
	if not _load_replay_document(completed_document):
		return
	# A just-finished game should open where the player left it. Rebuild the
	# replay through the shared codec, then present its final state immediately
	# without replaying every animation on the way there.
	replay_index = maxi(0, replay_states.size() - 1)
	game_state = replay_states[replay_index].duplicate(true)
	_clear_selection()
	_render_game_state()
	game_over_overlay.visible = false
	_update_replay_controls()
	_update_session_control_labels()
	_update_interaction_status()
	_refresh_notation_overlay()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_dismiss_topmost_ui()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		var mode := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN
			else DisplayServer.WINDOW_MODE_FULLSCREEN
		)
		get_viewport().set_input_as_handled()
		return
	if view_mode == "replay" and event is InputEventKey and event.pressed:
		if event.keycode == KEY_LEFT:
			_step_replay(-1)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_RIGHT:
			_step_replay(1)
			get_viewport().set_input_as_handled()
			return
	if _gameplay_input_locked():
		return
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_Z and event.shift_pressed:
			_redo_state()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Z:
			_undo_state()
			get_viewport().set_input_as_handled()
			return


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		_handle_mobile_back_request()
	elif what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		if session != null:
			session.save_autosave()


func _handle_mobile_back_request() -> void:
	# Android Back unwinds the same visible layers as Escape. At the bare
	# tabletop it opens the game menu instead of silently terminating an active
	# match, where New Game and other session controls are available.
	if not _dismiss_topmost_ui():
		if hamburger_panel != null:
			hamburger_panel.visible = true


func _dismiss_topmost_ui() -> bool:
	if game_over_overlay != null and game_over_overlay.visible:
		_enter_completed_game_replay()
		return true
	if notation_overlay != null and notation_overlay.visible:
		notation_overlay.visible = false
		return true
	if encyclopedia_overlay != null and encyclopedia_overlay.visible:
		encyclopedia_overlay.visible = false
		return true
	if settings_overlay != null and settings_overlay.visible:
		settings_overlay.visible = false
		return true
	if blunder_overlay != null and blunder_overlay.visible:
		_cancel_blunder_action()
		return true
	if recall_choice_panel != null and recall_choice_panel.visible:
		_hide_recall_choices()
		_clear_selection()
		return true
	if hamburger_panel != null and hamburger_panel.visible:
		hamburger_panel.visible = false
		return true
	if not selected_source.is_empty() or not selected_reserve_kind.is_empty() or not expanded_discard_owner.is_empty():
		_clear_selection()
		_collapse_discard_explosion()
		return true
	return false


func _on_tabletop_gui_input(event: InputEvent) -> void:
	if _is_primary_pointer_press(event):
		if hamburger_panel != null and hamburger_panel.visible:
			hamburger_panel.visible = false
			interaction_surface.accept_event()
			return
	if _gameplay_input_locked() and view_mode != "replay":
		interaction_surface.accept_event()
		return
	if _is_primary_pointer_press(event):
		_handle_pointer_click(_pointer_event_position(event))
		interaction_surface.accept_event()


func _is_primary_pointer_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed


func _pointer_event_position(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		return event.position
	if event is InputEventMouseButton:
		return event.position
	return Vector2.ZERO


func _handle_pointer_click(screen_position: Vector2) -> void:
	# On a touch screen, interpret taps near visible legal markers before doing a
	# literal 3D ray hit. This makes small phone targets forgiving without ever
	# snapping a move to a square that is not currently legal.
	var action_square := _action_square_at_screen(screen_position)
	if not action_square.is_empty():
		_handle_board_click(action_square)
		return
	var stack_square := _stack_square_from_physics(screen_position)
	if stack_square.is_empty():
		stack_square = _stack_square_at_screen(screen_position)
	if not stack_square.is_empty():
		_handle_board_click(stack_square)
		return
	var reserve_kind := _reserve_kind_at_screen(screen_position)
	if not reserve_kind.is_empty():
		_select_reserve(reserve_kind)
		return
	var world_point = _world_point_from_screen(screen_position)
	if world_point != null:
		_handle_world_click(world_point)


func _action_square_at_screen(screen_position: Vector2) -> String:
	var legal_squares: Array[String] = []
	if not pending_actions.is_empty():
		for action in pending_actions:
			var destination := str(action.get("destination", ""))
			if not destination.is_empty() and not legal_squares.has(destination):
				legal_squares.append(destination)
			var effect_target := str(action.get("effect_target", ""))
			if not effect_target.is_empty() and not legal_squares.has(effect_target):
				legal_squares.append(effect_target)
	elif not candidate_actions.is_empty():
		for action in candidate_actions:
			var destination := str(action.get("destination", ""))
			if not destination.is_empty() and not legal_squares.has(destination):
				legal_squares.append(destination)
	elif game_state.is_empty() and selected_reserve_kind == Rules.SOVEREIGN and session != null:
		var rank := 9 if session.setup_black_file < 0 else 1
		for file_index in range(9):
			legal_squares.append("%s%d" % [char("A".unicode_at(0) + file_index), rank])
	return _nearest_square_at_screen(screen_position, legal_squares, MIN_ACTION_HIT_RADIUS)


func _nearest_square_at_screen(screen_position: Vector2, squares: Array[String], minimum_radius: float) -> String:
	var closest_square := ""
	var closest_distance := INF
	for square in squares:
		var anchor := _square_position(square) + Vector3(0.0, 0.05, 0.0)
		var projected := camera.unproject_position(anchor)
		var projected_edge := camera.unproject_position(anchor + Vector3(0.48, 0.0, 0.0))
		var hit_radius := maxf(minimum_radius, projected.distance_to(projected_edge) * 0.82)
		var distance := projected.distance_to(screen_position)
		if distance <= hit_radius and distance < closest_distance:
			closest_square = square
			closest_distance = distance
	return closest_square


func _reserve_kind_at_screen(screen_position: Vector2) -> String:
	if session == null:
		return ""
	var owner := Rules.BLACK if game_state.is_empty() and session.setup_black_file < 0 else Rules.WHITE
	var kinds: Array[String] = []
	if game_state.is_empty():
		kinds.append(Rules.SOVEREIGN)
	else:
		kinds.assign([
			Rules.INFANTRY, Rules.SOVEREIGN, Rules.MARSHAL, Rules.DRAGOON, Rules.CHARIOT,
			Rules.GRIFFIN, Rules.SPY, Rules.TREBUCHET, Rules.BALLISTA, Rules.REINFORCEMENT,
			Rules.RECALL,
		])
	if not game_state.is_empty():
		owner = str(game_state.turn)
	var closest_kind := ""
	var closest_distance := INF
	for kind in kinds:
		if not game_state.is_empty() and int(game_state.reserves[owner].get(kind, 0)) <= 0:
			continue
		var anchor := _reserve_world_position(kind, owner)
		anchor.y += 0.20
		var projected := camera.unproject_position(anchor)
		var projected_edge := camera.unproject_position(anchor + Vector3(0.50, 0.0, 0.0))
		var hit_radius := maxf(MIN_RESERVE_HIT_RADIUS, projected.distance_to(projected_edge))
		var distance := projected.distance_to(screen_position)
		if distance <= hit_radius and distance < closest_distance:
			closest_kind = kind
			closest_distance = distance
	return closest_kind


func _stack_square_from_physics(screen_position: Vector2) -> String:
	if not is_inside_tree() or get_world_3d() == null:
		return ""
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 40.0, 1)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var collider = hit.get("collider")
	if collider is Area3D and collider.has_meta("board_square"):
		return str(collider.get_meta("board_square"))
	return ""


func _stack_square_at_screen(screen_position: Vector2) -> String:
	var closest_square := ""
	var closest_distance := INF
	var board: Dictionary = (
		session.setup_board()
		if game_state.is_empty() and session != null
		else game_state.get("board", {})
	)
	for square_value in board:
		var square := str(square_value)
		var stack: Array = board[square]
		var anchor := _square_position(square)
		anchor.y += (
			0.44
			if stack.size() == 1 and str(stack[-1].kind) == Rules.SOVEREIGN
			else float(stack.size() - 1) * 0.150 + 0.180
		)
		var projected := camera.unproject_position(anchor)
		var projected_edge := camera.unproject_position(anchor + Vector3(0.48, 0.0, 0.0))
		var hit_radius := maxf(MIN_POINTER_HIT_RADIUS, projected.distance_to(projected_edge))
		var distance := projected.distance_to(screen_position)
		if distance <= hit_radius and distance < closest_distance:
			closest_square = square
			closest_distance = distance
	return closest_square


func _world_point_from_screen(screen_position: Vector2):
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	return Plane(Vector3.UP, 0.34).intersects_ray(ray_origin, ray_direction)


func _handle_world_click(point: Vector3) -> void:
	var square := _square_at_world_point(point)
	if not square.is_empty():
		_collapse_discard_explosion()
		_handle_board_click(square)
		return
	var discard_owner := _discard_owner_at_world_point(point)
	if not discard_owner.is_empty():
		_toggle_discard_explosion(discard_owner)
		return
	_collapse_discard_explosion()
	if view_mode == "replay":
		_clear_selection()
		return
	var reserve_kind := _reserve_kind_at_world_point(point)
	if not reserve_kind.is_empty():
		_select_reserve(reserve_kind)
		return
	_clear_selection()


func _discard_owner_at_world_point(point: Vector3) -> String:
	var owner := (
		(Rules.WHITE if point.z > 0.0 else Rules.BLACK)
		if portrait_layout
		else (Rules.WHITE if point.x < 0.0 else Rules.BLACK)
	)
	var local_point := _tray_world_to_local(point, owner)
	if abs(local_point.x) > 1.48:
		return ""
	if local_point.y < TRAY_DISCARD_START_Z - 0.48 or local_point.y > TRAY_DISCARD_START_Z + TRAY_DISCARD_PITCH + 0.48:
		return ""
	return owner


func _square_at_world_point(point: Vector3) -> String:
	if point.x < -4.5 or point.x >= 4.5 or point.z < -4.5 or point.z >= 4.5:
		return ""
	var file_index := int(floor(point.x + 4.5))
	var rank := 9 - int(floor(point.z + 4.5))
	return "%s%d" % [char("A".unicode_at(0) + file_index), rank]


func _reserve_kind_at_world_point(point: Vector3) -> String:
	var owner := (
		("white" if point.z > 0.0 else "black")
		if portrait_layout
		else ("white" if point.x < 0.0 else "black")
	)
	if game_state.is_empty():
		if session == null:
			return ""
		var setup_owner := Rules.BLACK if session.setup_black_file < 0 else Rules.WHITE
		if owner != setup_owner:
			return ""
		var setup_local_point := _tray_world_to_local(point, owner)
		var sovereign_center := Vector2(-TRAY_COLUMN_OFFSET, TRAY_RESERVE_START_Z)
		return Rules.SOVEREIGN if setup_local_point.distance_to(sovereign_center) < 0.54 else ""
	if owner != str(game_state.turn):
		return ""
	var local_point := _tray_world_to_local(point, owner)
	if abs(local_point.x) > 1.15:
		return ""
	if abs(local_point.y - TRAY_INFANTRY_Z) < 0.60 and int(game_state.reserves[owner].get("infantry", 0)) > 0:
		return "infantry"
	var kinds := [
		"sovereign", "marshal", "dragoon", "chariot", "griffin",
		"spy", "trebuchet", "ballista", "reinforcement", "recall",
	]
	for index in range(kinds.size()):
		var column := index % 2
		var row := index / 2
		var center := Vector2(
			-TRAY_COLUMN_OFFSET if column == 0 else TRAY_COLUMN_OFFSET,
			TRAY_RESERVE_START_Z + float(row) * TRAY_RESERVE_PITCH,
		)
		if local_point.distance_to(center) < 0.54 and int(game_state.reserves[owner].get(kinds[index], 0)) > 0:
			return kinds[index]
	return ""


func _handle_board_click(square: String) -> void:
	if view_mode == "replay":
		if not game_state.get("board", {}).has(square):
			_clear_selection()
			return
		if selected_source == square:
			_toggle_stack_explosion(square)
			return
		_select_board_stack(square, true)
		return
	if game_state.is_empty():
		if session != null and session.choose_sovereign_square(square):
			_clear_selection()
		return
	if not pending_actions.is_empty():
		for action in pending_actions:
			if str(action.get("effect_target", "")) == square:
				_execute_action(action)
				return
		# Clicking the placement square a second time confirms the legal
		# place-without-firing action. Gold markers remain explicit SHOOT choices.
		for action in pending_actions:
			if not action.has("effect_target") and str(action.get("destination", "")) == square:
				_execute_action(action)
				return
		_clear_selection()
		return
	# The selected stack itself is not a MOVE destination. Repeated clicks use
	# that otherwise-idle gesture to fan the physical tiles apart, then restore
	# them, without losing the legal MOVE/ATTACK markers.
	if selected_source == square:
		_toggle_stack_explosion(square)
		return
	if not selected_source.is_empty() or not selected_reserve_kind.is_empty():
		var destination_actions: Array = []
		for action in candidate_actions:
			if str(action.get("destination", "")) == square:
				destination_actions.append(action)
		if destination_actions.size() == 1:
			_execute_action(destination_actions[0])
			return
		if destination_actions.size() > 1:
			pending_actions = destination_actions
			_show_effect_target_markers()
			_update_interaction_status("Choose SHOOT target or PLACE")
			return
		if _explain_opening_rejection(square):
			return
	if game_state.board.has(square):
		var stack: Array = game_state.board[square]
		if str(stack[-1].owner) == str(game_state.turn):
			if GameEngine.in_development(game_state):
				_show_opening_instruction(square)
				return
			_select_board_stack(square)
			return
		_select_board_stack(square, true)
		return
	_clear_selection()


func _select_board_stack(square: String, inspection_only := false) -> void:
	_collapse_exploded_stack()
	_hide_recall_choices()
	selected_source = square
	selected_reserve_kind = ""
	selected_recall_kind = ""
	pending_actions.clear()
	candidate_actions.clear()
	inspection_destinations.clear()
	if inspection_only:
		for destination in GameEngine.movement_destinations(game_state, square):
			inspection_destinations.append(str(destination))
	else:
		for action in session.legal_actions():
			if str(action.get("type", "")) == "move" and str(action.get("source", "")) == square:
				candidate_actions.append(action)
	_show_destination_markers()
	if inspection_only:
		var inspected_stack: Array = game_state.board[square]
		_update_interaction_status(
			"%s · %s %s · %d moves" % [
				square,
				str(inspected_stack[-1].owner).capitalize(),
				str(inspected_stack[-1].kind).capitalize(),
				inspection_destinations.size(),
			]
		)
	elif candidate_actions.is_empty():
		var stack: Array = game_state.board[square]
		_update_interaction_status("%s · %s · no move" % [square, str(stack[-1].kind).capitalize()])
	else:
		_update_interaction_status("%s · %d moves" % [square, candidate_actions.size()])


func _select_reserve(kind: String) -> void:
	_collapse_exploded_stack()
	selected_source = ""
	selected_reserve_kind = kind
	selected_recall_kind = ""
	pending_actions.clear()
	candidate_actions.clear()
	inspection_destinations.clear()
	if game_state.is_empty():
		_hide_recall_choices()
		_show_setup_markers()
		_update_interaction_status("%s to PLACE Sovereign" % (Rules.BLACK.capitalize() if session.setup_black_file < 0 else Rules.WHITE.capitalize()))
		return
	if kind == Rules.RECALL:
		_show_recall_choices()
		return
	_hide_recall_choices()
	for action in session.legal_actions():
		if str(action.get("type", "")) == "place" and str(action.get("piece", "")) == kind:
			candidate_actions.append(action)
	_show_destination_markers()
	if candidate_actions.is_empty() and GameEngine.in_development(game_state):
		_show_opening_instruction("", kind)
		return
	_update_interaction_status("PLACE %s" % kind.capitalize())


func _explain_opening_rejection(square: String) -> bool:
	if game_state.is_empty() or not GameEngine.in_development(game_state):
		return false
	var rank_index := Rules.square_to_xy(square).y
	var player := str(game_state.turn)
	var in_home := (
		rank_index < Rules.home_ranks()
		if player == Rules.WHITE
		else rank_index >= Rules.board_size() - Rules.home_ranks()
	)
	if in_home:
		return false
	_show_opening_instruction(square)
	return true


func _show_opening_instruction(attempted_square := "", attempted_kind := "") -> void:
	last_feedback_reason = "opening_incomplete"
	var viewport_size := get_viewport().get_visible_rect().size
	var compact_feedback := portrait_layout or viewport_size.x < viewport_size.y
	var required := int(game_state.get("rules", {}).get("development_placements_per_player", 4))
	var player := str(game_state.get("turn", Rules.WHITE))
	var placed := int(game_state.get("development_placements", {}).get(player, 0))
	var remaining := maxi(0, required - placed)
	var detail := "PLACE %d tiles before acting in neutral territory." % required
	if placed > 0 and remaining > 0:
		detail = "PLACE %d more %s in your territory." % [remaining, "tile" if remaining == 1 else "tiles"]
	if attempted_kind in [Rules.SPY, Rules.BALLISTA, Rules.TREBUCHET, Rules.RECALL]:
		detail = "%s becomes available after OPENING." % attempted_kind.capitalize()
	if compact_feedback:
		detail = detail.replace(" before acting in ", " before acting\nin ")
	last_instructional_message = "OPENING\n%s" % detail
	_play_feedback_cue("invalid")
	if not instructional_feedback_enabled:
		_update_interaction_status("OPENING")
		return
	_clear_instructional_feedback()
	_add_home_region_highlight(player)
	if not attempted_square.is_empty():
		_add_feedback_square_pulse(attempted_square, Color("a85f45"))
	var label := Label3D.new()
	label.name = "Opening instruction"
	label.text = last_instructional_message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.font_size = 30 if compact_feedback else 42
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = Color("f2dfb9")
	label.outline_modulate = Color(0.035, 0.025, 0.018, 0.96)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 1.0, 3.05 if player == Rules.WHITE else -3.05)
	feedback_root.add_child(label)
	_update_interaction_status("OPENING · %d PLACEMENT%s remaining" % [remaining, "" if remaining == 1 else "S"])
	_schedule_instructional_feedback_clear()


func _show_destination_markers() -> void:
	_clear_markers()
	if not selected_source.is_empty():
		var source_color := SELECTED_STACK_MARKER if inspection_destinations.is_empty() else INACTIVE_MOVE_MARKER
		_add_legal_marker(selected_source, source_color)
	var destinations := {}
	for action in candidate_actions:
		destinations[str(action.destination)] = true
	for destination in destinations:
		_add_legal_marker(str(destination), ACTIVE_MOVE_MARKER)
	var inspected_destinations := {}
	for destination in inspection_destinations:
		inspected_destinations[str(destination)] = true
	for destination in inspected_destinations:
		_add_legal_marker(str(destination), INACTIVE_MOVE_MARKER)


func _show_effect_target_markers() -> void:
	_clear_markers()
	var placement_square := ""
	for action in pending_actions:
		placement_square = str(action.get("destination", placement_square))
		if action.has("effect_target"):
			_add_legal_marker(str(action.effect_target), SHOOT_TARGET_MARKER, 0.24)
	if not placement_square.is_empty():
		_add_legal_marker(placement_square, ACTIVE_MOVE_MARKER)


func _add_legal_marker(square: String, color: Color, emission_strength := 0.12) -> void:
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.29
	ring.outer_radius = 0.36
	ring.rings = 48
	ring.ring_segments = 16
	marker.mesh = ring
	marker.position = _square_position(square) + Vector3(0.0, -0.09, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * emission_strength
	material.roughness = 0.52
	marker.material_override = material
	marker_root.add_child(marker)


func _clear_markers() -> void:
	for child in marker_root.get_children():
		child.queue_free()


func _clear_instructional_feedback() -> void:
	feedback_generation += 1
	if feedback_root == null:
		return
	for child in feedback_root.get_children():
		child.queue_free()


func _schedule_instructional_feedback_clear() -> void:
	feedback_generation += 1
	var generation := feedback_generation
	get_tree().create_timer(2.4).timeout.connect(func() -> void:
		if generation == feedback_generation:
			_clear_instructional_feedback()
			_update_interaction_status()
	)


func _add_home_region_highlight(player: String) -> void:
	var center_z := 3.0 if player == Rules.WHITE else -3.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.76, 0.56, 0.25, 0.74)
	material.emission_enabled = true
	material.emission = Color("8b612b") * 0.32
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for edge_data in [
		[Vector3(0.0, 0.455, center_z - 1.49), Vector3(9.0, 0.025, 0.055)],
		[Vector3(0.0, 0.455, center_z + 1.49), Vector3(9.0, 0.025, 0.055)],
		[Vector3(-4.49, 0.455, center_z), Vector3(0.055, 0.025, 3.0)],
		[Vector3(4.49, 0.455, center_z), Vector3(0.055, 0.025, 3.0)],
	]:
		var edge := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = edge_data[1]
		edge.mesh = mesh
		edge.position = edge_data[0]
		edge.material_override = material
		feedback_root.add_child(edge)


func _add_feedback_square_pulse(square: String, color: Color) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "Rejected square"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.31
	ring.outer_radius = 0.39
	ring.rings = 48
	ring.ring_segments = 16
	marker.mesh = ring
	marker.position = _square_position(square) + Vector3(0.0, -0.08, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.34
	marker.material_override = material
	feedback_root.add_child(marker)
	var tween := create_tween()
	tween.tween_property(marker, "scale", Vector3(1.16, 1.0, 1.16), 0.10)
	tween.tween_property(marker, "scale", Vector3.ONE, 0.14)


func _clear_selection() -> void:
	_collapse_exploded_stack()
	_hide_recall_choices()
	selected_source = ""
	selected_reserve_kind = ""
	selected_recall_kind = ""
	candidate_actions.clear()
	inspection_destinations.clear()
	pending_actions.clear()
	_clear_markers()
	_update_interaction_status()


func _toggle_stack_explosion(square: String) -> void:
	if exploded_stack_square == square:
		_collapse_exploded_stack()
		_update_interaction_status()
		return
	_collapse_exploded_stack()
	var stack_root: Node3D = board_stack_nodes.get(square)
	if stack_root == null:
		return
	var tokens: Array[Node3D] = []
	for child in stack_root.get_children():
		if child is Node3D and child.has_meta("stack_index"):
			tokens.append(child)
	if tokens.size() < 2:
		return
	tokens.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return int(a.get_meta("stack_index")) < int(b.get_meta("stack_index"))
	)
	exploded_stack_square = square
	var x_direction := 1.0 if stack_root.position.x <= 0.0 else -1.0
	var z_direction := -1.0 if stack_root.position.z >= 0.0 else 1.0
	var hit_shape := stack_root.get_node_or_null("Complete stack hit area/Stack hit shape") as CollisionShape3D
	if hit_shape != null and hit_shape.shape is CylinderShape3D:
		(hit_shape.shape as CylinderShape3D).radius = 1.02
	var tween := create_tween().set_parallel(true)
	for token in tokens:
		var index := int(token.get_meta("stack_index"))
		var fan := float(index)
		var target := Vector3(fan * 0.38 * x_direction, fan * 0.10, fan * 0.12 * z_direction)
		tween.tween_property(token, "position", target, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_update_interaction_status("%s · %d tiles" % [square, tokens.size()])


func _collapse_exploded_stack() -> void:
	if exploded_stack_square.is_empty():
		return
	var stack_root: Node3D = board_stack_nodes.get(exploded_stack_square)
	exploded_stack_square = ""
	if stack_root == null:
		return
	var hit_shape := stack_root.get_node_or_null("Complete stack hit area/Stack hit shape") as CollisionShape3D
	if hit_shape != null and hit_shape.shape is CylinderShape3D:
		(hit_shape.shape as CylinderShape3D).radius = 0.43
	var tween := create_tween().set_parallel(true)
	for child in stack_root.get_children():
		if child is Node3D and child.has_meta("stack_index"):
			var index := int(child.get_meta("stack_index"))
			var target := Vector3(0.0, float(index) * 0.150, 0.0)
			tween.tween_property(child, "position", target, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _toggle_discard_explosion(owner: String) -> void:
	var tokens: Array = discard_token_nodes.get(owner, [])
	if tokens.is_empty():
		_update_interaction_status("%s discard empty" % owner.capitalize())
		return
	if expanded_discard_owner == owner:
		_collapse_discard_explosion()
		_update_interaction_status()
		return
	_collapse_discard_explosion()
	_collapse_exploded_stack()
	expanded_discard_owner = owner
	var tween := create_tween().set_parallel(true)
	for token_value in tokens:
		var token := token_value as Node3D
		if token == null:
			continue
		var index := int(token.get_meta("discard_index", 0))
		var column := index % 6
		var row := index / 6
		var local_x := (float(column) - 2.5) * 0.47
		var local_z := TRAY_DISCARD_START_Z - 0.16 - float(row) * 0.57
		var target := _tray_local_to_world(local_x, 0.72 + float(row) * 0.025, local_z, owner)
		tween.tween_property(token, "position", target, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(token, "rotation_degrees", Vector3(0.0, float(index * 9 - 18), 0.0), 0.20).set_trans(Tween.TRANS_QUAD)
	_update_interaction_status("%s discard · %d pieces" % [owner.capitalize(), tokens.size()])


func _collapse_discard_explosion() -> void:
	if expanded_discard_owner.is_empty():
		return
	var owner := expanded_discard_owner
	expanded_discard_owner = ""
	var tween := create_tween().set_parallel(true)
	for token_value in discard_token_nodes.get(owner, []):
		var token := token_value as Node3D
		if token == null or not is_instance_valid(token):
			continue
		tween.tween_property(token, "position", token.get_meta("discard_home_position"), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(token, "rotation_degrees", token.get_meta("discard_home_rotation"), 0.16).set_trans(Tween.TRANS_QUAD)


func _execute_action(action: Dictionary) -> void:
	if session == null:
		return
	if warn_major_blunder:
		var warning := TacticalWarnings.action_warning(game_state, action)
		if str(warning.get("kind", "")) == "major_blunder":
			pending_warning_action = action.duplicate(true)
			blunder_message.text = str(warning.get("message", "This leaves your Sovereign open to immediate capture."))
			blunder_overlay.visible = true
			return
	_commit_action(action)


func _commit_action(action: Dictionary) -> void:
	if session == null or not session.apply_action(action):
		_update_interaction_status("That action is no longer legal.")
	else:
		_clear_instructional_feedback()


func _cancel_blunder_action() -> void:
	pending_warning_action = {}
	if blunder_overlay != null:
		blunder_overlay.visible = false


func _confirm_blunder_action() -> void:
	var action := pending_warning_action.duplicate(true)
	_cancel_blunder_action()
	if not action.is_empty():
		_commit_action(action)


func _animate_action(action: Dictionary, next_state: Dictionary) -> void:
	var action_type := str(action.get("type", ""))
	if action_type == "move":
		await _animate_move(action, next_state)
	elif action_type in ["place", "recall"]:
		await _animate_place(action, next_state)


func _animate_move(action: Dictionary, next_state: Dictionary) -> void:
	var source := str(action.source)
	var destination := str(action.destination)
	var moving_node: Node3D = board_stack_nodes.get(source)
	if moving_node == null:
		return
	var moving_stack: Array = game_state.board[source]
	var owner := str(moving_stack[-1].owner)
	var destination_stack: Array = game_state.board.get(destination, [])
	var is_attack := not destination_stack.is_empty() and str(destination_stack[-1].owner) != owner
	var captures_entire_stack := is_attack and (
		moving_stack.size() >= destination_stack.size()
		or str(moving_stack[-1].kind) == "sovereign"
	)
	if not is_attack:
		await _animate_node_to(moving_node, _square_position(destination), 0.42)
		return
	var defender_node: Node3D = board_stack_nodes.get(destination)
	var destination_position := _square_position(destination)
	var approach := (_square_position(source) - destination_position).normalized()
	var contact_position := destination_position + approach * 0.72
	var is_griffin_attack := str(moving_stack[-1].kind) == Rules.GRIFFIN
	await _animate_attack_approach(moving_node, contact_position, is_griffin_attack)
	await _animate_attack_impact(moving_node, defender_node, destination, approach)
	if captures_entire_stack:
		if defender_node != null:
			var discard_time := _launch_stack_tiles_to_discard(
				defender_node,
				str(destination_stack[-1].owner),
				destination_stack.size(),
			)
			await get_tree().create_timer(discard_time).timeout
		await _settle_node_at(moving_node, destination_position)
	else:
		var attacker_discard_time := _launch_stack_tiles_to_discard(
			moving_node,
			owner,
			moving_stack.size(),
		)
		var defender_discard_time := 0.0
		if defender_node != null:
			defender_discard_time = _launch_stack_tiles_to_discard(
				defender_node,
				str(destination_stack[-1].owner),
				moving_stack.size(),
			)
			_settle_surviving_stack_tiles(defender_node, moving_stack.size())
		await get_tree().create_timer(maxf(attacker_discard_time, defender_discard_time)).timeout


func _animate_attack_approach(attacker: Node3D, contact_position: Vector3, is_griffin: bool) -> void:
	if is_griffin:
		await _animate_node_to(attacker, contact_position, 0.22)
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(attacker, "position", contact_position, 0.30)
	await tween.finished


func _animate_attack_impact(attacker: Node3D, defender: Node3D, square: String, approach: Vector3) -> void:
	_play_feedback_cue("impact")
	var attacker_contact := attacker.position - approach * 0.18
	var defender_home := _square_position(square)
	var defender_knock := defender_home - approach * 0.24
	var bump := create_tween().set_parallel(true)
	bump.set_trans(Tween.TRANS_QUAD)
	bump.set_ease(Tween.EASE_OUT)
	bump.tween_property(attacker, "position", attacker_contact, 0.09)
	if defender != null:
		bump.tween_property(defender, "position", defender_knock, 0.09)
	await bump.finished
	var ring := MeshInstance3D.new()
	ring.name = "Attack impact ring"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.22
	mesh.outer_radius = 0.29
	mesh.rings = 40
	mesh.ring_segments = 12
	ring.mesh = mesh
	ring.position = _square_position(square) + Vector3(0.0, 0.36, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.91, 0.69, 0.33, 0.90)
	material.emission_enabled = true
	material.emission = Color("bb7831") * 0.45
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material
	feedback_root.add_child(ring)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(1.75, 1.0, 1.75), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.13)
	if attacker != null:
		tween.tween_property(attacker, "position", attacker.position + approach * 0.08, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if defender != null:
		tween.tween_property(defender, "position", defender.position - approach * 0.08, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	ring.queue_free()
	await get_tree().create_timer(0.04).timeout


func _stack_tiles(stack_root: Node3D) -> Array[Node3D]:
	var tiles: Array[Node3D] = []
	if stack_root == null:
		return tiles
	for child in stack_root.get_children():
		if child is Node3D and child.has_meta("stack_index"):
			tiles.append(child as Node3D)
	tiles.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return int(a.get_meta("stack_index")) < int(b.get_meta("stack_index"))
	)
	return tiles


func _launch_stack_tiles_to_discard(stack_root: Node3D, owner: String, count: int) -> float:
	var tiles := _stack_tiles(stack_root)
	var discard_count := mini(count, tiles.size())
	if discard_count <= 0:
		return 0.0
	var target_base := _discard_drop_position(owner)
	for index in range(discard_count):
		var tile := tiles[index]
		tile.reparent(position_root, true)
		var start := tile.position
		var target := target_base + Vector3(float(index - discard_count / 2) * 0.035, float(index) * 0.025, 0.0)
		var midpoint := start.lerp(target, 0.46) + Vector3(0.0, 0.42 + float(index) * 0.035, 0.0)
		var delay := float(index) * 0.055
		var flight := create_tween()
		flight.tween_interval(delay)
		flight.tween_property(tile, "position", midpoint, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flight.tween_property(tile, "position", target, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		flight.parallel().tween_property(
			tile,
			"rotation_degrees:y",
			tile.rotation_degrees.y + 35.0 + float(index) * 12.0,
			0.20,
		)
	return 0.33 + float(discard_count - 1) * 0.055


func _settle_surviving_stack_tiles(stack_root: Node3D, removed_bottom_count: int) -> void:
	var survivors := _stack_tiles(stack_root)
	var tween := create_tween().set_parallel(true)
	for tile in survivors:
		var old_index := int(tile.get_meta("stack_index"))
		if old_index < removed_bottom_count:
			continue
		var new_index := old_index - removed_bottom_count
		tile.set_meta("stack_index", new_index)
		tween.tween_property(tile, "position:y", float(new_index) * 0.150, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _settle_node_at(node: Node3D, destination: Vector3) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position", destination, 0.14)
	await tween.finished


func _animate_place(action: Dictionary, next_state: Dictionary) -> void:
	var owner := str(game_state.turn)
	var kind := str(action.piece)
	var destination := str(action.destination)
	var former_stack: Array = game_state.board.get(destination, [])
	if not former_stack.is_empty() and str(former_stack[-1].owner) != owner:
		var defeated_node: Node3D = board_stack_nodes.get(destination)
		if defeated_node != null:
			await _animate_node_to(defeated_node, _discard_drop_position(str(former_stack[-1].owner)), 0.28)
	var token := _new_token(owner == "black", kind)
	token.position = (
		_discard_drop_position(owner)
		if str(action.get("type", "")) == "recall"
		else _reserve_world_position(kind, owner)
	)
	position_root.add_child(token)
	await _animate_node_to(token, _square_position(destination), 0.40)
	if action.has("effect_target"):
		if kind in [Rules.BALLISTA, Rules.TREBUCHET]:
			await _animate_artillery_facing(
				token,
				_artillery_rotation(kind, destination, str(action.effect_target)),
			)
		await _animate_shot(destination, str(action.effect_target), next_state)


func _animate_artillery_facing(token: Node3D, target_rotation: float) -> void:
	var current := token.rotation_degrees
	var nearest_target := current.y + wrapf(target_rotation - current.y, -180.0, 180.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(token, "rotation_degrees", Vector3(current.x, nearest_target, current.z), 0.22)
	await tween.finished


func _animate_node_to(node: Node3D, destination: Vector3, travel_time: float) -> void:
	var start_y := node.position.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position:y", start_y + 0.34, 0.12)
	tween.tween_property(node, "position:x", destination.x, travel_time).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(node, "position:z", destination.z, travel_time).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "position:y", destination.y, 0.12)
	await tween.finished


func _pulse_node(node: Node3D) -> void:
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector3(1.10, 0.88, 1.10), 0.10)
	tween.tween_property(node, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK)
	await tween.finished


func _play_feedback_cue(kind: String) -> void:
	if not _is_automated_test_run():
		match kind:
			"impact":
				Input.vibrate_handheld(58, 0.58)
			"invalid":
				Input.vibrate_handheld(28, 0.24)
	if feedback_audio == null:
		return
	if not feedback_sounds.has(kind):
		feedback_sounds[kind] = _build_feedback_sound(kind)
	feedback_audio.stream = feedback_sounds[kind]
	feedback_audio.play()


func _build_feedback_sound(kind: String) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.13 if kind == "impact" else 0.09
	var frame_count := int(float(sample_rate) * duration)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 0x713
	for frame in range(frame_count):
		var time := float(frame) / float(sample_rate)
		var envelope := pow(1.0 - float(frame) / float(frame_count), 2.4)
		var sample: float
		if kind == "impact":
			sample = (sin(TAU * 92.0 * time) * 0.62 + random.randf_range(-0.28, 0.28)) * envelope
		else:
			sample = (sin(TAU * 205.0 * time) - sin(TAU * 142.0 * time) * 0.55) * envelope * 0.34
		data.encode_s16(frame * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = sample_rate
	sound.stereo = false
	sound.data = data
	return sound


func _animate_shot(source: String, target: String, next_state: Dictionary) -> void:
	var beam := MeshInstance3D.new()
	var source_position := _square_position(source) + Vector3(0.0, 0.34, 0.0)
	var target_position := _square_position(target) + Vector3(0.0, 0.34, 0.0)
	var direction := target_position - source_position
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.025
	cylinder.bottom_radius = 0.025
	cylinder.height = direction.length()
	cylinder.radial_segments = 16
	beam.mesh = cylinder
	beam.position = (source_position + target_position) * 0.5
	beam.quaternion = Quaternion(Vector3.UP, direction.normalized())
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d9a646")
	material.emission_enabled = true
	material.emission = Color("8d541d")
	beam.material_override = material
	marker_root.add_child(beam)
	await get_tree().create_timer(0.22).timeout
	var target_node: Node3D = board_stack_nodes.get(target)
	if target_node != null:
		if not next_state.board.has(target):
			var target_stack: Array = game_state.board[target]
			await _animate_node_to(target_node, _discard_drop_position(str(target_stack[-1].owner)), 0.30)
		else:
			await _pulse_node(target_node)
	beam.queue_free()


func _reserve_world_position(kind: String, owner: String) -> Vector3:
	if kind == "infantry":
		return _tray_local_to_world(0.0, 0.51, TRAY_INFANTRY_Z, owner)
	var kinds := [
		"sovereign", "marshal", "dragoon", "chariot", "griffin",
		"spy", "trebuchet", "ballista", "reinforcement", "recall",
	]
	var index := kinds.find(kind)
	if index < 0:
		return _tray_local_to_world(0.0, 0.45, TRAY_RESERVE_START_Z, owner)
	var column := index % 2
	var row := index / 2
	return _tray_local_to_world(
		-TRAY_COLUMN_OFFSET if column == 0 else TRAY_COLUMN_OFFSET,
		0.48,
		TRAY_RESERVE_START_Z + float(row) * TRAY_RESERVE_PITCH,
		owner,
	)


func _discard_drop_position(owner: String) -> Vector3:
	return _tray_local_to_world(0.0, 0.51, TRAY_DISCARD_START_Z, owner)


func _undo_state() -> void:
	if session != null:
		session.undo()


func _redo_state() -> void:
	if session != null:
		session.redo()


func _update_interaction_status(message := "") -> void:
	if interaction_status == null:
		return
	if not message.is_empty():
		_set_status_plate_text(message)
		return
	if view_mode == "replay":
		_set_status_plate_text("")
		_position_replay_controls_on_plate()
		return
	if game_state.is_empty():
		if session != null and session.ai_busy:
			_set_status_plate_text("Computer thinking")
		elif session != null and session.setup_black_file < 0:
			_set_status_plate_text("Black to PLACE Sovereign")
		else:
			_set_status_plate_text("White to PLACE Sovereign")
		return
	if session != null and session.ai_busy:
		_set_status_plate_text("%s thinking" % str(game_state.turn).capitalize())
		return
	if game_state.get("winner") != null:
		_set_status_plate_text("%s wins" % str(game_state.winner).capitalize())
	else:
		var tactical := _current_position_warning()
		var warning_kind := str(tactical.get("kind", ""))
		if warning_kind == "checkmate" and warn_checkmate:
			_set_status_plate_text("%s · CHECKMATE danger" % str(game_state.turn).capitalize())
		elif warning_kind == "check" and warn_check:
			_set_status_plate_text("%s · CHECK" % str(game_state.turn).capitalize())
		else:
			_set_status_plate_text("%s to act · ply %d" % [str(game_state.turn).capitalize(), int(game_state.ply)])


func _current_position_warning() -> Dictionary:
	var checksum := Codec.state_checksum(game_state)
	if checksum != tactical_warning_checksum:
		tactical_warning_checksum = checksum
		cached_position_warning = TacticalWarnings.position_warning(game_state)
	return cached_position_warning


func _set_status_plate_text(value: String) -> void:
	interaction_status.text = value
	if value.length() <= 30:
		interaction_status.font_size = 34
	elif value.length() <= 52:
		interaction_status.font_size = 25
	else:
		interaction_status.font_size = 18


func _on_session_state_changed(_reason: String) -> void:
	if view_mode == "replay":
		return
	game_state = session.game_state.duplicate(true)
	_clear_selection()
	_render_game_state()
	_show_setup_markers()
	_update_session_control_labels()
	_update_interaction_status()
	_update_game_over_overlay()
	_refresh_notation_overlay()


func _on_session_setup_changed() -> void:
	if view_mode == "replay":
		return
	game_state = session.game_state.duplicate(true)
	_clear_selection()
	_render_game_state()
	_show_setup_markers()
	_update_session_control_labels()
	_update_interaction_status()
	_update_game_over_overlay()
	_refresh_notation_overlay()


func _on_session_action_committed(before: Dictionary, action: Dictionary, after: Dictionary, _decision: Dictionary) -> void:
	if view_mode == "replay":
		session.presentation_complete()
		return
	game_state = before.duplicate(true)
	animating = true
	_update_session_control_labels()
	_clear_markers()
	await _animate_action(action, after)
	game_state = after.duplicate(true)
	selected_source = ""
	selected_reserve_kind = ""
	candidate_actions.clear()
	inspection_destinations.clear()
	pending_actions.clear()
	_render_game_state()
	animating = false
	_update_session_control_labels()
	_update_interaction_status()
	_update_game_over_overlay()
	_refresh_notation_overlay()
	session.presentation_complete()


func _on_session_ai_busy_changed(_busy: bool) -> void:
	_update_session_control_labels()
	_update_interaction_status()


func _toggle_hamburger() -> void:
	if hamburger_panel == null:
		return
	hamburger_panel.visible = not hamburger_panel.visible


func _toggle_encyclopedia_overlay() -> void:
	if encyclopedia_overlay == null:
		return
	encyclopedia_overlay.visible = not encyclopedia_overlay.visible
	if encyclopedia_overlay.visible:
		hamburger_panel.visible = false
		if notation_overlay != null:
			notation_overlay.visible = false
		if settings_overlay != null:
			settings_overlay.visible = false


func _toggle_settings_overlay() -> void:
	if settings_overlay == null:
		return
	settings_overlay.visible = not settings_overlay.visible
	if settings_overlay.visible:
		hamburger_panel.visible = false
		if notation_overlay != null:
			notation_overlay.visible = false
		if encyclopedia_overlay != null:
			encyclopedia_overlay.visible = false


func _on_warning_setting_changed(enabled: bool, setting: String) -> void:
	match setting:
		"check":
			warn_check = enabled
		"checkmate":
			warn_checkmate = enabled
		"blunder":
			warn_major_blunder = enabled
	_save_warning_preferences()
	_update_interaction_status()


func _on_instructional_feedback_changed(enabled: bool) -> void:
	instructional_feedback_enabled = enabled
	if not enabled:
		_clear_instructional_feedback()
	_save_warning_preferences()


func _load_warning_preferences() -> void:
	if _is_automated_test_run():
		return
	var config := ConfigFile.new()
	if config.load(PREFERENCES_PATH) != OK:
		return
	warn_check = bool(config.get_value("tactical_warnings", "check", true))
	warn_checkmate = bool(config.get_value("tactical_warnings", "checkmate", true))
	warn_major_blunder = bool(config.get_value("tactical_warnings", "major_blunder", true))
	instructional_feedback_enabled = bool(config.get_value("gameplay", "instructional_feedback", true))


func _save_warning_preferences() -> void:
	if _is_automated_test_run():
		return
	var config := ConfigFile.new()
	config.set_value("tactical_warnings", "check", warn_check)
	config.set_value("tactical_warnings", "checkmate", warn_checkmate)
	config.set_value("tactical_warnings", "major_blunder", warn_major_blunder)
	config.set_value("gameplay", "instructional_feedback", instructional_feedback_enabled)
	var error := config.save(PREFERENCES_PATH)
	if error != OK:
		push_warning("Could not save tactical warning preferences: %s" % error_string(error))


func _toggle_notation_overlay() -> void:
	if notation_overlay == null:
		return
	notation_overlay.visible = not notation_overlay.visible
	hamburger_panel.visible = false
	if notation_overlay.visible:
		_refresh_notation_overlay()


func _open_replay_dialog() -> void:
	if session != null and session.ai_busy:
		return
	if not is_instance_valid(file_dialog):
		_build_file_dialog()
	hamburger_panel.visible = false
	file_dialog.current_file = ""
	file_dialog.popup_file_dialog()


func _load_replay(path: String) -> void:
	var parsed = Codec.load_json(path)
	if not parsed is Dictionary:
		replay_error = "That file is not a T3RNARY replay."
		_update_interaction_status()
		return
	_load_replay_document(parsed)


func _load_replay_document(document: Dictionary) -> bool:
	if not document.has("initial_state") or not document.has("actions"):
		replay_error = "That document is not a T3RNARY replay."
		_update_interaction_status()
		return false
	if session != null:
		session.configure_opponent(false, human_color, false)
	view_mode = "replay"
	replay_document = document.duplicate(true)
	replay_actions.clear()
	for raw_action in document.actions:
		if raw_action is Dictionary:
			replay_actions.append(Codec.normalize_action(raw_action))
	replay_states.clear()
	replay_states.append(Codec.normalize_state(document.initial_state))
	replay_index = 0
	replay_error = ""
	replay_end_method = str(document.get("metadata", {}).get("end_method", ""))
	var state: Dictionary = replay_states[0]
	for index in range(replay_actions.size()):
		var action: Dictionary = replay_actions[index]
		if not Codec.actions_contain(GameEngine.legal_actions(state), action):
			replay_error = "Stops at ply %d: recorded action is not legal under the current rules." % (index + 1)
			break
		var next_state := GameEngine.apply_action(state, action, false)
		if next_state.is_empty():
			replay_error = "Stops at ply %d: recorded action could not be applied." % (index + 1)
			break
		replay_states.append(next_state)
		state = next_state
	if replay_end_method == "RESIGNATION" and replay_states.size() == replay_actions.size() + 1:
		var outcome := str(document.get("metadata", {}).get("outcome", ""))
		var resigned_state: Dictionary = replay_states[-1].duplicate(true)
		if outcome == "white_win":
			resigned_state.winner = Rules.WHITE
		elif outcome == "black_win":
			resigned_state.winner = Rules.BLACK
		resigned_state.is_draw = false
		replay_states[-1] = resigned_state
	game_state = replay_states[0].duplicate(true)
	_clear_selection()
	_render_game_state()
	replay_controls.visible = true
	_position_replay_controls_on_plate()
	notation_overlay.visible = false
	game_over_overlay.visible = false
	_update_replay_controls()
	_update_session_control_labels()
	_update_interaction_status()
	return true


func _set_replay_index(index: int, animate_forward := false) -> void:
	if replay_states.is_empty() or animating:
		return
	var target := clampi(index, 0, replay_states.size() - 1)
	var previous := replay_index
	if target == previous:
		return
	_clear_selection()
	if animate_forward and target == previous + 1 and previous < replay_actions.size():
		animating = true
		_update_replay_controls()
		await _animate_action(replay_actions[previous], replay_states[target])
	replay_index = target
	game_state = replay_states[replay_index].duplicate(true)
	_render_game_state()
	animating = false
	_update_replay_controls()
	_update_interaction_status()
	_refresh_notation_overlay()


func _step_replay(delta: int) -> void:
	await _set_replay_index(replay_index + delta, delta > 0)


func _go_to_replay_end() -> void:
	if not replay_states.is_empty():
		_set_replay_index(replay_states.size() - 1)


func _update_replay_controls() -> void:
	if replay_controls == null:
		return
	var last_index := maxi(0, replay_states.size() - 1)
	replay_status.text = "%d / %d" % [replay_index, replay_actions.size()]
	replay_first_button.disabled = animating or replay_index <= 0
	replay_previous_button.disabled = animating or replay_index <= 0
	replay_next_button.disabled = animating or replay_index >= last_index
	replay_last_button.disabled = animating or replay_index >= last_index
	if replay_controls.visible:
		_position_replay_controls_on_plate()


func _action_text(action: Dictionary) -> String:
	var normalized := Codec.normalize_action(action)
	if str(normalized.get("type", "")) == "move":
		return "MOVE %s → %s" % [str(normalized.get("source", "")), str(normalized.get("destination", ""))]
	var verb := "RECALL" if str(normalized.get("type", "")) == "recall" else ("SHOOT" if normalized.get("effect_target") != null else "PLACE")
	var text := "%s %s @ %s" % [verb, Rules.piece_notation(str(normalized.get("piece", ""))), str(normalized.get("destination", ""))]
	if normalized.get("effect_target") != null:
		text += " → %s" % str(normalized.effect_target)
	return text


func _notation_action_count() -> int:
	return mini(replay_index, replay_actions.size()) if view_mode == "replay" else (session.actions.size() if session != null else 0)


func _notation_source() -> Dictionary:
	if view_mode == "replay" and not replay_states.is_empty():
		var count := _notation_action_count()
		return {
			"initial_state": replay_states[0],
			"actions": replay_actions.slice(0, count),
			"states": replay_states.slice(0, count + 1),
			"game_id": str(replay_document.get("game_id", "Replay")),
		}
	if session != null and not session.initial_state.is_empty():
		return {
			"initial_state": session.initial_state,
			"actions": session.actions,
			"states": session.states,
			"game_id": session.game_id,
		}
	return {"initial_state": {}, "actions": [], "states": [], "game_id": "New game"}


func _sovereign_square_in_state(state: Dictionary, owner: String) -> String:
	for square_value in state.get("board", {}):
		var square := str(square_value)
		var stack: Array = state.board[square]
		if not stack.is_empty() and str(stack[-1].owner) == owner and str(stack[-1].kind) == Rules.SOVEREIGN:
			return square
	return ""


func _notation_entries() -> Array[String]:
	var source := _notation_source()
	var initial: Dictionary = source.initial_state
	if initial.is_empty():
		return []
	var entries: Array[String] = []
	var white_square := _sovereign_square_in_state(initial, Rules.WHITE)
	var black_square := _sovereign_square_in_state(initial, Rules.BLACK)
	if not black_square.is_empty():
		entries.append("1B P-V@%s" % black_square)
	if not white_square.is_empty():
		entries.append("1W P-V@%s" % white_square)
	var turn_numbers := {Rules.WHITE: 2, Rules.BLACK: 2}
	var actions: Array = source.actions
	var states: Array = source.states
	for index in range(actions.size()):
		if index + 1 >= states.size():
			break
		var before: Dictionary = states[index]
		var after: Dictionary = states[index + 1]
		var owner := str(before.get("turn", Rules.WHITE))
		var owner_code := "W" if owner == Rules.WHITE else "B"
		entries.append("%d%s %s" % [int(turn_numbers[owner]), owner_code, _action_notation(actions[index], before, after)])
		turn_numbers[owner] = int(turn_numbers[owner]) + 1
	return entries


func _action_notation(action: Dictionary, before: Dictionary, after: Dictionary) -> String:
	var normalized := Codec.normalize_action(action)
	var result := ""
	if str(normalized.get("type", "")) == "move":
		var stack: Array = before.get("board", {}).get(str(normalized.source), [])
		var piece_code := "?" if stack.is_empty() else Rules.piece_notation(str(stack[-1].kind))
		var separator := "x" if before.get("board", {}).has(str(normalized.destination)) else "-"
		result = "M-%s:%s%s%s" % [piece_code, normalized.source, separator, normalized.destination]
	else:
		var destination := str(normalized.destination)
		var target = normalized.get("effect_target")
		if str(normalized.type) == "recall":
			result = "P-Rc(%s)@%s" % [Rules.piece_notation(str(normalized.piece)), destination]
		elif str(normalized.piece) == Rules.SPY and before.get("board", {}).has(destination):
			result = "P-Spx%s" % destination
		else:
			result = "P-%s@%s" % [Rules.piece_notation(str(normalized.piece)), destination]
		if target != null:
			result += "x%s" % str(target)
	var actor := str(before.get("turn", Rules.WHITE))
	if str(after.get("winner", "")) == actor:
		result += "#"
	return result


func _notation_copy_text() -> String:
	var source := _notation_source()
	var initial: Dictionary = source.initial_state
	var ruleset := str(initial.get("rules", {}).get("id", "unknown")) if not initial.is_empty() else "unknown"
	var lines: Array[String] = [
		"T3RNARY GAME NOTATION",
		"Game: %s" % str(source.game_id),
		"Ruleset: %s" % ruleset,
		"Through recorded ply: %d" % _notation_action_count(),
		"",
	]
	var result_line := _notation_result_line()
	if not result_line.is_empty():
		lines.insert(3, result_line)
	for entry in _notation_entries():
		lines.append(entry)
	return "\n".join(lines)


func _notation_result_line() -> String:
	var metadata: Dictionary = replay_document.get("metadata", {}) if view_mode == "replay" else (session.replay_document().get("metadata", {}) if session != null else {})
	if view_mode == "replay" and replay_index < replay_states.size() - 1:
		return ""
	var outcome := str(metadata.get("outcome", ""))
	if outcome == "white_win":
		return "Result: White wins by %s" % str(metadata.get("end_method", "victory")).to_lower()
	if outcome == "black_win":
		return "Result: Black wins by %s" % str(metadata.get("end_method", "victory")).to_lower()
	if outcome == "draw":
		return "Result: Draw"
	return ""


func _refresh_notation_overlay() -> void:
	if notation_text != null and notation_overlay != null and notation_overlay.visible:
		notation_text.text = _notation_copy_text()


func _copy_notation_to_clipboard() -> void:
	DisplayServer.clipboard_set(_notation_copy_text())
	if notation_copy_button != null:
		notation_copy_button.text = "COPIED"
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(notation_copy_button):
			notation_copy_button.text = "COPY"


func _show_setup_markers() -> void:
	if session == null or session.is_setup_complete():
		return
	_clear_markers()
	if session.setup_black_file < 0:
		for file_index in range(Rules.board_size()):
			_add_legal_marker("%s9" % Rules.files().substr(file_index, 1), ACTIVE_MOVE_MARKER)
	else:
		for file_index in session.sovereign_response_files():
			_add_legal_marker("%s1" % Rules.files().substr(file_index, 1), ACTIVE_MOVE_MARKER)


func _start_new_game() -> void:
	view_mode = "play"
	replay_controls.visible = false
	hamburger_panel.visible = false
	notation_overlay.visible = false
	replay_document.clear()
	replay_states.clear()
	replay_actions.clear()
	replay_index = 0
	replay_error = ""
	replay_end_method = ""
	if session != null:
		session.start_new_game()


func _toggle_opponent() -> void:
	if session == null:
		return
	if view_mode == "replay":
		view_mode = "play"
		replay_controls.visible = false
		notation_overlay.visible = false
	session.configure_opponent(not session.ai_enabled, human_color, false)
	session.save_autosave()
	_update_session_control_labels()


func _toggle_human_color() -> void:
	if session == null or not session.ai_enabled:
		return
	if view_mode == "replay":
		view_mode = "play"
		replay_controls.visible = false
		notation_overlay.visible = false
	human_color = Rules.opponent(human_color)
	session.configure_opponent(true, human_color, false)
	session.save_autosave()
	_update_session_control_labels()


func _update_session_control_labels() -> void:
	if new_game_button == null or opponent_button == null or color_button == null or undo_button == null or redo_button == null:
		return
	var computer_enabled: bool = session != null and bool(session.ai_enabled)
	var computer_busy: bool = session != null and bool(session.ai_busy)
	opponent_button.text = "OPPONENT: COMPUTER" if computer_enabled else "OPPONENT: HUMAN"
	color_button.text = "PLAY: %s" % human_color.to_upper()
	color_button.visible = computer_enabled
	new_game_button.disabled = computer_busy or animating
	opponent_button.disabled = computer_busy or animating
	color_button.disabled = computer_busy or animating
	undo_button.disabled = computer_busy or animating or session == null or session.states.size() <= 1 or view_mode == "replay"
	redo_button.disabled = computer_busy or animating or session == null or session.redo_states.is_empty() or view_mode == "replay"
	hamburger_button.disabled = computer_busy or animating


func _show_recall_choices() -> void:
	if recall_choice_panel == null:
		return
	for child in recall_choice_panel.get_children():
		child.queue_free()
	var available := {}
	for action in session.legal_actions():
		if str(action.get("type", "")) == "recall":
			available[str(action.get("piece", ""))] = true
	if available.is_empty():
		recall_choice_panel.visible = false
		_update_interaction_status("No Recall available")
		return
	var heading := Label.new()
	heading.text = "RECALL WHICH PIECE?"
	heading.add_theme_color_override("font_color", Color("ead9ba"))
	recall_choice_panel.add_child(heading)
	var kinds: Array = available.keys()
	kinds.sort()
	for kind_value in kinds:
		var kind := str(kind_value)
		var button := Button.new()
		button.text = kind.to_upper()
		button.pressed.connect(_select_recall_kind.bind(kind))
		_style_touch_button(button)
		recall_choice_panel.add_child(button)
	recall_choice_panel.visible = true
	_update_interaction_status("Choose Recall piece")


func _select_recall_kind(kind: String) -> void:
	selected_recall_kind = kind
	candidate_actions.clear()
	inspection_destinations.clear()
	for action in session.legal_actions():
		if str(action.get("type", "")) == "recall" and str(action.get("piece", "")) == kind:
			candidate_actions.append(action)
	_hide_recall_choices()
	_show_destination_markers()
	_update_interaction_status("RECALL %s" % kind.capitalize())


func _hide_recall_choices() -> void:
	if recall_choice_panel != null:
		recall_choice_panel.visible = false


func _gameplay_input_locked() -> bool:
	if view_mode == "replay":
		return true
	if animating or session == null or session.ai_busy:
		return true
	if (
		(encyclopedia_overlay != null and encyclopedia_overlay.visible)
		or (settings_overlay != null and settings_overlay.visible)
		or (blunder_overlay != null and blunder_overlay.visible)
	):
		return true
	return (
		session.ai_enabled
		and not game_state.is_empty()
		and str(game_state.turn) == str(session.ai_player)
	)
