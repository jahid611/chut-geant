"""
Icônes fidèles aux modèles du jeu : on part d'un rendu Studio sur fond magenta (ViewportFrame), jamais d'une
simple description (retour utilisateur du 15/09 : l'épée des icônes ne ressemblait pas à l'épée du jeu, et le
détourage automatique trouait les icônes).

Python embarqué de ComfyUI (PIL + numpy) :
    python icone-depuis-rendu.py prep <rendu.jpg|png> <dossier> <nom>
        -> <nom>-ref.png (objet recadré au carré 1024, fond gris clair, pour FLUX img2img)
        -> <nom>-masque.png (silhouette exacte, blanc = objet)
    python icone-depuis-rendu.py planche <sortie.png> <image> [<image> ...]
        -> planche de vignettes 256 px avec le nom de chaque fichier
    python icone-depuis-rendu.py final <genere.png> <masque.png> <sortie.png> [taille=512]
        -> icône RGBA : l'image générée découpée par la silhouette du rendu (légèrement dilatée et adoucie),
           donc aucun trou au milieu de l'objet et aucun reste de fond
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

MAGENTA = np.array([255, 0, 255], dtype=np.float32)
BACKGROUND = (236, 238, 244)


def silhouette(image: Image.Image) -> np.ndarray:
    """Masque 0..1 de l'objet : distance au magenta, tolérante à la compression JPEG."""
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    distance = np.linalg.norm(rgb - MAGENTA, axis=2)
    alpha = np.clip((distance - 60.0) / 60.0, 0.0, 1.0)
    # Bouche les petits trous internes : un objet du jeu n'a pas de pixels magenta en son centre.
    mask = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    return np.asarray(mask, dtype=np.float32) / 255.0


def prep(render_path: str, folder: str, name: str) -> None:
    image = Image.open(render_path).convert("RGB")
    alpha = silhouette(image)
    ys, xs = np.nonzero(alpha > 0.5)
    if len(xs) == 0:
        raise SystemExit(f"aucun objet trouvé dans {render_path}")
    left, right, top, bottom = xs.min(), xs.max(), ys.min(), ys.max()
    side = int(max(right - left, bottom - top) * 1.18)
    cx, cy = (left + right) / 2, (top + bottom) / 2
    box = (int(cx - side / 2), int(cy - side / 2), int(cx + side / 2), int(cy + side / 2))

    rgb = np.asarray(image, dtype=np.float32)
    # Retire le reflet magenta des bords avant de poser l'objet sur le fond clair.
    spill = np.clip(np.minimum(rgb[:, :, 0], rgb[:, :, 2]) - rgb[:, :, 1], 0, None) * (1 - alpha) * 0.5
    rgb[:, :, 0] -= spill
    rgb[:, :, 2] -= spill
    background = np.array(BACKGROUND, dtype=np.float32)
    composite = rgb * alpha[..., None] + background * (1 - alpha[..., None])

    ref = Image.new("RGB", (side, side), BACKGROUND)
    ref.paste(Image.fromarray(np.clip(composite, 0, 255).astype(np.uint8)).crop(box), (0, 0))
    mask = Image.new("L", (side, side), 0)
    mask.paste(Image.fromarray((alpha * 255).astype(np.uint8)).crop(box), (0, 0))

    os.makedirs(folder, exist_ok=True)
    ref.resize((1024, 1024), Image.LANCZOS).save(os.path.join(folder, f"{name}-ref.png"))
    mask.resize((1024, 1024), Image.LANCZOS).save(os.path.join(folder, f"{name}-masque.png"))
    print(f"ok {name} : objet {right - left}x{bottom - top} px, carré {side}")


def planche(out: str, images: list) -> None:
    cols = 4
    thumb = 256
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * thumb, rows * (thumb + 28)), (20, 24, 50))
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(images):
        tile = Image.open(path).convert("RGBA")
        tile.thumbnail((thumb, thumb))
        back = Image.new("RGBA", (thumb, thumb), (60, 66, 110, 255))
        back.alpha_composite(tile, ((thumb - tile.width) // 2, (thumb - tile.height) // 2))
        x, y = (index % cols) * thumb, (index // cols) * (thumb + 28)
        sheet.paste(back.convert("RGB"), (x, y))
        draw.text((x + 6, y + thumb + 6), os.path.basename(path)[:34], fill=(230, 230, 255))
    sheet.save(out)
    print(f"ok planche {out} ({len(images)} images)")


def final(generated: str, mask_path: str, out: str, size: int) -> None:
    image = Image.open(generated).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    mask = Image.open(mask_path).convert("L").resize((1024, 1024), Image.LANCZOS)
    # Dilatation de 6 px puis flou léger : le contour stylisé par FLUX déborde un peu du rendu d'origine.
    mask = mask.filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(2.2))
    icon = image.convert("RGBA")
    icon.putalpha(mask)
    bbox = mask.point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox:
        left, top, right, bottom = bbox
        side = int(max(right - left, bottom - top) * 1.08)
        cx, cy = (left + right) / 2, (top + bottom) / 2
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square.alpha_composite(icon.crop((int(cx - side / 2), int(cy - side / 2), int(cx + side / 2), int(cy + side / 2))))
        icon = square
    icon.resize((size, size), Image.LANCZOS).save(out)
    print(f"ok icône {out}")


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "prep":
        prep(sys.argv[2], sys.argv[3], sys.argv[4])
    elif mode == "planche":
        planche(sys.argv[2], sys.argv[3:])
    elif mode == "final":
        final(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]) if len(sys.argv) > 5 else 512)
    else:
        raise SystemExit("mode attendu : prep, planche ou final")
