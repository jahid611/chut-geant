#!/usr/bin/env node
/**
 * Charge dans Studio (via le daemon MCP) tous les modeles du registre qui ont
 * une place dans la table ci-dessous, a leur echelle de jeu.
 *
 *   node tools/load-assets.mjs            tout ce qui est au registre et dans la table
 *   node tools/load-assets.mjs meuble-    seulement les noms qui commencent par ce prefixe
 *
 * Echelle en studs sur la plus grande dimension ; un joueur mesure environ 5 studs.
 * Les modeles sont ancres, leur pivot recentre sans rotation (voir ToySpawnService).
 * Un modele deja present sous le meme nom est remplace.
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const registry = JSON.parse(fs.readFileSync(path.join(root, 'assets', 'models', 'registry.json'), 'utf8'));

// nom au registre -> [dossier dans ServerStorage, nom de l'instance, taille en studs]
const TABLE = {
    'bebe-pleure': ['BabyParts', 'BodyCrying', 160],
    'bebe-corps-dort': ['BabyParts', 'BodySleeping', 160],
    'bebe-tetine': ['BabyParts', 'Pacifier', 30],

    'base-boite-chaussures': ['BaseModels', 'ShoeBox', 36],
    'base-pantoufle': ['BaseModels', 'Slipper', 40],
    'base-boite-mouchoirs': ['BaseModels', 'TissueBox', 30],
    'base-boite-cereales': ['BaseModels', 'CerealBox', 40],
    'base-tiroir': ['BaseModels', 'Drawer', 36],
    'base-carton': ['BaseModels', 'MovingBox', 40],
    // Pantoufle lapin ouverte au talon : premiere base ou l'on entre, a l'echelle d'une cachette (joueur = 5 studs).
    'base-pantoufle2': ['BaseModels', 'Slipper2', 60],

    // Jouets refaits sur Tripo : remplacent les versions TRELLIS dans ToyModels (le canard reste celui de TRELLIS).
    canard: ['ToyModels', 'Duck', 8],
    'jouet-bloc': ['ToyModels', 'Block', 8],
    'jouet-voiture': ['ToyModels', 'Car', 8],
    'jouet-dino': ['ToyModels', 'Dino', 8],
    'jouet-toupie': ['ToyModels', 'Top', 8],
    'jouet-robot': ['ToyModels', 'Robot', 14],
    'jouet-fusee': ['ToyModels', 'Rocket', 14],
    'jouet-chateau': ['ToyModels', 'Castle', 20],
    'jouet-console': ['ToyModels', 'Console', 20],
    'jouet-nounours': ['ToyModels', 'Teddy', 14],
    'jouet-ours-orange': ['ToyModels', 'TumblerBear', 10],
    // Jouet musical : version au logo de marque repeint en corail (tools/recolor-logo.py). Ne jamais charger
    // « jouet-colore-lisse » (107512102208623) : il porte encore le logo.
    'jouet-colore-rouge': ['ToyModels', 'MusicToy', 10],
    // Ballon, objet lourd : ~3 fois la hauteur d'un joueur (5 studs), comme un gros ballon de bebe pour un petit voleur.
    'jouet-balle-emoji': ['ToyModels', 'EmojiBall', 16],
    'jouet-cactus': ['ToyModels', 'Cactus', 10],
    'jouet-pyramide': ['ToyModels', 'RingStack', 9],
    // Cheval a bascule, objet lourd : un peu plus grand que les autres jouets, sans exces. Version au logo de marque
    // efface (tools/recolor-logo.py mode « tache ») ; ne jamais charger « jouet-cheval-bascule-lisse » (logo visible).
    'jouet-cheval-propre': ['ToyModels', 'RockingHorse', 22],

    'meuble-berceau': ['DecorModels', 'Crib', 220],
    // Berceau v2 (Tripo, avec couverture) : remplace le premier dans la chambre.
    'meuble-berceau2': ['DecorModels', 'Crib2', 220],
    'meuble-mobile': ['DecorModels', 'Mobile', 60],
    'meuble-commode': ['DecorModels', 'Dresser', 150],
    'meuble-veilleuse': ['DecorModels', 'NightLamp', 40],
    'meuble-veilleuse2': ['DecorModels', 'NightLamp2', 40],
    'meuble-coffre': ['DecorModels', 'ToyChest', 90],
    'meuble-etagere': ['DecorModels', 'WallShelf', 80],
    'meuble-hochet': ['DecorModels', 'Rattle', 20],
    'meuble-tapis': ['DecorModels', 'Rug', 380],
    // porte de la chambre (mini-jeu « Maman arrive ! »), hauteur de l'ouverture du mur droit
    'meuble-porte': ['DecorModels', 'BedroomDoor', 290],
    // la maman du mini-jeu « Maman arrive ! », mise a DOOR_H - 20 par la recette. Modele Tripo envoye par
    // l'utilisateur (plus propre que la premiere version Higgsfield « maman », gardee au registre).
    'maman-tripo': ['DecorModels', 'Mom', 270],
    // Boutique complete (15/09/2026). Tripo (utilisateur) : doudou, sac, coffre dore, trophee, peluche dino ;
    // TRELLIS 2 local : ventouse, decors, oreilles, cuisine. Tailles en studs a l'echelle des joueurs (~5 studs).
    'boutique-doudou-lapin': ['DecorModels', 'ShieldPlush', 6],
    'boutique-sac-a-dos': ['DecorModels', 'Backpack', 2.6],
    'boutique-coffre-dore': ['DecorModels', 'GoldChest', 70],
    'boutique-ventouse': ['DecorModels', 'SuctionCup', 3],
    'boutique-trophee': ['CosmeticModels', 'DecorTrophy', 12],
    'boutique-capuche-dino': ['CosmeticModels', 'DecorDinoPlush', 14],
    'boutique-oreilles-lapin': ['CosmeticModels', 'SkinBunny', 3],
    'decor-pouf': ['CosmeticModels', 'DecorBeanbag', 12],
    'decor-tipi': ['CosmeticModels', 'DecorTent', 30],
    'decor-lampe-etoile': ['CosmeticModels', 'DecorStarLamp', 10],
    'decor-guirlande': ['CosmeticModels', 'DecorLights', 20],
    'decor-panneau-classement': ['DecorModels', 'LeaderboardBoard', 40],
    // trampoline pres du berceau pour sauter sur le matelas (TrampolineService)
    'decor-trampoline': ['DecorModels', 'Trampoline', 40],
    'cuisine-frigo': ['KitchenModels', 'Fridge', 260],
    'cuisine-table': ['KitchenModels', 'Table', 160],
    'cuisine-chaise-haute': ['KitchenModels', 'HighChair', 170],
    'cuisine-plan-travail': ['KitchenModels', 'Counter', 200],
    'cuisine-cuisiniere': ['KitchenModels', 'Stove', 190],
    // Bibliotheque v2 (Tripo, 14:30) : remplace la premiere sous le meme nom d'instance.
    'meuble-bibliotheque-v2': ['DecorModels', 'Bookcase', 200],
    'meuble-anneaux': ['DecorModels', 'StackingRings', 30],
};

// La version lissee (lissage B : smooth-glb.py forme 40 0.5), televersee sous "<nom>-lisse", passe devant l'originale.
const assetOf = name => registry[`${name}-lisse`]?.assetId ?? registry[name]?.assetId;
const prefix = process.argv[2] ?? '';
const rows = Object.entries(TABLE)
    .filter(([name]) => name.startsWith(prefix) && assetOf(name))
    .map(([name, [folder, instance, size]]) => `{ "${folder}", "${instance}", ${assetOf(name)}, ${size} }`);

if (rows.length === 0) {
    console.log('rien a charger (registre vide pour ces noms)');
    process.exit(0);
}

const code = `local IS = game:GetService("InsertService")
local SS = game:GetService("ServerStorage")
local out = {}
for _, row in { ${rows.join(', ')} } do
    local folderName, instanceName, assetId, size = row[1], row[2], row[3], row[4]
    local folder = SS:FindFirstChild(folderName) or Instance.new("Folder")
    folder.Name = folderName
    folder.Parent = SS
    local ok, container = pcall(function() return IS:LoadAsset(assetId) end)
    if not ok then
        table.insert(out, instanceName .. " ECHEC " .. tostring(container))
        continue
    end
    local old = folder:FindFirstChild(instanceName)
    if old then old:Destroy() end
    container.Name = instanceName
    for _, d in container:GetDescendants() do
        if d:IsA("BasePart") then d.Anchored = true end
    end
    local _, s = container:GetBoundingBox()
    container:ScaleTo(size / math.max(s.X, s.Y, s.Z))
    local cf = container:GetBoundingBox()
    container.WorldPivot = CFrame.new(cf.Position)
    container.Parent = folder
    table.insert(out, folderName .. "." .. instanceName)
end
return table.concat(out, " | ")`;

const result = execFileSync('node', [path.join(root, 'tools', 'mcpd.mjs'), 'execute_luau', JSON.stringify({ code })], {
    encoding: 'utf8',
});
console.log(result.trim());
