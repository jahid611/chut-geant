"""
Lisse un GLB avant l'import Roblox, sans ajouter de triangles.

    blender --background --python tools/smooth-glb.py -- <entree.glb> <sortie.glb> [mode] [angle] [force]

mode   : "normales" (defaut) — ombrage lisse par angle : les facettes disparaissent a la lumiere,
         les aretes plus vives que `angle` degres (defaut 40) restent nettes. Forme et UV inchangees.
         "forme" — idem, plus un lissage geometrique leger (Corrective Smooth, `force` 0..1, defaut 0.5,
         10 iterations) qui efface les petites bosses tout en preservant le volume. Les UV suivent les
         sommets, la texture ne glisse pas.

Le nombre de triangles ne change pas : Roblox plafonne une MeshPart a 10 000.
"""
import math
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
source, dest = argv[0], argv[1]
mode = argv[2] if len(argv) > 2 else "normales"
angle = float(argv[3]) if len(argv) > 3 else 40.0
force = float(argv[4]) if len(argv) > 4 else 0.5

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)

for obj in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    if mode == "forme":
        smooth = obj.modifiers.new("lissage", "CORRECTIVE_SMOOTH")
        smooth.factor = force
        smooth.iterations = 10
        smooth.use_only_smooth = False
        smooth.rest_source = "ORCO"
        bpy.ops.object.modifier_apply(modifier="lissage")

    # Ombrage lisse par angle (Blender 4.1+), avec repli sur l'ombrage lisse simple.
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle), keep_sharp_edges=True)
    except Exception:
        bpy.ops.object.shade_smooth()
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"lisse {obj.name} mode={mode} angle={angle} triangles={tris}")

bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB", export_normals=True)
print(f"ok {dest}")
