--!strict

--[[
    ComboService
    Combo de discretion (idee 3 du carnet docs/IDEES.md) : recompenser le jeu discret.

    Chaque jouet depose dans sa base (BaseService.ToyDeposited) alors que le joueur n'a pas « casse » son combo
    depuis le depot precedent rapporte l'XP du depot multipliee par le combo en cours (XP en plus via
    PassService:AddXp, source "combo") et 50 tetines x combo, puis fait monter le combo (x1 -> x2 -> ... -> x5).
    Le combo retombe a x1 si :
    - la jauge de bruit de la chambre depasse COMBO_NOISE_LIMIT pendant que le joueur est dans la chambre ;
    - le joueur est attrape (GiantService.Caught) ;
    - il lache ou lance un jouet (attribut CarriedToyId qui change sans depot juste avant).
    Attributs joueur : Combo (1 a MAX_COMBO), ComboMax (record, garde dans profile.stats.comboMax).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Levels = require(Shared:WaitForChild("Levels"))
local Toys = require(Shared:WaitForChild("Toys"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GiantService = require(script.Parent:WaitForChild("GiantService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local PassService = require(script.Parent:WaitForChild("PassService"))

local MAX_COMBO = 5
-- Part de la jauge au-dela de laquelle le combo casse pour les joueurs de la chambre.
local COMBO_NOISE_LIMIT = 0.5
local TETINES_PER_LEVEL = 50
local SAMPLE_SECONDS = 0.25
-- Un changement de CarriedToyId dans ce delai apres un depot vient du depot (pas d'un lacher).
local DEPOSIT_GRACE = 0.6

local ComboService = {}

local lastDepositAt: { [Player]: number } = {}
local lastCarried: { [Player]: string? } = {}

local function comboOf(player: Player): number
    local value = player:GetAttribute("Combo")
    return if typeof(value) == "number" then value else 1
end

local function setCombo(player: Player, combo: number): ()
    combo = math.clamp(combo, 1, MAX_COMBO)
    player:SetAttribute("Combo", combo)
    local profile = DataService:Get(player)
    local record = if profile then profile.stats.comboMax or 1 else 1
    if combo > record then
        if profile then
            profile.stats.comboMax = combo
        end
        record = combo
    end
    player:SetAttribute("ComboMax", record)
end

function ComboService:Break(player: Player): ()
    if comboOf(player) > 1 then
        setCombo(player, 1)
    end
end

-- XP de base d'un depot (meme bareme que LevelService : rarete x mutation).
local function depositXp(toyId: string, mutationId: string?): number
    local def = Toys.Get(toyId)
    if def == nil then
        return 0
    end
    local base = (Levels.XP_BY_RARITY :: any)[def.rarity] or 0
    local multiplier = if mutationId then (Levels.XP_MUTATION_MULTIPLIER :: any)[mutationId] or 1 else 1
    return base * multiplier
end

local function onDeposited(player: Player, toyId: string, mutationId: string?): ()
    lastDepositAt[player] = os.clock()
    local combo = comboOf(player)
    if combo >= 2 then
        local extraXp = math.floor(depositXp(toyId, mutationId) * (combo - 1))
        if extraXp > 0 then
            PassService:AddXp(player, extraXp, "combo")
        end
        BaseService:AddCash(player, TETINES_PER_LEVEL * combo)
    end
    setCombo(player, combo + 1)
end

local function watchCarry(player: Player): ()
    local current = player:GetAttribute("CarriedToyId")
    lastCarried[player] = if typeof(current) == "string" then current else nil
    player:GetAttributeChangedSignal("CarriedToyId"):Connect(function()
        local value = player:GetAttribute("CarriedToyId")
        local now: string? = if typeof(value) == "string" then value else nil
        local before: string? = lastCarried[player]
        lastCarried[player] = now
        -- ramasser (rien -> jouet) ne casse rien ; un jouet qui quitte les mains sans depot recent = lache ou lance
        if before ~= nil and now ~= before then
            local deposited: number? = lastDepositAt[player]
            if deposited == nil or os.clock() - deposited > DEPOSIT_GRACE then
                ComboService:Break(player)
            end
        end
    end)
end

local function onPlayer(player: Player): ()
    local profile = DataService:WaitForProfile(player)
    if player.Parent == nil then
        return
    end
    player:SetAttribute("Combo", 1)
    player:SetAttribute("ComboMax", if profile then profile.stats.comboMax or 1 else 1)
    watchCarry(player)
end

function ComboService:Init(): () end

function ComboService:Start(): ()
    BaseService.ToyDeposited:Connect(onDeposited)
    GiantService.Caught:Connect(function(player: Player)
        ComboService:Break(player)
    end)

    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        lastDepositAt[player] = nil
        lastCarried[player] = nil
    end)

    -- Jauge trop haute : le combo des joueurs presents dans la chambre casse.
    local elapsed = 0
    RunService.Heartbeat:Connect(function(dt: number)
        elapsed += dt
        if elapsed < SAMPLE_SECONDS then
            return
        end
        elapsed = 0
        if NoiseService:Get() <= Tuning.NOISE_MAX * COMBO_NOISE_LIMIT then
            return
        end
        for _, player in Players:GetPlayers() do
            if comboOf(player) <= 1 then
                continue
            end
            local character = player.Character
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            if root and root:IsA("BasePart") and NoiseService:IsInRoom(root.Position) then
                ComboService:Break(player)
            end
        end
    end)
end

return ComboService
