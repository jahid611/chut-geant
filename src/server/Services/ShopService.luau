--!strict

--[[
    ShopService
    Achats en tetines de tout le catalogue (Shared/Catalog) et equipement des cosmetiques.

    - BuyItem (RemoteFunction) : verifie l'article, le niveau suivant, le prix et le solde, debite, applique.
    - EquipCosmetic (RemoteFunction) : equipe un cosmetique possede dans son emplacement.
    Possession publiee en attributs du joueur : Owned_<id> = niveau ; equipement : Equipped_<slot> = id.
    Compatibilite : QuietSlippers et StrongArms gardent aussi leur attribut booleen (true des le niveau 1), et
    StrongArmsLevel / QuietSlippersLevel donnent le niveau aux services qui en tiennent compte.
    Les decors et skins (needs3D) restent « Bientôt » tant que leur modele n'est pas dans
    ServerStorage.CosmeticModels.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local ShopService = {}

local purchased = Instance.new("BindableEvent")
-- (player: Player, itemId: string, level: number)
ShopService.Purchased = purchased.Event

-- Niveau possede d'un article (coffres compris : coffres en plus du premier, coffres dores).
function ShopService:GetLevel(player: Player, itemId: string): number
    local profile = DataService:Get(player)
    if profile == nil then
        return 0
    end
    if itemId == "Chest" then
        return profile.chests - 1
    elseif itemId == "GoldChest" then
        return profile.goldChests
    end
    return profile.owned[itemId] or 0
end

function ShopService:Owns(player: Player, itemId: string): boolean
    return ShopService:GetLevel(player, itemId) > 0
end

local function publish(player: Player, itemId: string, level: number): ()
    player:SetAttribute("Owned_" .. itemId, if level > 0 then level else nil)
    if itemId == "QuietSlippers" or itemId == "StrongArms" then
        player:SetAttribute(itemId, if level > 0 then true else nil)
        player:SetAttribute(itemId .. "Level", level)
    end
end

-- Emplacement equipable automatiquement a l'achat : cosmetiques a slot (hors decors et danses) et armes.
local function autoEquipSlot(item: Catalog.Item): string?
    local slot = item.slot
    if slot == nil then
        return nil
    end
    if item.kind == "weapon" then
        return slot
    end
    if item.kind == "cosmetic" and slot ~= "decor" and slot ~= "dance" then
        return slot
    end
    return nil
end

local function modelAvailable(item: Catalog.Item): boolean
    if not item.needs3D then
        return true
    end
    -- armes : ServerStorage.WeaponModels ; cosmetiques : ServerStorage.CosmeticModels
    local folderName = if item.kind == "weapon"
        then "WeaponModels"
        elseif item.kind == "cosmetic" then "CosmeticModels"
        else nil
    if folderName == nil then
        return true
    end
    local folder = ServerStorage:FindFirstChild(folderName)
    return folder ~= nil and folder:FindFirstChild(item.id) ~= nil
end

function ShopService:Buy(player: Player, itemId: string): (boolean, string)
    local profile = DataService:Get(player)
    local item = Catalog.Get(itemId)
    if profile == nil then
        return false, "Ton profil charge encore, réessaie."
    end
    if item == nil then
        return false, "Article inconnu."
    end
    if item.exclusive then
        return false, "Récompense de mission : vole la tétine du bébé !"
    end
    if not modelAvailable(item) then
        return false, "Bientôt disponible !"
    end
    local level = ShopService:GetLevel(player, itemId)
    if itemId == "GoldChest" and level >= profile.chests then
        return false, "Achète d'abord un autre coffre à dorer."
    end
    local price = Catalog.NextPrice(item, level)
    if price == nil or (itemId == "Chest" and profile.chests >= Tuning.MAX_CHESTS) then
        return false, if item.kind == "upgrade" then "Niveau maximum atteint." else "Déjà acheté."
    end
    if not BaseService:SpendCash(player, price) then
        return false, "Pas assez de tétines."
    end

    local newLevel = level + 1
    if itemId == "Chest" then
        BaseService:AddChest(player)
    elseif itemId == "GoldChest" then
        profile.goldChests = newLevel
        BaseService:RefreshIncome(player)
    else
        profile.owned[itemId] = newLevel
        local slot = autoEquipSlot(item)
        if slot and profile.equipped[slot] == nil then
            profile.equipped[slot] = itemId
            player:SetAttribute("Equipped_" .. slot, itemId)
        end
    end
    publish(player, itemId, ShopService:GetLevel(player, itemId))
    purchased:Fire(player, itemId, newLevel)
    DataService:Save(player)

    if item.kind == "upgrade" and Catalog.MaxLevel(item) > 1 then
        return true, string.format("%s : niveau %d !", item.name, newLevel)
    end
    return true, item.name .. " : acheté !"
end

-- Donne un article sans paiement (recompenses du pass de saison). Faux s'il est deja au niveau maximum.
function ShopService:Grant(player: Player, itemId: string): boolean
    local profile = DataService:Get(player)
    local item = Catalog.Get(itemId)
    if profile == nil or item == nil or item.kind == "chest" then
        return false
    end
    local level = profile.owned[itemId] or 0
    if level >= Catalog.MaxLevel(item) then
        return false
    end
    local newLevel = level + 1
    profile.owned[itemId] = newLevel
    local slot = autoEquipSlot(item)
    if slot and profile.equipped[slot] == nil then
        profile.equipped[slot] = itemId
        player:SetAttribute("Equipped_" .. slot, itemId)
    end
    publish(player, itemId, newLevel)
    purchased:Fire(player, itemId, newLevel)
    return true
end

function ShopService:Equip(player: Player, itemId: string): (boolean, string)
    local profile = DataService:Get(player)
    local item = Catalog.Get(itemId)
    -- cosmetiques a emplacement et armes (slot "weapon" : une seule arme en main)
    if profile == nil or item == nil or (item.kind ~= "cosmetic" and item.kind ~= "weapon") or item.slot == nil then
        return false, "Impossible d'équiper ça."
    end
    if not ShopService:Owns(player, itemId) then
        return false, "Achète-le d'abord."
    end
    local slot = item.slot :: string
    if profile.equipped[slot] == itemId then
        profile.equipped[slot] = nil
        player:SetAttribute("Equipped_" .. slot, nil)
        return true, item.name .. " : retiré."
    end
    profile.equipped[slot] = itemId
    player:SetAttribute("Equipped_" .. slot, itemId)
    return true, item.name .. " : équipé !"
end

--[[
    Apercus 3D de la boutique : le client ne voit pas ServerStorage. Copie legere de chaque modele de CosmeticModels
    et WeaponModels dans ReplicatedStorage.ApercusBoutique.<id> (scripts, sons, lumieres, particules retires, pieces
    ancrees et inertes) ; Ui/Shop l'affiche dans un ViewportFrame tant que l'icone de l'article n'est pas televersee.
]]
local PREVIEW_FOLDER = "ApercusBoutique"
local STRIP_CLASSES = {
    "LuaSourceContainer",
    "Sound",
    "Light",
    "ParticleEmitter",
    "Trail",
    "Beam",
    "Fire",
    "Smoke",
    "Sparkles",
    "ProximityPrompt",
    "ClickDetector",
    "BillboardGui",
    "ForceField",
}

local function lightCopy(source: Instance): Model?
    local model = Instance.new("Model")
    model.Name = source.Name
    local copy = source:Clone()
    if copy:IsA("BasePart") then
        copy.Parent = model
    else
        for _, child in copy:GetChildren() do
            child.Parent = model
        end
        copy:Destroy()
    end
    for _, descendant in model:GetDescendants() do
        local strip = false
        for _, className in STRIP_CLASSES do
            if descendant:IsA(className) then
                strip = true
                break
            end
        end
        if strip then
            descendant:Destroy()
        elseif descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
            descendant.CastShadow = false
        end
    end
    if model:FindFirstChildWhichIsA("BasePart", true) == nil then
        model:Destroy()
        return nil
    end
    return model
end
-- Reutilisee par ToyPreviewService pour les apercus 3D des jouets de la collection.
ShopService.LightCopy = lightCopy

local function refreshPreviews(): ()
    local existing = ReplicatedStorage:FindFirstChild(PREVIEW_FOLDER)
    local folder: Instance
    if existing then
        folder = existing
    else
        folder = Instance.new("Folder")
        folder.Name = PREVIEW_FOLDER
        folder.Parent = ReplicatedStorage
    end
    local wanted: { [string]: Instance } = {}
    for _, name in { "CosmeticModels", "WeaponModels" } do
        local source = ServerStorage:FindFirstChild(name)
        if source then
            for _, child in source:GetChildren() do
                wanted[child.Name] = child
            end
        end
    end
    for _, preview in folder:GetChildren() do
        if (wanted[preview.Name] :: Instance?) == nil then
            preview:Destroy()
        end
    end
    for name, source in wanted do
        if folder:FindFirstChild(name) == nil then
            local ok, copy = pcall(lightCopy, source)
            if ok and copy then
                copy.Parent = folder
            end
        end
    end
end

function ShopService:Init(): () end

function ShopService:Start(): ()
    local buy = Remotes.Get("BuyItem") :: RemoteFunction
    buy.OnServerInvoke = function(player: Player, itemId: any)
        if typeof(itemId) ~= "string" then
            return false, "Requête invalide."
        end
        return ShopService:Buy(player, itemId)
    end
    local equip = Remotes.Get("EquipCosmetic") :: RemoteFunction
    equip.OnServerInvoke = function(player: Player, itemId: any)
        if typeof(itemId) ~= "string" then
            return false, "Requête invalide."
        end
        return ShopService:Equip(player, itemId)
    end

    -- Articles a modele 3D disponibles, publies pour le client (il ne voit pas ServerStorage) : attributs
    -- Dispo_<id> de ReplicatedStorage, remis a jour quand des modeles arrivent pendant la partie. Plus de « Bientôt »
    -- pour un article dont le modele est la (retour utilisateur du 15/09).
    local function publishAvailability(): ()
        for _, item in Catalog.All() do
            if item.needs3D then
                ReplicatedStorage:SetAttribute("Dispo_" .. item.id, modelAvailable(item))
            end
        end
    end
    -- apercus d'abord : le client redessine la boutique quand Dispo_<id> change, l'apercu est alors deja la
    local function onModelsChanged(): ()
        task.defer(function()
            refreshPreviews()
            publishAvailability()
        end)
    end
    refreshPreviews()
    publishAvailability()
    local function watch(folder: Instance): ()
        folder.ChildAdded:Connect(onModelsChanged)
        folder.ChildRemoved:Connect(onModelsChanged)
    end
    for _, name in { "CosmeticModels", "WeaponModels" } do
        local folder = ServerStorage:FindFirstChild(name)
        if folder then
            watch(folder)
        end
    end
    ServerStorage.ChildAdded:Connect(function(child: Instance)
        if child.Name == "CosmeticModels" or child.Name == "WeaponModels" then
            watch(child)
            onModelsChanged()
        end
    end)

    local function onPlayer(player: Player): ()
        local profile = DataService:WaitForProfile(player)
        if profile == nil then
            return
        end
        for _, item in Catalog.All() do
            publish(player, item.id, ShopService:GetLevel(player, item.id))
        end
        for slot, id in profile.equipped do
            player:SetAttribute("Equipped_" .. slot, id)
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
end

return ShopService
