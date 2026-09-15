--!strict

--[[
    SfxController
    Sons des actions du joueur qui ne passent pas par un bouton (Ui/Sfx pour la liste des sons) :
    - attrape (remote Caught) : boing comique + whoosh ;
    - ramasser un jouet : attribut CarriedToyId qui passe de rien a un jouet ;
    - entrer / sortir de sa base : remote BaseTransition, puis on regarde ou le joueur arrive (les interieurs des
      bases sont tres bas, y < -400) ;
    - jouet depose dans un coffre : attribut Count d'un coffre du joueur qui augmente
      (workspace.BaseChests.Base_<UserId>) ;
    - pleine lune (remote MoonEvent, phase "start") : hurlement de loup.
    Lancer et poser : CarryController ; achats : Ui/Shop ; roue : Ui/Menus/Gifts ; clics : Ui/Theme.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Sfx = require(script.Parent.Parent.Ui.Sfx)

local INTERIOR_BELOW_Y = -400

local SfxController = {}

local player = Players.LocalPlayer

local function rootY(): number?
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
    return if root and root:IsA("BasePart") then root.Position.Y else nil
end

-- Ecoute les coffres du joueur : chaque hausse de Count = un jouet depose.
local function watchChest(chest: Instance): ()
    local count = chest:GetAttribute("Count")
    local last: number = if typeof(count) == "number" then count else 0
    chest:GetAttributeChangedSignal("Count"):Connect(function()
        local value = chest:GetAttribute("Count")
        if typeof(value) == "number" then
            if value > last then
                Sfx.play("deposit")
            end
            last = value
        end
    end)
end

function SfxController:Init(): () end

function SfxController:Start(): ()
    local caught = Remotes.Get("Caught") :: RemoteEvent
    caught.OnClientEvent:Connect(function()
        Sfx.play("caught")
        Sfx.play("caughtWhoosh")
    end)

    local carried: any = player:GetAttribute("CarriedToyId")
    player:GetAttributeChangedSignal("CarriedToyId"):Connect(function()
        local now = player:GetAttribute("CarriedToyId")
        if carried == nil and now ~= nil then
            Sfx.play("pickup")
        end
        carried = now
    end)

    local transition = Remotes.Get("BaseTransition") :: RemoteEvent
    transition.OnClientEvent:Connect(function(seconds: any)
        local before = rootY()
        local wait = if typeof(seconds) == "number" then seconds else 0.35
        task.delay(wait + 0.3, function()
            local after = rootY()
            if before == nil or after == nil then
                return
            end
            local wasInside = before < INTERIOR_BELOW_Y
            local isInside = after < INTERIOR_BELOW_Y
            if isInside and not wasInside then
                Sfx.play("baseEnter")
            elseif wasInside and not isInside then
                Sfx.play("baseExit")
            else
                Sfx.play(if isInside then "baseEnter" else "baseExit")
            end
        end)
    end)

    local moon = Remotes.Get("MoonEvent") :: RemoteEvent
    moon.OnClientEvent:Connect(function(phase: any)
        if phase == "start" then
            Sfx.play("howl")
        end
    end)

    task.spawn(function()
        local root = Workspace:WaitForChild("BaseChests", 60)
        if root == nil then
            return
        end
        local folder = root:WaitForChild("Base_" .. player.UserId, 60)
        if folder == nil then
            return
        end
        for _, chest in folder:GetChildren() do
            watchChest(chest)
        end
        folder.ChildAdded:Connect(function(chest: Instance)
            task.wait()
            watchChest(chest)
        end)
    end)
end

return SfxController
