--!strict

--[[
    KitchenEventService
    Evenements propres a la cuisine (idee 22 du carnet docs/IDEES.md), pour les joueurs dont l'attribut Piece vaut
    "Cuisine". Ils s'appuient sur DogService (jauge, reveil, chasse) sans dupliquer sa logique :
    - FridgeLight : le frigo s'ouvre tout seul et sa lumiere balaie le carrelage ; un joueur pris dans le faisceau
      (sans meuble entre lui et le frigo) remplit la jauge du chien, qui se reveille ;
    - BowlCrash : la gamelle glisse puis tombe avec fracas : gros bruit sur la jauge du chien ;
    - DogDream : le chien reve et aboie en dormant, fausse alerte (aucun bruit ajoute).
    Un evenement a la fois, jamais le meme deux fois de suite, seulement quand le chien dort et qu'un joueur est dans la
    cuisine. Remote KitchenEvent (kind, phase, endsAt) vers les joueurs de la cuisine (KitchenEventController).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kitchen = require(Shared:WaitForChild("Kitchen"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DogService = require(script.Parent:WaitForChild("DogService"))

local FIRST_DELAY = 45
local MIN_GAP = 55
local MAX_GAP = 100

local FRIDGE_WARN_SECONDS = 2.5
local FRIDGE_SWEEP_SECONDS = 8
local FRIDGE_SWEEP_ANGLE = math.rad(50)
local FRIDGE_BEAM_LENGTH = 260
local FRIDGE_BEAM_HALF_ANGLE = math.rad(10)
local FRIDGE_CHECK_SECONDS = 0.2

local BOWL_WARN_SECONDS = 3
local BOWL_NOISE = 45
local BOWL_DOWN_SECONDS = 5
local BOWL_SOUND = "rbxassetid://9118736388" -- meme son que Sfx.weaponBonk (bibliotheque Roblox)

local DREAM_SECONDS = 8
local BARK_SOUND = "rbxassetid://99723552215501" -- « Dog bark », comme DogController

type EventDef = { name: string, run: () -> (), weight: number }

local KitchenEventService = {}

local random = Random.new()
local running = false
local lastEvent: string? = nil

local function kitchen(): Instance?
    return workspace:FindFirstChild("Cuisine")
end

local function inKitchen(player: Player): boolean
    return player:GetAttribute("Piece") == "Cuisine"
end

local function kitchenPlayers(): { Player }
    local list: { Player } = {}
    for _, player in Players:GetPlayers() do
        if inKitchen(player) then
            table.insert(list, player)
        end
    end
    return list
end

local function announce(kind: string, phase: string, endsAt: number, target: Player?): ()
    local remote = Remotes.Get("KitchenEvent") :: RemoteEvent
    if target then
        remote:FireClient(target, kind, phase, endsAt)
        return
    end
    for _, player in kitchenPlayers() do
        remote:FireClient(player, kind, phase, endsAt)
    end
end

local function invisiblePart(name: string, position: Vector3, parent: Instance): BasePart
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Transparency = 1
    part.Size = Vector3.one
    part.Position = position
    part.Parent = parent
    return part
end

local function playSound(id: string, parent: Instance, volume: number, speed: number): ()
    local sound = Instance.new("Sound")
    sound.SoundId = id
    sound.Volume = volume
    sound.PlaybackSpeed = speed
    sound.RollOffMaxDistance = 500
    sound.Parent = parent
    sound:Play()
    task.delay(4, function()
        sound:Destroy()
    end)
end

-- Frigo : faisceau qui balaie le carrelage ; un joueur eclaire (sans obstacle) reveille le chien.
local function fridgeLight(): ()
    local root = kitchen()
    local source = if root then root:FindFirstChild("LumiereFrigo") else nil
    if root == nil or source == nil or not source:IsA("BasePart") then
        return
    end
    local origin = source.Position
    local now = workspace:GetServerTimeNow()
    announce("FridgeLight", "warn", now + FRIDGE_WARN_SECONDS)
    task.wait(FRIDGE_WARN_SECONDS)

    local folder = Instance.new("Folder")
    folder.Name = "EvenementFrigo"
    folder.Parent = root
    local sourcePart = invisiblePart("SourceFrigo", origin, folder)
    local targetPart = invisiblePart("CibleFrigo", origin + Vector3.new(0, -origin.Y + 1, FRIDGE_BEAM_LENGTH), folder)
    local a0 = Instance.new("Attachment")
    a0.Parent = sourcePart
    local a1 = Instance.new("Attachment")
    a1.Parent = targetPart
    local beam = Instance.new("Beam")
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.Color = ColorSequence.new(Color3.fromRGB(255, 244, 214))
    beam.Transparency = NumberSequence.new(0.5, 0.85)
    beam.Width0 = 4
    beam.Width1 = 70
    beam.LightEmission = 0.7
    beam.FaceCamera = true
    beam.Parent = sourcePart
    local glow = Instance.new("PointLight")
    glow.Color = Color3.fromRGB(255, 244, 214)
    glow.Brightness = 2
    glow.Range = 40
    glow.Parent = targetPart

    local started = workspace:GetServerTimeNow()
    announce("FridgeLight", "start", started + FRIDGE_SWEEP_SECONDS)
    local lit: { [Player]: boolean } = {}
    local woke = false
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    while workspace:GetServerTimeNow() - started < FRIDGE_SWEEP_SECONDS do
        local t = (workspace:GetServerTimeNow() - started) / FRIDGE_SWEEP_SECONDS
        local yaw = math.sin(t * math.pi * 2) * FRIDGE_SWEEP_ANGLE
        local direction = CFrame.Angles(0, yaw, 0) * Vector3.new(0, 0, 1)
        targetPart.Position = Vector3.new(origin.X, 1, origin.Z) + direction * FRIDGE_BEAM_LENGTH

        local ignore: { Instance } = { folder }
        for _, player in Players:GetPlayers() do
            if player.Character then
                table.insert(ignore, player.Character)
            end
        end
        local live = workspace:FindFirstChild("ToysLive")
        if live then
            table.insert(ignore, live)
        end
        params.FilterDescendantsInstances = ignore
        for _, player in kitchenPlayers() do
            local character = player.Character
            local body = if character then character:FindFirstChild("HumanoidRootPart") else nil
            if lit[player] or body == nil or not body:IsA("BasePart") then
                continue
            end
            local flat = Vector3.new(body.Position.X - origin.X, 0, body.Position.Z - origin.Z)
            if flat.Magnitude > FRIDGE_BEAM_LENGTH or flat.Magnitude < 1 then
                continue
            end
            local angle = math.acos(math.clamp(flat.Unit:Dot(direction), -1, 1))
            if angle > FRIDGE_BEAM_HALF_ANGLE then
                continue
            end
            local toBody = body.Position - origin
            local hit = workspace:Raycast(origin, toBody, params)
            if hit and (hit.Position - origin).Magnitude < toBody.Magnitude - 2 then
                continue
            end
            lit[player] = true
            announce("FridgeLight", "lit", 0, player)
            if not woke then
                woke = true
                DogService:Add(Kitchen.NOISE_MAX)
            end
        end
        task.wait(FRIDGE_CHECK_SECONDS)
    end
    folder:Destroy()
    announce("FridgeLight", "end", 0)
end

-- Gamelle : elle tremble, tombe avec fracas (gros bruit sur la jauge du chien), puis revient en place.
local function bowlCrash(): ()
    local root = kitchen()
    local bowl = if root then root:FindFirstChild("Gamelle") else nil
    if bowl == nil or not bowl:IsA("Model") then
        return
    end
    local rest = bowl:GetPivot()
    local driver = Instance.new("CFrameValue")
    driver.Value = rest
    driver.Changed:Connect(function(value: CFrame)
        bowl:PivotTo(value)
    end)
    announce("BowlCrash", "warn", workspace:GetServerTimeNow() + BOWL_WARN_SECONDS)
    local steps = 6
    for i = 1, steps do
        local side = if i % 2 == 0 then 1 else -1
        TweenService:Create(
            driver,
            TweenInfo.new(BOWL_WARN_SECONDS / steps, Enum.EasingStyle.Sine),
            { Value = rest * CFrame.Angles(0, 0, math.rad(6 * side)) }
        ):Play()
        task.wait(BOWL_WARN_SECONDS / steps)
    end
    local fallen = rest * CFrame.new(0, 0, 6) * CFrame.Angles(math.rad(75), 0, 0)
    TweenService:Create(driver, TweenInfo.new(0.35, Enum.EasingStyle.Bounce), { Value = fallen }):Play()
    local soundParent = bowl:FindFirstChildWhichIsA("BasePart", true)
    if soundParent then
        playSound(BOWL_SOUND, soundParent, 1, 0.7)
    end
    DogService:Add(BOWL_NOISE)
    announce("BowlCrash", "start", workspace:GetServerTimeNow() + BOWL_DOWN_SECONDS)
    task.wait(BOWL_DOWN_SECONDS)
    TweenService:Create(driver, TweenInfo.new(1, Enum.EasingStyle.Sine), { Value = rest }):Play()
    task.wait(1.1)
    driver:Destroy()
    bowl:PivotTo(rest)
    announce("BowlCrash", "end", 0)
end

-- Reve du chien : aboiements en dormant, fausse alerte (la jauge ne bouge pas).
local function dogDream(): ()
    local root = kitchen()
    local dog = if root then root:FindFirstChild(Kitchen.DOG_NAME) else nil
    local body = if dog then dog:FindFirstChildWhichIsA("BasePart", true) else nil
    if body == nil then
        return
    end
    local started = workspace:GetServerTimeNow()
    announce("DogDream", "start", started + DREAM_SECONDS)
    while workspace:GetServerTimeNow() - started < DREAM_SECONDS do
        local state = DogService:GetState()
        if state ~= "Sleeping" then
            break
        end
        playSound(BARK_SOUND, body, 0.6, random:NextNumber(1.15, 1.35))
        task.wait(random:NextNumber(1.3, 2.2))
    end
    announce("DogDream", "end", 0)
end

local EVENTS: { EventDef } = {
    { name = "FridgeLight", run = fridgeLight, weight = 2 },
    { name = "BowlCrash", run = bowlCrash, weight = 2 },
    { name = "DogDream", run = dogDream, weight = 1 },
}

local function pickEvent(): EventDef?
    local pool: { EventDef } = {}
    local total = 0
    for _, def in EVENTS do
        if def.name ~= lastEvent then
            table.insert(pool, def)
            total += def.weight
        end
    end
    local roll = random:NextNumber() * total
    for _, def in pool do
        roll -= def.weight
        if roll <= 0 then
            return def
        end
    end
    return pool[#pool]
end

local function runEvent(def: EventDef): ()
    lastEvent = def.name
    running = true
    local ok, err = pcall(function()
        def.run()
    end)
    if not ok then
        warn("[KitchenEventService] " .. def.name .. " : " .. tostring(err))
    end
    running = false
end

-- Lance un evenement de cuisine tout de suite (tests) : "FridgeLight" | "BowlCrash" | "DogDream".
function KitchenEventService:Trigger(kind: string): boolean
    if running then
        return false
    end
    for _, def in EVENTS do
        if def.name == kind then
            running = true
            task.spawn(runEvent, def)
            return true
        end
    end
    return false
end

function KitchenEventService:IsRunning(): boolean
    return running
end

function KitchenEventService:Init(): () end

function KitchenEventService:Start(): ()
    task.spawn(function()
        task.wait(FIRST_DELAY)
        while true do
            local state = DogService:GetState()
            if not running and state == "Sleeping" and #kitchenPlayers() > 0 then
                local def = pickEvent()
                if def then
                    runEvent(def)
                end
            end
            task.wait(random:NextNumber(MIN_GAP, MAX_GAP))
        end
    end)
end

return KitchenEventService
