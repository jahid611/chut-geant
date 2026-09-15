--!strict

--[[
    LivingToyService
    Jouets vivants (idee 9 du carnet docs/IDEES.md) : a l'apparition, un jouet Rare ou mieux a LIVING_CHANCE d'etre
    « vivant » (attribut Vivant). Petits yeux qui clignent au-dessus de lui. Quand un joueur approche a moins de
    FLEE_RADIUS studs, il s'enfuit en petits bonds (tweens de pivot du modele ancre, qui evitent murs et meubles par
    rayons et restent au sol), avec des etoiles et un couinement. Apres TIRED_AFTER secondes de poursuite il est
    epuise pendant TIRED_SECONDS (« z z ») : on peut alors le voler. Deposer un jouet vivant rapporte un bonus unique
    de BONUS_INCOME_SECONDS secondes de son revenu (message au joueur : RoomEvent « LivingToy », phase « won »).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))
local Zone = require(Shared:WaitForChild("Zone"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local LIVING_CHANCE = 0.04
local FLEE_RADIUS = 18
local HOP_DISTANCE = 6
local HOP_HEIGHT = 2.5
local HOP_SECONDS = 0.3
local TIRED_AFTER = 12
local TIRED_SECONDS = 5
local START_DELAY = 2.5
local TICK = 0.1
local BONUS_INCOME_SECONDS = 30
local SQUEAK_SOUND = "rbxassetid://9114123168"
local LIVING_RARITIES: { [string]: boolean } = { Rare = true, Epic = true, Legendary = true }

type LivingState = {
    toy: Model,
    primary: BasePart,
    chase: number,
    tiredUntil: number,
    nextHop: number,
    readyAt: number,
    lastCarrier: number?,
    eyes: { Frame },
    snore: TextLabel,
    stars: ParticleEmitter,
    squeak: Sound,
}

local LivingToyService = {}

local living: { [Model]: LivingState } = {}
local random = Random.new()

local function rootOf(player: Player): BasePart?
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    return if root and root:IsA("BasePart") then root else nil
end

-- Petits yeux ronds (BillboardGui) au-dessus du jouet, et « z z » cache pour la fatigue.
local function buildEyes(toy: Model, primary: BasePart): ({ Frame }, TextLabel)
    local _, size = toy:GetBoundingBox()
    local top = toy:GetBoundingBox().Position.Y + size.Y / 2
    local gui = Instance.new("BillboardGui")
    gui.Name = "YeuxVivant"
    gui.Adornee = primary
    gui.Size = UDim2.fromOffset(70, 34)
    gui.StudsOffsetWorldSpace = Vector3.new(0, top - primary.Position.Y + 1.2, 0)
    gui.AlwaysOnTop = false
    gui.MaxDistance = 140
    gui.LightInfluence = 0
    gui.Parent = toy
    local eyes: { Frame } = {}
    for i = 1, 2 do
        local white = Instance.new("Frame")
        white.Name = "Oeil" .. i
        white.BackgroundColor3 = Color3.new(1, 1, 1)
        white.Size = UDim2.fromOffset(26, 26)
        white.AnchorPoint = Vector2.new(0.5, 0.5)
        white.Position = UDim2.new(0.5, (i == 1 and -16 or 16), 0.5, 0)
        white.Parent = gui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = white
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(40, 30, 60)
        stroke.Parent = white
        local pupil = Instance.new("Frame")
        pupil.Name = "Pupille"
        pupil.BackgroundColor3 = Color3.fromRGB(30, 25, 45)
        pupil.Size = UDim2.fromScale(0.5, 0.5)
        pupil.AnchorPoint = Vector2.new(0.5, 0.5)
        pupil.Position = UDim2.fromScale(0.55, 0.5)
        pupil.Parent = white
        local pupilCorner = Instance.new("UICorner")
        pupilCorner.CornerRadius = UDim.new(1, 0)
        pupilCorner.Parent = pupil
        table.insert(eyes, white)
    end
    local snore = Instance.new("TextLabel")
    snore.Name = "Fatigue"
    snore.BackgroundTransparency = 1
    snore.Size = UDim2.fromOffset(70, 30)
    snore.AnchorPoint = Vector2.new(0.5, 1)
    snore.Position = UDim2.fromScale(0.5, 0)
    snore.Font = Enum.Font.FredokaOne
    snore.TextScaled = true
    snore.TextColor3 = Color3.fromRGB(190, 210, 255)
    snore.TextStrokeTransparency = 0.2
    snore.Text = "z z z"
    snore.Visible = false
    snore.Parent = gui
    return eyes, snore
end

local function setEyesOpen(state: LivingState, open: boolean): ()
    for _, eye in state.eyes do
        eye.Size = if open then UDim2.fromOffset(26, 26) else UDim2.fromOffset(26, 5)
    end
end

-- Sol sous une position (hors du jouet et des personnages), ou nil.
local function groundAt(position: Vector3, ignore: { Instance }): Vector3?
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
    return if hit then hit.Position else nil
end

local function ignoreList(toy: Model): { Instance }
    local list: { Instance } = { toy }
    for _, player in Players:GetPlayers() do
        if player.Character then
            table.insert(list, player.Character)
        end
    end
    return list
end

-- Un bond pour s'eloigner de `from` : directions essayees (directe, puis +-60, +-120 degres), sans obstacle a hauteur
-- du jouet et avec un sol a l'arrivee pas plus de 6 studs plus haut ou plus bas.
local function hop(state: LivingState, from: Vector3): boolean
    local toy = state.toy
    local center, size = toy:GetBoundingBox()
    local away = Vector3.new(center.Position.X - from.X, 0, center.Position.Z - from.Z)
    if away.Magnitude < 0.1 then
        away = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1))
    end
    away = away.Unit
    local ignore = ignoreList(toy)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local bottomY = center.Position.Y - size.Y / 2
    for _, angle in { 0, 60, -60, 120, -120 } do
        local jitter = math.rad(angle + random:NextNumber(-15, 15))
        local direction = (CFrame.Angles(0, jitter, 0) * away).Unit
        local origin = Vector3.new(center.Position.X, bottomY + math.min(size.Y * 0.5, 3), center.Position.Z)
        local blocked = workspace:Raycast(origin, direction * (HOP_DISTANCE + math.max(size.X, size.Z) / 2 + 1), params)
        if blocked then
            continue
        end
        local target = center.Position + direction * HOP_DISTANCE
        local ground = groundAt(target, ignore)
        if ground == nil or math.abs(ground.Y - bottomY) > 6 then
            continue
        end
        -- l'orientation du modele est gardee (les jouets ne regardent pas tous vers -Z) : seule la position bondit
        local startPivot = toy:GetPivot()
        local goal = startPivot.Position + direction * HOP_DISTANCE + Vector3.new(0, ground.Y - bottomY, 0)
        local driver = Instance.new("NumberValue")
        driver.Value = 0
        driver.Changed:Connect(function(alpha: number)
            if toy.Parent == nil or toy:GetAttribute("CarrierUserId") ~= nil then
                return
            end
            local position = startPivot.Position:Lerp(goal, alpha)
                + Vector3.new(0, math.sin(alpha * math.pi) * HOP_HEIGHT, 0)
            toy:PivotTo(CFrame.new(position) * startPivot.Rotation)
        end)
        local tween = TweenService:Create(driver, TweenInfo.new(HOP_SECONDS, Enum.EasingStyle.Sine), { Value = 1 })
        tween.Completed:Connect(function()
            driver:Destroy()
        end)
        tween:Play()
        state.stars:Emit(4)
        state.squeak.PlaybackSpeed = 1 + random:NextNumber(-0.15, 0.2)
        state.squeak:Play()
        return true
    end
    return false
end

local function forget(toy: Model): ()
    local state = living[toy]
    if state == nil then
        return
    end
    living[toy] = nil
    local gui = toy:FindFirstChild("YeuxVivant")
    if gui then
        gui:Destroy()
    end
    state.stars:Destroy()
    state.squeak:Destroy()
end

local function makeLiving(toy: Instance): ()
    if not toy:IsA("Model") or toy:GetAttribute("Temporaire") or toy:GetAttribute("PointAccueil") then
        return
    end
    local toyId = toy:GetAttribute("ToyId")
    local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
    if def == nil or not LIVING_RARITIES[def.rarity] or random:NextNumber() >= LIVING_CHANCE then
        return
    end
    LivingToyService:Awaken(toy)
end

-- Rend un jouet vivant tout de suite (tests : LivingToyService:Awaken(workspace.ToysLive.<jouet>)).
function LivingToyService:Awaken(toy: Model): boolean
    if toy:GetAttribute("PointAccueil") then
        return false
    end
    if living[toy] then
        return true
    end
    local primary = Zone.PrimaryPart(toy)
    if primary == nil then
        return false
    end
    toy:SetAttribute("Vivant", true)
    local eyes, snore = buildEyes(toy, primary)
    local stars = Instance.new("ParticleEmitter")
    stars.Name = "EtoilesVivant"
    stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    stars.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 170, 220))
    stars.Size = NumberSequence.new(0.8, 0)
    stars.Lifetime = NumberRange.new(0.5, 0.9)
    stars.Speed = NumberRange.new(3, 6)
    stars.SpreadAngle = Vector2.new(180, 180)
    stars.LightEmission = 0.8
    stars.Rate = 0
    stars.Parent = primary
    local squeak = Instance.new("Sound")
    squeak.Name = "CouinementVivant"
    squeak.SoundId = SQUEAK_SOUND
    squeak.Volume = 0.5
    squeak.RollOffMaxDistance = 160
    squeak.Parent = primary
    local state: LivingState = {
        toy = toy,
        primary = primary,
        chase = 0,
        tiredUntil = 0,
        nextHop = 0,
        readyAt = os.clock() + START_DELAY,
        lastCarrier = nil,
        eyes = eyes,
        snore = snore,
        stars = stars,
        squeak = squeak,
    }
    living[toy] = state
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

local function tick(): ()
    local now = os.clock()
    for toy, state in living do
        if toy.Parent == nil then
            continue
        end
        local carried = toy:GetAttribute("CarrierUserId") ~= nil
        state.snore.Visible = now < state.tiredUntil and not carried
        -- clignement de temps en temps
        setEyesOpen(state, not (now % 3.2 < 0.15) and now >= state.tiredUntil)
        if carried or now < state.readyAt or now < state.tiredUntil or not state.primary.Anchored then
            if carried then
                state.chase = 0
            end
            continue
        end
        local center = toy:GetBoundingBox().Position
        local nearest: Vector3? = nil
        local best = FLEE_RADIUS
        for _, player in Players:GetPlayers() do
            local root = rootOf(player)
            if root then
                local distance = (Vector3.new(root.Position.X, center.Y, root.Position.Z) - center).Magnitude
                if distance < best then
                    best = distance
                    nearest = root.Position
                end
            end
        end
        if nearest == nil then
            state.chase = math.max(state.chase - TICK * 0.5, 0)
            continue
        end
        state.chase += TICK
        if state.chase >= TIRED_AFTER then
            state.chase = 0
            state.tiredUntil = now + TIRED_SECONDS
            continue
        end
        if now >= state.nextHop then
            if hop(state, nearest) then
                state.nextHop = now + HOP_SECONDS + 0.12
            else
                state.nextHop = now + 0.4
            end
        end
    end
end

local function onDeposited(player: Player, toyId: string, mutation: string?): ()
    for toy, state in living do
        local carrier = toy:GetAttribute("CarrierUserId")
        local byPlayer = carrier == player.UserId or (carrier == nil and state.lastCarrier == player.UserId)
        if byPlayer and toy:GetAttribute("ToyId") == toyId then
            local bonus = math.floor(Toys.Income(toyId, mutation) * BONUS_INCOME_SECONDS)
            if bonus > 0 then
                BaseService:AddCash(player, bonus)
            end
            player:SetAttribute("BonusVivant", bonus)
            local remote = Remotes.Get("RoomEvent") :: RemoteEvent
            remote:FireClient(player, "LivingToy", "won", 0)
            forget(toy)
            return
        end
    end
end

function LivingToyService:Init(): () end

function LivingToyService:Start(): ()
    ToySpawnService.Spawned:Connect(makeLiving)
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

return LivingToyService
