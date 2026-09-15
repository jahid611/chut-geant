--!strict

--[[
    TrampolineController
    Rebond de trampoline (remote Bounce : depart, arrivee, sommet) : le personnage suit une vraie cloche jusqu'au
    matelas du berceau. Donner une simple vitesse ne suffisait pas : en l'air le Humanoid freine la vitesse
    horizontale et le joueur retombait devant le lit (teste en jeu le 16/09). Pendant le vol le personnage est en
    PlatformStand, deplace image par image sur la parabole, avec une petite pirouette ; il se releve a l'arrivee.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local TrampolineController = {}

local flying = false

-- Temps de vol et vitesse verticale d'une cloche qui passe par apex (gravite du workspace).
local function arc(from: Vector3, to: Vector3, apex: number): (number, number)
    local g = workspace.Gravity
    local vy = math.sqrt(2 * g * math.max(apex - from.Y, 1))
    local seconds = vy / g + math.sqrt(2 * math.max(apex - to.Y, 0) / g)
    return seconds, vy
end

function TrampolineController:Init(): () end

function TrampolineController:Start(): ()
    local player = Players.LocalPlayer
    local remote = Remotes.Get("Bounce") :: RemoteEvent
    remote.OnClientEvent:Connect(function(from: any, to: any, apex: any)
        if flying or typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or typeof(apex) ~= "number" then
            return
        end
        local character = player.Character
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        if root == nil or not root:IsA("BasePart") or humanoid == nil then
            return
        end
        flying = true
        local seconds, vy = arc(from, to, apex)
        local g = workspace.Gravity
        local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
        local facing = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
        humanoid.PlatformStand = true
        local started = os.clock()
        local connection: RBXScriptConnection? = nil
        connection = RunService.Heartbeat:Connect(function()
            local t = math.min(os.clock() - started, seconds)
            local alpha = t / seconds
            local position = from + flat * alpha + Vector3.new(0, vy * t - g * t * t / 2, 0)
            -- pirouette avant pendant la montee et la descente
            local spin = CFrame.Angles(-alpha * math.pi * 2, 0, 0)
            root.CFrame = CFrame.lookAt(position, position + facing) * spin
            root.AssemblyLinearVelocity = Vector3.zero
            if t >= seconds then
                if connection then
                    connection:Disconnect()
                end
                root.CFrame = CFrame.lookAt(to + Vector3.new(0, 3, 0), to + Vector3.new(0, 3, 0) + facing)
                humanoid.PlatformStand = false
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                flying = false
            end
        end)
    end)
end

return TrampolineController
