"""Renders a boost's model (the Sun Crown's Art/Models/Crown/sun_crown.glb, or another in Art/Models/Boosts) from the
front for its banner (KillFeed), where it sits on the taker's portrait, and the HUD's boost pill: transparent, lit
warm from the front and above, cut to its edges and outlined in the UI's dark edge.

    /Applications/Blender.app/Contents/MacOS/Blender -b -P Tools/render_crown_icon.py -- <out.png> [turn] [tilt] \
        [model.glb] [metallic] [lean] [saturation]

`turn` spins the model about its upright axis (degrees, to bring its front to the camera), `tilt` is how far the
camera looks down on it (degrees), `metallic` how much it shines as metal (0.75, the crown's polished gold), `lean`
how far its top leans to the right (degrees; the Wind Feather leans as in its concept) and `saturation` how strong its
colours are (1 as rendered).
"""

import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parent.parent
SIZE = 512
# The dark edge round it, in pixels, and its colour (UiStyle.Colors.Edge).
OUTLINE = 9
EDGE = [c / 255 for c in (70, 42, 20)]

args = sys.argv[sys.argv.index("--") + 1 :]
out = Path(args[0]).resolve()
turn = float(args[1]) if len(args) > 1 else 0.0
tilt = float(args[2]) if len(args) > 2 else 8.0
model = Path(args[3]).resolve() if len(args) > 3 else ROOT / "Art/Models/Crown/sun_crown.glb"
metallic = float(args[4]) if len(args) > 4 else 0.75
lean = float(args[5]) if len(args) > 5 else 0.0
saturation = float(args[6]) if len(args) > 6 else 1.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(model))
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
# The model's colours with a polished shine, as metal as `metallic` says.
for o in meshes:
    o.data.shade_smooth()
    for slot in o.material_slots:
        shader = slot.material and slot.material.node_tree.nodes.get("Principled BSDF")
        if shader:
            shader.inputs["Metallic"].default_value = metallic
            shader.inputs["Roughness"].default_value = 0.3

pivot = bpy.data.objects.new("Pivot", None)
bpy.context.scene.collection.objects.link(pivot)
for o in bpy.context.scene.objects:
    if o.parent is None and o is not pivot:
        o.parent = pivot
pivot.matrix_world = Matrix.Rotation(math.radians(lean), 4, "Y") @ Matrix.Rotation(math.radians(turn), 4, "Z")
bpy.context.view_layer.update()

corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
middle = (low + high) / 2
reach = max(high.x - low.x, high.z - low.z) * 0.56

scene = bpy.context.scene
camera_data = bpy.data.cameras.new("Camera")
camera_data.type = "ORTHO"
camera_data.ortho_scale = reach * 2
camera = bpy.data.objects.new("Camera", camera_data)
scene.collection.objects.link(camera)
away = Vector((0, -math.cos(math.radians(tilt)), math.sin(math.radians(tilt)))) * 10
camera.location = middle + away
camera.rotation_euler = (-away).to_track_quat("-Z", "Y").to_euler()
scene.camera = camera


def light(name: str, kind: str, energy: float, colour, direction: Vector):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = colour
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = middle + direction * 8
    obj.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    if kind == "SUN":
        data.angle = math.radians(30)


light("Key", "SUN", 3.2, (1.0, 0.92, 0.78), Vector((-0.5, -1, 1.1)).normalized())
light("Fill", "SUN", 1.2, (1.0, 0.85, 0.65), Vector((0.8, -0.6, 0.2)).normalized())
light("Rim", "SUN", 2.0, (1.0, 0.95, 0.85), Vector((0.2, 1, 0.8)).normalized())

# A warm studio for the metal to mirror: bright above, dark below.
world = bpy.data.worlds.new("World")
world.use_nodes = True
nodes, links = world.node_tree.nodes, world.node_tree.links
coords = nodes.new("ShaderNodeTexCoord")
split = nodes.new("ShaderNodeSeparateXYZ")
ramp = nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.35
ramp.color_ramp.elements[0].color = (0.08, 0.05, 0.03, 1)
ramp.color_ramp.elements[1].position = 0.75
ramp.color_ramp.elements[1].color = (1.0, 0.9, 0.72, 1)
remap = nodes.new("ShaderNodeMapRange")
remap.inputs["From Min"].default_value = -1
links.new(coords.outputs["Generated"], split.inputs[0])
links.new(split.outputs["Z"], remap.inputs["Value"])
links.new(remap.outputs["Result"], ramp.inputs["Fac"])
links.new(ramp.outputs["Color"], nodes["Background"].inputs["Color"])
nodes["Background"].inputs["Strength"].default_value = 1.4
scene.world = world

scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {
    e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items
} else "BLENDER_EEVEE"
scene.render.film_transparent = True
scene.render.resolution_x = SIZE
scene.render.resolution_y = SIZE
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"
scene.render.filepath = str(out)
bpy.ops.render.render(write_still=True)

# Cut to the crown and edge it as the UI edges its frames and lettering (UiStyle.Colors.Edge).
image = bpy.data.images.load(str(out))
width, height = image.size
pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)
alpha = pixels[:, :, 3]
rows, cols = np.nonzero(alpha > 0.02)
pad = OUTLINE + 4
top, bottom = max(rows.min() - pad, 0), min(rows.max() + pad + 1, height)
left, right = max(cols.min() - pad, 0), min(cols.max() + pad + 1, width)
crown = pixels[top:bottom, left:right]
grey = (crown[:, :, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32))[:, :, None]
crown[:, :, :3] = np.clip(grey + (crown[:, :, :3] - grey) * saturation, 0, 1)
shape = crown[:, :, 3]
grown = shape.copy()
for dy in range(-OUTLINE, OUTLINE + 1):
    for dx in range(-OUTLINE, OUTLINE + 1):
        if dx * dx + dy * dy <= OUTLINE * OUTLINE:
            grown = np.maximum(grown, np.roll(np.roll(shape, dy, 0), dx, 1))
edged = np.zeros_like(crown)
edged[:, :, :3] = EDGE
edged[:, :, 3] = grown
over = crown[:, :, 3:4]
edged[:, :, :3] = crown[:, :, :3] * over + edged[:, :, :3] * (1 - over)
cut = bpy.data.images.new("Cut", right - left, bottom - top, alpha=True)
cut.pixels[:] = edged.ravel()
cut.filepath_raw = str(out)
cut.file_format = "PNG"
cut.save()
print(f"rendered {out} ({right - left}x{bottom - top})")
