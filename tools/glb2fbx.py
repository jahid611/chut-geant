"""
Convertit des GLB en FBX autoportants, pour l'import Roblox.

    blender --background --python glb2fbx.py -- <dossier_glb> <dossier_fbx> [miroir]

miroir : retourne le modele sur X avant l'export (echelle -1 appliquee). Utile seulement pour
obtenir une version symetrique d'un modele. Attention : l'import Roblox ne met PAS les modeles
en miroir — l'essai sur le texte « Happy baby » du berceau l'a montre (texte toujours inverse).

Roblox n'avale pas le glTF par Open Cloud : son API d'assets attend du FBX
pour un Model. Les textures sont donc embarquees dans le fichier
(path_mode COPY + embed_textures), sinon l'import arrive nu et il faut
rebrancher trois cartes a la main sur chaque creature.

Une seule session Blender pour tout le dossier : demarrer le programme coute
plus cher que la conversion elle-meme.
"""
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
srcdir, outdir = argv[0], argv[1]
mirror = len(argv) > 2 and argv[2] == "miroir"
os.makedirs(outdir, exist_ok=True)

for fn in sorted(os.listdir(srcdir)):
    if not fn.lower().endswith(".glb"):
        continue
    dest = os.path.join(outdir, os.path.splitext(fn)[0] + ".fbx")
    if os.path.exists(dest):
        print("deja", fn)
        continue

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(srcdir, fn))

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        print("VIDE", fn)
        continue

    # Roblox travaille en studs et lit le FBX en centimetres. Le modele arrive
    # normalise autour d'une unite ; on le laisse tel quel et on reglera la
    # taille dans Studio, ou elle depend du socle.
    if mirror:
        # Echelle -1 sur X appliquee au maillage. Blender corrige lui-meme l'ordre des sommets en appliquant une
        # echelle negative : ne PAS retourner les normales en plus (verifie, le berceau sortait a l'envers, vu de dedans).
        for obj in meshes:
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            obj.scale.x *= -1
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        print("miroir", fn)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(
        filepath=dest,
        use_selection=False,
        path_mode="COPY",
        embed_textures=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_space_transform=False,
    )
    print("converti", fn, "->", os.path.basename(dest))
