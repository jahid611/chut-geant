--!strict

--[[
    CosmeticService
    Applique les cosmetiques equipes (attributs Equipped_<slot> poses par ShopService) et gere les danses.

    - trail   : trainee accrochee au bassin (nom TraineeCosmetique, distinct de TraineeFurie), remise a chaque
                reapparition et retiree quand on deséquipe. Etoiles : trainee doree + etincelles.
    - outline : contour (Highlight « ContourCosmetique ») sur chaque coffre du joueur, jouets compris
                (workspace.BaseChests.Base_<UserId>/Coffre*). Un Highlight par coffre, pas par jouet : Roblox n'en
                affiche que 31 a la fois. Arc-en-ciel : attribut Rainbow, la couleur tourne cote client
                (CosmeticController).
    - Dance (remote) : (danceId) si le joueur possede cette danse (Owned_<id>), attribut Dancing = id pendant
                DANCE_SECONDS ; « stop » l'arrete (le client l'envoie quand le joueur bouge).
    - decor   : chaque decor possede (articles slot "decor", attribut Owned_<id>) est pose au sol dans la base, de
                part et d'autre de la rangee de coffres (dossier Decors dans workspace.BaseChests.Base_<UserId> : il
                disparait avec les coffres au depart du joueur ou apres une Nuit, et il est repose ensuite).
                Modeles : ServerStorage.CosmeticModels.<id> ; rien n'est pose tant que le modele manque.
    - skin    : accessoire porte sur la tete (Equipped_skin, ex. SkinBunny = oreilles de lapin), soude a la tete,
                remis a chaque reapparition.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TRAIL_NAME = "TraineeCosmetique"
local SPARKLES_NAME = "EtincellesCosmetique"
local TOP_NAME = "CosmetiqueHaut"
local BOTTOM_NAME = "CosmetiqueBas"
local OUTLINE_NAME = "ContourCosmetique"
local DANCE_SECONDS = 4
local DANCE_COOLDOWN = 0.5
local DECOR_FOLDER = "Decors"
local DECOR_GAP = 4
-- Decors sur lesquels on peut monter (les autres ne bloquent pas les joueurs).
local SOLID_DECORS: { [string]: boolean } = { DecorBeanbag = true, DecorTent = true }
local SKIN_NAME = "AccessoireCosmetique"
local LAMP_NAME = "LampeFrontale"

type TrailStyle = {
    color: ColorSequence,
    lifetime: number,
    emission: number,
    sparkles: boolean,
}

local TRAILS: { [string]: TrailStyle } = {
    TrailRainbow = {
        color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
            ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 180, 70)),
            ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 90)),
            ColorSequenceKeypoint.new(0.6, Color3.fromRGB(100, 230, 120)),
            ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 160, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 110, 255)),
        }),
        lifetime = 0.6,
        emission = 0.4,
        sparkles = false,
    },
    TrailStars = {
        color = ColorSequence.new(Color3.fromRGB(255, 236, 140), Color3.fromRGB(255, 255, 255)),
        lifetime = 0.45,
        emission = 0.7,
        sparkles = true,
    },
    TrailHearts = {
        color = ColorSequence.new(Color3.fromRGB(255, 110, 170), Color3.fromRGB(255, 190, 220)),
        lifetime = 0.55,
        emission = 0.5,
        sparkles = false,
    },
    -- exclusive : mission de la tetine du bebe (PacifierMissionService)
    TrailPacifier = {
        color = ColorSequence.new(Color3.fromRGB(255, 205, 80), Color3.fromRGB(255, 150, 200)),
        lifetime = 0.6,
        emission = 0.8,
        sparkles = true,
    },
}

local OUTLINES: { [string]: Color3 } = {
    OutlineGold = Color3.fromRGB(255, 200, 60),
    OutlineRainbow = Color3.fromRGB(255, 120, 200),
}

local CosmeticService = {}

local lastDance: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    return if root and root:IsA("BasePart") then root else nil
end

local function clearTrail(root: BasePart): ()
    for _, name in { TRAIL_NAME, SPARKLES_NAME, TOP_NAME, BOTTOM_NAME } do
        local existing = root:FindFirstChild(name)
        if existing then
            existing:Destroy()
        end
    end
end

local function applyTrail(player: Player): ()
    local root = rootOf(player)
    if root == nil then
        return
    end
    clearTrail(root)
    local equipped = player:GetAttribute("Equipped_trail")
    local style: TrailStyle? = if typeof(equipped) == "string" then TRAILS[equipped] else nil
    if style == nil then
        return
    end
    local top = Instance.new("Attachment")
    top.Name = TOP_NAME
    top.Position = Vector3.new(0, 0.9, 0)
    top.Parent = root
    local bottom = Instance.new("Attachment")
    bottom.Name = BOTTOM_NAME
    bottom.Position = Vector3.new(0, -0.9, 0)
    bottom.Parent = root
    local trail = Instance.new("Trail")
    trail.Name = TRAIL_NAME
    trail.Attachment0 = top
    trail.Attachment1 = bottom
    trail.Color = style.color
    trail.Lifetime = style.lifetime
    trail.LightEmission = style.emission
    trail.Transparency = NumberSequence.new(0.2, 1)
    trail.MinLength = 0.2
    trail.Parent = root
    if style.sparkles then
        local sparkles = Instance.new("ParticleEmitter")
        sparkles.Name = SPARKLES_NAME
        -- texture livree avec Roblox (pas d'identifiant a televerser)
        sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
        sparkles.LightEmission = 1
        sparkles.Size = NumberSequence.new(0.6, 0)
        sparkles.Lifetime = NumberRange.new(0.4, 0.8)
        sparkles.Rate = 18
        sparkles.Speed = NumberRange.new(0.5, 2)
        sparkles.SpreadAngle = Vector2.new(180, 180)
        sparkles.Parent = bottom
    end
end

-- Contour de chaque coffre du joueur selon Equipped_outline.
local function applyOutline(player: Player): ()
    local root = workspace:FindFirstChild("BaseChests")
    local folder = if root then root:FindFirstChild("Base_" .. player.UserId) else nil
    if folder == nil then
        return
    end
    local equipped = player:GetAttribute("Equipped_outline")
    local color: Color3? = if typeof(equipped) == "string" then OUTLINES[equipped] else nil
    for _, chest in folder:GetChildren() do
        if not chest:IsA("Model") then
            continue
        end
        local existing = chest:FindFirstChild(OUTLINE_NAME)
        if color == nil then
            if existing then
                existing:Destroy()
            end
            continue
        end
        local highlight: Highlight
        if existing and existing:IsA("Highlight") then
            highlight = existing
        else
            highlight = Instance.new("Highlight")
            highlight.Name = OUTLINE_NAME
            highlight.FillTransparency = 1
            highlight.OutlineTransparency = 0.1
            highlight.DepthMode = Enum.HighlightDepthMode.Occluded
            highlight.Parent = chest
        end
        highlight.OutlineColor = color
        highlight:SetAttribute("Rainbow", if equipped == "OutlineRainbow" then true else nil)
    end
end

local function modelTemplate(id: string): Model?
    local folder = ServerStorage:FindFirstChild("CosmeticModels")
    local model = if folder then folder:FindFirstChild(id) else nil
    return if model and model:IsA("Model") then model else nil
end

local function setPhysics(model: Model, anchored: boolean, collide: boolean): ()
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.Anchored = anchored
            descendant.CanCollide = collide
            descendant.CanQuery = collide
            descendant.CanTouch = false
            descendant.Massless = not anchored
        end
    end
end

-- Pose (ou repose) tous les decors possedes de part et d'autre de la rangee de coffres du joueur.
local function placeDecors(player: Player): ()
    local chestsRoot = workspace:FindFirstChild("BaseChests")
    local folder = if chestsRoot then chestsRoot:FindFirstChild("Base_" .. player.UserId) else nil
    if folder == nil then
        return
    end
    local old = folder:FindFirstChild(DECOR_FOLDER)
    if old then
        old:Destroy()
    end
    local chests: { Model } = {}
    for _, child in folder:GetChildren() do
        if child:IsA("Model") and typeof(child:GetAttribute("Index")) == "number" then
            table.insert(chests, child)
        end
    end
    if #chests == 0 then
        return
    end
    table.sort(chests, function(a, b)
        return (a:GetAttribute("Index") :: number) < (b:GetAttribute("Index") :: number)
    end)
    local firstCFrame, firstSize = chests[1]:GetBoundingBox()
    local lastCFrame, lastSize = chests[#chests]:GetBoundingBox()
    -- axe de la rangee (coffre 1 vers le dernier), sinon le cote droit du premier coffre
    local along = lastCFrame.Position - firstCFrame.Position
    along = Vector3.new(along.X, 0, along.Z)
    if along.Magnitude < 1 then
        along = Vector3.new(firstCFrame.RightVector.X, 0, firstCFrame.RightVector.Z)
    end
    along = if along.Magnitude > 0.01 then along.Unit else Vector3.new(1, 0, 0)
    local facing = Vector3.new(firstCFrame.LookVector.X, 0, firstCFrame.LookVector.Z)
    facing = if facing.Magnitude > 0.01 then facing.Unit else Vector3.new(0, 0, -1)
    local leftCursor = firstCFrame.Position - along * (math.max(firstSize.X, firstSize.Z) / 2 + DECOR_GAP)
    local rightCursor = lastCFrame.Position + along * (math.max(lastSize.X, lastSize.Z) / 2 + DECOR_GAP)

    local holder: Folder? = nil
    local placed = 0
    local ignore: { Instance } = { folder }
    for _, other in Players:GetPlayers() do
        if other.Character then
            table.insert(ignore, other.Character)
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    for _, item in Catalog.All() do
        if item.slot ~= "decor" or player:GetAttribute("Owned_" .. item.id) == nil then
            continue
        end
        local template = modelTemplate(item.id)
        if template == nil then
            continue
        end
        if holder == nil then
            local newHolder = Instance.new("Folder")
            newHolder.Name = DECOR_FOLDER
            newHolder.Parent = folder
            holder = newHolder
        end
        local model = template:Clone()
        model.Name = item.id
        local _, size = model:GetBoundingBox()
        local extent = math.max(size.X, size.Z)
        placed += 1
        local center: Vector3
        if placed % 2 == 1 then
            center = leftCursor - along * extent / 2
            leftCursor -= along * (extent + DECOR_GAP)
        else
            center = rightCursor + along * extent / 2
            rightCursor += along * (extent + DECOR_GAP)
        end
        local hit = workspace:Raycast(center + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0), params)
        local groundY = if hit then hit.Position.Y else firstCFrame.Position.Y - firstSize.Y / 2
        -- face tournee comme les coffres (vers la piece)
        model:PivotTo(
            CFrame.lookAt(Vector3.new(center.X, groundY, center.Z), Vector3.new(center.X, groundY, center.Z) + facing)
        )
        local box, boxSize = model:GetBoundingBox()
        local bottom = box.Position.Y - boxSize.Y / 2
        model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - bottom, 0))
        setPhysics(model, true, SOLID_DECORS[item.id] == true)
        model.Parent = holder
    end
end

-- Accessoire de tete equipe (Equipped_skin), soude a la tete.
local function applySkin(player: Player): ()
    local character = player.Character
    if character == nil then
        return
    end
    local existing = character:FindFirstChild(SKIN_NAME)
    if existing then
        existing:Destroy()
    end
    local equipped = player:GetAttribute("Equipped_skin")
    local template = if typeof(equipped) == "string" then modelTemplate(equipped) else nil
    local head = character:FindFirstChild("Head")
    if template == nil or head == nil or not head:IsA("BasePart") then
        return
    end
    local model = template:Clone()
    model.Name = SKIN_NAME
    local _, size = model:GetBoundingBox()
    -- largeur ajustee a la tete du personnage
    local width = math.max(size.X, size.Z, 0.1)
    model:ScaleTo(model:GetScale() * (head.Size.X * 1.15 / width))
    local _, scaled = model:GetBoundingBox()
    local anchor = head.CFrame * CFrame.new(0, head.Size.Y / 2 + scaled.Y / 2 - scaled.Y * 0.15, 0)
    local box = model:GetBoundingBox()
    model:PivotTo(anchor * box:ToObjectSpace(model:GetPivot()))
    setPhysics(model, false, false)
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = head
            weld.Part1 = descendant
            weld.Parent = descendant
        end
    end
    model.Parent = character
end

-- Lampe frontale (Equipped_lamp) : faisceau doux devant la tete, un peu incline vers le sol, vu par tout le monde.
local function applyLamp(player: Player): ()
    local character = player.Character
    local head = if character then character:FindFirstChild("Head") else nil
    if head == nil or not head:IsA("BasePart") then
        return
    end
    local existing = head:FindFirstChild(LAMP_NAME)
    if existing then
        existing:Destroy()
    end
    local equipped = player:GetAttribute("Equipped_lamp")
    local item = if typeof(equipped) == "string" then Catalog.Get(equipped) else nil
    if item == nil or item.slot ~= "lamp" then
        return
    end
    local mount = Instance.new("Attachment")
    mount.Name = LAMP_NAME
    mount.CFrame = CFrame.new(0, head.Size.Y * 0.25, -head.Size.Z * 0.5) * CFrame.Angles(math.rad(-12), 0, 0)
    mount.Parent = head
    local beam = Instance.new("SpotLight")
    beam.Name = "Faisceau"
    beam.Face = Enum.NormalId.Front
    beam.Angle = 65
    beam.Range = 34
    beam.Brightness = 2
    beam.Color = Color3.fromRGB(255, 236, 200)
    beam.Shadows = true
    beam.Parent = mount
    local glow = Instance.new("PointLight")
    glow.Name = "Lueur"
    glow.Range = 5
    glow.Brightness = 0.6
    glow.Color = Color3.fromRGB(255, 236, 200)
    glow.Parent = mount
end

local function watchChests(player: Player): ()
    local root = workspace:WaitForChild("BaseChests", 30)
    if root == nil then
        return
    end
    local pending = false
    local function schedulePlace(): ()
        if pending then
            return
        end
        pending = true
        task.delay(0.5, function()
            pending = false
            placeDecors(player)
        end)
    end
    local function watchFolder(folder: Instance): ()
        if folder.Name ~= "Base_" .. player.UserId then
            return
        end
        folder.ChildAdded:Connect(function(child: Instance)
            task.defer(applyOutline, player)
            -- nouveau coffre (achat, Nuit, coffre dore reconstruit) : la rangee change, les decors sont reposes
            if child:IsA("Model") then
                schedulePlace()
            end
        end)
        applyOutline(player)
        schedulePlace()
    end
    for _, item in Catalog.All() do
        if item.slot == "decor" then
            player:GetAttributeChangedSignal("Owned_" .. item.id):Connect(schedulePlace)
        end
    end
    root.ChildAdded:Connect(watchFolder)
    for _, folder in root:GetChildren() do
        watchFolder(folder)
    end
end

local function onDance(player: Player, danceId: any): ()
    if danceId == "stop" then
        player:SetAttribute("Dancing", nil)
        return
    end
    if typeof(danceId) ~= "string" then
        return
    end
    local item = Catalog.Get(danceId)
    if item == nil or item.slot ~= "dance" or player:GetAttribute("Owned_" .. danceId) == nil then
        return
    end
    if player:GetAttribute("CarriedToyId") ~= nil then
        return
    end
    local now = os.clock()
    local last: number? = lastDance[player]
    if last and now - last < DANCE_COOLDOWN then
        return
    end
    lastDance[player] = now
    player:SetAttribute("Dancing", danceId)
    task.delay(DANCE_SECONDS, function()
        if lastDance[player] == now and player:GetAttribute("Dancing") == danceId then
            player:SetAttribute("Dancing", nil)
        end
    end)
end

function CosmeticService:Init(): () end

function CosmeticService:Start(): ()
    local dance = Remotes.Get("Dance") :: RemoteEvent
    dance.OnServerEvent:Connect(onDance)

    local function onPlayer(player: Player): ()
        player.CharacterAdded:Connect(function(character: Model)
            character:WaitForChild("HumanoidRootPart", 5)
            player:SetAttribute("Dancing", nil)
            applyTrail(player)
            character:WaitForChild("Head", 5)
            applySkin(player)
            applyLamp(player)
        end)
        player:GetAttributeChangedSignal("Equipped_lamp"):Connect(function()
            applyLamp(player)
        end)
        player:GetAttributeChangedSignal("Equipped_trail"):Connect(function()
            applyTrail(player)
        end)
        player:GetAttributeChangedSignal("Equipped_skin"):Connect(function()
            applySkin(player)
        end)
        player:GetAttributeChangedSignal("Equipped_outline"):Connect(function()
            applyOutline(player)
        end)
        player:GetAttributeChangedSignal("CarriedToyId"):Connect(function()
            if player:GetAttribute("CarriedToyId") ~= nil then
                player:SetAttribute("Dancing", nil)
            end
        end)
        if player.Character then
            applyTrail(player)
            applySkin(player)
            applyLamp(player)
        end
        task.spawn(watchChests, player)
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        onPlayer(player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        lastDance[player] = nil
    end)
end

return CosmeticService
