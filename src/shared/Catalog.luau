--!strict

--[[
    Catalog
    Tout ce qui s'achete en tetines dans la boutique (liste d'idees validee par l'utilisateur le 14/09/2026).
    Partage serveur (ShopService verifie prix et niveaux) et client (Shop affiche les cartes).

    kind :
    - "ability"  : pouvoir actif a recharge, achete une fois (AbilityService) ;
    - "upgrade"  : amelioration permanente a niveaux (prices[n] = prix du niveau n) ;
    - "chest"    : coffres a jouets (Chest : coffre suivant ; GoldChest : dore un coffre, revenu x2) ;
    - "cosmetic" : apparence, achetee une fois puis equipee (slot) ou posee (decor) ;
    - "weapon"   : arme de la boite a outils (CatalogWeapons), achetee une fois puis equipee.
    Possession : profil joueur owned[id] = niveau (1 = achete), publie en attribut « Owned_<id> » du joueur.
    icon : cle d'Ui/Assets, une icone propre a chaque article (« rbxassetid://0 » tant qu'elle n'est pas televersee :
    la boutique montre alors l'icone de la categorie).
    needs3D : l'article utilise un modele 3D ; un cosmetique reste « Bientôt » tant que son modele n'est pas dans
    ServerStorage (ShopService publie Dispo_<id> en attribut de ReplicatedStorage), une amelioration jamais.
]]

export type Kind = "ability" | "upgrade" | "chest" | "cosmetic" | "weapon"

export type Item = {
    id: string,
    tab: string,
    kind: Kind,
    name: string,
    description: string,
    icon: string,
    prices: { number },
    slot: string?, -- cosmetiques equipables : "trail" | "dance" | "outline" | "skin" | "lamp" ; "decor" = objet pose
    needs3D: boolean?,
    -- recompense de mission, jamais en vente (bouton « Mission » dans la boutique tant qu'elle n'est pas gagnee)
    exclusive: boolean?,
}

local Tuning = require(script.Parent:WaitForChild("Tuning"))

local TABS = { "Pouvoirs", "Améliorations", "Coffres", "Armes", "Cosmétiques", "Tétines" }

local ITEMS: { Item } = {
    -- Pouvoirs actifs (touches et barre de pouvoirs : AbilityController)
    {
        id = "Fury",
        tab = "Pouvoirs",
        kind = "ability",
        name = "Furie",
        description = string.format("Cours très vite pendant %d s. Très bruyant !", Tuning.FURY_SECONDS),
        icon = "pouvoirFurie",
        prices = { Tuning.FURY_PRICE },
    },
    {
        id = "MagicPacifier",
        tab = "Pouvoirs",
        kind = "ability",
        name = "Tétine magique",
        description = "Fait baisser la jauge de bruit de 30 %.",
        icon = "pouvoirTetine",
        prices = { 6000 },
    },
    {
        id = "DecoyRattle",
        tab = "Pouvoirs",
        kind = "ability",
        name = "Hochet leurre",
        description = "Lance-le : le bébé regarde ailleurs 4 s.",
        icon = "pouvoirHochet",
        prices = { 9000 },
    },
    {
        id = "ShieldPlush",
        tab = "Pouvoirs",
        kind = "ability",
        name = "Doudou bouclier",
        description = "Annule ta prochaine propulsion.",
        icon = "pouvoirDoudou",
        prices = { 12000 },
    },
    {
        id = "SuctionGun",
        tab = "Pouvoirs",
        kind = "ability",
        name = "Ventouse",
        description = "Vise un jouet pour l'attirer. Niv. 2 : jouets lourds et plus loin.",
        icon = "pouvoirVentouse",
        prices = { 15000, 60000 },
    },
    {
        id = "ShadowCape",
        tab = "Pouvoirs",
        kind = "ability",
        name = "Cape d'ombre",
        description = "Invisible pour le bébé et maman 5 s.",
        icon = "pouvoirCape",
        prices = { 20000 },
    },
    {
        id = "Lullaby",
        tab = "Pouvoirs",
        kind = "ability",
        name = "Berceuse",
        description = "Rendort le bébé pour tout le serveur.",
        icon = "pouvoirBerceuse",
        prices = { 40000 },
    },

    -- Ameliorations permanentes
    {
        id = "QuietSlippers",
        tab = "Améliorations",
        kind = "upgrade",
        name = "Chaussons silencieux",
        description = "Chaque niveau : moins de bruit en marchant.",
        icon = "articleChaussons",
        prices = { 2500, 6000, 15000, 35000, 80000 },
    },
    {
        id = "StrongArms",
        tab = "Améliorations",
        kind = "upgrade",
        name = "Bras costauds",
        description = "Chaque niveau : porte les jouets plus vite.",
        icon = "articleBras",
        prices = { 8000, 18000, 40000, 90000, 200000 },
    },
    {
        id = "Backpack",
        tab = "Améliorations",
        kind = "upgrade",
        name = "Sac à dos",
        description = "Porte 2 petits jouets à la fois.",
        icon = "ameliorationSac",
        prices = { 50000 },
        needs3D = true,
    },
    {
        id = "Magnet",
        tab = "Améliorations",
        kind = "upgrade",
        name = "Aimant à tétines",
        description = "Chaque niveau : +10 % de tétines.",
        icon = "ameliorationAimant",
        prices = { 10000, 30000, 80000 },
    },
    {
        id = "KeenEar",
        tab = "Améliorations",
        kind = "upgrade",
        name = "Oreille fine",
        description = "Entends maman et le bébé arriver plus tôt.",
        icon = "ameliorationOreille",
        prices = { 12000, 35000 },
    },

    -- Coffres
    {
        id = "Chest",
        tab = "Coffres",
        kind = "chest",
        name = "Coffre à jouets",
        description = "12 jouets de plus dans ta base !",
        icon = "articleCoffre",
        prices = { 5000, 5000, 5000 },
    },
    {
        id = "GoldChest",
        tab = "Coffres",
        kind = "chest",
        name = "Coffre doré",
        description = "Double le revenu d'un de tes coffres.",
        icon = "coffreDore",
        prices = { 100000, 250000, 500000, 1000000 },
    },

    -- Cosmetiques
    {
        id = "TrailRainbow",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "trail",
        name = "Traînée arc-en-ciel",
        description = "Une traînée qui te suit partout.",
        icon = "iconeTraineeArc",
        prices = { 5000 },
    },
    {
        id = "TrailStars",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "trail",
        name = "Traînée d'étoiles",
        description = "Des petites étoiles derrière toi.",
        icon = "iconeTraineeEtoiles",
        prices = { 8000 },
    },
    {
        id = "TrailHearts",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "trail",
        name = "Traînée de cœurs",
        description = "Des cœurs roses derrière toi.",
        icon = "iconeTraineeCoeurs",
        prices = { 12000 },
    },
    {
        id = "DanceJoy",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "dance",
        name = "Danse de la joie",
        description = "Touche B pour danser.",
        icon = "iconeDanseJoie",
        prices = { 7500 },
    },
    {
        id = "DanceRobot",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "dance",
        name = "Danse du robot",
        description = "Touche B pour danser.",
        icon = "iconeDanseRobot",
        prices = { 10000 },
    },
    {
        id = "DanceSpin",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "dance",
        name = "Danse toupie",
        description = "Touche B pour tourner sur toi-même.",
        icon = "iconeDanseToupie",
        prices = { 15000 },
    },
    {
        id = "OutlineGold",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "outline",
        name = "Contour doré",
        description = "Tes jouets volés brillent d'or dans tes coffres.",
        icon = "iconeContourDore",
        prices = { 20000 },
    },
    {
        id = "OutlineRainbow",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "outline",
        name = "Contour arc-en-ciel",
        description = "Tes jouets volés changent de couleur.",
        icon = "iconeContourArc",
        prices = { 50000 },
    },
    {
        id = "DecorLights",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "decor",
        name = "Guirlande lumineuse",
        description = "Décore ta base.",
        icon = "iconeDecorGuirlande",
        prices = { 8000 },
        needs3D = true,
    },
    {
        id = "DecorTent",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "decor",
        name = "Petit tipi",
        description = "Décore ta base.",
        icon = "iconeDecorTipi",
        prices = { 15000 },
        needs3D = true,
    },
    {
        id = "DecorBeanbag",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "decor",
        name = "Pouf moelleux",
        description = "Décore ta base.",
        icon = "iconeDecorPouf",
        prices = { 12000 },
        needs3D = true,
    },
    {
        id = "DecorStarLamp",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "decor",
        name = "Lampe étoile",
        description = "Décore ta base.",
        icon = "iconeDecorLampe",
        prices = { 20000 },
        needs3D = true,
    },
    {
        id = "DecorTrophy",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "decor",
        name = "Trophée du voleur",
        description = "Décore ta base.",
        icon = "iconeDecorTrophee",
        prices = { 30000 },
        needs3D = true,
    },
    -- Le modele Tripo « capuche dino » est un petit personnage entier en costume : il devient un decor de base.
    {
        id = "DecorDinoPlush",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "decor",
        name = "Peluche dino",
        description = "Décore ta base.",
        icon = "iconeDecorDino",
        prices = { 25000 },
        needs3D = true,
    },
    -- Accessoire porte sur la tete (modele 3D local, TRELLIS 2).
    {
        id = "SkinBunny",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "skin",
        name = "Oreilles de lapin",
        description = "Des grandes oreilles toutes douces.",
        icon = "iconeOreillesLapin",
        prices = { 25000 },
        needs3D = true,
    },
    -- Lampe frontale : lumiere douce devant la tete (CosmeticService), bien utile pendant la panne de veilleuse.
    {
        id = "HeadLamp",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "lamp",
        name = "Lampe frontale",
        description = "Éclaire devant toi, même dans le noir.",
        icon = "iconeDecorLampe",
        prices = { 18000 },
    },
    -- Exclusif : recompense de la mission du jour « Vole la tetine du bebe » (PacifierMissionService).
    {
        id = "TrailPacifier",
        tab = "Cosmétiques",
        kind = "cosmetic",
        slot = "trail",
        name = "Traînée de la tétine d'or",
        description = "Exclusif : vole la tétine du bébé.",
        icon = "pouvoirTetine",
        prices = { 0 },
        exclusive = true,
    },
}

local Catalog = {}

Catalog.TABS = table.freeze(TABS)

-- Listes complementaires tenues a part (un fichier par domaine) : decors de la boite a outils Roblox et armes.
for _, extra in { script.Parent:WaitForChild("CatalogDecor"), script.Parent:WaitForChild("CatalogWeapons") } do
    local ok, list = pcall(require, extra)
    if ok and typeof(list) == "table" then
        for _, item in list :: { Item } do
            table.insert(ITEMS, item)
        end
    end
end

local byId: { [string]: Item } = {}
for _, item in ITEMS do
    byId[item.id] = table.freeze(item)
end

function Catalog.Get(id: string): Item?
    return byId[id]
end

function Catalog.All(): { Item }
    return ITEMS
end

-- Nombre de niveaux (1 pour un achat unique).
function Catalog.MaxLevel(item: Item): number
    return #item.prices
end

-- Prix du prochain niveau, ou nil si le maximum est atteint.
function Catalog.NextPrice(item: Item, level: number): number?
    return item.prices[level + 1]
end

return table.freeze(Catalog)
