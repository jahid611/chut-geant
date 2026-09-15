--!strict

--[[
    CarryService
    Voler et porter les jouets.

    Chaque jouet tague "Toy" recoit un ProximityPrompt. Le serveur valide la prise
    (joueur vivant, mains libres, jouet libre, distance), soude le jouet au-dessus
    du joueur et regle sa vitesse. Un jouet qui demande plusieurs porteurs n'avance
    a vitesse normale que si assez de coequipiers se tiennent a cote. Arrive dans
    sa base, le porteur depose le jouet dans ses coffres (BaseService) et son point
    d'origine se recharge (ToySpawnService). Coffres pleins : le joueur garde le
    jouet et recoit la fenetre « Coffre plein ! » (remote ChestFull).

    Attributs du joueur lus par le HUD : CarriedToyId, CarriedMutation ; sac a dos : CarriedToyId2,
    CarriedMutation2.
    Ameliorations (Shared/Abilities, attributs Owned_<id>) :
    - Bras costauds (5 niveaux) : portage plus rapide ;
    - Sac a dos : un 2e jouet LEGER se ramasse quand on porte deja un jouet leger ; il est soude dans le dos.
      Poser et lancer agissent sur le jouet des mains, puis celui du dos passe dans les mains.
    Ventouse (pouvoir, tir vise) : FindShot trouve le jouet touche par le tir, PullToy lance la ventouse avec son fil,
    puis ramene le jouet en vol jusqu'au joueur avant de le ramasser (attribut AspireParUserId pendant le vol :
    personne d'autre ne peut le prendre).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))
local Tuning = require(Shared:WaitForChild("Tuning"))
local Zone = require(Shared:WaitForChild("Zone"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local ToySpawnService = require(script.Parent:WaitForChild("ToySpawnService"))

local TOY_TAG = "Toy"
local PROMPT_NAME = "StealPrompt"
local CHECK_INTERVAL = 0.2
-- Delai minimal entre deux fenetres « Coffre plein ! » pour un meme joueur qui reste dans sa base.
local FULL_NOTICE_SECONDS = 6
-- Sac a dos : le jouet du dos passe dans les mains un peu apres un lancer (pas de choc avec le jouet lance).
local PROMOTE_AFTER_THROW = 0.3

local CarryService = {}

-- Emis quand un jouet piege explose : (position: Vector3). EventService reveille le bebe.
local trapExplodedEvent = Instance.new("BindableEvent")
CarryService.TrapExploded = trapExplodedEvent.Event
-- Emis quand un jouet fait du bruit (lancer, atterrissage) : (amount: number). NoiseService l'ajoute a la jauge.
local madeNoiseEvent = Instance.new("BindableEvent")
CarryService.MadeNoise = madeNoiseEvent.Event

local EXPLOSION_SOUND = "rbxassetid://3149249837"

local carried: { [Player]: Instance } = {}
local carryWelds: { [Player]: WeldConstraint } = {}
-- Sac a dos visible (ServerStorage.DecorModels.Backpack) soude dans le dos des joueurs qui l'ont achete.
local BACKPACK_MODEL_NAME = "SacADos"

local backpack: { [Player]: Instance } = {}
local backpackWelds: { [Player]: WeldConstraint } = {}
local lastFullNotice: { [Player]: number } = {}

local function aliveRoot(player: Player): (BasePart?, Humanoid?)
    local character = player.Character
    if character == nil then
        return nil, nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
        return root, humanoid
    end
    return nil, nil
end

local function partsOf(toy: Instance): { BasePart }
    local parts: { BasePart } = {}
    if toy:IsA("BasePart") then
        table.insert(parts, toy)
    end
    for _, descendant in toy:GetDescendants() do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end
    return parts
end

local function sizeOf(toy: Instance): Vector3
    if toy:IsA("Model") then
        local _, size = toy:GetBoundingBox()
        return size
    end
    local primary = Zone.PrimaryPart(toy)
    return if primary then primary.Size else Vector3.one
end

local function setPromptEnabled(toy: Instance, enabled: boolean): ()
    local primary = Zone.PrimaryPart(toy)
    local prompt = if primary then primary:FindFirstChild(PROMPT_NAME) else nil
    if prompt and prompt:IsA("ProximityPrompt") then
        prompt.Enabled = enabled
    end
end

local function carriersFor(toy: Instance): number
    local toyId = toy:GetAttribute("ToyId")
    local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
    return if def then def.carriers else 1
end

-- Poids d'un jouet pour le lancer (a appeler quand il a repris sa taille au sol) : un canard vaut 1, un gros jouet ou
-- un jouet a deux porteurs bien plus. Plus il est lourd, moins il va loin et plus il fait de bruit.
local function weightOf(toy: Instance): number
    local size = sizeOf(toy)
    local biggest = math.max(size.X, size.Y, size.Z)
    return math.max(1, carriersFor(toy) + (biggest - Tuning.THROW_LIGHT_SIZE) / Tuning.THROW_SIZE_PER_WEIGHT)
end

-- Choc a l'atterrissage : plastique leger pour les petits jouets, gros choc sourd pour les lourds, plus fort et plus
-- grave avec le poids (sons Pro Sound Effects de la bibliotheque Roblox).
local IMPACT_LIGHT = "rbxassetid://9117566164"
local IMPACT_HEAVY = "rbxassetid://9113805607"
local function playImpact(part: BasePart, weight: number): ()
    local sound = Instance.new("Sound")
    sound.SoundId = if weight >= 2 then IMPACT_HEAVY else IMPACT_LIGHT
    sound.Volume = math.clamp(0.3 * weight, 0.3, 1)
    sound.PlaybackSpeed = math.clamp(1.25 - 0.15 * weight, 0.75, 1.2)
    sound.RollOffMaxDistance = 400
    sound.Parent = part
    sound:Play()
    task.delay(4, function()
        sound:Destroy()
    end)
end

-- Bonus de vitesse de la Furie en cours (AbilityService pose l'attribut FuryUntil, en temps serveur).
local function furyBonus(player: Player): number
    return if Abilities.IsActive(player, "Fury") then Tuning.FURY_SPEED_BONUS else 0
end

-- Vitesse d'un porteur : aide = assez de coequipiers autour pour ce jouet. Bras costauds : bonus par niveau.
local function carrySpeed(player: Player, needed: number, helped: boolean): number
    local strong = Abilities.Level(player, "StrongArms")
    if not helped then
        return Tuning.CARRY_SPEED_ALONE + Abilities.STRONG_ALONE_PER_LEVEL * strong + furyBonus(player)
    end
    local base = Tuning.CARRY_SPEED[needed] or Tuning.CARRY_SPEED_ALONE
    return base + Abilities.STRONG_BONUS_PER_LEVEL * strong + furyBonus(player)
end

-- Vitesse normale d'un joueur les mains vides (Furie comprise).
function CarryService:WalkSpeedFor(player: Player): number
    return Tuning.WALK_SPEED + furyBonus(player)
end

local function hasBackpack(player: Player): boolean
    return Abilities.Level(player, "Backpack") > 0
end

-- Taille d'origine retrouvee en quittant le joueur.
local function restoreScale(toy: Instance): ()
    local groundScale = toy:GetAttribute("GroundScale")
    if typeof(groundScale) == "number" and toy:IsA("Model") then
        toy:SetAttribute("GroundScale", nil)
        toy:ScaleTo(groundScale)
    end
end

-- Detache le jouet des mains sans decider ou il va. Rend le jouet, ou nil.
local function release(player: Player): Instance?
    local toy: Instance? = carried[player]
    if toy == nil then
        return nil
    end
    carried[player] = nil
    local weld: WeldConstraint? = carryWelds[player]
    if weld then
        weld:Destroy()
        carryWelds[player] = nil
    end
    toy:SetAttribute("CarrierUserId", nil)
    restoreScale(toy)
    player:SetAttribute("CarriedToyId", nil)
    player:SetAttribute("CarriedMutation", nil)
    local _, humanoid = aliveRoot(player)
    if humanoid then
        humanoid.WalkSpeed = CarryService:WalkSpeedFor(player)
    end
    return toy
end

-- Detache le jouet du sac a dos. Rend le jouet, ou nil.
local function releaseBack(player: Player): Instance?
    local toy: Instance? = backpack[player]
    if toy == nil then
        return nil
    end
    backpack[player] = nil
    local weld: WeldConstraint? = backpackWelds[player]
    if weld then
        weld:Destroy()
        backpackWelds[player] = nil
    end
    toy:SetAttribute("CarrierUserId", nil)
    restoreScale(toy)
    player:SetAttribute("CarriedToyId2", nil)
    player:SetAttribute("CarriedMutation2", nil)
    return toy
end

local tryPickup: (Player, Instance, boolean?) -> boolean

-- Filtre de prise (mission de la tetine, PacifierMissionService) : faux = ce jouet ne peut pas etre pris maintenant.
local pickupFilter: ((Player, Instance) -> boolean)? = nil

-- Mains vides : le jouet du sac a dos passe dans les mains (s'il n'y arrive pas, il tombe au sol).
local function promoteBackpack(player: Player): ()
    if carried[player] then
        return
    end
    local toy = releaseBack(player)
    if toy == nil then
        return
    end
    if not tryPickup(player, toy, true) then
        setPromptEnabled(toy, true)
        for _, part in partsOf(toy) do
            part.CanCollide = true
            part.Massless = false
        end
    end
end

tryPickup = function(player: Player, toy: Instance, ignoreReach: boolean?): boolean
    if toy:GetAttribute("CarrierUserId") ~= nil or not CollectionService:HasTag(toy, TOY_TAG) then
        return false
    end
    -- Jouet en vol vers le joueur qui l'a attrape a la ventouse : a lui seul.
    local puller = toy:GetAttribute("AspireParUserId")
    if puller ~= nil and puller ~= player.UserId then
        return false
    end
    -- Prise volontaire (bouton « Voler ») : regles speciales du jouet. Les prises internes (sac a dos qui passe dans
    -- les mains, fin du vol de ventouse, deja filtree par CanTake) ne sont pas refiltrees.
    local filter = pickupFilter
    if not ignoreReach and filter and not filter(player, toy) then
        return false
    end
    local hands: Instance? = carried[player]
    local toBack = false
    if hands then
        -- Sac a dos : seulement deux jouets legers.
        if
            not hasBackpack(player)
            or (backpack[player] :: Instance?) ~= nil
            or carriersFor(hands) > 1
            or carriersFor(toy) > 1
        then
            return false
        end
        toBack = true
    end
    local root, humanoid = aliveRoot(player)
    local primary = Zone.PrimaryPart(toy)
    if root == nil or humanoid == nil or primary == nil then
        return false
    end
    local size = sizeOf(toy)
    local reach = Tuning.PICKUP_DISTANCE + math.max(size.X, size.Y, size.Z) / 2
    if not ignoreReach and (root.Position - primary.Position).Magnitude > reach then
        return false
    end

    -- Porte, le jouet est reduit a une taille qui laisse voir (il reprend sa taille une fois pose).
    if toy:IsA("Model") and toy:GetAttribute("GroundScale") == nil then
        local limit = if carriersFor(toy) > 1 then Tuning.CARRY_MAX_SIZE_HEAVY else Tuning.CARRY_MAX_SIZE
        local biggest = math.max(size.X, size.Y, size.Z)
        if biggest > limit then
            toy:SetAttribute("GroundScale", toy:GetScale())
            toy:ScaleTo(toy:GetScale() * limit / biggest)
            size = sizeOf(toy)
        end
    end

    -- Soudures internes une seule fois par jouet (il peut etre ramasse plusieurs fois).
    local welded = toy:GetAttribute("InnerWelded") == true
    for _, part in partsOf(toy) do
        part.Anchored = false
        part.CanCollide = false
        part.Massless = true
        if part ~= primary and not welded then
            local inner = Instance.new("WeldConstraint")
            inner.Part0 = primary
            inner.Part1 = part
            inner.Parent = part
        end
    end
    toy:SetAttribute("InnerWelded", true)

    local target: CFrame
    if toBack then
        -- Dans le dos (+Z du bassin), un peu plus haut que le bassin ; par-dessus le sac visible s'il est porte.
        local character = player.Character
        local bag = if character then character:FindFirstChild(BACKPACK_MODEL_NAME) else nil
        local bagDepth = if bag then bag:GetAttribute("Profondeur") else nil
        local extra = if typeof(bagDepth) == "number" then bagDepth else 0
        target = root.CFrame * CFrame.new(0, 0.6, root.Size.Z / 2 + extra + size.Z / 2 + 0.2)
    else
        -- Bras leves (CarryController cote client) : le bas du jouet au bout des doigts, au-dessus
        -- de la tete. Avant, le jouet etait pose a 2 studs du centre du torse, donc enfonce sur la tete.
        local character = player.Character
        local head = if character then character:FindFirstChild("Head") else nil
        local headTop = if head and head:IsA("BasePart")
            then head.Position.Y + head.Size.Y / 2
            else root.Position.Y + 2.5
        local lift = headTop + Tuning.CARRY_ABOVE_HEAD + size.Y / 2 - root.Position.Y
        target = root.CFrame * CFrame.new(0, lift, 0)
    end
    if toy:IsA("Model") then
        -- Centre de la boite du jouet sur la cible, pas son pivot : le pivot de certains modeles est loin de la
        -- geometrie, et le jouet flottait alors tres loin du joueur (retour utilisateur).
        local center = toy:GetBoundingBox()
        toy:PivotTo(target * center:ToObjectSpace(toy:GetPivot()))
    else
        primary.CFrame = target
    end
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = root
    weld.Part1 = primary
    weld.Parent = primary

    toy:SetAttribute("CarrierUserId", player.UserId)
    local toyId = toy:GetAttribute("ToyId")
    local mutation = toy:GetAttribute("Mutation")
    local idValue = if typeof(toyId) == "string" then toyId else nil
    local mutationValue = if typeof(mutation) == "string" then mutation else nil
    if toBack then
        backpack[player] = toy
        backpackWelds[player] = weld
        player:SetAttribute("CarriedToyId2", idValue)
        player:SetAttribute("CarriedMutation2", mutationValue)
    else
        carried[player] = toy
        carryWelds[player] = weld
        player:SetAttribute("CarriedToyId", idValue)
        player:SetAttribute("CarriedMutation", mutationValue)
        humanoid.WalkSpeed = carrySpeed(player, carriersFor(toy), true)
    end
    setPromptEnabled(toy, false)

    if ToySpawnService:IsTrapped(toy) then
        CarryService:ArmTrap(player, toy)
    end
    return true
end

-- Jouet vole dans la base d'un autre joueur (StealService, attribut StolenFromUserId) : lache sans etre depose (pose,
-- lance, attrape par le bebe ou maman, touche par une arme, deconnexion), il retourne a sa victime au lieu de rester.
local stolenReturnHook: ((Instance) -> ())? = nil

function CarryService:SetStolenReturnHook(hook: (Instance) -> ()): ()
    stolenReturnHook = hook
end

local function giveBackIfStolen(toy: Instance?): boolean
    if toy == nil or toy:GetAttribute("StolenFromUserId") == nil then
        return false
    end
    local hook = stolenReturnHook
    if hook then
        local ok, err = pcall(hook :: any, toy)
        if not ok then
            warn("[CarryService] retour du jouet vole : " .. tostring(err))
        end
    end
    toy:Destroy()
    return true
end

-- Fait porter un jouet vole (clone pose pres du voleur par StealService) : memes regles que la prise d'un jouet de
-- la chambre, sans condition de distance. Vrai si le joueur le porte.
function CarryService:CarryStolen(player: Player, toy: Instance): boolean
    return tryPickup(player, toy, true)
end

-- Jouet piege : il tremble et bipe (client), puis explose et reveille le bebe.
function CarryService:ArmTrap(player: Player, toy: Instance): ()
    ToySpawnService:ClearTrap(toy)
    toy:SetAttribute("Armed", true)
    local remote = Remotes.Get("TrapArmed") :: RemoteEvent
    remote:FireClient(player, Tuning.TRAP_FUSE_SECONDS)
    task.delay(Tuning.TRAP_FUSE_SECONDS, function()
        toy:SetAttribute("Armed", nil)
        if toy.Parent == nil then
            return
        end
        local primary = Zone.PrimaryPart(toy)
        local position = if primary then primary.Position else Vector3.zero
        local explosion = Instance.new("Explosion")
        explosion.Position = position
        explosion.BlastRadius = 10
        explosion.BlastPressure = 0
        explosion.DestroyJointRadiusPercent = 0
        explosion.Parent = workspace
        local anchor = Instance.new("Part")
        anchor.Name = "SonExplosion"
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanQuery = false
        anchor.Transparency = 1
        anchor.Size = Vector3.one
        anchor.Position = position
        anchor.Parent = workspace
        local sound = Instance.new("Sound")
        sound.SoundId = EXPLOSION_SOUND
        sound.Volume = 0.6
        sound.RollOffMaxDistance = 900
        sound.Parent = anchor
        sound:Play()
        task.delay(4, function()
            anchor:Destroy()
        end)
        -- Seul le jouet qui explose retourne a son point ; l'autre (mains ou dos) reste porte.
        local exploding: Instance? = nil
        if carried[player] == toy then
            exploding = release(player)
            promoteBackpack(player)
        elseif backpack[player] == toy then
            exploding = releaseBack(player)
        end
        if exploding then
            setPromptEnabled(exploding, true)
            ToySpawnService:ReturnToSpawn(exploding)
        elseif toy:GetAttribute("CarrierUserId") == nil then
            ToySpawnService:ReturnToSpawn(toy)
        end
        local exploded = Remotes.Get("TrapExploded") :: RemoteEvent
        exploded:FireAllClients(position)
        trapExplodedEvent:Fire(position)
    end)
end

local function setupPrompt(toy: Instance): ()
    local primary = Zone.PrimaryPart(toy)
    if primary == nil or primary:FindFirstChild(PROMPT_NAME) then
        return
    end
    local toyId = toy:GetAttribute("ToyId")
    local def = if typeof(toyId) == "string" then Toys.Get(toyId) else nil
    local mutationId = toy:GetAttribute("Mutation")
    local mutation = if typeof(mutationId) == "string" then Toys.GetMutation(mutationId) else nil

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = PROMPT_NAME
    prompt.ActionText = "Voler"
    prompt.ObjectText = (if def then def.displayName else "Jouet")
        .. (if mutation then " " .. mutation.displayName else "")
    prompt.HoldDuration = 0.3
    prompt.MaxActivationDistance = Tuning.PICKUP_DISTANCE
    prompt.RequiresLineOfSight = false
    prompt.Triggered:Connect(function(player: Player)
        tryPickup(player, toy)
    end)
    prompt.Parent = primary
end

-- Pose le jouet porte juste devant le joueur, sans bruit : il est lache au ras du sol trouve devant lui et tombe par
-- gravite (pas de pose dans un mur : on s'arrete avant l'obstacle). Le jouet du sac a dos passe ensuite dans les mains.
function CarryService:PutDown(player: Player): ()
    local toy: Instance? = carried[player]
    local root = aliveRoot(player)
    if toy == nil or root == nil then
        return
    end
    release(player)
    if giveBackIfStolen(toy) then
        promoteBackpack(player)
        return
    end
    setPromptEnabled(toy, true)
    local size = sizeOf(toy)
    local radius = math.max(size.X, size.Z) / 2
    local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
    look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore: { Instance } = { toy }
    if player.Character then
        table.insert(ignore, player.Character)
    end
    local back: Instance? = backpack[player]
    if back then
        table.insert(ignore, back)
    end
    params.FilterDescendantsInstances = ignore
    local distance = 1.5 + radius
    local blocked = workspace:Raycast(root.Position, look * (distance + radius), params)
    if blocked then
        distance = math.max((blocked.Position - root.Position).Magnitude - radius - 0.5, 0.5)
    end
    local front = root.Position + look * distance
    local ground = workspace:Raycast(front + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
    local groundY = if ground then ground.Position.Y else root.Position.Y - 3
    ToySpawnService:PlaceAt(toy, CFrame.new(front.X, groundY, front.Z) * root.CFrame.Rotation)
    promoteBackpack(player)
end

-- Lance le jouet porte dans une direction : bruit, et propulsion des autres joueurs touches en vol.
function CarryService:Throw(player: Player, direction: Vector3): ()
    local toy: Instance? = carried[player]
    local root = aliveRoot(player)
    if toy == nil or root == nil then
        return
    end
    local flat = Vector3.new(direction.X, 0, direction.Z)
    local aim = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
    release(player)
    if giveBackIfStolen(toy) then
        promoteBackpack(player)
        return
    end
    setPromptEnabled(toy, true)
    task.delay(PROMOTE_AFTER_THROW, function()
        promoteBackpack(player)
    end)
    local weight = weightOf(toy)
    local primary = Zone.PrimaryPart(toy)
    if primary == nil then
        return
    end
    local parts = partsOf(toy)
    for _, part in parts do
        part.Anchored = false
        part.CanCollide = true
        part.Massless = false
    end
    for _, part in parts do
        pcall(function()
            part:SetNetworkOwner(nil)
        end)
    end
    primary.AssemblyLinearVelocity = aim * (Tuning.THROW_SPEED / weight)
        + Vector3.new(0, Tuning.THROW_UP / math.sqrt(weight), 0)
    primary.AssemblyAngularVelocity = Vector3.new(math.random(-4, 4), math.random(-4, 4), math.random(-4, 4))
    madeNoiseEvent:Fire(Tuning.THROW_NOISE * weight)

    local hit: { [Player]: boolean } = {}
    local landed = false
    local connection: RBXScriptConnection? = nil
    connection = primary.Touched:Connect(function(other: BasePart)
        local model = other:FindFirstAncestorOfClass("Model")
        local victim = if model then Players:GetPlayerFromCharacter(model) else nil
        if victim and victim ~= player then
            if not hit[victim] then
                hit[victim] = true
                -- Doudou bouclier : le coup est encaisse par la bulle.
                if Abilities.ConsumeShield(victim) then
                    return
                end
                -- Drop est defini plus bas dans le module
                local service: any = CarryService
                service:Drop(victim, false)
                local remote = Remotes.Get("Caught") :: RemoteEvent
                remote:FireClient(
                    victim,
                    "hit",
                    aim * Tuning.HIT_LAUNCH_SPEED + Vector3.new(0, Tuning.HIT_LAUNCH_UP, 0)
                )
            end
        elseif victim == nil and not landed and not other:IsDescendantOf(toy) then
            landed = true
            playImpact(primary, weight)
            madeNoiseEvent:Fire(Tuning.THROW_LAND_NOISE * weight)
        end
    end)
    task.delay(Tuning.THROW_FLIGHT_SECONDS, function()
        if connection then
            connection:Disconnect()
        end
        if toy.Parent == nil or toy:GetAttribute("CarrierUserId") ~= nil then
            return
        end
        for _, part in parts do
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
            part.Anchored = true
        end
    end)
end

-- Prise d'un jouet par le code (tests en jeu) : memes verifications que le bouton « Voler ». Vrai si ramasse.
function CarryService:TryPickup(player: Player, toy: Instance): boolean
    return tryPickup(player, toy)
end

-- Prise sans condition de distance (Ventouse, apres le vol de la ventouse jusqu'au jouet).
function CarryService:TryPickupFrom(player: Player, toy: Instance): boolean
    return tryPickup(player, toy, true)
end

--[[
    Ventouse : ramasse de loin le jouet le mieux aligne avec la visee (direction de la camera), a moins de range
    studs, dans un cone etroit. Memes regles que la prise a la main (mains libres ou sac a dos, jouet libre).
    Vrai si un jouet a ete ramasse.
]]
function CarryService:PickupAimed(player: Player, direction: Vector3, range: number): boolean
    local best = CarryService:FindAimed(player, direction, range)
    if best == nil then
        return false
    end
    return tryPickup(player, best, true)
end

-- Jouet libre le mieux aligne avec la visee, a moins de range studs (sans le ramasser), ou nil.
function CarryService:FindAimed(player: Player, direction: Vector3, range: number): Instance?
    local root = aliveRoot(player)
    if root == nil or direction.Magnitude < 0.01 then
        return nil
    end
    local character = player.Character
    local head = if character then character:FindFirstChild("Head") else nil
    local origin = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 2, 0)
    local aim = direction.Unit
    local live = workspace:FindFirstChild("ToysLive")
    local best: Instance? = nil
    local bestDot = Abilities.SUCTION_MIN_DOT
    for _, toy in CollectionService:GetTagged(TOY_TAG) do
        if live and not toy:IsDescendantOf(live) then
            continue
        end
        if not toy:IsDescendantOf(workspace) or toy:GetAttribute("CarrierUserId") ~= nil then
            continue
        end
        local primary = Zone.PrimaryPart(toy)
        if primary == nil then
            continue
        end
        local center = if toy:IsA("Model") then toy:GetBoundingBox().Position else primary.Position
        local offset = center - origin
        local distance = offset.Magnitude
        if distance > 0.01 and distance <= range then
            local dot = offset.Unit:Dot(aim)
            if dot > bestDot then
                bestDot = dot
                best = toy
            end
        end
    end
    return best
end

-- Le joueur peut-il prendre ce jouet maintenant (mains libres, ou sac a dos pour un 2e jouet leger) ?
function CarryService:CanTake(player: Player, toy: Instance): boolean
    if toy:GetAttribute("CarrierUserId") ~= nil or toy:GetAttribute("AspireParUserId") ~= nil then
        return false
    end
    local filter = pickupFilter
    if filter and not filter(player, toy) then
        return false
    end
    local hands: Instance? = carried[player]
    if hands == nil then
        return true
    end
    return hasBackpack(player)
        and (backpack[player] :: Instance?) == nil
        and carriersFor(hands) <= 1
        and carriersFor(toy) <= 1
end

local function toyFromPart(part: Instance): Instance?
    local live = workspace:FindFirstChild("ToysLive")
    local current: Instance? = part
    while current and current ~= workspace do
        if CollectionService:HasTag(current, TOY_TAG) then
            return if live == nil or current:IsDescendantOf(live) then current else nil
        end
        current = current.Parent
    end
    return nil
end

local function centerOf(toy: Instance): Vector3
    if toy:IsA("Model") then
        return toy:GetBoundingBox().Position
    end
    local primary = Zone.PrimaryPart(toy)
    return if primary then primary.Position else Vector3.zero
end

local function headPosition(player: Player): Vector3?
    local root = aliveRoot(player)
    local character = player.Character
    local head = if character then character:FindFirstChild("Head") else nil
    if head and head:IsA("BasePart") then
        return head.Position
    end
    return if root then root.Position + Vector3.new(0, 2, 0) else nil
end

-- Rayon qui traverse les volumes invisibles (zones de jeu, cachettes) : seules les pieces visibles arretent le tir.
local function castVisible(origin: Vector3, vector: Vector3, ignore: { Instance }): RaycastResult?
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local skipped = table.clone(ignore)
    for _ = 1, 12 do
        params.FilterDescendantsInstances = skipped
        local hit = workspace:Raycast(origin, vector, params)
        if hit == nil then
            return nil
        end
        local part = hit.Instance
        if not part:IsA("BasePart") or part.Transparency < 0.95 then
            return hit
        end
        table.insert(skipped, part)
    end
    return nil
end

--[[
    Ventouse, tir vise : le point vise est donne par le rayon de la camera du joueur (origin, direction) ; le tir part
    de sa tete vers ce point, sur `range` studs. Rend le jouet touche (ou nil) et le point d'impact. Tolerance : un
    jouet libre dont le centre passe tout pres du trait, avant l'obstacle, compte comme touche.
]]
function CarryService:FindShot(
    player: Player,
    origin: Vector3?,
    direction: Vector3,
    range: number
): (Instance?, Vector3)
    local from = headPosition(player)
    if from == nil or direction.Magnitude < 0.01 or direction.Magnitude ~= direction.Magnitude then
        return nil, Vector3.zero
    end
    local ignore: { Instance } = {}
    if player.Character then
        table.insert(ignore, player.Character)
    end
    local hands: Instance? = carried[player]
    if hands then
        table.insert(ignore, hands)
    end
    local back: Instance? = backpack[player]
    if back then
        table.insert(ignore, back)
    end
    -- anti-triche : une origine de camera loin du joueur est ignoree (on vise depuis la tete)
    local cameraOrigin = if origin and (origin - from).Magnitude <= 60 then origin else from
    local aim = direction.Unit
    local reach = range + (cameraOrigin - from).Magnitude + 20
    local cameraHit = castVisible(cameraOrigin, aim * reach, ignore)
    local aimPoint = if cameraHit then cameraHit.Position else cameraOrigin + aim * reach
    local toward = aimPoint - from
    if toward.Magnitude < 0.1 then
        return nil, from
    end
    local shot = toward.Unit
    local hit = castVisible(from, shot * range, ignore)
    local impact = if hit then hit.Position else from + shot * range
    local direct = if hit then toyFromPart(hit.Instance) else nil
    if direct and direct:GetAttribute("CarrierUserId") == nil then
        return direct, centerOf(direct)
    end
    local blocked = (impact - from).Magnitude
    local best: Instance? = nil
    local bestAlong = math.huge
    local live = workspace:FindFirstChild("ToysLive")
    for _, toy in CollectionService:GetTagged(TOY_TAG) do
        if live and not toy:IsDescendantOf(live) then
            continue
        end
        if toy:GetAttribute("CarrierUserId") ~= nil or toy:GetAttribute("AspireParUserId") ~= nil then
            continue
        end
        local size = sizeOf(toy)
        local biggest = math.max(size.X, size.Y, size.Z)
        local relative = centerOf(toy) - from
        local along = relative:Dot(shot)
        if along <= 0 or along > math.min(range, blocked + biggest / 2) then
            continue
        end
        local offLine = (relative - shot * along).Magnitude
        if offLine <= Abilities.SUCTION_AIM_TOLERANCE + biggest / 3 and along < bestAlong then
            best = toy
            bestAlong = along
        end
    end
    if best then
        return best, centerOf(best)
    end
    return nil, impact
end

-- Ventouse visible : le modele DecorModels.SuctionCup, ou une petite ventouse en pieces si absent.
local CUP_SIZE = 1.6
local CUP_SPEED = 260
local CUP_COLOR = Color3.fromRGB(235, 70, 80)

local function makeCup(): (Model, BasePart)
    local decor = ServerStorage:FindFirstChild("DecorModels")
    local template = if decor then decor:FindFirstChild("SuctionCup") else nil
    local model: Model
    if template and template:IsA("Model") then
        model = template:Clone()
        local _, size = model:GetBoundingBox()
        model:ScaleTo(model:GetScale() * (CUP_SIZE / math.max(size.X, size.Y, size.Z, 0.1)))
    else
        model = Instance.new("Model")
        local cup = Instance.new("Part")
        cup.Name = "Cloche"
        cup.Shape = Enum.PartType.Cylinder
        cup.Size = Vector3.new(0.35, 1.4, 1.4)
        cup.Color = CUP_COLOR
        cup.Material = Enum.Material.SmoothPlastic
        cup.Parent = model
        local knob = Instance.new("Part")
        knob.Name = "Poignee"
        knob.Shape = Enum.PartType.Ball
        knob.Size = Vector3.new(0.6, 0.6, 0.6)
        knob.Color = CUP_COLOR
        knob.Material = Enum.Material.SmoothPlastic
        knob.CFrame = cup.CFrame * CFrame.new(-0.4, 0, 0)
        knob.Parent = model
        model.PrimaryPart = cup
    end
    model.Name = "VentouseTir"
    local primary: BasePart? = nil
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = false
            primary = primary or descendant
        end
    end
    return model, (model.PrimaryPart or primary) :: BasePart
end

-- Pose le centre de la boite du jouet sur cframe (rotation comprise).
local function placeCenter(toy: Instance, cframe: CFrame): ()
    if toy:IsA("Model") then
        local center = toy:GetBoundingBox()
        toy:PivotTo(cframe * center:ToObjectSpace(toy:GetPivot()))
    elseif toy:IsA("BasePart") then
        toy.CFrame = cframe
    end
end

--[[
    Animation de la ventouse (vue par tous) : la ventouse file vers le jouet au bout de son fil, se colle, puis le
    jouet revient en vol en arc vers le joueur, en tournant et en retrecissant a sa taille « portee ». A l'arrivee il
    est ramasse (memes regles que la prise a la main) ; si ce n'est plus possible, il retombe devant le joueur.
    onDone(ramasse) est appele a la fin.
]]
function CarryService:PullToy(player: Player, toy: Instance, onDone: (boolean) -> ()): ()
    local primary = Zone.PrimaryPart(toy)
    local from = headPosition(player)
    if primary == nil or from == nil then
        onDone(false)
        return
    end
    toy:SetAttribute("AspireParUserId", player.UserId)
    setPromptEnabled(toy, false)
    local parts = partsOf(toy)
    for _, part in parts do
        part.Anchored = true
        part.CanCollide = false
    end

    local cup, cupPart = makeCup()
    local cupAttachment = Instance.new("Attachment")
    cupAttachment.Name = "Fil"
    cupAttachment.Parent = cupPart
    local character = player.Character
    local head = if character then character:FindFirstChild("Head") else nil
    local anchorPart: BasePart? = if head and head:IsA("BasePart") then head else aliveRoot(player)
    local handAttachment = Instance.new("Attachment")
    handAttachment.Name = "FilVentouse"
    handAttachment.Parent = anchorPart
    local beam = Instance.new("Beam")
    beam.Name = "FilVentouse"
    beam.Attachment0 = handAttachment
    beam.Attachment1 = cupAttachment
    beam.Width0 = 0.16
    beam.Width1 = 0.16
    beam.FaceCamera = true
    beam.Segments = 12
    beam.Color = ColorSequence.new(CUP_COLOR)
    beam.LightEmission = 0.2
    beam.Parent = cupPart
    local start = centerOf(toy)
    cup:PivotTo(CFrame.lookAt(from, start))
    cup.Parent = workspace

    task.spawn(function()
        local distance = (start - from).Magnitude
        -- 1. la ventouse part vers le jouet
        local outTime = math.clamp(distance / CUP_SPEED, 0.12, 0.6)
        local began = os.clock()
        while os.clock() - began < outTime do
            local alpha = (os.clock() - began) / outTime
            local origin = headPosition(player) or from
            local position = origin:Lerp(start, alpha)
            if (start - position).Magnitude > 0.05 then
                cup:PivotTo(CFrame.lookAt(position, start))
            end
            RunService.Heartbeat:Wait()
        end

        -- 2. le jouet revient en arc, en tournant et en retrecissant jusqu'a sa taille portee
        local groundScale = if toy:IsA("Model") then toy:GetScale() else 1
        local endScale = groundScale
        if toy:IsA("Model") and toy:GetAttribute("GroundScale") == nil then
            local size = sizeOf(toy)
            local limit = if carriersFor(toy) > 1 then Tuning.CARRY_MAX_SIZE_HEAVY else Tuning.CARRY_MAX_SIZE
            local biggest = math.max(size.X, size.Y, size.Z)
            if biggest > limit then
                endScale = groundScale * limit / biggest
                toy:SetAttribute("GroundScale", groundScale)
            end
        end
        local startRotation = if toy:IsA("Model") then toy:GetPivot().Rotation else primary.CFrame.Rotation
        local backTime = math.clamp(distance / 110, 0.35, 1.1)
        local arc = math.clamp(distance * 0.25, 2, 30)
        began = os.clock()
        while os.clock() - began < backTime do
            if toy.Parent == nil or aliveRoot(player) == nil then
                break
            end
            local alpha = (os.clock() - began) / backTime
            local eased = alpha * alpha * (3 - 2 * alpha)
            local target = (headPosition(player) or from) + Vector3.new(0, 2.5, 0)
            local middle = start:Lerp(target, 0.5) + Vector3.new(0, arc, 0)
            local position = start:Lerp(middle, eased):Lerp(middle:Lerp(target, eased), eased)
            if toy:IsA("Model") and endScale ~= groundScale then
                toy:ScaleTo(groundScale + (endScale - groundScale) * eased)
            end
            local spin = CFrame.Angles(0, eased * math.pi * 2, math.sin(eased * math.pi) * 0.6)
            placeCenter(toy, CFrame.new(position) * startRotation * spin)
            local toward = target - position
            if toward.Magnitude > 0.05 then
                cup:PivotTo(CFrame.lookAt(position + toward.Unit * 0.8, position + toward.Unit * 2))
            end
            RunService.Heartbeat:Wait()
        end

        cup:Destroy()
        handAttachment:Destroy()
        toy:SetAttribute("AspireParUserId", nil)
        if toy.Parent == nil then
            onDone(false)
            return
        end
        local picked = tryPickup(player, toy, true)
        if not picked then
            -- plus possible (mains prises entre-temps, joueur mort) : le jouet retombe devant le joueur
            restoreScale(toy)
            setPromptEnabled(toy, true)
            local root = aliveRoot(player)
            local landing = if root then root.Position + root.CFrame.LookVector * 4 else start
            ToySpawnService:PlaceAt(toy, CFrame.new(landing.X, landing.Y - 2.5, landing.Z))
        end
        onDone(picked)
    end)
end

function CarryService:GetCarried(player: Player): Instance?
    return carried[player]
end

function CarryService:GetBackpack(player: Player): Instance?
    return backpack[player]
end

--[[
    Lache les jouets portes (mains et sac a dos). returnToSpawn = vrai : ils retournent a leur point d'origine
    (attrape par le geant, deconnexion). Sinon ils tombent la ou ils sont.
]]
function CarryService:Drop(player: Player, returnToSpawn: boolean): ()
    for _, released in { release(player), releaseBack(player) } do
        -- les nil ne sont pas stockes dans la table : chaque entree parcourue est un jouet
        local toy = released :: Instance
        if giveBackIfStolen(toy) then
            continue
        end
        setPromptEnabled(toy, true)
        if returnToSpawn then
            ToySpawnService:ReturnToSpawn(toy)
        else
            for _, part in partsOf(toy) do
                part.CanCollide = true
                part.Massless = false
            end
        end
    end
end

local function countHelpers(player: Player, root: BasePart): number
    local helpers = 0
    for _, other in Players:GetPlayers() do
        local otherToy: Instance? = carried[other]
        if other ~= player and otherToy == nil then
            local otherRoot = aliveRoot(other)
            if otherRoot and (otherRoot.Position - root.Position).Magnitude <= Tuning.HELPER_RADIUS then
                helpers += 1
            end
        end
    end
    return helpers
end

local function notifyFull(player: Player): ()
    local now = os.clock()
    local last: number? = lastFullNotice[player]
    if last and now - last < FULL_NOTICE_SECONDS then
        return
    end
    lastFullNotice[player] = now
    local chests, canBuy = BaseService:GetChestInfo(player)
    -- remote range dans une variable : une ligne qui commence par « ( » serait lue comme la suite de l'appel precedent
    local remote = Remotes.Get("ChestFull") :: RemoteEvent
    remote:FireClient(player, chests, Tuning.CHEST_CAPACITY, Tuning.CHEST_PRICE, canBuy)
end

-- Rangement appele avant le depot en coffre pour le jouet des mains : (player, toy, position) -> vrai si le jouet
-- est pris (il est alors detache, compte comme vole et detruit ici ; le jouet du sac passe dans les mains).
local depositHook: ((Player, Instance, Vector3) -> boolean)? = nil

function CarryService:SetDepositHook(hook: (Player, Instance, Vector3) -> boolean): ()
    depositHook = hook
end

-- Regle de prise supplementaire, verifiee au bouton « Voler » et par CanTake (ventouse) : (player, toy) -> vrai si permis.
function CarryService:SetPickupFilter(filter: (Player, Instance) -> boolean): ()
    pickupFilter = filter
end

local function checkCarriers(): ()
    local snapshot: { [Player]: Instance } = table.clone(carried)
    for player, toy in snapshot do
        local root, humanoid = aliveRoot(player)
        if root == nil or humanoid == nil then
            CarryService:Drop(player, true)
            continue
        end

        local toyId = toy:GetAttribute("ToyId")
        local mutationId = toy:GetAttribute("Mutation")
        -- Rangement prioritaire (tipi, TentService) : s'il prend le jouet, pas de depot en coffre en plus.
        local hook = depositHook
        if hook and typeof(toyId) == "string" then
            local ok, taken = pcall(hook, player, toy, root.Position)
            if ok and taken == true then
                release(player)
                ToySpawnService:OnTaken(toy)
                toy:Destroy()
                promoteBackpack(player)
                continue
            end
        end
        if typeof(toyId) == "string" then
            local mutation = if typeof(mutationId) == "string" then mutationId else nil
            local source = if toy:GetAttribute("StolenFromUserId") ~= nil then "stolen" else "room"
            local deposited, reason = BaseService:TryDeposit(player, toyId, mutation, root.Position, source)
            if deposited then
                release(player)
                ToySpawnService:OnTaken(toy)
                toy:Destroy()
                -- le jouet du sac a dos passe dans les mains et sera depose au controle suivant
                promoteBackpack(player)
                continue
            elseif reason == "full" then
                notifyFull(player)
            end
        end

        local needed = carriersFor(toy)
        local helpers = if needed > 1 then countHelpers(player, root) else 0
        humanoid.WalkSpeed = carrySpeed(player, needed, helpers >= needed - 1)
    end
end

function CarryService:Init(): () end

function CarryService:Start(): ()
    for _, toy in CollectionService:GetTagged(TOY_TAG) do
        setupPrompt(toy)
    end

    local toyAction = Remotes.Get("ToyAction") :: RemoteEvent
    toyAction.OnServerEvent:Connect(function(player: Player, action: any, direction: any)
        if action == "drop" then
            CarryService:PutDown(player)
        elseif action == "throw" and typeof(direction) == "Vector3" then
            CarryService:Throw(player, direction)
        end
    end)
    CollectionService:GetInstanceAddedSignal(TOY_TAG):Connect(setupPrompt)

    -- Sac a dos visible : pose ou retire selon la possession (attribut Owned_Backpack).
    local function refreshBackpackModel(player: Player): ()
        local character = player.Character
        if character == nil then
            return
        end
        local existing = character:FindFirstChild(BACKPACK_MODEL_NAME)
        local decor = ServerStorage:FindFirstChild("DecorModels")
        local template = if decor then decor:FindFirstChild("Backpack") else nil
        local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
        if not hasBackpack(player) or template == nil or not template:IsA("Model") then
            if existing then
                existing:Destroy()
            end
            return
        end
        if existing or torso == nil or not torso:IsA("BasePart") then
            return
        end
        local model = template:Clone()
        model.Name = BACKPACK_MODEL_NAME
        local _, size = model:GetBoundingBox()
        -- hauteur du sac = hauteur du torse
        model:ScaleTo(model:GetScale() * (torso.Size.Y / math.max(size.Y, 0.1)))
        local _, scaled = model:GetBoundingBox()
        local depth = math.min(scaled.X, scaled.Z)
        model:SetAttribute("Profondeur", depth)
        -- dos du torse = +Z local ; les modeles Tripo regardent vers -Z : demi-tour pour que la poche regarde
        -- vers l'arriere (a verifier en capture)
        local anchor = torso.CFrame * CFrame.new(0, 0, torso.Size.Z / 2 + depth / 2) * CFrame.Angles(0, math.pi, 0)
        local box = model:GetBoundingBox()
        model:PivotTo(anchor * box:ToObjectSpace(model:GetPivot()))
        for _, descendant in model:GetDescendants() do
            if descendant:IsA("BasePart") then
                descendant.Anchored = false
                descendant.CanCollide = false
                descendant.CanQuery = false
                descendant.CanTouch = false
                descendant.Massless = true
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = torso
                weld.Part1 = descendant
                weld.Parent = descendant
            end
        end
        model.Parent = character
    end

    local function onPlayer(player: Player): ()
        player.CharacterAdded:Connect(function(character: Model)
            local humanoid = character:WaitForChild("Humanoid", 5)
            if humanoid and humanoid:IsA("Humanoid") then
                humanoid.WalkSpeed = Tuning.WALK_SPEED
                humanoid.Died:Connect(function()
                    CarryService:Drop(player, true)
                end)
            end
            local _ = character:WaitForChild("UpperTorso", 3) or character:WaitForChild("Torso", 2)
            refreshBackpackModel(player)
        end)
        player:GetAttributeChangedSignal("Owned_Backpack"):Connect(function()
            refreshBackpackModel(player)
        end)
        if player.Character then
            task.spawn(refreshBackpackModel, player)
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        onPlayer(player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        CarryService:Drop(player, true)
        lastFullNotice[player] = nil
    end)

    local elapsed = 0
    RunService.Heartbeat:Connect(function(dt: number)
        elapsed += dt
        if elapsed >= CHECK_INTERVAL then
            elapsed = 0
            checkCarriers()
        end
    end)
end

return CarryService
