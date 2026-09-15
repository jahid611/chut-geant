--!strict

--[[
    EventService
    Les mini-jeux aleatoires qui mettent la pression (demande utilisateur : « rajoute de la difficulte »).

    - SurpriseWake : le bebe gigote (Tuning.SURPRISE_WARN_SECONDS) puis se reveille sans que la jauge soit pleine.
    - ShadowRun    : « Vite, dans l'ombre ! » compte a rebours de Tuning.SHADOW_COUNTDOWN secondes ; les zones
                     d'ombre (tag ShadowZone, attribut Radius) s'affichent au sol ; a zero le bebe regarde : tous
                     les joueurs de la chambre hors de l'ombre sont attrapes.
    - MomComing    : « Maman arrive ! » des pas dans l'escalier pendant Tuning.MOM_WARN_SECONDS, puis la porte
                     (tag MomDoor) s'entrouvre avec la lumiere du couloir ; pendant Tuning.MOM_LOOK_SECONDS, les
                     joueurs de la chambre hors de l'ombre ou d'une cachette (HideZone) sont attrapes.
    - Jouet piege  : CarryService.TrapExploded -> le bebe se reveille aussitot.

    Nouveaux evenements (nuit du 15-16/09), tires au hasard avec des poids (les mauvais plus frequents que les bons),
    jamais deux fois le meme de suite :
    - Storm       : orage 25 s ; avant chaque eclair un grondement (phase "rumble", 1 s), puis l'eclair ("flash") :
                    les joueurs de la chambre hors ombre/cachette sont vus et attrapes.
    - MusicBox    : 15 s de berceuse, le bruit ne compte plus (NoiseService x0) : fenetre de vol libre.
    - ToyRain     : l'etagere eternue, 6 a 10 jouets temporaires tombent dans la chambre, dont 1 dore.
    - Nightmare   : 20 s de cauchemar, le bruit compte double.
    - GoldenToy   : un jouet legendaire dore tombe quelque part ; le premier qui le ramene gagne GOLDEN_BONUS.
    - PowerOutage : 20 s de panne de veilleuse, noir cote client, le bebe entend mieux (x1,5).
    - DadSnores   : 20 s de ronflements de papa qui couvrent le bruit (x0,4).
    - HouseCat    : si ServerStorage.DecorModels.HouseCat existe, un chat traverse la chambre ; s'il frole un
                    joueur : miaulement (bruit) et le joueur lache son jouet.
    - BabyChest   : le coffre a jouets de la chambre (workspace.Chambre, modele ToyChest) s'ouvre CHEST_SECONDS :
                    couvercle qui pivote s'il existe (piece nommee Lid/Couvercle), lumiere doree et etincelles, un
                    jouet legendaire temporaire apparait dedans ; tout le serveur court.
    Phases RoomEvent : "warn" / "start" / "end" (+ "rumble", "flash", "won", "meow", "taken").

    Un seul evenement a la fois, et seulement quand le bebe dort. Les clients recoivent RoomEvent pour
    les bandeaux, les sons et l'affichage des zones.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Tuning"))
local Zone = require(Shared:WaitForChild("Zone"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CarryService = require(script.Parent:WaitForChild("CarryService"))
local GiantService = require(script.Parent:WaitForChild("GiantService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local SHADOW_TAG = "ShadowZone"
local HIDE_TAG = "HideZone"
local DOOR_TAG = "MomDoor"
local DOOR_OPEN_DEGREES = 70

local EventService = {}

-- (kind: string, caught: { [Player]: boolean }, participants: { Player }) fin d'un mini-jeu ou l'on peut etre vu
-- (ShadowRun, MomComing) : participants = joueurs de la chambre au moment du regard. LevelService donne de l'XP a
-- ceux qui n'ont pas ete attrapes.
local eventFinished = Instance.new("BindableEvent")
EventService.EventFinished = eventFinished.Event

local random = Random.new()
local running = false

local function playersInRoom(): { Player }
    local list: { Player } = {}
    for _, player in Players:GetPlayers() do
        local character = player.Character
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        if root and root:IsA("BasePart") and NoiseService:IsInRoom(root.Position) then
            table.insert(list, player)
        end
    end
    return list
end

local function announce(kind: string, phase: string, seconds: number): ()
    local remote = Remotes.Get("RoomEvent") :: RemoteEvent
    remote:FireAllClients(kind, phase, workspace:GetServerTimeNow() + seconds)
end

local function inWorkspace(instance: Instance): boolean
    return instance:IsDescendantOf(workspace)
end

-- Dans une zone d'ombre (disque horizontal) ou une cachette (volume) ?
function EventService:IsHidden(position: Vector3, includeHideZones: boolean): boolean
    for _, zone in CollectionService:GetTagged(SHADOW_TAG) do
        if zone:IsA("BasePart") and inWorkspace(zone) then
            local radius = zone:GetAttribute("Radius")
            local r = if typeof(radius) == "number" then radius else zone.Size.Z / 2
            local flat = Vector3.new(position.X - zone.Position.X, 0, position.Z - zone.Position.Z)
            if flat.Magnitude <= r and math.abs(position.Y - zone.Position.Y) < 30 then
                return true
            end
        end
    end
    if includeHideZones then
        for _, zone in CollectionService:GetTagged(HIDE_TAG) do
            if zone:IsA("BasePart") and inWorkspace(zone) and Zone.Contains(zone, position) then
                return true
            end
        end
    end
    return false
end

-- Eclaire par la lumiere qui entre par la porte ? Rayon vers la source (Tuning.MOM_LIGHT_DIRECTION) : s'il sort sans
-- toucher de piece qui fait de l'ombre, le joueur est dans la lumiere. Les pieces sans ombre portee (couloir,
-- volumes invisibles), les personnages et les jouets portes sont traverses : on est cache seulement derriere ce qui
-- dessine vraiment une ombre au sol (meubles, porte, la maman elle-meme).
function EventService:IsLitThroughDoor(position: Vector3): boolean
    local ignore: { Instance } = {}
    for _, other in Players:GetPlayers() do
        if other.Character then
            table.insert(ignore, other.Character)
        end
    end
    local live = workspace:FindFirstChild("ToysLive")
    if live then
        for _, toy in live:GetChildren() do
            if toy:GetAttribute("CarrierUserId") ~= nil then
                table.insert(ignore, toy)
            end
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local direction = Tuning.MOM_LIGHT_DIRECTION.Unit * 2500
    for _ = 1, 16 do
        params.FilterDescendantsInstances = ignore
        local hit = workspace:Raycast(position, direction, params)
        if hit == nil then
            return true
        end
        local part = hit.Instance
        if part:IsA("BasePart") and part.CastShadow and part.Transparency < 0.9 then
            return false
        end
        table.insert(ignore, part)
    end
    return false
end

--[[
    Oreille fine (amelioration, 2 niveaux) : avant l'alerte d'un evenement, les joueurs qui l'ont recoivent un indice
    (RoomEvent phase "hint") Abilities.KEEN_EAR_LEAD[niveau] secondes avant les autres. L'alerte normale attend
    donc la plus grande avance parmi les joueurs presents (aucune attente si personne ne l'a).
]]
local function keenEarHint(kind: string): ()
    local leads: { [Player]: number } = {}
    local longest = 0
    for _, player in Players:GetPlayers() do
        local level = Abilities.Level(player, "KeenEar")
        local lead = Abilities.KEEN_EAR_LEAD[math.min(level, #Abilities.KEEN_EAR_LEAD)]
        if level > 0 and lead then
            leads[player] = lead
            longest = math.max(longest, lead)
        end
    end
    if longest <= 0 then
        return
    end
    local remote = Remotes.Get("RoomEvent") :: RemoteEvent
    local alertAt = workspace:GetServerTimeNow() + longest
    for player, lead in leads do
        task.delay(longest - lead, function()
            if player.Parent then
                remote:FireClient(player, kind, "hint", alertAt)
            end
        end)
    end
    task.wait(longest)
end

local function surpriseWake(): ()
    keenEarHint("SurpriseWake")
    announce("SurpriseWake", "warn", Tuning.SURPRISE_WARN_SECONDS)
    task.wait(Tuning.SURPRISE_WARN_SECONDS)
    -- fin de l'alerte : sans elle, le bandeau « Hmm ?.. » restait affiche avec « -0 » (retour utilisateur)
    announce("SurpriseWake", "end", 0)
    GiantService:Wake()
end

local function shadowRun(): ()
    announce("ShadowRun", "warn", Tuning.SHADOW_COUNTDOWN)
    task.wait(Tuning.SHADOW_COUNTDOWN)
    announce("ShadowRun", "open", Tuning.SHADOW_GLANCE_SECONDS)
    -- sans regard (bebe deja reveille), personne n'a vraiment survecu : pas d'XP
    local watched = GiantService:GetState() == "Sleeping"
    local participants = playersInRoom()
    local caught: { [Player]: boolean } = {}
    GiantService:Glance(Tuning.SHADOW_GLANCE_SECONDS, function(player: Player, position: Vector3): boolean
        local safe = EventService:IsHidden(position, true)
        if not safe then
            caught[player] = true
        end
        return safe
    end)
    task.wait(Tuning.SHADOW_GLANCE_SECONDS)
    announce("ShadowRun", "end", 0)
    if watched then
        eventFinished:Fire("ShadowRun", caught, participants)
    end
end

-- Deplace un modele ancre en douceur (PivotTo pilote par une valeur tweenee).
local function tweenPivot(model: Model, goal: CFrame, seconds: number): ()
    local driver = Instance.new("CFrameValue")
    driver.Value = model:GetPivot()
    driver.Changed:Connect(function(value: CFrame)
        model:PivotTo(value)
    end)
    local tween = TweenService:Create(driver, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Value = goal })
    tween.Completed:Connect(function()
        driver:Destroy()
    end)
    tween:Play()
end

-- Les modeles « Maman » poses dans le modele de chaque porte (recette build-chambre, attributs PoseVisible et
-- PoseCachee). Avant, la porte s'ouvrait sur un couloir vide (retour utilisateur « y a rien ni mere ni rien »).
local function moms(): { Model }
    local found: { Model } = {}
    for _, hinge in CollectionService:GetTagged(DOOR_TAG) do
        local model = hinge.Parent
        local mom = if model and inWorkspace(hinge) then model:FindFirstChild("Maman") else nil
        if mom and mom:IsA("Model") then
            table.insert(found, mom)
        end
    end
    return found
end

-- La maman glisse depuis le cote du couloir jusque devant la porte ouverte (ou repart), lampe du telephone allumee.
local function moveMom(show: boolean, seconds: number): ()
    for _, mom in moms() do
        local goal = mom:GetAttribute(if show then "PoseVisible" else "PoseCachee")
        if typeof(goal) ~= "CFrame" then
            continue
        end
        local lamp = mom:FindFirstChild("LampeMaman")
        if lamp then
            for _, l in lamp:GetDescendants() do
                if l:IsA("Light") then
                    l.Enabled = show
                end
            end
        end
        tweenPivot(mom, goal, seconds)
    end
end

-- Pendant qu'elle regarde, le faisceau de la lampe balaie la chambre de gauche a droite.
local function sweepMomLamp(seconds: number): ()
    for _, mom in moms() do
        local lamp = mom:FindFirstChild("LampeMaman")
        if lamp == nil or not lamp:IsA("BasePart") then
            continue
        end
        local base = lamp.CFrame
        task.spawn(function()
            local started = os.clock()
            while os.clock() - started < seconds and lamp.Parent do
                local t = os.clock() - started
                lamp.CFrame = base * CFrame.Angles(0, math.sin(t * 2.2) * 0.45, 0)
                task.wait()
            end
            lamp.CFrame = base
        end)
    end
end

-- Tourne la porte (tous les enfants du modele sauf la lumiere) autour de sa charniere.
local function swingDoor(open: boolean, seconds: number): ()
    for _, hinge in CollectionService:GetTagged(DOOR_TAG) do
        if not hinge:IsA("BasePart") or not inWorkspace(hinge) then
            continue
        end
        local model = hinge.Parent
        if model == nil then
            continue
        end
        local light = model:FindFirstChild("LumiereCouloir")
        if light then
            for _, l in light:GetDescendants() do
                if l:IsA("Light") then
                    l.Enabled = open
                end
            end
        end
        local leaf = model:FindFirstChild("Battant")
        if leaf and leaf:IsA("Model") then
            local closed = leaf:GetAttribute("ClosedPivot")
            if typeof(closed) ~= "CFrame" then
                closed = leaf:GetPivot()
                leaf:SetAttribute("ClosedPivot", closed)
            end
            local hingeCF = hinge.CFrame
            local offset = hingeCF:ToObjectSpace(closed :: CFrame)
            local goal = if open
                then hingeCF * CFrame.Angles(0, math.rad(DOOR_OPEN_DEGREES), 0) * offset
                else closed :: CFrame
            tweenPivot(leaf, goal, seconds)
        end
    end
end

local function momComing(): ()
    keenEarHint("MomComing")
    announce("MomComing", "warn", Tuning.MOM_WARN_SECONDS)
    task.wait(Tuning.MOM_WARN_SECONDS)
    announce("MomComing", "open", Tuning.MOM_LOOK_SECONDS)
    local participants = playersInRoom()
    swingDoor(true, 1.2)
    moveMom(true, 0.8)
    task.wait(0.8)
    sweepMomLamp(math.max(Tuning.MOM_LOOK_SECONDS - 0.8, 0))
    -- Tant qu'elle regarde, tout joueur de la chambre dans la lumiere de la porte (hors cachette) est attrape.
    task.wait(Tuning.MOM_CATCH_GRACE)
    local caught: { [Player]: boolean } = {}
    local stopAt = os.clock() + math.max(Tuning.MOM_LOOK_SECONDS - 0.8 - Tuning.MOM_CATCH_GRACE, 0)
    repeat
        for _, player in Players:GetPlayers() do
            local character = player.Character
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            -- Cape d'ombre : maman ne le voit pas (et il reste repérable une fois la cape finie).
            if
                caught[player]
                or root == nil
                or not root:IsA("BasePart")
                or Abilities.IsActive(player, "ShadowCape")
            then
                continue
            end
            local position = root.Position
            if not NoiseService:IsInRoom(position) or EventService:IsHidden(position, true) then
                continue
            end
            if EventService:IsLitThroughDoor(position + Vector3.new(0, 1, 0)) then
                caught[player] = true
                GiantService:Catch(player, "mom")
            end
        end
        task.wait(0.2)
    until os.clock() >= stopAt
    moveMom(false, 0.8)
    task.wait(0.6)
    swingDoor(false, 1)
    announce("MomComing", "end", 0)
    eventFinished:Fire("MomComing", caught, participants)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Nouveaux evenements (nuit du 15-16/09)
-- ---------------------------------------------------------------------------------------------------------------

local STORM_SECONDS = 25
local MUSIC_SECONDS = 15
local NIGHTMARE_SECONDS = 20
local OUTAGE_SECONDS = 20
local SNORE_SECONDS = 20
-- Jouet dore geant : il disparait apres ce temps s'il n'est pas porte ; l'evenement attend au plus GOLDEN_MAX_WAIT
-- (un legendaire se porte a plusieurs, seul c'est tres lent). Bonus affiche aussi cote client (EventController).
local GOLDEN_SECONDS = 90
local GOLDEN_MAX_WAIT = 240
local GOLDEN_BONUS = 25000
local RAIN_LIFETIME = 60
local CAT_SECONDS = 14
local CAT_NOISE = 20
-- Coffre du bebe : ouvert ce temps, le jouet legendaire disparait a la fermeture s'il n'est pas porte.
local CHEST_SECONDS = 30
local CHEST_LID_DEGREES = 75
local GOLD_LIGHT = Color3.fromRGB(255, 205, 90)

local function rootOf(player: Player): BasePart?
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    return if root and root:IsA("BasePart") then root else nil
end

local function roomPart(): BasePart?
    for _, room in CollectionService:GetTagged("GiantRoom") do
        if room:IsA("BasePart") and inWorkspace(room) then
            return room
        end
    end
    return nil
end

-- Point du sol libre au hasard dans la chambre : rayon depuis sous le plafond, rejete s'il touche le haut d'un meuble
-- (le sol de la chambre est a y 0, tapis compris sous 10 studs).
local function randomFloorPoint(): Vector3?
    local room = roomPart()
    if room == nil then
        return nil
    end
    local ignore: { Instance } = { room }
    for _, other in Players:GetPlayers() do
        if other.Character then
            table.insert(ignore, other.Character)
        end
    end
    local live = workspace:FindFirstChild("ToysLive")
    if live then
        table.insert(ignore, live)
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    for _ = 1, 16 do
        local local_ =
            Vector3.new(random:NextNumber(-0.42, 0.42) * room.Size.X, 0, random:NextNumber(-0.42, 0.42) * room.Size.Z)
        local point = room.CFrame:PointToWorldSpace(local_)
        local hit = workspace:Raycast(Vector3.new(point.X, 330, point.Z), Vector3.new(0, -400, 0), params)
        if hit and hit.Position.Y < 10 then
            return hit.Position
        end
    end
    return nil
end

-- Evenement « bruit modifie » : annonce, multiplicateur de bruit pendant seconds, fin.
local function timedNoise(kind: string, factor: number, seconds: number): ()
    announce(kind, "start", seconds)
    NoiseService:SetGainMultiplier(kind, factor)
    local ok, err = pcall(function()
        task.wait(seconds)
    end)
    NoiseService:SetGainMultiplier(kind, nil)
    if not ok then
        warn("[EventService] " .. kind .. " : " .. tostring(err))
    end
    announce(kind, "end", 0)
end

local function storm(): ()
    local participants = playersInRoom()
    local caught: { [Player]: boolean } = {}
    announce("Storm", "warn", 3)
    task.wait(3)
    local stopAt = os.clock() + STORM_SECONDS
    while os.clock() < stopAt do
        announce("Storm", "rumble", 1)
        task.wait(1)
        announce("Storm", "flash", 0)
        for _, player in playersInRoom() do
            local root = rootOf(player)
            if
                root
                and not Abilities.IsActive(player, "ShadowCape")
                and not EventService:IsHidden(root.Position, true)
            then
                caught[player] = true
                GiantService:Catch(player, "seen")
            end
        end
        task.wait(random:NextNumber(3, 5.5))
    end
    announce("Storm", "end", 0)
    eventFinished:Fire("Storm", caught, participants)
end

local function musicBox(): ()
    timedNoise("MusicBox", 0, MUSIC_SECONDS)
end

local function nightmare(): ()
    timedNoise("Nightmare", 2, NIGHTMARE_SECONDS)
end

local function powerOutage(): ()
    timedNoise("PowerOutage", 1.5, OUTAGE_SECONDS)
end

local function dadSnores(): ()
    timedNoise("DadSnores", 0.4, SNORE_SECONDS)
end

local function toyRain(): ()
    announce("ToyRain", "warn", 1.5)
    task.wait(1.5)
    announce("ToyRain", "start", 0)
    local count = random:NextInteger(6, 10)
    local golden = random:NextInteger(1, count)
    for i = 1, count do
        local point = randomFloorPoint()
        if point then
            ToySpawnService:SpawnTemporary(
                nil,
                point + Vector3.new(0, 60, 0),
                if i == golden then "Gold" else nil,
                RAIN_LIFETIME,
                nil
            )
        end
        task.wait(0.25)
    end
    task.wait(2)
    announce("ToyRain", "end", 0)
end

local function goldenToy(): ()
    local point = randomFloorPoint()
    if point == nil then
        return
    end
    local toy = ToySpawnService:SpawnTemporary(nil, point + Vector3.new(0, 40, 0), "Gold", GOLDEN_SECONDS, "Legendary")
    if toy == nil then
        return
    end
    toy:SetAttribute("EventDore", true)
    local toyId = toy:GetAttribute("ToyId")
    local lastCarrier: number? = nil
    local carrierConnection = toy:GetAttributeChangedSignal("CarrierUserId"):Connect(function()
        local id = toy:GetAttribute("CarrierUserId")
        if typeof(id) == "number" then
            lastCarrier = id
        end
    end)
    local won = false
    -- ToyDeposited part avant la destruction du jouet depose (CarryService : depot, puis release, puis Destroy).
    local depositConnection = BaseService.ToyDeposited:Connect(
        function(player: Player, depositedId: string, mutation: string?)
            if won or depositedId ~= toyId or mutation ~= "Gold" or lastCarrier ~= player.UserId then
                return
            end
            won = true
            BaseService:AddCash(player, GOLDEN_BONUS)
            workspace:SetAttribute("EventGagnant", player.DisplayName)
            announce("GoldenToy", "won", 0)
        end
    )
    announce("GoldenToy", "start", 0)
    local started = os.clock()
    while not won and toy.Parent and os.clock() - started < GOLDEN_MAX_WAIT do
        task.wait(0.5)
    end
    carrierConnection:Disconnect()
    depositConnection:Disconnect()
    if won then
        task.wait(3)
    elseif toy.Parent and toy:GetAttribute("CarrierUserId") == nil then
        toy:Destroy()
    end
    announce("GoldenToy", "end", 0)
end

local function catTemplate(): Model?
    local decor = ServerStorage:FindFirstChild("DecorModels")
    local cat = if decor then decor:FindFirstChild("HouseCat") else nil
    return if cat and cat:IsA("Model") then cat else nil
end

local function houseCat(): ()
    local template = catTemplate()
    local room = roomPart()
    local a, b = randomFloorPoint(), randomFloorPoint()
    if template == nil or room == nil or a == nil or b == nil then
        return
    end
    local first, second = a :: Vector3, b :: Vector3
    local cat = template:Clone()
    cat.Name = "ChatDeLaMaison"
    for _, part in cat:GetDescendants() do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
        end
    end
    local _, size = cat:GetBoundingBox()
    local lift = Vector3.new(0, size.Y / 2, 0)
    local reach = math.max(size.X, size.Z) / 2 + 4
    local left = room.Position.X - room.Size.X * 0.45
    local right = room.Position.X + room.Size.X * 0.45
    local points = { Vector3.new(left, first.Y, first.Z), first, second, Vector3.new(right, second.Y, second.Z) }
    local total = 0
    for i = 1, #points - 1 do
        total += (points[i + 1] - points[i]).Magnitude
    end
    local speed = math.max(total / CAT_SECONDS, 1)
    announce("HouseCat", "start", CAT_SECONDS)
    cat:PivotTo(CFrame.new(points[1] + lift))
    cat.Parent = workspace
    local touched: { [Player]: number } = {}
    local ok, err = pcall(function()
        for i = 1, #points - 1 do
            local from, to = points[i], points[i + 1]
            local distance = (to - from).Magnitude
            if distance < 0.5 then
                continue
            end
            local direction = (to - from).Unit
            local steps = math.max(math.ceil(distance / speed / 0.05), 1)
            for step = 1, steps do
                local position = from:Lerp(to, step / steps) + lift
                cat:PivotTo(CFrame.lookAt(position, position + direction))
                for _, player in playersInRoom() do
                    local root = rootOf(player)
                    local last: number? = touched[player]
                    if
                        root
                        and (root.Position - position).Magnitude < reach
                        and (last == nil or os.clock() - last > 3)
                    then
                        touched[player] = os.clock()
                        CarryService:Drop(player, true)
                        NoiseService:Add(CAT_NOISE)
                        announce("HouseCat", "meow", 0)
                    end
                end
                task.wait(0.05)
            end
        end
    end)
    cat:Destroy()
    if not ok then
        warn("[EventService] HouseCat : " .. tostring(err))
    end
    announce("HouseCat", "end", 0)
end

-- Coffre a jouets du decor de la chambre (build-chambre : Chambre.Decor.ToyChest).
local function roomChest(): Model?
    local chambre = workspace:FindFirstChild("Chambre")
    local chest = if chambre then chambre:FindFirstChild("ToyChest", true) else nil
    return if chest and chest:IsA("Model") then chest else nil
end

-- Couvercle du coffre : une piece ou un modele nomme Lid / Couvercle (le modele actuel peut ne pas en avoir).
local function chestLid(chest: Model): PVInstance?
    for _, child in chest:GetDescendants() do
        local name = string.lower(child.Name)
        if (child:IsA("BasePart") or child:IsA("Model")) and (name:find("lid") or name:find("couvercle")) then
            return child
        end
    end
    return nil
end

-- Pivote le couvercle autour de son arete arriere (celle la plus loin du centre de la chambre) : alpha 0 = ferme,
-- 1 = ouvert. Renvoie une fonction qui applique alpha.
local function lidHinge(lid: PVInstance, chest: Model): (number) -> ()
    local closed = lid:GetPivot()
    local box: CFrame, size: Vector3
    if lid:IsA("Model") then
        box, size = lid:GetBoundingBox()
    else
        local part = lid :: BasePart
        box, size = part.CFrame, part.Size
    end
    local room = roomPart()
    local center = if room then room.Position else chest:GetPivot().Position + chest:GetPivot().LookVector * 10
    local back = box.LookVector * (size.Z / 2)
    local edge = box.Position + back + box.UpVector * (size.Y / 2)
    if (edge - center).Magnitude < (box.Position - back - center).Magnitude then
        back = -back
        edge = box.Position + back + box.UpVector * (size.Y / 2)
    end
    local axis = box.RightVector
    -- sens qui souleve l'avant du couvercle
    local front = box.Position - back
    local sign = 1
    local lifted = (CFrame.fromAxisAngle(axis, math.rad(CHEST_LID_DEGREES)) * (front - edge)).Y
    if lifted < (front - edge).Y then
        sign = -1
    end
    return function(alpha: number)
        local rotation = CFrame.fromAxisAngle(axis, sign * math.rad(CHEST_LID_DEGREES) * alpha)
        local offset = closed.Position - edge
        local newPosition = edge + rotation * offset
        lid:PivotTo(CFrame.new(newPosition) * rotation * closed.Rotation)
    end
end

local function babyChest(): ()
    local chest = roomChest()
    if chest == nil then
        return
    end
    local primary = Zone.PrimaryPart(chest)
    if primary == nil then
        return
    end
    local center, size = chest:GetBoundingBox()
    local top = center.Position + Vector3.new(0, size.Y / 2, 0)

    -- lumiere doree et etincelles au-dessus de la cavite
    local attachment = Instance.new("Attachment")
    attachment.Name = "LumiereCoffreBebe"
    attachment.Parent = primary
    attachment.WorldPosition = top
    local light = Instance.new("PointLight")
    light.Color = GOLD_LIGHT
    light.Brightness = 0
    light.Range = math.clamp(size.Magnitude, 24, 60)
    light.Shadows = false
    light.Parent = attachment
    local sparkles = Instance.new("ParticleEmitter")
    sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sparkles.Color = ColorSequence.new(GOLD_LIGHT, Color3.fromRGB(255, 250, 220))
    sparkles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.6),
        NumberSequenceKeypoint.new(1, 0),
    })
    sparkles.Lifetime = NumberRange.new(1, 1.8)
    sparkles.Speed = NumberRange.new(6, 14)
    sparkles.SpreadAngle = Vector2.new(35, 35)
    sparkles.EmissionDirection = Enum.NormalId.Top
    sparkles.Acceleration = Vector3.new(0, -4, 0)
    sparkles.LightEmission = 1
    sparkles.Rate = 18
    sparkles.Parent = attachment
    TweenService:Create(light, TweenInfo.new(1), { Brightness = 3 }):Play()

    local lid = chestLid(chest)
    local setLid = if lid then lidHinge(lid, chest) else nil
    local driver = Instance.new("NumberValue")
    if setLid then
        driver.Changed:Connect(setLid)
        TweenService:Create(driver, TweenInfo.new(0.8, Enum.EasingStyle.Back), { Value = 1 }):Play()
    end

    local toy = ToySpawnService:SpawnTemporary(nil, top + Vector3.new(0, 4, 0), nil, CHEST_SECONDS, "Legendary")
    local taken = false
    local carrierConnection: RBXScriptConnection? = nil
    if toy then
        toy:SetAttribute("CoffreBebe", true)
        carrierConnection = toy:GetAttributeChangedSignal("CarrierUserId"):Connect(function()
            local id = toy:GetAttribute("CarrierUserId")
            local carrier = if typeof(id) == "number" then Players:GetPlayerByUserId(id) else nil
            if carrier and not taken then
                taken = true
                workspace:SetAttribute("EventGagnant", carrier.DisplayName)
                announce("BabyChest", "taken", 0)
            end
        end)
    end
    announce("BabyChest", "start", CHEST_SECONDS)
    task.wait(CHEST_SECONDS)

    if carrierConnection then
        carrierConnection:Disconnect()
    end
    sparkles.Enabled = false
    TweenService:Create(light, TweenInfo.new(1), { Brightness = 0 }):Play()
    if setLid then
        TweenService:Create(driver, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Value = 0 }):Play()
    end
    announce("BabyChest", "end", 0)
    task.wait(2)
    driver:Destroy()
    if lid and setLid then
        setLid(0)
    end
    attachment:Destroy()
end

type EventDef = { name: string, run: () -> (), weight: number, available: (() -> boolean)? }

-- Poids : les evenements qui mettent la pression reviennent plus souvent que les cadeaux.
local EVENTS: { EventDef } = {
    { name = "SurpriseWake", run = surpriseWake, weight = 3 },
    { name = "ShadowRun", run = shadowRun, weight = 3 },
    { name = "MomComing", run = momComing, weight = 3 },
    { name = "Storm", run = storm, weight = 2 },
    { name = "Nightmare", run = nightmare, weight = 2 },
    { name = "PowerOutage", run = powerOutage, weight = 2 },
    {
        name = "HouseCat",
        run = houseCat,
        weight = 2,
        available = function(): boolean
            return catTemplate() ~= nil
        end,
    },
    { name = "MusicBox", run = musicBox, weight = 1 },
    { name = "ToyRain", run = toyRain, weight = 1 },
    { name = "GoldenToy", run = goldenToy, weight = 1 },
    { name = "DadSnores", run = dadSnores, weight = 1 },
    {
        name = "BabyChest",
        run = babyChest,
        weight = 1,
        available = function(): boolean
            return roomChest() ~= nil
        end,
    },
}

local lastEvent: string? = nil

local function isAvailable(def: EventDef): boolean
    local available = def.available
    return available == nil or available()
end

-- Tirage pondere, jamais le meme evenement deux fois de suite.
local function pickEvent(): EventDef?
    local pool: { EventDef } = {}
    local total = 0
    for _, def in EVENTS do
        if def.name ~= lastEvent and isAvailable(def) then
            table.insert(pool, def)
            total += def.weight
        end
    end
    if total <= 0 then
        return nil
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
    local ok, err = pcall(function()
        def.run()
    end)
    if not ok then
        warn("[EventService] " .. def.name .. " : " .. tostring(err))
    end
end

-- Lance un evenement tout de suite (tests) : "SurpriseWake" | "ShadowRun" | "MomComing" | "Storm" | "MusicBox" |
-- "ToyRain" | "Nightmare" | "GoldenToy" | "PowerOutage" | "DadSnores" | "HouseCat" | "BabyChest".
function EventService:Trigger(kind: string): boolean
    if running then
        return false
    end
    local chosen: EventDef? = nil
    for _, def in EVENTS do
        if def.name == kind and isAvailable(def) then
            chosen = def
        end
    end
    if chosen == nil then
        return false
    end
    running = true
    local def: EventDef = chosen
    task.spawn(function()
        runEvent(def)
        running = false
    end)
    return true
end

function EventService:IsRunning(): boolean
    return running
end

function EventService:Init(): () end

function EventService:Start(): ()
    CarryService.TrapExploded:Connect(function()
        GiantService:Wake(true)
    end)

    task.spawn(function()
        task.wait(Tuning.EVENT_FIRST_DELAY)
        while true do
            local state = GiantService:GetState()
            if not running and state == "Sleeping" and #Players:GetPlayers() > 0 then
                local def = pickEvent()
                if def then
                    running = true
                    runEvent(def)
                    running = false
                end
            end
            task.wait(random:NextNumber(Tuning.EVENT_MIN_GAP, Tuning.EVENT_MAX_GAP))
        end
    end)
end

return EventService
