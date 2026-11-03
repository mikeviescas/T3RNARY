"""Build a clean, Blender-native luxury Sovereign tile material study.

This is intentionally independent of the earlier Godot POC token generator.
It exists to approve geometry, engraving, stone, metal, and lighting before any
real-time optimization or simulator integration.
"""

from math import atan2
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
ART_DIR = ROOT / "art" / "premium_tile_v2"
ART_DIR.mkdir(parents=True, exist_ok=True)
BLEND_PATH = ART_DIR / "premium_sovereign_study.blend"
RENDER_PATH = ART_DIR / "premium_sovereign_study.png"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.materials, bpy.data.curves, bpy.data.meshes, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def principled(material):
    material.use_nodes = True
    return material.node_tree.nodes.get("Principled BSDF")


def marble_material():
    mat = bpy.data.materials.new("Honed Calacatta marble")
    shader = principled(mat)
    shader.inputs["Roughness"].default_value = 0.16
    shader.inputs["IOR"].default_value = 1.49
    if "Coat Weight" in shader.inputs:
        shader.inputs["Coat Weight"].default_value = 0.18
        shader.inputs["Coat Roughness"].default_value = 0.10

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    tex = nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = 3.2
    tex.inputs["Detail"].default_value = 7.5
    tex.inputs["Roughness"].default_value = 0.68
    tex.inputs["Distortion"].default_value = 1.8
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
    base = ramp.color_ramp.elements[0]
    base.position = 0.33
    base.color = (0.88, 0.86, 0.80, 1.0)
    pre_vein = ramp.color_ramp.elements.new(0.455)
    pre_vein.color = (0.95, 0.94, 0.90, 1.0)
    vein = ramp.color_ramp.elements.new(0.495)
    vein.color = (0.53, 0.55, 0.56, 1.0)
    pearl = ramp.color_ramp.elements.new(0.535)
    pearl.color = (0.96, 0.95, 0.91, 1.0)
    top = ramp.color_ramp.elements.new(0.72)
    top.color = (0.82, 0.80, 0.74, 1.0)
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.075
    bump.inputs["Distance"].default_value = 0.025
    links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
    links.new(tex.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    return mat


def obsidian_material():
    mat = bpy.data.materials.new("Polished volcanic obsidian")
    shader = principled(mat)
    shader.inputs["Roughness"].default_value = 0.085
    shader.inputs["IOR"].default_value = 1.51
    if "Coat Weight" in shader.inputs:
        shader.inputs["Coat Weight"].default_value = 0.36
        shader.inputs["Coat Roughness"].default_value = 0.055

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    tex = nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = 2.35
    tex.inputs["Detail"].default_value = 8.0
    tex.inputs["Roughness"].default_value = 0.72
    tex.inputs["Distortion"].default_value = 2.4
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.22
    ramp.color_ramp.elements[0].color = (0.0025, 0.0035, 0.005, 1.0)
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[1].color = (0.042, 0.039, 0.038, 1.0)
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.035
    bump.inputs["Distance"].default_value = 0.018
    links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
    links.new(tex.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    return mat


def gold_material():
    mat = bpy.data.materials.new("Brushed 18k gold")
    shader = principled(mat)
    shader.inputs["Base Color"].default_value = (0.83, 0.52, 0.14, 1.0)
    shader.inputs["Metallic"].default_value = 0.94
    shader.inputs["Roughness"].default_value = 0.16
    if "Anisotropic IOR Level" in shader.inputs:
        shader.inputs["Anisotropic IOR Level"].default_value = 0.22
    return mat


def dark_metal_material():
    mat = bpy.data.materials.new("Blackened engraving shadow")
    shader = principled(mat)
    shader.inputs["Base Color"].default_value = (0.008, 0.007, 0.006, 1.0)
    shader.inputs["Metallic"].default_value = 0.72
    shader.inputs["Roughness"].default_value = 0.22
    return mat


def velvet_material():
    mat = bpy.data.materials.new("Deep charcoal velvet")
    shader = principled(mat)
    shader.inputs["Base Color"].default_value = (0.012, 0.010, 0.012, 1.0)
    shader.inputs["Roughness"].default_value = 0.88
    if "Sheen Weight" in shader.inputs:
        shader.inputs["Sheen Weight"].default_value = 0.42
        shader.inputs["Sheen Tint"].default_value = (0.18, 0.15, 0.20, 1.0)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 145.0
    noise.inputs["Detail"].default_value = 2.0
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    bump.inputs["Distance"].default_value = 0.015
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    return mat


def bevel_object(obj, width, segments=6):
    modifier = obj.modifiers.new("Precision edge bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True


def frustum(name, radius1, radius2, depth, z, mat, bevel=0.035):
    bpy.ops.mesh.primitive_cone_add(
        vertices=192,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=(0, 0, z),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel_object(obj, bevel)
    return obj


def cylinder(name, radius, depth, z, mat, bevel=0.025):
    bpy.ops.mesh.primitive_cylinder_add(vertices=192, radius=radius, depth=depth, location=(0, 0, z))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel_object(obj, bevel)
    return obj


def crown_relief(name, mat):
    points = [
        (-0.50, -0.25), (-0.46, 0.34), (-0.19, 0.10),
        (0.00, 0.49), (0.19, 0.10), (0.46, 0.34),
        (0.50, -0.25), (0.45, -0.38), (-0.45, -0.38),
    ]
    points.reverse()
    vertices = [(x, y, 0.0) for x, y in points]
    mesh = bpy.data.meshes.new(f"{name} mesh")
    mesh.from_pydata(vertices, [], [list(range(len(vertices)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.location.z = 0.885
    triangulate = obj.modifiers.new("Triangulate crown face", "TRIANGULATE")
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    solidify = obj.modifiers.new("Cut-stone crown relief", "SOLIDIFY")
    solidify.thickness = 0.070
    solidify.offset = 0.0
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=solidify.name)
    bevel_object(obj, 0.025, 5)
    for x, y, scale in ((-0.46, 0.34, 0.075), (0.0, 0.49, 0.085), (0.46, 0.34, 0.075)):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=scale, location=(x, y, 0.925))
        jewel = bpy.context.object
        jewel.name = "Rounded crown point"
        jewel.scale.z = 0.42
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        jewel.data.materials.append(mat)
    return obj


def add_tile(name, location, rotation_z, stone, gold, shadow):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    before = set(bpy.context.scene.objects)

    frustum("Stone lower skirt", 1.40, 1.31, 0.45, 0.225, stone, 0.055)
    frustum("Stone upper crown", 1.13, 1.045, 0.38, 0.635, stone, 0.045)
    face_rim = cylinder("Machined stone face rim", 1.045, 0.120, 0.830, stone, 0.030)
    bpy.ops.mesh.primitive_cylinder_add(vertices=192, radius=0.905, depth=0.180, location=(0, 0, 0.855))
    recess_cutter = bpy.context.object
    recess_cutter.name = "Gold-field recess cutter"
    bpy.context.view_layer.objects.active = face_rim
    recess = face_rim.modifiers.new("Cut reverse-engraved field", "BOOLEAN")
    recess.operation = "DIFFERENCE"
    recess.solver = "EXACT"
    recess.object = recess_cutter
    bpy.ops.object.modifier_apply(modifier=recess.name)
    bpy.data.objects.remove(recess_cutter, do_unlink=True)
    cylinder("Recessed reverse-gold field", 0.885, 0.055, 0.852, gold, 0.018)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.920,
        minor_radius=0.020,
        major_segments=192,
        minor_segments=24,
        location=(0, 0, 0.864),
    )
    groove = bpy.context.object
    groove.name = "Machined shadow line"
    groove.data.materials.append(shadow)
    crown_relief("Raised stone Sovereign crown", stone)

    created = [obj for obj in bpy.context.scene.objects if obj not in before]
    for obj in created:
        for owner in list(obj.users_collection):
            owner.objects.unlink(obj)
        collection.objects.link(obj)
    collection_instance = bpy.data.objects.new(f"{name} assembly", None)
    bpy.context.scene.collection.objects.link(collection_instance)
    for obj in created:
        obj.parent = collection_instance
    collection_instance.location = location
    collection_instance.rotation_euler.z = rotation_z
    return collection_instance


def point_camera(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def build_scene():
    clear_scene()
    marble = marble_material()
    obsidian = obsidian_material()
    gold = gold_material()
    shadow = dark_metal_material()
    velvet = velvet_material()

    bpy.ops.mesh.primitive_plane_add(size=18, location=(0, 0, -0.04))
    floor = bpy.context.object
    floor.name = "Velvet presentation surface"
    floor.data.materials.append(velvet)

    add_tile("White marble Sovereign", (-1.42, 0.12, 0.0), -0.15, marble, gold, shadow)
    add_tile("Black obsidian Sovereign", (1.42, 0.34, 0.0), 0.18, obsidian, gold, shadow)

    world = bpy.data.worlds.new("Premium studio world")
    bpy.context.scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.008, 0.006, 0.006, 1.0)
    background.inputs["Strength"].default_value = 0.13

    bpy.ops.object.light_add(type="AREA", location=(-3.8, -3.2, 6.5))
    key = bpy.context.object
    key.name = "Large warm softbox"
    key.data.energy = 880.0
    key.data.shape = "DISK"
    key.data.size = 4.0
    key.data.color = (1.0, 0.78, 0.56)
    point_camera(key, (0, 0, 0.35))

    bpy.ops.object.light_add(type="AREA", location=(4.2, -0.2, 4.0))
    rim = bpy.context.object
    rim.name = "Cool edge softbox"
    rim.data.energy = 720.0
    rim.data.size = 3.2
    rim.data.color = (0.54, 0.70, 1.0)
    point_camera(rim, (0.5, 0.25, 0.45))

    bpy.ops.object.light_add(type="AREA", location=(0.0, 4.5, 5.0))
    back = bpy.context.object
    back.name = "Gold rim light"
    back.data.energy = 650.0
    back.data.size = 2.6
    back.data.color = (1.0, 0.54, 0.22)
    point_camera(back, (0, 0.4, 0.5))

    bpy.ops.object.camera_add(location=(0.0, -7.4, 4.5))
    camera = bpy.context.object
    camera.name = "Premium product camera"
    camera.data.lens = 58
    point_camera(camera, (0, 0.30, 0.48))
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(RENDER_PATH)
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.resolution_percentage = 100
    scene.render.image_settings.color_depth = "8"
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_scene()
    print(f"Saved Blender study: {BLEND_PATH}")
    print(f"Saved render: {RENDER_PATH}")
