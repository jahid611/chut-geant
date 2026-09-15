--!strict

--[[
    AbilityService
    Pouvoirs actifs a recharge et effets des ameliorations a niveaux (reglages : Shared/Abilities, prix :
    Shared/Catalog). Chaque pouvoir s'achete une fois en tetines (ShopService:Owns).

    - Fury           : sprint (Tuning.FURY_*) avec une trainee, tres bruyant (NoiseService).
    - MagicPacifier  : jauge de bruit -30 % (sans effet si le bebe est deja reveille : pas de recharge perdue).
    - DecoyRattle    : un hochet part devant le joueur ; 4 s pendant lesquelles le bebe le regarde (attribut
                       DecoyUntil du workspace : chasse et regard n'attrapent personne).
    - ShieldPlush    : bulle (ForceField) qui annule la prochaine propulsion, 60 s au plus.
    - SuctionGun     : tir vise (CarryService:FindShot) : le jouet touche a portee (90 / 160 studs selon le niveau)
                       revient en vol (CarryService:PullToy) ; rate ou jouet lourd au niveau 1 : recharge courte.
    - ShadowCape     : 5 s invisible pour le bebe et maman (GiantService:Catch l'ignore), personnage translucide.
    - Lullaby        : le bebe se rendort tout de suite et la jauge revient a zero pour tout le serveur.
    Etat en attributs du joueur, temps serveur : <Id>Until (effet en cours), <Id>ReadyAt (recharge).
    Remote UseAbility (abilityId, direction: Vector3?) ; AbilityCast (id, userId, position) vers tous les clients.

    Ameliorations : Aimant a tetines (+10 % de revenu par niveau, BaseService:AddIncomeMultiplier).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CarryService = require(script.Parent:WaitForChild("CarryService"))
local GiantService = require(script.Parent:WaitForChild("GiantService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))

local TRAIL_NAME = "TraineeFurie"
local SHIELD_NAME = "BulleDoudou"
local DECOY_SIZE = 3
local DECOY_LIFETIME = 6

local AbilityService = {}

-- start rend (utilise, recharge?) : une recharge explicite remplace celle du pouvoir (tir de ventouse rate).
type Handler = {
    start: (Player, Vector3?, Vector3?) -> (boolean, number?),
    finish: ((Player) -> ())?,
}

-- Resultat du dernier tir de ventouse d'un joueur, joint a AbilityCast (« hit » | « miss » | « heavy »).
local shotResults: { [Player]: { result: string, point: Vector3 } } = {}

local function humanoidOf(player: Player): (BasePart?, Humanoid?)
    local character = player.Character
    if character == nil then
        return nil, nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
        return root, humanoid
    end
    return nil, nil
end

-- Vitesse du moment : celle du portage si le joueur porte un jouet (CarryService la recalcule), sinon la marche.
local function refreshSpeed(player: Player): ()
    local _, humanoid = humanoidOf(player)
    if humanoid and CarryService:GetCarried(player) == nil then
        humanoid.WalkSpeed = CarryService:WalkSpeedFor(player)
    end
end

-- Trainee rose et jaune accrochee au bassin, visible par tous.
local function setTrail(player: Player, enabled: boolean): ()
    local root = humanoidOf(player)
    if root == nil then
        return
    end
    local existing = root:FindFirstChild(TRAIL_NAME)
    if not enabled then
        if existing then
            existing:Destroy()
        end
        for _, name in { "FurieHaut", "FurieBas" } do
            local attachment = root:FindFirstChild(name)
            if attachment then
                attachment:Destroy()
            end
        end
        return
    end
    if existing then
        return
    end
    local top = Instance.new("Attachment")
    top.Name = "FurieHaut"
    top.Position = Vector3.new(0, 1.3, 0)
    top.Parent = root
    local bottom = Instance.new("Attachment")
    bottom.Name = "FurieBas"
    bottom.Position = Vector3.new(0, -1.3, 0)
    bottom.Parent = root
    local trail = Instance.new("Trail")
    trail.Name = TRAIL_NAME
    trail.Attachment0 = top
    trail.Attachment1 = bottom
    trail.Lifetime = 0.35
    trail.Color = ColorSequence.new(Color3.fromRGB(255, 120, 190), Color3.fromRGB(255, 220, 90))
    trail.Transparency = NumberSequence.new(0.15, 1)
    trail.LightEmission = 0.6
    trail.Parent = root
end

-- Doudou qui tourne autour du joueur tant que le bouclier est actif (ServerStorage.DecorModels.ShieldPlush).
local PLUSH_NAME = "DoudouBouclier"
local PLUSH_SIZE = 2.5
local PLUSH_RADIUS = 3.2
local orbits: { [Player]: RBXScriptConnection } = {}

local function removeShield(player: Player): ()
    local character = player.Character
    local bubble = if character then character:FindFirstChild(SHIELD_NAME) else nil
    if bubble then
        bubble:Destroy()
    end
    local plush = if character then character:FindFirstChild(PLUSH_NAME) else nil
    if plush then
        plush:Destroy()
    end
    local orbit = orbits[player]
    if orbit then
        orbit:Disconnect()
        orbits[player] = nil
    end
end

local function addOrbitingPlush(player: Player): ()
    local character = player.Character
    local root = humanoidOf(player)
    local decor = ServerStorage:FindFirstChild("DecorModels")
    local template = if decor then decor:FindFirstChild("ShieldPlush") else nil
    if character == nil or root == nil or template == nil or not template:IsA("Model") then
        return
    end
    local model = template:Clone()
    model.Name = PLUSH_NAME
    local _, size = model:GetBoundingBox()
    model:ScaleTo(model:GetScale() * (PLUSH_SIZE / math.max(size.X, size.Y, size.Z, 0.1)))
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = false
        end
    end
    model.Parent = character
    local started = os.clock()
    orbits[player] = RunService.Heartbeat:Connect(function()
        local currentRoot = humanoidOf(player)
        if currentRoot == nil or model.Parent == nil then
            return
        end
        local t = os.clock() - started
        local angle = t * 2.4
        local offset =
            Vector3.new(math.cos(angle) * PLUSH_RADIUS, 1.2 + math.sin(t * 3) * 0.3, math.sin(angle) * PLUSH_RADIUS)
        local position = currentRoot.Position + offset
        model:PivotTo(CFrame.lookAt(position, currentRoot.Position + Vector3.new(0, 1.2, 0)))
    end)
end

-- Cape d'ombre : personnage translucide (transparence d'origine gardee en attribut sur chaque piece).
local function setCloaked(player: Player, cloaked: boolean): ()
    local character = player.Character
    if character == nil then
        return
    end
    for _, descendant in character:GetDescendants() do
        if descendant:IsA("BasePart") or descendant:IsA("Decal") then
            if descendant.Name == "HumanoidRootPart" then
                continue
            end
            local saved = descendant:GetAttribute("TransparenceAvantCape")
            if cloaked then
                if typeof(saved) ~= "number" then
                    local part = descendant :: any
                    descendant:SetAttribute("TransparenceAvantCape", part.Transparency)
                    part.Transparency = math.max(part.Transparency, Abilities.CAPE_TRANSPARENCY)
                end
            elseif typeof(saved) == "number" then
                local part = descendant :: any
                part.Transparency = saved
                descendant:SetAttribute("TransparenceAvantCape", nil)
            end
        end
    end
end

-- Hochet leurre visible : copie du hochet du decor lancee devant le joueur, detruite apres quelques secondes.
local function throwDecoy(player: Player, direction: Vector3?): ()
    local root = humanoidOf(player)
    local decor = ServerStorage:FindFirstChild("DecorModels")
    local template = if decor then decor:FindFirstChild("Rattle") else nil
    if root == nil or template == nil or not template:IsA("Model") then
        return
    end
    local model = template:Clone()
    model.Name = "HochetLeurre"
    local _, size = model:GetBoundingBox()
    model:ScaleTo(model:GetScale() * (DECOY_SIZE / math.max(size.X, size.Y, size.Z, 0.1)))
    local flat = if direction then Vector3.new(direction.X, 0, direction.Z) else Vector3.zero
    local aim = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
    model:PivotTo(CFrame.new(root.Position + aim * 3 + Vector3.new(0, 3, 0)))
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
    for _, part in parts do
        part.Anchored = false
        part.CanCollide = true
        part.CanQuery = false
        if part ~= primary then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = primary
            weld.Part1 = part
            weld.Parent = part
        end
    end
    model.Parent = workspace
    for _, part in parts do
        pcall(function()
            part:SetNetworkOwner(nil)
        end)
    end
    primary.AssemblyLinearVelocity = aim * Abilities.DECOY_THROW_SPEED + Vector3.new(0, 25, 0)
    primary.AssemblyAngularVelocity = Vector3.new(0, 6, 4)
    task.delay(DECOY_LIFETIME, function()
        model:Destroy()
    end)
end

local HANDLERS: { [string]: Handler } = {
    Fury = {
        start = function(player: Player): boolean
            refreshSpeed(player)
            setTrail(player, true)
            return true
        end,
        finish = function(player: Player): ()
            refreshSpeed(player)
            setTrail(player, false)
        end,
    },
    MagicPacifier = {
        start = function(): boolean
            return NoiseService:Reduce(Tuning.NOISE_MAX * Abilities.PACIFIER_FRACTION)
        end,
    },
    DecoyRattle = {
        start = function(player: Player, direction: Vector3?): boolean
            local untilTime = workspace:GetServerTimeNow() + Abilities.DECOY_SECONDS
            local current = workspace:GetAttribute("DecoyUntil")
            if typeof(current) ~= "number" or current < untilTime then
                workspace:SetAttribute("DecoyUntil", untilTime)
            end
            throwDecoy(player, direction)
            return true
        end,
    },
    ShieldPlush = {
        start = function(player: Player): boolean
            local character = player.Character
            if character == nil then
                return false
            end
            removeShield(player)
            local bubble = Instance.new("ForceField")
            bubble.Name = SHIELD_NAME
            bubble.Visible = true
            bubble.Parent = character
            addOrbitingPlush(player)
            return true
        end,
        finish = removeShield,
    },
    SuctionGun = {
        start = function(player: Player, direction: Vector3?, origin: Vector3?): (boolean, number?)
            if direction == nil then
                return false
            end
            local level = math.max(Abilities.Level(player, "SuctionGun"), 1)
            local range = Abilities.SUCTION_RANGES[math.min(level, #Abilities.SUCTION_RANGES)]
            local toy, point = CarryService:FindShot(player, origin, direction, range)
            if toy == nil then
                shotResults[player] = { result = "miss", point = point }
                return true, Abilities.SUCTION_MISS_COOLDOWN
            end
            local toyId = toy:GetAttribute("ToyId")
            local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
            if def and def.carriers > 1 and level < Abilities.SUCTION_HEAVY_LEVEL then
                shotResults[player] = { result = "heavy", point = point }
                return true, Abilities.SUCTION_MISS_COOLDOWN
            end
            if not CarryService:CanTake(player, toy) then
                shotResults[player] = { result = "full", point = point }
                return false
            end
            shotResults[player] = { result = "hit", point = point }
            CarryService:PullToy(player, toy, function(picked: boolean)
                -- ramassage impossible a l'arrivee : seulement la recharge courte
                if not picked and player.Parent then
                    player:SetAttribute(
                        "SuctionGunReadyAt",
                        workspace:GetServerTimeNow() + Abilities.SUCTION_MISS_COOLDOWN
                    )
                end
            end)
            return true
        end,
    },
    ShadowCape = {
        start = function(player: Player): boolean
            setCloaked(player, true)
            return true
        end,
        finish = function(player: Player): ()
            setCloaked(player, false)
        end,
    },
    Lullaby = {
        start = function(): boolean
            GiantService:Soothe()
            return true
        end,
    },
}

--[[
    Utilise un pouvoir : possession, recharge, joueur vivant, puis l'effet. La recharge ne part que si l'effet a
    vraiment eu lieu. Vrai si le pouvoir a ete utilise.
]]
function AbilityService:Use(player: Player, abilityId: string, direction: Vector3?, origin: Vector3?): boolean
    local ability = Abilities.Get(abilityId)
    local handler = HANDLERS[abilityId]
    if ability == nil or handler == nil or not ShopService:Owns(player, abilityId) then
        return false
    end
    local now = workspace:GetServerTimeNow()
    local readyAt = player:GetAttribute(abilityId .. "ReadyAt")
    if typeof(readyAt) == "number" and readyAt > now then
        return false
    end
    local root = humanoidOf(player)
    if root == nil then
        return false
    end
    local untilTime = now + ability.duration
    -- l'etat « en cours » est pose avant l'effet : la Furie calcule sa vitesse a partir de FuryUntil
    if ability.duration > 0 then
        player:SetAttribute(abilityId .. "Until", untilTime)
    end
    shotResults[player] = nil
    local ok, started, cooldown = pcall(handler.start, player, direction, origin)
    local shot = shotResults[player]
    shotResults[player] = nil
    local cast = Remotes.Get("AbilityCast") :: RemoteEvent
    if not ok or started ~= true then
        if not ok then
            warn(string.format("[AbilityService] %s : %s", abilityId, tostring(started)))
        end
        if ability.duration > 0 then
            player:SetAttribute(abilityId .. "Until", nil)
        end
        -- tir refuse (mains pleines) : seul le tireur est prevenu
        if shot then
            cast:FireClient(player, abilityId, player.UserId, root.Position, shot.result, shot.point)
        end
        return false
    end
    local wait = if typeof(cooldown) == "number" then cooldown else ability.cooldown
    player:SetAttribute(abilityId .. "ReadyAt", now + wait)
    -- AbilityCast : (id, userId, position, resultat du tir?, point vise?) ; resultat pour la ventouse seulement.
    cast:FireAllClients(
        abilityId,
        player.UserId,
        root.Position,
        if shot then shot.result else nil,
        if shot then shot.point else nil
    )
    if ability.duration > 0 then
        task.delay(ability.duration, function()
            if player.Parent == nil or player:GetAttribute(abilityId .. "Until") ~= untilTime then
                return
            end
            player:SetAttribute(abilityId .. "Until", nil)
            local finish = handler.finish
            if finish then
                finish(player)
            end
        end)
    end
    return true
end

-- Compatibilite : ancienne entree de la Furie.
function AbilityService:UseFury(player: Player): boolean
    return AbilityService:Use(player, "Fury", nil)
end

function AbilityService:Init(): () end

function AbilityService:Start(): ()
    local remote = Remotes.Get("UseAbility") :: RemoteEvent
    -- (abilityId, direction de visee, origine du rayon de visee = camera) ; valeurs non finies ignorees.
    remote.OnServerEvent:Connect(function(player: Player, abilityId: any, direction: any, origin: any)
        if typeof(abilityId) ~= "string" then
            return
        end
        local aim: Vector3? = nil
        if typeof(direction) == "Vector3" and direction.Magnitude == direction.Magnitude then
            aim = direction
        end
        local from: Vector3? = nil
        if typeof(origin) == "Vector3" and origin.Magnitude == origin.Magnitude and origin.Magnitude < 1e6 then
            from = origin
        end
        AbilityService:Use(player, abilityId, aim, from)
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        shotResults[player] = nil
    end)

    -- Aimant a tetines : +10 % de revenu par niveau.
    BaseService:AddIncomeMultiplier(function(player: Player): number
        return 1 + Abilities.MAGNET_PER_LEVEL * Abilities.Level(player, "Magnet")
    end)

    local function onPlayer(player: Player): ()
        player:GetAttributeChangedSignal("Owned_Magnet"):Connect(function()
            BaseService:RefreshIncome(player)
        end)
        -- Doudou bouclier consomme (GiantService, CarryService) ou fini : la bulle disparait.
        player:GetAttributeChangedSignal("ShieldPlushUntil"):Connect(function()
            if not Abilities.IsActive(player, "ShieldPlush") then
                removeShield(player)
            end
        end)
        player.CharacterAdded:Connect(function()
            -- les effets en cours ne survivent pas a la reapparition
            for _, ability in Abilities.LIST do
                if ability.duration > 0 then
                    player:SetAttribute(ability.id .. "Until", nil)
                end
            end
        end)
        if player:GetAttribute("Owned_Magnet") ~= nil then
            BaseService:RefreshIncome(player)
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        onPlayer(player)
    end
end

return AbilityService
