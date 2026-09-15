--!strict

--[[
    ToysPackA
    Jouets supplementaires, lot A (modeles gratuits de la boite a outils Roblox, theme chambre de bebe), fusionnes
    dans Shared/Toys. Meme forme qu'un jouet : id (PascalCase, unique), displayName (francais), rarity, carriers,
    incomePerSecond. Modele : ServerStorage.ToyModels.<id>. Provenance : docs/jouets-lot-a.md.
    Theme : peluches et animaux en peluche, poupees et figurines, vehicules jouets, jouets musicaux.
]]

type Toy = {
    id: string,
    displayName: string,
    rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary",
    carriers: number,
    incomePerSecond: number,
}

local function toy(
    id: string,
    displayName: string,
    rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary",
    carriers: number,
    income: number
): Toy
    return { id = id, displayName = displayName, rarity = rarity, carriers = carriers, incomePerSecond = income }
end

local TOYS: { Toy } = {
    -- Communs
    toy("MaracasPair", "Maracas", "Common", 1, 2),
    toy("Tambourine", "Tambourin", "Common", 1, 2),
    toy("Harmonica", "Harmonica", "Common", 1, 1),
    toy("ToySoldierGreen", "Soldat de plomb vert", "Common", 1, 2),
    toy("ToySoldierRifle", "Petit soldat", "Common", 1, 2),
    toy("SmallWhiteCar", "Petite voiture blanche", "Common", 1, 3),
    toy("WoodenCarOld", "Voiture en bois ancienne", "Common", 1, 3),
    toy("WoodenToyTruck", "Camion en bois", "Common", 1, 3),
    toy("WoodenCarBrown", "Voiture en bois", "Common", 1, 3),
    toy("RedToyTruck", "Camionnette rouge", "Common", 1, 4),
    toy("ChickPlush", "Poussin en peluche", "Common", 1, 2),
    toy("CatPlush", "Chat en peluche", "Common", 1, 3),
    toy("DogPlush", "Chien en peluche", "Common", 1, 3),
    toy("OwlPlush", "Chouette en peluche", "Common", 1, 2),
    toy("PurpleBlobPlush", "Peluche kawaii violette", "Common", 1, 3),
    toy("MonkeyPlush", "Singe en peluche", "Common", 1, 3),
    toy("BlueTeddy", "Nounours bleu", "Common", 1, 4),
    toy("Ukulele", "Ukulélé", "Common", 1, 4),
    toy("Accordion", "Accordéon", "Common", 1, 4),
    toy("HuskyPlush", "Husky en peluche", "Common", 1, 3),

    -- Peu communs
    toy("YellowBearPlush", "Ourson jaune", "Uncommon", 1, 6),
    toy("BrownBearPlush", "Ourson marron", "Uncommon", 1, 6),
    toy("WhiteBearPlush", "Ourson blanc", "Uncommon", 1, 7),
    toy("RedPandaPlush", "Panda roux en peluche", "Uncommon", 1, 8),
    toy("KoalaPlush", "Koala en peluche", "Uncommon", 1, 7),
    toy("BowTeddy", "Nounours au nœud rose", "Uncommon", 1, 9),
    toy("ClassicTeddy", "Nounours classique", "Uncommon", 1, 8),
    toy("GiraffePlush", "Girafe en peluche", "Uncommon", 1, 7),
    toy("Xylophone", "Xylophone", "Uncommon", 1, 6),
    toy("YellowToyPiano", "Piano jouet jaune", "Uncommon", 1, 8),
    toy("WoodenTrainEngine", "Locomotive en bois", "Uncommon", 1, 7),
    toy("WoodenCarsSet", "Voitures en bois", "Uncommon", 1, 9),
    toy("WhiteBunnyPlush", "Lapin blanc en peluche", "Uncommon", 1, 10),

    -- Rares
    toy("PinkHippoPlush", "Hippo rose", "Rare", 1, 20),
    toy("BigPenguinPlush", "Pingouin tout doux", "Rare", 1, 25),
    toy("AlpacaPlush", "Alpaga en peluche", "Rare", 1, 22),
    toy("CatPiano", "Piano chat", "Rare", 1, 28),
    toy("PinkKeyboard", "Clavier rose", "Rare", 1, 18),
    toy("BallerinaMusicBox", "Boîte à musique ballerine", "Rare", 1, 35),
    toy("RedRaceCar", "Voiture de course", "Rare", 1, 26),
    toy("RedGoKart", "Kart rouge", "Rare", 1, 24),
    toy("YellowWoodenTrain", "Train en bois jaune", "Rare", 2, 38),
    toy("DuckyUnicorn", "Canard licorne", "Rare", 1, 20),

    -- Epiques
    toy("ToyTrainSet", "Train de jouets", "Epic", 2, 70),
    toy("BigWoodenLocomotive", "Grosse locomotive en bois", "Epic", 2, 60),
    toy("ToyTractor", "Tracteur jouet", "Epic", 2, 65),
    toy("ToySpeedboat", "Bateau de course", "Epic", 2, 55),
    toy("BigGiraffePlush", "Grande girafe", "Epic", 2, 80),
    toy("RainbowUnicornPlush", "Licorne arc-en-ciel", "Epic", 1, 50),

    -- Legendaire
    toy("GiantTeddyBear", "Nounours géant", "Legendary", 3, 300),
}

return TOYS
