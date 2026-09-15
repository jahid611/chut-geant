"""
Efface un logo imprime (texte clair) sur une etiquette coloree d'un GLB Tripo. On donne des rectangles SERRES
autour des lettres : dans chacun, tout pixel clair et peu sature prend la couleur mediane de l'etiquette
(pixels corail du meme rectangle). Rien d'autre ne change.
Essais rejetes : seuil rouge global (attrapait l'orange), rouge trop sombre (silhouette visible), masque
« entoure d'etiquette » (ne couvrait que le contour des lettres).

    blender --background --python tools/recolor-logo.py -- <entree.glb> <sortie.glb> <dossier_apercus> x0,y0,x1,y1 [...]

Rectangles en pixels de la texture, origine en haut a gauche comme dans un apercu PNG.
"""
import os
import sys
import numpy as np
import bpy

args = sys.argv[sys.argv.index("--") + 1:]
src, dest, preview_dir = args[0], args[1], args[2]
# Mode facultatif avant les rectangles : « texte » (defaut, texte clair sur etiquette corail) ou « tache » (logo rouge
# et blanc pose sur une matiere unie, ex. le cheval bleu : tout ce qui est rouge ou blanc prend la couleur mediane
# du reste du rectangle).
mode = "texte"
if len(args) > 3 and args[3] in ("texte", "tache"):
    mode = args[3]
    args = args[:3] + args[4:]
rects = [tuple(int(v) for v in a.split(",")) for a in args[3:]]
os.makedirs(preview_dir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
color_img = None
for mat in bpy.data.materials:
    if mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                link = node.inputs["Base Color"].links
                if link and link[0].from_node.type == "TEX_IMAGE":
                    color_img = link[0].from_node.image
if color_img is None:
    raise SystemExit("pas de texture de couleur")

w, h = color_img.size
px = np.array(color_img.pixels[:], dtype=np.float32).reshape(h, w, 4)

normal_img = next((im for im in bpy.data.images if "normal" in im.name.lower() and tuple(im.size) == (w, h)), None)
normal_px = (
    np.array(normal_img.pixels[:], dtype=np.float32).reshape(h, w, 4) if normal_img is not None else None
)

def box_mean(a, k):
    # moyenne glissante (fenetre (2k+1)^2) par sommes cumulees
    pad = np.pad(a, k, mode="edge")
    c = np.pad(pad.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    n = 2 * k + 1
    return (c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]) / (n * n)


def close_mask(mask, k):
    dilated = box_mean(mask.astype(np.float32), k) > 0.001
    return box_mean((~dilated).astype(np.float32), k) < 0.001


def crop_save(name, x0, y0, x1, y1, data, margin=40):
    xa, ya, xb, yb = max(x0 - margin, 0), max(y0 - margin, 0), min(x1 + margin, w), min(y1 + margin, h)
    top, bottom = h - yb, h - ya
    sub = data[top:bottom, xa:xb].copy()
    img = bpy.data.images.new(name, xb - xa, yb - ya, alpha=True)
    img.pixels[:] = sub.ravel()
    img.scale((xb - xa) * 4, (yb - ya) * 4)
    img.filepath_raw = os.path.join(preview_dir, name + ".png")
    img.file_format = "PNG"
    img.save()

for i, (x0, y0, x1, y1) in enumerate(rects):
    crop_save(f"v4-logo{i}-avant", x0, y0, x1, y1, px)
    top, bottom = h - y1, h - y0
    region = px[top:bottom, x0:x1]
    r, g, b = region[..., 0], region[..., 1], region[..., 2]
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    whitish = (mx > 0.62) & (sat < 0.32)
    if mode == "tache":
        # rouge franc seulement : l'orange (g ~0,5) du jouet musical passait pour du rouge
        reddish = (r > 0.55) & (g < 0.38) & (b < 0.38)
        # Fermeture (dilatation puis erosion, 20 px) : bouche les lettres bleues imprimees DANS l'etiquette, sinon
        # elles restaient visibles en relief une fois le rouge et le blanc repeints (essai du cheval).
        paint = close_mask(whitish | reddish, 20)
        rest = ~paint
        if not rest.any():
            print(f"rectangle {i} : pas de fond, ignore")
            continue
        fill = np.median(region[rest][:, :3], axis=0)
        region[paint, 0], region[paint, 1], region[paint, 2] = fill
        # Le logo est aussi grave dans la carte de relief (ovale visible au rendu) : relief plat sous la zone,
        # elargie de 10 px pour attraper les bords de la gravure.
        if normal_px is not None:
            nregion = normal_px[top:bottom, x0:x1]
            flat = box_mean(paint.astype(np.float32), 10) > 0.001
            nregion[flat, 0], nregion[flat, 1], nregion[flat, 2] = 0.5, 0.5, 1.0
        print(f"rectangle {i} (tache) : {int(paint.sum())} px repeints en {fill.round(3)}")
        crop_save(f"v4-logo{i}-apres", x0, y0, x1, y1, px)
        continue
    coral = (r > 0.7) & (r - g > 0.3) & (r - b > 0.35)
    if not coral.any():
        print(f"rectangle {i} : pas d'etiquette, ignore")
        continue
    label = np.median(region[coral][:, :3], axis=0)
    region[whitish, 0], region[whitish, 1], region[whitish, 2] = label
    print(f"rectangle {i} : {int(whitish.sum())} px clairs repeints en {label.round(3)}")
    crop_save(f"v4-logo{i}-apres", x0, y0, x1, y1, px)

color_img.pixels[:] = px.ravel()
color_img.update()
color_img.pack()
if normal_img is not None and mode == "tache":
    normal_img.pixels[:] = normal_px.ravel()
    normal_img.update()
    normal_img.pack()
    print("relief aplani sous les zones repeintes")
bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
print("ok", dest)
