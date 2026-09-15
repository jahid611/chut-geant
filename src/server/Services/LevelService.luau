--!strict

--[[
    LevelService
    Niveau du joueur (1 a Levels.MAX_LEVEL), sauvegarde dans le profil (level, xp).

    Toute l'XP passe par PassService:AddXp, qui emet PassService.XpGained : le pass et le niveau avancent ensemble.
    Sources ajoutees ici (reglages Shared/Levels) :
    - jouet depose (BaseService.ToyDeposited) : XP selon la rarete, x mutation, + bonus par porteur en plus ;
    - survivre a « Maman arrive ! » / « Vite, dans l'ombre ! » (EventService.EventFinished) ;
    - premiere decouverte d'un jouet ou d'une mutation (ToyCollectionService.Discovered).
    Les quetes, la roue, la connexion, les jouets voles et les minutes jouees donnent deja de l'XP via le pass.

    Montee de niveau : tetines a chaque niveau, gros bonus tous les 5, cosmetique aux niveaux 10/20/30/50
    (tetines s'il est deja possede), nouveau titre a certains niveaux.
    Attributs du joueur : Level, Xp, XpNeeded, Title ; XpGain = "<compteur>:<montant>" a chaque gain ;
    LevelReward = JSON { level, cash, cosmetic?, title? } pose juste avant Level quand le niveau monte.
    Au-dessus de la tete : « Niv. N » et le titre (BillboardGui NiveauJoueur, au-dessus du titre « Nuit N »).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Levels = require(Shared:WaitForChild("Levels"))
local Toys = require(Shared:WaitForChild("Toys"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local EventService = require(script.Parent:WaitForChild("EventService"))
local PassService = require(script.Parent:WaitForChild("PassService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))
local ToyCollectionService = require(script.Parent:WaitForChild("ToyCollectionService"))

local BILLBOARD_NAME = "NiveauJoueur"

type Reward = { level: number, cash: number, cosmetic: string?, title: string? }

local LevelService = {}

local gainCounter = 0

local function setBillboard(player: Player): ()
    local profile = DataService:Get(player)
    local character = player.Character
    local head = if character then character:FindFirstChild("Head") else nil
    if profile == nil or head == nil or not head:IsA("BasePart") then
        return
    end
    local existing = head:FindFirstChild(BILLBOARD_NAME)
    if existing then
        existing:Destroy()
    end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = BILLBOARD_NAME
    -- taille en studs : reste proportionnee au personnage, et au-dessus du titre « Nuit N » (a 2,6 studs)
    -- 6 x 1,7 studs cachait la moitie de l'ecran de pres (capture du 15/09) : plus petit et plus proche.
    billboard.Size = UDim2.fromScale(3.4, 0.95)
    billboard.StudsOffset = Vector3.new(0, 3.9, 0)
    billboard.MaxDistance = 140
    billboard.LightInfluence = 0
    billboard.Adornee = head
    local function label(name: string, text: string, height: number, y: number, color: Color3): ()
        local text_ = Instance.new("TextLabel")
        text_.Name = name
        text_.Size = UDim2.fromScale(1, height)
        text_.Position = UDim2.fromScale(0, y)
        text_.BackgroundTransparency = 1
        text_.Font = Enum.Font.FredokaOne
        text_.TextScaled = true
        text_.TextColor3 = color
        text_.Text = text
        text_.Parent = billboard
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(12, 16, 40)
        stroke.Parent = text_
    end
    label("Niveau", string.format("Niv. %d", profile.level), 0.58, 0, Color3.fromRGB(255, 212, 96))
    label("Titre", Levels.TitleFor(profile.level), 0.42, 0.58, Color3.fromRGB(176, 190, 245))
    billboard.Parent = head
end

local function publish(player: Player): ()
    local profile = DataService:Get(player)
    if profile == nil then
        return
    end
    player:SetAttribute("Xp", profile.xp)
    player:SetAttribute("XpNeeded", Levels.XpNeeded(profile.level))
    player:SetAttribute("Title", Levels.TitleFor(profile.level))
    player:SetAttribute("Level", profile.level)
    setBillboard(player)
end

-- Recompenses du niveau atteint (tetines versees ici).
local function grantRewards(player: Player, level: number): Reward
    local reward: Reward = { level = level, cash = Levels.CashReward(level) }
    if level % Levels.MILESTONE_EVERY == 0 then
        reward.cash += Levels.MilestoneCash(level)
    end
    local cosmeticId: string? = Levels.COSMETICS[level]
    if cosmeticId then
        if ShopService:Grant(player, cosmeticId) then
            reward.cosmetic = cosmeticId
        else
            reward.cash += Levels.CosmeticRefund(level)
        end
    end
    local title = Levels.TitleFor(level)
    if title ~= Levels.TitleFor(level - 1) then
        reward.title = title
    end
    BaseService:AddCash(player, reward.cash)
    return reward
end

local function addXp(player: Player, amount: number, source: string?): ()
    local profile = DataService:Get(player)
    if profile == nil or amount <= 0 then
        return
    end
    gainCounter += 1
    player:SetAttribute("XpGain", string.format("%d:%d:%s", gainCounter, math.floor(amount), source or ""))
    if profile.level >= Levels.MAX_LEVEL then
        return
    end
    profile.xp += math.floor(amount)
    local total: Reward? = nil
    while profile.level < Levels.MAX_LEVEL and profile.xp >= Levels.XpNeeded(profile.level) do
        profile.xp -= Levels.XpNeeded(profile.level)
        profile.level += 1
        local reward = grantRewards(player, profile.level)
        -- plusieurs niveaux d'un coup : on annonce le dernier avec la somme des tetines
        local previous = total
        if previous then
            reward.cash += previous.cash
            reward.cosmetic = reward.cosmetic or previous.cosmetic
            reward.title = reward.title or previous.title
        end
        total = reward
    end
    if profile.level >= Levels.MAX_LEVEL then
        profile.xp = 0
    end
    if total then
        player:SetAttribute("LevelReward", HttpService:JSONEncode(total))
        task.spawn(function()
            DataService:Save(player)
        end)
    end
    publish(player)
end

function LevelService:GetLevel(player: Player): number
    local profile = DataService:Get(player)
    return if profile then profile.level else 1
end

function LevelService:Init(): () end

function LevelService:Start(): ()
    PassService.XpGained:Connect(function(player: Player, amount: number, source: string?)
        addXp(player, amount, source)
    end)

    BaseService.ToyDeposited:Connect(function(player: Player, toyId: string, mutationId: string?)
        local def = Toys.Get(toyId)
        if def == nil then
            return
        end
        local xp = (Levels.XP_BY_RARITY :: any)[def.rarity] or Levels.XP_BY_RARITY.Common
        local multiplier = if mutationId then (Levels.XP_MUTATION_MULTIPLIER :: any)[mutationId] else nil
        xp *= if typeof(multiplier) == "number" then multiplier else 1
        xp += math.max(def.carriers - 1, 0) * Levels.XP_HEAVY_BONUS
        PassService:AddXp(player, xp, "vol")
    end)

    EventService.EventFinished:Connect(function(kind: string, caught: { [Player]: boolean }, participants: { Player })
        local xp = (Levels.XP_SURVIVE :: any)[kind]
        if typeof(xp) ~= "number" then
            return
        end
        for _, player in participants do
            if player.Parent and not caught[player] then
                PassService:AddXp(player, xp, "survie")
            end
        end
    end)

    ToyCollectionService.Discovered:Connect(function(player: Player, rarity: string)
        PassService:AddXp(
            player,
            if rarity == "Mutation" then Levels.XP_MUTATION_DISCOVERY else Levels.XP_DISCOVERY,
            "collection"
        )
    end)

    local function onPlayer(player: Player): ()
        player.CharacterAdded:Connect(function(character: Model)
            character:WaitForChild("Head", 5)
            task.defer(setBillboard, player)
        end)
        local profile = DataService:WaitForProfile(player)
        if profile == nil then
            return
        end
        profile.level = math.clamp(math.floor(profile.level), 1, Levels.MAX_LEVEL)
        profile.xp = math.max(math.floor(profile.xp), 0)
        publish(player)
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
end

return LevelService
