--!strict

--[[
    PacifierMissionService
    Mission du jour « Vole la tetine du bebe » (idee 4 du carnet docs/IDEES.md).

    Une tetine unique (modele ServerStorage.ToyModels.Pacifier, grossie, doree et etincelante) est posee sur le matelas
    du berceau (cible du trampoline). Elle ne se vole QUE pendant un reveil du bebe (etat Hunting) : il faut grimper au
    berceau pendant qu'il chasse, ultra risque. Chaque joueur la reussit une fois par jour au plus
    (profile.daily.pacifierDay = Retention.DayNumber) ; ensuite elle lui est refusee jusqu'au lendemain.

    Deposee (coffre ou tipi) : REWARD_CASH tetines, REWARD_XP XP, stat pacifierStolen (quete « Vole la tetine ») et, la
    premiere fois, la trainee exclusive TrailPacifier. Lachee au sol, elle reste la (reprise seulement pendant un
    reveil) ; perdue (joueur attrape) ou deposee, elle revient sur le berceau RESPAWN_SECONDS plus tard.

    Attribut du joueur TetineFaite (mission deja reussie aujourd'hui : le client cache le panneau « MISSION »).
    Remote PacifierMission : ("refused", texte) | ("win", { cash, xp, cosmetic? }) au joueur ; ("stolen", nom, userId)
    a tous.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Retention = require(Shared:WaitForChild("Retention"))
local Zone = require(Shared:WaitForChild("Zone"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CarryService = require(script.Parent:WaitForChild("CarryService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local GiantService = require(script.Parent:WaitForChild("GiantService"))
local PassService = require(script.Parent:WaitForChild("PassService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local TOY_ID = "Pacifier"
local MISSION_ATTRIBUTE = "TetineMission"
local DONE_ATTRIBUTE = "TetineFaite"
local EXCLUSIVE_COSMETIC = "TrailPacifier"
local REWARD_CASH = 20000
local REWARD_XP = 400
local SCALE = 1.7
local RESPAWN_SECONDS = 20
local DEPENDENCY_TIMEOUT = 15
local DEPENDENCY_POLL = 0.5
-- jouet « temporaire » qui ne disparait jamais de lui-meme
local LIFETIME = 10 ^ 9
local DROP_HEIGHT = 8
local REFUSE_COOLDOWN = 2.5
local GOLD = Color3.fromRGB(255, 205, 80)
local ICON = "rbxassetid://78137565006209" -- Ui/Assets.pouvoirTetine
local SIGN_NAME = "PanneauTetine"

local PacifierMissionService = {}

local mission: Instance? = nil
-- Dernier porteur de la tetine et moment ou elle a quitte le monde : les evenements (ToyDeposited, Destroying) sont
-- differes, le jouet est deja detruit quand le depot est traite.
local lastMission: Instance? = nil
local holderUserId: number? = nil
local goneAt: number? = nil
local respawnPending = false
local spawnInProgress = false
local lastSpawnFailure: string? = nil
local lastRefusal: { [Player]: number } = {}

local function remote(): RemoteEvent
    return Remotes.Get("PacifierMission") :: RemoteEvent
end

-- Attendre le vrai repère du matelas, sans déplacer la mission vers un point de secours.
local function cribSpot(): Vector3?
    for _, pad in CollectionService:GetTagged("Trampoline") do
        local target = pad:GetAttribute("Target")
        if pad:IsDescendantOf(workspace) and typeof(target) == "Vector3" then
            return target
        end
    end
    return nil
end

local function spawnDependencies(): (Vector3?, string?)
    local models = ServerStorage:FindFirstChild("ToyModels")
    if models == nil then
        return nil, "dépendance : ServerStorage.ToyModels indisponible"
    end
    local template = models:FindFirstChild(TOY_ID)
    if template == nil then
        return nil, "modèle absent : ServerStorage.ToyModels.Pacifier"
    end
    if not template.Archivable or Zone.PrimaryPart(template) == nil then
        return nil, "modèle invalide : Pacifier doit être clonable et avoir une pièce physique"
    end
    local live = workspace:FindFirstChild("ToysLive")
    if live == nil or not live:IsA("Folder") then
        return nil, "dépendance : Workspace.ToysLive indisponible"
    end
    local room = workspace:FindFirstChild("Chambre")
    local structure = if room then room:FindFirstChild("Structure") else nil
    local floor = if structure then structure:FindFirstChild("Sol") else nil
    if floor == nil or not floor:IsA("BasePart") then
        return nil, "dépendance : Workspace.Chambre.Structure.Sol indisponible"
    end
    local spot = cribSpot()
    if spot == nil then
        return nil, "dépendance : cible Target du trampoline indisponible"
    end
    for _, zone in CollectionService:GetTagged("GiantRoom") do
        if zone:IsA("BasePart") and zone:IsDescendantOf(workspace) and Zone.Contains(zone, spot) then
            return spot, nil
        end
    end
    return nil, "dépendance : zone GiantRoom du berceau indisponible"
end

local function reportSpawnFailure(reason: string): ()
    if lastSpawnFailure ~= reason then
        lastSpawnFailure = reason
        warn("[PacifierMissionService] " .. reason)
    end
end

local function doneToday(player: Player): boolean
    local profile = DataService:Get(player)
    if profile == nil then
        return false
    end
    local daily = profile.daily :: any
    return daily.pacifierDay == Retention.DayNumber(os.time())
end

local function publishDone(player: Player): ()
    player:SetAttribute(DONE_ATTRIBUTE, if doneToday(player) then true else nil)
end

local function refuse(player: Player, text: string): ()
    local now = os.clock()
    local last: number? = lastRefusal[player]
    if last and now - last < REFUSE_COOLDOWN then
        return
    end
    lastRefusal[player] = now
    remote():FireClient(player, "refused", text)
end

-- Filtre de prise (CarryService) : la tetine seulement pendant un reveil, une fois par jour.
local function canTake(player: Player, toy: Instance): boolean
    if toy:GetAttribute(MISSION_ATTRIBUTE) ~= true then
        return true
    end
    if doneToday(player) then
        refuse(player, "Tu as déjà volé la tétine aujourd'hui : reviens demain !")
        return false
    end
    local state = GiantService:GetState()
    if state ~= "Hunting" then
        refuse(player, "La tétine ne se vole que quand le bébé est réveillé !")
        return false
    end
    return true
end

-- Tetine grossie, lueur doree, etincelles et panneau « MISSION » visible de loin.
local function decorate(toy: Instance): ()
    toy:SetAttribute(MISSION_ATTRIBUTE, true)
    if toy:IsA("Model") then
        toy:ScaleTo(toy:GetScale() * SCALE)
    end
    local highlight = Instance.new("Highlight")
    highlight.Name = "LueurTetine"
    highlight.FillColor = GOLD
    highlight.FillTransparency = 0.6
    highlight.OutlineColor = Color3.fromRGB(255, 240, 170)
    highlight.OutlineTransparency = 0.1
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.Parent = toy

    local primary = Zone.PrimaryPart(toy)
    if primary == nil then
        return
    end
    local light = Instance.new("PointLight")
    light.Name = "LumiereTetine"
    light.Color = GOLD
    light.Brightness = 1.2
    light.Range = 14
    light.Parent = primary

    local sparkles = Instance.new("ParticleEmitter")
    sparkles.Name = "EtincellesTetine"
    -- texture livree avec Roblox (pas d'identifiant a televerser)
    sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
    sparkles.LightEmission = 1
    sparkles.Size = NumberSequence.new(0.8, 0)
    sparkles.Lifetime = NumberRange.new(0.5, 1)
    sparkles.Rate = 10
    sparkles.Speed = NumberRange.new(1, 3)
    sparkles.SpreadAngle = Vector2.new(180, 180)
    sparkles.Parent = primary

    local sign = Instance.new("BillboardGui")
    sign.Name = SIGN_NAME
    sign.Adornee = primary
    sign.Size = UDim2.fromOffset(150, 64)
    sign.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
    sign.AlwaysOnTop = true
    sign.MaxDistance = 320
    sign.LightInfluence = 0
    sign.Parent = toy
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icone"
    icon.BackgroundTransparency = 1
    icon.Image = ICON
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Size = UDim2.fromScale(0.4, 1)
    icon.Parent = sign
    local title = Instance.new("TextLabel")
    title.Name = "Titre"
    title.BackgroundTransparency = 1
    title.Text = "MISSION"
    title.Font = Enum.Font.FredokaOne
    title.TextScaled = true
    title.TextColor3 = GOLD
    title.Size = UDim2.fromScale(0.6, 0.7)
    title.Position = UDim2.fromScale(0.4, 0.15)
    title.Parent = sign
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 3
    stroke.Color = Color3.fromRGB(30, 26, 60)
    stroke.Parent = title
    -- porte, le panneau disparait (le voleur est deja reconnu par sa course)
    toy:GetAttributeChangedSignal("CarrierUserId"):Connect(function()
        sign.Enabled = toy:GetAttribute("CarrierUserId") == nil
    end)
end

local spawnMission: () -> ()

local function scheduleRespawn(): ()
    if respawnPending then
        return
    end
    respawnPending = true
    task.delay(RESPAWN_SECONDS, function()
        respawnPending = false
        spawnMission()
    end)
end

spawnMission = function(): ()
    local current = mission
    if spawnInProgress or (current and current.Parent) then
        return
    end
    spawnInProgress = true
    local deadline = os.clock() + DEPENDENCY_TIMEOUT
    local spot, reason = spawnDependencies()
    while spot == nil and os.clock() < deadline do
        task.wait(DEPENDENCY_POLL)
        spot, reason = spawnDependencies()
    end
    if spot == nil then
        spawnInProgress = false
        reportSpawnFailure(
            (reason or "dépendance indisponible") .. " ; attente de 15 s expirée, nouvel essai dans 20 s"
        )
        scheduleRespawn()
        return
    end
    local toy, failure =
        ToySpawnService:SpawnTemporary(TOY_ID, spot + Vector3.new(0, DROP_HEIGHT, 0), nil, LIFETIME, nil)
    spawnInProgress = false
    if toy == nil then
        -- Le placement reste protégé par PlaceAt. Un refus nécessite une tâche séparée, sans essais en boucle.
        reportSpawnFailure(failure or "échec d'apparition sans diagnostic")
        return
    end
    lastSpawnFailure = nil
    decorate(toy)
    mission = toy
    lastMission = toy
    holderUserId = nil
    goneAt = nil
    toy:GetAttributeChangedSignal("CarrierUserId"):Connect(function()
        local carrier = toy:GetAttribute("CarrierUserId")
        if typeof(carrier) == "number" then
            holderUserId = carrier
        end
    end)
    toy.Destroying:Connect(function()
        if lastMission == toy and goneAt == nil then
            goneAt = os.clock()
        end
        if mission == toy then
            mission = nil
            scheduleRespawn()
        end
    end)
end

-- Depot (coffre ou tipi) d'une « Tetine » par le dernier porteur de la mission, qui la porte encore ou vient de la
-- deposer (jouet detruit juste apres le depot, avant le traitement de l'evenement differe).
local GONE_TOLERANCE = 2
local function onDeposited(player: Player, toyId: string): ()
    local toy = lastMission
    if toyId ~= TOY_ID or toy == nil or holderUserId ~= player.UserId then
        return
    end
    local stillCarried = toy.Parent ~= nil and toy:GetAttribute("CarrierUserId") == player.UserId
    local gone = goneAt
    local justGone = toy.Parent == nil and (gone == nil or os.clock() - gone < GONE_TOLERANCE)
    if not stillCarried and not justGone then
        return
    end
    holderUserId = nil
    local profile = DataService:Get(player)
    if profile == nil or doneToday(player) then
        return
    end
    local daily = profile.daily :: any
    daily.pacifierDay = Retention.DayNumber(os.time())
    publishDone(player)
    local cosmetic: string? = nil
    if not ShopService:Owns(player, EXCLUSIVE_COSMETIC) and ShopService:Grant(player, EXCLUSIVE_COSMETIC) then
        cosmetic = EXCLUSIVE_COSMETIC
    end
    BaseService:AddCash(player, REWARD_CASH)
    PassService:AddXp(player, REWARD_XP, "tetine")
    DataService:AddStat(player, "pacifierStolen", 1)
    DataService:Save(player)
    remote():FireClient(player, "win", { cash = REWARD_CASH, xp = REWARD_XP, cosmetic = cosmetic })
    remote():FireAllClients("stolen", player.DisplayName, player.UserId)
end

-- Tests en jeu : la tetine actuelle (ou nil).
function PacifierMissionService:GetMission(): Instance?
    return mission
end

function PacifierMissionService:Init(): () end

function PacifierMissionService:Start(): ()
    CarryService:SetPickupFilter(canTake)
    BaseService.ToyDeposited:Connect(onDeposited)

    local function onPlayer(player: Player): ()
        if DataService:WaitForProfile(player) then
            publishDone(player)
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayer, player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        lastRefusal[player] = nil
    end)

    -- Les filtres et écouteurs sont branchés ; Start revient sans attendre les assets.
    task.spawn(spawnMission)
    task.spawn(function()
        -- changement de jour : la mission redevient possible pour tout le monde
        while true do
            task.wait(30)
            for _, player in Players:GetPlayers() do
                if DataService:Get(player) then
                    publishDone(player)
                end
            end
        end
    end)
end

return PacifierMissionService
