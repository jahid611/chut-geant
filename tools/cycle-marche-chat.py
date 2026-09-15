#!/usr/bin/env python3
"""Cycle mesuré dans Blender, puis échantillonné pour les 22 os Roblox.

blender --background --python tools/cycle-marche-chat.py -- [--sans-rendus]
Les seuls produits sont CatWalkCycle.luau et le dossier local cycle/.
Le solveur est exclusivement un outil de fabrication : aucune IK dans Roblox.

Références biomécaniques (les angles demandés sont des guides, pas des mesures
universelles) : doi:10.1152/jn.00524.2013 ; PMID:12106265 ; PMID:7952299.
Un os distal par pied dans ce rig : poignet/doigts ne sont pas indépendants.
"""

import argparse
import heapq
import json
import math
from pathlib import Path
import runpy
import subprocess
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/chat-maison-v2/cycle"
FPS = FRAMES = 30
SUPPORT = 0.6
STRIDE = 0.36  # distance par cycle complet / hauteur du maillage au repos
LIFT = 0.045
LEGS = {
    "ArriereG": (["CuisseG", "JambeG", "MetatarseG", "PatteArriereG"], 0.0),
    "AvantG": (["EpauleG", "AvantBrasG", "PatteAvantG"], 0.25),
    "ArriereD": (["CuisseD", "JambeD", "MetatarseD", "PatteArriereD"], 0.5),
    "AvantD": (["EpauleD", "AvantBrasD", "PatteAvantD"], 0.75),
}


def log(s):
    print("[cycle] " + s, flush=True)


def rx(angle):
    return Matrix.Rotation(angle, 3, "X")


def world_pose(bone, rotation):
    """Rotation absolue par rapport au repos ; conserver la tête héritée.

    L'évaluation du parent précède celle de son enfant.
    """
    rest = bone.bone.matrix_local
    parent = bone.parent
    base = parent.matrix @ parent.bone.matrix_local.inverted() @ rest if parent else rest.copy()
    desired = (rotation @ rest.to_3x3()).to_4x4()
    desired.translation = base.translation
    bone.matrix_basis = base.inverted() @ desired
    bpy.context.view_layer.update()
    return desired


def joint_yz(a, target, first, second, front):
    delta = target - a
    distance = np.linalg.norm(delta)
    if not abs(first - second) + 1e-7 < distance < first + second - 1e-7:
        raise RuntimeError(f"Cible inaccessible : {distance:.5f}, portée {first + second:.5f}")
    direction = delta / distance
    along = (first * first - second * second + distance * distance) / (2 * distance)
    bend = math.sqrt(max(first * first - along * along, 0))
    perpendicular = np.array([-direction[1], direction[0]])
    return a + along * direction + (1 if front else -1) * bend * perpendicular


def angle_between(rest, posed):
    return math.atan2(posed[1], posed[0]) - math.atan2(rest[1], rest[0])


def trajectory(phase, home, height):
    if phase < SUPPORT:
        return home[1] + STRIDE * height * (phase - SUPPORT / 2), 0.0, 0.0
    t = (phase - SUPPORT) / (1 - SUPPORT)
    # Hermite : même vitesse -STRIDE vers l'avant du monde aux deux contacts.
    # y recule à +STRIDE pendant l'appui (chat orienté -Y).
    s = t * t * (3 - 2 * t)
    y = home[1] + STRIDE * height * (SUPPORT / 2 - SUPPORT * s + (1 - SUPPORT) * (2*t**3 - 3*t*t + t))
    arch = math.sin(math.pi * t) ** 2
    return y, LIFT * height * arch, arch


def build_pose(rig, legs, height, phase):
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    wave = 2 * math.pi * phase
    drop = height * (-0.05 + 0.0075 * math.cos(2 * wave))
    root = rig.pose.bones["Racine"]
    root.location = root.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, drop))
    bpy.context.view_layer.update()
    # Deux oscillations verticales par cycle ; courbure latérale opposée des
    # lombaires/thorax. Cou et tête compensent la rotation de leurs ancêtres.
    world_pose(rig.pose.bones["ColonneLombaire"], Matrix.Rotation(math.radians(3) * math.sin(wave), 3, "Z") @ rx(math.radians(-6)))
    world_pose(rig.pose.bones["ColonneThoracique"], Matrix.Rotation(math.radians(-1.5) * math.sin(wave), 3, "Z") @ rx(math.radians(-6)))
    world_pose(rig.pose.bones["Cou"], Matrix.Identity(3))
    world_pose(rig.pose.bones["Tete"], Matrix.Identity(3))
    # Ondulation locale autour de la vraie courbe au repos, sans redressement.
    for i in range(1, 4):
        bone = rig.pose.bones[f"Queue{i}"]
        rest = bone.bone.matrix_local.to_3x3()
        rotation = (Matrix.Rotation(math.radians(1.5) * math.sin(wave - i * 0.65), 3, "Z")
                    @ rx(math.radians(1.0) * math.sin(wave - i * 0.7)))
        bone.matrix_basis = (rest.inverted() @ rotation @ rest).to_4x4()
    targets = {}
    for name, leg in legs.items():
        names, offset = LEGS[name]
        local_phase = (phase - offset) % 1
        y, z, curl = trajectory(local_phase, leg["home"], height)
        front = name.startswith("Avant")
        bones = [rig.pose.bones[n] for n in names]
        first = bones[0]
        base = first.parent.matrix @ first.parent.bone.matrix_local.inverted() @ first.bone.matrix_local
        origin = np.array(base.translation)[1:]
        # Orientation du pied : semelle à plat à l'appui, repli pendant le lever.
        foot_angle = math.radians(28 if front else 12) * curl
        rotated_pad = leg["pad_offsets"] @ np.array(rx(foot_angle)).T
        foot_delta = np.array([rotated_pad[:, 1].mean(), rotated_pad[:, 2].min()])
        target = np.array([y, z]) - foot_delta
        if not front:
            meta_angle = math.radians(-12) * curl
            meta_delta = np.array(rx(meta_angle) @ Vector(leg["heads"][-1] - leg["heads"][-2]))[1:]
            target -= meta_delta
        joint = joint_yz(origin, target, *leg["lengths"], front)
        a = angle_between(leg["segments"][0], joint - origin)
        b = angle_between(leg["segments"][1], target - joint)
        world_pose(bones[0], rx(a))
        world_pose(bones[1], rx(b))
        if not front:
            world_pose(bones[2], rx(meta_angle))
        world_pose(bones[-1], rx(foot_angle))
        targets[name] = {"phase": local_phase, "y": y, "z": z}
    bpy.context.view_layer.update()
    return drop, targets


def mesh_positions(chat):
    evaluated = chat.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        co = np.empty(len(mesh.vertices) * 3, dtype=np.float64)
        mesh.vertices.foreach_get("co", co)
        return co.reshape((-1, 3))
    finally:
        evaluated.to_mesh_clear()


def trace_tail(chat, xyz, m, r):
    """Coupes géodésiques depuis le bout : les cuisses ne sont pas des voisins.

    Souder les doublons des coutures UV pour parcourir la surface, sans changer
    le maillage. L'élargissement transversal marque l'entrée dans la croupe.
    Cette détection vise chat-maison-v2, orienté vers -Y.
    """
    _, unique, inverse = np.unique(np.round(xyz / m["H"], 6), axis=0,
                                   return_index=True, return_inverse=True)
    points = xyz[unique]
    adjacent = [[] for _ in points]
    for edge in chat.data.edges:
        a, b = inverse[list(edge.vertices)]
        length = float(np.linalg.norm(points[a] - points[b]))
        adjacent[a].append((b, length))
        adjacent[b].append((a, length))
    tip = int(points[:, 1].argmax())
    distance = np.full(len(points), np.inf)
    distance[tip] = 0
    pending = [(0.0, tip)]
    while pending:
        cost, i = heapq.heappop(pending)
        if cost != distance[i]:
            continue
        for j, length in adjacent[i]:
            candidate = cost + length
            if candidate < distance[j]:
                distance[j] = candidate
                heapq.heappush(pending, (candidate, j))
    step = m["H"] / 30
    sections, widths, centers = [], [], []
    for start in np.arange(0, m["H"], step):
        section = points[(distance >= start) & (distance < start + step)]
        if len(section) < 5:
            raise RuntimeError("Section de queue insuffisante ; contrôler le maillage.")
        width = float(np.ptp(section[:, 0]))
        # Ignorer le capuchon arrondi du bout dans la référence de diamètre.
        if len(widths) >= 8 and width > 1.45 * float(np.median(widths[2:])):
            boundary = float(start)
            break
        sections.append(start + step / 2)
        widths.append(width)
        centers.append(section.mean(axis=0))
    else:
        raise RuntimeError("Aucune séparation queue/croupe mesurable.")
    line = np.array(centers[::-1])
    for _ in range(2):
        line[1:-1] = (line[:-2] + 2 * line[1:-1] + line[2:]) / 4
    arc = np.r_[0, np.cumsum(np.linalg.norm(np.diff(line, axis=0), axis=1))]
    joints_at = np.linspace(0, arc[-1], 4)
    joints = np.column_stack([np.interp(joints_at, arc, line[:, k]) for k in range(3)])
    vertex_distance = distance[inverse]
    mass = 1 - r["lisse"](boundary - m["H"] * 0.04, boundary, vertex_distance)
    along = np.interp(vertex_distance, np.array(sections), arc[::-1])
    distribution = np.zeros((len(xyz), 3))
    previous = np.ones(len(xyz))
    for i in range(2):
        transition = r["lisse"](joints_at[i + 1] - m["H"] * 0.03,
                                 joints_at[i + 1] + m["H"] * 0.03, along)
        distribution[:, i] = previous * (1 - transition)
        previous *= transition
    distribution[:, 2] = previous
    m["queue"] = joints
    report = {"method": "coupes géodésiques depuis le bout, arrêt avant élargissement de la croupe",
              "joints": joints.tolist(), "centerline": line.tolist(),
              "boundaryDistance": boundary, "baseBlend": m["H"] * 0.04,
              "vertexCount": int(np.count_nonzero(mass)),
              "outsideWeightMax": float(mass[vertex_distance >= boundary].max()),
              "localAmplitudeDegrees": {"lateral": 1.5, "vertical": 1.0}}
    assert report["outsideWeightMax"] == 0
    log(f"Queue isolée : {report['vertexCount']} sommets ; repères {joints.tolist()}")
    return mass, distribution, report


def rigid_weights(chat, rig, xyz, m, definitions, branches, r, tail):
    """Segments rigides et raccords progressifs autour des articulations.

    Les articulations ont été ajustées aux coupes du maillage par le rig source.
    L'appartenance aux quatre membres est exclusive sous le ventre : aucune
    capsule élargie ne peut relier une patte avant à une patte arrière.
    """
    names = [d[0] for d in definitions]
    old = np.zeros((len(xyz), len(names)))
    for v in chat.data.vertices:
        for g in v.groups:
            old[v.index, names.index(chat.vertex_groups[g.group].name)] = g.weight
    members = list(LEGS)
    axes = []
    for name in members:
        chain = np.array([definitions[j][1] for j in branches[name]])
        order = np.argsort(chain[:, 2])
        axes.append(np.column_stack([np.interp(xyz[:, 2], chain[order, 2], chain[order, k]) for k in (0, 1)]))
    distances = np.stack([np.linalg.norm(xyz[:, :2] - axis, axis=1) for axis in axes], axis=1)
    owner = distances.argmin(axis=1)
    weights = np.zeros_like(old)
    queue_mass, queue_distribution, _ = tail
    limb_total = np.zeros(len(xyz))
    masks = {}
    for i, name in enumerate(members):
        ids = branches[name]
        root_z = definitions[ids[0]][1][2]
        vertical = 1 - r["lisse"](root_z - m["H"] * 0.04, root_z, xyz[:, 2])
        # Au-dessus du ventre, limiter le muscle à une section elliptique et
        # exclure le plan médian du tronc. Une grande capsule ronde entraînait
        # aussi le ventre derrière l'épaule, qui formait un pli triangulaire.
        scaled = (xyz[:, :2] - axes[i]) / np.array([m["W"] * 0.24, m["L"] * 0.06])
        radius = 1 - r["lisse"](0.75, 1.25, np.linalg.norm(scaled, axis=1))
        side = r["lisse"](m["W"] * 0.025, m["W"] * 0.20, np.abs(xyz[:, 0] - m["x"]))
        above_belly = r["lisse"](m["ventre"] - m["H"] * 0.04, m["ventre"], xyz[:, 2])
        radius = (1 - above_belly) + above_belly * radius * side
        mass = (owner == i) * vertical * radius * (1 - queue_mass)
        limb_total += mass
        masks[name] = mass
        # Raccord large aux coudes, genoux et jarrets : une bande trop courte
        # concentre la rotation sur quelques arêtes et étire la peau.
        # Les coussinets restent rigides grâce au raccord distal plus court.
        previous = np.ones(len(xyz))
        for j, idx in enumerate(ids):
            if j < len(ids) - 1:
                joint_z = definitions[ids[j + 1]][1][2]
                half_blend = m["H"] * (0.025 if j == len(ids) - 2 else 0.075)
                above = r["lisse"](joint_z - half_blend, joint_z + half_blend, xyz[:, 2])
                weights[:, idx] = mass * previous * above
                previous *= 1 - above
            else:
                weights[:, idx] = mass * previous
    weights[:, branches["queue"]] = queue_mass[:, None] * queue_distribution
    for branch, total in (("tronc", 1 - queue_mass - limb_total),):
        ids = branches[branch]
        sub = old[:, ids].copy()
        empty = sub.sum(axis=1) < 1e-8
        sub[empty, 0] = 1
        sub /= sub.sum(axis=1)[:, None]
        weights[:, ids] = sub * total[:, None]
    # Réduction stable aux quatre influences de Roblox.
    order = np.argsort(weights, axis=1)[:, :-4]
    np.put_along_axis(weights, order, 0, axis=1)
    weights /= weights.sum(axis=1)[:, None]
    assert np.isfinite(weights).all() and weights.min() >= -1e-8
    assert np.all(weights[queue_mass == 0][:, branches["queue"]] == 0)
    chat.vertex_groups.clear()
    groups = [chat.vertex_groups.new(name=n) for n in names]
    for i, row in enumerate(weights):
        for j in np.flatnonzero(row > 1e-8):
            groups[j].add([i], float(row[j]), "REPLACE")
    return masks, weights


def bake(chat, rig, legs, height):
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
    frames, measures = [], {name: [] for name in legs}
    for i in range(FRAMES + 1):
        bpy.context.scene.frame_set(i + 1)
        drop, targets = build_pose(rig, legs, height, (i % FRAMES) / FRAMES)
        rotations = {}
        for bone in rig.pose.bones:
            bone.rotation_mode = "QUATERNION"
            # Conjugaison par la rotation DE REPOS de l'os, sans les ancêtres
            # animés : c'est exactement le Bone.Transform local de Roblox.
            rest = bone.bone.matrix_local.to_quaternion()
            q = rest @ bone.rotation_quaternion @ rest.inverted()
            if q.w < 0:
                q.negate()
            axis, angle = q.to_axis_angle()
            v = axis * angle
            rotations[bone.name] = [-v.x, v.z, -v.y]
            bone.keyframe_insert("rotation_quaternion", frame=i + 1, group=bone.name)
            if bone.name == "Racine":
                bone.keyframe_insert("location", frame=i + 1, group=bone.name)
        frames.append({"rootY": drop / height, "rotations": rotations})
        vertices = mesh_positions(chat)
        for name, leg in legs.items():
            skin = vertices[leg["pad"]]
            measures[name].append({**targets[name], "skinMinZ": float(skin[:, 2].min()),
                                   "skinY": float(skin[:, 1].mean()),
                                   "contact": list(rig.pose.bones[LEGS[name][0][-1]].matrix
                                                   @ rig.data.bones[LEGS[name][0][-1]].matrix_local.inverted()
                                                   @ Vector(leg["rest_contact"]))})
    # Dupliquer uniquement la clé 31 dans Blender pour fermer la boucle ;
    # exporter les 30 poses uniques. Aucun doublon temporel dans Roblox.
    assert frames[0] == frames[-1], "Raccord de boucle différent"
    return frames[:FRAMES], measures


def verify_interpolation(chat, rig, legs, height, frames, xyz, weights, tail):
    """120 échantillons de la lecture Roblox, y compris l'intervalle 30 -> 1."""
    action = rig.animation_data.action
    rig.animation_data.action = None
    rows = {name: [] for name in legs}
    quaternions = []
    all_edges = np.array([e.vertices[:] for e in chat.data.edges])
    rest_edges = np.linalg.norm(xyz[all_edges[:, 1]] - xyz[all_edges[:, 0]], axis=1)
    zones = {}
    tail_mass = tail[0]
    zones["Queue"] = (tail_mass[all_edges].max(axis=1) > 0)
    for name, (names, _) in LEGS.items():
        ids = [chat.vertex_groups[n].index for n in names]
        member = weights[:, ids].sum(axis=1) > 0.95
        for joint in names[1:]:
            near = np.abs(xyz[:, 2] - rig.data.bones[joint].head_local.z) < height * 0.035
            zones[joint] = member[all_edges].all(axis=1) & near[all_edges].any(axis=1)
    zone_edges = {}
    for name, mask in zones.items():
        selected = mask & (rest_edges > height * 1e-5)
        assert selected.any(), f"Articulation sans arête mesurable : {name}"
        zone_edges[name] = (all_edges[selected], rest_edges[selected])
    strains = {name: [] for name in zones}
    outside_motion = 0.0
    for frame in frames:
        qs = {}
        for name, v in frame["rotations"].items():
            vector = Vector((-v[0], -v[2], v[1]))
            angle = vector.length
            q = Quaternion(vector / angle, angle) if angle > 1e-8 else Quaternion()
            rest = rig.data.bones[name].matrix_local.to_quaternion()
            qs[name] = rest.inverted() @ q @ rest
        quaternions.append(qs)
    # Arêtes à l'intérieur des segments rigides : mesure réelle sur la peau.
    edges = np.array([e.vertices[:] for e in chat.data.edges])
    rigid = weights.max(axis=1) > 0.999999
    same = weights.argmax(axis=1)[edges[:, 0]] == weights.argmax(axis=1)[edges[:, 1]]
    edges = edges[rigid[edges[:, 0]] & rigid[edges[:, 1]] & same]
    original = np.linalg.norm(xyz[edges[:, 1]] - xyz[edges[:, 0]], axis=1)
    valid = original > height * 1e-5
    edges, original = edges[valid], original[valid]
    min_edge, max_edge = 1.0, 1.0
    try:
        for i in range(FRAMES * 4):
            phase = i / (FRAMES * 4)
            first, blend = divmod(i / 4, 1)
            first = int(first)
            second = (first + 1) % FRAMES
            for bone in rig.pose.bones:
                bone.location = (0, 0, 0)
                bone.rotation_quaternion = quaternions[first][bone.name].slerp(quaternions[second][bone.name], blend)
            root_y = (1 - blend) * frames[first]["rootY"] + blend * frames[second]["rootY"]
            root = rig.pose.bones["Racine"]
            root.location = root.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, root_y * height))
            bpy.context.view_layer.update()
            vertices = mesh_positions(chat)
            for name, (zone, lengths) in zone_edges.items():
                strains[name].append(np.linalg.norm(vertices[zone[:, 1]] - vertices[zone[:, 0]], axis=1) / lengths)
            if i == 0:
                saved_tail = [rig.pose.bones[f"Queue{j}"].rotation_quaternion.copy() for j in range(1, 4)]
                for j in range(1, 4):
                    rig.pose.bones[f"Queue{j}"].rotation_quaternion = Quaternion()
                bpy.context.view_layer.update()
                neutral = mesh_positions(chat)
                outside_motion = float(np.linalg.norm((vertices - neutral)[tail_mass == 0], axis=1).max()) / height
                assert outside_motion < 1e-6, "La queue déplace la croupe ou les pattes"
                for j, rotation in enumerate(saved_tail, 1):
                    rig.pose.bones[f"Queue{j}"].rotation_quaternion = rotation
                bpy.context.view_layer.update()
            ratios = np.linalg.norm(vertices[edges[:, 1]] - vertices[edges[:, 0]], axis=1) / original
            min_edge, max_edge = min(min_edge, float(ratios.min())), max(max_edge, float(ratios.max()))
            for name, leg in legs.items():
                local_phase = (phase - LEGS[name][1]) % 1
                skin = vertices[leg["pad"]]
                target_y, _, _ = trajectory(local_phase, leg["home"], height)
                last = rig.pose.bones[LEGS[name][0][-1]]
                contact = last.matrix @ last.bone.matrix_local.inverted() @ Vector(leg["rest_contact"])
                top = rig.pose.bones[LEGS[name][0][0]].head
                rest_length = np.linalg.norm(leg["rest_contact"] - leg["heads"][0])
                rows[name].append({"phase": local_phase, "z": float(skin[:, 2].min()) / height,
                                   "yError": (float(skin[:, 1].mean()) - target_y) / height,
                                   "compression": float((contact - top).length / rest_length)})
    finally:
        rig.animation_data.action = action
        bpy.context.scene.frame_set(1)
    result = {"samples": FRAMES * 4, "rigidEdgeRatio": [min_edge, max_edge], "legs": {}, "anglesDegrees": {}}
    result["jointEdgeRatios"] = {name: dict(zip(("min", "p01", "median", "p99", "max"),
                                                np.quantile(np.concatenate(values), [0, 0.01, 0.5, 0.99, 1]).tolist()))
                                  for name, values in strains.items()}
    result["tailOutsideMotionHeight"] = outside_motion
    assert min_edge > 0.999 and max_edge < 1.001, "Un segment rigide change de longueur"
    for name, values in rows.items():
        stance = [v for v in values if v["phase"] < SUPPORT - 1e-7]
        spread = float(np.ptp([v["z"] for v in stance]))
        peak = max(v["z"] for v in values)
        slip = max(abs(v["yError"]) for v in stance)
        assert spread < 0.01 and slip < 0.002, f"Appui incorrect : {name}, {spread}, {slip}"
        assert 0.04 < peak < 0.051, f"Lever incorrect : {name}, {peak}"
        assert max(v["compression"] for v in values) < 1.005, f"Patte étendue au-delà du repos : {name}"
        result["legs"][name] = {"stanceVariationHeight": spread, "stanceYErrorHeight": slip,
                                 "swingHeight": peak,
                                 "compression": [min(v["compression"] for v in values), max(v["compression"] for v in values)]}
    for name in rig.data.bones.keys():
        angles = [math.degrees(f["rotations"][name][0]) for f in frames]
        result["anglesDegrees"][name] = [min(angles), max(angles)]
    log("Interpolation vérifiée : " + json.dumps(result, ensure_ascii=False))
    return result


def export_luau(frames, height, rig):
    lines = ["--!strict", "", "-- Généré par tools/cycle-marche-chat.py ; ne pas éditer à la main.",
             "-- Blender : X gauche, -Y avant, Z haut. Roblox : X droite, Y haut, -Z avant.",
             "-- Conversion de position/axe : (x, y, z) Blender -> (-x, z, y) Roblox.",
             "-- Chaque Vector3 est un VECTEUR DE ROTATION (axe * radians), exprimé dans",
             "-- les axes du chat (droite, haut, avant), pas un triplet d'angles Euler.",
             "-- Conjuguer par le repère de repos de chaque os, puis interpoler les rotations.",
             "-- rootY et strideHeight sont en fractions de la hauteur AU REPOS.",
             "-- Réimporter cycle/chat-poids-corriges.fbx : les nouveaux poids sont nécessaires.",
             "-- Les doigts partagent l'os du pied : pas de rotation digitale indépendante.",
             "return {", f"    fps = {FPS},", f"    frameCount = {FRAMES},", f"    strideHeight = {STRIDE},",
             f"    strideStudsAt81 = {STRIDE * 81:.5f},", f"    support = {SUPPORT},", f"    liftHeight = {LIFT},",
             "    bones = {"]
    for name in rig.data.bones.keys():
        lines.append(f'        "{name}",')
    lines += ["    },", "    frames = {"]
    for frame in frames:
        lines += ["        {", f"            rootY = {frame['rootY']:.8f},", "            rotations = {"]
        for name, v in frame["rotations"].items():
            lines.append(f"                {name} = Vector3.new({v[0]:.8f}, {v[1]:.8f}, {v[2]:.8f}),")
        lines += ["            },", "        },"]
    lines += ["    },", "}", ""]
    destination = ROOT / "src/shared/CatWalkCycle.luau"
    destination.write_text("\n".join(lines), encoding="utf-8")
    subprocess.run(["stylua", str(destination)], check=True)


def render_scene(chat, rig, height, args):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 800, 600
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("Fond de contrôle")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.34, 0.38, 0.44, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    bpy.ops.mesh.primitive_plane_add(size=height * 200, location=(0, 0, -height * 0.002))
    floor = bpy.context.object
    floor.name = "Sol de contrôle Blender"
    mat = bpy.data.materials.new("Sol gris")
    mat.diffuse_color = (0.19, 0.21, 0.25, 1)
    floor.data.materials.append(mat)
    center = Vector((0, 0.14, height * 0.51))
    for index, direction in enumerate(((2, -2, 3), (-2, -1, 2), (0, 3, 2))):
        light = bpy.data.lights.new(f"Éclairage {index}", "AREA")
        light.energy = 100 * height**2
        light.size = height * 2
        obj = bpy.data.objects.new(light.name, light)
        scene.collection.objects.link(obj)
        obj.location = center + Vector(direction) * height
        obj.rotation_euler = (center - obj.location).to_track_quat("-Z", "Y").to_euler()
    data = bpy.data.cameras.new("Profil orthographique")
    camera = bpy.data.objects.new(data.name, data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    data.type = "ORTHO"
    data.ortho_scale = height * 1.95
    data.clip_start, data.clip_end = 0.001, 100
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, FRAMES
    for prefix, indices, direction in (
        ("profil", range(FRAMES), (-3, 0, 0)),
        ("trois-quarts", (0, 4, 8, 11, 15, 19, 23, 26), (-3, -1.7, 0.7)),
    ):
        camera.location = center + Vector(direction) * height
        camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
        for n, i in enumerate(indices):
            scene.frame_set(i + 1)
            scene.render.filepath = str(OUT / f"{prefix}-{n + 1:02d}.png")
            bpy.ops.render.render(write_still=True)
            log(f"Rendu {prefix} {n + 1}")
    camera.location = center + Vector((-3, 0, 0)) * height
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.frame_set(1)
    # Conserver l'action et le mesh de contrôle pour réouvrir exactement les poses.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.preferences.filepaths.file_preview_type = "NONE"
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "cycle-marche.blend"))
    ffmpeg = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    subprocess.run(ffmpeg + ["-framerate", str(FPS), "-i", str(OUT / "profil-%02d.png"),
                            "-vf", "scale=400:300,tile=6x5:padding=4:margin=4:color=white",
                            "-frames:v", "1", str(OUT / "planche-profils.png")], check=True)
    subprocess.run(ffmpeg + ["-stream_loop", "7", "-framerate", str(FPS), "-i", str(OUT / "profil-%02d.png"),
                            "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p",
                            "-movflags", "+faststart", str(OUT / "marche-profil-boucle.mp4")], check=True)


def export_fbx(chat, rig, r):
    """Même export Roblox que le rig source, textures locales sans TemporaryDirectory.

    Les répertoires temporaires 0700 de Python sont illisibles par ce sandbox
    Windows. Les PNG font partie des produits locaux du cycle et restent visibles.
    """
    images = set()
    for material in chat.data.materials:
        if material and material.use_nodes:
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    images.add(node.image)
    for i, img in enumerate(sorted(images, key=lambda image: image.name)):
        img.filepath_raw = str(OUT / f"texture-chat-{i:02d}.png")
        img.file_format = "PNG"
        img.save()
        data = Path(img.filepath_raw).read_bytes()
        img.pack(data=data, data_len=len(data))
    r["selection"](chat, rig)
    rig.data.pose_position = "REST"
    chat.animation_data_clear()
    rig.animation_data_clear()
    bpy.context.view_layer.update()
    destination = OUT / "chat-poids-corriges.fbx"
    result = bpy.ops.export_scene.fbx(
        filepath=str(destination), check_existing=False, use_selection=True,
        object_types={"ARMATURE", "MESH"}, add_leaf_bones=False,
        use_armature_deform_only=True, armature_nodetype="NULL",
        bake_anim=False, use_mesh_modifiers=True, mesh_smooth_type="FACE",
        path_mode="COPY", embed_textures=True, axis_forward="-Z", axis_up="Y",
        primary_bone_axis="Y", secondary_bone_axis="X", apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS", use_space_transform=True, bake_space_transform=False,
    )
    assert "FINISHED" in result and destination.stat().st_size > 0, "Échec export FBX"
    log(f"FBX avec poids corrigés : {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sans-rendus", action="store_true")
    parser.add_argument("--samples", type=int, default=16)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    OUT.mkdir(parents=True, exist_ok=True)
    r = runpy.run_path(str(ROOT / "tools/rig-chat-gpt.py"))
    chat = r["importer"](ROOT / "assets/models/glb/chat-maison-v2.glb")
    points, normals = r["surface"](chat.data)
    points, xyz, orientation = r["orienter"](chat, points, normals)
    m = r["mesurer"](points, xyz, orientation)
    tail = trace_tail(chat, xyz, m, r)
    rig, definitions, branches = r["creer_squelette"](chat, points, m)
    r["ponderer"](chat, rig, xyz, m, definitions, branches)
    height = float(np.ptp(xyz[:, 2]))
    fractions, weights = rigid_weights(chat, rig, xyz, m, definitions, branches, r, tail)
    legs = {}
    for name, (names, _) in LEGS.items():
        indices = np.flatnonzero((fractions[name] > 0.45) & (xyz[:, 2] < height * 0.075))
        assert len(indices) > 10, f"Coussinet non mesurable : {name}"
        lowest = float(xyz[indices, 2].min())
        pad = indices[xyz[indices, 2] < lowest + height * 0.006]
        home = xyz[pad].mean(axis=0)
        home[2] = lowest
        rest_contact = home.copy()
        if name.startswith("Avant"):
            home[1] -= height * 0.04
        log(f"Coussinet {name} : {home.tolist()}, {len(pad)} sommets")
        heads = np.array([rig.data.bones[n].head_local[:] for n in names])
        segments = np.diff(heads, axis=0)[:2, 1:]
        legs[name] = {"heads": heads, "home": home, "rest_contact": rest_contact,
                      "pad": pad, "pad_offsets": xyz[pad] - heads[-1],
                      "segments": segments, "lengths": np.linalg.norm(segments, axis=1)}
    frames, measurements = bake(chat, rig, legs, height)
    verification = verify_interpolation(chat, rig, legs, height, frames, xyz, weights, tail)
    report = {"fps": FPS, "frames": FRAMES, "height": height, "strideHeight": STRIDE,
              "support": SUPPORT, "liftHeight": LIFT, "weights": "segments rigides, fondu 15 % H aux articulations et 5 % H aux pieds, skinning linéaire",
              "verification": verification, "tail": tail[2],
              "legs": measurements}
    for name, values in measurements.items():
        stance = [v for v in values[:FRAMES] if v["phase"] < SUPPORT]
        spread = np.ptp([v["skinMinZ"] for v in stance]) / height
        log(f"{name} variation peau en appui : {spread:.3%} de H")
    (OUT / "mesures.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    export_luau(frames, height, rig)
    if not args.sans_rendus:
        render_scene(chat, rig, height, args)
        # Le FBX ne contient que le chat, son squelette et les poids corrigés.
        # Conserver le .blend animé avant l'exporteur source qui efface l'action.
    export_fbx(chat, rig, r)


if __name__ == "__main__":
    main()
