"""
Ramene un GLB tres dense (Tripo sort ~2 millions de faces) sous le plafond Roblox
de 10 000 triangles par MeshPart, en gardant ses materiaux et textures.

    blender --background --python tools/decimate-glb.py -- <entree.glb> <sortie.glb> [faces=9500]

Decimation par effondrement d'aretes, en une passe par objet, au prorata de son
nombre de faces. La texture porte le detail visible ; la geometrie n'a qu'a garder
la silhouette. Les faces sont triangulees avant de compter, parce que Roblox compte
en triangles.
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
source, dest = argv[0], argv[1]
target = int(argv[2]) if len(argv) > 2 else 9500

bpy.ops.wm.read_factory_settings(use_empty=True)
# Tripo exporte en GLB ou en FBX (texture dans le dossier .fbm voisin) : on accepte les deux.
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
    share = target * triangles(obj) / max(total, 1)
    ratio = min(1.0, share / max(triangles(obj), 1))
    bpy.context.view_layer.objects.active = obj
    tri = obj.modifiers.new("tri", "TRIANGULATE")
    dec = obj.modifiers.new("dec", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = ratio
    dec.use_collapse_triangulate = True
    for name in ("tri", "dec"):
        bpy.ops.object.modifier_apply(modifier=name)

after = sum(triangles(o) for o in meshes)
print(f"apres : {after} triangles")

bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB", export_image_format="AUTO")
print(f"ok {dest}")
