--!strict

--[[
    ToySpawnService
    Fait apparaitre les jouets sur les points tagues "ToySpawn" de la chambre.

    Modeles : ServerStorage.ToyModels, un enfant par jouet nomme par son id
    (voir Shared/Toys). Un point peut imposer son jouet avec l'attribut ToyId,
    sinon le jouet est tire selon les poids de rarete. Un jouet vole reapparait
    apres Tuning.RESPAWN_SECONDS.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Toys = require(Shared:WaitForChild("Toys"))
local Tuning = require(Shared:WaitForChild("Tuning"))
local Zone = require(Shared:WaitForChild("Zone"))

local WelcomePoints = require(script.Parent.Parent:WaitForChild("WelcomePoints"))

local SPAWN_TAG = "ToySpawn"
local TOY_TAG = "Toy"

local RARITY_COLORS: { [string]: Color3 } = {
    Common = Color3.fromRGB(205, 210, 220),
    Uncommon = Color3.fromRGB(95, 200, 125),
    Rare = Color3.fromRGB(85, 150, 245),
    Epic = Color3.fromRGB(170, 115, 245),
    Legendary = Color3.fromRGB(245, 185, 65),
}

local MUTATION_COLORS: { [string]: Color3 } = {
    Gold = Color3.fromRGB(255, 200, 40),
    Rainbow = Color3.fromRGB(255, 80, 220),
    Cosmic = Color3.fromRGB(120, 70, 255),
}

local ToySpawnService = {}

-- (toy: Instance) un jouet vient d'apparaitre sur un point de la chambre (LivingToyService : jouets vivants).
local spawnedEvent = Instance.new("BindableEvent")
ToySpawnService.Spawned = spawnedEvent.Event

local random = Random.new()
local liveFolder: Folder? = nil
local spawnOf: { [Instance]: BasePart } = {}
local occupied: { [BasePart]: Instance } = {}
local welcomeBase: { [BasePart]: BasePart } = {}
local toyConnections: { [Instance]: RBXScriptConnection } = {}
type Pending = { connection: RBXScriptConnection? }
local pending: { [BasePart]: Pending } = {}
local warnedMissing: { [string]: boolean } = {}
-- Jouets pieges : garde cote serveur seulement, pour que personne ne puisse les reperer avant de les ramasser.
local trapped: { [Instance]: boolean } = {}

-- Pleine lune (MoonService) : > 1 = plus de jouets rares. Sur un point de rarete imposee, chance de monter d'un
-- cran ; sans rarete imposee, poids des raretes Rare et au-dessus multiplies.
local rarityBoost = 1
local RARITY_STEPS: { [string]: string } = {
    Common = "Uncommon",
    Uncommon = "Rare",
    Rare = "Epic",
    Epic = "Legendary",
}

function ToySpawnService:SetRarityBoost(factor: number): ()
    rarityBoost = math.max(factor, 1)
end

local function weightOf(rarity: Toys.Rarity): number
    local weight = Tuning.RARITY_WEIGHTS[rarity] or 0
    if rarity ~= "Common" and rarity ~= "Uncommon" then
        weight *= rarityBoost
    end
    return weight
end

-- Jouets de la bonne piece : ceux de la cuisine (kitchenOnly) n'apparaissent que dans la cuisine, et inversement.
local function poolFor(kitchen: boolean): { Toys.Toy }
    local pool: { Toys.Toy } = {}
    for _, toy in Toys.All() do
        if (toy.kitchenOnly == true) == kitchen then
            table.insert(pool, toy)
        end
    end
    return pool
end

-- Tire un jouet selon les poids de rarete. Si `rarity` est fourni (attribut Rarity du point
-- d'apparition), le tirage se limite aux jouets de cette rarete : plus pres du bebe, plus rare.
-- `kitchen` : point d'apparition de la cuisine (tirage parmi les jouets de la cuisine seulement).
local function pickToyId(rarity: string?, kitchen: boolean?): string?
    if rarity and rarityBoost > 1 then
        local nextRarity: string? = RARITY_STEPS[rarity]
        if nextRarity and random:NextNumber() < math.min((rarityBoost - 1) * 0.35, 0.8) then
            rarity = nextRarity
        end
    end
    local pool = poolFor(kitchen == true)
    if #pool == 0 then
        pool = poolFor(false)
    end
    local candidates: { Toys.Toy } = {}
    for _, toy in pool do
        if rarity == nil or toy.rarity == rarity then
            table.insert(candidates, toy)
        end
    end
    if #candidates == 0 then
        candidates = pool
    end
    local total = 0
    for _, toy in candidates do
        total += weightOf(toy.rarity)
    end
    if total <= 0 then
        return nil
    end
    local roll = random:NextNumber() * total
    for _, toy in candidates do
        roll -= weightOf(toy.rarity)
        if roll <= 0 then
            return toy.id
        end
    end
    return nil
end

local function pickMutation(): string?
    for _, entry in Tuning.MUTATION_CHANCES do
        if random:NextNumber() < entry.chance then
            return entry.id
        end
    end
    return nil
end

local function allParts(instance: Instance): { BasePart }
    local parts: { BasePart } = {}
    if instance:IsA("BasePart") then
        table.insert(parts, instance)
    end
    for _, descendant in instance:GetDescendants() do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end
    return parts
end

local function heightOf(instance: Instance): number
    if instance:IsA("Model") then
        local _, size = instance:GetBoundingBox()
        return size.Y
    end
    local primary = Zone.PrimaryPart(instance)
    return if primary then primary.Size.Y else 1
end

-- Place le centre de la boite englobante sur cframe (les appelants ajoutent la demi-hauteur). Pas le pivot : celui de
-- certains modeles est loin de la geometrie, le jouet atterrissait alors loin de l'endroit voulu.
local function pivot(instance: Instance, cframe: CFrame): ()
    if instance:IsA("Model") then
        local center = instance:GetBoundingBox()
        instance:PivotTo(cframe * center:ToObjectSpace(instance:GetPivot()))
    elseif instance:IsA("BasePart") then
        instance.CFrame = cframe
    end
end

-- Pose un jouet au repos sur son point. Il est lache juste au-dessus et tombe par gravite (un jouet pose a la main
-- d'apres sa boite englobante semble leviter), puis il est ancre la ou il s'est arrete.
local SETTLE_SECONDS = 1.5
local settling: { [Instance]: {} } = {}

-- Une prise annule aussi l'ancien rappel de pose : il ne doit pas figer un lancer suivant.
function ToySpawnService:CancelSettling(toy: Instance): ()
    settling[toy] = nil
end

local function validPoint(point: BasePart): boolean
    return point:IsDescendantOf(workspace) and CollectionService:HasTag(point, SPAWN_TAG)
end

local function cancelPending(point: BasePart): ()
    local previous = pending[point]
    pending[point] = nil
    if previous and previous.connection then
        previous.connection:Disconnect()
    end
end

local function scheduleReplacement(point: BasePart): ()
    cancelPending(point)
    if not validPoint(point) then
        return
    end
    -- L'identité de cette table est le jeton de génération ; aucun ancien rappel ne peut le retrouver.
    local token: Pending = {}
    pending[point] = token
    token.connection = point.AncestryChanged:Connect(function()
        if not point:IsDescendantOf(workspace) then
            cancelPending(point)
        end
    end)
    local kitchen = workspace:FindFirstChild("Cuisine")
    local delaySeconds = if kitchen and point:IsDescendantOf(kitchen)
        then Tuning.KITCHEN_RESPAWN_SECONDS
        elseif point:GetAttribute("PointAccueil") == true then Tuning.WELCOME_RESPAWN_SECONDS
        else Tuning.RESPAWN_SECONDS
    task.delay(delaySeconds, function()
        if pending[point] ~= token then
            return
        end
        cancelPending(point)
        local current: Instance? = occupied[point]
        if validPoint(point) and current == nil then
            ToySpawnService:SpawnAt(point)
        end
    end)
end

local function forgetToy(toy: Instance): BasePart?
    local point = spawnOf[toy]
    spawnOf[toy] = nil
    trapped[toy] = nil
    settling[toy] = nil
    local connection = toyConnections[toy]
    toyConnections[toy] = nil
    if connection then
        connection:Disconnect()
    end
    if point and occupied[point] == toy then
        occupied[point] = nil
        return point
    end
    return nil
end

-- Contrat serveur pour le tutoriel : association par instance, indépendante des noms des six bases.
function ToySpawnService:GetWelcomeBase(toy: Instance): BasePart?
    local point = spawnOf[toy]
    return if point and validPoint(point) then welcomeBase[point] else nil
end

function ToySpawnService:GetWelcomeOrigin(base: BasePart): Vector3?
    local origin = WelcomePoints.Origin(base)
    return if origin then origin.Position else nil
end

local function rest(toy: Instance, spawnPart: BasePart): ()
    local parts = allParts(toy)
    for _, part in parts do
        part.CanCollide = true
        part.Massless = false
        part.Anchored = true
    end
    -- Les modeles Tripo regardent vers -Z (le berceau) : on les tourne vers les bases (+Z), avec un petit angle au
    -- hasard pour un desordre naturel. Verifie par capture des deux cotes (les joueurs voyaient les jouets de dos).
    local facing = CFrame.Angles(0, math.rad(180 + random:NextNumber(-35, 35)), 0)
    pivot(toy, spawnPart.CFrame * CFrame.new(0, spawnPart.Size.Y / 2 + heightOf(toy) / 2 + 1, 0) * facing)

    local token = {}
    settling[toy] = token
    for _, part in parts do
        part.Anchored = false
    end
    task.delay(SETTLE_SECONDS, function()
        -- Un jouet ramasse entre-temps (soude au personnage) ou relance ailleurs garde son etat.
        if settling[toy] ~= token or toy.Parent == nil or toy:GetAttribute("CarrierUserId") ~= nil then
            return
        end
        settling[toy] = nil
        for _, part in parts do
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
            part.Anchored = true
        end
    end)
end

function ToySpawnService:Init(): ()
    local folder = Instance.new("Folder")
    folder.Name = "ToysLive"
    liveFolder = folder
end

-- Clone du modele d'un jouet, ou nil (avec un avertissement unique) s'il manque.
function ToySpawnService:CloneTemplate(toyId: string): Instance?
    local models = ServerStorage:FindFirstChild("ToyModels")
    local template = if models then models:FindFirstChild(toyId) else nil
    if template == nil then
        if not warnedMissing[toyId] then
            warnedMissing[toyId] = true
            warn(string.format("[ToySpawnService] modele absent : ServerStorage.ToyModels.%s", toyId))
        end
        return nil
    end
    return template:Clone()
end

-- Aspect d'une mutation : un contour colore. Sans effet si la mutation est nil ou inconnue.
function ToySpawnService:ApplyMutationLook(toy: Instance, mutationId: string?): ()
    local color = if mutationId then MUTATION_COLORS[mutationId] else nil
    if color == nil then
        return
    end
    local highlight = Instance.new("Highlight")
    highlight.Name = "MutationLook"
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.65
    highlight.Parent = toy
end

function ToySpawnService:SpawnAt(spawnPart: BasePart): Instance?
    if not validPoint(spawnPart) then
        return nil
    end
    local current: Instance? = occupied[spawnPart]
    if current then
        return current
    end
    local fixed = spawnPart:GetAttribute("ToyId")
    local rarity = spawnPart:GetAttribute("Rarity")
    local kitchenFolder = workspace:FindFirstChild("Cuisine")
    local inKitchen = kitchenFolder ~= nil and spawnPart:IsDescendantOf(kitchenFolder)
    local welcome = spawnPart:GetAttribute("PointAccueil") == true and not inKitchen
    local toyId = if typeof(fixed) == "string" and Toys.Get(fixed)
        then fixed
        else pickToyId(if typeof(rarity) == "string" then rarity else nil, inKitchen)
    if welcome then
        -- Aucun tirage de mutation, de promotion lunaire ou de poids lourd pour l'accueil.
        local candidates: { string } = {}
        local models = ServerStorage:FindFirstChild("ToyModels")
        for _, def in poolFor(false) do
            if def.rarity == "Common" and def.carriers == 1 and models and models:FindFirstChild(def.id) then
                table.insert(candidates, def.id)
            end
        end
        toyId = if #candidates > 0 then candidates[random:NextInteger(1, #candidates)] else nil
    end
    if toyId == nil then
        return nil
    end
    local toy = ToySpawnService:CloneTemplate(toyId)
    if toy == nil then
        return nil
    end
    toy.Name = toyId
    toy:SetAttribute("ToyId", toyId)
    toy:SetAttribute("PointAccueil", if welcome then true else nil)
    local mutation = if welcome then nil else pickMutation()
    toy:SetAttribute("Mutation", mutation)
    if mutation then
        ToySpawnService:ApplyMutationLook(toy, mutation)
    else
        local def = Toys.Get(toyId)
        if def then
            ToySpawnService:ApplyRarityLook(toy, def.rarity)
        end
    end
    rest(toy, spawnPart)
    toy.Parent = liveFolder
    local toyDef = Toys.Get(toyId)
    if toyDef and toyDef.carriers > 1 then
        ToySpawnService:ApplyHeavyBadge(toy, toyDef.carriers)
    end
    if not welcome and random:NextNumber() < Tuning.TRAP_CHANCE then
        trapped[toy] = true
    end
    spawnOf[toy] = spawnPart
    occupied[spawnPart] = toy
    cancelPending(spawnPart)
    toyConnections[toy] = toy.AncestryChanged:Connect(function()
        if not toy:IsDescendantOf(workspace) then
            local freed = forgetToy(toy)
            if freed then
                scheduleReplacement(freed)
            end
        end
    end)
    CollectionService:AddTag(toy, TOY_TAG)
    spawnedEvent:Fire(toy)
    return toy
end

-- Renvoie un jouet lache ou confisque sur son point d'origine.
function ToySpawnService:ReturnToSpawn(toy: Instance): ()
    local spawnPart: BasePart? = spawnOf[toy]
    if spawnPart == nil or not validPoint(spawnPart) then
        toy:Destroy()
        return
    end
    rest(toy, spawnPart)
end

-- Pose un jouet a un endroit libre (lache par un joueur) : il tombe par gravite puis se fige, comme a l'apparition.
function ToySpawnService:PlaceAt(toy: Instance, cframe: CFrame): ()
    local parts = allParts(toy)
    for _, part in parts do
        part.CanCollide = true
        part.Massless = false
        part.Anchored = true
    end
    pivot(toy, cframe * CFrame.new(0, heightOf(toy) / 2 + 1, 0))
    local token = {}
    settling[toy] = token
    for _, part in parts do
        part.Anchored = false
    end
    task.delay(SETTLE_SECONDS, function()
        if settling[toy] ~= token or toy.Parent == nil or toy:GetAttribute("CarrierUserId") ~= nil then
            return
        end
        settling[toy] = nil
        for _, part in parts do
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
            part.Anchored = true
        end
    end)
end

-- Contour couleur de la rarete (demande utilisateur : « pas trop flashy, moyen ») : liseré seul, sans remplissage.
function ToySpawnService:ApplyRarityLook(toy: Instance, rarity: string): ()
    local color: Color3? = RARITY_COLORS[rarity]
    -- Pas de contour sur les communs : Roblox n'affiche que 31 Highlight a la fois et la chambre compte 37 jouets.
    if color == nil or rarity == "Common" then
        return
    end
    local highlight = Instance.new("Highlight")
    highlight.Name = "RarityLook"
    highlight.FillTransparency = 1
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0.35
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.Parent = toy
end

-- Icone « lourd » au-dessus des objets a plusieurs porteurs, visible de loin et a travers le decor ; masquee
-- pendant qu'on le porte (demande utilisateur).
-- kettlebell generee sur Higgsfield, detouree (assets/ui/propres/lourd.png, registre assets/ui/registry-lourd.json)
local HEAVY_ICON = "rbxassetid://105373636987385"
function ToySpawnService:ApplyHeavyBadge(toy: Instance, carriers: number): ()
    local primary = Zone.PrimaryPart(toy)
    if primary == nil then
        return
    end
    local gui = Instance.new("BillboardGui")
    gui.Name = "BadgeLourd"
    gui.Adornee = primary
    gui.Size = UDim2.fromOffset(64, 64)
    -- Juste au-dessus du haut du jouet : ExtentsOffset (multiple de la taille) le mettait bien trop haut, on ne
    -- voyait plus a quel objet il appartenait (retour utilisateur).
    local top = if toy:IsA("Model")
        then toy:GetBoundingBox().Position.Y + heightOf(toy) / 2
        else primary.Position.Y + primary.Size.Y / 2
    gui.StudsOffsetWorldSpace = Vector3.new(0, top - primary.Position.Y + 1.6, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 400
    gui.LightInfluence = 0
    gui.Parent = toy
    if HEAVY_ICON ~= "rbxassetid://0" then
        local icon = Instance.new("ImageLabel")
        icon.BackgroundTransparency = 1
        icon.Size = UDim2.fromScale(1, 1)
        icon.Image = HEAVY_ICON
        icon.Parent = gui
    end
    local count = Instance.new("TextLabel")
    count.BackgroundTransparency = 1
    count.Size = UDim2.fromScale(0.6, 0.45)
    count.Position = UDim2.fromScale(0.62, 0.62)
    count.Font = Enum.Font.FredokaOne
    count.TextScaled = true
    count.TextColor3 = Color3.new(1, 1, 1)
    count.TextStrokeTransparency = 0
    count.Text = "x" .. carriers
    count.Parent = gui
    toy:GetAttributeChangedSignal("CarrierUserId"):Connect(function()
        gui.Enabled = toy:GetAttribute("CarrierUserId") == nil
    end)
end

function ToySpawnService:IsTrapped(toy: Instance): boolean
    return trapped[toy] == true
end

-- Piege desamorce (il a explose) ; aussi utilisable pour pieger un jouet a la main (tests) avec armed = true.
function ToySpawnService:ClearTrap(toy: Instance, armed: boolean?): ()
    if armed then
        trapped[toy] = true
    else
        trapped[toy] = nil
    end
end

--[[
    Jouet temporaire (evenements : pluie de jouets, jouet dore geant) : lache a une position, il tombe par gravite
    (PlaceAt), n'a pas de point d'apparition (depose ou lache, il n'est pas remplace) et disparait apres `lifetime`
    secondes s'il n'est pas porte a ce moment-la. toyId nil = tire selon `rarity` (ou toutes raretes).
    Attribut Temporaire = true. Rend le jouet, ou nil si le modele manque.
]]
function ToySpawnService:SpawnTemporary(
    toyId: string?,
    position: Vector3,
    mutation: string?,
    lifetime: number,
    rarity: string?
): Instance?
    local id = if toyId and Toys.Get(toyId) then toyId else pickToyId(rarity)
    if id == nil then
        return nil
    end
    local toy = ToySpawnService:CloneTemplate(id)
    if toy == nil then
        return nil
    end
    toy.Name = id
    toy:SetAttribute("ToyId", id)
    toy:SetAttribute("Temporaire", true)
    local def = Toys.Get(id)
    if mutation and MUTATION_COLORS[mutation] then
        toy:SetAttribute("Mutation", mutation)
        ToySpawnService:ApplyMutationLook(toy, mutation)
    elseif def then
        ToySpawnService:ApplyRarityLook(toy, def.rarity)
    end
    toy.Parent = liveFolder
    ToySpawnService:PlaceAt(toy, CFrame.new(position) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))
    if def and def.carriers > 1 then
        ToySpawnService:ApplyHeavyBadge(toy, def.carriers)
    end
    CollectionService:AddTag(toy, TOY_TAG)
    task.delay(lifetime, function()
        if toy.Parent and toy:GetAttribute("CarrierUserId") == nil then
            toy:Destroy()
        end
    end)
    return toy
end

-- Le jouet a ete depose dans une base : on libere son point et on programme le suivant.
function ToySpawnService:OnTaken(toy: Instance): ()
    local point = forgetToy(toy)
    if point then
        scheduleReplacement(point)
    end
end

function ToySpawnService:Start(): ()
    local folder = liveFolder :: Folder
    folder.Parent = workspace

    local pointsFolder = Instance.new("Folder")
    pointsFolder.Name = "PointsAccueil"
    pointsFolder.Parent = workspace
    for _, entry in WelcomePoints.Build(pointsFolder) do
        welcomeBase[entry.part] = entry.base
        CollectionService:AddTag(entry.part, SPAWN_TAG)
    end
    CollectionService:GetInstanceRemovedSignal(SPAWN_TAG):Connect(function(instance: Instance)
        if instance:IsA("BasePart") then
            cancelPending(instance)
            welcomeBase[instance] = nil
        end
    end)

    local function onSpawn(instance: Instance): ()
        -- Les tags suivent les instances rangees dans ServerStorage : seuls les points du workspace comptent.
        if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
            ToySpawnService:SpawnAt(instance)
        end
    end
    for _, instance in CollectionService:GetTagged(SPAWN_TAG) do
        onSpawn(instance)
    end
    CollectionService:GetInstanceAddedSignal(SPAWN_TAG):Connect(onSpawn)

    if #CollectionService:GetTagged(SPAWN_TAG) == 0 then
        warn("[ToySpawnService] aucun point tague ToySpawn : aucun jouet n'apparaitra")
    end
end

return ToySpawnService
