--!strict

--[[
    BaseAlertController
    Alerte d'intrusion (BaseAlertService : attributs AlerteIntrus et AlerteIntrusN du joueur) : message rouge et
    alarme discrete quand un autre joueur entre dans sa base pendant qu'on est ailleurs.
]]

local Players = game:GetService("Players")

local Sfx = require(script.Parent.Parent.Ui.Sfx)
local Theme = require(script.Parent.Parent.Ui.Theme)

local BaseAlertController = {}

local player = Players.LocalPlayer

function BaseAlertController:Init(): () end

function BaseAlertController:Start(): ()
    local gui = Instance.new("ScreenGui")
    gui.Name = "AlerteIntrus"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 8
    gui.Parent = player:WaitForChild("PlayerGui")

    player:GetAttributeChangedSignal("AlerteIntrusN"):Connect(function()
        local intruder = player:GetAttribute("AlerteIntrus")
        local name = if typeof(intruder) == "string" and intruder ~= "" then intruder else "Quelqu'un"
        Sfx.play("alarm")
        Theme.toast(gui, name .. " est dans ta base : reviens défendre tes coffres !", Theme.RED)
    end)
end

return BaseAlertController
