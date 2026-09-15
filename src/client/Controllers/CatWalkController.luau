--!strict

-- Le serveur décide des déplacements et contacts. Cette copie locale rejoue
-- uniquement les poses fabriquées dans Blender, sans solveur de patte.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Cycle = require(ReplicatedStorage.Shared.CatWalkCycle)
local CAT_NAME = "ChatDeLaMaison"
local MAX_DISTANCE = 500
local FOLLOW_RATE = 18
local TURN_RATE = 7

type BoneData = {
    bone: Bone,
    vertical: Vector3,
    poses: { CFrame },
}
type State = {
    source: Model,
    visual: Model,
    hidden: { [BasePart]: number },
    addedConnection: RBXScriptConnection?,
    bones: { [string]: BoneData },
    rays: RaycastParams,
    position: Vector3,
    velocity: Vector3,
    rotation: CFrame,
    lastTarget: Vector3,
    height: number,
    length: number,
    bottom: number,
    groundOffset: number,
    phase: number,
    amount: number,
}

local CatWalkController = {}
local state: State? = nil
local renderConnection: RBXScriptConnection? = nil
local destroyConnection: RBXScriptConnection? = nil
local retryAt = 0

local function alpha(rate: number, dt: number): number
    return 1 - math.exp(-rate * dt)
end

local function cleanup(): ()
    local current = state
    state = nil
    if current then
        if current.addedConnection then
            current.addedConnection:Disconnect()
        end
        for part, transparency in current.hidden do
            if part.Parent then
                part.LocalTransparencyModifier = transparency
            end
        end
        current.visual:Destroy()
    end
end

local function create(source: Model): State?
    if not source.Archivable then
        return nil
    end
    local visual = source:Clone()
    visual.Name = "ChatMarcheLocal"
    for _, descendant in visual:GetDescendants() do
        if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") then
            descendant:Destroy()
        elseif descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
            descendant.LocalTransparencyModifier = 0
        elseif descendant:IsA("Bone") then
            descendant.Transform = CFrame.identity
        end
    end
    local pivot = source:GetPivot()
    local box, size = source:GetBoundingBox()
    local bones: { [string]: BoneData } = {}
    for _, name in Cycle.bones do
        local found = visual:FindFirstChild(name, true)
        if found == nil or not found:IsA("Bone") then
            visual:Destroy()
            return nil -- Réplication du modèle incomplète : réessayer plus tard.
        end
        local rest = pivot:ToObjectSpace(found.WorldCFrame)
        local poses: { CFrame } = {}
        for _, frame in Cycle.frames do
            local rotations: { [string]: Vector3 } = frame.rotations
            local vector = rotations[name]
            -- Le vecteur exporté est axe * angle dans (droite, haut, AVANT).
            -- L'avant Roblox vaut -Z. Changer de base AVANT l'exponentielle.
            local localAxis = rest:VectorToObjectSpace(Vector3.new(vector.X, vector.Y, -vector.Z))
            local angle = localAxis.Magnitude
            table.insert(
                poses,
                if angle > 0.000001 then CFrame.fromAxisAngle(localAxis / angle, angle) else CFrame.identity
            )
        end
        bones[name] = { bone = found, vertical = rest:VectorToObjectSpace(Vector3.yAxis), poses = poses }
    end
    local rays = RaycastParams.new()
    rays.FilterType = Enum.RaycastFilterType.Exclude
    rays.FilterDescendantsInstances = { source, visual }
    rays.RespectCanCollide = true
    rays.IgnoreWater = true
    local current: State = {
        source = source,
        visual = visual,
        hidden = {},
        addedConnection = nil,
        bones = bones,
        rays = rays,
        position = pivot.Position,
        velocity = Vector3.zero,
        rotation = pivot.Rotation,
        lastTarget = pivot.Position,
        height = math.max(size.Y, 1),
        length = math.max(size.X, size.Z, 1),
        bottom = pivot:PointToObjectSpace(box.Position - Vector3.yAxis * size.Y * 0.5).Y,
        groundOffset = 0,
        phase = 0,
        amount = 0,
    }
    visual.Parent = Workspace
    local function hide(descendant: Instance): ()
        if descendant:IsA("BasePart") and current.hidden[descendant] == nil then
            current.hidden[descendant] = descendant.LocalTransparencyModifier
            descendant.LocalTransparencyModifier = 1
        end
    end
    for _, descendant in source:GetDescendants() do
        hide(descendant)
    end
    current.addedConnection = source.DescendantAdded:Connect(hide)
    return current
end

local function update(current: State, target: CFrame, dt: number): ()
    local previous = current.position
    -- Solution analytique du ressort critique conservée pour les positions
    -- serveur reçues à 20 Hz. La phase suit la distance de CETTE copie lissée.
    local displacement = previous - target.Position
    local impulse = current.velocity + displacement * FOLLOW_RATE
    local decay = math.exp(-FOLLOW_RATE * dt)
    current.position = target.Position + (displacement + impulse * dt) * decay
    current.velocity = (current.velocity - impulse * FOLLOW_RATE * dt) * decay
    current.rotation = current.rotation:Lerp(target.Rotation, alpha(TURN_RATE, dt))
    local delta = current.position - previous
    local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
    current.phase = (current.phase + distance / (Cycle.strideHeight * current.height)) % 1
    local speed = if dt > 0 then distance / dt else 0
    local wanted = if speed > 0.8 then 1 else 0
    current.amount += (wanted - current.amount) * alpha(8, dt)
    if wanted == 0 and current.amount < 0.0001 then
        current.amount = 0
    end

    -- Translation du corps entier pour le tapis (3,3 à 4,3 studs) et le parquet.
    -- Aucun déplacement d'articulation : un cycle sans IK conserve ses longueurs.
    -- Le bord du tapis reste un changement de plan, à contrôler en jeu.
    local bottomY = current.position.Y + current.bottom
    local range = current.height * 0.12
    local origin = Vector3.new(current.position.X, bottomY + range, current.position.Z)
    local hit = Workspace:Raycast(origin, -Vector3.yAxis * range * 2, current.rays)
    local offset = 0
    if hit and hit.Normal.Y > 0.85 then
        offset = math.clamp(hit.Position.Y - bottomY, -range, range)
    end
    current.groundOffset += (offset - current.groundOffset) * alpha(14, dt)
    current.visual:PivotTo(CFrame.new(current.position + Vector3.yAxis * current.groundOffset) * current.rotation)

    local sample = current.phase * Cycle.frameCount
    local first = math.floor(sample) + 1
    local second = first % Cycle.frameCount + 1
    local blend = sample % 1
    local rootY = Cycle.frames[first].rootY + (Cycle.frames[second].rootY - Cycle.frames[first].rootY) * blend
    for name, entry in current.bones do
        local rotation = entry.poses[first]:Lerp(entry.poses[second], blend)
        local rest = CFrame.identity
        local transform = rest:Lerp(rotation, current.amount)
        if name == "Racine" then
            transform = CFrame.new(entry.vertical * (rootY * current.height * current.amount)) * transform
        end
        entry.bone.Transform = transform
    end
end

function CatWalkController:Init(): () end

function CatWalkController:Stop(): ()
    if renderConnection then
        renderConnection:Disconnect()
        renderConnection = nil
    end
    if destroyConnection then
        destroyConnection:Disconnect()
        destroyConnection = nil
    end
    cleanup()
    retryAt = 0
end

function CatWalkController:Start(): ()
    if renderConnection then
        return
    end
    destroyConnection = script.Destroying:Connect(function()
        self:Stop()
    end)
    renderConnection = RunService.RenderStepped:Connect(function(frameDt: number)
        -- Le ralenti agit sur le suivi, jamais une seconde fois sur la distance.
        local slow = Workspace:GetAttribute("ChatRalenti")
        local factor = if typeof(slow) == "number" and slow >= 0 and slow < math.huge then slow else 1
        local dt = math.clamp(frameDt * factor, 0, 0.1)
        local found = Workspace:FindFirstChild(CAT_NAME)
        local camera = Workspace.CurrentCamera
        if found == nil or not found:IsA("Model") or camera == nil then
            cleanup()
            return
        end
        local target = found:GetPivot()
        if (camera.CFrame.Position - target.Position).Magnitude > MAX_DISTANCE then
            cleanup()
            retryAt = os.clock() + 0.25
            return
        end
        local current = state
        if
            current
            and (
                current.source ~= found
                or current.visual.Parent == nil
                or (target.Position - current.lastTarget).Magnitude > current.length
                or frameDt > 0.25
            )
        then
            cleanup()
            current = nil
        end
        if current == nil then
            if os.clock() < retryAt then
                return
            end
            current = create(found)
            state = current
            retryAt = os.clock() + 0.5
        end
        if current then
            current.lastTarget = target.Position
            update(current, target, dt)
        end
    end)
end

return CatWalkController
