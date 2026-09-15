--!strict

--[[
    CarryController
    Portage vu par ce joueur :
    - pose « bras leves » sur les personnages qui portent un jouet (attribut CarriedToyId de leur joueur) :
      Transform des epaules ecrit a chaque image apres les animations. Les epaules de ce place sont des
      AnimationConstraint : tourner C0 ou Attachment0 ne tenait pas (l'animation compensait, teste en jeu). Le
      client proprietaire du personnage le simule, donc les autres joueurs voient aussi la pose ;
    - touches G (poser, sans bruit) et F (lancer devant le personnage, avec du bruit), et boutons tactiles
      « Poser » / « Lancer » sur mobile, actifs seulement quand on porte un jouet (remote ToyAction).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local DROP_ACTION = "PoserJouet"
local THROW_ACTION = "LancerJouet"
-- Demi-tour autour de X : le bras qui pend passe a la verticale vers le haut (R15 et R6).
local ARMS_UP = CFrame.Angles(math.pi, 0, 0)
local SHOULDERS =
    { "RightUpperArm/RightShoulder", "LeftUpperArm/LeftShoulder", "Torso/Right Shoulder", "Torso/Left Shoulder" }

local CarryController = {}

local player = Players.LocalPlayer
local hint: TextLabel? = nil

local function poseArms(): ()
    for _, other in Players:GetPlayers() do
        local character = other.Character
        if character == nil or other:GetAttribute("CarriedToyId") == nil then
            continue
        end
        for _, path in SHOULDERS do
            local slash = string.find(path, "/", 1, true) or 0
            local limb = character:FindFirstChild(string.sub(path, 1, slash - 1))
            local joint = if limb then limb:FindFirstChild(string.sub(path, slash + 1)) else nil
            if joint and (joint:IsA("AnimationConstraint") or joint:IsA("Motor6D")) then
                joint.Transform = ARMS_UP
            end
        end
    end
end

local function send(action: string): ()
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    if root == nil or not root:IsA("BasePart") then
        return
    end
    Sfx.play(if action == "throw" then "throw" else "drop")
    local remote = Remotes.Get("ToyAction") :: RemoteEvent
    remote:FireServer(action, root.CFrame.LookVector)
end

local function onAction(name: string, state: Enum.UserInputState): Enum.ContextActionResult
    if state ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Pass
    end
    send(if name == THROW_ACTION then "throw" else "drop")
    return Enum.ContextActionResult.Sink
end

local function refreshBindings(): ()
    local carrying = player:GetAttribute("CarriedToyId") ~= nil
    if carrying then
        ContextActionService:BindAction(DROP_ACTION, onAction, true, Enum.KeyCode.G, Enum.KeyCode.ButtonX)
        ContextActionService:BindAction(THROW_ACTION, onAction, true, Enum.KeyCode.F, Enum.KeyCode.ButtonR2)
        ContextActionService:SetTitle(DROP_ACTION, "Poser")
        ContextActionService:SetTitle(THROW_ACTION, "Lancer")
    else
        ContextActionService:UnbindAction(DROP_ACTION)
        ContextActionService:UnbindAction(THROW_ACTION)
    end
    if hint then
        hint.Visible = carrying
    end
end

function CarryController:Init(): () end

function CarryController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "Portage"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 6
    gui.Parent = player:WaitForChild("PlayerGui")
    local holder = Instance.new("Frame")
    holder.Name = "Aide"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(420, 40)
    holder.Position = UDim2.new(0.5, 0, 1, -118)
    holder.AnchorPoint = Vector2.new(0.5, 1)
    holder.Parent = gui
    Theme.fit(holder, Theme.HUD_FACTOR)
    hint = Theme.text(
        holder,
        "Touches",
        "G : poser     F : lancer",
        UDim2.fromScale(1, 1),
        UDim2.fromScale(0.5, 0.5),
        Theme.WHITE,
        Vector2.new(0.5, 0.5)
    )

    player:GetAttributeChangedSignal("CarriedToyId"):Connect(refreshBindings)
    refreshBindings()
    -- apres les animations, avant la simulation physique
    RunService.PreSimulation:Connect(poseArms)
end

return CarryController
