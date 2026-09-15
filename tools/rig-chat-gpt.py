#!/usr/bin/env python3
"""Chat TRELLIS -> squelette de marche et FBX Roblox, sans dépendance ajoutée.

Blender 5.2 :
  blender --background --python tools/rig-chat-gpt.py -- chat.glb sortie.fbx [apercu.png]
  L'aperçu produit aussi apercu-profil.png, dans la même pose.

Le chat reste un maillage continu : ses parties anatomiques sont des groupes de
déformation, pas des morceaux séparés qui laisseraient des trous aux articulations.
L'orientation et les repères sont des estimations géométriques, pas une reconnaissance
sémantique garantie. Les mesures et les indices de confiance sont imprimés.
"""

import argparse
import heapq
import json
import math
from pathlib import Path
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Matrix, Vector


def message(texte):
    print("[chat] " + texte, flush=True)


def normalise(v):
    return v / max(float(np.linalg.norm(v)), 1e-12)


def lisse(a, b, v):
    t = np.clip((v - a) / max(b - a, 1e-12), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def selection(*objets):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for objet in objets:
        objet.hide_set(False)
        objet.select_set(True)
    bpy.context.view_layer.objects.active = objets[-1]


def sommets(mesh):
    xyz = np.empty(len(mesh.vertices) * 3, dtype=np.float64)
    mesh.vertices.foreach_get("co", xyz)
    return xyz.reshape((-1, 3))


def importer(chemin):
    # Cette scène appartient au processus Blender de conversion uniquement.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    avant = set(bpy.data.objects)
    resultat = bpy.ops.import_scene.gltf(filepath=str(chemin))
    if "FINISHED" not in resultat:
        raise RuntimeError("L'import GLB a échoué.")
    importes = [o for o in bpy.data.objects if o not in avant]
    objets = [o for o in importes if o.type == "MESH" and len(o.data.vertices)]
    if not objets:
        raise RuntimeError("Le GLB ne contient aucun maillage.")
    # Figer d'abord chaque matrice mondiale : un parent GLTF peut porter toute
    # la rotation, l'échelle ou une réflexion. Conserver aussi les UV/matériaux.
    for objet in objets:
        selection(objet)
        monde = objet.matrix_world.copy()
        objet.parent = None
        objet.matrix_world = monde
        objet.animation_data_clear()
        for mod in list(objet.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        if objet.data.shape_keys:
            bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    selection(*objets)
    if len(objets) > 1:
        bpy.ops.object.join()
    chat = bpy.context.object
    chat.name = "Chat"
    chat.data.name = "ChatMaillage"
    chat.vertex_groups.clear()
    for objet in importes:
        # Les objets joints ont déjà été libérés par Blender.
        try:
            if objet != chat and objet.name in bpy.data.objects:
                bpy.data.objects.remove(objet, do_unlink=True)
        except ReferenceError:
            pass
    xyz = sommets(chat.data)
    if len(xyz) < 32 or not np.isfinite(xyz).all():
        raise RuntimeError("Maillage vide, trop petit ou coordonnées non finies.")
    if np.max(np.ptp(xyz, axis=0)) < 1e-8:
        raise RuntimeError("Le chat a une taille nulle.")
    return chat


def surface(mesh, nombre=22000):
    # Un échantillonnage par aire évite de confondre une zone très tessellée
    # (museau, yeux) avec la masse du corps. Les sommets restent tous exportés.
    mesh.calc_loop_triangles()
    triangles = np.array([t.vertices[:] for t in mesh.loop_triangles], dtype=int)
    if not len(triangles):
        raise RuntimeError("Le maillage ne contient aucune face.")
    xyz = sommets(mesh)
    abc = xyz[triangles]
    normales = np.cross(abc[:, 1] - abc[:, 0], abc[:, 2] - abc[:, 0])
    aires = np.linalg.norm(normales, axis=1)
    if aires.sum() <= 1e-16:
        raise RuntimeError("Toutes les faces sont dégénérées.")
    rng = np.random.default_rng(1709)
    indices = rng.choice(len(abc), nombre, p=aires / aires.sum())
    uv = rng.random((nombre, 2))
    uv[uv.sum(axis=1) > 1] = 1 - uv[uv.sum(axis=1) > 1]
    t = abc[indices]
    points = t[:, 0] + uv[:, :1] * (t[:, 1] - t[:, 0])
    points += uv[:, 1:] * (t[:, 2] - t[:, 0])
    grands = np.argsort(aires)[-160:]
    return points, normales[grands] / np.maximum(aires[grands, None], 1e-16)


def quatre_centres(xy):
    """Quatre appuis, initialisés dans les quatre quadrants, sans SciPy."""
    lo, hi = np.quantile(xy, [0.12, 0.88], axis=0)
    centres = np.array([[x, y] for y in (lo[1], hi[1]) for x in (lo[0], hi[0])])
    for _ in range(24):
        distances = ((xy[:, None] - centres[None]) ** 2).sum(axis=2)
        etiquettes = distances.argmin(axis=1)
        nouveaux = np.array([
            np.median(xy[etiquettes == k], axis=0) if np.any(etiquettes == k) else centres[k]
            for k in range(4)
        ])
        if np.max(np.abs(nouveaux - centres)) < 1e-7:
            break
        centres = nouveaux
    distances = ((xy[:, None] - centres[None]) ** 2).sum(axis=2)
    etiquettes = distances.argmin(axis=1)
    return centres, etiquettes, np.sqrt(distances.min(axis=1))


def repere_horizontal(points, haut):
    haut = normalise(haut)
    choix = np.eye(3)[np.argmin(np.abs(haut))]
    u = normalise(np.cross(haut, choix))
    v = np.cross(haut, u)
    plan = points @ np.array([u, v]).T
    _, vecteurs = np.linalg.eigh(np.cov(plan.T))
    long = normalise(vecteurs[0, -1] * u + vecteurs[1, -1] * v)
    lateral = np.cross(long, haut)
    return np.array([lateral, long, haut])


def score_sol(points, haut):
    repere = repere_horizontal(points, haut)
    p = points @ repere.T
    bas, sommet = np.quantile(p[:, 2], [0.001, 0.998])
    hauteur = sommet - bas
    largeur, longueur = np.ptp(np.quantile(p[:, :2], [0.01, 0.99], axis=0), axis=0)
    if min(hauteur, largeur, longueur) < 1e-8:
        return -1e6, repere
    sol = p[p[:, 2] < bas + 0.085 * hauteur, :2]
    if len(sol) < 45:
        return -1e6, repere
    centres, labels, erreurs = quatre_centres(sol)
    comptes = np.bincount(labels, minlength=4)
    ecarts = np.linalg.norm(centres[:, None] - centres[None], axis=2)
    ecarts += np.eye(4) * longueur * 10
    separation = ecarts.min()
    compacite = np.median(erreurs) / max(separation, 1e-9)
    equilibre = float(comptes.min() / max(comptes.max(), 1))
    couverture = np.ptp(centres, axis=0) / np.array([largeur, longueur])
    # Sous le ventre : quatre colonnes et du vide, puis un volume plein au-dessus.
    z = (p[:, 2] - bas) / hauteur
    bas_volume = np.count_nonzero((z > 0.12) & (z < 0.36))
    haut_volume = np.count_nonzero((z > 0.43) & (z < 0.78))
    quadrants = len(set((int(c[0] > np.median(centres[:, 0])),
                         int(c[1] > np.median(centres[:, 1]))) for c in centres))
    score = 2.2 * np.clip(couverture[0], 0, 1) + 3.0 * np.clip(couverture[1], 0, 1)
    score += 1.4 * equilibre + 0.6 * quadrants - 5.0 * compacite
    score += np.clip(math.log((haut_volume + 1) / (bas_volume + 1)), -2, 2)
    score -= 3.0 * max(largeur / longueur - 0.70, 0)
    score -= 2.0 * max(0.35 - hauteur / longueur, 0)
    return float(score), repere


def orienter(chat, points, normales):
    centre = np.median(points, axis=0)
    p = points - centre
    _, axes = np.linalg.eigh(np.cov(p.T))
    candidats = []
    import os

    if os.environ.get("CHAT_HAUT_Z", "1") != "0":
        # Les GLB de TRELLIS sont en Y-haut, que l'import glTF de Blender met en +Z : le haut est connu. La recherche
        # libre avait couché le chat final sur le dos (queue enroulée près du sol, 15/09). CHAT_HAUT_Z=0 la réactive.
        candidats.append(np.array([0.0, 0.0, 1.0]))
    else:
        # Tester les deux sens de chaque normale : le GLB peut être couché ou retourné.
        for axe in list(axes.T) + list(np.eye(3)) + list(normales):
            for signe in (-1, 1):
                direction = normalise(axe * signe)
                if all(np.dot(direction, autre) < 0.996 for autre in candidats):
                    candidats.append(direction)
    evaluations = [score_sol(p, h) for h in candidats]
    evaluations.sort(key=lambda valeur: valeur[0], reverse=True)
    meilleur, repere = evaluations[0]
    # Petites corrections de tangage/roulis, utiles si les pieds sont arrondis.
    for angle in (6, 2, 0.7):
        essais = [(meilleur, repere)]
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            haut = repere[2] + math.tan(math.radians(angle)) * (dx * repere[0] + dy * repere[1])
            essais.append(score_sol(p, haut))
        meilleur, repere = max(essais, key=lambda valeur: valeur[0])
    local = p @ repere.T
    y0, y1 = np.quantile(local[:, 1], [0.003, 0.997])
    longueur = y1 - y0
    bouts = []
    for inverse in (False, True):
        t = (local[:, 1] - y0) / longueur
        if inverse:
            t = 1 - t
        bout = local[(t > 0.025) & (t < 0.22)]
        largeur = np.ptp(np.quantile(bout[:, 0], [0.08, 0.92])) if len(bout) else 0
        bouts.append(largeur * math.sqrt(len(bout) / len(local)))
    # La tête a une section large ; la queue forme une extrémité fine et allongée.
    # Dans ce repère, le premier bout est déjà du côté -Y.
    if bouts[1] > bouts[0]:
        repere[0] *= -1
        repere[1] *= -1
    transforme = (sommets(chat.data) - centre) @ repere.T
    decale = np.array([np.median((p @ repere.T)[:, 0]), 0.0, transforme[:, 2].min()])
    transforme -= decale
    chat.data.vertices.foreach_set("co", transforme.astype(np.float32).ravel())
    chat.data.update()
    # Le repère est une rotation propre : ni réflexion des UV, ni échelle cachée.
    if np.linalg.det(repere) < 0.99:
        raise RuntimeError("Le repère calculé n'est pas une rotation propre.")
    confiance = abs(bouts[0] - bouts[1]) / max(max(bouts), 1e-9)
    message(f"Orientation : score d'appui {meilleur:.2f}, distinction tête/queue {confiance:.2f}.")
    if confiance < 0.18:
        message("ATTENTION : tête/queue peu distinctes ; contrôler visuellement l'aperçu.")
    return (p @ repere.T) - decale, transforme, {
        "rotation_depuis_glb": repere.tolist(), "score_sol": meilleur,
        "confiance_tete_queue": confiance,
    }


def profil(points, nombre=72):
    y0, y1 = np.quantile(points[:, 1], [0.002, 0.998])
    limites = np.linspace(y0, y1, nombre + 1)
    centres = (limites[1:] + limites[:-1]) / 2
    largeur = np.zeros(nombre)
    milieu = np.zeros((nombre, 3))
    bas = np.zeros(nombre)
    haut = np.zeros(nombre)
    for i, y in enumerate(centres):
        tranche = points[(points[:, 1] >= limites[i]) & (points[:, 1] < limites[i + 1])]
        milieu[i, 1] = y
        if len(tranche) >= 8:
            largeur[i] = np.ptp(np.quantile(tranche[:, 0], [0.08, 0.92]))
            milieu[i] = np.median(tranche, axis=0)
            bas[i], haut[i] = np.quantile(tranche[:, 2], [0.06, 0.94])
    largeur = np.convolve(np.pad(largeur, 1, mode="edge"), np.ones(3) / 3, mode="valid")
    return centres, largeur, milieu, bas, haut


def suivre_queue(points, base, longueur, largeur):
    """Suivre une queue courbe par un graphe de petites cellules occupées."""
    pas = max(longueur / 65, largeur / 18)
    queue = points[points[:, 1] > base[1] + 0.025 * longueur]
    if len(queue) < 35:
        message("ATTENTION : queue peu visible ; repère court estimé derrière le bassin.")
        return np.array([base + np.array([0, t * 0.22 * longueur, t * 0.05 * longueur])
                         for t in np.linspace(0, 1, 4)])
    indices = np.floor(queue / pas).astype(int)
    cellules, inverse = np.unique(indices, axis=0, return_inverse=True)
    centres = np.zeros((len(cellules), 3))
    np.add.at(centres, inverse, queue)
    centres /= np.bincount(inverse)[:, None]
    registre = {tuple(c): i for i, c in enumerate(cellules)}
    depart = int(np.argmin(np.linalg.norm(centres - base, axis=1)))
    distances = {depart: 0.0}
    parents = {}
    file = [(0.0, depart)]
    # Deux cellules de rayon raccordent les petites lacunes d'échantillonnage.
    offsets = [(x, y, z) for x in range(-2, 3) for y in range(-2, 3)
               for z in range(-2, 3) if 0 < x*x + y*y + z*z <= 6]
    while file:
        cout, i = heapq.heappop(file)
        if cout != distances[i]:
            continue
        c = cellules[i]
        for dx, dy, dz in offsets:
            j = registre.get((c[0] + dx, c[1] + dy, c[2] + dz))
            if j is None:
                continue
            nouveau = cout + float(np.linalg.norm(centres[i] - centres[j]))
            if nouveau < distances.get(j, float("inf")):
                distances[j] = nouveau
                parents[j] = i
                heapq.heappush(file, (nouveau, j))
    bout = max(distances, key=distances.get)
    chemin = [bout]
    while chemin[-1] != depart:
        chemin.append(parents[chemin[-1]])
    ligne = np.vstack([base, centres[chemin[::-1]]])
    if len(ligne) < 3 or distances[bout] < longueur * 0.06:
        # Une queue déconnectée reste exploitable par ses sections arrière.
        ys = np.linspace(base[1], np.quantile(queue[:, 1], 0.99), 18)
        ligne = [base]
        for y in ys[1:]:
            section = queue[np.abs(queue[:, 1] - y) < pas * 2]
            if len(section):
                ligne.append(np.median(section, axis=0))
        ligne = np.array(ligne)
    # Centrer le trajet (trouvé sur la surface) au milieu de la section de queue.
    for i in range(1, len(ligne)):
        voisins = queue[np.linalg.norm(queue - ligne[i], axis=1) < pas * 2.5]
        if len(voisins):
            ligne[i] = np.mean(voisins, axis=0)
    for _ in range(3):
        ligne[1:-1] = (ligne[:-2] + 2 * ligne[1:-1] + ligne[2:]) / 4
    cumul = np.r_[0, np.cumsum(np.linalg.norm(np.diff(ligne, axis=0), axis=1))]
    if cumul[-1] < 1e-8:
        raise RuntimeError("Impossible d'estimer une longueur de queue non nulle.")
    return np.array([[np.interp(t, cumul, ligne[:, k]) for k in range(3)]
                     for t in np.linspace(0, cumul[-1], 4)])


def mesurer(points, xyz, orientation):
    hauteur = float(np.quantile(points[:, 2], 0.997))
    ys, largeurs, milieux, bas, hauts = profil(points)
    largeur = float(np.quantile(largeurs[largeurs > 0], 0.85))
    # Le dernier tronçon épais appartient à la croupe ; la queue est exclue.
    epais = np.flatnonzero(largeurs > largeur * 0.48)
    if len(epais) < 4:
        raise RuntimeError("Le profil ne permet pas de localiser le tronc.")
    arriere = float(ys[epais[-1]])
    nez = float(np.quantile(points[:, 1], 0.002))
    longueur = arriere - nez
    if longueur <= largeur * 0.6:
        raise RuntimeError("Orientation anatomique invraisemblable : corps trop court.")
    corporel = points[(points[:, 1] < arriere) & (points[:, 2] > 0.38 * hauteur)]
    centre_x = float(np.median(corporel[:, 0]))
    # Essayer plusieurs hauteurs pour ne pas inclure une queue touchant le sol.
    meilleur = None
    for fraction in (0.055, 0.085, 0.12, 0.17):
        sol = points[(points[:, 2] < fraction * hauteur)
                     & (points[:, 1] < arriere - 0.025 * longueur)]
        if len(sol) < 45:
            continue
        centres, labels, erreurs = quatre_centres(sol[:, :2])
        ecarts = np.linalg.norm(centres[:, None] - centres[None], axis=2)
        ecarts += np.eye(4) * longueur * 10
        comptes = np.bincount(labels, minlength=4)
        # Un centre sans aucun sommet (pattes rapprochées, queue près du sol) faisait planter la mesure du pied
        # (quantile d'un tableau vide, chat final du 15/09) : cette hauteur de coupe est simplement écartée.
        if comptes.min() == 0:
            continue
        qualite = ecarts.min() / max(np.median(erreurs), longueur * 0.01)
        qualite *= float(comptes.min() / max(comptes.max(), 1)) ** 0.3
        if meilleur is None or qualite > meilleur[0]:
            meilleur = (qualite, centres, sol, labels)
    pieds = {}
    confiance = 0.0
    if meilleur is not None:
        confiance, centres, sol, labels = meilleur
        ordre = np.argsort(centres[:, 1])
        for nom, paire in (("Avant", ordre[:2]), ("Arriere", ordre[2:])):
            paire = sorted(paire, key=lambda i: centres[i, 0])
            for cote, i in zip(("D", "G"), paire):
                cluster = sol[labels == i]
                pied = np.median(cluster, axis=0)
                pied[2] = max(float(np.quantile(cluster[:, 2], 0.30)), hauteur * 0.02)
                pieds[nom + cote] = pied
        # Ne pas présenter quatre centres artificiels comme quatre pattes détectées.
        separation_av = pieds["AvantG"][0] - pieds["AvantD"][0]
        separation_ar = pieds["ArriereG"][0] - pieds["ArriereD"][0]
        empattement = np.mean([pieds["Arriere" + c][1] - pieds["Avant" + c][1] for c in ("G", "D")])
        if min(separation_av, separation_ar) < largeur * 0.22 or empattement < longueur * 0.30:
            confiance = 0.0
    if confiance < 1.3:
        message("ATTENTION : quatre appuis mal séparés ; proportions anatomiques de repli.")
        pieds = {nom + cote: np.array([centre_x + signe * largeur * 0.34,
                                       nez + fraction * longueur, hauteur * 0.025])
                 for nom, fraction in (("Avant", 0.29), ("Arriere", 0.79))
                 for cote, signe in (("G", 1), ("D", -1))}
    avant = float(np.mean([pieds["Avant" + c][1] for c in ("G", "D")]))
    hanche_y = float(np.mean([pieds["Arriere" + c][1] for c in ("G", "D")]))
    dos = points[(points[:, 1] > avant) & (points[:, 1] < hanche_y)
                 & (np.abs(points[:, 0] - centre_x) < largeur * 0.4)]
    dos_z = float(np.quantile(dos[:, 2], 0.94)) if len(dos) else 0.78 * hauteur
    # Section médiane : son bord inférieur est le ventre, et non les quatre pieds.
    ventre = points[(points[:, 1] > avant + 0.25 * (hanche_y - avant))
                    & (points[:, 1] < hanche_y - 0.25 * (hanche_y - avant))]
    ventre_z = float(np.quantile(ventre[:, 2], 0.10)) if len(ventre) else 0.44 * hauteur
    ventre_z = float(np.clip(ventre_z, 0.32 * hauteur, 0.66 * hauteur))
    colonne_z = ventre_z + 0.68 * (dos_z - ventre_z)
    tete = points[(points[:, 1] < avant - 0.08 * longueur) & (points[:, 2] > ventre_z)]
    tete_centre = np.median(tete, axis=0) if len(tete) > 30 else np.array([
        centre_x, nez + 0.13 * longueur, 0.81 * hauteur])
    tete_centre[0] = centre_x
    base = np.array([centre_x, arriere - 0.015 * longueur, colonne_z])
    depart_queue = points[(points[:, 1] > arriere + 0.02 * longueur)
                          & (points[:, 1] < arriere + 0.10 * longueur)]
    if len(depart_queue) > 15:
        base[[0, 2]] = np.median(depart_queue, axis=0)[[0, 2]]
    queue = suivre_queue(points, base, longueur, largeur)
    mesures = dict(orientation)
    mesures.update({
        "longueur_sans_queue": longueur, "longueur_tronc_entre_appuis": hanche_y - avant,
        "largeur_tronc": largeur, "hauteur": float(xyz[:, 2].max()),
        "hauteur_dos": dos_z, "hauteur_ventre": ventre_z,
        "base_queue": base.tolist(), "queue_repères": queue.tolist(),
        "confiance_appuis": float(confiance),
        "appuis": {k: v.tolist() for k, v in pieds.items()},
    })
    return {"L": longueur, "W": largeur, "H": hauteur, "x": centre_x,
            "nez": nez, "arriere": arriere, "avant": avant, "hanche": hanche_y,
            "dos": dos_z, "ventre": ventre_z, "colonne": colonne_z,
            "tete": tete_centre, "pieds": pieds, "queue": queue, "mesures": mesures}


def creer_squelette(chat, points, m):
    L, W, H = m["L"], m["W"], m["H"]
    x, z = m["x"], m["colonne"]
    bassin = np.array([x, m["hanche"], z])
    lombaires = np.array([x, m["hanche"] - 0.16 * L, z])
    thorax = np.array([x, m["avant"] + 0.09 * L, z + 0.015 * H])
    garrot = np.array([x, m["avant"] - 0.035 * L, z + 0.035 * H])
    nuque = 0.72 * m["tete"] + 0.28 * garrot
    museau = m["tete"].copy()
    museau[1] = m["nez"] + 0.035 * L
    donnees = []
    branches = {}

    def os(nom, a, b, parent=None, branche="tronc"):
        a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
        if np.linalg.norm(a - b) < L * 0.005:
            b = a + np.array([0, -L * 0.02, 0])
        donnees.append((nom, a.copy(), b.copy(), parent))
        branches.setdefault(branche, []).append(len(donnees) - 1)

    os("Racine", bassin, lombaires)
    os("ColonneLombaire", lombaires, thorax, "Racine")
    os("ColonneThoracique", thorax, garrot, "ColonneLombaire")
    os("Cou", garrot, nuque, "ColonneThoracique")
    os("Tete", nuque, museau, "Cou")
    for i in range(3):
        os(f"Queue{i + 1}", m["queue"][i], m["queue"][i + 1],
           "Racine" if i == 0 else f"Queue{i}", "queue")

    def ajuster(point, pied, force=0.45):
        # Les coupes de la patte suivent sa position réelle. Déplacement borné
        # pour conserver le coude arrière et le zigzag digitigrade du membre.
        zone = points[(np.abs(points[:, 2] - point[2]) < 0.045 * H)
                      & (np.abs(points[:, 0] - pied[0]) < 0.21 * W)
                      & (np.abs(points[:, 1] - point[1]) < 0.10 * L)]
        if len(zone) >= 15:
            cible = np.median(zone, axis=0)
            point[:2] += force * np.clip(cible[:2] - point[:2],
                                        [-0.08 * W, -0.035 * L], [0.08 * W, 0.035 * L])
        return point

    for cote in ("G", "D"):
        pied = m["pieds"]["Avant" + cote]
        epaule = np.array([x + 0.88 * (pied[0] - x), pied[1] + 0.005 * L, z - 0.03 * H])
        coude = ajuster(np.array([pied[0], pied[1] + 0.065 * L, 0.60 * epaule[2]]), pied)
        poignet = ajuster(np.array([pied[0], pied[1] + 0.015 * L,
                                   max(pied[2] + 0.04 * H, 0.14 * epaule[2])]), pied)
        doigts = np.array([pied[0], pied[1] - 0.040 * L, pied[2]])
        os("Epaule" + cote, epaule, coude, "ColonneThoracique", "Avant" + cote)
        os("AvantBras" + cote, coude, poignet, "Epaule" + cote, "Avant" + cote)
        os("PatteAvant" + cote, poignet, doigts, "AvantBras" + cote, "Avant" + cote)

        pied = m["pieds"]["Arriere" + cote]
        hanche = np.array([x + 0.84 * (pied[0] - x), pied[1] + 0.005 * L, z - 0.035 * H])
        genou = ajuster(np.array([pied[0], pied[1] - 0.085 * L, 0.65 * hanche[2]]), pied)
        jarret = ajuster(np.array([pied[0], pied[1] + 0.060 * L, 0.35 * hanche[2]]), pied)
        metatarse = ajuster(np.array([pied[0], pied[1] + 0.004 * L,
                                     max(pied[2] + 0.02 * H, 0.085 * hanche[2])]), pied)
        doigts = np.array([pied[0], pied[1] - 0.045 * L, pied[2]])
        os("Cuisse" + cote, hanche, genou, "Racine", "Arriere" + cote)
        os("Jambe" + cote, genou, jarret, "Cuisse" + cote, "Arriere" + cote)
        os("Metatarse" + cote, jarret, metatarse, "Jambe" + cote, "Arriere" + cote)
        os("PatteArriere" + cote, metatarse, doigts, "Metatarse" + cote, "Arriere" + cote)

    armature = bpy.data.armatures.new("SqueletteChat")
    rig = bpy.data.objects.new("ChatRig", armature)
    bpy.context.collection.objects.link(rig)
    selection(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for nom, a, b, parent in donnees:
        bone = armature.edit_bones.new(nom)
        bone.head, bone.tail = Vector(a), Vector(b)
        bone.use_deform = True
        # Tous les membres fléchissent autour du même axe transversal mondial.
        # Aligner Z sur X ; les poses utilisent malgré tout une conversion explicite.
        bone.align_roll(Vector((1, 0, 0)))
        if parent:
            bone.parent = armature.edit_bones[parent]
            bone.use_connect = (bone.head - bone.parent.tail).length < 1e-6 * L
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.show_in_front = True
    armature.display_type = "OCTAHEDRAL"
    return rig, donnees, branches


def distances_os(xyz, donnees):
    distances = np.empty((len(xyz), len(donnees)), dtype=np.float32)
    for i, (_, a, b, _) in enumerate(donnees):
        ab = b - a
        t = np.clip(((xyz - a) @ ab) / np.dot(ab, ab), 0, 1)
        distances[:, i] = np.linalg.norm(xyz - (a + t[:, None] * ab), axis=1)
    return distances


def enveloppes(xyz, m, donnees, branches, distances):
    L, W, H = m["L"], m["W"], m["H"]
    gates = np.zeros_like(distances)
    membres = ("AvantG", "AvantD", "ArriereG", "ArriereD")
    masses = np.zeros((len(xyz), 4), dtype=np.float32)
    axes = []
    for nom in membres:
        indices = branches[nom]
        chaine = np.array([donnees[j][1] for j in indices] + [donnees[indices[-1]][2]])
        ordre = np.argsort(chaine[:, 2])
        axes.append(np.column_stack([
            np.interp(xyz[:, 2], chaine[ordre, 2], chaine[ordre, k]) for k in (0, 1)
        ]))
    ecarts = np.stack([np.linalg.norm(xyz[:, :2] - axe, axis=1) for axe in axes], axis=1)
    plus_proche = ecarts.argmin(axis=1)
    for i, nom in enumerate(membres):
        indices = branches[nom]
        attache = donnees[indices[0]][1][2]
        # Capsules elliptiques à support fini, une par os. Leur faible rayon
        # vertical empêche un os distal d'atteindre le flanc ou le poitrail.
        rayons = np.array([W * 0.33, L * 0.10, H * 0.035])
        capsules = distances_os(xyz / rayons, [
            (donnees[j][0], donnees[j][1] / rayons, donnees[j][2] / rayons, donnees[j][3])
            for j in indices
        ])
        # Sous le ventre les pattes sont séparées : ajuster la section sur
        # leur peau réelle, y compris les doigts qui dépassent l'axe des os.
        # Cet élargissement s'arrête au ventre ; il n'atteint pas les flancs.
        bas = (xyz[:, 2] < m["ventre"] - H * 0.125) & (plus_proche == i)
        rayon_mesure = max(1.0, float(capsules[bas].min(axis=1).max()) / 0.65) if np.any(bas) else 1.0
        facteur = 1 + (rayon_mesure - 1) * (1 - lisse(
            m["ventre"] - H * 0.125, m["ventre"] - H * 0.025, xyz[:, 2]))
        supports = 1 - lisse(0.65, 1.0, capsules / facteur[:, None])
        # La séparation suit les deux pattes à cette hauteur : les appuis
        # décalés du vrai chat traversent le plan médian global du tronc.
        autre = i ^ 1
        separation = np.maximum(np.linalg.norm(axes[i] - axes[autre], axis=1), 1e-12)
        cote = lisse(0, H * 0.015, (ecarts[:, autre]**2 - ecarts[:, i]**2) / (2 * separation))
        raccord = 1 - lisse(attache - H * 0.045, attache, xyz[:, 2])
        masses[:, i] = supports.max(axis=1) * cote * raccord
        gates[:, indices] = supports
    # Aucune attribution forcée à « la patte la moins éloignée » : tout ce
    # qui sort des capsules revient au tronc, même sous la hauteur du ventre.
    masses /= np.maximum(masses.sum(axis=1)[:, None], 1)
    queue_dist = distances[:, branches["queue"]].min(axis=1)
    base = m["queue"][0]
    # Le bassin (avant la base) ne reçoit jamais Queue1, même si cet os est
    # plus proche que Racine. Raccord court, puis capsule autour de la queue.
    derriere = lisse(base[1], base[1] + H * 0.04, xyz[:, 1])
    queue_gate = derriere * (1 - lisse(W * 0.16, W * 0.24, queue_dist))
    fractions = {}
    for i, nom in enumerate(membres):
        fractions[nom] = masses[:, i] * (1 - queue_gate)
        gates[:, branches[nom]] *= fractions[nom][:, None]
    fractions["queue"] = queue_gate
    fractions["tronc"] = (1 - masses.sum(axis=1)) * (1 - queue_gate)
    gates[:, branches["queue"]] = queue_gate[:, None]
    gates[:, branches["tronc"]] = fractions["tronc"][:, None]
    return gates, fractions


def ponderer(chat, rig, xyz, m, donnees, branches):
    noms = [d[0] for d in donnees]
    selection(chat, rig)
    auto_ok = False
    try:
        resultat = bpy.ops.object.parent_set(type="ARMATURE_AUTO")
        auto_ok = "FINISHED" in resultat
    except RuntimeError as erreur:
        message("Poids automatiques indisponibles : " + str(erreur))
    # Blender peut signaler un échec de diffusion tout en renvoyant FINISHED.
    auto = np.zeros((len(xyz), len(noms)), dtype=np.float32)
    index = {g.index: noms.index(g.name) for g in chat.vertex_groups if g.name in noms}
    if auto_ok:
        for v in chat.data.vertices:
            for g in v.groups:
                if g.group in index and math.isfinite(g.weight) and g.weight > 0:
                    auto[v.index, index[g.group]] = g.weight
    totaux = auto.sum(axis=1)
    valides = totaux > 1e-8
    auto[valides] /= totaux[valides, None]
    message(f"Poids ARMATURE_AUTO valides : {int(valides.sum())}/{len(xyz)} sommets.")
    distances = distances_os(xyz, donnees)
    gates, fractions = enveloppes(xyz, m, donnees, branches, distances)
    repli = np.zeros_like(distances)
    for nom, indices in branches.items():
        # Mélanger les os d'une même chaîne autour des articulations, sans
        # qu'un pied distant ou la queue puisse influencer le membre voisin.
        rayon = m["L"] * (0.065 if nom == "tronc" else 0.027)
        d = distances[:, indices]
        proximite = np.exp(-np.minimum((d * d - d.min(axis=1)[:, None] ** 2) / rayon**2, 60))
        proximite *= gates[:, indices]
        proximite /= np.maximum(proximite.sum(axis=1)[:, None], 1e-30)
        repli[:, indices] = proximite * fractions[nom][:, None]
    # Garder la diffusion thermique là où elle respecte l'anatomie. Ne corriger
    # que les fuites nettes (patte opposée, tronc sous le ventre, queue éloignée).
    compatibilite = np.clip(gates * 5, 0, 1)
    poids = auto * compatibilite
    masses = poids.sum(axis=1)
    confiance = np.clip((masses - 0.25) / 0.55, 0, 1)
    poids /= np.maximum(masses[:, None], 1e-12)
    poids = confiance[:, None] * poids + (1 - confiance[:, None]) * repli
    # Lisser sur les arêtes réelles, pas entre deux surfaces qui se touchent.
    edges = np.empty(len(chat.data.edges) * 2, dtype=np.int32)
    chat.data.edges.foreach_get("vertices", edges)
    edges = edges.reshape((-1, 2))
    if len(edges):
        degres = np.bincount(edges.ravel(), minlength=len(xyz)).astype(np.float32)
        for _ in range(2):
            voisinage = np.zeros_like(poids)
            np.add.at(voisinage, edges[:, 0], poids[edges[:, 1]])
            np.add.at(voisinage, edges[:, 1], poids[edges[:, 0]])
            voisinage /= np.maximum(degres[:, None], 1)
            facteur = (0.25 * (1 - confiance) * (degres > 0))[:, None]
            poids = ((1 - facteur) * poids + facteur * voisinage) * compatibilite
    # Réappliquer les limites APRÈS le lissage. Conserver la masse de chaque
    # branche pendant la réduction à quatre os : renormaliser globalement
    # amplifierait une faible influence de patte dans le raccord avec le tronc.
    poids *= gates > 0
    limites = np.zeros_like(poids)
    for i in range(len(xyz)):
        actifs = []
        candidats = []
        retenus = []
        for nom, indices in branches.items():
            masse = float(fractions[nom][i])
            if masse <= 1e-8:
                continue
            valeurs = poids[i, indices].copy()
            if valeurs.sum() <= 1e-30:
                valeurs = repli[i, indices].copy()
            valeurs *= masse / max(float(valeurs.sum()), 1e-30)
            ordre = np.argsort(-valeurs)
            retenus.append(indices[ordre[0]])
            candidats.extend((float(valeurs[k]), indices[k]) for k in ordre[1:] if valeurs[k] > 0)
            poids[i, indices] = valeurs
            actifs.append((indices, masse))
        if len(retenus) > 4:
            raise RuntimeError(f"Trop de volumes anatomiques au sommet {i}.")
        retenus.extend(j for _, j in sorted(candidats, reverse=True)[:4 - len(retenus)])
        for indices, masse in actifs:
            gardes = [j for j in indices if j in retenus]
            valeurs = poids[i, gardes]
            limites[i, gardes] = valeurs * (masse / max(float(valeurs.sum()), 1e-30))
    limites /= limites.sum(axis=1)[:, None]
    if not np.isfinite(limites).all():
        raise RuntimeError("Pondération non finie.")
    if np.any(limites[gates == 0] > 0):
        raise RuntimeError("Une influence a débordé de son volume anatomique.")
    for nom, indices in branches.items():
        ecart = float(np.max(np.abs(limites[:, indices].sum(axis=1) - fractions[nom])))
        if ecart > 1e-5:
            raise RuntimeError(f"Raccord altéré pour {nom} : {ecart}.")
    message("Volumes vérifiés après lissage : aucune fuite, masses des raccords conservées.")
    chat.vertex_groups.clear()
    groupes = [chat.vertex_groups.new(name=nom) for nom in noms]
    for i, ligne in enumerate(limites):
        for j in np.flatnonzero(ligne > 0):
            groupes[j].add([i], float(ligne[j]), "REPLACE")
    chat.parent = rig
    chat.matrix_parent_inverse = Matrix.Identity(4)
    for mod in list(chat.modifiers):
        if mod.type == "ARMATURE":
            chat.modifiers.remove(mod)
    mod = chat.modifiers.new("DeformationChat", "ARMATURE")
    mod.object = rig
    mod.use_vertex_groups = True
    # Même skinning linéaire que l'import cible, sans avantage visuel non exporté.
    mod.use_deform_preserve_volume = False
    for vertex in chat.data.vertices:
        somme = sum(g.weight for g in vertex.groups)
        if not math.isfinite(somme) or abs(somme - 1) > 1e-4 or len(vertex.groups) > 4:
            raise RuntimeError(f"Poids invalides au sommet {vertex.index}.")
    message("Poids vérifiés : aucun sommet sans poids, quatre influences au maximum.")


def apercu(chat, rig, chemin, m):
    scene = bpy.context.scene
    matrices = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
    temporaires = []
    ancien_monde, ancienne_camera = scene.world, scene.camera

    def tourner(nom, degres):
        bone = rig.pose.bones[nom]
        axe_local = bone.bone.matrix_local.to_3x3().inverted() @ Vector((1, 0, 0))
        bone.matrix_basis = Matrix.Rotation(math.radians(degres), 4, axe_local)

    def viser(objet, cible):
        objet.rotation_euler = (Vector(cible) - objet.location).to_track_quat("-Z", "Y").to_euler()

    try:
        # +X fléchit un membre descendant vers l'arrière (+Y).
        # L'avant gauche s'avance ; l'arrière droit s'étend en sens opposé.
        for nom, angle in {"EpauleG": -16, "AvantBrasG": -28, "PatteAvantG": 30,
                           "CuisseD": 17, "JambeD": -14, "MetatarseD": 8,
                           "PatteArriereD": -8, "EpauleD": 9, "CuisseG": -8,
                           "Queue1": 12, "Queue2": 7, "Queue3": -4}.items():
            tourner(nom, angle)
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evalue = chat.evaluated_get(depsgraph)
        mesh = evalue.to_mesh()
        try:
            xyz = np.array([evalue.matrix_world @ v.co for v in mesh.vertices])
        finally:
            evalue.to_mesh_clear()
        lo, hi = xyz.min(axis=0), xyz.max(axis=0)
        centre = (lo + hi) / 2
        taille = float(np.linalg.norm(hi - lo))
        # Plateau purement technique de rendu, absent du FBX.
        bpy.ops.mesh.primitive_plane_add(size=taille * 200, location=(centre[0], centre[1], min(0, lo[2]) - m["H"] * 0.006))
        sol = bpy.context.object
        temporaires.append(sol)
        mat = bpy.data.materials.new("SolApercu")
        mat.diffuse_color = (0.13, 0.16, 0.20, 1)
        mat.use_nodes = True
        shader = mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (0.13, 0.16, 0.20, 1)
        shader.inputs["Roughness"].default_value = 0.85
        sol.data.materials.append(mat)
        camera_data = bpy.data.cameras.new("CameraApercu")
        camera = bpy.data.objects.new("CameraApercu", camera_data)
        scene.collection.objects.link(camera)
        temporaires.append(camera)
        camera_data.type = "ORTHO"
        camera_data.clip_start = max(taille * 0.001, 1e-5)
        camera_data.clip_end = taille * 1000
        scene.camera = camera
        monde = bpy.data.worlds.new("MondeApercu")
        monde.use_nodes = True
        monde.node_tree.nodes["Background"].inputs[0].default_value = (0.22, 0.27, 0.35, 1)
        monde.node_tree.nodes["Background"].inputs[1].default_value = 0.45
        scene.world = monde
        for nom, position, puissance, couleur in (
            ("Principale", (1.4, -1.0, 2.2), 700, (1.0, 0.88, 0.75)),
            ("Remplissage", (-1.3, -0.7, 1.0), 420, (0.72, 0.83, 1.0)),
            ("Contour", (0.1, 1.6, 1.8), 850, (1.0, 0.94, 0.85)),
        ):
            data = bpy.data.lights.new(nom, "AREA")
            data.energy = puissance * taille**2
            data.shape = "DISK"
            data.size = taille * 1.3
            data.color = couleur
            lampe = bpy.data.objects.new(nom, data)
            scene.collection.objects.link(lampe)
            temporaires.append(lampe)
            lampe.location = Vector(centre) + Vector(position) * taille
            viser(lampe, centre)
        moteurs = scene.render.bl_rna.properties["engine"].enum_items.keys()
        scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in moteurs else "BLENDER_EEVEE"
        scene.render.resolution_x = scene.render.resolution_y = 768
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = "PNG"
        scene.render.film_transparent = False
        scene.render.use_file_extension = False
        profil = chemin.with_name(chemin.stem + "-profil.png")
        for destination, direction in (
            (chemin, (1.9, -0.85, 0.68)),
            # -X montre la patte arrière droite étendue. Aucun tangage ni
            # lacet : projection exacte dans le plan longitudinal Y/Z.
            (profil, (-2.0, 0.0, 0.0)),
        ):
            camera.location = Vector(centre) + Vector(direction) * taille
            viser(camera, centre)
            rotation = camera.rotation_euler.to_matrix()
            cadre = (xyz - centre) @ np.array(rotation)
            camera_data.ortho_scale = float(max(np.ptp(cadre[:, 0]), np.ptp(cadre[:, 1])) * 1.22)
            scene.render.filepath = str(destination)
            bpy.ops.render.render(write_still=True)
            if not destination.is_file():
                raise RuntimeError("L'aperçu n'a pas été écrit : " + str(destination))
            message("Aperçu rendu : " + str(destination))
    finally:
        for nom, matrice in matrices.items():
            rig.pose.bones[nom].matrix_basis = matrice
        scene.camera, scene.world = ancienne_camera, ancien_monde
        for objet in temporaires:
            bpy.data.objects.remove(objet, do_unlink=True)
        bpy.context.view_layer.update()


def exporter(chat, rig, chemin):
    # Le GLB stocke souvent les images en mémoire. Matérialiser des PNG temporaires
    # et les réembarquer : le FBX privilégie les octets packed_file lorsqu'ils
    # existent. Leur format doit correspondre au suffixe du fichier référencé.
    images = set()
    for materiau in chat.data.materials:
        if materiau and materiau.use_nodes:
            for node in materiau.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    images.add(node.image)
    with tempfile.TemporaryDirectory(prefix="chat-fbx-") as dossier:
        anciens = []
        try:
            for i, img in enumerate(sorted(images, key=lambda image: image.name)):
                anciens.append((img, img.filepath_raw, img.file_format))
                if not img.has_data:
                    img.reload()
                if not img.has_data:
                    raise RuntimeError("Texture illisible : " + img.name)
                img.filepath_raw = str(Path(dossier) / f"texture_chat_{i:03d}.png")
                img.file_format = "PNG"
                img.save()
                if not Path(img.filepath_raw).is_file():
                    raise RuntimeError("Écriture de texture impossible : " + img.name)
                octets = Path(img.filepath_raw).read_bytes()
                img.pack(data=octets, data_len=len(octets))
            selection(chat, rig)
            rig.data.pose_position = "REST"
            chat.animation_data_clear()
            rig.animation_data_clear()
            bpy.context.view_layer.update()
            resultat = bpy.ops.export_scene.fbx(
                filepath=str(chemin), check_existing=False, use_selection=True,
                object_types={"ARMATURE", "MESH"}, add_leaf_bones=False,
                use_armature_deform_only=True, armature_nodetype="NULL",
                bake_anim=False, use_mesh_modifiers=True, mesh_smooth_type="FACE",
                path_mode="COPY", embed_textures=True,
                axis_forward="-Z", axis_up="Y", primary_bone_axis="Y", secondary_bone_axis="X",
                apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS",
                use_space_transform=True, bake_space_transform=False,
            )
            if "FINISHED" not in resultat or not chemin.is_file() or chemin.stat().st_size == 0:
                raise RuntimeError("L'export FBX a échoué.")
        finally:
            rig.data.pose_position = "POSE"
            for img, ancien_chemin, ancien_format in anciens:
                img.filepath_raw, img.file_format = ancien_chemin, ancien_format


def main():
    parser = argparse.ArgumentParser(description="Armature anatomique d'un chat TRELLIS pour Roblox.")
    parser.add_argument("glb", type=Path)
    parser.add_argument("fbx", type=Path)
    parser.add_argument("apercu", type=Path, nargs="?")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source, sortie = args.glb.resolve(), args.fbx.resolve()
    image = args.apercu.resolve() if args.apercu else None
    if not source.is_file() or source.suffix.lower() != ".glb":
        parser.error("L'entrée doit être un fichier .glb existant.")
    if sortie.suffix.lower() != ".fbx":
        parser.error("La sortie doit porter l'extension .fbx.")
    if image and image.suffix.lower() != ".png":
        parser.error("L'aperçu doit porter l'extension .png.")
    sortie.parent.mkdir(parents=True, exist_ok=True)
    if image:
        image.parent.mkdir(parents=True, exist_ok=True)
    message("Import et application des transformations.")
    chat = importer(source)
    points, normales = surface(chat.data)
    points, xyz, orientation = orienter(chat, points, normales)
    mesures = mesurer(points, xyz, orientation)
    # Construire explicitement le rapport à partir des repères réellement
    # utilisés, sans dépendre d'un sous-dictionnaire éventuellement vide.
    rapport = dict(mesures["mesures"])
    rapport.update({
        "repere": "X gauche, Y arrière, Z haut ; origine verticale au sol",
        "longueur_sans_queue": float(mesures["L"]),
        "longueur_totale": float(np.ptp(xyz[:, 1])),
        "largeur_tronc": float(mesures["W"]),
        "largeur_totale": float(np.ptp(xyz[:, 0])),
        "hauteur": float(np.ptp(xyz[:, 2])),
        "base_queue": mesures["queue"][0].tolist(),
        "appuis": {nom: position.tolist() for nom, position in mesures["pieds"].items()},
    })
    rapport_json = json.dumps(rapport, ensure_ascii=False, indent=2)
    rig, donnees, branches = creer_squelette(chat, points, mesures)
    ponderer(chat, rig, xyz, mesures, donnees, branches)
    if image:
        message("Rendu du même pas de marche en trois quarts et de profil, puis retour au repos.")
        apercu(chat, rig, image, mesures)
    exporter(chat, rig, sortie)
    message("Mesures dans les unités du GLB importé :")
    print(rapport_json, flush=True)
    message(f"Nombre d'os : {len(rig.data.bones)}")
    print(f"ok {sortie}", flush=True)


if __name__ == "__main__":
    main()
