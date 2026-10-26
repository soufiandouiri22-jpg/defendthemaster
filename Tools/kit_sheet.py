# Renders every GLB in a folder from the front three-quarter view and prints its size and triangle count.
# blender -b -P Tools/Blender/kit_sheet.py -- <folder> <out_folder>
import math
import os
import sys

import bpy
from mathutils import Vector

folder, out = sys.argv[sys.argv.index("--") + 1 :][:2]
os.makedirs(out, exist_ok=True)

for name in sorted(f for f in os.listdir(folder) if f.endswith(".glb")):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(folder, name))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    tris = 0
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    size = hi - lo
    center = (lo + hi) / 2
    print(f"KIT {name} size={tuple(round(v, 3) for v in size)} tris={tris} meshes={len(meshes)}")

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 480
    scene.render.resolution_y = 360
    world = bpy.data.worlds.new("w")
    world.color = (0.75, 0.75, 0.78)
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(size) * 1.25
    scene.collection.objects.link(cam)
    scene.camera = cam
    a = math.radians(-35)
    distance = max(size) * 3
    cam.location = center + Vector((math.sin(-a) * distance * 0.8, -math.cos(a) * distance, distance * 0.45))
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(out, name.replace(".glb", ".png"))
    bpy.ops.render.render(write_still=True)
