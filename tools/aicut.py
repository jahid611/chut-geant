"""aicut — detourage par IA (rembg, modele isnet-general-use).

    python tools/aicut.py entree.png sortie.png [entree2.png sortie2.png ...]

Le detourage par remplissage (tools/cutout.mjs) laisse un lisere clair et
mange les ombres portees ; le joueur veut un detourage « intelligent et
precis ». rembg segmente l'objet lui-meme, ombre comprise, et rend un PNG
avec alpha. Tourne avec le Python embarque de ComfyUI (rembg + onnxruntime y
sont installes) ; le modele est telecharge a la premiere execution.
"""

import sys
from pathlib import Path

from rembg import new_session, remove

MODEL = "isnet-general-use"


def main(argv: list[str]) -> int:
    if len(argv) < 2 or len(argv) % 2 != 0:
        print("usage: aicut.py entree.png sortie.png [entree2 sortie2 ...]", file=sys.stderr)
        return 2
    session = new_session(MODEL)
    pairs = list(zip(argv[0::2], argv[1::2]))
    for source, target in pairs:
        data = Path(source).read_bytes()
        result = remove(data, session=session, post_process_mask=True)
        Path(target).parent.mkdir(parents=True, exist_ok=True)
        Path(target).write_bytes(result)
        print(f"ok {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
