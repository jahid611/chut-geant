--!strict

--[[
    Toys
    Catalogue des jouets a voler, partage serveur et client.

    Le serveur s'en sert pour le revenu et le nombre de porteurs, le client pour
    l'affichage. Source de verite du design : docs/ASSETS.md.
]]

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type Toy = {
    id: string,
    displayName: string,
    rarity: Rarity,
    carriers: number, -- joueurs necessaires pour le porter
    incomePerSecond: number,
    -- vrai : n'apparait que dans la cuisine (ToysKitchen), jamais dans la chambre
    kitchenOnly: boolean?,
}

export type Mutation = {
    id: string,
    displayName: string,
    multiplier: number,
}

local TOYS: { Toy } = {
    { id = "Block", displayName = "Cube de construction", rarity = "Common", carriers = 1, incomePerSecond = 1 },
    { id = "Duck", displayName = "Canard en caoutchouc", rarity = "Common", carriers = 1, incomePerSecond = 2 },
    { id = "Car", displayName = "Petite voiture", rarity = "Common", carriers = 1, incomePerSecond = 3 },
    { id = "Dino", displayName = "Dinosaure en plastique", rarity = "Uncommon", carriers = 1, incomePerSecond = 6 },
    { id = "Top", displayName = "Toupie", rarity = "Uncommon", carriers = 1, incomePerSecond = 8 },
    { id = "Robot", displayName = "Robot a piles", rarity = "Rare", carriers = 2, incomePerSecond = 20 },
    { id = "Teddy", displayName = "Nounours", rarity = "Rare", carriers = 2, incomePerSecond = 25 },
    { id = "TumblerBear", displayName = "Ours culbuto", rarity = "Uncommon", carriers = 1, incomePerSecond = 7 },
    -- Jouet musical retire : sa texture Tripo porte un logo de marque (« fp ») sur plusieurs etiquettes, et
    -- l'effacement automatique laissait de grosses taches. A regenerer sur Tripo depuis une image sans marque.
    -- { id = "MusicToy", displayName = "Jouet musical", rarity = "Rare", carriers = 1, incomePerSecond = 18 },
    -- Ballon : objet lourd (demande utilisateur), gros ballon de bebe a l'echelle des joueurs.
    { id = "EmojiBall", displayName = "Ballon rigolo", rarity = "Rare", carriers = 2, incomePerSecond = 35 },
    { id = "Cactus", displayName = "Cactus rigolo", rarity = "Uncommon", carriers = 1, incomePerSecond = 6 },
    { id = "RingStack", displayName = "Pyramide d'anneaux", rarity = "Common", carriers = 1, incomePerSecond = 3 },
    -- Cheval a bascule : objet lourd propose (2 porteurs pour aller vite, seul tres lentement), a valider.
    { id = "RockingHorse", displayName = "Cheval à bascule", rarity = "Epic", carriers = 2, incomePerSecond = 70 },
    { id = "Rocket", displayName = "Fusee", rarity = "Epic", carriers = 2, incomePerSecond = 60 },
    { id = "Castle", displayName = "Chateau fort", rarity = "Epic", carriers = 3, incomePerSecond = 90 },
    { id = "Console", displayName = "Console doree", rarity = "Legendary", carriers = 3, incomePerSecond = 250 },
}

local MUTATIONS: { Mutation } = {
    { id = "Gold", displayName = "Dore", multiplier = 2 },
    { id = "Rainbow", displayName = "Arc-en-ciel", multiplier = 5 },
    { id = "Cosmic", displayName = "Cosmique", multiplier = 10 },
}

-- Lots de jouets supplementaires (modeles gratuits de la boite a outils Roblox, dans le theme), un fichier par lot
-- pour que plusieurs personnes les remplissent en parallele. Modeles : ServerStorage.ToyModels.<id>.
-- ToysKitchen : jouets de la cuisine (kitchenOnly), plus rares et plus rentables.
for _, name in { "ToysPackA", "ToysPackB", "ToysKitchen" } do
    local pack = script.Parent:FindFirstChild(name)
    if pack and pack:IsA("ModuleScript") then
        local ok, list = pcall(require, pack)
        if ok and typeof(list) == "table" then
            for _, toy in list :: { Toy } do
                table.insert(TOYS, toy)
            end
        end
    end
end

local byId: { [string]: Toy } = {}
for _, toy in TOYS do
    byId[toy.id] = table.freeze(toy)
end

local mutationById: { [string]: Mutation } = {}
for _, mutation in MUTATIONS do
    mutationById[mutation.id] = table.freeze(mutation)
end

local Toys = {}

function Toys.Get(id: string): Toy?
    return byId[id]
end

function Toys.GetMutation(id: string): Mutation?
    return mutationById[id]
end

function Toys.All(): { Toy }
    return TOYS
end

-- Revenu par seconde d'un jouet, mutation comprise. Une mutation inconnue compte pour x1.
function Toys.Income(id: string, mutationId: string?): number
    local toy = byId[id]
    if toy == nil then
        return 0
    end
    local mutation = if mutationId then mutationById[mutationId] else nil
    return toy.incomePerSecond * (if mutation then mutation.multiplier else 1)
end

return table.freeze(Toys)
