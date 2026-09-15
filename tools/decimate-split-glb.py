"""
Modele vu de tres pres (jumpscare) : decimation moins forte que decimate-glb.py, puis decoupe en morceaux
sous le plafond Roblox de 10 000 triangles par MeshPart. Un seul modele a televerser, plusieurs MeshParts.

    blender --background --python tools/decimate-split-glb.py -- <entree.fbx|glb> <sortie.glb> [total=48000] [morceau=9500]

A 9 500 triangles pour tout le buste, la maman en colere montrait facettes et coutures de texture dechirees en gros
plan (capture du 15/09) alors qu'elle etait propre de loin. La decoupe se fait APRES la decimation : les sommets des
bords ne bougent plus, donc aucune fente entre les morceaux. Partage recursif au milieu de l'axe le plus long.
"""
import sys

import bmesh
import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
source, dest = argv[0], argv[1]
total_target = int(argv[2]) if len(argv) > 2 else 48000
chunk = int(argv[3]) if len(argv) > 3 else 9500

bpy.ops.wm.read_factory_settings(use_empty=True)
if source.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=source)
else:
    bpy.ops.import_scene.gltf(filepath=source)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]


def triangles(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


total = sum(triangles(o) for o in meshes)
print(f"avant : {len(meshes)} maillage(s), {total} triangles")

for obj in meshes:
    bpy.context.view_layer.objects.active = obj
    obj.modifiers.new("tri", "TRIANGULATE")
    dec = obj.modifiers.new("dec", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = min(1.0, total_target / max(total, 1))
    dec.use_collapse_triangulate = True
    for name in ("tri", "dec"):
        bpy.ops.object.modifier_apply(modifier=name)


def split(obj):
    count = len(obj.data.polygons)
    if count <= chunk:
        return [obj]
    centers = [p.center.copy() for p in obj.data.polygons]
    groups = []

    def part(indices):
        if len(indices) <= chunk:
            groups.append(indices)
            return
        points = [centers[i] for i in indices]
        spans = [max(c[k] for c in points) - min(c[k] for c in points) for k in range(3)]
        axis = max(range(3), key=lambda k: spans[k])
        indices = sorted(indices, key=lambda i: centers[i][axis])
        half = len(indices) // 2
        part(indices[:half])
        part(indices[half:])

    part(list(range(count)))
    pieces = []
    for number, group in enumerate(groups, start=1):
        keep = set(group)
        piece = obj.copy()
        piece.data = obj.data.copy()
        piece.name = f"{obj.name}_{number}"
        piece.data.name = piece.name
        bpy.context.scene.collection.objects.link(piece)
        bm = bmesh.new()
        bm.from_mesh(piece.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
        bm.to_mesh(piece.data)
        bm.free()
        pieces.append(piece)
    bpy.data.objects.remove(obj, do_unlink=True)
    return pieces


pieces = []
for obj in meshes:
    pieces.extend(split(obj))

print(f"apres : {sum(triangles(o) for o in pieces)} triangles en {len(pieces)} morceau(x), "
      f"le plus gros {max(triangles(o) for o in pieces)}")

bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB", export_image_format="AUTO")
print(f"ok {dest}")
