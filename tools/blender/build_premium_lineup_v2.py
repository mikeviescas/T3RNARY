"""Render all eleven T3RNARY premium tile faces in marble and obsidian.

Sovereign: recessed gold field with stone crown relief.
All other units: shallow opposite-color embossed ring and logo.
"""

from math import cos, pi, sin
from pathlib import Path
import sys

import bpy
from mathutils import Vector

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from build_premium_tile_v2 import (  # noqa: E402
    add_tile as add_sovereign_tile,
    bevel_object,
    clear_scene,
    cylinder,
    dark_metal_material,
    frustum,
    gold_material,
    marble_material,
    obsidian_material,
    point_camera,
    principled,
    velvet_material,
)


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "art" / "premium_tile_v2"
ICON_SOURCE_DIR = OUTPUT / "icon_sources"
OUTPUT.mkdir(parents=True, exist_ok=True)

UNITS = [
    "sovereign", "infantry", "dragoon", "chariot",
    "griffin", "marshal", "trebuchet", "ballista",
    "spy", "reinforcement", "recall",
]


def paint_material(name, color):
    mat = bpy.data.materials.new(name)
    shader = principled(mat)
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = 0.52
    shader.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.20
    if "Coat Weight" in shader.inputs:
        shader.inputs["Coat Weight"].default_value = 0.0
    return mat


def polygon_shape(name, points, z, depth, mat, bevel=0.018):
    vertices = [(x, y, z - depth * 0.5) for x, y in points]
    mesh = bpy.data.meshes.new(f"{name} mesh")
    mesh.from_pydata(vertices, [], [list(range(len(points)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if mat is not None:
        obj.data.materials.append(mat)
    triangulate = obj.modifiers.new("Triangulate filled mark", "TRIANGULATE")
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    solidify = obj.modifiers.new("Engraving depth", "SOLIDIFY")
    solidify.thickness = depth
    solidify.offset = 0.0
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=solidify.name)
    if bevel:
        bevel_object(obj, bevel, 4)
    return obj


def bar(name, a, b, width, z, depth, mat):
    ax, ay = a
    bx, by = b
    length = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
    bpy.ops.mesh.primitive_cube_add(location=((ax + bx) * 0.5, (ay + by) * 0.5, z))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (width, length, depth)
    obj.rotation_euler.z = -atan2_safe(bx - ax, by - ay)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat is not None:
        obj.data.materials.append(mat)
    bevel_object(obj, min(width * 0.22, 0.020), 4)
    return obj


def atan2_safe(x, y):
    from math import atan2
    return atan2(x, y)


def disc(name, x, y, radius, z, depth, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=radius, depth=depth, location=(x, y, z))
    obj = bpy.context.object
    obj.name = name
    if mat is not None:
        obj.data.materials.append(mat)
    bevel_object(obj, min(radius * 0.12, 0.015), 4)
    return obj


def ellipse_ring(name, x, y, rx, ry, width, z, mat):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=1.0,
        minor_radius=width,
        major_segments=128,
        minor_segments=16,
        location=(x, y, z),
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = (rx, ry, 3.0 if mat is None else 0.15)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def star_points(outer=0.57, inner=0.235, count=5):
    points = []
    for index in range(count * 2):
        radius = outer if index % 2 == 0 else inner
        angle = pi * 0.5 + index * pi / count
        points.append((cos(angle) * radius, sin(angle) * radius))
    points.reverse()
    return points


def imported_icon_geometry(kind, mat, z, depth, scale):
    """Turn the approved 2D silhouette source into actual recessed 3D tooling."""
    before = set(bpy.context.scene.objects)
    bpy.ops.import_curve.svg(filepath=str(ICON_SOURCE_DIR / f"{kind}.svg"))
    curves = [obj for obj in bpy.context.scene.objects if obj not in before and obj.type == "CURVE"]
    if not curves:
        raise RuntimeError(f"No paths imported for {kind}")

    corners = []
    for obj in curves:
        corners.extend([obj.matrix_world @ Vector(corner) for corner in obj.bound_box])
    min_x = min(point.x for point in corners)
    max_x = max(point.x for point in corners)
    min_y = min(point.y for point in corners)
    max_y = max(point.y for point in corners)
    center_x = (min_x + max_x) * 0.5
    center_y = (min_y + max_y) * 0.5
    factor = (1.25 * scale) / max(max_x - min_x, max_y - min_y)

    meshes = []
    for obj in curves:
        obj.data.dimensions = "2D"
        obj.data.resolution_u = 12
        obj.data.extrude = depth
        obj.data.bevel_depth = min(depth * 0.12, 0.006)
        obj.scale.x *= factor
        obj.scale.y *= factor
        obj.location.x -= center_x * factor
        obj.location.y -= center_y * factor
        obj.location.z = z - depth
        obj.data.materials.clear()
        if mat is not None:
            obj.data.materials.append(mat)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
        meshes.append(bpy.context.object)
    return meshes


def raster_silhouette_geometry(filename, mat, z, depth, scale, resolution=192):
    """Convert a transparent silhouette bitmap into shallow relief geometry."""
    image = bpy.data.images.load(str(ICON_SOURCE_DIR / filename), check_existing=False)
    image.scale(resolution, resolution)
    pixels = list(image.pixels)
    mask = []
    for y in range(resolution):
        row = []
        for x in range(resolution):
            index = (y * resolution + x) * 4
            alpha = pixels[index + 3]
            luminance = (pixels[index] + pixels[index + 1] + pixels[index + 2]) / 3.0
            row.append(alpha > 0.45 and luminance < 0.45)
        mask.append(row)

    occupied = [(x, y) for y, row in enumerate(mask) for x, value in enumerate(row) if value]
    if not occupied:
        raise RuntimeError(f"No silhouette pixels found in {filename}")
    min_x = min(x for x, _ in occupied)
    max_x = max(x for x, _ in occupied)
    min_y = min(y for _, y in occupied)
    max_y = max(y for _, y in occupied)
    width = max_x - min_x + 1
    height = max_y - min_y + 1
    cell = (1.30 * scale) / max(width, height)
    center_x = (min_x + max_x + 1) * 0.5
    center_y = (min_y + max_y + 1) * 0.5
    bottom = z - depth

    vertices = []
    faces = []

    def quad(points):
        start = len(vertices)
        vertices.extend(points)
        faces.append((start, start + 1, start + 2, start + 3))

    for x, y in occupied:
        left = (x - center_x) * cell
        right = left + cell
        low = (y - center_y) * cell
        high = low + cell
        quad(((left, low, z), (right, low, z), (right, high, z), (left, high, z)))
        if x == 0 or not mask[y][x - 1]:
            quad(((left, high, bottom), (left, low, bottom), (left, low, z), (left, high, z)))
        if x == resolution - 1 or not mask[y][x + 1]:
            quad(((right, low, bottom), (right, high, bottom), (right, high, z), (right, low, z)))
        if y == 0 or not mask[y - 1][x]:
            quad(((left, low, bottom), (right, low, bottom), (right, low, z), (left, low, z)))
        if y == resolution - 1 or not mask[y + 1][x]:
            quad(((right, high, bottom), (left, high, bottom), (left, high, z), (right, high, z)))

    mesh = bpy.data.meshes.new("Heraldic Griffin relief mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("Heraldic Griffin relief", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return [obj]


def icon_geometry(kind, mat, z=0.867, depth=0.020, scale=1.0):
    if kind == "dragoon":
        return imported_icon_geometry(kind, mat, z, depth, scale)
    if kind == "griffin":
        return raster_silhouette_geometry("griffin-heraldic-source.png", mat, z, depth, scale)
    made = []

    def p(points, name):
        made.append(polygon_shape(name, [(x * scale, y * scale) for x, y in points], z, depth, mat))

    def b(a, c, width, name):
        made.append(bar(name, (a[0] * scale, a[1] * scale), (c[0] * scale, c[1] * scale), width * scale, z, depth, mat))

    def d(x, y, radius, name):
        made.append(disc(name, x * scale, y * scale, radius * scale, z, depth, mat))

    if kind == "infantry":
        for x in (-0.26, 0.0, 0.26):
            b((x, -0.48), (x, 0.24), 0.075, "Infantry pike")
            p([(x - 0.12, 0.20), (x + 0.12, 0.20), (x, 0.55)], "Infantry spearhead")
    elif kind == "marshal":
        p(star_points(), "Marshal star")
    elif kind == "chariot":
        body = polygon_shape("Chariot body", [
            (-0.56 * scale, -0.06 * scale), (-0.52 * scale, 0.43 * scale),
            (-0.10 * scale, 0.36 * scale), (0.18 * scale, 0.18 * scale),
            (0.26 * scale, -0.11 * scale), (0.54 * scale, -0.11 * scale),
            (0.54 * scale, -0.23 * scale), (-0.22 * scale, -0.23 * scale),
        ], z, depth, mat)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=96,
            radius=0.405 * scale,
            depth=depth * 3.0,
            location=(-0.30 * scale, -0.29 * scale, z - depth * 0.45),
        )
        wheel_clearance = bpy.context.object
        bpy.context.view_layer.objects.active = body
        wheel_cut = body.modifiers.new("Remove body behind wheel", "BOOLEAN")
        wheel_cut.operation = "DIFFERENCE"
        wheel_cut.solver = "EXACT"
        wheel_cut.object = wheel_clearance
        bpy.ops.object.modifier_apply(modifier=wheel_cut.name)
        bpy.data.objects.remove(wheel_clearance, do_unlink=True)
        made.append(body)
        made.append(ellipse_ring("Chariot wheel", -0.30 * scale, -0.29 * scale, 0.35 * scale, 0.35 * scale, 0.055 * scale, z, mat))
        d(-0.30, -0.29, 0.075, "Chariot hub")
        for angle in range(0, 360, 45):
            r = angle * pi / 180.0
            b((-0.30 + cos(r) * 0.10, -0.29 + sin(r) * 0.10),
              (-0.30 + cos(r) * 0.28, -0.29 + sin(r) * 0.28), 0.026, "Chariot spoke")

        # The wheel makes the silhouette visually heavy at lower left. Center the
        # completed mark by its full bounds so it reads centrally inside the ring.
        for obj in made:
            obj.location.x += 0.055 * scale
            obj.location.y += 0.105 * scale
    elif kind == "trebuchet":
        # Overhead plan: an inverted Christian-cross frame. The long throwing
        # arm points upward into a spoon; the other three ends have stabilizers.
        b((0.0, -0.42), (0.0, 0.48), 0.135, "Trebuchet throwing arm")
        b((-0.46, -0.20), (0.46, -0.20), 0.125, "Trebuchet cross frame")
        p([(-0.16, 0.38), (0.16, 0.38), (0.24, 0.53),
           (0.17, 0.65), (-0.17, 0.65), (-0.24, 0.53)], "Trebuchet spoon")
        b((-0.55, -0.34), (-0.55, -0.06), 0.105, "Trebuchet left foot")
        b((0.55, -0.34), (0.55, -0.06), 0.105, "Trebuchet right foot")
        b((-0.16, -0.52), (0.16, -0.52), 0.105, "Trebuchet rear foot")
        d(0.0, -0.20, 0.105, "Trebuchet axle")
    elif kind == "ballista":
        # Built on the vertical axis rather than rotating the former diagonal
        # mark. The massive stock reads separately from the slimmer bolt.
        b((0.0, -0.50), (0.0, 0.50), 0.165, "Ballista heavy center stock")
        b((0.0, -0.38), (0.0, 0.57), 0.048, "Ballista bolt")
        p([(-0.13, 0.49), (0.13, 0.49), (0.0, 0.69)], "Ballista bolt head")
        bow = [(-0.64, 0.04), (-0.50, 0.20), (-0.27, 0.31),
               (0.0, 0.35), (0.27, 0.31), (0.50, 0.20), (0.64, 0.04)]
        for index in range(len(bow) - 1):
            b(bow[index], bow[index + 1], 0.090, "Ballista transverse bow")
        b((-0.64, 0.04), (0.0, -0.16), 0.026, "Ballista taut string")
        b((0.0, -0.16), (0.64, 0.04), 0.026, "Ballista taut string")
        p([(-0.18, -0.42), (0.18, -0.42), (0.25, -0.59),
           (-0.25, -0.59)], "Ballista rear block")
    elif kind == "spy":
        made.append(ellipse_ring("Spy eye", 0, 0, 0.58 * scale, 0.34 * scale, 0.065 * scale, z, mat))
        d(0, 0, 0.17, "Spy pupil")
    elif kind == "reinforcement":
        b((-0.48, 0.0), (0.48, 0.0), 0.19, "Reinforcement cross")
        b((0.0, -0.48), (0.0, 0.48), 0.19, "Reinforcement cross")
    elif kind == "recall":
        arc_points = []
        for index in range(13):
            angle = (35 + index * 22) * pi / 180.0
            arc_points.append((cos(angle) * 0.43, sin(angle) * 0.43))
        for index in range(len(arc_points) - 1):
            b(arc_points[index], arc_points[index + 1], 0.090, "Recall circular arrow")
        p([(0.31, 0.39), (0.65, 0.35), (0.48, 0.06)], "Recall arrowhead")
    return made


def join_objects(objects, name):
    if not objects:
        return None
    if len(objects) == 1:
        objects[0].name = name
        return objects[0]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    return joined


def add_standard_tile(kind, location, rotation_z, stone, fill):
    before = set(bpy.context.scene.objects)
    frustum("Stone lower skirt", 1.40, 1.31, 0.45, 0.225, stone, 0.055)
    frustum("Stone upper crown", 1.13, 1.045, 0.38, 0.635, stone, 0.045)
    face = cylinder("Machined stone face", 1.045, 0.120, 0.830, stone, 0.030)

    # Shallow embossed opposite-color ring and unit mark. Gold is reserved for
    # the Sovereign's reverse face.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.920, minor_radius=0.018, major_segments=192, minor_segments=24, location=(0, 0, 0.903))
    ring_fill = bpy.context.object
    ring_fill.name = "Embossed opposite-color pinstripe"
    ring_fill.data.materials.append(fill)
    logo = join_objects(icon_geometry(kind, fill, z=0.925, depth=0.040, scale=1.0), f"Embossed {kind} mark")
    if kind == "trebuchet":
        # The artillery marks teach their firing geometry: Ballista points
        # orthogonally up; Trebuchet points on the upper-left diagonal.
        bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
        bpy.ops.object.select_all(action="DESELECT")
        logo.select_set(True)
        bpy.context.view_layer.objects.active = logo
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        logo.rotation_euler.z = pi / 4

    created = [obj for obj in bpy.context.scene.objects if obj not in before]
    root = bpy.data.objects.new(f"{kind.capitalize()} tile assembly", None)
    bpy.context.scene.collection.objects.link(root)
    for obj in created:
        obj.parent = root
    root.location = location
    root.rotation_euler.z = 0.0 if kind in ("trebuchet", "ballista") else rotation_z
    return root


def add_label(text, location, mat):
    bpy.ops.object.text_add(location=location)
    label = bpy.context.object
    label.name = f"{text} label"
    label.data.body = text.upper()
    label.data.align_x = "CENTER"
    label.data.align_y = "CENTER"
    label.data.size = 0.19
    label.data.extrude = 0.006
    label.data.bevel_depth = 0.002
    label.data.materials.append(mat)
    return label


def build_lineup(dark=False):
    clear_scene()
    marble = marble_material()
    obsidian = obsidian_material()
    gold = gold_material()
    shadow = dark_metal_material()
    black_fill = paint_material("Black enamel engraving fill", (0.008, 0.009, 0.011))
    white_fill = paint_material("Ivory enamel engraving fill", (0.92, 0.90, 0.84))
    label_mat = paint_material("Lineup label", (0.70, 0.66, 0.58))
    velvet = velvet_material()
    stone = obsidian if dark else marble
    fill = white_fill if dark else black_fill

    bpy.ops.mesh.primitive_plane_add(size=22, location=(0, 0, -0.05))
    floor = bpy.context.object
    floor.name = "Velvet lineup surface"
    floor.data.materials.append(velvet)

    xs = (-4.8, -1.6, 1.6, 4.8)
    ys = (4.0, 0.0, -4.0)
    for index, kind in enumerate(UNITS):
        row, column = divmod(index, 4)
        position = (xs[column], ys[row], 0.0)
        if kind == "sovereign":
            add_sovereign_tile("Sovereign", position, 0.0, stone, gold, shadow)
        else:
            add_standard_tile(kind, position, (index % 3 - 1) * 0.035, stone, fill)
        add_label(kind, (position[0], position[1] - 1.64, 0.01), label_mat)

    world = bpy.data.worlds.new("Lineup studio world")
    bpy.context.scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.006, 0.005, 0.006, 1.0)
    background.inputs["Strength"].default_value = 0.11

    # Near-neutral studio lighting keeps the white embossing white. Gold belongs
    # to the Sovereign face itself, never to a reflected color cast.
    for name, location, energy, size, color in (
        ("Neutral key", (-6.0, -6.5, 11.0), 1500.0, 6.0, (1.0, 0.97, 0.93)),
        ("Cool fill", (7.0, -1.0, 9.0), 1050.0, 5.0, (0.76, 0.84, 1.0)),
        ("Neutral rim", (0.0, 8.0, 10.0), 750.0, 4.0, (0.93, 0.95, 1.0)),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = size
        light.data.color = color
        point_camera(light, (0, 0, 0.4))

    bpy.ops.object.camera_add(location=(0.0, -16.2, 18.2))
    camera = bpy.context.object
    camera.data.lens = 57
    point_camera(camera, (0, 0, 0.25))
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 1400
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.look = "AgX - Medium High Contrast"
    color_name = "black" if dark else "white"
    scene.render.filepath = str(OUTPUT / f"premium_{color_name}_lineup.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"premium_{color_name}_lineup.blend"))
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_lineup(dark=False)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_lineup(dark=True)
    print(f"Saved premium lineups in {OUTPUT}")
