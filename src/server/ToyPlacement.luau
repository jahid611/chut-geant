--!strict

-- Géométrie serveur commune aux apparitions et aux secours physiques.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Zone = require(ReplicatedStorage.Shared.Zone)

local ToyPlacement = {}
local random = Random.new()

function ToyPlacement.Bounds(toy: Instance): (CFrame, Vector3)
    if toy:IsA("Model") then
        return toy:GetBoundingBox()
    end
    local primary = Zone.PrimaryPart(toy)
    assert(primary, "Jouet sans pièce physique")
    return primary.CFrame, primary.Size
end

function ToyPlacement.MoveCenter(toy: Instance, target: CFrame): ()
    if toy:IsA("Model") then
        local center = toy:GetBoundingBox()
        toy:PivotTo(target * center:ToObjectSpace(toy:GetPivot()))
    elseif toy:IsA("BasePart") then
        toy.CFrame = target
    end
end

function ToyPlacement.RoomAt(position: Vector3): Instance?
    for _, entry in { { "GiantRoom", "Chambre" }, { "KitchenZone", "Cuisine" } } do
        for _, zone in CollectionService:GetTagged(entry[1]) do
            if zone:IsA("BasePart") and zone:IsDescendantOf(workspace) and Zone.Contains(zone, position) then
                return workspace:FindFirstChild(entry[2])
            end
        end
    end
    return nil
end

function ToyPlacement.Params(toy: Instance): RaycastParams
    local ignore: { Instance } = { toy }
    local live = workspace:FindFirstChild("ToysLive")
    if live then
        table.insert(ignore, live)
    end
    for _, player in Players:GetPlayers() do
        if player.Character then
            table.insert(ignore, player.Character)
        end
    end
    local params = RaycastParams.new()
    params.RespectCanCollide = true
    params.FilterDescendantsInstances = ignore
    return params
end

local function surfaces(room: Instance): { Instance }
    local result: { Instance } = {}
    local structure = room:FindFirstChild("Structure")
    for _, name in { "Sol", "Tapis" } do
        local surface = if structure then structure:FindFirstChild(name) else nil
        if surface then
            table.insert(result, surface)
        end
    end
    local rug = room:FindFirstChild("TapisLune", true)
    if rug then
        table.insert(result, rug)
    end
    return result
end

function ToyPlacement.SupportParams(room: Instance): RaycastParams
    local params = RaycastParams.new()
    params.RespectCanCollide = true
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = surfaces(room)
    return params
end

-- Mesure indépendante du centre du jouet, y compris lorsqu'il a déjà traversé le parquet.
function ToyPlacement.FloorAt(room: Instance, position: Vector3): Vector3?
    local structure = room:FindFirstChild("Structure")
    local floor = if structure then structure:FindFirstChild("Sol") else nil
    if floor == nil or not floor:IsA("BasePart") then
        return nil
    end
    local hit = workspace:Raycast(
        Vector3.new(position.X, floor.Position.Y + 340, position.Z),
        Vector3.new(0, -360, 0),
        ToyPlacement.SupportParams(room)
    )
    return if hit and hit.Normal.Y > 0.5 then hit.Position else nil
end

-- Rayon depuis le haut de la pièce : un meuble, même bas, invalide le candidat.
-- Les cinq sondes couvrent l'emprise du jouet ; les volumes de sécurité sont élargis de son rayon.
function ToyPlacement.Ground(room: Instance, position: Vector3, toy: Instance, spacing: boolean?): Vector3?
    local structure = room:FindFirstChild("Structure")
    local floor = if structure then structure:FindFirstChild("Sol") else nil
    if floor == nil or not floor:IsA("BasePart") then
        return nil
    end
    local _, size = ToyPlacement.Bounds(toy)
    local radius = Vector2.new(size.X, size.Z).Magnitude / 2
    local params = ToyPlacement.Params(toy)
    local allowed = surfaces(room)
    local ground: Vector3? = nil
    for _, offset in
        {
            Vector3.zero,
            Vector3.new(radius, 0, 0),
            Vector3.new(-radius, 0, 0),
            Vector3.new(0, 0, radius),
            Vector3.new(0, 0, -radius),
        }
    do
        local probe = position + offset
        local hit =
            workspace:Raycast(Vector3.new(probe.X, floor.Position.Y + 340, probe.Z), Vector3.new(0, -360, 0), params)
        if hit == nil or hit.Normal.Y < 0.95 then
            return nil
        end
        local valid = false
        for _, surface in allowed do
            if hit.Instance == surface or hit.Instance:IsDescendantOf(surface) then
                valid = true
                break
            end
        end
        if not valid or ToyPlacement.RoomAt(hit.Position + Vector3.new(0, 3, 0)) ~= room then
            return nil
        end
        if ground and math.abs(hit.Position.Y - ground.Y) > 1.5 then
            return nil
        end
        ground = Vector3.new(position.X, math.max(if ground then ground.Y else -math.huge, hit.Position.Y), position.Z)
    end
    if ground == nil then
        return nil
    end
    for _, tag in { "Base", "HideZone", "BaseDoor", "InteriorZone", "KitchenDoor" } do
        for _, zone in CollectionService:GetTagged(tag) do
            if zone:IsA("BasePart") and zone:IsDescendantOf(workspace) then
                local p = zone.CFrame:PointToObjectSpace(ground + Vector3.new(0, size.Y / 2, 0))
                local half = zone.Size / 2 + Vector3.new(radius + 3, size.Y / 2 + 3, radius + 3)
                if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
                    return nil
                end
            end
        end
    end
    local overlap = OverlapParams.new()
    overlap.RespectCanCollide = true
    -- Le rayon a mesuré la vraie surface ; la boîte du tapis MeshPart peut dépasser celle-ci.
    local overlapIgnore = table.clone(params.FilterDescendantsInstances)
    for _, surface in allowed do
        table.insert(overlapIgnore, surface)
    end
    overlap.FilterDescendantsInstances = overlapIgnore
    local box = CFrame.new(ground + Vector3.new(0, size.Y / 2 + 0.15, 0))
    if #workspace:GetPartBoundsInBox(box, Vector3.new(radius * 2, size.Y, radius * 2), overlap) > 0 then
        return nil
    end
    if spacing then
        for _, other in CollectionService:GetTagged("Toy") do
            if other ~= toy and other:IsDescendantOf(workspace) then
                local center, otherSize = ToyPlacement.Bounds(other)
                local delta = center.Position - ground
                if
                    math.abs(delta.Y) < 60
                    and Vector2.new(delta.X, delta.Z).Magnitude
                        < radius + Vector2.new(otherSize.X, otherSize.Z).Magnitude / 2 + 3
                then
                    return nil
                end
            end
        end
    end
    return ground
end

function ToyPlacement.RandomGround(point: BasePart, toy: Instance): (Vector3?, Instance?)
    local kitchen = workspace:FindFirstChild("Cuisine")
    local room = if kitchen and point:IsDescendantOf(kitchen) then kitchen else workspace:FindFirstChild("Chambre")
    if room == nil then
        return nil, nil
    end
    local welcome = point:GetAttribute("PointAccueil") == true
    local anchors: { BasePart } = {}
    if welcome then
        table.insert(anchors, point)
    else
        for _, other in CollectionService:GetTagged("ToySpawn") do
            if
                other:IsA("BasePart")
                and other:IsDescendantOf(room)
                and other:GetAttribute("PointAccueil") ~= true
                and other:GetAttribute("Rarity") == point:GetAttribute("Rarity")
            then
                table.insert(anchors, other)
            end
        end
    end
    if #anchors == 0 then
        table.insert(anchors, point)
    end
    local radius = if welcome then 6 elseif room == kitchen then 18 else 32
    -- L'ancien point légendaire est sur le matelas. Sa zone doit atteindre le parquet
    -- autour du berceau, tout en restant centrée sur ce repère de rareté.
    local structure = room:FindFirstChild("Structure")
    local floor = if structure then structure:FindFirstChild("Sol") else nil
    if
        not welcome
        and floor
        and floor:IsA("BasePart")
        and point.Position.Y > floor.Position.Y + floor.Size.Y / 2 + 8
    then
        local hit = workspace:Raycast(
            Vector3.new(point.Position.X, floor.Position.Y + 340, point.Position.Z),
            Vector3.new(0, -360, 0),
            ToyPlacement.Params(toy)
        )
        local obstacle = if hit then hit.Instance:FindFirstAncestorWhichIsA("Model") else nil
        if obstacle and obstacle ~= room and obstacle:IsDescendantOf(room) then
            local _, obstacleSize = obstacle:GetBoundingBox()
            radius = math.max(radius, Vector2.new(obstacleSize.X, obstacleSize.Z).Magnitude / 2 + 32)
        else
            radius = math.max(radius, 96)
        end
    end
    for _ = 1, 48 do
        local anchor = anchors[random:NextInteger(1, #anchors)]
        local angle = random:NextNumber(0, math.pi * 2)
        local distance = radius * math.sqrt(random:NextNumber())
        local candidate = anchor.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
        local ground = ToyPlacement.Ground(room, candidate, toy, true)
        if ground then
            return ground, room
        end
    end
    return nil, room
end

return ToyPlacement
