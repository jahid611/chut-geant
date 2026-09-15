--!strict

--[[
    ToysPackB
    Jouets supplementaires, lot B (modeles gratuits de la boite a outils Roblox, theme chambre de bebe), fusionnes
    dans Shared/Toys. Meme forme qu'un jouet : id (PascalCase, unique), displayName (francais), rarity, carriers,
    incomePerSecond. Modele : ServerStorage.ToyModels.<id>. Provenance : docs/jouets-lot-b.md.
    Theme : jouets de bebe, dinosaures / espace, dinette, exterieur, construction, deguisements.
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
    toy("BabyRattle", "Hochet de bébé", "Common", 1, 2),
    toy("RattleDuo", "Paire de hochets", "Common", 1, 2),
    toy("BuildingBlocks", "Cubes à empiler", "Common", 1, 3),
    toy("LetterBlock", "Cube lettre", "Common", 1, 1),
    toy("AbcBlocks", "Cubes ABC", "Common", 1, 3),
    toy("BeachBall", "Ballon de plage", "Common", 1, 2),
    toy("RubberBall", "Balle rebondissante", "Common", 1, 1),
    toy("RedBall", "Balle rouge", "Common", 1, 2),
    toy("Pacifier", "Tétine", "Common", 1, 1),
    toy("BabyBottle", "Biberon", "Common", 1, 2),
    toy("Cupcake", "Cupcake au chocolat", "Common", 1, 2),
    toy("PuzzlePiece", "Pièce de puzzle", "Common", 1, 2),
    toy("StackingCups", "Gobelets empilés", "Common", 1, 3),
    toy("Lollipop", "Sucette géante", "Common", 1, 2),
    toy("Donut", "Donut", "Common", 1, 2),
    toy("BabyShoe", "Chausson de bébé", "Common", 1, 1),
    toy("BubbleWand", "Baguette à bulles", "Common", 1, 3),
    toy("WateringCan", "Arrosoir", "Common", 1, 3),

    -- Peu communs
    toy("TeaCups", "Tasses de dînette", "Uncommon", 1, 6),
    toy("FruitBowl", "Corbeille de fruits", "Uncommon", 1, 6),
    toy("BucketSpade", "Seau et pelle", "Uncommon", 1, 7),
    toy("Kite", "Cerf-volant", "Uncommon", 1, 8),
    toy("SpinningTop", "Toupie magique", "Uncommon", 1, 7),
    toy("ShapeSorter", "Boîte à formes", "Uncommon", 1, 9),
    toy("IceCreamCone", "Cornet de glace", "Uncommon", 1, 6),
    toy("PiggyBank", "Tirelire cochon", "Uncommon", 1, 9),
    toy("JackInTheBox", "Diable en boîte", "Uncommon", 1, 10),
    toy("FishingToySet", "Pêche aux canards", "Uncommon", 1, 8),
    toy("Dominoes", "Dominos", "Uncommon", 1, 6),
    toy("WizardHat", "Chapeau de sorcier", "Uncommon", 1, 8),
    toy("GiftBox", "Paquet cadeau", "Uncommon", 1, 7),
    toy("BallToy", "Balle d'éveil", "Common", 1, 3),
    toy("Yoyo", "Yo-yo", "Common", 1, 2),
    toy("ToySailboat", "Petit voilier", "Uncommon", 1, 7),

    -- Rares
    toy("ToyRocketSmall", "Fusée jouet", "Rare", 1, 18),
    toy("Saturn", "Planète Saturne", "Rare", 2, 30),
    toy("Triceratops", "Tricératops en peluche", "Rare", 1, 22),
    toy("Sonorasaurus", "Dino long cou", "Rare", 2, 32),
    toy("StrawberryTeaSet", "Dînette fraise", "Rare", 1, 25),
    toy("PinkTeaSet", "Dînette rose", "Rare", 1, 24),
    toy("SandCastle", "Château de sable", "Rare", 2, 35),
    toy("ToyUfo", "Soucoupe volante", "Rare", 1, 28),
    toy("SnowGlobe", "Boule à neige", "Rare", 1, 20),

    -- Epiques
    toy("BabySpaceMobile", "Mobile de l'espace", "Epic", 2, 70),
    toy("KingCrown", "Couronne de roi", "Epic", 1, 55),
    toy("Shunosaurus", "Grand dino en peluche", "Epic", 3, 90),
    toy("ModelRocket", "Grande fusée", "Epic", 3, 95),
    toy("BalloonBunch", "Bouquet de ballons", "Epic", 2, 50),
    toy("BirthdayCake", "Gâteau d'anniversaire", "Epic", 2, 60),
    toy("TreasureChestToy", "Coffre au trésor", "Epic", 2, 65),

    -- Legendaires
    toy("FairyWand", "Baguette de fée", "Legendary", 1, 220),
    toy("RoyalCrown", "Couronne royale", "Legendary", 1, 250),
}

return TOYS
