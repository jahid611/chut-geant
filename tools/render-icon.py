"""
Rend un modele 3D du jeu en icone PNG carree SANS FOND (alpha), textures comprises.

    blender --background --python tools/render-icon.py -- <modele.glb> <sortie.png> [taille=512] [yaw=-35]

Sert a garder un visuel unique par objet : l'icone du coffre est le rendu de notre coffre 3D, pas une image
generee a part (demande utilisateur). Eevee, fond transparent, lumiere douce de face, cadrage serre.
"""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
source, dest = argv[0], argv[1]
size = int(argv[2]) if len(argv) > 2 else 512
yaw = math.radians(float(argv[3])) if len(argv) > 3 else math.radians(-35)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
scene = bpy.context.scene
try:
    scene.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError:
    scene.render.engine = "BLENDER_EEVEE"
scene.render.film_transparent = True
scene.render.resolution_x = size
scene.render.resolution_y = size
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"

world = bpy.data.worlds.new("World")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
scene.world = world

meshes = [o for o in scene.objects if o.type == "MESH"]
corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
center = (lo + hi) / 2
radius = max((hi - lo).length / 2, 1e-3)

# glTF : l'avant du modele regarde -Y dans Blender ; camera devant, legerement de cote et au-dessus
direction = Vector((math.sin(yaw), -math.cos(yaw), 0.45)).normalized()
cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 85
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
# 4,8 rayons : a 3,4 le coffre et le nounours depassaient du cadre
cam.location = center + direction * radius * 4.8
cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()

key = bpy.data.lights.new("cle", "AREA")
key.energy = 600 * radius * radius
key.size = radius * 3
key_obj = bpy.data.objects.new("cle", key)
key_obj.location = center + Vector((radius * 2, -radius * 3, radius * 3))
key_obj.rotation_euler = (center - key_obj.location).to_track_quat("-Z", "Y").to_euler()
scene.collection.objects.link(key_obj)

scene.render.filepath = dest
bpy.ops.render.render(write_still=True)
print("ok", dest)
