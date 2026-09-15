--!strict

--[[
    ToysKitchen
    Jouets de la cuisine (idee 21 du carnet docs/IDEES.md) : dinette, fruits en plastique, biberon dore... Ils
    n'apparaissent que sur les points de workspace.Cuisine (kitchenOnly, ToySpawnService) et rapportent plus que ceux
    de la chambre a rarete egale : une vraie raison d'affronter le chien. Fusionnes dans Shared/Toys comme les lots A
    et B. Modeles : ServerStorage.ToyModels.<id> (Creator Store, scripts et sons retires).
]]

type Toy = {
    id: string,
    displayName: string,
    rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary",
    carriers: number,
    incomePerSecond: number,
    kitchenOnly: boolean?,
}

local function toy(
    id: string,
    displayName: string,
    rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary",
    carriers: number,
    income: number
): Toy
    return {
        id = id,
        displayName = displayName,
        rarity = rarity,
        carriers = carriers,
        incomePerSecond = income,
        kitchenOnly = true,
    }
end

local TOYS: { Toy } = {
    -- Peu communs (chambre : 6 a 10 /s)
    toy("KitchenBanana", "Banane en plastique", "Uncommon", 1, 14),
    toy("KitchenRedApple", "Pomme en plastique", "Uncommon", 1, 15),
    toy("KitchenTomato", "Tomate en plastique", "Uncommon", 1, 16),
    toy("KitchenToaster", "Grille-pain de dînette", "Uncommon", 1, 18),

    -- Rares (chambre : 18 a 38 /s)
    toy("KitchenOrange", "Orange en plastique", "Rare", 1, 45),
    toy("KitchenBlender", "Mixeur jouet", "Rare", 1, 50),
    toy("KitchenDragonFruit", "Fruit du dragon", "Rare", 1, 55),
    toy("KitchenStrawberryTea", "Service à thé fraise", "Rare", 1, 60),

    -- Epiques (chambre : 50 a 90 /s)
    toy("KitchenGoldenApple", "Pomme dorée", "Epic", 1, 130),
    toy("KitchenKawaiiKitchen", "Mini-cuisine kawaii", "Epic", 2, 150),
    toy("KitchenGoldenBottle", "Biberon doré", "Epic", 1, 160),

    -- Legendaire (chambre : 250 a 300 /s)
    toy("KitchenPlayKitchen", "Cuisine de poupée", "Legendary", 3, 450),
}

return TOYS
