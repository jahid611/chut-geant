--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Placement = require(script.Parent.ToyPlacement)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Zone = require(ReplicatedStorage.Shared.Zone)

local ToyPhysics = {}
local MAX_ACTIVE = 40
local MAX_SECONDS = 6
local IGNORE_CHARACTER_SECONDS = 0.5
type State = {
    primary: BasePart,
    parts: { BasePart },
    room: Instance,
    safe: Vector3,
    origin: Vector3,
    floorY: number,
    ignoredCollisions: { NoCollisionConstraint },
    rotation: CFrame,
    began: number,
    still: number,
    previous: CFrame,
    done: (() -> ())?,
}
local active: { [Instance]: State } = {}
local count = 0

local function restoreCollisions(state: State): ()
    for _, constraint in state.ignoredCollisions do
        constraint:Destroy()
    end
    table.clear(state.ignoredCollisions)
end

function ToyPhysics.Parts(toy: Instance): { BasePart }
    local parts: { BasePart } = {}
    if toy:IsA("BasePart") then
        table.insert(parts, toy)
    end
    for _, part in toy:GetDescendants() do
        if part:IsA("BasePart") then
            table.insert(parts, part)
        end
    end
    return parts
end

function ToyPhysics.Cancel(toy: Instance): ()
    local state = active[toy]
    if state then
        active[toy] = nil
        count -= 1
        restoreCollisions(state)
        toy:SetAttribute("PhysiqueActive", nil)
        if state.done then
            state.done()
        end
    end
end

function ToyPhysics.HasCapacity(): boolean
    -- Réserve pour les captures (mains et sac) et les lancers pendant les apparitions.
    return count < MAX_ACTIVE - 16
end

local function freeze(state: State): ()
    state.primary.AssemblyLinearVelocity = Vector3.zero
    state.primary.AssemblyAngularVelocity = Vector3.zero
    for _, part in state.parts do
        part.Anchored = true
    end
end

local function recover(toy: Instance, state: State): ()
    -- L'orientation droite rend la demi-hauteur exacte, même après une vrille.
    Placement.MoveCenter(toy, CFrame.new(state.safe) * state.rotation)
    local _, size = Placement.Bounds(toy)
    Placement.MoveCenter(toy, CFrame.new(state.safe + Vector3.new(0, size.Y / 2 + 0.02, 0)) * state.rotation)
    freeze(state)
    ToyPhysics.Cancel(toy)
end

function ToyPhysics.Launch(
    toy: Instance,
    center: CFrame,
    velocity: Vector3,
    room: Instance,
    safe: Vector3,
    done: (() -> ())?,
    ignoredCharacter: Model?
): boolean
    ToyPhysics.Cancel(toy)
    local primary = Zone.PrimaryPart(toy)
    if primary == nil then
        return false
    end
    -- Cas exceptionnel de captures simultanées : libérer le plus ancien au sol de secours,
    -- jamais en l'ancrant au milieu de sa trajectoire. Le budget reste strictement borné.
    if count >= MAX_ACTIVE then
        local oldestToy: Instance? = nil
        local oldest: State? = nil
        for other, state in active do
            if oldest == nil or state.began < oldest.began then
                oldestToy, oldest = other, state
            end
        end
        if oldestToy and oldest then
            recover(oldestToy, oldest)
        end
    end
    local parts = ToyPhysics.Parts(toy)
    local welded = toy:GetAttribute("InnerWelded") == true
    for _, part in parts do
        part.Anchored = true
        part.CanCollide = true
        part.CanTouch = true
        part.Massless = false
        if part ~= primary and not welded then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = primary
            weld.Part1 = part
            weld.Parent = part
        end
    end
    toy:SetAttribute("InnerWelded", true)
    Placement.MoveCenter(toy, center)
    -- Les soudures et exclusions existent avant le désancrage. Le sol reste toujours solide.
    local ignoredCollisions: { NoCollisionConstraint } = {}
    if ignoredCharacter then
        for _, bodyPart in ignoredCharacter:GetDescendants() do
            if bodyPart:IsA("BasePart") then
                for _, part in parts do
                    local constraint = Instance.new("NoCollisionConstraint")
                    constraint.Part0 = part
                    constraint.Part1 = bodyPart
                    constraint.Parent = part
                    table.insert(ignoredCollisions, constraint)
                end
            end
        end
    end
    for _, part in parts do
        part.Anchored = false
    end
    primary:SetNetworkOwner(nil)
    primary.AssemblyLinearVelocity = velocity
    primary.AssemblyAngularVelocity = Vector3.zero
    local _, yaw = center:ToOrientation()
    local floor = Placement.FloorAt(room, center.Position)
    active[toy] = {
        primary = primary,
        parts = parts,
        room = room,
        safe = safe,
        origin = center.Position,
        floorY = if floor then floor.Y else safe.Y,
        ignoredCollisions = ignoredCollisions,
        rotation = CFrame.Angles(0, yaw, 0),
        began = os.clock(),
        still = 0,
        previous = center,
        done = done,
    }
    count += 1
    toy:SetAttribute("PhysiqueActive", true)
    return true
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt: number)
    elapsed += dt
    if elapsed < 0.1 then
        return
    end
    local step = math.min(elapsed, 0.2)
    elapsed = 0
    for toy, state in active do
        if
            not toy:IsDescendantOf(workspace)
            or toy:GetAttribute("CarrierUserId") ~= nil
            or toy:GetAttribute("AspireParUserId") ~= nil
        then
            ToyPhysics.Cancel(toy)
            continue
        end
        local age = os.clock() - state.began
        if age >= IGNORE_CHARACTER_SECONDS then
            restoreCollisions(state)
        end
        -- Roblox déplace et fait rebondir l'assemblage. Aucun PivotTo ni réécriture de vitesse en vol.
        local center, size = Placement.Bounds(toy)
        local vertical = math.abs(center.RightVector.Y) * size.X
            + math.abs(center.UpVector.Y) * size.Y
            + math.abs(center.LookVector.Y) * size.Z
        local bottom = center.Position.Y - vertical / 2
        local floor = Placement.FloorAt(state.room, center.Position)
        local floorY = if floor then floor.Y else state.floorY
        local inRoom = Placement.RoomAt(center.Position) == state.room
        -- Vérifier avant de déplacer le secours : une chute ne doit jamais abaisser le sol de référence.
        if
            not inRoom
            or bottom < floorY - 0.3
            or (center.Position - state.origin).Magnitude > Tuning.TOY_PHYSICS_MAX_DISTANCE
            or age >= MAX_SECONDS
        then
            recover(toy, state)
            continue
        end
        local ground = Placement.Ground(state.room, center.Position, toy)
        if ground and bottom >= ground.Y then
            state.safe = ground
        end
        -- Un objet lent au sommet de son arc n'est pas au repos : il faut aussi un appui réel.
        local supported = workspace:Raycast(
            center.Position,
            Vector3.new(0, -vertical / 2 - 0.3, 0),
            Placement.SupportParams(state.room)
        ) ~= nil
        local speed = state.primary.AssemblyLinearVelocity.Magnitude
        local spin = state.primary.AssemblyAngularVelocity.Magnitude
        local moved = (center.Position - state.previous.Position).Magnitude
        if ground and supported and speed < 0.6 and spin < 0.4 and moved < 0.1 then
            state.still += step
        else
            state.still = 0
        end
        state.previous = center
        if state.still >= 0.5 then
            if bottom < floorY then
                recover(toy, state)
            else
                freeze(state)
                ToyPhysics.Cancel(toy)
            end
        end
    end
end)

return ToyPhysics
