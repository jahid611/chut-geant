--!strict

--[[
    ChallengeService
    Defis chronometres (idee 11 du carnet docs/IDEES.md) : une plaque lumineuse « DÉFI » posee sur le sol de la
    chambre, entre le tapis et les bases. Son bouton lance un defi au hasard :
    - « Voleur éclair » : ramener 3 jouets dans sa base en 90 s ;
    - « Chasseur de raretés » : ramener 1 jouet Rare ou mieux en 60 s ;
    - « Pas de loup » : ramener 5 jouets en 150 s sans que la jauge de la chambre depasse 50 %.
    Echec si le bebe se reveille (GiantService:GetState() ~= "Sleeping"), si le temps est ecoule, ou (Pas de loup)
    si la jauge depasse 50 %. Reussite : 8 000 tetines + 300 XP + badge « Voleur éclair » (stat challengesWon).
    Un defi par joueur toutes les 10 min (compte a partir du lancement).

    Attributs publies : ChallengeTitle, ChallengeText, ChallengeGoal, ChallengeProgress, ChallengeEndsAt (temps
    serveur), ChallengeReadyAt. Remote ChallengeResult (serveur -> client) : ("win", recompense) | ("fail", raison)
    | ("info", message).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GiantService = require(script.Parent:WaitForChild("GiantService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local PassService = require(script.Parent:WaitForChild("PassService"))

type Challenge = {
    id: string,
    title: string,
    text: string,
    goal: number,
    seconds: number,
    rareOnly: boolean,
    quiet: boolean,
}

type Run = {
    challenge: Challenge,
    progress: number,
    endsAt: number,
}

local CHALLENGES: { Challenge } = {
    {
        id = "TroisJouets",
        title = "Voleur éclair",
        text = "Ramène 3 jouets dans ta base en 90 s sans réveiller le bébé !",
        goal = 3,
        seconds = 90,
        rareOnly = false,
        quiet = false,
    },
    {
        id = "JouetRare",
        title = "Chasseur de raretés",
        text = "Ramène 1 jouet Rare ou mieux en 60 s !",
        goal = 1,
        seconds = 60,
        rareOnly = true,
        quiet = false,
    },
    {
        id = "PasDeLoup",
        title = "Pas de loup",
        text = "Ramène 5 jouets sans que la jauge dépasse 50 % !",
        goal = 5,
        seconds = 150,
        rareOnly = false,
        quiet = true,
    },
}

local COOLDOWN = 600
local REWARD_CASH = 8000
local REWARD_XP = 300
local BADGE = "Voleur éclair"
local QUIET_LIMIT = 0.5
-- Plaque : au bord gauche du tapis (centre z = 70, rayon 190), sur le parquet, loin des bases (z = 290) ; les
-- positions suivantes servent si un meuble occupe la premiere (le rayon doit toucher le sol, y < 3).
local PLATE_POSITIONS = { Vector3.new(-235, 0, 70), Vector3.new(235, 0, 70), Vector3.new(-235, 0, -40) }
local PLATE_SIZE = 16
local STAR_IMAGE = "rbxassetid://138761456781140" -- icone etoile du jeu (Ui/Assets.etoile)
local RARE: { [string]: boolean } = { Rare = true, Epic = true, Legendary = true }

local ChallengeService = {}

local runs: { [Player]: Run } = {}
local lastId: { [Player]: string } = {}

local function resultRemote(): RemoteEvent
    return Remotes.Get("ChallengeResult") :: RemoteEvent
end

local function clear(player: Player): ()
    runs[player] = nil
    for _, name in { "ChallengeTitle", "ChallengeText", "ChallengeGoal", "ChallengeProgress", "ChallengeEndsAt" } do
        player:SetAttribute(name, nil)
    end
end

local function fail(player: Player, reason: string): ()
    clear(player)
    resultRemote():FireClient(player, "fail", reason)
end

local function win(player: Player, run: Run): ()
    clear(player)
    BaseService:AddCash(player, REWARD_CASH)
    PassService:AddXp(player, REWARD_XP, "defi")
    DataService:AddStat(player, "challengesWon", 1)
    local profile = DataService:Get(player)
    local wins = if profile then profile.stats.challengesWon or 1 else 1
    resultRemote():FireClient(player, "win", {
        title = run.challenge.title,
        cash = REWARD_CASH,
        xp = REWARD_XP,
        badge = BADGE,
        wins = wins,
    })
end

local function inRoom(player: Player): boolean
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    return root ~= nil and root:IsA("BasePart") and NoiseService:IsInRoom(root.Position)
end

local function start(player: Player): ()
    if runs[player] then
        resultRemote():FireClient(player, "info", "Tu as déjà un défi en cours !")
        return
    end
    local now = workspace:GetServerTimeNow()
    local readyAt = player:GetAttribute("ChallengeReadyAt")
    if typeof(readyAt) == "number" and readyAt > now then
        local minutes = math.ceil((readyAt - now) / 60)
        resultRemote():FireClient(player, "info", string.format("Prochain défi dans %d min", minutes))
        return
    end
    if GiantService:GetState() ~= "Sleeping" then
        resultRemote():FireClient(player, "info", "Attends que le bébé dorme !")
        return
    end
    if not inRoom(player) then
        return
    end
    local choices: { Challenge } = {}
    for _, challenge in CHALLENGES do
        if challenge.id ~= lastId[player] then
            table.insert(choices, challenge)
        end
    end
    local challenge = choices[math.random(1, #choices)]
    lastId[player] = challenge.id
    local run: Run = { challenge = challenge, progress = 0, endsAt = now + challenge.seconds }
    runs[player] = run
    player:SetAttribute("ChallengeReadyAt", now + COOLDOWN)
    player:SetAttribute("ChallengeTitle", challenge.title)
    player:SetAttribute("ChallengeText", challenge.text)
    player:SetAttribute("ChallengeGoal", challenge.goal)
    player:SetAttribute("ChallengeProgress", 0)
    player:SetAttribute("ChallengeEndsAt", run.endsAt)
end

local function groundAt(position: Vector3): Vector3?
    local ignore: { Instance } = {}
    for _, player in Players:GetPlayers() do
        if player.Character then
            table.insert(ignore, player.Character)
        end
    end
    local live = workspace:FindFirstChild("ToysLive")
    if live then
        table.insert(ignore, live)
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(position + Vector3.new(0, 300, 0), Vector3.new(0, -400, 0), params)
    return if hit then hit.Position else nil
end

-- Plaque lumineuse « DÉFI » : disque neon, lumiere, panneau flottant et bouton.
local function buildPlate(): ()
    local ground: Vector3? = nil
    for _, candidate in PLATE_POSITIONS do
        local hit = groundAt(candidate)
        -- sol de la chambre (parquet a y ~0), pas un meuble ni le tapis epais
        if hit and hit.Y < 3 then
            ground = hit
            break
        end
    end
    if ground == nil then
        warn("[ChallengeService] pas de sol libre pour la plaque de defi")
        return
    end
    local plate = Instance.new("Part")
    plate.Name = "PlaqueDefi"
    plate.Shape = Enum.PartType.Cylinder
    plate.Size = Vector3.new(1, PLATE_SIZE, PLATE_SIZE)
    plate.CFrame = CFrame.new(ground + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
    plate.Anchored = true
    plate.CanCollide = false
    plate.CanTouch = false
    plate.CanQuery = false
    plate.CastShadow = false
    -- pas de Neon : avec le bloom de la chambre, le disque eblouissait tout l'ecran des qu'on s'en approchait
    plate.Material = Enum.Material.SmoothPlastic
    plate.Color = Color3.fromRGB(255, 205, 90)
    plate.Transparency = 0.35
    plate.Parent = workspace

    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 210, 120)
    light.Brightness = 1.2
    light.Range = 24
    light.Parent = plate

    local sign = Instance.new("BillboardGui")
    sign.Name = "Panneau"
    sign.Size = UDim2.fromScale(12, 4.2)
    sign.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
    sign.MaxDistance = 260
    sign.LightInfluence = 0
    sign.Parent = plate
    local star = Instance.new("ImageLabel")
    star.Name = "Etoile"
    star.BackgroundTransparency = 1
    star.Image = STAR_IMAGE
    star.ScaleType = Enum.ScaleType.Fit
    star.Size = UDim2.fromScale(0.3, 1)
    star.Parent = sign
    local title = Instance.new("TextLabel")
    title.Name = "Titre"
    title.BackgroundTransparency = 1
    title.Text = "DÉFI"
    title.Font = Enum.Font.FredokaOne
    title.TextScaled = true
    title.TextColor3 = Color3.fromRGB(255, 214, 90)
    title.Size = UDim2.fromScale(0.68, 1)
    title.Position = UDim2.fromScale(0.32, 0)
    title.Parent = sign
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 3
    stroke.Color = Color3.fromRGB(30, 26, 60)
    stroke.Parent = title

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "LancerDefi"
    prompt.ActionText = "Relever le défi"
    prompt.ObjectText = "Défi chronométré"
    prompt.HoldDuration = 0.5
    prompt.MaxActivationDistance = 16
    prompt.RequiresLineOfSight = false
    prompt.Parent = plate
    prompt.Triggered:Connect(start)

    -- La plaque respire doucement pour attirer l'oeil.
    task.spawn(function()
        local t = 0
        while plate.Parent do
            t += 0.1
            plate.Transparency = 0.3 + 0.15 * (1 + math.sin(t * 2)) / 2
            light.Brightness = 1 + 0.4 * math.sin(t * 2)
            task.wait(0.1)
        end
    end)
end

local function onDeposit(player: Player, toyId: string, _mutation: string?): ()
    local run: Run? = runs[player]
    if run == nil then
        return
    end
    if run.challenge.rareOnly then
        local def = Toys.Get(toyId)
        if def == nil or not RARE[def.rarity] then
            return
        end
    end
    run.progress += 1
    player:SetAttribute("ChallengeProgress", run.progress)
    if run.progress >= run.challenge.goal then
        win(player, run)
    end
end

local function tick(): ()
    local now = workspace:GetServerTimeNow()
    local awake = GiantService:GetState() ~= "Sleeping"
    local loud = NoiseService:Get() > Tuning.NOISE_MAX * QUIET_LIMIT
    for player, run in runs do
        if player.Parent == nil then
            runs[player] = nil
        elseif awake then
            fail(player, "Le bébé s'est réveillé...")
        elseif now >= run.endsAt then
            fail(player, "Temps écoulé !")
        elseif run.challenge.quiet and loud then
            fail(player, "Trop de bruit : la jauge a dépassé 50 %")
        end
    end
end

function ChallengeService:Init(): () end

function ChallengeService:Start(): ()
    BaseService.ToyDeposited:Connect(onDeposit)
    Players.PlayerRemoving:Connect(function(player: Player)
        runs[player] = nil
        lastId[player] = nil
    end)
    task.spawn(function()
        -- la chambre est chargee avec le place, un court delai laisse le temps aux autres services de demarrer
        task.wait(2)
        buildPlate()
    end)
    local elapsed = 0
    RunService.Heartbeat:Connect(function(dt: number)
        elapsed += dt
        if elapsed >= 0.25 then
            elapsed = 0
            tick()
        end
    end)
end

return ChallengeService
