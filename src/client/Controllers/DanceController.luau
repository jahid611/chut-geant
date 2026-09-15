--!strict

--[[
    DanceController
    Danses achetees en boutique (Catalog, slot "dance").

    - Touche B, bouton L1 de manette ou bouton tactile « Danse » : lance la danse choisie dans la boutique
      (attribut local ChosenDance) ou, a defaut, la premiere danse possedee. Remote Dance ; le serveur verifie la
      possession et pose l'attribut Dancing du joueur pendant 4 s.
    - La danse s'arrete (Dance « stop ») des que le joueur local bouge, saute ou ramasse un jouet.
    - Animation procedurale pour tous les personnages dont le joueur a l'attribut Dancing : les articulations
      de ce place sont des AnimationConstraint, on ecrit leur Transform a chaque PreSimulation, apres les
      animations (meme methode que les bras leves du portage, CarryController).
      Joie : bras qui s'agitent en l'air et petits sauts. Robot : poses saccadees des bras et de la tete.
      Toupie : le corps tourne sur lui-meme, bras tendus.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DANCE_ACTION = "Danser"

local DanceController = {}

local player = Players.LocalPlayer
local stopSent = false

local function ownedDances(): { string }
    local list: { string } = {}
    for _, item in Catalog.All() do
        if item.slot == "dance" and player:GetAttribute("Owned_" .. item.id) ~= nil then
            table.insert(list, item.id)
        end
    end
    return list
end

local function chosenDance(): string?
    local chosen = player:GetAttribute("ChosenDance")
    if typeof(chosen) == "string" and player:GetAttribute("Owned_" .. chosen) ~= nil then
        return chosen
    end
    return ownedDances()[1]
end

local function onDance(_: string, state: Enum.UserInputState): Enum.ContextActionResult
    if state ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Pass
    end
    local dance = chosenDance()
    if dance == nil or player:GetAttribute("CarriedToyId") ~= nil then
        return Enum.ContextActionResult.Pass
    end
    stopSent = false
    local remote = Remotes.Get("Dance") :: RemoteEvent
    remote:FireServer(dance)
    return Enum.ContextActionResult.Sink
end

local function refreshBinding(): ()
    if #ownedDances() > 0 then
        ContextActionService:BindAction(DANCE_ACTION, onDance, true, Enum.KeyCode.B, Enum.KeyCode.ButtonL1)
        ContextActionService:SetTitle(DANCE_ACTION, "Danse")
    else
        ContextActionService:UnbindAction(DANCE_ACTION)
    end
end

local function joint(character: Model, limb: string, name: string): Instance?
    local part = character:FindFirstChild(limb)
    local found = if part then part:FindFirstChild(name) else nil
    if found and (found:IsA("AnimationConstraint") or found:IsA("Motor6D")) then
        return found
    end
    return nil
end

local function setTransform(target: Instance?, frame: CFrame): ()
    if target == nil then
        return
    end
    if target:IsA("AnimationConstraint") or target:IsA("Motor6D") then
        local constraint: any = target
        constraint.Transform = frame
    end
end

local function animate(character: Model, dance: string, t: number): ()
    local rightArm = joint(character, "RightUpperArm", "RightShoulder")
    local leftArm = joint(character, "LeftUpperArm", "LeftShoulder")
    local neck = joint(character, "Head", "Neck")
    local root = joint(character, "LowerTorso", "Root")
    if dance == "DanceJoy" then
        local wave = math.sin(t * 9)
        setTransform(rightArm, CFrame.Angles(math.pi + wave * 0.35, 0, 0.35 + math.sin(t * 11) * 0.3))
        setTransform(leftArm, CFrame.Angles(math.pi - wave * 0.35, 0, -0.35 - math.sin(t * 11) * 0.3))
        setTransform(neck, CFrame.Angles(0, math.sin(t * 4) * 0.35, 0))
        setTransform(root, CFrame.new(0, math.abs(math.sin(t * 7)) * 0.7, 0))
    elseif dance == "DanceRobot" then
        -- une pose fixe toutes les 1/3 s : mouvements saccades
        local step = math.floor(t * 3) % 4
        local arm = if step % 2 == 0 then math.pi / 2 else math.pi
        setTransform(rightArm, CFrame.Angles(arm, 0, 0))
        setTransform(leftArm, CFrame.Angles(if step % 2 == 0 then math.pi else math.pi / 2, 0, 0))
        setTransform(neck, CFrame.Angles(0, if step < 2 then 0.5 else -0.5, 0))
        setTransform(root, CFrame.new(0, if step == 3 then -0.25 else 0, 0))
    elseif dance == "DanceSpin" then
        setTransform(rightArm, CFrame.Angles(0, 0, math.pi / 2))
        setTransform(leftArm, CFrame.Angles(0, 0, -math.pi / 2))
        setTransform(root, CFrame.Angles(0, (t * 10) % (math.pi * 2), 0))
    end
end

local function poseDancers(): ()
    local t = os.clock()
    for _, other in Players:GetPlayers() do
        local dance = other:GetAttribute("Dancing")
        local character = other.Character
        if typeof(dance) ~= "string" or character == nil or other:GetAttribute("CarriedToyId") ~= nil then
            continue
        end
        if other == player then
            -- le joueur local bouge, saute ou porte : fin de la danse
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and (humanoid.MoveDirection.Magnitude > 0.1 or humanoid.Jump) then
                if not stopSent then
                    stopSent = true
                    local remote = Remotes.Get("Dance") :: RemoteEvent
                    remote:FireServer("stop")
                end
                continue
            end
        end
        animate(character, dance, t)
    end
end

function DanceController:Init(): () end

function DanceController:Start(): ()
    player.AttributeChanged:Connect(function(attribute: string)
        if string.sub(attribute, 1, 11) == "Owned_Dance" then
            refreshBinding()
        end
    end)
    refreshBinding()
    RunService.PreSimulation:Connect(poseDancers)
end

return DanceController
