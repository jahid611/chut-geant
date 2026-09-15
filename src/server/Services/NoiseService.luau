--!strict

--[[
    NoiseService
    La jauge de bruit partagee par tout le serveur.

    Bouger plus vite que Tuning.SNEAK_SPEED dans la chambre fait du bruit (plus
    encore en portant un gros jouet), atterrir d'un saut aussi. Le calme fait
    redescendre la jauge. Pleine, elle se fige et emet Maxed : GiantService
    s'y abonne pour reveiller le geant, puis appelle Reset a la fin de la chasse.

    La chambre est l'ensemble des pieces taguees "GiantRoom" ; sans aucune, toute
    la carte compte.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local NoiseMath = require(Shared:WaitForChild("NoiseMath"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))
local Tuning = require(Shared:WaitForChild("Tuning"))
local Zone = require(Shared:WaitForChild("Zone"))

local CarryService = require(script.Parent:WaitForChild("CarryService"))

local ROOM_TAG = "GiantRoom"

local NoiseService = {}

local maxedEvent = Instance.new("BindableEvent")
NoiseService.Maxed = maxedEvent.Event

local noise = 0
local frozen = false
local lastSent = -1
local sinceBroadcast = 0
local runSeconds: { [Player]: number } = {}

local function broadcast(): ()
    lastSent = noise
    local remote = Remotes.Get("NoiseState") :: RemoteEvent
    remote:FireAllClients(noise, Tuning.NOISE_MAX)
end

function NoiseService:IsInRoom(position: Vector3): boolean
    local rooms = CollectionService:GetTagged(ROOM_TAG)
    if #rooms == 0 then
        return true
    end
    for _, room in rooms do
        if room:IsA("BasePart") and room:IsDescendantOf(workspace) and Zone.Contains(room, position) then
            return true
        end
    end
    return false
end

function NoiseService:Get(): number
    return noise
end

-- Multiplicateurs temporaires du bruit ajoute (evenements : boite a musique x0, cauchemar x2, panne x1,5, papa qui
-- ronfle x0,4). Un par cle ; ils se multiplient entre eux.
local gainMultipliers: { [string]: number } = {}

function NoiseService:SetGainMultiplier(key: string, factor: number?): ()
    local multipliers: { [string]: number? } = gainMultipliers
    multipliers[key] = if factor then math.max(factor, 0) else nil
end

local function gainFactor(): number
    local factor = 1
    for _, value in gainMultipliers do
        factor *= value
    end
    return factor
end

local function addEffective(amount: number): ()
    if frozen or amount <= 0 then
        return
    end
    noise = math.min(noise + amount, Tuning.NOISE_MAX)
    if noise >= Tuning.NOISE_MAX then
        frozen = true
        broadcast()
        maxedEvent:Fire()
    end
end

function NoiseService:Add(amount: number): ()
    addEffective(amount * gainFactor())
end

-- Retire du bruit (Tetine magique). Sans effet quand la jauge est pleine et le bebe deja reveille. Vrai si la
-- jauge a baisse.
function NoiseService:Reduce(amount: number): boolean
    if frozen or amount <= 0 or noise <= 0 then
        return false
    end
    noise = math.max(noise - amount, 0)
    broadcast()
    return true
end

function NoiseService:Reset(): ()
    noise = 0
    frozen = false
    broadcast()
end

local function movementNoise(dt: number): number
    local players = Players:GetPlayers()
    local runners: { NoiseMath.Runner } = {}
    for _, player in players do
        local character = player.Character
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        local speed = 0
        if
            root
            and root:IsA("BasePart")
            and humanoid
            and humanoid.Health > 0
            and NoiseService:IsInRoom(root.Position)
        then
            local velocity = root.AssemblyLinearVelocity
            speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        end
        local toy = CarryService:GetCarried(player)
        local toyId = if toy then toy:GetAttribute("ToyId") else nil
        local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
        table.insert(runners, {
            speed = speed,
            carriers = if def then def.carriers else 1,
            quiet = math.max(1 - Abilities.QUIET_PER_LEVEL * Abilities.Level(player, "QuietSlippers"), 0.1),
            fury = if Abilities.IsActive(player, "Fury") then Tuning.FURY_NOISE_MULTIPLIER else 1,
            runSeconds = runSeconds[player] or 0,
        })
    end
    local gain, durations = NoiseMath.Movement(runners, dt, Tuning, gainFactor())
    for i, player in players do
        runSeconds[player] = durations[i]
    end
    return gain
end

function NoiseService:Init(): () end

function NoiseService:Start(): ()
    -- Jouet lance ou qui atterrit : bruit ajoute a la jauge (hors de la chambre compris, c'est un vacarme).
    CarryService.MadeNoise:Connect(function(amount: number)
        self:Add(amount)
    end)

    local function onCharacter(character: Model): ()
        local humanoid = character:WaitForChild("Humanoid", 5)
        if humanoid == nil or not humanoid:IsA("Humanoid") then
            return
        end
        humanoid.StateChanged:Connect(function(_, newState: Enum.HumanoidStateType)
            local root = character:FindFirstChild("HumanoidRootPart")
            if newState == Enum.HumanoidStateType.Landed and root and root:IsA("BasePart") then
                if self:IsInRoom(root.Position) then
                    self:Add(Tuning.NOISE_LANDING)
                end
            end
        end)
    end
    local function onPlayer(player: Player): ()
        player.CharacterRemoving:Connect(function()
            runSeconds[player] = nil
        end)
        player.CharacterAdded:Connect(onCharacter)
        if player.Character then
            task.spawn(onCharacter, player.Character)
        end
        local remote = Remotes.Get("NoiseState") :: RemoteEvent
        remote:FireClient(player, noise, Tuning.NOISE_MAX)
    end
    Players.PlayerAdded:Connect(onPlayer)
    Players.PlayerRemoving:Connect(function(player: Player)
        runSeconds[player] = nil
    end)
    for _, player in Players:GetPlayers() do
        onPlayer(player)
    end

    RunService.Heartbeat:Connect(function(dt: number)
        local gain = movementNoise(dt)
        if not frozen then
            if gain > 0 then
                addEffective(gain)
            else
                noise = math.max(noise - Tuning.NOISE_DECAY_PER_SECOND * dt, 0)
            end
        end
        sinceBroadcast += dt
        if sinceBroadcast >= 1 / Tuning.NOISE_BROADCAST_HZ then
            sinceBroadcast = 0
            if math.abs(noise - lastSent) >= 0.5 or (noise == 0 and lastSent ~= 0) then
                broadcast()
            end
        end
    end)
end

return NoiseService
