"""Generate the first T3RNARY tabletop POC meshes for Godot.

Run with Blender, not the system Python:
  blender --background --python tools/blender/build_tabletop_poc.py
"""

from pathlib import Path
import importlib.util
from math import cos, pi, sin
import sys

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "godot" / "assets" / "poc"
OUTPUT.mkdir(parents=True, exist_ok=True)

PREMIUM_SPEC = importlib.util.spec_from_file_location(
    "premium_lineup_geometry", ROOT / "tools" / "blender" / "build_premium_lineup_v2.py"
)
PREMIUM = importlib.util.module_from_spec(PREMIUM_SPEC)
PREMIUM_SPEC.loader.exec_module(PREMIUM)

TOKEN_KINDS = (
    "sovereign", "infantry", "dragoon", "chariot", "griffin", "marshal",
    "trebuchet", "ballista", "spy", "reinforcement", "recall",
)


def material(name, color, roughness=0.55, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return mat


def bevel_box(name, location, dimensions, mat, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        modifier = obj.modifiers.new("Soft manufactured edge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 4
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.materials.append(mat)
    return obj


def cylinder(name, radius, depth, z, mat, bevel=0.025, vertices=96):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0, 0, z))
    obj = bpy.context.object
    obj.name = name
    if bevel > 0:
        modifier = obj.modifiers.new("Rounded rim", "BEVEL")
        modifier.width = bevel
        modifier.segments = 4
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.materials.append(mat)
    return obj


def bottle_cap_body(name, side_mat, crown_mat):
    # 28:22:10 proportions represented at a convenient Godot scale:
    # 0.84 base diameter, 0.66 crown diameter, and ~0.30 body height.
    bpy.ops.mesh.primitive_cone_add(
        vertices=128,
        radius1=0.420,
        radius2=0.402,
        depth=0.150,
        location=(0, 0, -0.075),
    )
    lower = bpy.context.object
    lower.name = name
    lower.data.materials.append(side_mat)

    bpy.ops.mesh.primitive_cone_add(
        vertices=128,
        radius1=0.345,
        radius2=0.325,
        depth=0.150,
        location=(0, 0, 0.075),
    )
    crown = bpy.context.object
    crown.name = "Upper crown"
    crown.data.materials.append(crown_mat)

    # Unite the skirt and crown so the underside socket can extend just beyond
    # the midpoint. The upper tile therefore rests on the full annular shoulder
    # while the lower crown clears the socket roof.
    bpy.context.view_layer.objects.active = lower
    union = lower.modifiers.new("Join crown to skirt", "BOOLEAN")
    union.operation = "UNION"
    union.solver = "EXACT"
    union.object = crown
    bpy.ops.object.modifier_apply(modifier=union.name)
    bpy.data.objects.remove(crown, do_unlink=True)

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=128,
        radius=0.338,
        depth=0.180,
        location=(0, 0, -0.070),
    )
    socket = bpy.context.object
    socket.name = "Underside socket cutter"
    bpy.context.view_layer.objects.active = lower
    difference = lower.modifiers.new("Cut nesting socket", "BOOLEAN")
    difference.operation = "DIFFERENCE"
    difference.solver = "EXACT"
    difference.object = socket
    bpy.ops.object.modifier_apply(modifier=difference.name)
    bpy.data.objects.remove(socket, do_unlink=True)

    # Machine a shallow face well into the crown. The icon and ring sit within
    # this recess instead of reading as a printed label laid over the tile.
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=128,
        radius=0.304,
        depth=0.020,
        location=(0, 0, 0.148),
    )
    face_well = bpy.context.object
    face_well.name = "Engraved face-well cutter"
    bpy.context.view_layer.objects.active = lower
    face_cut = lower.modifiers.new("Machine recessed face", "BOOLEAN")
    face_cut.operation = "DIFFERENCE"
    face_cut.solver = "EXACT"
    face_cut.object = face_well
    bpy.ops.object.modifier_apply(modifier=face_cut.name)
    bpy.data.objects.remove(face_well, do_unlink=True)

    bevel = lower.modifiers.new("Bottle-cap bevels", "BEVEL")
    bevel.width = 0.012
    bevel.segments = 4
    bevel.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = lower
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return lower


def flat_polygon(name, points, z, depth, mat):
    """Create a shallow piece of relief/inlay geometry on the tile face."""
    vertices = [(x, y, z - depth * 0.5) for x, y in points]
    mesh = bpy.data.meshes.new(f"{name} mesh")
    mesh.from_pydata(vertices, [], [list(range(len(points)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    solidify = obj.modifiers.new("Shallow engraved relief", "SOLIDIFY")
    solidify.thickness = depth
    solidify.offset = 0.0
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=solidify.name)
    bevel = obj.modifiers.new("Soft relief edge", "BEVEL")
    bevel.width = 0.004
    bevel.segments = 3
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def add_star_icon(mat, z=0.155):
    from math import cos, pi, sin

    points = []
    for index in range(10):
        # Fill the engraved field so the Marshal reads immediately at tabletop
        # scale while leaving a narrow breathing gap inside the circular ring.
        radius = 0.215 if index % 2 == 0 else 0.090
        angle = pi * 0.5 + index * pi / 5.0
        points.append((cos(angle) * radius, sin(angle) * radius))
    flat_polygon("Engraved Marshal star", points, z, 0.010, mat)


def add_infantry_icon(mat, z=0.155):
    for x in (-0.075, 0.0, 0.075):
        bevel_box("Engraved Infantry shaft", (x, -0.015, z), (0.025, 0.195, 0.010), mat, 0.004)
        flat_polygon(
            "Engraved Infantry spearhead",
            [(x - 0.038, 0.065), (x + 0.038, 0.065), (x, 0.140)],
            z,
            0.010,
            mat,
        )


def add_crown_icon(mat, z=0.161):
    points = [
        (-0.145, -0.090), (-0.128, 0.085), (-0.052, 0.020),
        (0.000, 0.125), (0.052, 0.020), (0.128, 0.085),
        (0.145, -0.090),
    ]
    flat_polygon("Sovereign crown relief", points, z, 0.018, mat)
    bevel_box("Sovereign crown base", (0, -0.112, z), (0.260, 0.030, 0.018), mat, 0.006)


def add_dotted_perimeter(mat, radius=0.276, z=0.160, count=24):
    """Build a manufactured dotted inlay rather than a texture or decal."""
    for index in range(count):
        angle = 2.0 * pi * float(index) / float(count)
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=16,
            ring_count=8,
            radius=0.011,
            location=(radius * cos(angle), radius * sin(angle), z),
        )
        dot = bpy.context.object
        dot.name = "Dotted special-piece perimeter"
        dot.scale.z = 0.42
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        dot.data.materials.append(mat)


def add_crown_prong(angle, mat, radius=0.255, width=0.235, bottom_z=0.175, tip_z=0.395):
    """Add one broad triangular crown plate facing away from the center."""
    radial = Vector((cos(angle), sin(angle), 0.0))
    tangent = Vector((-sin(angle), cos(angle), 0.0))
    center = radial * radius
    points = [
        center - tangent * (width * 0.5) + Vector((0, 0, bottom_z)),
        center + tangent * (width * 0.5) + Vector((0, 0, bottom_z)),
        center + Vector((0, 0, tip_z)),
    ]
    mesh = bpy.data.meshes.new("Sovereign triangular crown prong mesh")
    mesh.from_pydata([tuple(point) for point in points], [], [[0, 1, 2]])
    mesh.update()
    prong = bpy.data.objects.new("Sovereign broad triangular crown prong", mesh)
    bpy.context.collection.objects.link(prong)
    prong.data.materials.append(mat)
    solidify = prong.modifiers.new("Substantial crown plate", "SOLIDIFY")
    solidify.thickness = 0.040
    solidify.offset = 0.0
    bpy.context.view_layer.objects.active = prong
    bpy.ops.object.modifier_apply(modifier=solidify.name)
    bevel = prong.modifiers.new("Soft royal prong edge", "BEVEL")
    bevel.width = 0.009
    bevel.segments = 3
    bpy.context.view_layer.objects.active = prong
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return center


def sovereign_crown_piece(side_mat, stone_mat, stripe_mat):
    """Create a standalone royal crown approximately as tall as a 3 Stack."""
    bpy.ops.mesh.primitive_cone_add(
        vertices=128,
        radius1=0.420,
        radius2=0.385,
        depth=0.150,
        location=(0, 0, -0.075),
    )
    plinth = bpy.context.object
    plinth.name = "Sovereign stone plinth"
    plinth.data.materials.append(side_mat)
    plinth_bevel = plinth.modifiers.new("Royal plinth bevel", "BEVEL")
    plinth_bevel.width = 0.014
    plinth_bevel.segments = 4
    plinth_bevel.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = plinth
    bpy.ops.object.modifier_apply(modifier=plinth_bevel.name)

    cylinder("Sovereign stone dais", 0.335, 0.075, 0.025, stone_mat, 0.012)

    # Two opposite-color inlays make the Sovereign's physical layers readable
    # from the playing camera: one at the foot of the crown itself and one near
    # the exposed lower edge of its tile-like plinth.
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.307,
        minor_radius=0.007,
        major_segments=128,
        minor_segments=12,
        location=(0, 0, 0.066),
    )
    crown_stripe = bpy.context.object
    crown_stripe.name = "Sovereign crown-base opposite-color pinstripe"
    crown_stripe.data.materials.append(stripe_mat)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.412,
        minor_radius=0.007,
        major_segments=128,
        minor_segments=12,
        location=(0, 0, -0.108),
    )
    plinth_stripe = bpy.context.object
    plinth_stripe.name = "Sovereign plinth-base opposite-color pinstripe"
    plinth_stripe.data.materials.append(stripe_mat)

    # Hollow stone band: the opening makes the object read as a crown from the
    # tabletop camera instead of as a tall decorated token.
    band = cylinder("Sovereign hollow stone crown band", 0.302, 0.145, 0.130, stone_mat, 0.012)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=128,
        radius=0.224,
        depth=0.190,
        location=(0, 0, 0.145),
    )
    cutter = bpy.context.object
    bpy.context.view_layer.objects.active = band
    hollow = band.modifiers.new("Open the royal crown", "BOOLEAN")
    hollow.operation = "DIFFERENCE"
    hollow.solver = "EXACT"
    hollow.object = cutter
    bpy.ops.object.modifier_apply(modifier=hollow.name)
    bpy.data.objects.remove(cutter, do_unlink=True)

    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.263,
        minor_radius=0.018,
        major_segments=128,
        minor_segments=16,
        location=(0, 0, 0.198),
    )
    upper_band = bpy.context.object
    upper_band.name = "Sovereign upper stone crown rail"
    upper_band.data.materials.append(stone_mat)

    # Six broad triangular plates echo the original crown icon. From the normal
    # playing angle, three pronounced triangles form the readable silhouette
    # instead of the previous cluster of needle-like cones.
    for index in range(6):
        angle = 2.0 * pi * float(index) / 6.0
        center = add_crown_prong(angle, stone_mat)
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=24,
            ring_count=12,
            radius=0.030,
            location=(center.x, center.y, 0.414),
        )
        jewel = bpy.context.object
        jewel.name = "Sovereign opposite-color spire tip"
        jewel.data.materials.append(stripe_mat)


def export_scene(path):
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_apply=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def build_table_surface():
    clear_scene()
    table = material("Walnut tabletop", (0.115, 0.043, 0.018), 0.45)
    bevel_box("Table", (0, 0, -0.28), (17.8, 11.8, 0.42), table, 0.18)
    export_scene(OUTPUT / "table_surface.glb")


def build_board():
    clear_scene()
    frame = material("Dark walnut frame", (0.075, 0.026, 0.011), 0.38)
    frame_edge = material("Warm frame edge", (0.205, 0.077, 0.025), 0.42)
    brass = material("Aged brass", (0.64, 0.355, 0.085), 0.24, 0.86)
    board_base = material("Board backing", (0.025, 0.022, 0.019), 0.58)
    light = material("Maple square", (0.63, 0.405, 0.175), 0.49)
    dark = material("Walnut square", (0.235, 0.125, 0.070), 0.50)
    neutral_light = material("Faded maple square", (0.67, 0.49, 0.275), 0.53)
    neutral_dark = material("Faded walnut square", (0.315, 0.205, 0.135), 0.55)
    bevel_box("Board backing", (0, 0, 0.02), (10.35, 10.35, 0.28), board_base, 0.10)

    for row in range(9):
        for column in range(9):
            square_mat = light if (row + column) % 2 == 0 else dark
            if 3 <= row <= 5:
                square_mat = neutral_light if (row + column) % 2 == 0 else neutral_dark
            bevel_box(
                f"Square_{column}_{row}",
                (column - 4, row - 4, 0.205),
                (0.992, 0.992, 0.085),
                square_mat,
                0.012,
            )

    for boundary_y in (-1.5, 1.5):
        bevel_box("Neutral field metal border", (0, boundary_y, 0.268), (9.0, 0.110, 0.032), brass, 0.012)

    for x in (-5.05, 5.05):
        bevel_box("Board frame vertical", (x, 0, 0.34), (0.56, 10.64, 0.50), frame, 0.09)
        bevel_box("Frame warm edge vertical", (x + (-0.20 if x < 0 else 0.20), 0, 0.60), (0.045, 10.35, 0.028), frame_edge, 0.01)
        bevel_box("Brass inlay vertical", (x + (0.20 if x < 0 else -0.20), 0, 0.605), (0.026, 9.86, 0.034), brass, 0.008)
    for y in (-5.05, 5.05):
        bevel_box("Board frame horizontal", (0, y, 0.34), (10.64, 0.56, 0.50), frame, 0.09)
        bevel_box("Frame warm edge horizontal", (0, y + (-0.20 if y < 0 else 0.20), 0.60), (10.35, 0.045, 0.028), frame_edge, 0.01)
        bevel_box("Brass inlay horizontal", (0, y + (0.20 if y < 0 else -0.20), 0.605), (9.86, 0.026, 0.034), brass, 0.008)

    export_scene(OUTPUT / "board.glb")


def build_player_tray():
    clear_scene()
    frame_edge = material("Warm frame edge", (0.205, 0.077, 0.025), 0.42)
    velvet = material("Deep black velvet upholstery", (0.008, 0.007, 0.006), 0.94)

    # The tray is designed from the 0.84-unit token diameter rather than from
    # decorative spacing. Three physically separate leather-lined bays fill
    # the same 9-square length as the board: Infantry sleeve, centered 2x5
    # reserve caddy, and two-row discard magazine.
    bevel_box("Infantry velvet bay", (0, 3.90, 0.02), (2.42, 1.34, 0.18), velvet, 0.10)
    bevel_box("Reserve velvet well", (0, 0.10, 0.02), (2.42, 6.05, 0.18), velvet, 0.10)
    bevel_box("Discard velvet well", (0, -3.94, 0.02), (2.42, 1.68, 0.18), velvet, 0.10)

    # Full perimeter plus structural dividers. The gaps between bays are now
    # real walls rather than accidental unused floor area.
    for y in (4.86, 3.18, -3.03, -4.86):
        bevel_box("Tray rail horizontal", (0, y, 0.29), (2.86, 0.28, 0.48), frame_edge, 0.06)
    for side_x in (-1.29, 1.29):
        bevel_box("Tray rail vertical", (side_x, 0, 0.29), (0.28, 9.86, 0.48), frame_edge, 0.06)

    # Ten non-Infantry storage wells: two columns of five. Four low L-shaped
    # corner stops make every location a real retaining pocket rather than a
    # printed placement guide.
    for slot_y in (2.45, 1.30, 0.15, -1.00, -2.15):
        for slot_x in (-0.58, 0.58):
            for x_sign in (-1, 1):
                for y_sign in (-1, 1):
                    corner_x = slot_x + x_sign * 0.395
                    corner_y = slot_y + y_sign * 0.395
                    bevel_box(
                        "Reserve pocket corner",
                        (corner_x - x_sign * 0.040, corner_y, 0.205),
                        (0.16, 0.075, 0.19),
                        velvet,
                        0.018,
                    )
                    bevel_box(
                        "Reserve pocket corner",
                        (corner_x, corner_y - y_sign * 0.040, 0.205),
                        (0.075, 0.16, 0.19),
                        velvet,
                        0.018,
                    )

    def add_chip_sleeve(name, center_y):
        # A real U-shaped magazine: its front and rear lips sit just above the
        # centerline of an upright token, obscuring about half of the side while
        # the face remains readable. End stops keep the nested roll captive.
        bevel_box(f"{name} velvet cushion", (0, center_y, 0.125), (2.12, 0.92, 0.16), velvet, 0.055)
        for rail_y in (center_y - 0.475, center_y + 0.475):
            bevel_box(f"{name} velvet bolster", (0, rail_y, 0.305), (2.16, 0.105, 0.52), velvet, 0.045)
        for end_x in (-1.08, 1.08):
            bevel_box(f"{name} velvet arm", (end_x, center_y, 0.305), (0.105, 1.06, 0.52), velvet, 0.045)

    add_chip_sleeve("Infantry", 3.88)
    add_chip_sleeve("Discard row one", -3.53)
    add_chip_sleeve("Discard row two", -4.28)

    export_scene(OUTPUT / "player_tray.glb")


def build_token(filename, dark=False, icon="infantry"):
    clear_scene()
    if dark:
        body = material("Polished obsidian crown", (0.009, 0.012, 0.016), 0.10)
        side = material("Polished obsidian skirt", (0.004, 0.006, 0.008), 0.12)
        face = material("Obsidian engraved field", (0.014, 0.019, 0.025), 0.09)
        inlay = material("Ivory enamel relief", (0.92, 0.90, 0.84), 0.28, 0.0)
    else:
        body = material("Polished white marble crown", (0.79, 0.78, 0.74), 0.12)
        side = material("Polished white marble skirt", (0.68, 0.67, 0.63), 0.14)
        face = material("White marble engraved field", (0.86, 0.85, 0.81), 0.11)
        inlay = material("Black enamel relief", (0.008, 0.009, 0.011), 0.30, 0.0)

    # This narrow contrasting inlay lives in the exposed half of the lower
    # skirt. Because tiles nest by half their height, one stripe remains visible
    # for every physical layer in a stack without changing the tile silhouette.
    stack_stripe = (
        material("Ivory enamel stack stripe", (0.70, 0.69, 0.64), 0.31, 0.0)
        if dark
        else material("Black enamel stack stripe", (0.055, 0.060, 0.065), 0.34, 0.0)
    )

    # The Sovereign is intentionally not a tile. Its tall, open crown silhouette
    # makes its unstackable royal role legible before the player reads an icon.
    if icon == "sovereign":
        sovereign_crown_piece(side, body, inlay)
        export_scene(OUTPUT / filename)
        return

    bottle_cap_body("Nesting bottle-cap body", side, body)
    # Charcoal loses more apparent width against the white marble's own veining
    # and contact shadow, so the white-piece inlay sits slightly higher and is
    # modestly wider. The successful ivory-on-obsidian treatment stays finer.
    stripe_z = -0.105 if dark else -0.085
    stripe_radius = 0.416 if dark else 0.413
    stripe_width = 0.006 if dark else 0.009
    bpy.ops.mesh.primitive_torus_add(
        major_radius=stripe_radius,
        minor_radius=stripe_width,
        major_segments=128,
        minor_segments=10,
        location=(0, 0, stripe_z),
    )
    stripe = bpy.context.object
    stripe.name = "Opposite-color stack-count inlay"
    stripe.data.materials.append(stack_stripe)
    immobile = icon in ("spy", "trebuchet", "ballista")
    special = icon in ("reinforcement", "recall")
    if dark:
        inverse_icon = material("Black enamel inverse relief", (0.008, 0.009, 0.011), 0.30, 0.0)
    else:
        inverse_icon = material("Ivory enamel inverse relief", (0.92, 0.90, 0.84), 0.28, 0.0)
    immobile_field = material("Neutral gray enamel immobile field", (0.11, 0.13, 0.16), 0.27, 0.0)
    field_material = immobile_field if immobile else face
    icon_material = inverse_icon if immobile else inlay
    cylinder("Recessed engraved field", 0.296, 0.010, 0.149, field_material, 0.004)
    if special:
        add_dotted_perimeter(inlay)
    else:
        bpy.ops.mesh.primitive_torus_add(
            major_radius=0.276,
            minor_radius=0.005,
            major_segments=128,
            minor_segments=12,
            location=(0, 0, 0.155),
        )
        ring = bpy.context.object
        ring.name = "Embossed circular ring"
        ring.data.materials.append(immobile_field if immobile else inlay)

    if icon == "marshal":
        add_star_icon(inlay)
    elif icon == "infantry":
        PREMIUM.icon_geometry(icon, inlay, z=0.164, depth=0.012, scale=0.30)
    elif icon in TOKEN_KINDS:
        icon_objects = PREMIUM.icon_geometry(icon, icon_material, z=0.164, depth=0.012, scale=0.30)
        if icon == "trebuchet":
            # The Trebuchet teaches its diagonal firing direction everywhere
            # this model is used: board, reserve, discard, and caddy emblem.
            icon_root = bpy.data.objects.new("Diagonal Trebuchet mark", None)
            bpy.context.scene.collection.objects.link(icon_root)
            for icon_object in icon_objects:
                icon_object.parent = icon_root
            icon_root.rotation_euler.z = pi / 4
    export_scene(OUTPUT / filename)


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if "--tray-only" in sys.argv:
        build_player_tray()
    elif "--tokens-only" in sys.argv:
        for dark, color_name in ((False, "white"), (True, "black")):
            build_token(f"token_{color_name}.glb", dark=dark, icon="none")
            for icon in TOKEN_KINDS:
                build_token(f"token_{color_name}_{icon}.glb", dark=dark, icon=icon)
    else:
        build_table_surface()
        build_board()
        build_player_tray()
        for dark, color_name in ((False, "white"), (True, "black")):
            build_token(f"token_{color_name}.glb", dark=dark, icon="none")
            for icon in TOKEN_KINDS:
                build_token(f"token_{color_name}_{icon}.glb", dark=dark, icon=icon)
    print(f"Generated T3RNARY tabletop POC assets in {OUTPUT}")
