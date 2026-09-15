"""
Rend un modele (FBX ou GLB) de trois quarts, cadre automatiquement.

    blender --background --python tools/render-model.py -- <modele> <sortie.png> [largeur]

Sert a comparer des maillages d'origines differentes (Meshy, TRELLIS) avant
de choisir. Workbench, lumiere studio, textures telles quelles.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
source, dest = argv[0], argv[1]
width = int(argv[2]) if len(argv) > 2 else 960

bpy.ops.wm.read_factory_settings(use_empty=True)
if source.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=source)
else:
    bpy.ops.import_scene.gltf(filepath=source)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = width
scene.render.resolution_y = width // 2
scene.world = bpy.data.worlds.new("World")

meshes = [o for o in scene.objects if o.type == "MESH"]
corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
center = (lo + hi) / 2
radius = max((hi - lo).length / 2, 1e-3)

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 50
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
direction = Vector((-1.0, -1.1, 0.55)).normalized()
cam.location = center + direction * radius * 2.6
cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = dest
bpy.ops.render.render(write_still=True)
faces = sum(len(o.data.polygons) for o in meshes)
print(f"ok {os.path.basename(source)}: {len(meshes)} objet(s), {faces} faces, taille {tuple(round(v, 3) for v in (hi - lo))}")
