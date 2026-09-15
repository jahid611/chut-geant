--!strict

--[[
    NightlightService
    Veilleuse a remonter (idee 15 du carnet docs/IDEES.md) : les deux veilleuses des commodes s'epuisent en
    DRAIN_SECONDS. Leurs lueurs (Chambre.Decor.Lumieres) baissent avec l'energie ; a vide, le bebe dort mal et le bruit
    ajoute est multiplie par EMPTY_NOISE_FACTOR.

    Au pied de chaque commode, un remontoir (piece invisible, ProximityPrompt maintenu HOLD_SECONDS, jauge en
    BillboardGui) : le remonter fait un leger bruit de clic, recharge la veilleuse, retire CALM_REDUCE de la jauge et
    divise le bruit ajoute par deux pendant CALM_SECONDS pour tout le serveur (cooperation entre inconnus). XP pour le
    joueur, attribut NightlightWinder de workspace (nom) et NightlightWinds (compteur) pour le message des clients.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataService = require(script.Parent:WaitForChild("DataService"))
local GiantService = require(script.Parent:WaitForChild("GiantService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local PassService = require(script.Parent:WaitForChild("PassService"))

local DRAIN_SECONDS = 240
local REWIND_BELOW = 60
local HOLD_SECONDS = 2.5
local WIND_NOISE = 4
local CALM_REDUCE = 15
local CALM_SECONDS = 20
local CALM_FACTOR = 0.5
local EMPTY_NOISE_FACTOR = 1.3
local PLAYER_COOLDOWN = 30
local WIND_XP = 40
local TICK = 1
-- au pied de la face avant des commodes (x = +-241), sur le parquet
local SPOTS = { Vector3.new(-225, 0, -10), Vector3.new(225, 0, -10) }
local MOON_ICON = "rbxassetid://86040169964113" -- Ui/Assets.lune

local NightlightService = {}

type Winder = { part: BasePart, prompt: ProximityPrompt, fill: Frame }

local energy = 100
local calmUntil = 0
local winders: { Winder } = {}
local lights: { { light: Light, base: number } } = {}
local lastWind: { [Player]: number } = {}

local function collectLights(): ()
    local chambre = workspace:FindFirstChild("Chambre")
    local decor = if chambre then chambre:FindFirstChild("Decor") else nil
    if decor == nil then
        return
    end
    for _, folder in decor:GetChildren() do
        if folder.Name == "Lumieres" then
            for _, descendant in folder:GetDescendants() do
                if descendant:IsA("Light") and descendant.Parent and descendant.Parent.Name:find("Veilleuse") then
                    table.insert(lights, { light = descendant, base = descendant.Brightness })
                end
            end
        end
    end
end

local function groundAt(position: Vector3): Vector3?
    local ignore: { Instance } = {}
    for _, player in Players:GetPlayers() do
        if player.Character then
            table.insert(ignore, player.Character)
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), params)
    return if hit then hit.Position else nil
end

local function refresh(): ()
    local fraction = energy / 100
    for _, entry in lights do
        entry.light.Brightness = entry.base * (0.2 + 0.8 * fraction)
    end
    local calm = workspace:GetServerTimeNow() < calmUntil
    for _, winder in winders do
        winder.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
        winder.fill.BackgroundColor3 = if fraction < 0.25
            then Color3.fromRGB(255, 110, 110)
            elseif fraction < 0.6 then Color3.fromRGB(255, 212, 96)
            else Color3.fromRGB(120, 220, 255)
        winder.prompt.Enabled = energy < REWIND_BELOW and not calm
    end
    NoiseService:SetGainMultiplier("VeilleuseVide", if energy <= 0 then EMPTY_NOISE_FACTOR else nil)
    NoiseService:SetGainMultiplier("VeilleuseCalme", if calm then CALM_FACTOR else nil)
    workspace:SetAttribute("NightlightEnergy", math.floor(energy))
    workspace:SetAttribute("NightlightCalmUntil", if calm then calmUntil else nil)
end

local function wind(player: Player): ()
    local now = os.clock()
    local last: number? = lastWind[player]
    if energy >= REWIND_BELOW or (last and now - last < PLAYER_COOLDOWN) then
        return
    end
    lastWind[player] = now
    energy = 100
    NoiseService:Add(WIND_NOISE)
    if GiantService:GetState() == "Sleeping" then
        NoiseService:Reduce(CALM_REDUCE)
        calmUntil = workspace:GetServerTimeNow() + CALM_SECONDS
    end
    PassService:AddXp(player, WIND_XP, "veilleuse")
    DataService:AddStat(player, "nightlightWinds", 1)
    local count = workspace:GetAttribute("NightlightWinds")
    workspace:SetAttribute("NightlightWinder", player.DisplayName)
    workspace:SetAttribute("NightlightWinds", (if typeof(count) == "number" then count else 0) + 1)
    refresh()
end

local function buildWinder(spot: Vector3): ()
    local ground = groundAt(spot)
    if ground == nil or ground.Y > 3 then
        warn(string.format("[NightlightService] pas de parquet libre pour le remontoir en %s", tostring(spot)))
        return
    end
    local part = Instance.new("Part")
    part.Name = "RemontoirVeilleuse"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Transparency = 1
    part.Size = Vector3.new(4, 4, 4)
    part.Position = ground + Vector3.new(0, 2, 0)
    part.Parent = workspace

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "Remonter"
    prompt.ActionText = "Remonter la veilleuse"
    prompt.ObjectText = "Veilleuse"
    prompt.HoldDuration = HOLD_SECONDS
    prompt.MaxActivationDistance = 14
    prompt.RequiresLineOfSight = false
    prompt.Enabled = false
    prompt.Parent = part
    prompt.Triggered:Connect(wind)

    local gauge = Instance.new("BillboardGui")
    gauge.Name = "JaugeVeilleuse"
    -- taille fixe en pixels : en studs, la jauge couvrait la moitie de l'ecran une fois devant le remontoir
    gauge.Size = UDim2.fromOffset(150, 46)
    gauge.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
    gauge.MaxDistance = 220
    gauge.LightInfluence = 0
    gauge.Parent = part
    local icon = Instance.new("ImageLabel")
    icon.Name = "Lune"
    icon.BackgroundTransparency = 1
    icon.Image = MOON_ICON
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Size = UDim2.fromScale(0.3, 1)
    icon.Parent = gauge
    local track = Instance.new("Frame")
    track.Name = "Fond"
    track.BackgroundColor3 = Color3.fromRGB(12, 16, 40)
    track.BackgroundTransparency = 0.15
    track.BorderSizePixel = 0
    track.AnchorPoint = Vector2.new(0, 0.5)
    track.Position = UDim2.fromScale(0.34, 0.5)
    track.Size = UDim2.fromScale(0.64, 0.42)
    track.Parent = gauge
    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track
    local trackStroke = Instance.new("UIStroke")
    trackStroke.Thickness = 2
    trackStroke.Color = Color3.new(1, 1, 1)
    trackStroke.Parent = track
    local fill = Instance.new("Frame")
    fill.Name = "Remplissage"
    fill.BorderSizePixel = 0
    fill.Size = UDim2.fromScale(1, 1)
    fill.Parent = track
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local winder: Winder = { part = part :: BasePart, prompt = prompt, fill = fill }
    table.insert(winders, winder)
end

function NightlightService:Init(): () end

function NightlightService:Start(): ()
    Players.PlayerRemoving:Connect(function(player: Player)
        lastWind[player] = nil
    end)
    task.spawn(function()
        -- la chambre est chargee avec le place ; court delai pour laisser les autres services demarrer
        task.wait(2)
        collectLights()
        for _, spot in SPOTS do
            buildWinder(spot)
        end
        refresh()
        local elapsed = 0
        RunService.Heartbeat:Connect(function(dt: number)
            elapsed += dt
            if elapsed < TICK then
                return
            end
            -- la veilleuse ne s'use que pendant que le bebe dort (pas pendant une chasse)
            if GiantService:GetState() == "Sleeping" then
                energy = math.max(energy - 100 * elapsed / DRAIN_SECONDS, 0)
            end
            elapsed = 0
            refresh()
        end)
    end)
end

-- Tests : vide la veilleuse tout de suite (NightlightService:SetEnergy(10)).
function NightlightService:SetEnergy(value: number): ()
    energy = math.clamp(value, 0, 100)
    refresh()
end

return NightlightService
