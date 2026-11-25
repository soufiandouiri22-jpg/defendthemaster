"""Closes the knight statue's visor slit, the small hole Meshy made between its two eyes (owner, 2026-11-25), so the
visor has two eye holes and nothing else:

    blender -b -P Tools/statue_slit.py -- Art/Models/Colosseum/statue.glb Art/Models/Colosseum/statue_two_eyes.glb

The slit goes through the visor's plate: its four side walls (8 triangles) are deleted, the vertices round it merged
so the plate's outer and inner rims close into loops, and each rim filled, the outer one flush with the visor. The
patch takes its texture from the middle of the visor face beside the slit, metal of the same plate (an affine map
from the visor's plane to that face's UVs), so the texture itself stays as Meshy painted it. Every other corner keeps
its own custom normal; the patch's corners take the normals of the visor round them, so it is lit as the visor is.
"""

import sys

import bmesh
import bpy
from mathutils import Vector

src, out = sys.argv[sys.argv.index("--") + 1 :][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
o = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
me = o.data
mw = o.matrix_world
inv = mw.inverted()

# The slit as ColosseumBuilder measured it (Roblox mesh space, from the middle of the bounding box; Roblox's
# (x, y, z) is Blender's (-x, z, y)): its middle, and the visor's right, up and outward there.
pts = [mw @ v.co for v in me.vertices]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))


def blender(v):
    return Vector((-v[0], v[2], v[1]))


C = (lo + hi) / 2 + blender((-0.0001, 0.5366, -0.1231))
R = blender((-0.9372, 0, 0.3489)).normalized()
U = blender((0.0061, 0.9999, 0.0165)).normalized()
B = blender((-0.3488, 0.0176, -0.937)).normalized()
# The visor plate's outer surface lies this far out from the slit's middle, its inner one about half as far.
OUTER = 0.024


def local(p):
    d = p - C
    return d.dot(R), d.dot(U), d.dot(B)


def key(p):
    return tuple(round(x, 5) for x in p)


normals = {}
for poly in me.polygons:
    fc = key(mw @ poly.center)
    for li in poly.loop_indices:
        v = me.loops[li].vertex_index
        normals[(fc, key(mw @ me.vertices[v].co))] = me.corner_normals[li].vector.copy()

bm = bmesh.new()
bm.from_mesh(me)
bm.transform(mw)
uv = bm.loops.layers.uv.active
bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if (v.co - C).length < 0.06], dist=1e-5)

walls = []
for f in bm.faces:
    rs, us, ds = zip(*(local(v.co) for v in f.verts))
    if (
        abs(f.normal.dot(B)) < 0.3
        and -0.006 < min(rs)
        and max(rs) < 0.010
        and -0.019 < min(us)
        and max(us) < 0.019
        and min(ds) > 0.008
        and max(ds) < 0.027
    ):
        walls.append(f)
assert len(walls) == 8, f"expected the slit's 8 wall triangles, found {len(walls)}"

donor = None
for f in bm.faces:
    rs, us, ds = zip(*(local(v.co) for v in f.verts))
    if f.normal.dot(B) > 0.95 and min(ds) > 0.02 and -0.04 < min(rs) and max(rs) < -0.002 and min(us) < 0 < max(us):
        if donor is None or f.calc_area() > donor.calc_area():
            donor = f
assert donor is not None, "found no visor face beside the slit"
(r0, u0, _), (r1, u1, _), (r2, u2, _) = (local(loop.vert.co) for loop in donor.loops)
t0, t1, t2 = (loop[uv].uv.copy() for loop in donor.loops)
det = (r1 - r0) * (u2 - u0) - (r2 - r0) * (u1 - u0)


def affine(p):
    r, u, _ = local(p)
    a = ((r - r0) * (u2 - u0) - (r2 - r0) * (u - u0)) / det
    b = ((r1 - r0) * (u - u0) - (r - r0) * (u1 - u0)) / det
    return t0 + (t1 - t0) * a + (t2 - t0) * b


shift = (t0 + t1 + t2) / 3 - affine(C + B * OUTER)

bmesh.ops.delete(bm, geom=walls, context="FACES_ONLY")
rim = [e for e in bm.edges if e.is_boundary and all((v.co - C).length < 0.04 for v in e.verts)]
assert len(rim) == 8, f"expected the slit's two rims of 4 edges, found {len(rim)} edges"
filled = bmesh.ops.holes_fill(bm, edges=rim, sides=0)["faces"]
patch = bmesh.ops.triangulate(bm, faces=filled)["faces"]
for f in patch:
    f.normal_update()
    outward = min(local(v.co)[2] for v in f.verts) > OUTER * 0.75
    if (f.normal.dot(B) > 0) != outward:
        f.normal_flip()
    for loop in f.loops:
        loop[uv].uv = affine(loop.vert.co) + shift
    f.material_index = donor.material_index
    f.smooth = True
print("patch faces", len(patch))

bm.transform(inv)
bm.to_mesh(me)
bm.free()
me.update()

outward = (inv.to_3x3() @ B).normalized()
at_vertex = {}
for (_, vk), n in normals.items():
    at_vertex.setdefault(vk, []).append(n)
custom = []
for poly in me.polygons:
    fc = key(mw @ poly.center)
    for li in poly.loop_indices:
        vk = key(mw @ me.vertices[me.loops[li].vertex_index].co)
        n = normals.get((fc, vk))
        if n is None:
            side = 1 if poly.normal.dot(outward) > 0 else -1
            same = [m for m in at_vertex.get(vk, []) if m.dot(outward) * side > 0.8]
            n = (sum(same, Vector()) / len(same)).normalized() if same else poly.normal.copy()
        custom.append(n)
me.normals_split_custom_set(custom)

bpy.ops.export_scene.gltf(filepath=out, export_format="GLB")
print("wrote", out)
