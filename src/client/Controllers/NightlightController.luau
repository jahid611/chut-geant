--!strict

--[[
    NightlightController
    Message pour tout le serveur quand quelqu'un remonte la veilleuse (NightlightService : attributs
    NightlightWinder et NightlightWinds de workspace).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local NightlightController = {}

local player = Players.LocalPlayer

function NightlightController:Init(): () end

function NightlightController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "Veilleuse"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 7
    gui.Parent = player:WaitForChild("PlayerGui")

    Workspace:GetAttributeChangedSignal("NightlightWinds"):Connect(function()
        local winder = Workspace:GetAttribute("NightlightWinder")
        local name = if typeof(winder) == "string" then winder else "Quelqu'un"
        Sfx.play("click")
        local text = if name == player.DisplayName
            then "Tu as remonté la veilleuse : le bébé se calme !"
            else name .. " a remonté la veilleuse : le bébé se calme !"
        Theme.toast(gui, text, Theme.BLUE)
    end)
end

return NightlightController
