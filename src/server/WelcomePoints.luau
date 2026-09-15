--!strict

-- Points de jeu invisibles, créés uniquement à l'exécution. Aucune recette de scène à rejouer.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Tuning"))
local Zone = require(Shared:WaitForChild("Zone"))

local WelcomePoints = {}

local function taggedParts(tag: string): { BasePart }
    local parts: { BasePart } = {}
    for _, instance in CollectionService:GetTagged(tag) do
        if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
            table.insert(parts, instance)
        end
    end
    return parts
end

local function inRoom(position: Vector3): boolean
    for _, room in taggedParts("GiantRoom") do
        if Zone.Contains(room, position) then
            return true
        end
    end
    return false
end

-- Les recettes déplacent les volumes Base à y = -900. L'intérieur doit contenir exactement une base et une
-- sortie vers la chambre. On utilise sa Destination réelle, jamais un nom ou le voisin le plus proche.
function WelcomePoints.Origin(base: BasePart): CFrame?
    if not base:IsDescendantOf(workspace) or not CollectionService:HasTag(base, "Base") then
        return nil
    end
    if inRoom(base.Position) then
        return base.CFrame * CFrame.new(0, -base.Size.Y / 2 + 3, 0)
    end
    local interior: BasePart? = nil
    for _, zone in taggedParts("InteriorZone") do
        if Zone.Contains(zone, base.Position) then
            if interior then
                return nil
            end
            interior = zone
        end
    end
    if interior == nil then
        return nil
    end
    for _, other in taggedParts("Base") do
        if other ~= base and Zone.Contains(interior, other.Position) then
            return nil
        end
    end
    local origin: CFrame? = nil
    for _, door in taggedParts("BaseDoor") do
        local destination = door:GetAttribute("Destination")
        if
            Zone.Contains(interior, door.Position)
            and typeof(destination) == "CFrame"
            and inRoom(destination.Position)
        then
            if origin then
                return nil
            end
            origin = destination
        end
    end
    return origin
end

export type Point = { part: BasePart, base: BasePart }

function WelcomePoints.Build(parent: Instance): { Point }
    local result: { Point } = {}
    local chamber = workspace:FindFirstChild("Chambre")
    local structure = if chamber then chamber:FindFirstChild("Structure") else nil
    local floor = if structure then structure:FindFirstChild("Sol") else nil
    if floor == nil or not floor:IsA("BasePart") then
        warn("[ToySpawnService] points d'accueil : sol de la chambre introuvable")
        return result
    end
    local rug = if chamber then chamber:FindFirstChild("TapisLune", true) else nil
    local oldRug = if structure then structure:FindFirstChild("Tapis") else nil
    local params = RaycastParams.new()
    params.RespectCanCollide = true
    params.FilterDescendantsInstances = { parent }
    local blocked: { BasePart } = {}
    for _, tag in { "Base", "HideZone", "BaseDoor" } do
        for _, part in taggedParts(tag) do
            table.insert(blocked, part)
        end
    end
    local taken = taggedParts("ToySpawn")
    local bases = taggedParts("Base")
    table.sort(bases, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)
    for _, base in bases do
        local origin = WelcomePoints.Origin(base)
        if origin == nil then
            warn("[ToySpawnService] sortie d'accueil absente ou ambiguë : " .. base:GetFullName())
            continue
        end
        local forward = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z)
        if forward.Magnitude < 0.9 then
            continue
        end
        forward = forward.Unit
        local right = Vector3.new(-forward.Z, 0, forward.X)
        local count = 0
        -- Candidats déterministes en éventail côté chambre, tous à 35–55 studs de la sortie.
        for _, distance in { Tuning.WELCOME_MIN_DISTANCE, 45, Tuning.WELCOME_MAX_DISTANCE } do
            for _, degrees in { -20, 20, -40, 40, -60, 60, 0 } do
                if count >= Tuning.WELCOME_POINTS_PER_BASE then
                    break
                end
                local angle = math.rad(degrees)
                local candidate = origin.Position + (forward * math.cos(angle) + right * math.sin(angle)) * distance
                local ground = workspace:Raycast(
                    Vector3.new(candidate.X, floor.Position.Y + 340, candidate.Z),
                    Vector3.new(0, -360, 0),
                    params
                )
                -- Seuls le parquet et le tapis connus conviennent : un meuble bas est aussi refusé.
                local onFloor = ground and (ground.Instance == floor or ground.Instance == oldRug)
                local onRug = ground and rug and ground.Instance:IsDescendantOf(rug)
                if
                    ground == nil
                    or not (onFloor or onRug)
                    or ground.Normal.Y < 0.95
                    or not inRoom(ground.Position + Vector3.new(0, 3, 0))
                then
                    continue
                end
                local free = true
                for _, zone in blocked do
                    local p = zone.CFrame:PointToObjectSpace(ground.Position + Vector3.new(0, 3, 0))
                    local half = zone.Size / 2 + Vector3.new(6, 6, 6)
                    if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
                        free = false
                        break
                    end
                end
                for _, point in taken do
                    local offset = point.Position - ground.Position
                    if Vector3.new(offset.X, 0, offset.Z).Magnitude < Tuning.WELCOME_POINT_SPACING then
                        free = false
                        break
                    end
                end
                if not free then
                    continue
                end
                local point: BasePart = Instance.new("Part")
                point.Name = "PointAccueil"
                point.Size = Vector3.new(4, 1, 4)
                point.CFrame = CFrame.new(ground.Position + Vector3.new(0, 0.5, 0))
                point.Anchored = true
                point.Locked = true
                point.Transparency = 1
                point.CanCollide = false
                point.CanQuery = false
                point.CanTouch = false
                point:SetAttribute("Rarity", "Common")
                point:SetAttribute("PointAccueil", true)
                point.Parent = parent
                -- Le service pose le tag après avoir enregistré l'association exacte à la base.
                table.insert(result, { part = point, base = base })
                table.insert(taken, point)
                count += 1
            end
        end
        if count < Tuning.WELCOME_POINTS_PER_BASE then
            warn(
                string.format(
                    "[ToySpawnService] %s : %d/%d points d'accueil sûrs",
                    base.Name,
                    count,
                    Tuning.WELCOME_POINTS_PER_BASE
                )
            )
        end
    end
    return result
end

return WelcomePoints
