extends SceneTree


func _init() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var prototype := scene.instantiate()
	viewport.add_child(prototype)
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		prototype.selected_square = str(user_args[0]).to_upper()
	await process_frame
	await process_frame
	await process_frame
	var output := "/tmp/t3rnary-visual-prototype.png"
	var error := viewport.get_texture().get_image().save_png(output)
	if error != OK:
		printerr("Could not save prototype screenshot: %s" % error)
		quit(1)
	else:
		print("Saved visual prototype: " + output)
		quit(0)
