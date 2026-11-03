extends Node

signal tabletop_ready(runtime: Node3D)

const RUNTIME_SCENE := "res://scenes/tabletop_poc_runtime.tscn"

var loading_layer: CanvasLayer
var loading_status: Label


func _ready() -> void:
	_size_standalone_window()
	_build_loading_screen()
	# The frame must reach the renderer before requesting the premium model set.
	# Otherwise Godot presents an unexplained black window throughout first load.
	await get_tree().process_frame
	await get_tree().process_frame
	# The runtime script preloads the complete premium token library. Asking the
	# loader to fan that scene out across sub-threads can race nested glTF loads on
	# a cold project launch, leaving valid imported models unavailable to GDScript.
	# Keep the outer load asynchronous but resolve its dependency graph serially.
	var error := ResourceLoader.load_threaded_request(RUNTIME_SCENE, "PackedScene", false)
	if error != OK:
		_show_failure("Could not begin loading the tabletop scene.")
		return
	var pulse := 0
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(RUNTIME_SCENE, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_show_failure("Could not load the tabletop assets.")
			return
		pulse = (pulse + 1) % 4
		var percentage := int(float(progress[0]) * 100.0) if not progress.is_empty() else 0
		loading_status.text = "Preparing the tabletop%s\n%d%%" % [".".repeat(pulse), percentage]
		await get_tree().create_timer(0.08).timeout

	loading_status.text = "Arranging the pieces…"
	await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get(RUNTIME_SCENE)
	var runtime: Node3D = packed.instantiate()
	add_child(runtime)
	await get_tree().process_frame
	loading_layer.queue_free()
	tabletop_ready.emit(runtime)


func _size_standalone_window() -> void:
	# The editor's embedded Game view controls its own size. When the scene runs
	# in a real window, maximize it so the tabletop is not trapped at the POC's
	# original 1280x800 test size. The window remains resizable.
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _build_loading_screen() -> void:
	loading_layer = CanvasLayer.new()
	loading_layer.layer = 100
	add_child(loading_layer)
	var background := ColorRect.new()
	background.color = Color("160b06")
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	loading_layer.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	background.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(520.0, 150.0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	var title := Label.new()
	column.add_child(title)
	title.text = "T3RNARY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("ead9ba"))
	loading_status = Label.new()
	column.add_child(loading_status)
	loading_status.custom_minimum_size = Vector2(520.0, 62.0)
	loading_status.text = "Preparing the tabletop…"
	loading_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_status.add_theme_font_size_override("font_size", 18)
	loading_status.add_theme_color_override("font_color", Color("d7c8b5"))


func _show_failure(message: String) -> void:
	loading_status.text = message
	loading_status.add_theme_color_override("font_color", Color("dc7a6c"))
