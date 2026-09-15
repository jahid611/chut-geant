--!strict

--[[
    WeaponService
    Armes rigolotes achetees en tetines (Shared/CatalogWeapons, stats Shared/Weapons), serveur autoritaire.

    - L'arme equipee (attribut Equipped_weapon, ShopService) est donnee en outil dans le sac du joueur a chaque
      apparition et quand il en change : clone de ServerStorage.WeaponModels.<id>, scripts supprimes ; un Model ou
      une piece seule devient un Tool dont la plus grosse piece est la poignee (Handle).
    - Pas d'arme en main pendant le portage d'un jouet : l'outil est range.
    - Remote WeaponSwing (direction) : cadence, arme vraiment en main, portee, cone devant le joueur, ligne de vue.
      Cible touchee : lache son jouet (selon l'arme), propulsee (remote Caught, reason "hit"), bruit a la jauge.
      Protegee : dans sa propre base, sous Cape d'ombre, ou Doudou bouclier (consomme).
    - Remote WeaponHit vers tous les clients pour le son et l'etincelle.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Zone = require(Shared:WaitForChild("Zone"))

local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CarryService = require(script.Parent:WaitForChild("CarryService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))

-- Marge de reseau : un coup legerement en avance ou un peu hors de portee reste accepte.
local COOLDOWN_TOLERANCE = 0.85
local RANGE_TOLERANCE = 2

local WeaponService = {}

local lastSwing: { [Player]: number } = {}

local function aliveRoot(player: Player): (BasePart?, Humanoid?)
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

--[[
    Prise en main (Tool.Grip = repere de la main exprime dans le repere de la poignee) : la batte etait tenue a la
    verticale au-dessus de la tete (capture du 15/09). Boite de toute l'arme dans le repere de la poignee, grand axe
    = longueur de l'arme ; la main tient le bout le plus fin (a 12 % de la longueur), l'arme part vers l'avant de la
    main (-Z), inclinee vers le haut de gripTilt degres. Reglages par arme : Shared/Weapons (gripTilt, gripRoll,
    gripFlip).
]]
local DEFAULT_GRIP_TILT = 20
local GRIP_AXES: { [string]: Vector3 } = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }

local function computeGrip(handle: BasePart, parts: { BasePart }, weapon: Weapons.Weapon?): CFrame
    local minV = Vector3.new(math.huge, math.huge, math.huge)
    local maxV = -minV
    local points: { Vector3 } = {}
    for _, part in parts do
        local half = part.Size / 2
        for _, sx in { -1, 1 } do
            for _, sy in { -1, 1 } do
                for _, sz in { -1, 1 } do
                    local world = part.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
                    local point = handle.CFrame:PointToObjectSpace(world)
                    table.insert(points, point)
                    minV = minV:Min(point)
                    maxV = maxV:Max(point)
                end
            end
        end
    end
    local tilt = if weapon and weapon.gripTilt then weapon.gripTilt else DEFAULT_GRIP_TILT
    local roll = if weapon and weapon.gripRoll then weapon.gripRoll else 0
    -- Reglage explicite par arme (Shared/Weapons : gripAxis, gripEnd...) : le calcul automatique se trompait de bout
    -- sur les armes d'une seule piece (tapette tenue par la tete, 15/09).
    local namedAxis = if weapon and weapon.gripAxis then GRIP_AXES[weapon.gripAxis] else nil
    if weapon and namedAxis then
        local endSign = if weapon.gripEnd and weapon.gripEnd > 0 then 1 else -1
        local lowT, highT = minV:Dot(namedAxis), maxV:Dot(namedAxis)
        local span = math.max(highT - lowT, 0.1)
        local at = weapon.gripAt or 0.12
        local middle = (minV + maxV) / 2
        local t = if endSign < 0 then lowT + span * at else highT - span * at
        local position = middle - namedAxis * middle:Dot(namedAxis) + namedAxis * t
        position += weapon.gripOffset or Vector3.zero
        local towardHead = namedAxis * -endSign
        local upAxis = weapon.gripUp or (if weapon.gripAxis == "Y" then Vector3.zAxis else Vector3.yAxis)
        return CFrame.lookAt(position, position + towardHead, upAxis)
            * CFrame.Angles(math.rad(-tilt), 0, math.rad(roll))
    end
    local extent = maxV - minV
    local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
    local lengths = { extent.X, extent.Y, extent.Z }
    local long = 1
    for i = 2, 3 do
        if lengths[i] > lengths[long] then
            long = i
        end
    end
    local axis = axes[long]
    local length = math.max(lengths[long], 0.1)
    local low, high = minV:Dot(axis), maxV:Dot(axis)
    -- epaisseur d'un bout : etendue des points proches de ce bout dans les deux autres axes
    local function spread(atLow: boolean): number
        local sMin = Vector3.new(math.huge, math.huge, math.huge)
        local sMax = -sMin
        local count = 0
        for _, point in points do
            local t = point:Dot(axis)
            local near = if atLow then t <= low + length * 0.2 else t >= high - length * 0.2
            if near then
                local flat = point - axis * t
                sMin = sMin:Min(flat)
                sMax = sMax:Max(flat)
                count += 1
            end
        end
        return if count > 0 then (sMax - sMin).Magnitude else math.huge
    end
    local gripAtLow = spread(true) <= spread(false)
    if weapon and weapon.gripFlip then
        gripAtLow = not gripAtLow
    end
    local center = (minV + maxV) / 2
    local endT = if gripAtLow then low + length * 0.12 else high - length * 0.12
    local gripPos = center - axis * center:Dot(axis) + axis * endT
    local forward = if gripAtLow then axis else -axis
    local upHint = if long == 2 then Vector3.zAxis else Vector3.yAxis
    return CFrame.lookAt(gripPos, gripPos + forward, upHint) * CFrame.Angles(math.rad(-tilt), 0, math.rad(roll))
end

-- Outil pret a donner, ou nil si le modele de l'arme n'est pas dans ServerStorage.WeaponModels.
local function buildTool(id: string): Tool?
    local folder = ServerStorage:FindFirstChild("WeaponModels")
    local template = if folder then folder:FindFirstChild(id) else nil
    if template == nil then
        return nil
    end
    local tool: Tool
    if template:IsA("Tool") then
        tool = template:Clone()
    else
        tool = Instance.new("Tool")
        local copy = template:Clone()
        if copy:IsA("BasePart") then
            copy.Parent = tool
        else
            for _, child in copy:GetChildren() do
                child.Parent = tool
            end
            copy:Destroy()
        end
    end
    for _, descendant in tool:GetDescendants() do
        if descendant:IsA("LuaSourceContainer") then
            descendant:Destroy()
        end
    end
    local parts: { BasePart } = {}
    for _, descendant in tool:GetDescendants() do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end
    if #parts == 0 then
        tool:Destroy()
        return nil
    end
    local handle: BasePart? = nil
    for _, part in parts do
        if part.Name == "Handle" and part.Parent == tool then
            handle = part
        end
    end
    if handle == nil then
        local biggest = parts[1]
        for _, part in parts do
            if part.Size.Magnitude > biggest.Size.Magnitude then
                biggest = part
            end
        end
        biggest.Name = "Handle"
        biggest.Parent = tool
        handle = biggest
    end
    local grip = handle :: BasePart
    for _, part in parts do
        part.Anchored = false
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Massless = true
        if part ~= grip then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = grip
            weld.Part1 = part
            weld.Parent = part
        end
    end
    tool.Grip = computeGrip(grip, parts, Weapons.Get(id))
    local item = Catalog.Get(id)
    tool.Name = if item then item.name else id
    tool.RequiresHandle = true
    tool.CanBeDropped = false
    tool:SetAttribute(Weapons.TOOL_ATTRIBUTE, id)
    return tool
end

-- Retire les armes du sac et des mains du joueur.
local function removeWeapons(player: Player): ()
    local containers: { Instance } = {}
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        table.insert(containers, backpack)
    end
    if player.Character then
        table.insert(containers, player.Character)
    end
    for _, container in containers do
        for _, child in container:GetChildren() do
            if child:IsA("Tool") and child:GetAttribute(Weapons.TOOL_ATTRIBUTE) ~= nil then
                child:Destroy()
            end
        end
    end
end

-- Donne l'arme equipee (si possedee et si son modele existe).
local function giveWeapon(player: Player): ()
    removeWeapons(player)
    local id = player:GetAttribute("Equipped_weapon")
    if typeof(id) ~= "string" or Weapons.Get(id) == nil or not ShopService:Owns(player, id) then
        return
    end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack == nil then
        return
    end
    local tool = buildTool(id)
    if tool then
        tool.Parent = backpack
    end
end

-- Arme en main : l'outil de l'arme equipee dans le personnage, sinon nil.
local function heldWeapon(player: Player): Weapons.Weapon?
    local character = player.Character
    local id = player:GetAttribute("Equipped_weapon")
    if character == nil or typeof(id) ~= "string" then
        return nil
    end
    for _, child in character:GetChildren() do
        if child:IsA("Tool") and child:GetAttribute(Weapons.TOOL_ATTRIBUTE) == id then
            return Weapons.Get(id)
        end
    end
    return nil
end

-- Rien de solide entre l'attaquant et la cible (murs, meubles) ?
local function clearLine(from: Vector3, to: Vector3): boolean
    local ignore: { Instance } = {}
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
    local hit = workspace:Raycast(from, to - from, params)
    return hit == nil or not hit.Instance.CanCollide or hit.Instance.Transparency >= 0.95
end

local function isProtected(target: Player, position: Vector3): boolean
    local base = BaseService:GetBase(target)
    if base and Zone.Contains(base, position) then
        return true
    end
    if Abilities.IsActive(target, "ShadowCape") then
        return true
    end
    return false
end

function WeaponService:Swing(player: Player, direction: Vector3?): ()
    local weapon = heldWeapon(player)
    local root = aliveRoot(player)
    if weapon == nil or root == nil or CarryService:GetCarried(player) ~= nil then
        return
    end
    local now = os.clock()
    local last: number? = lastSwing[player]
    if last and now - last < weapon.cooldown * COOLDOWN_TOLERANCE then
        return
    end
    lastSwing[player] = now

    local flat = if direction then Vector3.new(direction.X, 0, direction.Z) else Vector3.zero
    local forward = if flat.Magnitude > 0.1
        then flat.Unit
        else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
    local cosCone = math.cos(math.rad(weapon.cone))

    type Hit = { player: Player, root: BasePart, distance: number }
    local hits: { Hit } = {}
    for _, other in Players:GetPlayers() do
        if other == player then
            continue
        end
        local targetRoot = aliveRoot(other)
        if targetRoot == nil then
            continue
        end
        local offset = targetRoot.Position - root.Position
        local distance = offset.Magnitude
        local flatOffset = Vector3.new(offset.X, 0, offset.Z)
        if distance > weapon.range + RANGE_TOLERANCE or math.abs(offset.Y) > weapon.range then
            continue
        end
        -- tout pres, l'angle n'a plus de sens : on accepte
        local inCone = flatOffset.Magnitude < 2 or flatOffset.Unit:Dot(forward) >= cosCone
        if inCone and clearLine(root.Position, targetRoot.Position) then
            table.insert(hits, { player = other, root = targetRoot, distance = distance })
        end
    end
    if #hits == 0 then
        return
    end
    table.sort(hits, function(a, b)
        return a.distance < b.distance
    end)
    if not weapon.multi then
        hits = { hits[1] }
    end

    local caught = Remotes.Get("Caught") :: RemoteEvent
    local hitRemote = Remotes.Get("WeaponHit") :: RemoteEvent
    for _, hit in hits do
        local target = hit.player
        if isProtected(target, hit.root.Position) then
            continue
        end
        -- Doudou bouclier : le coup est absorbe (et le bouclier consomme)
        if Abilities.ConsumeShield(target) then
            continue
        end
        local away = Vector3.new(hit.root.Position.X - root.Position.X, 0, hit.root.Position.Z - root.Position.Z)
        local push = if away.Magnitude > 0.1 then away.Unit else forward
        local launch = push * weapon.launch + Vector3.new(0, weapon.up, 0)
        if weapon.dropsToy then
            CarryService:Drop(target, false, launch)
        end
        caught:FireClient(target, "hit", launch)
        NoiseService:Add(weapon.noise)
        hitRemote:FireAllClients(weapon.id, player.UserId, target.UserId, hit.root.Position)
    end
end

function WeaponService:Init(): () end

function WeaponService:Start(): ()
    local swing = Remotes.Get("WeaponSwing") :: RemoteEvent
    swing.OnServerEvent:Connect(function(player: Player, direction: any)
        WeaponService:Swing(player, if typeof(direction) == "Vector3" then direction else nil)
    end)

    local function onPlayer(player: Player): ()
        player.CharacterAdded:Connect(function(character: Model)
            character:WaitForChild("HumanoidRootPart", 5)
            giveWeapon(player)
            -- pas d'arme en main pendant le portage : un outil sorti est remis dans le sac
            character.ChildAdded:Connect(function(child: Instance)
                if
                    child:IsA("Tool")
                    and child:GetAttribute(Weapons.TOOL_ATTRIBUTE) ~= nil
                    and player:GetAttribute("CarriedToyId") ~= nil
                then
                    task.defer(function()
                        local backpack = player:FindFirstChildOfClass("Backpack")
                        if backpack and child.Parent == character then
                            child.Parent = backpack
                        end
                    end)
                end
            end)
        end)
        player:GetAttributeChangedSignal("Equipped_weapon"):Connect(function()
            giveWeapon(player)
        end)
        player:GetAttributeChangedSignal("CarriedToyId"):Connect(function()
            if player:GetAttribute("CarriedToyId") ~= nil then
                local _, humanoid = aliveRoot(player)
                if humanoid then
                    humanoid:UnequipTools()
                end
            end
        end)
        if player.Character then
            task.spawn(giveWeapon, player)
        end
    end
    Players.PlayerAdded:Connect(onPlayer)
    for _, player in Players:GetPlayers() do
        onPlayer(player)
    end
    Players.PlayerRemoving:Connect(function(player: Player)
        lastSwing[player] = nil
    end)
    -- un modele d'arme qui arrive pendant la partie : les joueurs qui l'ont equipee le recoivent
    local function watch(folder: Instance): ()
        folder.ChildAdded:Connect(function()
            for _, player in Players:GetPlayers() do
                giveWeapon(player)
            end
        end)
    end
    local existing = ServerStorage:FindFirstChild("WeaponModels")
    if existing then
        watch(existing)
    end
    ServerStorage.ChildAdded:Connect(function(child: Instance)
        if child.Name == "WeaponModels" then
            watch(child)
        end
    end)
end

return WeaponService
