extends SceneTree

const PieceModelView = preload("res://scripts/presentation/piece_model_view.gd")

const KINDS := [
	"sovereign", "infantry", "dragoon", "chariot", "griffin", "marshal",
	"spy", "ballista", "trebuchet", "reinforcement", "recall",
]

const NON_EMBLEM_NAMES := [
	"Nesting bottle-cap body",
	"Opposite-color stack-count inlay",
	"Recessed engraved field",
	"Embossed circular ring",
]


func _init() -> void:
	var output_directory := ProjectSettings.globalize_path("res://assets/poc/encyclopedia_emblems")
	DirAccess.make_dir_recursive_absolute(output_directory)
	for kind in KINDS:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(512, 512)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_8X
		root.add_child(viewport)
		var model: Node3D = PieceModelView.MODELS["white_" + kind].instantiate()
		viewport.add_child(model)
		_apply_emblem_only(model)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 0.92 if kind != "sovereign" else 1.05
		if kind == "sovereign":
			camera.look_at_from_position(Vector3(0.0, 2.35, 2.45), Vector3(0.0, 0.18, 0.0))
		else:
			camera.position = Vector3(0.0, 3.0, 0.0)
			camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		viewport.add_child(camera)
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR
		settings.background_color = Color(0.0, 0.0, 0.0, 0.0)
		environment.environment = settings
		viewport.add_child(environment)
		for _frame in range(4):
			await process_frame
		var image := viewport.get_texture().get_image()
		image = _normalize_transparent_framing(image, kind)
		var path := output_directory.path_join(kind + ".png")
		if image == null or image.is_empty() or image.save_png(path) != OK:
			printerr("Could not render current emblem: " + kind)
			quit(1)
			return
		viewport.queue_free()
		await process_frame
	print("Rendered %d emblems from current tabletop geometry" % KINDS.size())
	quit(0)


func _normalize_transparent_framing(image: Image, kind: String) -> Image:
	if image == null or image.is_empty():
		return image
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return image
	var padding := maxi(8, ceili(float(maxi(used.size.x, used.size.y)) * 0.08))
	var padded := Rect2i(
		Vector2i(maxi(0, used.position.x - padding), maxi(0, used.position.y - padding)),
		Vector2i(
			mini(image.get_width(), used.end.x + padding) - maxi(0, used.position.x - padding),
			mini(image.get_height(), used.end.y + padding) - maxi(0, used.position.y - padding),
		)
	)
	var cropped := image.get_region(padded)
	var target_extent := 432.0
	var scale_factor := target_extent / float(maxi(cropped.get_width(), cropped.get_height()))
	var target_size := Vector2i(
		maxi(1, roundi(float(cropped.get_width()) * scale_factor)),
		maxi(1, roundi(float(cropped.get_height()) * scale_factor)),
	)
	cropped.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	var normalized := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	normalized.fill(Color.TRANSPARENT)
	var destination := Vector2i((512 - target_size.x) / 2, (512 - target_size.y) / 2)
	if kind == "chariot":
		# The large wheel pulls the Chariot's visual weight down and left even
		# when its geometric bounds are centered. Correct that optical imbalance.
		destination += Vector2i(18, -18)
	normalized.blit_rect(cropped, Rect2i(Vector2i.ZERO, target_size), destination)
	return normalized


func _apply_emblem_only(node: Node) -> void:
	var emblem_material := StandardMaterial3D.new()
	emblem_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emblem_material.albedo_color = Color("eee1ca")
	for descendant in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := descendant as MeshInstance3D
		var keep := true
		for excluded_name in NON_EMBLEM_NAMES:
			if mesh_instance.name.begins_with(excluded_name):
				keep = false
				break
		mesh_instance.visible = keep
		if keep:
			mesh_instance.material_override = emblem_material
