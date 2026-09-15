"""
Rend un apercu d'un maillage, pour voir ce qu'on vient de recevoir.

    blender --background --python tools/model-preview.py -- <fichier> <sortie.png>

Accepte .obj, .glb, .gltf et .fbx. Le maillage est decime pour que le rendu
tienne en quelques secondes — on cherche a reconnaitre l'objet, pas a en
juger le detail.
"""
import os
import sys
import math

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    raise SystemExit("usage: model-preview.py -- <fichier> <sortie.png>")
source, target = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
lower = source.lower()
if lower.endswith(".obj"):
    bpy.ops.wm.obj_import(filepath=source)
elif lower.endswith(".glb") or lower.endswith(".gltf"):
    bpy.ops.import_scene.gltf(filepath=source)
else:
    bpy.ops.import_scene.fbx(filepath=source)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not meshes:
    raise SystemExit("aucun maillage")
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

faces = len(body.data.polygons)
if faces > 40000:
    modifier = body.modifiers.new("Decimate", "DECIMATE")
    modifier.ratio = 40000 / faces
    bpy.ops.object.modifier_apply(modifier=modifier.name)

# Cadrage : la camera recule jusqu'a contenir la boite englobante.
corners = [body.matrix_world @ Vector(c) for c in body.bound_box]
low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
centre = (low + high) / 2
reach = max(high.x - low.x, high.y - low.y, high.z - low.z)

camera_data = bpy.data.cameras.new("Camera")
camera = bpy.data.objects.new("Camera", camera_data)
bpy.context.scene.collection.objects.link(camera)
bpy.context.scene.camera = camera
direction = Vector((0.9, -1.4, 0.55)).normalized()
camera.location = centre + direction * reach * 1.9
look = centre - camera.location
camera.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()

light_data = bpy.data.lights.new("Sun", type="SUN")
light_data.energy = 4
light = bpy.data.objects.new("Sun", light_data)
light.location = centre + Vector((reach, -reach, reach * 2))
light.rotation_euler = (math.radians(45), 0, math.radians(35))
bpy.context.scene.collection.objects.link(light)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = 900
scene.render.resolution_y = 620
scene.render.film_transparent = False
scene.render.filepath = target
bpy.ops.render.render(write_still=True)
print("apercu %s : %d faces, ecrit %s" % (os.path.basename(source), faces, target))
