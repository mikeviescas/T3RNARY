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
		var mode := str(user_args[0]).to_upper()
		if mode in ["PLAY", "PLAY_BLACK"]:
			prototype._start_new_game()
			prototype._handle_play_square("E1")
			prototype._handle_play_square("E9")
			if mode == "PLAY_BLACK":
				prototype._select_reserve_piece("infantry")
				for action in prototype._legal_actions():
					if action.type == "place" and action.piece == "infantry" and action.get("effect_target") == null:
						prototype._handle_play_square(str(action.destination))
						break
			prototype._select_reserve_piece("infantry")
		elif mode == "REPLAY" and user_args.size() >= 2:
			prototype._load_replay(str(user_args[1]))
			if user_args.size() >= 3:
				prototype._set_replay_index(int(user_args[2]))
		else:
			prototype.selected_square = mode
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
