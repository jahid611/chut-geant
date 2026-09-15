"""
Squelette de chat pour une vraie marche (demande utilisateur du 15/09 : « étudie l'anatomie réelle du chat, coupe-le en
parties : pattes, tête, cou, tronc »). Un seul maillage texturé (TRELLIS) reçoit une armature anatomique et des poids
automatiques, puis part en FBX : Roblox l'importe en MeshPart avec des Bones, animés par le code (marche à quatre temps).

    blender --background --python tools/rig-chat.py -- <chat.glb> <sortie.fbx> [apercu.png]

Repères d'anatomie (chat domestique debout, proportions mesurées sur le maillage) :
- digitigrade : il marche sur les doigts ; poignet (carpe) et jarret (tarse) sont hauts, pas au sol ;
- patte avant : épaule haute sur le flanc, coude vers l'arrière, poignet presque vertical, doigts vers l'avant ;
- patte arrière : hanche, genou (grasset) vers l'AVANT, jarret vers l'ARRIÈRE, métatarse long, doigts ;
- colonne souple en deux segments (lombaire, thoracique), cou court, tête, queue en trois segments.

Orientation détectée : axe long horizontal = longueur du corps ; le bout de la tête est le côté dont la tranche est la
plus haute, la queue le côté le plus fin. Le modèle est ramené tête vers -Y, dos vers +Z, pattes au sol à Z = 0.
"""
import math
import sys

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
source, dest = argv[0], argv[1]
preview = argv[2] if len(argv) > 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
cat = bpy.context.view_layer.objects.active
cat.name = "Chat"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# les parents vides de glTF gardent parfois une rotation : on détache et on applique
if cat.parent:
    cat.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def world_points(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def bounds(points):
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


points = world_points(cat)
lo, hi = bounds(points)
size = hi - lo
# glTF est Y-haut converti en Z-haut par l'import ; l'axe long horizontal est X ou Y
long_axis = 0 if size.x >= size.y else 1


def slice_height(fraction_lo, fraction_hi):
    a = lo[long_axis] + size[long_axis] * fraction_lo
    b = lo[long_axis] + size[long_axis] * fraction_hi
    selected = [p for p in points if a <= p[long_axis] <= b]
    return (max(p.z for p in selected) if selected else lo.z), len(selected)


low_height, low_count = slice_height(0.0, 0.15)
high_height, high_count = slice_height(0.85, 1.0)
# la tête est le bout le plus haut ; à hauteur égale, le plus dense (la queue est fine)
head_at_high = (high_height, high_count) > (low_height, low_count)

# Ramène le chat : tête vers -Y, centre au sol en 0, pattes à Z = 0.
angle = 0.0
if long_axis == 0:
    angle = math.pi / 2 if head_at_high else -math.pi / 2
else:
    angle = math.pi if head_at_high else 0.0
center = (lo + hi) / 2
cat.matrix_world = Matrix.Rotation(angle, 4, "Z") @ Matrix.Translation(Vector((-center.x, -center.y, -lo.z)))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
points = world_points(cat)
lo, hi = bounds(points)
size = hi - lo
print(f"chat : longueur {size.y:.3f} largeur {size.x:.3f} hauteur {size.z:.3f}, tête vers -Y")

# Mesures anatomiques sur le maillage : fin de la queue = partie arrière fine.
L, W, H = size.y, size.x, size.z
front = lo.y  # bout du nez
back = hi.y  # bout de la queue


def thickness_at(y0, y1):
    selected = [p for p in points if y0 <= p.y <= y1]
    if not selected:
        return 0.0
    return max(p.z for p in selected) - min(p.z for p in selected)


# balaie depuis l'arrière jusqu'à trouver le corps (épaisseur > 35 % de la hauteur) : c'est la base de la queue
tail_base_y = back
steps = 40
for i in range(steps):
    y1 = back - L * i / steps
    y0 = y1 - L / steps
    if thickness_at(y0, y1) > 0.35 * H:
        tail_base_y = y1
        break
body_length = tail_base_y - front
print(f"base de la queue à {tail_base_y:.3f}, corps {body_length:.3f}")


def body(u, z, x=0.0):
    """u : 0 = nez, 1 = base de la queue ; z en fraction de la hauteur ; x en fraction de la largeur."""
    return Vector((x * W, front + body_length * u, H * z))


bones = {
    # tronc (du bassin vers l'avant) et tête
    "Racine": (body(0.86, 0.58), body(0.62, 0.62), None),
    "ColonneLombaire": (body(0.62, 0.62), body(0.40, 0.66), "Racine"),
    "ColonneThoracique": (body(0.40, 0.66), body(0.22, 0.70), "ColonneLombaire"),
    "Cou": (body(0.22, 0.70), body(0.12, 0.82), "ColonneThoracique"),
    "Tete": (body(0.12, 0.82), body(0.0, 0.80), "Cou"),
    # queue en trois segments, de la base au bout
    "Queue1": (body(0.95, 0.60), body(0.95, 0.60) + Vector((0, (back - tail_base_y) / 3, 0.04 * H)), "Racine"),
}
tail_step = Vector((0, (back - tail_base_y) / 3, 0.04 * H))
bones["Queue2"] = (bones["Queue1"][1], bones["Queue1"][1] + tail_step, "Queue1")
bones["Queue3"] = (bones["Queue2"][1], bones["Queue2"][1] + tail_step, "Queue2")

for side, sx in (("G", 0.28), ("D", -0.28)):
    # patte avant (sous l'épaule, u = 0.26)
    bones[f"Epaule{side}"] = (body(0.24, 0.62, sx), body(0.30, 0.40, sx), "ColonneThoracique")
    bones[f"AvantBras{side}"] = (body(0.30, 0.40, sx), body(0.27, 0.12, sx), f"Epaule{side}")
    bones[f"PatteAvant{side}"] = (body(0.27, 0.12, sx), body(0.21, 0.0, sx), f"AvantBras{side}")
    # patte arrière (sous la hanche, u = 0.82) : genou vers l'avant, jarret vers l'arrière
    bones[f"Cuisse{side}"] = (body(0.82, 0.60, sx), body(0.74, 0.38, sx), "Racine")
    bones[f"Jambe{side}"] = (body(0.74, 0.38, sx), body(0.86, 0.18, sx), f"Cuisse{side}")
    bones[f"Metatarse{side}"] = (body(0.86, 0.18, sx), body(0.82, 0.03, sx), f"Jambe{side}")
    bones[f"PatteArriere{side}"] = (body(0.82, 0.03, sx), body(0.77, 0.0, sx), f"Metatarse{side}")

bpy.ops.object.armature_add(location=(0, 0, 0))
armature = bpy.context.view_layer.objects.active
armature.name = "SqueletteChat"
bpy.ops.object.mode_set(mode="EDIT")
edit_bones = armature.data.edit_bones
edit_bones.remove(edit_bones[0])
for name, (head, tail, _parent) in bones.items():
    bone = edit_bones.new(name)
    bone.head = head
    bone.tail = tail
for name, (_head, _tail, parent) in bones.items():
    if parent:
        edit_bones[name].parent = edit_bones[parent]
        edit_bones[name].use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

# poids automatiques (chaleur des os) ; repli sur les enveloppes si le maillage n'est pas étanche
bpy.ops.object.select_all(action="DESELECT")
cat.select_set(True)
armature.select_set(True)
bpy.context.view_layer.objects.active = armature
try:
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    mode = "automatique"
except RuntimeError:
    bpy.ops.object.parent_set(type="ARMATURE_ENVELOPE")
    mode = "enveloppes"
empty_groups = [g.name for g in cat.vertex_groups if not any(g.index in [x.group for x in v.groups] for v in cat.data.vertices[:2000])]
print(f"poids {mode} ; {len(cat.vertex_groups)} groupes")

if preview:
    # pose d'essai : un pas de marche, pour vérifier que chaque patte plie au bon endroit
    bpy.ops.object.mode_set(mode="POSE")
    pose = armature.pose.bones
    pose["EpauleG"].rotation_mode = "XYZ"
    pose["EpauleG"].rotation_euler = (math.radians(-25), 0, 0)
    pose["AvantBrasG"].rotation_mode = "XYZ"
    pose["AvantBrasG"].rotation_euler = (math.radians(35), 0, 0)
    pose["CuisseD"].rotation_mode = "XYZ"
    pose["CuisseD"].rotation_euler = (math.radians(25), 0, 0)
    pose["JambeD"].rotation_mode = "XYZ"
    pose["JambeD"].rotation_euler = (math.radians(-30), 0, 0)
    pose["Queue2"].rotation_mode = "XYZ"
    pose["Queue2"].rotation_euler = (math.radians(20), 0, math.radians(15))
    bpy.ops.object.mode_set(mode="OBJECT")
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 768
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("Fond")
    world.color = (0.85, 0.87, 0.9)
    scene.world = world
    bpy.ops.object.light_add(type="SUN", location=(3, -3, 5))
    bpy.context.view_layer.objects.active.data.energy = 3.5
    bpy.ops.object.camera_add(location=(L * 2.2, -L * 0.2, H * 0.9))
    camera = bpy.context.view_layer.objects.active
    direction = Vector((0, body_length * 0.5 + front, H * 0.45)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.filepath = preview
    bpy.ops.render.render(write_still=True)
    # remet la pose de repos avant l'export
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.transforms_clear()
    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"aperçu {preview}")

bpy.ops.object.select_all(action="DESELECT")
cat.select_set(True)
armature.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=dest,
    use_selection=True,
    object_types={"ARMATURE", "MESH"},
    add_leaf_bones=False,
    bake_anim=False,
    path_mode="COPY",
    embed_textures=True,
    axis_forward="-Z",
    axis_up="Y",
)
print(f"ok {dest} ({len(bones)} os)")
