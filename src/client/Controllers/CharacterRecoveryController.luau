--!strict

--[[
    CharacterRecoveryController
    Filet de securite : le personnage restait parfois couche au sol, impossible a relever (capture utilisateur du 15/09),
    apres une propulsion (capture du bebe ou de maman, coup d'arme) ou un rebond de trampoline interrompu.

    Si le personnage est a terre (PlatformStand, ou etat FallingDown, Ragdoll, Physics ou PlatformStanding) plus de
    RECOVER_AFTER secondes au-dela de son etourdissement prevu (attribut local EtourdiJusqua pose par EventController et
    TrampolineController), il est remis debout : fin de PlatformStand, rotation annulee, redresse sur place, GettingUp.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RECOVER_AFTER = 1.2
local CHECK_EVERY = 0.25

local DOWN_STATES: { [Enum.HumanoidStateType]: boolean } = {
    [Enum.HumanoidStateType.FallingDown] = true,
    [Enum.HumanoidStateType.Ragdoll] = true,
    [Enum.HumanoidStateType.Physics] = true,
    [Enum.HumanoidStateType.PlatformStanding] = true,
}

local CharacterRecoveryController = {}

function CharacterRecoveryController:Init(): () end

function CharacterRecoveryController:Start(): ()
    local player = Players.LocalPlayer
    local downSince: number? = nil
    local elapsed = 0
    RunService.Heartbeat:Connect(function(dt: number)
        elapsed += dt
        if elapsed < CHECK_EVERY then
            return
        end
        elapsed = 0
        local character = player.Character
        local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
        local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
        if character == nil or humanoid == nil or root == nil or not root:IsA("BasePart") or humanoid.Health <= 0 then
            downSince = nil
            return
        end
        if not (humanoid.PlatformStand or DOWN_STATES[humanoid:GetState()]) then
            downSince = nil
            return
        end
        local now = os.clock()
        local stunned = character:GetAttribute("EtourdiJusqua")
        if typeof(stunned) == "number" and stunned > now then
            downSince = nil
            return
        end
        if downSince == nil then
            downSince = now
            return
        end
        if now - (downSince :: number) < RECOVER_AFTER then
            return
        end
        downSince = nil
        humanoid.PlatformStand = false
        root.AssemblyAngularVelocity = Vector3.zero
        local look = root.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        local forward = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
        local standing = root.Position + Vector3.new(0, 1.5, 0)
        root.CFrame = CFrame.lookAt(standing, standing + forward)
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)
end

return CharacterRecoveryController
