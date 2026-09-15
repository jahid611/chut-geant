--!strict

--[[
    BaseService
    Attribue une base a chaque joueur, range les jouets deposes dans ses coffres a jouets, verse le revenu
    et vend les ameliorations de la boutique.

    Une base est une BasePart taguee "Base" qui delimite son volume de depot (transparente, non solide).
    L'argent du jeu est la tetine : attribut Cash du joueur, affiche « Tétines » dans leaderstats.

    Coffres a jouets (maquettes validees) : chaque joueur commence avec 1 coffre de Tuning.CHEST_CAPACITY
    jouets et peut en acheter jusqu'a Tuning.MAX_CHESTS. Ce sont de vrais modeles poses sur l'attribut
    ChestCFrame de la base (bas du coffre, rotation comprise), les suivants decales de ChestStep, a la taille
    ChestSize (defaut Tuning.CHEST_SIZE) ; une base sans ces attributs recoit de petits coffres devant sa zone.
    Chaque jouet depose est une copie du jouet, a l'echelle du coffre, lachee au-dessus de l'ouverture : il
    tombe par la physique sur les autres puis se fige. Des parois invisibles epousent la cavite du coffre.

    Dossier workspace.BaseChests.Base_<UserId> : modeles Coffre1..n, attributs Index, Count, Capacity, Size,
    CavityCFrame (centre du fond de la cavite) et CavitySize ; le client s'en sert pour la vue « Mes jouets ».
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Toys = require(Shared:WaitForChild("Toys"))
local Tuning = require(Shared:WaitForChild("Tuning"))
local Zone = require(Shared:WaitForChild("Zone"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local BASE_TAG = "Base"
-- Coffres des bases sans interieur : petits, alignes devant la zone de depot.
local ROOM_CHEST_SIZE = 26
local ROOM_CHEST_STEP = 30
-- Les jouets sont dessines pour un coffre de Tuning.CHEST_SIZE : taille reelle (a 0,75 le coffre plein paraissait
-- vide en vue de dessus, teste en jeu).
local TOY_IN_CHEST_SCALE = 1
-- Cavite du modele ToyChest, mesuree par rayons (fractions de sa boite englobante, repere du modele) :
-- centree en X, decalee vers l'avant en Z, fond a 10 % de la hauteur, bord a 50 %.
local CAVITY_OFFSET = Vector2.new(0, -0.1)
local CAVITY_SPAN = Vector2.new(0.62, 0.45)
local CAVITY_FLOOR = 0.1
local CAVITY_RIM = 0.5

type OwnedToy = { id: string, mutation: string? }

-- Comptes qui recoivent un gros solde de depart pour tester la boutique (compte Roblox de l'utilisateur).
local TEST_ACCOUNTS: { [number]: boolean } = { [11620637288] = true }
local TEST_GRANT = 500000

local BaseService = {}

-- (player: Player, toyId: string, mutation: string?) un jouet vient d'etre depose dans un coffre du joueur.
local toyDeposited = Instance.new("BindableEvent")
BaseService.ToyDeposited = toyDeposited.Event

-- Multiplicateurs de revenu enregistres par d'autres services (aimant, Nuits, pleine lune, amis...).
local incomeMultipliers: { (Player) -> number } = {}
-- Revenus additionnels par seconde, avant les multiplicateurs (jouets du tipi : TentService).
local incomeSources: { (Player) -> number } = {}

local random = Random.new()
local baseOf: { [Player]: BasePart } = {}
local ownerOf: { [BasePart]: Player } = {}
local owned: { [Player]: { OwnedToy } } = {}
local chestCount: { [Player]: number } = {}
local chestFolders: { [Player]: Folder } = {}
local chestRoot: Folder? = nil

local function freeBase(): BasePart?
    local bases = CollectionService:GetTagged(BASE_TAG)
    table.sort(bases, function(a, b)
        return a.Name < b.Name
    end)
    for _, base in bases do
        -- Les tags suivent les instances rangees dans ServerStorage : seules les bases du workspace comptent.
        if base:IsA("BasePart") and base:IsDescendantOf(workspace) then
            local owner: Player? = ownerOf[base]
            if owner == nil then
                return base
            end
        end
    end
    return nil
end

local function cashOf(player: Player): number
    local cash = player:GetAttribute("Cash")
    return if typeof(cash) == "number" then cash else 0
end

local function setCash(player: Player, amount: number): ()
    local profile = DataService:Get(player)
    if profile then
        profile.cash = amount
    end
    player:SetAttribute("Cash", amount)
    local stats = player:FindFirstChild("leaderstats")
    local value = if stats then stats:FindFirstChild("Tétines") else nil
    if value and value:IsA("IntValue") then
        value.Value = math.floor(amount)
    end
end

-- Pose du coffre n° index : CFrame du bas du coffre et taille en studs.
local function chestPlacement(base: BasePart, index: number): (CFrame, number)
    local anchor = base:GetAttribute("ChestCFrame")
    if typeof(anchor) == "CFrame" then
        local step = base:GetAttribute("ChestStep")
        local size = base:GetAttribute("ChestSize")
        local offset: Vector3 = if typeof(step) == "Vector3" then step else Vector3.new(Tuning.CHEST_SIZE + 12, 0, 0)
        return anchor + offset * (index - 1), if typeof(size) == "number" then size else Tuning.CHEST_SIZE
    end
    local x = -(Tuning.MAX_CHESTS - 1) * ROOM_CHEST_STEP / 2 + (index - 1) * ROOM_CHEST_STEP
    local front = base.CFrame * CFrame.new(x, -base.Size.Y / 2, -base.Size.Z / 2 - ROOM_CHEST_SIZE / 2 - 6)
    return CFrame.new(front.Position), ROOM_CHEST_SIZE
end

-- Hauteur du sol sous une position (terrain, parquet, tapis), sans compter les coffres ni les joueurs.
local function groundY(position: Vector3): number?
    local ignore: { Instance } = {}
    if chestRoot then
        table.insert(ignore, chestRoot)
    end
    for _, player in Players:GetPlayers() do
        if player.Character then
            table.insert(ignore, player.Character)
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -160, 0), params)
    return if hit then hit.Position.Y else nil
end

local function solidPart(parent: Instance, name: string, size: Vector3, cframe: CFrame): ()
    local part = Instance.new("Part")
    part.Name = name
    part.Size = Vector3.new(math.max(size.X, 0.4), math.max(size.Y, 0.4), math.max(size.Z, 0.4))
    part.CFrame = cframe
    part.Anchored = true
    part.CanCollide = true
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Transparency = 1
    part.Parent = parent
end

local function buildChest(player: Player, index: number): Model?
    local base: BasePart? = baseOf[player]
    local folder: Folder? = chestFolders[player]
    if base == nil or folder == nil then
        return nil
    end
    local decor = ServerStorage:FindFirstChild("DecorModels")
    -- Coffres dores (les premiers du joueur, profile.goldChests) : modele GoldChest s'il existe, sinon ToyChest.
    -- Memes fractions de cavite : les proportions du coffre dore sont proches, c'est accepte.
    local profile = DataService:Get(player)
    local golden = profile ~= nil and index <= profile.goldChests
    local goldTemplate = if golden and decor then decor:FindFirstChild("GoldChest") else nil
    local template = if goldTemplate and goldTemplate:IsA("Model")
        then goldTemplate
        elseif decor then decor:FindFirstChild("ToyChest")
        else nil
    if template == nil or not template:IsA("Model") then
        warn("[BaseService] modele absent : ServerStorage.DecorModels.ToyChest")
        return nil
    end
    local usesGoldModel = template == goldTemplate

    local placement, size = chestPlacement(base, index)
    -- Sol le plus haut sous l'empreinte (centre + 4 coins) : un seul rayon au centre enfouissait le coffre n°2
    -- dans le flanc d'une dune de la pantoufle (teste en jeu, vue « Mes jouets » toute noire).
    local ground: number? = nil
    local half = size / 2
    for _, corner in
        {
            Vector3.zero,
            Vector3.new(half, 0, half),
            Vector3.new(-half, 0, half),
            Vector3.new(half, 0, -half),
            Vector3.new(-half, 0, -half),
        }
    do
        local y = groundY(placement.Position + corner)
        if y and (ground == nil or y > (ground :: number)) then
            ground = y
        end
    end
    if ground then
        -- 1 stud dans le sol (fourrure, mouchoirs, tapis) pour ne pas flotter
        placement = placement.Rotation + Vector3.new(placement.Position.X, ground - 1, placement.Position.Z)
    end

    local chest = template:Clone()
    chest.Name = "Coffre" .. index
    local _, raw = chest:GetBoundingBox()
    chest:ScaleTo(chest:GetScale() * (size / math.max(raw.X, raw.Y, raw.Z)))
    chest:PivotTo(placement)
    local placedCFrame, placedSize = chest:GetBoundingBox()
    local bottom = placedCFrame.Position - placedCFrame.UpVector * placedSize.Y / 2
    chest:PivotTo(chest:GetPivot() + (placement.Position - bottom))
    local box, boxSize = chest:GetBoundingBox()

    for _, descendant in chest:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
        end
    end

    -- Collisions : un corps plein autour d'une cavite ouverte (le maillage seul boucherait l'ouverture).
    local walls = Instance.new("Folder")
    walls.Name = "Parois"
    walls.Parent = chest
    local halfW, halfH, halfD = boxSize.X / 2, boxSize.Y / 2, boxSize.Z / 2
    local cx, cz = CAVITY_OFFSET.X * boxSize.X, CAVITY_OFFSET.Y * boxSize.Z
    local innerW, innerD = CAVITY_SPAN.X * boxSize.X, CAVITY_SPAN.Y * boxSize.Z
    local floorY = -halfH + CAVITY_FLOOR * boxSize.Y
    local rimY = -halfH + CAVITY_RIM * boxSize.Y
    local wallHeight = rimY + halfH
    local wallY = (-halfH + rimY) / 2
    local frontEdge, backEdge = cz - innerD / 2, cz + innerD / 2
    local leftEdge, rightEdge = cx - innerW / 2, cx + innerW / 2
    solidPart(
        walls,
        "Fond",
        Vector3.new(innerW, floorY + halfH, innerD),
        box * CFrame.new(cx, (-halfH + floorY) / 2, cz)
    )
    solidPart(
        walls,
        "Avant",
        Vector3.new(boxSize.X, wallHeight, frontEdge + halfD),
        box * CFrame.new(0, wallY, (-halfD + frontEdge) / 2)
    )
    solidPart(
        walls,
        "Arriere",
        Vector3.new(boxSize.X, wallHeight, halfD - backEdge),
        box * CFrame.new(0, wallY, (backEdge + halfD) / 2)
    )
    solidPart(
        walls,
        "Gauche",
        Vector3.new(leftEdge + halfW, wallHeight, innerD),
        box * CFrame.new((-halfW + leftEdge) / 2, wallY, cz)
    )
    solidPart(
        walls,
        "Droite",
        Vector3.new(halfW - rightEdge, wallHeight, innerD),
        box * CFrame.new((rightEdge + halfW) / 2, wallY, cz)
    )

    local toysFolder = Instance.new("Folder")
    toysFolder.Name = "Jouets"
    toysFolder.Parent = chest

    -- Lueur douce au-dessus de la cavite : chaque coffre est eclaire, pas seulement le premier (sans elle, la vue
    -- « Mes jouets » du coffre n°2 etait toute noire, teste en jeu).
    local lamp = Instance.new("Part")
    lamp.Name = "Lueur"
    lamp.Size = Vector3.new(1, 1, 1)
    lamp.CFrame = box * CFrame.new(cx, rimY + boxSize.Y * 0.35, cz)
    lamp.Anchored = true
    lamp.CanCollide = false
    lamp.CanQuery = false
    lamp.CanTouch = false
    lamp.CastShadow = false
    lamp.Transparency = 1
    lamp.Parent = chest
    local glow = Instance.new("PointLight")
    glow.Color = Color3.fromRGB(255, 222, 170)
    -- 0,6 : les joueurs arrivent maintenant colles a leur coffre, 1,4 s'ajoutait aux lumieres de la boite et
    -- saturait l'ecran en blanc (teste en jeu)
    glow.Brightness = 0.6
    glow.Range = math.max(boxSize.X * 0.9, 16)
    glow.Shadows = true
    glow.Parent = lamp

    chest:SetAttribute("Index", index)
    -- vrai si le coffre est pose avec le modele GoldChest (sert a savoir s'il faut le reconstruire)
    chest:SetAttribute("GoldModel", usesGoldModel)
    chest:SetAttribute("Capacity", Tuning.CHEST_CAPACITY)
    chest:SetAttribute("Count", 0)
    chest:SetAttribute("Size", size)
    chest:SetAttribute("OwnerUserId", player.UserId)
    chest:SetAttribute("CavityCFrame", box * CFrame.new(cx, floorY, cz))
    chest:SetAttribute("CavitySize", Vector3.new(innerW, rimY - floorY, innerD))
    chest.Parent = folder
    return chest
end

local function refreshCounts(player: Player): ()
    local folder: Folder? = chestFolders[player]
    local list: { OwnedToy }? = owned[player]
    if folder == nil or list == nil then
        return
    end
    for _, chest in folder:GetChildren() do
        local index = chest:GetAttribute("Index")
        if typeof(index) == "number" then
            local count = math.clamp(#list - (index - 1) * Tuning.CHEST_CAPACITY, 0, Tuning.CHEST_CAPACITY)
            chest:SetAttribute("Count", count)
        end
    end
    player:SetAttribute("Income", BaseService:GetIncome(player))
end

-- Jette une copie du jouet dans le coffre : elle tombe par la physique, puis se fige.
local function dropToy(player: Player, toy: OwnedToy, chestIndex: number): ()
    local folder: Folder? = chestFolders[player]
    local chest = if folder then folder:FindFirstChild("Coffre" .. chestIndex) else nil
    if chest == nil then
        return
    end
    local cavity = chest:GetAttribute("CavityCFrame")
    local cavitySize = chest:GetAttribute("CavitySize")
    local size = chest:GetAttribute("Size")
    local toysFolder = chest:FindFirstChild("Jouets")
    if
        typeof(cavity) ~= "CFrame"
        or typeof(cavitySize) ~= "Vector3"
        or typeof(size) ~= "number"
        or toysFolder == nil
    then
        return
    end
    local model = ToySpawnService:CloneTemplate(toy.id)
    if model == nil then
        return
    end
    if not model:IsA("Model") then
        model:Destroy()
        return
    end
    model.Name = toy.id
    ToySpawnService:ApplyMutationLook(model, toy.mutation)
    model:ScaleTo(model:GetScale() * (size / Tuning.CHEST_SIZE) * TOY_IN_CHEST_SCALE)

    local parts: { BasePart } = {}
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end
    local primary: BasePart? = parts[1]
    if primary == nil then
        model:Destroy()
        return
    end

    local _, toySize = model:GetBoundingBox()
    local offset = Vector3.new(
        (random:NextNumber() - 0.5) * cavitySize.X * 0.5,
        cavitySize.Y + toySize.Magnitude / 2 + 1,
        (random:NextNumber() - 0.5) * cavitySize.Z * 0.4
    )
    local spin = CFrame.Angles(
        random:NextNumber(0, math.pi * 2),
        random:NextNumber(0, math.pi * 2),
        random:NextNumber(0, math.pi * 2)
    )
    model:PivotTo(cavity * CFrame.new(offset) * spin)

    for _, part in parts do
        part.Anchored = false
        part.CanCollide = true
        part.CanQuery = false
        part.Massless = false
        if part ~= primary then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = primary
            weld.Part1 = part
            weld.Parent = part
        end
    end
    model.Parent = toysFolder
    for _, part in parts do
        pcall(function()
            part:SetNetworkOwner(nil)
        end)
    end
    primary.AssemblyAngularVelocity =
        Vector3.new(random:NextNumber(-3, 3), random:NextNumber(-3, 3), random:NextNumber(-3, 3))

    task.delay(Tuning.CHEST_SETTLE_SECONDS, function()
        if model.Parent == nil then
            return
        end
        for _, part in parts do
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
            part.Anchored = true
        end
    end)
end

function BaseService:GetBase(player: Player): BasePart?
    return baseOf[player]
end

function BaseService:GetSpawnCFrame(player: Player): CFrame?
    local base: BasePart? = baseOf[player]
    if base == nil then
        return nil
    end
    return base.CFrame * CFrame.new(0, -base.Size.Y / 2 + 3, 0)
end

-- Nombre de coffres du joueur, et s'il peut encore en acheter.
function BaseService:GetChestInfo(player: Player): (number, boolean)
    local chests = chestCount[player] or 1
    return chests, chests < Tuning.MAX_CHESTS
end

-- Revenu par seconde de tout ce que possede le joueur : jouets (x2 dans les coffres dores, les premiers coffres
-- du joueur), puis les multiplicateurs enregistres (AddIncomeMultiplier).
function BaseService:GetIncome(player: Player): number
    local list: { OwnedToy }? = owned[player]
    if list == nil then
        return 0
    end
    local profile = DataService:Get(player)
    local golden = if profile then profile.goldChests else 0
    local total = 0
    for index, toy in list do
        local chestIndex = math.ceil(index / Tuning.CHEST_CAPACITY)
        total += Toys.Income(toy.id, toy.mutation) * (if chestIndex <= golden then 2 else 1)
    end
    for _, source in incomeSources do
        local ok, extra = pcall(source, player)
        if ok and typeof(extra) == "number" and extra > 0 then
            total += extra
        end
    end
    for _, multiplier in incomeMultipliers do
        local ok, factor = pcall(multiplier, player)
        if ok and typeof(factor) == "number" and factor > 0 then
            total *= factor
        end
    end
    return math.floor(total)
end

-- Enregistre un multiplicateur de revenu (fonction du joueur, 1 = sans effet).
function BaseService:AddIncomeMultiplier(multiplier: (Player) -> number): ()
    table.insert(incomeMultipliers, multiplier)
end

-- Enregistre un revenu additionnel par seconde (fonction du joueur), ajoute avant les multiplicateurs.
function BaseService:AddIncomeSource(source: (Player) -> number): ()
    table.insert(incomeSources, source)
end

-- Un jouet vole a ete range ailleurs que dans un coffre (tipi) : memes stats et meme evenement qu'un depot en
-- coffre (quetes, collection, XP).
function BaseService:NotifyDeposited(player: Player, toyId: string, mutationId: string?, source: string?): ()
    DataService:AddStat(player, "stolen", 1)
    toyDeposited:Fire(player, toyId, mutationId, source or "room")
end

-- Recalcule l'attribut Income (apres un coffre dore, un bonus qui change...).
function BaseService:RefreshIncome(player: Player): ()
    player:SetAttribute("Income", BaseService:GetIncome(player))
end

function BaseService:GetCash(player: Player): number
    return cashOf(player)
end

function BaseService:AddCash(player: Player, amount: number): ()
    setCash(player, cashOf(player) + amount)
end

-- Debite si le solde suffit. Vrai si c'est paye.
function BaseService:SpendCash(player: Player, amount: number): boolean
    if amount < 0 or cashOf(player) < amount then
        return false
    end
    setCash(player, cashOf(player) - amount)
    return true
end

-- Nuits (renaissance, NightsService) : tetines a zero, jouets vides, un seul coffre non dore, et le joueur est
-- ramene a sa base. Vrai si la base a ete reinitialisee.
function BaseService:ResetBase(player: Player): boolean
    local profile = DataService:Get(player)
    local folder: Folder? = chestFolders[player]
    if profile == nil or folder == nil then
        return false
    end
    table.clear(profile.toys)
    owned[player] = profile.toys
    profile.chests = 1
    profile.goldChests = 0
    chestCount[player] = 1
    player:SetAttribute("Chests", 1)
    for _, child in folder:GetChildren() do
        child:Destroy()
    end
    buildChest(player, 1)
    setCash(player, 0)
    refreshCounts(player)
    local spawnCFrame = BaseService:GetSpawnCFrame(player)
    local character = player.Character
    if spawnCFrame and character then
        character:PivotTo(spawnCFrame)
    end
    return true
end

-- Reconstruit le coffre n° index (devenu dore) et y rejette ses jouets, un par un.
local function rebuildChest(player: Player, index: number): ()
    local folder: Folder? = chestFolders[player]
    local list: { OwnedToy }? = owned[player]
    if folder == nil or list == nil then
        return
    end
    local old = folder:FindFirstChild("Coffre" .. index)
    if old then
        old:Destroy()
    end
    buildChest(player, index)
    local first = (index - 1) * Tuning.CHEST_CAPACITY + 1
    local last = math.min(#list, index * Tuning.CHEST_CAPACITY)
    local toys: { OwnedToy } = {}
    for i = first, last do
        table.insert(toys, list[i])
    end
    task.spawn(function()
        for _, toy in toys do
            if player.Parent == nil then
                return
            end
            dropToy(player, toy, index)
            task.wait(0.15)
        end
    end)
    refreshCounts(player)
end

-- Apres l'achat d'un coffre dore (attribut Owned_GoldChest publie par ShopService) : les coffres dont le modele ne
-- correspond plus sont reconstruits. Sans modele GoldChest dans ServerStorage, rien a changer a l'ecran.
local function refreshGoldChests(player: Player): ()
    local folder: Folder? = chestFolders[player]
    local profile = DataService:Get(player)
    local decor = ServerStorage:FindFirstChild("DecorModels")
    if folder == nil or profile == nil or decor == nil or decor:FindFirstChild("GoldChest") == nil then
        return
    end
    for index = 1, chestCount[player] or 1 do
        local chest = folder:FindFirstChild("Coffre" .. index)
        local wantsGold = index <= profile.goldChests
        if chest and chest:GetAttribute("GoldModel") ~= wantsGold then
            rebuildChest(player, index)
        end
    end
end

-- Coffre suivant (achat en boutique). Vrai si un coffre a ete ajoute.
function BaseService:AddChest(player: Player): boolean
    local chests = chestCount[player] or 1
    if chests >= Tuning.MAX_CHESTS then
        return false
    end
    local index = chests + 1
    chestCount[player] = index
    local profile = DataService:Get(player)
    if profile then
        profile.chests = index
    end
    player:SetAttribute("Chests", index)
    buildChest(player, index)
    refreshCounts(player)
    return true
end

--[[
    Tente de deposer un jouet porte. Vrai si le porteur se trouve dans sa propre base, que le jouet est connu
    et qu'il reste une place dans ses coffres ; le jouet est alors jete dans le premier coffre non plein.
    Faux avec la raison "full" quand tous les coffres sont pleins.
]]
function BaseService:TryDeposit(
    player: Player,
    toyId: string,
    mutationId: string?,
    position: Vector3,
    source: string?
): (boolean, string?)
    local base: BasePart? = baseOf[player]
    if base == nil or not Zone.Contains(base, position) or Toys.Get(toyId) == nil then
        return false, nil
    end
    local list: { OwnedToy }? = owned[player]
    if list == nil then
        return false, nil
    end
    local chests = chestCount[player] or 1
    if #list >= chests * Tuning.CHEST_CAPACITY then
        return false, "full"
    end
    local mutation = if mutationId and Toys.GetMutation(mutationId) then mutationId else nil
    local entry: OwnedToy = { id = toyId, mutation = mutation }
    table.insert(list, entry)
    dropToy(player, entry, math.ceil(#list / Tuning.CHEST_CAPACITY))
    refreshCounts(player)
    self:NotifyDeposited(player, toyId, mutation, source)
    return true, nil
end

-- Vol entre joueurs (StealService, BaseLockService) ------------------------------------------------------------

function BaseService:GetOwnerOfBase(base: BasePart): Player?
    return ownerOf[base]
end

-- Copie des bases occupees et de leurs proprietaires.
function BaseService:GetOwnedBases(): { [BasePart]: Player }
    return table.clone(ownerOf)
end

-- Base occupee dont le volume contient la position, et son proprietaire.
function BaseService:GetBaseAt(position: Vector3): (BasePart?, Player?)
    for base, owner in ownerOf do
        if base.Parent and Zone.Contains(base, position) then
            return base, owner
        end
    end
    return nil, nil
end

function BaseService:GetToyCount(player: Player): number
    local list: { OwnedToy }? = owned[player]
    return if list then #list else 0
end

-- Retire un modele de jouet (nomme par son id) du coffre n° index, sans toucher au profil.
local function removeToyModel(player: Player, chestIndex: number, toyId: string): ()
    local folder: Folder? = chestFolders[player]
    local chest = if folder then folder:FindFirstChild("Coffre" .. chestIndex) else nil
    local toys = if chest then chest:FindFirstChild("Jouets") else nil
    local model = if toys then toys:FindFirstChild(toyId) else nil
    if model then
        model:Destroy()
    end
end

-- Tirage d'un jouet a voler : les communs sortent plus souvent, pour que le vol reste juste.
local STEAL_WEIGHTS: { [string]: number } = { Common = 6, Uncommon = 4, Rare = 2, Epic = 1, Legendary = 0.5 }

local function stealWeight(toy: OwnedToy): number
    local def = Toys.Get(toy.id)
    return if def then STEAL_WEIGHTS[def.rarity] or 1 else 1
end

--[[
    Prend un jouet au hasard dans le coffre n° chestIndex du joueur (pondere vers les communs) et le retire de son
    profil. Le dernier jouet de la liste prend sa place, pour que les autres coffres ne changent pas. Rend le jouet
    retire, ou nil si le coffre est vide.
]]
function BaseService:TakeToyFromChest(player: Player, chestIndex: number): OwnedToy?
    local list: { OwnedToy }? = owned[player]
    if list == nil then
        return nil
    end
    local capacity = Tuning.CHEST_CAPACITY
    local first = (chestIndex - 1) * capacity + 1
    local last = math.min(#list, chestIndex * capacity)
    if first > last then
        return nil
    end
    local total = 0
    for i = first, last do
        total += stealWeight(list[i])
    end
    local roll = random:NextNumber() * total
    local chosen = last
    for i = first, last do
        roll -= stealWeight(list[i])
        if roll <= 0 then
            chosen = i
            break
        end
    end
    local taken = list[chosen]
    removeToyModel(player, chestIndex, taken.id)
    local lastIndex = #list
    if chosen ~= lastIndex then
        local moved = list[lastIndex]
        list[chosen] = moved
        table.remove(list, lastIndex)
        removeToyModel(player, math.ceil(lastIndex / capacity), moved.id)
        dropToy(player, moved, chestIndex)
    else
        table.remove(list, lastIndex)
    end
    refreshCounts(player)
    DataService:AddStat(player, "robbed", 1)
    return taken
end

-- Rend un jouet vole a son proprietaire (le voleur l'a lache). Faux si le joueur n'a plus de place dans ses coffres.
function BaseService:GiveBackToy(player: Player, toy: OwnedToy): boolean
    local list: { OwnedToy }? = owned[player]
    if list == nil or Toys.Get(toy.id) == nil then
        return false
    end
    local chests = chestCount[player] or 1
    if #list >= chests * Tuning.CHEST_CAPACITY then
        return false
    end
    local entry: OwnedToy = { id = toy.id, mutation = toy.mutation }
    table.insert(list, entry)
    dropToy(player, entry, math.ceil(#list / Tuning.CHEST_CAPACITY))
    refreshCounts(player)
    return true
end

-- Les achats sont geres par ShopService (catalogue complet, Shared/Catalog).

local function onPlayerAdded(player: Player): ()
    local stats = Instance.new("Folder")
    stats.Name = "leaderstats"
    -- La monnaie du jeu est la tetine (demande utilisateur), pas l'argent. L'attribut interne reste Cash.
    local cash = Instance.new("IntValue")
    cash.Name = "Tétines"
    cash.Parent = stats
    stats.Parent = player

    -- Profil sauvegarde (DataService) : tetines, coffres et jouets deja voles reviennent a chaque session.
    local profile = DataService:WaitForProfile(player)
    if player.Parent == nil then
        return
    end
    owned[player] = if profile then profile.toys else {}
    chestCount[player] = if profile then math.clamp(profile.chests, 1, Tuning.MAX_CHESTS) else 1
    setCash(player, if profile then profile.cash else 0)
    -- Compte de test de l'utilisateur (15/09/2026 : « 500 K pour tester les achats », pas infini) : don unique par
    -- profil, marque dans ses stats. En Studio sans DataStore le profil repart de zero, donc le don revient a chaque test.
    if profile and TEST_ACCOUNTS[player.UserId] and (profile.stats.testGrant or 0) == 0 then
        profile.stats.testGrant = 1
        setCash(player, profile.cash + TEST_GRANT)
    end
    player:SetAttribute("Income", 0)
    player:SetAttribute("Chests", chestCount[player])
    player:SetAttribute("ChestCapacity", Tuning.CHEST_CAPACITY)

    local base = freeBase()
    if base == nil then
        warn(string.format("[BaseService] plus de base libre pour %s", player.Name))
    else
        baseOf[player] = base
        ownerOf[base] = player
        base:SetAttribute("OwnerUserId", player.UserId)
        local folder = Instance.new("Folder")
        folder.Name = string.format("Base_%d", player.UserId)
        folder.Parent = chestRoot
        chestFolders[player] = folder
        for index = 1, chestCount[player] do
            buildChest(player, index)
        end
        -- Jouets sauvegardes rejetes dans leurs coffres, un par un pour ne pas surcharger la physique.
        local saved: { OwnedToy } = owned[player] or {}
        task.spawn(function()
            for i, toy in saved do
                if (player.Parent :: Instance?) == nil then
                    return
                end
                dropToy(player, toy, math.ceil(i / Tuning.CHEST_CAPACITY))
                task.wait(0.15)
            end
        end)
        refreshCounts(player)
        player:GetAttributeChangedSignal("Owned_GoldChest"):Connect(function()
            refreshGoldChests(player)
        end)
    end

    local function onCharacter(character: Model): ()
        local spawnCFrame = BaseService:GetSpawnCFrame(player)
        if spawnCFrame == nil then
            return
        end
        character:WaitForChild("HumanoidRootPart", 5)
        task.defer(function()
            if character.Parent then
                character:PivotTo(spawnCFrame)
            end
        end)
    end
    player.CharacterAdded:Connect(onCharacter)
    if player.Character then
        onCharacter(player.Character)
    end
end

local function onPlayerRemoving(player: Player): ()
    local base: BasePart? = baseOf[player]
    if base then
        ownerOf[base] = nil
        base:SetAttribute("OwnerUserId", nil)
    end
    local folder: Folder? = chestFolders[player]
    if folder then
        folder:Destroy()
    end
    baseOf[player] = nil
    owned[player] = nil
    chestFolders[player] = nil
    chestCount[player] = nil
end

function BaseService:Init(): ()
    local folder = Instance.new("Folder")
    folder.Name = "BaseChests"
    chestRoot = folder
end

function BaseService:Start(): ()
    local root = chestRoot :: Folder
    root.Parent = workspace

    if #CollectionService:GetTagged(BASE_TAG) == 0 then
        warn("[BaseService] aucune piece taguee Base : les joueurs n'auront pas de base")
    end

    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayerAdded, player)
    end

    task.spawn(function()
        while true do
            task.wait(Tuning.INCOME_TICK_SECONDS)
            for player in owned do
                local income = BaseService:GetIncome(player)
                if income > 0 then
                    setCash(player, cashOf(player) + income * Tuning.INCOME_TICK_SECONDS)
                end
            end
        end
    end)
end

return BaseService
