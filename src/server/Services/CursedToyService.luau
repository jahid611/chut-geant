--!strict

--[[
    CursedToyService
    Jouets maudits (idee 16 du carnet docs/IDEES.md) : a l'apparition, un jouet Peu commun, Rare ou Epique a
    CURSED_CHANCE d'etre « maudit » (attribut Maudit) : volutes violettes et petite lueur, lisibles sans texte.
    Porte, il couine a chaque pas (son pour tout le serveur) et chaque couinement ajoute CURSE_NOISE a la jauge si le
    porteur est dans la chambre. Depose en base, il rapporte un bonus unique de BONUS_INCOME_SECONDS secondes de son
    revenu : le joueur est prevenu par les attributs BonusMaudit (montant) et BonusMauditN (compteur, pour que deux
    bonus identiques de suite declenchent quand meme le message cote client).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Toys = require(Shared:WaitForChild("Toys"))
local Zone = require(Shared:WaitForChild("Zone"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local CURSED_CHANCE = 0.05
local CURSE_NOISE = 1.5
local STEP_SECONDS = 0.45
local BONUS_INCOME_SECONDS = 60
local TICK = 0.1
local SQUEAK_SOUND = "rbxassetid://9114123168"
local CURSED_RARITIES: { [string]: boolean } = { Uncommon = true, Rare = true, Epic = true }

type CursedState = {
    toy: Model,
    wisps: ParticleEmitter,
    glow: PointLight,
    squeak: Sound,
    nextStep: number,
    lastCarrier: number?,
}

local CursedToyService = {}

local cursed: { [Model]: CursedState } = {}
local random = Random.new()

local function forget(toy: Model): ()
    local state = cursed[toy]
    if state == nil then
        return
    end
    cursed[toy] = nil
    state.wisps:Destroy()
    state.glow:Destroy()
    state.squeak:Destroy()
end

-- Maudit un jouet tout de suite (tests : CursedToyService:Curse(workspace.ToysLive.<jouet>)).
function CursedToyService:Curse(toy: Model): boolean
    if toy:GetAttribute("PointAccueil") then
        return false
    end
    if cursed[toy] then
        return true
    end
    local primary = Zone.PrimaryPart(toy)
    if primary == nil then
        return false
    end
    toy:SetAttribute("Maudit", true)
    local wisps = Instance.new("ParticleEmitter")
    wisps.Name = "VolutesMaudit"
    wisps.Texture = "rbxasset://textures/particles/smoke_main.dds"
    wisps.Color = ColorSequence.new(Color3.fromRGB(170, 80, 255), Color3.fromRGB(60, 20, 110))
    wisps.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(1, 2.2),
    })
    wisps.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.55),
        NumberSequenceKeypoint.new(1, 1),
    })
    wisps.Lifetime = NumberRange.new(1, 1.6)
    wisps.Speed = NumberRange.new(1, 2.5)
    wisps.SpreadAngle = Vector2.new(35, 35)
    wisps.EmissionDirection = Enum.NormalId.Top
    wisps.LightEmission = 0.5
    wisps.Rate = 5
    wisps.Parent = primary
    local glow = Instance.new("PointLight")
    glow.Name = "LueurMaudit"
    glow.Color = Color3.fromRGB(170, 90, 255)
    glow.Brightness = 0.8
    glow.Range = 10
    glow.Shadows = false
    glow.Parent = primary
    local squeak = Instance.new("Sound")
    squeak.Name = "CouinementMaudit"
    squeak.SoundId = SQUEAK_SOUND
    squeak.Volume = 0.55
    squeak.RollOffMaxDistance = 180
    squeak.Parent = primary
    local state: CursedState = {
        toy = toy,
        wisps = wisps,
        glow = glow,
        squeak = squeak,
        nextStep = 0,
        lastCarrier = nil,
    }
    cursed[toy] = state
    toy:GetAttributeChangedSignal("CarrierUserId"):Connect(function()
        local id = toy:GetAttribute("CarrierUserId")
        if typeof(id) == "number" then
            state.lastCarrier = id
        end
    end)
    toy.AncestryChanged:Connect(function()
        if toy.Parent == nil then
            -- apres le depot : le bonus est verse par onDeposited avant la destruction
            task.defer(forget, toy)
        end
    end)
    return true
end

local function maybeCurse(toy: Instance): ()
    if not toy:IsA("Model") or toy:GetAttribute("Temporaire") or toy:GetAttribute("PointAccueil") then
        return
    end
    -- laisse le jouet vivant decider d'abord (meme signal) : un jouet n'est jamais vivant et maudit a la fois
    task.defer(function()
        if toy.Parent == nil or toy:GetAttribute("Vivant") then
            return
        end
        local toyId = toy:GetAttribute("ToyId")
        local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
        if def == nil or not CURSED_RARITIES[def.rarity] or random:NextNumber() >= CURSED_CHANCE then
            return
        end
        CursedToyService:Curse(toy)
    end)
end

-- Couinement a chaque pas du porteur (il faut qu'il marche vraiment : MoveDirection et pieds au sol).
local function tick(): ()
    local now = os.clock()
    for toy, state in cursed do
        local carrierId = toy:GetAttribute("CarrierUserId")
        if typeof(carrierId) ~= "number" or now < state.nextStep then
            continue
        end
        local carrier = Players:GetPlayerByUserId(carrierId)
        local character = if carrier then carrier.Character else nil
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        if humanoid == nil or root == nil or not root:IsA("BasePart") then
            continue
        end
        local walking = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.FloorMaterial ~= Enum.Material.Air
        if not walking then
            continue
        end
        state.nextStep = now + STEP_SECONDS
        state.squeak.PlaybackSpeed = 1 + random:NextNumber(-0.2, 0.25)
        state.squeak:Play()
        state.wisps:Emit(3)
        if NoiseService:IsInRoom(root.Position) then
            NoiseService:Add(CURSE_NOISE)
        end
    end
end

local function onDeposited(player: Player, toyId: string, mutation: string?): ()
    for toy, state in cursed do
        local carrier = toy:GetAttribute("CarrierUserId")
        local byPlayer = carrier == player.UserId or (carrier == nil and state.lastCarrier == player.UserId)
        if byPlayer and toy:GetAttribute("ToyId") == toyId then
            local bonus = math.floor(Toys.Income(toyId, mutation) * BONUS_INCOME_SECONDS)
            if bonus > 0 then
                BaseService:AddCash(player, bonus)
            end
            local count = player:GetAttribute("BonusMauditN")
            player:SetAttribute("BonusMaudit", bonus)
            player:SetAttribute("BonusMauditN", (if typeof(count) == "number" then count else 0) + 1)
            forget(toy)
            return
        end
    end
end

function CursedToyService:Init(): () end

function CursedToyService:Start(): ()
    ToySpawnService.Spawned:Connect(maybeCurse)
    BaseService.ToyDeposited:Connect(onDeposited)
    local elapsed = 0
    RunService.Heartbeat:Connect(function(dt: number)
        elapsed += dt
        if elapsed >= TICK then
            elapsed = 0
            tick()
        end
    end)
end

return CursedToyService
