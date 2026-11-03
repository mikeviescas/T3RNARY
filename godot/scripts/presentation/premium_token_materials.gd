class_name PremiumTokenMaterials
extends RefCounted

const WHITE_MARBLE: Texture2D = preload("res://assets/poc/textures/white_marble_albedo.png")
const BLACK_OBSIDIAN: Texture2D = preload("res://assets/poc/textures/black_obsidian_albedo.png")

static var _stone_shader: Shader
static var _white_stone: ShaderMaterial
static var _black_stone: ShaderMaterial
static var _sovereign_gold: StandardMaterial3D
static var _blackened_brass: StandardMaterial3D
static var _black_enamel: StandardMaterial3D
static var _ivory_enamel: StandardMaterial3D
static var _neutral_gray_enamel: StandardMaterial3D


static func apply(root: Node) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface_index)
			if source == null:
				continue
			var material_name := source.resource_name.to_lower()
			var replacement: Material
			if "white marble" in material_name:
				replacement = _shared_stone_material(false)
			elif "obsidian" in material_name:
				replacement = _shared_stone_material(true)
			elif "sovereign gold" in material_name or "pale gold" in material_name:
				if _sovereign_gold == null:
					_sovereign_gold = _metal_material(Color("e0a83c"), 0.78, 0.14)
				replacement = _sovereign_gold
			elif "blackened brass" in material_name:
				if _blackened_brass == null:
					_blackened_brass = _metal_material(Color("27221d"), 0.76, 0.19)
				replacement = _blackened_brass
			elif "black enamel" in material_name:
				if _black_enamel == null:
					_black_enamel = _enamel_material(Color("090a0c"))
				replacement = _black_enamel
			elif "ivory enamel" in material_name:
				if _ivory_enamel == null:
					_ivory_enamel = _enamel_material(Color("eee9de"))
				replacement = _ivory_enamel
			elif "neutral gray enamel" in material_name:
				if _neutral_gray_enamel == null:
					_neutral_gray_enamel = _enamel_material(Color("626a73"))
				replacement = _neutral_gray_enamel
			if replacement != null:
				mesh_instance.set_surface_override_material(surface_index, replacement)


static func _shared_stone_material(obsidian: bool) -> ShaderMaterial:
	if obsidian and _black_stone != null:
		return _black_stone
	if not obsidian and _white_stone != null:
		return _white_stone
	if _stone_shader == null:
		_stone_shader = Shader.new()
		_stone_shader.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform bool is_obsidian = false;
uniform sampler2D stone_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 object_position;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i);
	float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash3(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	object_position = VERTEX;
}

void fragment() {
	vec3 p = object_position * 5.2;
	vec3 texture_color = texture(stone_texture, UV * 0.82 + vec2(0.07, 0.11)).rgb;
	float broad = noise3(p * 0.72);
	float warp = noise3(p * 1.85 + vec3(2.7, 6.2, 1.4));
	float ribbon = abs(sin(p.x * 1.15 + p.z * 0.78 + warp * 5.6));
	float vein = pow(1.0 - ribbon, 16.0);
	float fine = noise3(p * 4.8);
	if (is_obsidian) {
		vec3 black = vec3(0.012, 0.016, 0.021);
		vec3 smoke = vec3(0.085, 0.095, 0.105);
		vec3 warm_vein = vec3(0.12, 0.085, 0.045);
		ALBEDO = mix(black, smoke, broad * 0.24 + fine * 0.05);
		ALBEDO = mix(ALBEDO, texture_color, 0.72);
		ALBEDO = mix(ALBEDO, warm_vein, vein * 0.10);
		ROUGHNESS = 0.075 + fine * 0.055;
		SPECULAR = 0.92;
	} else {
		vec3 ivory = vec3(0.76, 0.745, 0.70);
		vec3 pearl = vec3(0.94, 0.925, 0.875);
		vec3 grey_vein = vec3(0.34, 0.35, 0.35);
		ALBEDO = mix(ivory, pearl, broad * 0.28 + 0.48);
		ALBEDO = mix(ALBEDO, texture_color, 0.76);
		ALBEDO = mix(ALBEDO, grey_vein, vein * (0.07 + broad * 0.08));
		ROUGHNESS = 0.115 + fine * 0.055;
		SPECULAR = 0.76;
	}
}
"""
	var material := ShaderMaterial.new()
	material.shader = _stone_shader
	material.set_shader_parameter("is_obsidian", obsidian)
	material.set_shader_parameter("stone_texture", BLACK_OBSIDIAN if obsidian else WHITE_MARBLE)
	if obsidian:
		_black_stone = material
	else:
		_white_stone = material
	return material


static func _metal_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


static func _enamel_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = 0.27
	return material
