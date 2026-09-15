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
    reveil) ; detruite ou deposee, elle revient sur le berceau RESPAWN_SECONDS plus tard.

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
local RAY_HEIGHT = 30
local RAY_DEPTH = 100
local MIN_SUPPORT_NORMAL = 0.98
local MAX_SUPPORT_STEP = 0.25
local SEARCH_STEP = 3
local SEARCH_RINGS = 3 -- 49 positions au plus, à moins de 13 studs de Target.
local SEARCH_YAWS = 8
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
local random = Random.new()

local function remote(): RemoteEvent
    return Remotes.Get("PacifierMission") :: RemoteEvent
end

-- Attendre le vrai repère du matelas, sans déplacer la mission vers un point de secours.
local function cribSpot(): Vector3?
    local room = workspace:FindFirstChild("Chambre")
    for _, pad in CollectionService:GetTagged("Trampoline") do
        local target = pad:GetAttribute("Target")
        if room and pad:IsDescendantOf(room) and typeof(target) == "Vector3" then
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
    if
        not template.Archivable
        or not (template:IsA("Model") or template:IsA("BasePart"))
        or Zone.PrimaryPart(template) == nil
    then
        return nil, "modèle invalide : Pacifier doit être clonable et avoir une pièce physique"
    end
    local live = workspace:FindFirstChild("ToysLive")
    if live == nil or not live:IsA("Folder") then
        return nil, "dépendance : Workspace.ToysLive indisponible"
    end
    local room = workspace:FindFirstChild("Chambre")
    local decor = if room then room:FindFirstChild("Decor") else nil
    if decor == nil or decor:FindFirstChild("Crib") == nil then
        return nil, "dépendance : Workspace.Chambre.Decor.Crib indisponible"
    end
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

-- Exception privée à cette apparition : aucune permission de meuble n'est transmise aux lâchers suivants.
-- Le rayon interroge aussi les obstacles ; un autre meuble ou le parquet ne remplacent jamais le berceau.
local function createOnMattress(spot: Vector3): (Instance?, string?)
    local room = workspace:FindFirstChild("Chambre")
    local decor = if room then room:FindFirstChild("Decor") else nil
    local crib = if decor then decor:FindFirstChild("Crib") else nil
    local live = workspace:FindFirstChild("ToysLive")
    local models = ServerStorage:FindFirstChild("ToyModels")
    local template = if models then models:FindFirstChild(TOY_ID) else nil
    if crib == nil or live == nil or template == nil then
        return nil, "dépendance : berceau, ToysLive ou modèle indisponible"
    end
    local params = RaycastParams.new()
    params.RespectCanCollide = true
    local function supportAt(offset: Vector3): RaycastResult?
        return workspace:Raycast(spot + offset + Vector3.new(0, RAY_HEIGHT, 0), Vector3.new(0, -RAY_DEPTH, 0), params)
    end
    local function describe(hit: RaycastResult?, referenceY: number?): string
        if hit == nil then
            return "instance=aucune ; normale=absente ; écartY=non mesurable"
        end
        return string.format(
            "instance=%s ; normale=(%.3f, %.3f, %.3f) ; Y=%.3f ; écartY=%s",
            hit.Instance:GetFullName(),
            hit.Normal.X,
            hit.Normal.Y,
            hit.Normal.Z,
            hit.Position.Y,
            if referenceY then string.format("%.3f", hit.Position.Y - referenceY) else "non mesurable"
        )
    end
    local support = supportAt(Vector3.zero)
    if support == nil or not support.Instance:IsDescendantOf(crib) or support.Normal.Y < MIN_SUPPORT_NORMAL then
        return nil, "placement refusé : appui de référence sous Target ; " .. describe(support, nil)
    end
    local referenceY = support.Position.Y
    local toy = template:Clone()
    local box: CFrame
    local size: Vector3
    if toy:IsA("Model") then
        toy:ScaleTo(toy:GetScale() * SCALE)
        box, size = toy:GetBoundingBox()
    elseif toy:IsA("BasePart") then
        toy.Size *= SCALE
        box, size = toy.CFrame, toy.Size
    else
        toy:Destroy()
        return nil, "modèle invalide : Pacifier doit être un Model ou une BasePart"
    end
    local roomZones: { BasePart } = {}
    for _, zone in CollectionService:GetTagged("GiantRoom") do
        if zone:IsA("BasePart") and room and zone:IsDescendantOf(room) then
            table.insert(roomZones, zone)
        end
    end
    local function inRoom(position: Vector3): boolean
        for _, zone in roomZones do
            if Zone.Contains(zone, position) then
                return true
            end
        end
        return false
    end
    local forbidden: { BasePart } = {}
    for _, tag in { "Base", "HideZone", "BaseDoor", "InteriorZone", "KitchenDoor" } do
        for _, zone in CollectionService:GetTagged(tag) do
            if zone:IsA("BasePart") and zone:IsDescendantOf(workspace) then
                table.insert(forbidden, zone)
            end
        end
    end
    local overlap = OverlapParams.new()
    overlap.RespectCanCollide = true
    -- Le berceau monobloc a une boîte immense : sa géométrie est testée par les rayons ci-dessous.
    -- Les autres objets restent refusés par leur volume, y compris les joueurs et les jouets.
    overlap.FilterDescendantsInstances = { crib }
    local function validate(offset: Vector3, facing: CFrame): (CFrame?, number, string)
        local notes: { string } = {}
        local failures = 0
        local low, high = math.huge, -math.huge
        -- Ne pas s'arrêter au premier coin : conserver aussi les mesures des huit autres sondes.
        for _, x in { -1, 0, 1 } do
            for _, z in { -1, 0, 1 } do
                local probe = offset + facing:VectorToWorldSpace(Vector3.new(x * size.X / 2, 0, z * size.Z / 2))
                local hit = supportAt(probe)
                local valid = hit ~= nil
                    and hit.Instance:IsDescendantOf(crib)
                    and hit.Normal.Y >= MIN_SUPPORT_NORMAL
                    and math.abs(hit.Position.Y - referenceY) <= MAX_SUPPORT_STEP
                table.insert(
                    notes,
                    string.format(
                        "sonde(%d,%d) %s ; %s",
                        x,
                        z,
                        if valid then "appui" else "refus",
                        describe(hit, referenceY)
                    )
                )
                if valid and hit then
                    low = math.min(low, hit.Position.Y)
                    high = math.max(high, hit.Position.Y)
                else
                    failures += 1
                end
            end
        end
        local measurements = table.concat(notes, " | ")
        if failures > 0 then
            return nil, failures, measurements
        end
        if high - low > MAX_SUPPORT_STEP then
            return nil, 1, string.format("dispersionY=%.3f ; %s", high - low, measurements)
        end
        -- Le point le plus haut évite d'enfoncer un coin ; le jeu maximal reste borné à 0,25 stud.
        local center = CFrame.new(spot.X + offset.X, high + size.Y / 2, spot.Z + offset.Z) * facing
        for _, x in { -1, 1 } do
            for _, y in { -1, 1 } do
                for _, z in { -1, 1 } do
                    if not inRoom(center:PointToWorldSpace(Vector3.new(x * size.X, y * size.Y, z * size.Z) / 2)) then
                        return nil, 1, "empreinte hors de GiantRoom ; " .. measurements
                    end
                end
            end
        end
        local radius = Vector2.new(size.X, size.Z).Magnitude / 2
        for _, zone in forbidden do
            local p = zone.CFrame:PointToObjectSpace(center.Position)
            local half = zone.Size / 2 + Vector3.new(radius + 3, size.Y / 2 + 3, radius + 3)
            if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
                return nil, 1, "volume interdit=" .. zone:GetFullName() .. " ; " .. measurements
            end
        end
        local obstacles = workspace:GetPartBoundsInBox(center + Vector3.new(0, 0.05, 0), size, overlap)
        if #obstacles > 0 then
            return nil, 1, "obstacle=" .. obstacles[1]:GetFullName() .. " ; " .. measurements
        end
        -- Traverser le volume dans les deux sens : barreaux et reliefs du maillage ne sont pas ignorés.
        for _, height in { 0.05, size.Y / 2, size.Y } do
            for _, fraction in { -1, -0.5, 0, 0.5, 1 } do
                for _, alongX in { true, false } do
                    local a = if alongX
                        then Vector3.new(-size.X / 2, height - size.Y / 2, fraction * size.Z / 2)
                        else Vector3.new(fraction * size.X / 2, height - size.Y / 2, -size.Z / 2)
                    local delta = if alongX then Vector3.new(size.X, 0, 0) else Vector3.new(0, 0, size.Z)
                    local origin = center:PointToWorldSpace(a)
                    local direction = center:VectorToWorldSpace(delta)
                    local hit = workspace:Raycast(origin, direction, params)
                        or workspace:Raycast(origin + direction, -direction, params)
                    if hit then
                        return nil, 1, "dégagement refusé ; " .. describe(hit, high) .. " ; " .. measurements
                    end
                end
            end
        end
        return center, 0, measurements
    end
    -- Même ensemble de poses à chaque apparition ; seul l'ordre des lacets varie.
    -- Un tirage malchanceux ne peut plus éliminer une orientation admissible.
    local firstYaw = random:NextInteger(0, SEARCH_YAWS - 1)
    local center: CFrame? = nil
    local bestFailures = math.huge
    local bestRank = math.huge
    local bestDiagnostic = ""
    local attempts = 0
    for ring = 0, SEARCH_RINGS do
        for x = -ring, ring do
            for z = -ring, ring do
                if math.max(math.abs(x), math.abs(z)) ~= ring then
                    continue
                end
                local offset = Vector3.new(x * SEARCH_STEP, 0, z * SEARCH_STEP)
                for yaw = 0, SEARCH_YAWS - 1 do
                    local yawIndex = (firstYaw + yaw) % SEARCH_YAWS
                    local angle = yawIndex * math.pi * 2 / SEARCH_YAWS
                    local candidate, failures, diagnostic = validate(offset, CFrame.Angles(0, angle, 0))
                    attempts += 1
                    if candidate then
                        center = candidate
                        break
                    end
                    -- Diagnostic stable en cas d'échec identique, malgré l'ordre aléatoire des lacets.
                    local rank = (x * x + z * z) * 1000
                        + ((x + SEARCH_RINGS) * 7 + z + SEARCH_RINGS) * SEARCH_YAWS
                        + yawIndex
                    if failures < bestFailures or (failures == bestFailures and rank < bestRank) then
                        bestFailures = failures
                        bestRank = rank
                        bestDiagnostic = string.format(
                            "offset=(%.1f, %.1f), lacet=%.1f° ; %s",
                            offset.X,
                            offset.Z,
                            math.deg(angle),
                            diagnostic
                        )
                    end
                end
                if center then
                    break
                end
            end
            if center then
                break
            end
        end
        if center then
            break
        end
    end
    if center == nil then
        toy:Destroy()
        return nil,
            string.format("placement refusé après %d poses ; meilleur candidat : %s", attempts, bestDiagnostic)
    end
    if toy:IsA("Model") then
        toy:PivotTo(center * box:ToObjectSpace(toy:GetPivot()))
    elseif toy:IsA("BasePart") then
        toy.CFrame = center
    end
    local function anchor(part: BasePart): ()
        part.Anchored = true
        part.CanCollide = true
        part.CanQuery = true
        part.AssemblyLinearVelocity = Vector3.zero
        part.AssemblyAngularVelocity = Vector3.zero
    end
    if toy:IsA("BasePart") then
        anchor(toy)
    end
    for _, descendant in toy:GetDescendants() do
        if descendant:IsA("BasePart") then
            anchor(descendant)
        end
    end
    toy.Name = TOY_ID
    toy:SetAttribute("ToyId", TOY_ID)
    toy:SetAttribute("Temporaire", true)
    toy:SetAttribute(MISSION_ATTRIBUTE, true)
    toy.Parent = live
    return toy, nil
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
    local toy, failure = createOnMattress(spot)
    spawnInProgress = false
    if toy == nil then
        -- Une occupation temporaire du matelas ne doit pas supprimer la mission pour toute la session.
        reportSpawnFailure((failure or "échec d'apparition sans diagnostic") .. " ; nouvel essai dans 20 s")
        scheduleRespawn()
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
    -- La prise n'est publiée qu'après la pose, l'identité de mission et les écouteurs de son cycle.
    CollectionService:AddTag(toy, "Toy")
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
